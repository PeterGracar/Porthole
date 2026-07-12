import Foundation
import Security

final class HelperService: NSObject, NSXPCListenerDelegate {
    private let stateQueue = DispatchQueue(label: "io.github.petergracar.Porthole.helper.state")
    private var currentProcess: Process?

    // MARK: - NSXPCListenerDelegate

    func listener(_ listener: NSXPCListener, shouldAcceptNewConnection newConnection: NSXPCConnection) -> Bool {
        guard let requirement = Self.clientRequirement() else {
            NSLog("PortholeHelper: cannot determine a code signing requirement; rejecting connection")
            return false
        }
        newConnection.setCodeSigningRequirement(requirement)
        newConnection.exportedInterface = NSXPCInterface(with: PortHelperProtocol.self)
        newConnection.exportedObject = HelperAPI(service: self, connection: newConnection)
        newConnection.remoteObjectInterface = NSXPCInterface(with: PortHelperClientProtocol.self)
        newConnection.resume()
        return true
    }

    /// Only accept connections from the Porthole app signed by the same team as
    /// this helper. Falls back to an identifier-only requirement for unsigned
    /// debug builds.
    private static func clientRequirement() -> String? {
        if let team = selfTeamIdentifier() {
            return "anchor apple generic and identifier \"io.github.petergracar.Porthole\" and certificate leaf[subject.OU] = \"\(team)\""
        }
        #if DEBUG
        NSLog("PortholeHelper: no team identifier (ad-hoc build?); using identifier-only requirement")
        return "identifier \"io.github.petergracar.Porthole\""
        #else
        return nil
        #endif
    }

    private static func selfTeamIdentifier() -> String? {
        var codeRef: SecCode?
        guard SecCodeCopySelf(SecCSFlags(), &codeRef) == errSecSuccess, let code = codeRef else { return nil }
        var staticRef: SecStaticCode?
        guard SecCodeCopyStaticCode(code, SecCSFlags(), &staticRef) == errSecSuccess,
              let staticCode = staticRef else { return nil }
        var infoRef: CFDictionary?
        guard SecCodeCopySigningInformation(staticCode, SecCSFlags(rawValue: kSecCSSigningInformation), &infoRef) == errSecSuccess,
              let info = infoRef as? [String: Any] else { return nil }
        return info[kSecCodeInfoTeamIdentifier as String] as? String
    }

    // MARK: - Running port

    /// Runs /opt/local/bin/port with a fixed environment, streaming output to
    /// the client. Single-flight: MacPorts holds a global registry lock, so a
    /// second concurrent operation is rejected outright.
    func launch(arguments: [String], client: PortHelperClientProtocol?, reply: @escaping (Int32, String?) -> Void) {
        stateQueue.async {
            guard self.currentProcess == nil else {
                reply(-1, "Another operation is already in progress.")
                return
            }

            let process = Process()
            process.executableURL = URL(fileURLWithPath: kPortExecutablePath)
            process.arguments = arguments
            process.environment = [
                "PATH": "/opt/local/bin:/opt/local/sbin:/usr/bin:/bin:/usr/sbin:/sbin",
                "HOME": "/var/root",
            ]
            process.standardInput = FileHandle.nullDevice
            let stdout = Pipe()
            let stderr = Pipe()
            process.standardOutput = stdout
            process.standardError = stderr

            let pipesDrained = DispatchGroup()
            for (pipe, isStderr) in [(stdout, false), (stderr, true)] {
                pipesDrained.enter()
                pipe.fileHandleForReading.readabilityHandler = { handle in
                    let data = handle.availableData
                    if data.isEmpty {
                        handle.readabilityHandler = nil
                        pipesDrained.leave()
                    } else {
                        client?.output(String(decoding: data, as: UTF8.self), isStderr: isStderr)
                    }
                }
            }

            process.terminationHandler = { [weak self] finished in
                // Deliver the exit status only after both pipes hit EOF so the
                // final output chunks reach the app before it closes its stream.
                pipesDrained.notify(queue: .global()) {
                    self?.stateQueue.async { self?.currentProcess = nil }
                    reply(finished.terminationStatus, nil)
                }
            }

            do {
                try process.run()
                self.currentProcess = process
            } catch {
                stdout.fileHandleForReading.readabilityHandler = nil
                stderr.fileHandleForReading.readabilityHandler = nil
                pipesDrained.leave()
                pipesDrained.leave()
                reply(-1, "Failed to launch port: \(error.localizedDescription)")
            }
        }
    }

    /// SIGINT lets port clean up its registry lock; never SIGKILL.
    func cancelCurrent() {
        stateQueue.async {
            self.currentProcess?.interrupt()
        }
    }
}

/// Per-connection exported object implementing the XPC protocol. Validates
/// everything the app sends before it reaches `port`.
final class HelperAPI: NSObject, PortHelperProtocol {
    private let service: HelperService
    private weak var connection: NSXPCConnection?

    init(service: HelperService, connection: NSXPCConnection) {
        self.service = service
        self.connection = connection
    }

    func getVersion(reply: @escaping (Int) -> Void) {
        reply(kHelperVersion)
    }

    func run(operationRaw: Int, packages: [String], reply: @escaping (Int32, String?) -> Void) {
        guard let operation = PortOperation(rawValue: operationRaw) else {
            reply(-1, "Unknown operation.")
            return
        }
        if operation.requiresPackages && packages.isEmpty {
            reply(-1, "\(operation.displayName) requires at least one package name.")
            return
        }
        if !operation.requiresPackages && !packages.isEmpty {
            reply(-1, "\(operation.displayName) does not accept package names.")
            return
        }
        for token in packages where !PackageToken.isValid(token) {
            reply(-1, "Invalid package name: \(token)")
            return
        }
        let client = connection?.remoteObjectProxy as? PortHelperClientProtocol
        service.launch(arguments: operation.arguments(packages: packages), client: client, reply: reply)
    }

    func cancel() {
        service.cancelCurrent()
    }
}
