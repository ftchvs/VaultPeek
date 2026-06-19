import Foundation

/// Pure, view-agnostic presentation for a single category-dashboard status bar
/// (AND-538 / sub-issues 557 leaf, 558 group rollup).
///
/// Both a ``CategoryDashboardPresentation/Leaf`` and a
/// ``CategoryDashboardPresentation/GroupRollup`` carry the same four numbers —
/// `spent`, an optional `monthlyLimit`, an optional `fractionUsed`, and an
/// optional ``CategoryBudgetStatus`` — so this single value type drives the
/// capsule fill, the accessibility sentence, and the SPENT / BUDGET / LEFT
/// summary for both row kinds. Leaf and group status are independent: a group
/// can be `.over` while every one of its leaves is `.under`, and this model
/// reflects exactly the status it is handed.
///
/// Status is always carried as text + symbol (via ``CategoryBudgetStatus``),
/// never color alone (ACCESSIBILITY.md). When there is no budget the model
/// exposes an explicit "No budget set" verdict rather than a misleading
/// "under" band, so an empty / first-run row never reads as on-track.
public struct CategoryStatusBarModel: Sendable, Hashable {
    /// Net current-month spend for the row (already floored at 0 by the builder).
    public let spent: Double
    /// The monthly limit when budgeted; `nil` = no budget for this row.
    public let monthlyLimit: Double?
    /// `spent / monthlyLimit`, floored at 0; `nil` when there is no budget.
    public let fractionUsed: Double?
    /// Budget band; `nil` when there is no budget.
    public let status: CategoryBudgetStatus?
    /// Monthly-equivalent committed recurring spend for the row; `nil` when no
    /// recurring stream maps here, so the dashed ghost segment is hidden (AND-559).
    public let committed: Double?

    public init(
        spent: Double,
        monthlyLimit: Double?,
        fractionUsed: Double?,
        status: CategoryBudgetStatus?,
        committed: Double? = nil
    ) {
        self.spent = spent
        self.monthlyLimit = monthlyLimit
        self.fractionUsed = fractionUsed
        self.status = status
        self.committed = committed
    }

    /// Build from a dashboard leaf rollup.
    public init(leaf: CategoryDashboardPresentation.Leaf) {
        self.init(
            spent: leaf.spent,
            monthlyLimit: leaf.monthlyLimit,
            fractionUsed: leaf.fractionUsed,
            status: leaf.status,
            committed: leaf.committed
        )
    }

    /// Build from a dashboard group rollup.
    public init(group: CategoryDashboardPresentation.GroupRollup) {
        self.init(
            spent: group.spent,
            monthlyLimit: group.monthlyLimit,
            fractionUsed: group.fractionUsed,
            status: group.status,
            committed: group.committed
        )
    }

    /// True when this row tracks a monthly limit.
    public var isBudgeted: Bool { monthlyLimit != nil }

    /// Fraction of the capsule track to fill, clamped to `0...1`.
    ///
    /// An over-budget row pins the bar full (the *amount* of overspend is in the
    /// text, not by overflowing the track). An unbudgeted row has no meaningful
    /// fill, so it reads `0` — paired with the ``trackOnly`` flag the view can
    /// render an empty track instead of a misleading sliver.
    public var fillFraction: Double {
        guard let fraction = fractionUsed else { return 0 }
        return min(1, max(0, fraction))
    }

    /// True when there is no budget, so the view should draw an empty track and
    /// the "No budget set" verdict rather than a status band.
    public var trackOnly: Bool { monthlyLimit == nil }

    /// `monthlyLimit - spent` when budgeted; `nil` otherwise. Negative once over.
    public var remaining: Double? {
        monthlyLimit.map { $0 - spent }
    }

    /// Short verdict text — the budget band's label when budgeted, else an
    /// explicit no-budget verdict (never silently "on track").
    public var statusText: String {
        status?.label ?? "No budget set"
    }

    /// SF Symbol that carries the verdict without color. A budgeted row uses the
    /// band's glyph; an unbudgeted row uses a neutral "no gauge" symbol.
    public var statusIconName: String {
        status?.iconName ?? "minus.circle"
    }

    /// `"83%"`-style usage label for a budgeted row; `nil` when unbudgeted.
    public func percentUsedText(decimals: Int = 0) -> String? {
        fractionUsed.map { Formatters.percent($0 * 100, decimals: decimals) }
    }

    /// Share of the budget already committed to recurring bills, clamped to
    /// `0...1`. `nil` when unbudgeted or no recurring stream maps here — so the
    /// view hides the dashed ghost segment and the accessibility sentence omits it
    /// (AND-559).
    public var committedFraction: Double? {
        guard let limit = monthlyLimit, limit > 0, let committed, committed > 0 else { return nil }
        return min(1, max(0, committed / limit))
    }

    /// `"30%"`-style label for the committed-recurring share; `nil` when there is
    /// no ghost segment. Percent (not currency) keeps it safe under Privacy Mask.
    public func committedPercentText(decimals: Int = 0) -> String? {
        committedFraction.map { Formatters.percent($0 * 100, decimals: decimals) }
    }

    /// A single VoiceOver sentence describing the whole row: the spend, the
    /// budget context, and the verdict. The caller prefixes the row's name
    /// (category or group) and may substitute masked currency strings.
    ///
    /// Both currency arguments are pre-rendered by the view so the same sentence
    /// works under Privacy Mask (where they are dots) and in the clear.
    public func accessibilityDescription(
        spentText: String,
        limitText: String?
    ) -> String {
        guard isBudgeted, let limitText, let status else {
            return "\(spentText) spent. No budget set."
        }
        let percentClause = percentUsedText().map { ", \($0) of budget" } ?? ""
        // The dashed ghost segment is also voiced as text so it never reads through
        // pattern alone (ACCESSIBILITY.md). Percent keeps it Privacy-Mask safe.
        let committedClause = committedPercentText().map {
            " \($0) of the budget is committed to recurring bills."
        } ?? ""
        return "\(spentText) of \(limitText)\(percentClause). \(status.label).\(committedClause)"
    }
}
