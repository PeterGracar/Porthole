import SwiftUI
import AppKit

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    let state = AppState()

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        true
    }

    func applicationShouldTerminate(_ sender: NSApplication) -> NSApplication.TerminateReply {
        guard let operation = state.runningOperation else { return .terminateNow }
        let alert = NSAlert()
        alert.alertStyle = .warning
        alert.messageText = "\(operation.displayName) is still in progress"
        alert.informativeText = "Quitting Porthole interrupts the running port command. It stops cleanly (like pressing Ctrl-C), but the operation will be left unfinished."
        alert.addButton(withTitle: "Stop and Quit")
        alert.addButton(withTitle: "Cancel")
        if alert.runModal() == .alertFirstButtonReturn {
            state.cancelRunning()
            return .terminateNow
        }
        return .terminateCancel
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
