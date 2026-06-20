import PlaidBarCore
import SwiftUI

/// The window-first **Dashboard** recurring-obligations card content (AND-624).
///
/// Surface only — it re-hosts the same ``RecurringObligationsSection`` rows the
/// popover's Wealth Summary flyout shows, over the same
/// ``RecurringObligationsPresentation`` Core engine (`RecurringDetector` finds
/// the streams; this view never detects). It is meant to sit *inside* a
/// ``WindowSection`` (which supplies the title + card chrome), so unlike the
/// popover's self-carding section it renders only the rows — and, when nothing is
/// detected, a quiet empty line instead of self-hiding, so the dashboard grid
/// keeps a uniform card rather than a hole.
///
/// Honors Privacy Mask the same way the re-hosted rows do (amounts and the
/// monthly total run through `PrivacyMaskPresentation`). The "open" affordance
/// deep-links to **Planning → Recurring** rather than opening a local inspector
/// (the 2-column dashboard has none).
struct DashboardRecurringCard: View {
    @Environment(AppState.self) private var appState
    /// Deep-links to the recurring workspace (Planning → Recurring).
    let onOpen: () -> Void

    private var presentation: RecurringObligationsPresentation {
        RecurringObligationsPresentation.make(
            from: appState.recurringTransactions,
            asOf: Date()
        )
    }

    var body: some View {
        let presentation = presentation
        if presentation.isEmpty {
            Label("No recurring charges detected yet.", systemImage: "repeat")
                .windowSupportingText()
                .frame(maxWidth: .infinity, alignment: .leading)
                .accessibilityElement(children: .combine)
        } else {
            RecurringObligationsSection(
                presentation: presentation,
                onOpenSubscriptions: onOpen,
                privacyMaskEnabled: appState.shouldMaskFinancialValues
            )
        }
    }
}

#Preview {
    DashboardRecurringCard(onOpen: {})
        .environment(AppState())
        .padding()
        .frame(width: 360)
}
