import Foundation

/// Pure decision logic for the one-tap "accept suggested limit" affordance —
/// the "ghost guardrails" UX (AND-542).
///
/// The dashboard renders history-derived suggestions (`CategoryBudgetPresentation`
/// items flagged `isSuggested`) as faint guardrails for categories the user has
/// not yet budgeted. A single tap should promote that suggestion into a saved
/// budget by calling `AppState.setCategoryBudget(category, amount:)` — no sheet, no
/// typing.
///
/// All of the "is this a legal one-tap accept, and what would it persist" logic
/// lives here as a stateless `enum` so it is `Sendable`, testable without a view,
/// and identical wherever the affordance appears. The view only renders the
/// outcome and dispatches the resulting `setCategoryBudget` call.
///
/// The rules mirror the rest of the budget surface so an accept can never write a
/// budget the editor would reject:
/// - the item must be a *suggestion* (`isSuggested`) — an explicit, already-saved
///   limit has nothing to accept;
/// - the category must be budgetable — income / transfer categories are never
///   spend (mirrors `BudgetEditorInput.isBudgetable` /
///   `CategoryBudgetPlanner.excludedCategories` / the server's `budgetableCategory`);
/// - the suggested limit must be a positive, finite amount;
/// - the category must not already carry an explicit saved budget (a saved limit
///   wins — `mergedPresentation` already filters these out, but making the rule
///   explicit keeps the accept safe even if a caller passes a stale presentation).
public enum SuggestedBudgetAcceptance {
    /// Outcome of evaluating whether a suggested item can be accepted in one tap,
    /// and what it would persist.
    public enum Outcome: Sendable, Hashable {
        /// The suggestion is acceptable: persist `amount` as `category`'s monthly
        /// limit via `AppState.setCategoryBudget`.
        case accept(category: SpendingCategory, amount: Double)
        /// The item is an explicit (already-saved) budget, not a suggestion — there
        /// is nothing to accept.
        case notSuggested
        /// The category cannot carry a budget (income / transfer).
        case categoryNotBudgetable
        /// The suggested limit is not a positive, finite amount.
        case invalidLimit
        /// The category already has an explicit saved budget; the saved limit wins.
        case alreadyBudgeted

        /// True when this outcome is something the user can accept with one tap.
        public var isAcceptable: Bool {
            if case .accept = self { return true }
            return false
        }

        /// The amount a one-tap accept would persist, or `nil` when not acceptable.
        public var acceptedAmount: Double? {
            if case let .accept(_, amount) = self { return amount }
            return nil
        }

        /// The category a one-tap accept would budget, or `nil` when not acceptable.
        public var acceptedCategory: SpendingCategory? {
            if case let .accept(category, _) = self { return category }
            return nil
        }
    }

    /// Decide whether `item` can be accepted in one tap given the user's current
    /// `existingBudgets` (the explicit, saved limits — `AppState.categoryBudgets`).
    ///
    /// `existingBudgets` defaults to empty for callers that have already filtered
    /// suggestions against saved budgets; passing the live map makes the
    /// "saved limit wins" guard authoritative. A non-positive existing limit is
    /// treated as unset (no saved budget), matching `setCategoryBudget`, which
    /// removes a budget on a non-positive amount.
    public static func evaluate(
        item: CategoryBudgetPresentation.Item,
        existingBudgets: [SpendingCategory: Double] = [:]
    ) -> Outcome {
        guard item.isSuggested else { return .notSuggested }
        guard isBudgetable(item.category) else { return .categoryNotBudgetable }
        guard item.monthlyLimit > 0, item.monthlyLimit.isFinite else { return .invalidLimit }
        if let existing = existingBudgets[item.category], existing > 0 {
            return .alreadyBudgeted
        }
        return .accept(category: item.category, amount: item.monthlyLimit)
    }

    /// Whether a category can carry a budget. Kept in lock-step with
    /// `BudgetEditorInput.isBudgetable` / `CategoryBudgetPlanner.excludedCategories`
    /// so the accept affordance and the editor agree on which categories are spend.
    public static func isBudgetable(_ category: SpendingCategory) -> Bool {
        BudgetEditorInput.isBudgetable(category)
    }
}
