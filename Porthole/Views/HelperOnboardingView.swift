import SwiftUI

/// Banner shown while the privileged helper is not ready. Read-only features
/// work regardless; this only gates mutating operations.
struct HelperOnboardingView: View {
    @Environment(AppState.self) private var state

    var body: some View {
        InlineBanner(
            kind: .warning,
            systemImage: "lock.shield",
            title: title,
            subtitle: subtitle
        ) {
            actionButton
        }
    }

    private var title: String {
        switch state.helper.status {
        case .notRegistered, .unknown: return "Helper Not Enabled"
        case .requiresApproval: return "Approve the Helper in System Settings"
        case .enabled: return "Connecting to Helper…"
        }
    }

    private var subtitle: String {
        var text: String
        switch state.helper.status {
        case .notRegistered, .unknown:
            text = "Installing, upgrading, and uninstalling ports needs a one-time approval of Porthole's background helper. Browsing and searching work without it."
        case .requiresApproval:
            text = "Allow “Porthole” under Login Items & Extensions and authenticate once. After that, no more password prompts."
        case .enabled:
            text = "The helper is enabled; establishing the connection…"
        }
        if let error = state.helper.lastError {
            text += "\n\(error)"
        }
        return text
    }

    @ViewBuilder private var actionButton: some View {
        switch state.helper.status {
        case .notRegistered, .unknown:
            Button("Enable Helper") { state.helper.register() }
                .buttonStyle(.borderedProminent)
        case .requiresApproval:
            Button("Open System Settings") { state.helper.openSystemSettings() }
                .buttonStyle(.borderedProminent)
        case .enabled:
            Button("Retry") { state.helper.refreshStatus() }
        }
    }
}
