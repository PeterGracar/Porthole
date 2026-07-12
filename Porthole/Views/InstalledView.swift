import SwiftUI

struct InstalledView: View {
    @Environment(AppState.self) private var state
    @State private var filter = ""
    @State private var selection: InstalledPort.ID?
    @State private var confirmUninstall: InstalledPort?
    @FocusState private var searchFocused: Bool

    private var filtered: [InstalledPort] {
        guard !filter.isEmpty else { return state.installed }
        return state.installed.filter { $0.name.localizedCaseInsensitiveContains(filter) }
    }

    private var selectedPort: InstalledPort? {
        state.installed.first { $0.id == selection }
    }

    var body: some View {
        MasterDetail {
            Table(filtered, selection: $selection) {
                TableColumn("Name") { port in
                    Text(port.name)
                        .foregroundStyle(port.isActive ? Color.primary : Color.secondary)
                }
                TableColumn("Version") { port in
                    Text(port.versionDisplay)
                        .foregroundStyle(.secondary)
                }
                TableColumn("Status") { port in
                    port.isActive ? StatusBadge.active : StatusBadge.inactive
                }
                .width(90)
            }
            .contextMenu(forSelectionType: InstalledPort.ID.self) { ids in
                if let port = state.installed.first(where: { ids.contains($0.id) }) {
                    contextMenuItems(for: port)
                }
            }
        } detail: {
            detailPane
                .animation(.default, value: selection)
        }
        .searchable(text: $filter, placement: .toolbar, prompt: "Filter installed ports")
        .searchFocused($searchFocused)
        .onChange(of: state.searchFocusRequest) { searchFocused = true }
        .confirmationDialog(
            "Uninstall \(confirmUninstall?.name ?? "")?",
            isPresented: Binding(
                get: { confirmUninstall != nil },
                set: { if !$0 { confirmUninstall = nil } }
            ),
            presenting: confirmUninstall
        ) { port in
            Button("Uninstall \(port.name) @\(port.versionDisplay)", role: .destructive) {
                Task { await state.run(.uninstall, packages: [port.name, port.versionSpec]) }
            }
        } message: { _ in
            Text("Runs 'port uninstall'. Ports that other ports depend on will refuse to be removed.")
        }
    }

    @ViewBuilder private func contextMenuItems(for port: InstalledPort) -> some View {
        if port.isActive {
            Button("Deactivate") {
                Task { await state.run(.deactivate, packages: [port.name]) }
            }
        } else {
            Button("Activate") {
                Task { await state.run(.activate, packages: [port.name, port.versionSpec]) }
            }
        }
        Button("Clean") {
            Task { await state.run(.clean, packages: [port.name]) }
        }
        Divider()
        Button("Uninstall…", role: .destructive) {
            confirmUninstall = port
        }
    }

    @ViewBuilder private var detailPane: some View {
        if let port = selectedPort {
            VStack(spacing: 0) {
                PortDetailView(portName: port.name)
                Divider()
                ViewThatFits(in: .horizontal) {
                    HStack {
                        actionButtons(for: port)
                        Spacer()
                        uninstallButton(for: port)
                    }
                    VStack(alignment: .leading, spacing: Metrics.spacingS) {
                        HStack { actionButtons(for: port) }
                        uninstallButton(for: port)
                    }
                }
                .disabled(!state.canMutate)
                .padding(Metrics.spacingM)
            }
            .id(port.id)
            .transition(.opacity)
        } else {
            ContentUnavailableView(
                "No Selection",
                systemImage: "shippingbox",
                description: Text("Select a port to see its details.")
            )
        }
    }

    @ViewBuilder private func actionButtons(for port: InstalledPort) -> some View {
        if port.isActive {
            Button("Deactivate") {
                Task { await state.run(.deactivate, packages: [port.name]) }
            }
            .help("Take this port out of use while keeping its files installed")
        } else {
            Button("Activate") {
                Task { await state.run(.activate, packages: [port.name, port.versionSpec]) }
            }
            .help("Put this installed version back into use")
        }
        Button("Clean") {
            Task { await state.run(.clean, packages: [port.name]) }
        }
        .help("Remove build intermediates and downloaded files for this port")
    }

    private func uninstallButton(for port: InstalledPort) -> some View {
        Button("Uninstall…", role: .destructive) {
            confirmUninstall = port
        }
        .help("Remove this port after confirmation")
    }
}
