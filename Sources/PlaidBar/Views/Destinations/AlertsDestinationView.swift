import PlaidBarCore
import SwiftUI

/// **Alerts** destination (3-column — IA §3.1/§5.8, `[⌘7]`).
///
/// Alert feed (list) → alert detail / rule editor (inspector). The shell renders
/// this content column plus `Inspector` in the detail column, which is
/// content-gated and shows "Select an alert" when nothing is selected (IA §3.1).
///
/// Scaffold for the parallel Epics 4–7: both panes show the shared placeholders
/// today; the real alert feed and detail/rule-editor inspector land in this
/// destination's epic by replacing the two bodies, never touching `AppShellView`.
struct AlertsDestinationView: View {
    var body: some View {
        DestinationPlaceholder(destination: .alerts)
    }

    /// The detail-column (inspector) pane for Alerts.
    struct Inspector: View {
        var body: some View {
            DestinationInspectorPlaceholder(destination: .alerts)
        }
    }
}

#Preview("Content") {
    AlertsDestinationView()
}

#Preview("Inspector") {
    AlertsDestinationView.Inspector()
}
