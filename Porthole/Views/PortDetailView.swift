import SwiftUI

/// Lazily loads and shows `port info` + `port deps` for the selected port.
struct PortDetailView: View {
    @Environment(AppState.self) private var state
    let portName: String

    @State private var info: PortInfo?
    @State private var deps: [DependencySection] = []
    @State private var isLoading = false
    @State private var loadError: String?

    @ViewBuilder private func metadataRow(_ label: String, _ value: String) -> some View {
        if !value.isEmpty {
            VStack(alignment: .leading, spacing: 1) {
                Text(label)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                Text(value)
                    .font(.callout)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: Metrics.spacingM) {
                HStack(alignment: .firstTextBaseline) {
                    Text(portName).font(.title2).bold()
                    if let info {
                        Text("@\(info.version)")
                            .foregroundStyle(.secondary)
                            .textSelection(.enabled)
                    }
                    Spacer()
                    if isLoading {
                        ProgressView().controlSize(.small)
                    }
                }
                if let loadError {
                    Label(loadError, systemImage: "exclamationmark.triangle")
                        .font(.callout)
                        .foregroundStyle(.red)
                }
                if let info {
                    if !info.summary.isEmpty {
                        Text(info.summary)
                            .font(.headline)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    if !info.longDescription.isEmpty && info.longDescription != info.summary {
                        Text(info.longDescription)
                            .font(.callout)
                            .foregroundStyle(.secondary)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    if !info.homepage.isEmpty, let url = URL(string: info.homepage) {
                        Link(info.homepage, destination: url)
                            .font(.callout)
                            .lineLimit(1)
                            .truncationMode(.middle)
                    }
                    metadataRow("Categories", info.categories)
                    metadataRow("License", info.license)
                    metadataRow("Variants", info.variants.joined(separator: ", "))
                }
                if !deps.isEmpty {
                    Divider()
                    Text("Dependencies").font(.headline)
                    ForEach(deps) { section in
                        VStack(alignment: .leading, spacing: 2) {
                            Text(section.kind)
                                .font(.subheadline)
                                .foregroundStyle(.secondary)
                            Text(section.items.joined(separator: ", "))
                                .font(.callout)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                    }
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(Metrics.spacingM)
        }
        .task(id: portName) {
            info = nil
            deps = []
            loadError = nil
            isLoading = true
            defer { isLoading = false }
            do {
                info = try await state.client.info(portName)
                deps = try await state.client.deps(portName)
            } catch {
                if !Task.isCancelled {
                    loadError = error.localizedDescription
                }
            }
        }
    }
}
