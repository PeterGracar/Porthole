import Foundation

struct PortCommandError: LocalizedError {
    let status: Int32
    let output: String
    var errorDescription: String? {
        output.isEmpty ? "port exited with status \(status)" : output
    }
}

enum ProcessRunner {
    /// Runs an executable to completion, capturing stdout and stderr without
    /// deadlocking on full pipe buffers.
    static func run(_ executable: String, _ arguments: [String]) async throws -> (status: Int32, stdout: String, stderr: String) {
        try await withCheckedThrowingContinuation { continuation in
            let process = Process()
            process.executableURL = URL(fileURLWithPath: executable)
            process.arguments = arguments
            process.standardInput = FileHandle.nullDevice
            let stdout = Pipe()
            let stderr = Pipe()
            process.standardOutput = stdout
            process.standardError = stderr

            let lock = NSLock()
            var outData = Data()
            var errData = Data()
            let done = DispatchGroup()

            for (pipe, isStderr) in [(stdout, false), (stderr, true)] {
                done.enter()
                pipe.fileHandleForReading.readabilityHandler = { handle in
                    let data = handle.availableData
                    if data.isEmpty {
                        handle.readabilityHandler = nil
                        done.leave()
                    } else {
                        lock.lock()
                        if isStderr { errData.append(data) } else { outData.append(data) }
                        lock.unlock()
                    }
                }
            }

            done.enter()
            process.terminationHandler = { _ in done.leave() }

            do {
                try process.run()
            } catch {
                stdout.fileHandleForReading.readabilityHandler = nil
                stderr.fileHandleForReading.readabilityHandler = nil
                done.leave()
                done.leave()
                done.leave()
                continuation.resume(throwing: error)
                return
            }

            done.notify(queue: .global()) {
                lock.lock()
                let out = String(decoding: outData, as: UTF8.self)
                let err = String(decoding: errData, as: UTF8.self)
                lock.unlock()
                continuation.resume(returning: (process.terminationStatus, out, err))
            }
        }
    }
}

/// Read-only `port` queries, run directly by the app (no root required).
/// Mutating operations go through HelperManager instead.
struct PortClient {
    func run(_ arguments: [String]) async throws -> String {
        let result = try await ProcessRunner.run(kPortExecutablePath, arguments)
        guard result.status == 0 else {
            let message = (result.stderr + result.stdout).trimmingCharacters(in: .whitespacesAndNewlines)
            throw PortCommandError(status: result.status, output: message)
        }
        return result.stdout
    }

    func installed() async throws -> [InstalledPort] {
        PortParser.parseInstalled(try await run(["-q", "installed"]))
    }

    func outdated() async throws -> [OutdatedPort] {
        PortParser.parseOutdated(try await run(["-q", "outdated"]))
    }

    func search(_ term: String) async throws -> [SearchResult] {
        let sanitized = PackageToken.sanitizedSearchTerm(term)
        guard !sanitized.isEmpty else { return [] }
        return PortParser.parseSearch(try await run(["search", "--name", "--line", "--glob", "*\(sanitized)*"]))
    }

    func info(_ name: String) async throws -> PortInfo? {
        guard PackageToken.isValid(name) else { return nil }
        let output = try await run([
            "-q", "info", "--index",
            "--version", "--description", "--homepage", "--variants",
            "--license", "--categories", "--long_description",
            name,
        ])
        return PortParser.parseInfo(output)
    }

    func deps(_ name: String) async throws -> [DependencySection] {
        guard PackageToken.isValid(name) else { return [] }
        return PortParser.parseDeps(try await run(["-q", "deps", name]))
    }

    func inactive() async throws -> [String] {
        PortParser.parseEchoList(try await run(["-q", "echo", "inactive"]))
    }

    func leaves() async throws -> [String] {
        PortParser.parseEchoList(try await run(["-q", "echo", "leaves"]))
    }
}
