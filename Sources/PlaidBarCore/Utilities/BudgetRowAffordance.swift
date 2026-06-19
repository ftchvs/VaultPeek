import Foundation

/// The per-row "Set a budget" / "Edit" affordance on the Category Dashboard
/// (AND-541). Given a category and whether it currently carries a budget, this
/// pure value decides:
///
/// - whether the affordance should appear at all (income / transfer categories
///   can never be budgeted, so they get none — mirroring `BudgetEditorInput`),
/// - the call-to-action verb ("Set a budget" when unbudgeted, "Edit" when
///   budgeted) and its SF Symbol, and
/// - an accessibility label that always names *both* the category and the action,
///   so the control is unambiguous to VoiceOver (ACCESSIBILITY.md) even though
///   many such controls share one screen.
///
/// Lives in PlaidBarCore so the labels/visibility rules are `Sendable`, unit
/// tested without a view, and identical on the popover card and the detached
/// dashboard window. The view layer renders the result and, when tapped, opens
/// `BudgetEditorSheet` for `category` — it owns no copy of these rules.
public struct BudgetRowAffordance: Sendable, Hashable {
    /// What tapping the affordance does — both verbs open the same
    /// `BudgetEditorSheet`; only the framing differs.
    public enum Action: Sendable, Hashable {
        /// No saved budget yet — invite the user to create one.
        case setBudget
        /// A budget already exists — invite the user to change or clear it.
        case editBudget
    }

    public let category: SpendingCategory

    /// The resolved action, or `nil` when this category can't be budgeted.
    public let action: Action?

    /// Construct from an explicit budgeted flag.
    public init(category: SpendingCategory, isBudgeted: Bool) {
        self.category = category
        guard BudgetEditorInput.isBudgetable(category) else {
            self.action = nil
            return
        }
        self.action = isBudgeted ? .editBudget : .setBudget
    }

    /// Construct from a dashboard leaf — a budgeted leaf carries a `monthlyLimit`.
    public init(leaf: CategoryDashboardPresentation.Leaf) {
        self.init(category: leaf.category, isBudgeted: leaf.isBudgeted)
    }

    /// True when the affordance should be shown for this row.
    public var isAvailable: Bool { action != nil }

    /// The button title — empty when no affordance applies.
    public var title: String {
        switch action {
        case .setBudget: "Set a budget"
        case .editBudget: "Edit"
        case nil: ""
        }
    }

    /// The SF Symbol paired with the title (the verb is never carried by icon
    /// alone — the text label is always present).
    public var systemImage: String {
        switch action {
        case .setBudget: "plus.circle"
        case .editBudget: "slider.horizontal.3"
        case nil: ""
        }
    }

    /// A VoiceOver label that disambiguates *which* category this control acts on,
    /// since a dashboard renders one per row. Empty when no affordance applies.
    public var accessibilityLabel: String {
        switch action {
        case .setBudget: "Set a budget for \(category.displayName)"
        case .editBudget: "Edit budget for \(category.displayName)"
        case nil: ""
        }
    }
}
