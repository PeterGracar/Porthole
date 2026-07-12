import Foundation
import Observation
import ServiceManagement

enum HelperError: LocalizedError {
    case notConnected
    case operationFailed(code: Int32, message: String?)
    case connectionLost(underlying: Error)

    var errorDescription: String? {
        switch self {
        case .notConnected:
            return "The privileged helper is not available."
        case .operationFailed(let code, let message):
            return message ?? "port exited with status \(code)"
        case .connectionLost(let underlying):
            return "Lost connection to the helper: \(underlying.localizedDescription)"
        }
    }
}

/// Receives streamed output from the daemon; the active handler is swapped in
/// per operation (only one mutating operation runs at a time).
final class OutputSink: NSObject, PortHelperClientProtocol {
    private let lock = NSLock()
    private var handler: ((String, Bool) -> Void)?

    func setHandler(_ newHandler: ((String, Bool) -> Void)?) {
        lock.lock()
        handler = newHandler
        lock.unlock()
    }

    func output(_ chunk: String, isStderr: Bool) {
        lock.lock()
        let current = handler
        lock.unlock()
        current?(chunk, isStderr)
    }
}

/// Runs its body at most once; guards continuations that can be resumed from
/// both an XPC reply and the connection error handler.
final class Once: @unchecked Sendable {
    private let lock = NSLock()
    private var done = false

    func callAsFunction(_ body: () -> Void) {
        lock.lock()
        let shouldRun = !done
        done = true
        lock.unlock()
        if shouldRun { body() }
    }
}

/// Owns the SMAppService registration state machine and the XPC connection to
/// the root helper daemon.
@MainActor @Observable
final class HelperManager {
    enum Status: Equatable {
        case unknown
        case notRegistered
        case requiresApproval
        case enabled
    }

    private(set) var status: Status = .unknown
    /// True once the daemon is enabled AND the version handshake succeeded.
    private(set) var ready = false
    private(set) var lastError: String?

    private let service = SMAppService.daemon(plistName: "\(kMachServiceName).plist")
    private var connection: NSXPCConnection?
    private let sink = OutputSink()
    private var monitorTask: Task<Void, Never>?

    func start() {
        refreshStatus()
        monitorTask?.cancel()
        monitorTask = Task { [weak self] in
            // Poll while waiting for the user to approve the daemon in System
            // Settings; there is no notification API for that transition.
            while !Task.isCancelled {
                try? await Task.sleep(for: .seconds(2))
                guard let self else { return }
                if !self.ready { self.refreshStatus() }
            }
        }
    }

    func refreshStatus() {
        switch service.status {
        case .notRegistered, .notFound:
            status = .notRegistered
            ready = false
        case .requiresApproval:
            status = .requiresApproval
            ready = false
        case .enabled:
            status = .enabled
            if !ready {
                Task { await self.connectAndHandshake() }
            }
        @unknown default:
            status = .unknown
            ready = false
        }
    }

    func register() {
        lastError = nil
        do {
            try service.register()
        } catch {
            // Daemon registration commonly reports the pending-approval state
            // as an error; only surface anything beyond that.
            if service.status != .requiresApproval {
                lastError = error.localizedDescription
            }
        }
        refreshStatus()
        if status == .requiresApproval {
            SMAppService.openSystemSettingsLoginItems()
        }
    }

    func openSystemSettings() {
        SMAppService.openSystemSettingsLoginItems()
    }

    // MARK: - XPC connection

    private func connect() -> NSXPCConnection {
        if let connection { return connection }
        let newConnection = NSXPCConnection(machServiceName: kMachServiceName, options: .privileged)
        newConnection.remoteObjectInterface = NSXPCInterface(with: PortHelperProtocol.self)
        newConnection.exportedInterface = NSXPCInterface(with: PortHelperClientProtocol.self)
        newConnection.exportedObject = sink
        newConnection.invalidationHandler = { [weak self] in
            Task { @MainActor [weak self] in
                self?.connection = nil
                self?.ready = false
            }
        }
        newConnection.resume()
        connection = newConnection
        return newConnection
    }

    private func proxy(errorHandler: @escaping (Error) -> Void) -> PortHelperProtocol? {
        connect().remoteObjectProxyWithErrorHandler(errorHandler) as? PortHelperProtocol
    }

    private func connectAndHandshake() async {
        let version: Int? = await withCheckedContinuation { continuation in
            let once = Once()
            guard let proxy = proxy(errorHandler: { _ in once { continuation.resume(returning: nil) } }) else {
                once { continuation.resume(returning: nil) }
                return
            }
            proxy.getVersion { version in
                once { continuation.resume(returning: version) }
            }
        }
        guard let version else {
            ready = false
            lastError = "Could not communicate with the helper. Try disabling and re-enabling it in System Settings."
            return
        }
        if version == kHelperVersion {
            ready = true
            lastError = nil
        } else {
            // The app bundle contains a newer helper than the one running;
            // re-register so launchd picks up the new binary. Approval is tied
            // to the code signature, so this does not re-prompt.
            connection?.invalidate()
            connection = nil
            try? await service.unregister()
            try? await Task.sleep(for: .milliseconds(500))
            try? service.register()
            refreshStatus()
        }
    }

    // MARK: - Operations

    /// Streams output chunks for one mutating operation; finishes when port
    /// exits, throwing on nonzero exit or connection loss.
    func run(_ operation: PortOperation, packages: [String]) -> AsyncThrowingStream<ConsoleChunk, Error> {
        let (stream, continuation) = AsyncThrowingStream<ConsoleChunk, Error>.makeStream()
        guard ready else {
            continuation.finish(throwing: HelperError.notConnected)
            return stream
        }
        let sink = self.sink
        sink.setHandler { text, isStderr in
            continuation.yield(ConsoleChunk(text: text, isStderr: isStderr))
        }
        let once = Once()
        guard let proxy = proxy(errorHandler: { error in
            sink.setHandler(nil)
            once { continuation.finish(throwing: HelperError.connectionLost(underlying: error)) }
        }) else {
            sink.setHandler(nil)
            once { continuation.finish(throwing: HelperError.notConnected) }
            return stream
        }
        proxy.run(operationRaw: operation.rawValue, packages: packages) { code, message in
            sink.setHandler(nil)
            once {
                if code == 0 {
                    continuation.finish()
                } else {
                    continuation.finish(throwing: HelperError.operationFailed(code: code, message: message))
                }
            }
        }
        return stream
    }

    func cancel() {
        proxy(errorHandler: { _ in })?.cancel()
    }
}
