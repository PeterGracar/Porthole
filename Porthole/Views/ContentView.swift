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
    @State private var isSidebarVisible = true
    @State private var lastRootWidth: CGFloat = 0

    /// Below this width the sidebar collapses instead of truncating its labels.
    private let sidebarCollapseThreshold: CGFloat = 880
    private let sidebarWidth: CGFloat = 200

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

    // The obvious layout here is NavigationSplitView, and the app used it until
    // it hit a macOS 26.5 bug: on some multi-display setups the split view
    // measures its fitting height as window height + another display's height
    // (content-independent, reproducible on every fresh launch), lays out both
    // columns in that oversized, vertically centered frame, and autosaves the
    // broken geometry. Symptoms: sidebar looks empty, content bleeds past the
    // title bar and window bottom, row hit-testing is offset by hundreds of
    // points. No app-side constraint, autosave seeding, or frame pinning fixes
    // it reliably, so the sidebar is a plain fixed-width List instead.
    private var mainInterface: some View {
        @Bindable var state = state
        return NavigationStack {
            HStack(spacing: 0) {
                if isSidebarVisible {
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
                    .listStyle(.sidebar)
                    .frame(width: sidebarWidth)
                    .transition(.move(edge: .leading))
                    Divider()
                }
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
        }
        .onGeometryChange(for: CGFloat.self) { proxy in
            proxy.size.width
        } action: { width in
            // Collapse/expand the sidebar only when crossing the threshold, so
            // a manual toggle via the toolbar button is respected otherwise.
            defer { lastRootWidth = width }
            if lastRootWidth <= 0 {
                if width < sidebarCollapseThreshold { isSidebarVisible = false }
                return
            }
            if width < sidebarCollapseThreshold && lastRootWidth >= sidebarCollapseThreshold {
                isSidebarVisible = false
            } else if width >= sidebarCollapseThreshold && lastRootWidth < sidebarCollapseThreshold {
                isSidebarVisible = true
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
        ToolbarItem(placement: .navigation) {
            Button("Toggle Sidebar", systemImage: "sidebar.left") {
                withAnimation(.snappy(duration: 0.2)) { isSidebarVisible.toggle() }
            }
            .keyboardShortcut("s", modifiers: [.command, .control])
            .help("Hide or show the sidebar (⌃⌘S)")
        }
        // List refreshes are automatic (MacPortsChangeMonitor), so the trailing
        // slot is selfupdate — swapped for the stop button while anything runs.
        ToolbarItemGroup {
            if let operation = state.runningOperation {
                ProgressView()
                    .controlSize(.small)
                    // Breathing room against the capsule edge, which hugs the
                    // spinner tighter than it does bordered buttons.
                    .padding(.horizontal, Metrics.spacingXS)
                Text(operation.displayName)
                    .foregroundStyle(.secondary)
                Button("Stop", systemImage: "stop.circle") {
                    state.cancelRunning()
                }
                .help("Interrupt the running port command")
            } else if state.isRefreshing {
                ProgressView()
                    .controlSize(.small)
                    .padding(.horizontal, Metrics.spacingXS)
                    .help("Refreshing…")
            } else {
                Button("Selfupdate", systemImage: "arrow.clockwise") {
                    Task { await state.run(.selfupdate) }
                }
                .keyboardShortcut("r", modifiers: .command)
                .disabled(!state.canMutate)
                .help("Update MacPorts and sync the ports tree (⌘R)")
            }
        }
    }
}
