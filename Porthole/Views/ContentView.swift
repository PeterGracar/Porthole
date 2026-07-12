import SwiftUI
import Combine
import AppKit

enum SidebarItem: String, CaseIterable, Identifiable {
    case installed, outdated, search, maintenance
    var id: String { rawValue }
}

/// Full-window fallback shown when /opt/local/bin/port does not exist.
struct MacPortsMissingView: View {
    @Environment(AppState.self) private var state

    var body: some View {
        ContentUnavailableView {
            Label("MacPorts Not Installed", systemImage: "shippingbox.circle")
        } description: {
            Text("Porthole manages MacPorts packages, but no `port` executable was found at \(kPortExecutablePath).\nInstall MacPorts, then come back — the app picks it up automatically.")
        } actions: {
            HStack {
                Link("Get MacPorts", destination: URL(string: "https://www.macports.org/install.php")!)
                    .buttonStyle(.borderedProminent)
                Button("Check Again") {
                    state.recheckPortInstallation()
                }
            }
        }
        .navigationTitle("Porthole")
    }
}

struct ContentView: View {
    @Environment(AppState.self) private var state
    @State private var columnVisibility: NavigationSplitViewVisibility = .automatic
    @State private var lastRootWidth: CGFloat = 0

    /// Below this width the sidebar collapses instead of truncating its labels.
    private let sidebarCollapseThreshold: CGFloat = 880

    var body: some View {
        Group {
            if state.portInstalled {
                mainInterface
            } else {
                MacPortsMissingView()
            }
        }
        .task { state.startUp() }
        .onReceive(NotificationCenter.default.publisher(for: NSApplication.didBecomeActiveNotification)) { _ in
            // Re-check after the user visits System Settings (helper approval)
            // or installs MacPorts and comes back.
            state.recheckPortInstallation()
            state.helper.refreshStatus()
        }
    }

    private var mainInterface: some View {
        @Bindable var state = state
        return NavigationSplitView(columnVisibility: $columnVisibility) {
            List(selection: $state.sidebarSelection) {
                Label("Installed", systemImage: "shippingbox")
                    .badge(state.installed.count)
                    .tag(SidebarItem.installed)
                Label("Outdated", systemImage: "arrow.triangle.2.circlepath")
                    .badge(state.outdated.count)
                    .tag(SidebarItem.outdated)
                Label("Search", systemImage: "magnifyingglass")
                    .tag(SidebarItem.search)
                Label("Maintenance", systemImage: "wrench.and.screwdriver")
                    .tag(SidebarItem.maintenance)
            }
            .navigationSplitViewColumnWidth(min: 175, ideal: 195, max: 240)
        } detail: {
            VStack(spacing: 0) {
                if !state.helper.ready {
                    HelperOnboardingView()
                        .transition(.move(edge: .top).combined(with: .opacity))
                }
                if let message = state.statusMessage {
                    InlineBanner(kind: .error, title: message) {
                        Button("Dismiss") { state.statusMessage = nil }
                            .controlSize(.small)
                    }
                    .transition(.move(edge: .top).combined(with: .opacity))
                }
                detailContent
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .layoutPriority(1)
                Divider()
                ConsoleView()
            }
            .animation(.snappy(duration: 0.2), value: state.statusMessage)
            .animation(.snappy(duration: 0.2), value: state.helper.ready)
        }
        .navigationTitle("Porthole")
        .toolbar { toolbarContent }
        .onGeometryChange(for: CGFloat.self) { proxy in
            proxy.size.width
        } action: { width in
            // Collapse/expand the sidebar only when crossing the threshold, so
            // a manual toggle via the toolbar button is respected otherwise.
            defer { lastRootWidth = width }
            if lastRootWidth <= 0 {
                if width < sidebarCollapseThreshold { columnVisibility = .detailOnly }
                return
            }
            if width < sidebarCollapseThreshold && lastRootWidth >= sidebarCollapseThreshold {
                columnVisibility = .detailOnly
            } else if width >= sidebarCollapseThreshold && lastRootWidth < sidebarCollapseThreshold {
                columnVisibility = .all
            }
        }
    }

    @ViewBuilder private var detailContent: some View {
        switch state.sidebarSelection ?? .installed {
        case .installed: InstalledView()
        case .outdated: OutdatedView()
        case .search: SearchView()
        case .maintenance: MaintenanceView()
        }
    }

    @ToolbarContentBuilder private var toolbarContent: some ToolbarContent {
        ToolbarItemGroup {
            if let operation = state.runningOperation {
                ProgressView()
                    .controlSize(.small)
                Text(operation.displayName)
                    .foregroundStyle(.secondary)
                Button("Cancel", systemImage: "stop.circle") {
                    state.cancelRunning()
                }
                .help("Interrupt the running port command")
            }
            if state.isRefreshing {
                ProgressView()
                    .controlSize(.small)
                    .help("Refreshing…")
            } else {
                Button("Refresh", systemImage: "arrow.clockwise") {
                    Task { await state.refreshAll(announce: true) }
                }
                .keyboardShortcut("r", modifiers: .command)
                .help("Reload installed and outdated ports (⌘R)")
            }
        }
    }
}
