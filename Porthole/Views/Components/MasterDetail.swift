import SwiftUI

/// The list-plus-detail-pane layout shared by the Installed, Outdated, and
/// Search screens: master content on the left, a divider, and a width-clamped
/// detail pane on the right.
struct MasterDetail<Master: View, Detail: View>: View {
    @ViewBuilder var master: Master
    @ViewBuilder var detail: Detail

    var body: some View {
        HStack(spacing: 0) {
            master
                .frame(minWidth: Metrics.masterMin, maxWidth: .infinity)
            Divider()
            detail
                .frame(
                    minWidth: Metrics.detailPaneMin,
                    idealWidth: Metrics.detailPaneIdeal,
                    maxWidth: Metrics.detailPaneMax,
                    maxHeight: .infinity
                )
        }
    }
}
