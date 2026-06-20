import PlaidBarCore
import SwiftUI

/// **Insights** destination (2-column — IA §3.1/§5.7, `[⌘6]`).
///
/// A reading feed of receipts + weekly review; selecting a receipt expands in
/// place rather than filling a detail column, so the shell renders only this
/// content column (no inspector).
///
/// Scaffold for the parallel Epics 4–7: today it shows the shared
/// `DestinationPlaceholder`; the real feed lands in its epic by replacing this
/// `body`, without touching `AppShellView`.
struct InsightsDestinationView: View {
    var body: some View {
        DestinationPlaceholder(destination: .insights)
    }
}

#Preview {
    InsightsDestinationView()
}
