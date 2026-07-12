import SwiftUI

struct MaintenanceView: View {
    @Environment(AppState.self) private var state
    @State private var preview: CleanupPreview?
    @State private var isLoadingPreview = false

    struct CleanupPreview: Identifiable {
        let operation: PortOperation
        let items: [String]
        let error: String?
        var id: Int { operation.rawValue }
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: Metrics.spacingL) {
                section(
                    title: "Ports Tree",
                    description: "Update the MacPorts base system and sync the ports tree definitions (port selfupdate)."
                ) {
                    Button("Run Selfupdate") {
                        Task { await state.run(.selfupdate) }
                    }
                    .disabled(!state.canMutate)
                }
                section(
                    title: "Upgrade",
                    description: "Upgrade all installed ports for which a newer version is available (port upgrade outdated)."
                ) {
                    Button("Upgrade Outdated (\(state.outdated.count))") {
                        Task { await state.run(.upgradeOutdated) }
                    }
                    .disabled(!state.canMutate || state.outdated.isEmpty)
                }
                section(
                    title: "Reclaim Disk Space",
                    description: "Remove distfiles, unneeded build files, and inactive versions no longer required (port reclaim)."
                ) {
                    Button("Run Reclaim") {
                        Task { await state.run(.reclaim) }
                    }
                    .disabled(!state.canMutate)
                }
                section(
                    title: "Inactive Versions",
                    description: "After upgrades, superseded versions stay installed but inactive. Preview and remove them (port uninstall inactive)."
                ) {
                    Button("Remove Inactive…") { loadPreview(.uninstallInactive) }
                        .disabled(isLoadingPreview)
                }
                section(
                    title: "Leaves",
                    description: "Ports installed only as dependencies that nothing depends on anymore. Preview and uninstall them (port uninstall leaves)."
                ) {
                    Button("Uninstall Leaves…") { loadPreview(.uninstallLeaves) }
                        .disabled(isLoadingPreview)
                }
            }
            .padding(Metrics.spacingL)
        }
        .sheet(item: $preview) { preview in
            previewSheet(preview)
        }
    }

    private func section(title: String, description: String, @ViewBuilder content: () -> some View) -> some View {
        GroupBox {
            VStack(alignment: .leading, spacing: Metrics.spacingS) {
                Text(title).font(.headline)
                Text(description)
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
                content()
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(Metrics.spacingS)
        }
    }

    @ViewBuilder private func previewSheet(_ preview: CleanupPreview) -> some View {
        VStack(alignment: .leading, spacing: Metrics.spacingM) {
            Text(preview.operation.displayName).font(.title3).bold()
            if let error = preview.error {
                Label("Could not load the preview: \(error)", systemImage: "exclamationmark.triangle")
                    .foregroundStyle(.red)
                    .fixedSize(horizontal: false, vertical: true)
            } else if preview.items.isEmpty {
                ContentUnavailableView(
                    "Nothing to Remove",
                    systemImage: "checkmark.circle",
                    description: Text("Everything is already clean.")
                )
                .frame(minHeight: 140)
            } else {
                Text("The following \(preview.items.count) \(preview.items.count == 1 ? "entry" : "entries") will be removed:")
                ScrollView {
                    VStack(alignment: .leading, spacing: 2) {
                        ForEach(preview.items, id: \.self) { item in
                            Text(item).font(.system(.callout, design: .monospaced))
                        }
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(Metrics.spacingS)
                }
                .background(Color(nsColor: .textBackgroundColor))
                .frame(minHeight: 120, maxHeight: 320)
            }
            HStack {
                Spacer()
                if preview.error != nil || preview.items.isEmpty {
                    Button("OK") { self.preview = nil }
                        .buttonStyle(.borderedProminent)
                        .keyboardShortcut(.defaultAction)
                } else {
                    Button("Cancel") { self.preview = nil }
                        .keyboardShortcut(.cancelAction)
                    Button("Remove", role: .destructive) {
                        self.preview = nil
                        Task { await state.run(preview.operation) }
                    }
                    .buttonStyle(.borderedProminent)
                    .disabled(!state.canMutate)
                }
            }
        }
        .padding(Metrics.spacingL)
        .frame(minWidth: 440)
    }

    private func loadPreview(_ operation: PortOperation) {
        guard !isLoadingPreview else { return }
        isLoadingPreview = true
        Task {
            defer { isLoadingPreview = false }
            do {
                let items = operation == .uninstallInactive
                    ? try await state.client.inactive()
                    : try await state.client.leaves()
                preview = CleanupPreview(operation: operation, items: items, error: nil)
            } catch {
                preview = CleanupPreview(operation: operation, items: [], error: error.localizedDescription)
            }
        }
    }
}
