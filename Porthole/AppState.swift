import Foundation
import Observation

/// Console scrollback with carriage-return handling so port's progress bars
/// replace the current line instead of flooding the log.
@MainActor @Observable
final class ConsoleModel {
    struct Line: Identifiable {
        let id: Int
        var text: String
        var kind: Kind

        enum Kind { case stdout, stderr, system }
    }

    private(set) var lines: [Line] = []
    private var nextID = 0
    /// True while the last line has not been terminated by a newline yet.
    private var openLine = false
    private let maxLines = 2000

    func clear() {
        lines.removeAll()
        openLine = false
    }

    func appendSystem(_ text: String) {
        openLine = false
        lines.append(Line(id: nextID, text: text, kind: .system))
        nextID += 1
        trim()
    }

    func append(_ chunk: ConsoleChunk) {
        let kind: Line.Kind = chunk.isStderr ? .stderr : .stdout
        let text = chunk.text.replacingOccurrences(of: "\r\n", with: "\n")
        let segments = text.split(separator: "\n", omittingEmptySubsequences: false)
        for (index, segment) in segments.enumerated() {
            if index > 0 { openLine = false }
            appendToOpenLine(segment, kind: kind)
        }
        trim()
    }

    private func appendToOpenLine(_ segment: Substring, kind: Line.Kind) {
        var content = segment
        var resetLine = false
        if let lastCR = content.lastIndex(of: "\r") {
            content = content[content.index(after: lastCR)...]
            resetLine = true
        }
        guard !content.isEmpty || resetLine else { return }
        if openLine, let lastIndex = lines.indices.last {
            if resetLine {
                lines[lastIndex].text = String(content)
            } else {
                lines[lastIndex].text += content
            }
        } else if !content.isEmpty {
            lines.append(Line(id: nextID, text: String(content), kind: kind))
            nextID += 1
            openLine = true
        }
    }

    private func trim() {
        if lines.count > maxLines {
            lines.removeFirst(lines.count - maxLines)
        }
    }
}

@MainActor @Observable
final class AppState {
    let client = PortClient()
    let helper = HelperManager()
    let console = ConsoleModel()

    var installed: [InstalledPort] = []
    var outdated: [OutdatedPort] = []
    // UI state lives here (not in the views) so menu commands can drive it.
    var sidebarSelection: SidebarItem? = .installed
    var isConsoleExpanded = false
    /// Incremented by the ⌘F menu command; views observe it to focus their
    /// search field.
    var searchFocusRequest = 0
    /// Gate for mutating controls; port cannot run two mutating ops anyway.
    var runningOperation: PortOperation?
    var statusMessage: String?
    var isRefreshing = false
    var portInstalled = FileManager.default.isExecutableFile(atPath: kPortExecutablePath)
    private var servicesStarted = false

    var canMutate: Bool { runningOperation == nil && helper.ready }

    func startUp() {
        recheckPortInstallation()
    }

    /// Re-evaluates whether MacPorts exists; starts the helper and the first
    /// refresh once it appears (also called when the app regains focus, so the
    /// UI comes alive right after MacPorts is installed).
    func recheckPortInstallation() {
        portInstalled = FileManager.default.isExecutableFile(atPath: kPortExecutablePath)
        if portInstalled && !servicesStarted {
            servicesStarted = true
            helper.start()
            Task { await refreshAll() }
        }
    }

    /// Reloads the installed and outdated lists. `announce` adds a console
    /// line — used for the explicit toolbar action; automatic refreshes
    /// (startup, after operations) stay quiet.
    func refreshAll(announce: Bool = false) async {
        isRefreshing = true
        defer { isRefreshing = false }
        do {
            async let installedPorts = client.installed()
            async let outdatedPorts = client.outdated()
            installed = try await installedPorts
            outdated = try await outdatedPorts
            statusMessage = nil
            if announce {
                console.appendSystem("✓ Refreshed — \(installed.count) installed, \(outdated.count) outdated")
            }
        } catch {
            statusMessage = "Refresh failed: \(error.localizedDescription)"
            if announce {
                console.appendSystem("✗ Refresh failed: \(error.localizedDescription)")
            }
        }
    }

    /// Central runner for all mutating operations: streams output into the
    /// console, then refreshes the lists.
    func run(_ operation: PortOperation, packages: [String] = []) async {
        guard runningOperation == nil else { return }
        guard helper.ready else {
            statusMessage = "Enable the helper before running operations."
            return
        }
        runningOperation = operation
        console.appendSystem("▶ port " + operation.arguments(packages: packages).joined(separator: " "))
        do {
            for try await chunk in helper.run(operation, packages: packages) {
                console.append(chunk)
            }
            console.appendSystem("✓ \(operation.displayName) finished")
        } catch {
            console.appendSystem("✗ \(operation.displayName) failed: \(error.localizedDescription)")
        }
        runningOperation = nil
        await refreshAll()
    }

    func cancelRunning() {
        helper.cancel()
    }

    /// ⌘F: jump to a screen with a search field (if needed) and focus it.
    func focusSearch() {
        if sidebarSelection != .installed && sidebarSelection != .search {
            sidebarSelection = .search
            // Bump the counter on the next runloop pass so the freshly
            // switched-in view is mounted and observing before it fires.
            Task { @MainActor in searchFocusRequest += 1 }
        } else {
            searchFocusRequest += 1
        }
    }
}
