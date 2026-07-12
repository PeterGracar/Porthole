import SwiftUI

/// Capsule status indicator. The symbol doubles as a non-color cue so state
/// is readable without color vision (and by VoiceOver via the label).
struct StatusBadge: View {
    let text: String
    let systemImage: String
    let tint: Color

    var body: some View {
        Label(text, systemImage: systemImage)
            .font(.caption)
            .padding(.horizontal, Metrics.spacingS)
            .padding(.vertical, 2)
            .background(Capsule().fill(tint.opacity(0.15)))
            .foregroundStyle(tint)
            .accessibilityLabel(Text(text))
    }

    static let active = StatusBadge(text: "Active", systemImage: "checkmark.circle.fill", tint: .green)
    static let inactive = StatusBadge(text: "Inactive", systemImage: "pause.circle", tint: .orange)
    static let updateAvailable = StatusBadge(text: "Update", systemImage: "arrow.up.circle", tint: .blue)
    static let installed = StatusBadge(text: "Installed", systemImage: "checkmark.circle", tint: .green)
}
