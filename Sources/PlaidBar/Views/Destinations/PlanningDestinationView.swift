import PlaidBarCore
import SwiftUI

/// **Planning** destination (2-column — IA §3.1/§5.5, `[⌘4]`).
///
/// A composed analytical canvas (forecast + recurring + income flow); its
/// sub-sections switch via a segmented control, not a master list, so the shell
/// renders only this content column (no inspector).
///
/// Scaffold for the parallel Epics 4–7: today it shows the shared
/// `DestinationPlaceholder`; the real canvas lands in its epic by replacing this
/// `body`, without touching `AppShellView`.
struct PlanningDestinationView: View {
    var body: some View {
        DestinationPlaceholder(destination: .planning)
    }
}

#Preview {
    PlanningDestinationView()
}
