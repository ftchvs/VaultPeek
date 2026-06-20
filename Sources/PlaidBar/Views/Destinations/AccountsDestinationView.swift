import PlaidBarCore
import SwiftUI

/// **Accounts** destination (3-column — IA §3.1/§5.9, `[⌘8]`).
///
/// Institution/account list → `AccountDetailFlyout` inspector (the existing,
/// proven master→detail). The shell renders this content column plus `Inspector`
/// in the detail column, which is content-gated and shows "Select an account"
/// when nothing is selected (IA §3.1).
///
/// Scaffold for the parallel Epics 4–7: both panes show the shared placeholders
/// today; the real institution/account list and `AccountDetailFlyout` inspector
/// land in this destination's epic by replacing the two bodies, never touching
/// `AppShellView`.
struct AccountsDestinationView: View {
    var body: some View {
        DestinationPlaceholder(destination: .accounts)
    }

    /// The detail-column (inspector) pane for Accounts.
    struct Inspector: View {
        var body: some View {
            DestinationInspectorPlaceholder(destination: .accounts)
        }
    }
}

#Preview("Content") {
    AccountsDestinationView()
}

#Preview("Inspector") {
    AccountsDestinationView.Inspector()
}
