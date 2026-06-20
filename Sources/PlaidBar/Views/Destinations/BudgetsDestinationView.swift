import PlaidBarCore
import SwiftUI

/// **Budgets** destination (3-column — IA §3.1/§5.4, `[⌘3]`).
///
/// Category tree/table (list) → budget editor inspector (detail). The shell
/// renders this content column plus `Inspector` in the detail column, which is
/// content-gated and shows "Select a category" when nothing is selected
/// (IA §3.1).
///
/// Scaffold for the parallel Epics 4–7: both panes show the shared placeholders
/// today; the real `CategoryTreeView` list and budget-editor inspector land in
/// this destination's epic by replacing the two bodies, never touching
/// `AppShellView`.
struct BudgetsDestinationView: View {
    var body: some View {
        DestinationPlaceholder(destination: .budgets)
    }

    /// The detail-column (inspector) pane for Budgets.
    struct Inspector: View {
        var body: some View {
            DestinationInspectorPlaceholder(destination: .budgets)
        }
    }
}

#Preview("Content") {
    BudgetsDestinationView()
}

#Preview("Inspector") {
    BudgetsDestinationView.Inspector()
}
