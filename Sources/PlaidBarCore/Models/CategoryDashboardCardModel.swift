import Foundation

/// Pure, `Sendable` view-model for the **Category Dashboard card** (AND-539) — the
/// compact center-column surface in the popover that previews where this month's
/// money went and links out to the full detached dashboard window.
///
/// The card shows the donut (built from the same override-aware
/// ``CategoryDashboardPresentation`` the full dashboard uses — never a recompute,
/// Option A) plus the *top N* spending group rollups. This type owns
/// the "top N groups for the card" selection and every derived headline string so
/// the SwiftUI card stays a thin renderer and the selection / labels can be
/// unit-tested without a host view.
///
/// Top groups are the spend-heaviest ``CategoryDashboardPresentation/GroupRollup``
/// values (a stable tiebreak on ``CategoryGroup/sortIndex`` keeps equal-spend
/// ordering deterministic for screenshots and tests). Only groups that carry
/// positive spend can be "top groups"; a budgeted-but-unspent group never crowds
/// out a group the user actually spent in. When more groups exist than the card
/// shows, ``overflowCount`` reports how many are folded into the "Open dashboard"
/// affordance so the card can say "+3 more".
public struct CategoryDashboardCardModel: Sendable, Hashable {
    /// Default number of group rollups the card previews before overflowing into
    /// the full-dashboard link.
    public static let defaultTopGroupLimit = 3

    /// The donut model the card renders (same data as the full dashboard).
    public let donut: SpendDonutModel
    /// The top spending group rollups, spend-heaviest first (at most `topGroupLimit`).
    public let topGroups: [CategoryDashboardPresentation.GroupRollup]
    /// How many *spending* groups are not shown in ``topGroups`` (>= 0). Drives a
    /// "+N more" affordance on the open-dashboard link.
    public let overflowCount: Int
    /// Count of leaves over their individual budget across the whole month.
    public let overBudgetCount: Int
    /// Count of leaves in the nearing band (not yet over).
    public let nearingCount: Int
    /// Pre-formatted total spent this month, e.g. `"$1,234.00"` (same figure as the
    /// donut center). Carried so the card's header reads without a second format.
    public let totalSpentText: String
    /// ISO currency code amounts were formatted with (carried for the view).
    public let currencyCode: String

    /// Build the card model from the finished, override-aware dashboard rollup.
    ///
    /// - Parameters:
    ///   - presentation: the override-aware rollup (built once by
    ///     `CategoryDashboardBuilder`); the card never recomputes spend.
    ///   - currencyCode: ISO code used to format every amount. Defaults to `"USD"`.
    ///   - topGroupLimit: how many spending group rollups to preview. Values `< 1`
    ///     clamp to `0` (donut only, everything overflows).
    public init(
        presentation: CategoryDashboardPresentation,
        currencyCode: String = "USD",
        topGroupLimit: Int = CategoryDashboardCardModel.defaultTopGroupLimit
    ) {
        self.currencyCode = currencyCode
        self.donut = SpendDonutModel(presentation: presentation, currencyCode: currencyCode)
        self.overBudgetCount = presentation.overBudgetCount
        self.nearingCount = presentation.nearingCount
        self.totalSpentText = Formatters.currency(
            presentation.totalSpent,
            format: .full,
            currencyCode: currencyCode
        )

        // Only groups with real spend rank — a budgeted-but-unspent guardrail never
        // displaces a group the user actually spent in. Heaviest first, stable
        // tiebreak on canonical order so equal-spend groups never reorder.
        let spendingGroups = presentation.groups
            .filter { $0.spent > 0 }
            .sorted { lhs, rhs in
                if lhs.spent != rhs.spent { return lhs.spent > rhs.spent }
                return lhs.group.sortIndex < rhs.group.sortIndex
            }

        let limit = max(0, topGroupLimit)
        self.topGroups = Array(spendingGroups.prefix(limit))
        self.overflowCount = max(0, spendingGroups.count - limit)
    }

    /// True when there is no spend to preview (empty / first-run dataset).
    public var isEmpty: Bool { donut.isEmpty }

    /// True when at least one leaf needs attention (over or nearing) this month.
    public var hasAttention: Bool { overBudgetCount > 0 || nearingCount > 0 }

    /// Short, color-independent summary of budget pressure for the card subtitle,
    /// e.g. `"2 over budget"`, `"1 over · 3 nearing"`, or `"On track"`. Never relies
    /// on color (ACCESSIBILITY.md). `nil` when there is nothing to summarize because
    /// no row is budgeted (so the card omits the line rather than claiming "on
    /// track" for an unbudgeted month).
    public func attentionSummary(isBudgeted: Bool) -> String? {
        attentionSummary(isBudgeted: isBudgeted, privacyMaskEnabled: false)
    }

    /// Privacy-aware budget-pressure copy for surfaces that may render while
    /// Privacy Mask/App Lock is active. Exact over/nearing counts are behavioral
    /// finance metadata, so the masked variant keeps the risk state without the
    /// count.
    public func attentionSummary(isBudgeted: Bool, privacyMaskEnabled: Bool) -> String? {
        guard isBudgeted else { return nil }
        if overBudgetCount == 0, nearingCount == 0 { return "On track" }
        if privacyMaskEnabled {
            if overBudgetCount > 0, nearingCount > 0 { return "Over budget and nearing budget" }
            if overBudgetCount > 0 { return "Over budget" }
            return "Nearing budget"
        }
        var parts: [String] = []
        if overBudgetCount > 0 { parts.append("\(overBudgetCount) over budget") }
        if nearingCount > 0 { parts.append("\(nearingCount) nearing") }
        return parts.joined(separator: " · ")
    }

    /// `"+N more"` overflow caption for the open-dashboard link, or `nil` when the
    /// card already shows every spending group.
    public var overflowText: String? {
        overflowText(privacyMaskEnabled: false)
    }

    /// Privacy-aware overflow caption. The exact number of hidden spending groups
    /// is behavioral finance metadata, so masked surfaces use generic copy.
    public func overflowText(privacyMaskEnabled: Bool) -> String? {
        guard overflowCount > 0 else { return nil }
        return privacyMaskEnabled ? "More categories" : "+\(overflowCount) more"
    }
}
