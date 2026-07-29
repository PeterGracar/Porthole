import SwiftUI

struct OutdatedView: View {
    @Environment(AppState.self) private var state
    @State private var selection: OutdatedPort.ID?

    private var selectedPort: OutdatedPort? {
        state.outdated.first { $0.id == selection }
    }

    var body: some View {
        VStack(spacing: 0) {
            if state.outdated.isEmpty {
                ContentUnavailableView(
                    "Everything Up to Date",
                    systemImage: "checkmark.seal",
                    description: Text("No outdated ports. Run selfupdate from the toolbar to sync the ports tree, then check again.")
                )
            } else {
                MasterDetail {
                    portTable
                } detail: {
                    detailPane
                        .animation(.default, value: selection)
                }
            }
            Divider()
            HStack {
                Spacer()
                Button("Upgrade All Outdated") {
                    Task { await state.run(.upgradeOutdated) }
                }
                .buttonStyle(.borderedProminent)
                .disabled(state.outdated.isEmpty)
                .help("Upgrade every outdated port in one run")
            }
            .disabled(!state.canMutate)
            .padding(Metrics.spacingM)
        }
    }

    private var portTable: some View {
        Table(state.outdated, selection: $selection) {
            TableColumn("Name") { port in
                Text(port.name)
            }
            TableColumn("Installed") { port in
                Text(port.currentVersion)
                    .foregroundStyle(.secondary)
            }
            TableColumn("Available") { port in
                Text(port.newVersion)
            }
            TableColumn("Status") { _ in
                StatusBadge.updateAvailable
            }
            .width(110)
        }
        .contextMenu(forSelectionType: OutdatedPort.ID.self) { ids in
            if let port = state.outdated.first(where: { ids.contains($0.id) }) {
                Button("Upgrade") {
                    Task { await state.run(.upgrade, packages: [port.name]) }
                }
                .disabled(!state.canMutate)
            }
        }
    }

    @ViewBuilder private var detailPane: some View {
        if let port = selectedPort {
            VStack(spacing: 0) {
                PortDetailView(portName: port.name)
                Divider()
                HStack {
                    Spacer()
                    Button("Upgrade \(port.name)") {
                        Task { await state.run(.upgrade, packages: [port.name]) }
                    }
                    .buttonStyle(.borderedProminent)
                    .disabled(!state.canMutate)
                    .help("Upgrade just this port to \(port.newVersion.isEmpty ? "the latest version" : port.newVersion)")
                }
                .padding(Metrics.spacingM)
            }
            .id(port.id)
            .transition(.opacity)
        } else {
            ContentUnavailableView(
                "No Selection",
                systemImage: "arrow.triangle.2.circlepath",
                description: Text("Select a port to see its details and upgrade it individually.")
            )
        }
    }
}
