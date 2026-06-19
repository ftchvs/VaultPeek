import PlaidBarCore
import SwiftUI

/// One-tap "accept suggested limit" affordance — the "ghost guardrails" UX
/// (AND-542, spec §3/§4).
///
/// Given a `CategoryBudgetPresentation.Item` that is a history-derived *suggestion*
/// for a budgetable category the user has not yet budgeted, this renders a single
/// button that promotes the suggestion into a saved budget via
/// `AppState.setCategoryBudget(category, amount:)` — no sheet, no typing.
///
/// The decision of whether the affordance is offered, and what it would persist,
/// is the pure `SuggestedBudgetAcceptance` (income / transfer rejected, positive
/// finite limit required, an already-saved budget wins). This view only renders the
/// outcome and dispatches the call, so it stays trivially correct and the rules are
/// unit-tested without a view. When the item is not acceptable the view renders
/// nothing.
///
/// Accessibility: the suggested amount is carried by text (not color), the button
/// has an explicit descriptive label, and the in-flight state is announced.
struct SuggestedBudgetAcceptButton: View {
    /// The suggested presentation item to (maybe) offer for one-tap accept.
    let item: CategoryBudgetPresentation.Item
    /// The user's current explicit budgets, so an already-saved category is never
    /// re-accepted. Defaults to empty for callers that pre-filter suggestions.
    var existingBudgets: [SpendingCategory: Double] = [:]

    @Environment(AppState.self) private var appState

    /// True while the accept network round-trip is in flight.
    @State private var isAccepting = false

    /// The pure accept decision for this item, recomputed every render.
    private var outcome: SuggestedBudgetAcceptance.Outcome {
        SuggestedBudgetAcceptance.evaluate(item: item, existingBudgets: existingBudgets)
    }

    var body: some View {
        if case let .accept(category, amount) = outcome {
            Button {
                Task { await accept(category: category, amount: amount) }
            } label: {
                Label(
                    "Set \(Formatters.currency(amount)) limit",
                    systemImage: "wand.and.stars"
                )
                .font(.caption)
            }
            .buttonStyle(.borderless)
            .disabled(isAccepting)
            .accessibilityLabel(
                "Accept suggested \(Formatters.currency(amount)) monthly budget for \(category.displayName)"
            )
            .accessibilityHint("Saves this as the monthly limit")
            .accessibilityValue(isAccepting ? "Saving" : "")
        }
    }

    private func accept(category: SpendingCategory, amount: Double) async {
        guard !isAccepting else { return }
        isAccepting = true
        await appState.setCategoryBudget(category, amount: amount)
        isAccepting = false
    }
}
