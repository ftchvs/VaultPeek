import Foundation

/// Pure, `Sendable` view-model for the **spend donut + center total** (AND-537).
///
/// The donut visualizes *where this month's money went* by ``CategoryGroup``,
/// consuming the already-computed override-aware rollups in
/// ``CategoryDashboardPresentation`` — it never recomputes spend. Each slice is one
/// spending group's net total; the ring's center shows the overall spend total.
///
/// All display strings (slice/legend labels, share percentages, VoiceOver text, the
/// center total) are baked here so the SwiftUI view stays a thin renderer and every
/// label can be unit-tested without a host view. Meaning never rides on color alone:
/// each slice carries its group title, amount, and share as text (ACCESSIBILITY.md).
///
/// Slices are ordered spend-heaviest first (a stable tiebreak on
/// ``CategoryGroup/sortIndex`` keeps equal-spend ordering deterministic for
/// screenshots and tests), and shares are computed against the donut's *own* slice
/// total — which equals ``CategoryDashboardPresentation/totalSpent`` because the
/// presentation only ever contains spend groups (income / transfers are dropped
/// before aggregation), so the shares always sum to ~100%.
public struct SpendDonutModel: Sendable, Hashable {
    /// One donut slice — a spending ``CategoryGroup`` and its net current-month spend.
    public struct Slice: Sendable, Hashable, Identifiable {
        /// Stable identity (`group.rawValue`) — also the Swift Charts plot key.
        public let id: String
        public let group: CategoryGroup
        /// Net current-month spend for this group (already floored at `0`).
        public let amount: Double
        /// `amount / total`, in `0...1`; `0` when the donut total is `0`.
        public let fraction: Double
        /// Group title, e.g. `"Food & Dining"`.
        public var title: String { group.title }
        /// Pre-formatted currency amount, e.g. `"$420.00"`.
        public let amountText: String
        /// Pre-formatted share, e.g. `"34%"` (whole-percent, never color-only).
        public let shareText: String
        /// Legend / VoiceOver line: `"Food & Dining, $420.00, 34%"`.
        public let label: String

        public init(group: CategoryGroup, amount: Double, fraction: Double, currencyCode: String) {
            self.id = group.rawValue
            self.group = group
            self.amount = amount
            self.fraction = fraction
            let amountText = Formatters.currency(amount, format: .full, currencyCode: currencyCode)
            self.amountText = amountText
            let shareText = SpendDonutModel.shareText(fraction)
            self.shareText = shareText
            self.label = "\(group.title), \(amountText), \(shareText)"
        }
    }

    /// Slices, spend-heaviest first. Empty when there is no spend to show.
    public let slices: [Slice]
    /// Sum of every slice's spend — the figure shown in the ring's center.
    public let total: Double
    /// Pre-formatted center total, e.g. `"$1,234.00"`.
    public let totalText: String
    /// Short label rendered under the center total (`"Spent this month"`).
    public let centerCaption: String
    /// Currency code the amounts were formatted with (carried for the view).
    public let currencyCode: String

    /// Build the donut model from the dashboard rollups.
    ///
    /// - Parameters:
    ///   - presentation: the override-aware rollup the donut renders. Only groups
    ///     with positive spend become slices; income / transfers never carry spend so
    ///     they never appear.
    ///   - currencyCode: ISO code used to format every amount. Defaults to `"USD"`.
    public init(presentation: CategoryDashboardPresentation, currencyCode: String = "USD") {
        self.currencyCode = currencyCode
        self.centerCaption = "Spent this month"

        // Only groups that actually carry spend are slices. Sort spend-heaviest
        // first, breaking ties on the canonical display order so equal-spend groups
        // never reorder between builds (stable screenshots / tests).
        let spendingGroups = presentation.groups
            .filter { $0.spent > 0 }
            .sorted { lhs, rhs in
                if lhs.spent != rhs.spent { return lhs.spent > rhs.spent }
                return lhs.group.sortIndex < rhs.group.sortIndex
            }

        let total = spendingGroups.reduce(0) { $0 + $1.spent }
        self.total = total
        self.totalText = Formatters.currency(total, format: .full, currencyCode: currencyCode)

        self.slices = spendingGroups.map { rollup in
            let fraction = total > 0 ? rollup.spent / total : 0
            return Slice(
                group: rollup.group,
                amount: rollup.spent,
                fraction: fraction,
                currencyCode: currencyCode
            )
        }
    }

    /// True when there is no spend to chart.
    public var isEmpty: Bool { slices.isEmpty }

    /// Number of slices.
    public var sliceCount: Int { slices.count }

    /// One-line VoiceOver summary of the whole donut: total + every slice's group,
    /// amount, and share, so a screen-reader user gets the same breakdown the
    /// sighted legend shows — never color alone (ACCESSIBILITY.md).
    public var accessibilityLabel: String {
        guard !isEmpty else {
            return "Spending by category. No spending this month."
        }
        let breakdown = slices.map(\.label).joined(separator: ". ")
        return "Spending by category. \(totalText) spent this month across \(sliceCount) "
            + "\(sliceCount == 1 ? "group" : "groups"). \(breakdown)."
    }

    /// Whole-percent share string, e.g. `0.3412 -> "34%"`. A non-zero-but-tiny share
    /// floors to `"<1%"` rather than `"0%"` so a present slice never reads as absent.
    static func shareText(_ fraction: Double) -> String {
        let pct = fraction * 100
        if pct > 0, pct < 1 { return "<1%" }
        return Formatters.percent(pct, decimals: 0)
    }
}
