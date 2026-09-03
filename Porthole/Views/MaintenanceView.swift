import SwiftUI

struct MaintenanceView: View {
    @Environment(AppState.self) private var state
    @State private var preview: CleanupPreview?
    @State private var isLoadingPreview = false
    @State private var isConfirmingMigrate = false
    @State private var migrateAcknowledged = false

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
                section(
                    title: "Migrate After a macOS Upgrade",
                    description: "After a major macOS update (or a move to a different CPU architecture), MacPorts itself and every installed port must be rebuilt for the new platform (port migrate). Does nothing when no migration is needed. Can take a long time and requires Xcode or the Command Line Tools for the new macOS."
                ) {
                    Button("Migrate…") { isConfirmingMigrate = true }
                        .disabled(!state.canMutate)
                }
            }
            .padding(Metrics.spacingL)
        }
        .sheet(item: $preview) { preview in
            previewSheet(preview)
        }
        .sheet(isPresented: $isConfirmingMigrate, onDismiss: { migrateAcknowledged = false }) {
            migrateSheet
        }
    }

    /// Migration is long-running and rebuilds MacPorts base under itself, so
    /// starting it takes three deliberate actions: the Migrate… button, the
    /// acknowledgement checkbox, and the Migrate button. No button is the
    /// default action, so Return cannot start it either.
    private var migrateSheet: some View {
        VStack(alignment: .leading, spacing: Metrics.spacingM) {
            Text("Migrate MacPorts to this macOS version?").font(.title3).bold()
            Text("Runs 'port migrate'. MacPorts base is reinstalled first, then every port that is incompatible with the current platform is rebuilt from source. This can take hours and requires Xcode or the Command Line Tools for the new macOS.")
                .fixedSize(horizontal: false, vertical: true)
            Label("Do not interrupt the migration while MacPorts base is being reinstalled.", systemImage: "exclamationmark.triangle")
                .foregroundStyle(.orange)
                .fixedSize(horizontal: false, vertical: true)
            Toggle("I understand this can take a long time and should not be interrupted", isOn: $migrateAcknowledged)
            HStack {
                Spacer()
                Button("Cancel") { isConfirmingMigrate = false }
                    .keyboardShortcut(.cancelAction)
                Button("Migrate") {
                    isConfirmingMigrate = false
                    Task { await state.run(.migrate) }
                }
                .buttonStyle(.borderedProminent)
                .disabled(!migrateAcknowledged || !state.canMutate)
            }
        }
        .padding(Metrics.spacingL)
        .frame(minWidth: 440, maxWidth: 520)
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
