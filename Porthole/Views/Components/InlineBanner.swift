import SwiftUI

/// Full-width notification strip stacked above the main content, replacing
/// the previous per-view ad-hoc colored backgrounds.
struct InlineBanner<Actions: View>: View {
    enum Kind {
        case info, warning, error

        var tint: Color {
            switch self {
            case .info: return .blue
            case .warning: return .orange
            case .error: return .red
            }
        }

        var defaultSymbol: String {
            switch self {
            case .info: return "info.circle"
            case .warning: return "exclamationmark.triangle"
            case .error: return "exclamationmark.triangle"
            }
        }
    }

    let kind: Kind
    var systemImage: String?
    let title: String
    var subtitle: String?
    @ViewBuilder var actions: Actions

    init(
        kind: Kind,
        systemImage: String? = nil,
        title: String,
        subtitle: String? = nil,
        @ViewBuilder actions: () -> Actions
    ) {
        self.kind = kind
        self.systemImage = systemImage
        self.title = title
        self.subtitle = subtitle
        self.actions = actions()
    }

    var body: some View {
        HStack(spacing: Metrics.spacingM) {
            Image(systemName: systemImage ?? kind.defaultSymbol)
                .font(.title2)
                .foregroundStyle(kind.tint)
            VStack(alignment: .leading, spacing: 2) {
                Text(title).bold()
                if let subtitle {
                    Text(subtitle)
                        .font(.callout)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            Spacer()
            actions
        }
        .padding(Metrics.spacingM)
        .background(kind.tint.opacity(0.12))
        .overlay(alignment: .bottom) { Divider() }
        .accessibilityElement(children: .combine)
    }
}

extension InlineBanner where Actions == EmptyView {
    init(kind: Kind, systemImage: String? = nil, title: String, subtitle: String? = nil) {
        self.init(kind: kind, systemImage: systemImage, title: title, subtitle: subtitle) {
            EmptyView()
        }
    }
}
