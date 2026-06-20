import PlaidBarCore
import SwiftUI

/// **Dashboard** destination (2-column — IA §3.1/§5.1, `[⌘1]`).
///
/// A composed overview canvas with no master→detail relationship, so the shell
/// renders only this content column (no inspector). Drill-ins deep-link to other
/// destinations rather than opening a local third column.
///
/// Scaffold for the parallel Epics 4–7: today it shows the shared
/// `DestinationPlaceholder`; the real canvas (decomposed from `MainPopover`'s
/// dashboard body) lands in its epic by replacing this `body`. Owning its own
/// file means that epic never touches `AppShellView`.
struct DashboardDestinationView: View {
    var body: some View {
        DestinationPlaceholder(destination: .dashboard)
    }
}

#Preview {
    DashboardDestinationView()
}
