import PlaidBarCore
import SwiftUI

/// **Review** destination (3-column — IA §3.1/§5.3, `[⌘2]`, the marquee
/// list ↔ detail triage flow).
///
/// The shell renders this content (list) column plus `Inspector` in the detail
/// column. The detail column is **content-gated, not existence-gated** (IA §3.1):
/// when nothing is selected the inspector shows the "Select an item to review"
/// prompt rather than collapsing.
///
/// Scaffold for the parallel Epics 4–7: both panes show the shared placeholders
/// today; the real `ReviewInboxView(embedded:)` list and triage inspector land in
/// this destination's epic by replacing the two bodies, never touching
/// `AppShellView`.
struct ReviewDestinationView: View {
    var body: some View {
        DestinationPlaceholder(destination: .review)
    }

    /// The detail-column (inspector) pane for Review.
    struct Inspector: View {
        var body: some View {
            DestinationInspectorPlaceholder(destination: .review)
        }
    }
}

#Preview("Content") {
    ReviewDestinationView()
}

#Preview("Inspector") {
    ReviewDestinationView.Inspector()
}
