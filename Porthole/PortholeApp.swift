import SwiftUI
import AppKit

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate, NSWindowDelegate {
    let state = AppState()

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        true
    }

    /// True while a quit-confirmation alert is on screen (or was just dismissed
    /// this run-loop turn). Cmd-Q re-delivers the terminate request after the
    /// alert is cancelled; swallowing that repeat is what stops the dialog from
    /// looping. The flag is cleared asynchronously so the repeat — which arrives
    /// before the next run-loop turn — still sees it set.
    private var isConfirmingQuit = false

    /// Prompts to interrupt the running operation, if any. Returns true when the
    /// caller may proceed (nothing running, or the user chose "Stop and Quit" —
    /// in which case the operation is cancelled) and false to stay put. The
    /// re-entrancy guard stops a re-delivered close/terminate request from
    /// stacking a second dialog.
    private func confirmInterruptRunningOperation() -> Bool {
        guard let operation = state.runningOperation else { return true }
        if isConfirmingQuit { return false }
        isConfirmingQuit = true
        defer { DispatchQueue.main.async { self.isConfirmingQuit = false } }

        let alert = NSAlert()
        alert.alertStyle = .warning
        alert.messageText = "\(operation.displayName) is still in progress"
        alert.informativeText = "Quitting Porthole interrupts the running port command. It stops cleanly (like pressing Ctrl-C), but the operation will be left unfinished."
        alert.addButton(withTitle: "Stop and Quit")
        alert.addButton(withTitle: "Cancel")
        if alert.runModal() == .alertFirstButtonReturn {
            state.cancelRunning()
            return true
        }
        return false
    }

    func applicationShouldTerminate(_ sender: NSApplication) -> NSApplication.TerminateReply {
        confirmInterruptRunningOperation() ? .terminateNow : .terminateCancel
    }

    // Gate the window's close button too: closing the last window would
    // terminate the app via applicationShouldTerminateAfterLastWindowClosed,
    // but the window closes *before* that check — so intercept it here and keep
    // the window open when the user cancels. On "Stop and Quit" the operation is
    // already cancelled, so the subsequent terminate check passes without a
    // second prompt.
    func windowShouldClose(_ sender: NSWindow) -> Bool {
        confirmInterruptRunningOperation()
    }
}

/// Installs `delegate` as the hosting window's delegate so `windowShouldClose`
/// is honored. SwiftUI's WindowGroup doesn't expose a close hook of its own.
private struct WindowDelegateInstaller: NSViewRepresentable {
    let delegate: NSWindowDelegate

    func makeNSView(context: Context) -> NSView {
        let view = NSView()
        DispatchQueue.main.async { [weak view] in
            view?.window?.delegate = delegate
        }
        return view
    }

    func updateNSView(_ nsView: NSView, context: Context) {
        DispatchQueue.main.async { [weak nsView] in
            if nsView?.window?.delegate == nil {
                nsView?.window?.delegate = delegate
            }
        }
    }
}

@main
struct PortholeApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environment(appDelegate.state)
                // Keep the ideal size of the (potentially huge) installed table
                // from driving the initial window frame past the screen edge.
                .frame(minWidth: 760, minHeight: 480)
                .background(WindowDelegateInstaller(delegate: appDelegate))
        }
        .defaultSize(width: 1080, height: 700)
        .commands {
            CommandGroup(after: .sidebar) {
                Divider()
                Button("Installed") { appDelegate.state.sidebarSelection = .installed }
                    .keyboardShortcut("1", modifiers: .command)
                Button("Outdated") { appDelegate.state.sidebarSelection = .outdated }
                    .keyboardShortcut("2", modifiers: .command)
                Button("Search") { appDelegate.state.sidebarSelection = .search }
                    .keyboardShortcut("3", modifiers: .command)
                Button("Maintenance") { appDelegate.state.sidebarSelection = .maintenance }
                    .keyboardShortcut("4", modifiers: .command)
                Divider()
                Button(appDelegate.state.isConsoleExpanded ? "Hide Console" : "Show Console") {
                    withAnimation(.easeInOut(duration: 0.15)) {
                        appDelegate.state.isConsoleExpanded.toggle()
                    }
                }
                .keyboardShortcut("l", modifiers: .command)
                Button("Clear Console") { appDelegate.state.console.clear() }
                    .keyboardShortcut("k", modifiers: .command)
            }
            CommandGroup(after: .textEditing) {
                Button("Find") { appDelegate.state.focusSearch() }
                    .keyboardShortcut("f", modifiers: .command)
            }
        }
    }
}
