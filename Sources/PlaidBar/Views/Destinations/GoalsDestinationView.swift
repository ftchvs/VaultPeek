import PlaidBarCore
import SwiftUI

/// **Goals** destination (3-column — IA §3.1/§5.6, `[⌘5]`).
///
/// Goal list → goal detail/progress (and new-goal editor) inspector. The shell
/// renders this content column plus `Inspector` in the detail column, which is
/// content-gated and shows "Select a goal" when nothing is selected (IA §3.1).
///
/// Scaffold for the parallel Epics 4–7: both panes show the shared placeholders
/// today; the real goal list and progress/editor inspector land in this
/// destination's epic by replacing the two bodies, never touching `AppShellView`.
struct GoalsDestinationView: View {
    var body: some View {
        DestinationPlaceholder(destination: .goals)
    }

    /// The detail-column (inspector) pane for Goals.
    struct Inspector: View {
        var body: some View {
            DestinationInspectorPlaceholder(destination: .goals)
        }
    }
}

#Preview("Content") {
    GoalsDestinationView()
}

#Preview("Inspector") {
    GoalsDestinationView.Inspector()
}
