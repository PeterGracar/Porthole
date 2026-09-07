import SwiftUI
import AppKit

struct ConsoleView: View {
    @Environment(AppState.self) private var state
    @State private var autoScroll = true

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: Metrics.spacingM) {
                Button {
                    withAnimation(.easeInOut(duration: 0.15)) { state.isConsoleExpanded.toggle() }
                } label: {
                    HStack(spacing: 6) {
                        Image(systemName: state.isConsoleExpanded ? "chevron.down" : "chevron.right")
                            .font(.caption)
                        Label("Console", systemImage: "terminal")
                            .font(.callout.bold())
                    }
                }
                .buttonStyle(.plain)
                .accessibilityLabel(state.isConsoleExpanded ? "Hide console" : "Show console")
                // Activity lives here rather than in the toolbar, next to the
                // output it produces (see the toolbar comment in ContentView).
                if let operation = state.runningOperation {
                    activityLabel(operation.displayName)
                } else if state.isRefreshing {
                    activityLabel("Refreshing…")
                }
                Spacer()
                if state.isConsoleExpanded {
                    Toggle("Auto-scroll", isOn: $autoScroll)
                        .toggleStyle(.checkbox)
                        .font(.callout)
                    Button("Copy") { copyLog() }
                        .controlSize(.small)
                        .disabled(state.console.lines.isEmpty)
                        .help("Copy the entire log to the clipboard")
                    Button("Clear") { state.console.clear() }
                        .controlSize(.small)
                        .help("Empty the console (⌘K)")
                }
            }
            .padding(.horizontal, Metrics.spacingM)
            .padding(.vertical, 6)
            .contentShape(Rectangle())
            .background(.bar)
            if state.isConsoleExpanded {
                Divider()
                logView
                    .frame(height: Metrics.consoleHeight)
            }
        }
        // Surface the log automatically when an operation starts.
        .onChange(of: state.runningOperation != nil) { _, isRunning in
            if isRunning {
                withAnimation(.easeInOut(duration: 0.15)) { state.isConsoleExpanded = true }
            }
        }
    }

    private var logView: some View {
        VStack(spacing: 0) {
            ScrollViewReader { proxy in
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 1) {
                        ForEach(state.console.lines) { line in
                            Text(line.text)
                                .font(font(for: line.kind))
                                .foregroundStyle(color(for: line.kind))
                                .textSelection(.enabled)
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .id(line.id)
                        }
                    }
                    .padding(Metrics.spacingS)
                }
                .background(Color(nsColor: .textBackgroundColor))
                .onChange(of: state.console.lines.last?.id) { _, newID in
                    if autoScroll, let newID {
                        proxy.scrollTo(newID, anchor: .bottom)
                    }
                }
                .onChange(of: state.console.lines.last?.text) { _, _ in
                    if autoScroll, let id = state.console.lines.last?.id {
                        proxy.scrollTo(id, anchor: .bottom)
                    }
                }
            }
        }
    }

    private func activityLabel(_ title: String) -> some View {
        HStack(spacing: Metrics.spacingS) {
            ProgressView()
                .controlSize(.small)
            Text(title)
                .font(.callout)
                .foregroundStyle(.secondary)
        }
        .padding(.leading, Metrics.spacingXS)
        .transition(.opacity)
        .animation(.easeInOut(duration: 0.15), value: title)
    }

    private func copyLog() {
        let text = state.console.lines.map(\.text).joined(separator: "\n")
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(text, forType: .string)
    }

    private func color(for kind: ConsoleModel.Line.Kind) -> Color {
        switch kind {
        case .stdout: return .primary
        case .stderr: return .red
        case .system: return .blue
        }
    }

    /// System lines are bold so they stand out without relying on color alone.
    private func font(for kind: ConsoleModel.Line.Kind) -> Font {
        let base = Font.system(.caption, design: .monospaced)
        return kind == .system ? base.bold() : base
    }
}
