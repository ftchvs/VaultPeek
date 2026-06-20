import PlaidBarCore
import SwiftUI

/// **Transactions** destination (3-column — IA §3.1/§5.2).
///
/// The ledger: a table (list) → transaction inspector (detail). The shell
/// renders this content (table) column plus `Inspector` in the detail column,
/// which is content-gated and shows "Select a transaction" when nothing is
/// selected (IA §3.1).
///
/// Scaffold for the parallel Epics 4–7: both panes show the shared placeholders
/// today; the real `ReviewTableWindow` table engine and `TransactionDetailView`
/// inspector land in this destination's epic by replacing the two bodies, never
/// touching `AppShellView`.
struct TransactionsDestinationView: View {
    var body: some View {
        DestinationPlaceholder(destination: .transactions)
    }

    /// The detail-column (inspector) pane for Transactions.
    struct Inspector: View {
        var body: some View {
            DestinationInspectorPlaceholder(destination: .transactions)
        }
    }
}

#Preview("Content") {
    TransactionsDestinationView()
}

#Preview("Inspector") {
    TransactionsDestinationView.Inspector()
}
