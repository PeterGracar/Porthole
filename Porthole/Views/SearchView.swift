import SwiftUI

struct SearchView: View {
    @Environment(AppState.self) private var state
    @State private var query = ""
    @State private var results: [SearchResult] = []
    @State private var isSearching = false
    @State private var searchError: String?
    @State private var selection: SearchResult.ID?
    @State private var installName = ""
    @FocusState private var searchFocused: Bool

    private var selectedResult: SearchResult? {
        results.first { $0.id == selection }
    }

    var body: some View {
        MasterDetail {
            VStack(spacing: 0) {
                if let searchError {
                    InlineBanner(kind: .error, title: searchError) {
                        Button("Dismiss") { self.searchError = nil }
                            .controlSize(.small)
                    }
                }
                Table(results, selection: $selection) {
                    TableColumn("Name") { result in
                        Text(result.name)
                    }
                    TableColumn("Version") { result in
                        Text(result.version).foregroundStyle(.secondary)
                    }
                    .width(90)
                    TableColumn("Description") { result in
                        Text(result.summary).lineLimit(1)
                    }
                }
                .overlay {
                    if isSearching && results.isEmpty {
                        ProgressView("Searching…")
                    }
                }
                Divider()
                HStack {
                    TextField("Install by exact name", text: $installName)
                        .textFieldStyle(.roundedBorder)
                        .onSubmit { installByName() }
                    Button("Install") { installByName() }
                        .disabled(!state.canMutate || !PackageToken.isValid(installName.trimmingCharacters(in: .whitespaces)))
                        .help("Install the port named in the field")
                }
                .padding(Metrics.spacingS)
            }
        } detail: {
            detailPane
                .animation(.default, value: selection)
        }
        .searchable(text: $query, placement: .toolbar, prompt: "Search ports by name")
        .searchFocused($searchFocused)
        .onChange(of: state.searchFocusRequest) { searchFocused = true }
        .task(id: query) {
            let term = query.trimmingCharacters(in: .whitespaces)
            guard term.count >= 2 else {
                results = []
                searchError = nil
                return
            }
            // Debounce type-ahead; the task is cancelled when the query changes.
            try? await Task.sleep(for: .milliseconds(350))
            guard !Task.isCancelled else { return }
            isSearching = true
            defer { isSearching = false }
            do {
                let found = try await state.client.search(term)
                if !Task.isCancelled {
                    results = found
                    searchError = nil
                }
            } catch {
                if !Task.isCancelled {
                    searchError = error.localizedDescription
                }
            }
        }
    }

    @ViewBuilder private var detailPane: some View {
        if let result = selectedResult {
            VStack(spacing: 0) {
                PortDetailView(portName: result.name)
                Divider()
                HStack {
                    Spacer()
                    if state.installed.contains(where: { $0.name == result.name }) {
                        StatusBadge.installed
                    } else {
                        Button("Install") {
                            Task { await state.run(.install, packages: [result.name]) }
                        }
                        .buttonStyle(.borderedProminent)
                        .disabled(!state.canMutate)
                        .help("Install \(result.name) with default variants")
                    }
                }
                .padding(Metrics.spacingM)
            }
            .id(result.id)
            .transition(.opacity)
        } else {
            ContentUnavailableView(
                "Search MacPorts",
                systemImage: "magnifyingglass",
                description: Text("Type at least two characters to search the ports tree by name.")
            )
        }
    }

    private func installByName() {
        let name = installName.trimmingCharacters(in: .whitespaces)
        guard PackageToken.isValid(name), state.canMutate else { return }
        installName = ""
        Task { await state.run(.install, packages: [name]) }
    }
}
