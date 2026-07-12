import SwiftUI

/// Shared layout constants so spacing stays consistent across screens.
enum Metrics {
    /// Tight stacks: metadata rows, badge internals.
    static let spacingXS: CGFloat = 4
    /// Inline padding: banners, toolbars, footers.
    static let spacingS: CGFloat = 8
    /// Content spacing/padding inside panes and sheets.
    static let spacingM: CGFloat = 12
    /// Page-level padding and section spacing.
    static let spacingL: CGFloat = 16

    static let masterMin: CGFloat = 280
    static let detailPaneMin: CGFloat = 230
    static let detailPaneIdeal: CGFloat = 310
    static let detailPaneMax: CGFloat = 360
    static let consoleHeight: CGFloat = 190
}
