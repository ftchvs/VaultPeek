import Foundation

/// A read-only, **dashboard-scale** preview of the user's savings ``Goal``s
/// (AND-730).
///
/// The Goals workspace owns the full list; the Dashboard only needs a compact
/// glance — the top few goals most worth seeing, plus a hint of how many more are
/// tracked. This pure value type performs that selection so the dashboard card
/// stays a thin surface and the "which goals lead" ordering is unit-tested at the
/// Core layer (CLAUDE.md: shared logic lives in `PlaidBarCore`).
///
/// Ordering surfaces the goals that most reward a glance: **behind-pace goals
/// first** (they need attention), then in-progress goals **closest to their
/// target** (the satisfying almost-there ones), with funded goals last. Ties fall
/// back to the same newest-first ordering the Goals list uses, so the dashboard
/// and the workspace never feel arbitrary relative to each other.
public struct DashboardGoalsPreview: Sendable, Equatable {
    /// The featured goals, already ordered and capped to the requested limit.
    public let goals: [Goal]
    /// The total number of goals the user has (before capping), so the card can
    /// say "+N more".
    public let totalGoalCount: Int
    /// How many goals are not shown in `goals` (`totalGoalCount - goals.count`).
    public let overflowCount: Int

    public init(goals: [Goal], totalGoalCount: Int, overflowCount: Int) {
        self.goals = goals
        self.totalGoalCount = totalGoalCount
        self.overflowCount = overflowCount
    }

    /// True when there are no goals to preview — the dashboard shows the quiet
    /// "set a savings goal" empty affordance in that case.
    public var isEmpty: Bool { totalGoalCount == 0 }

    /// "+N more goal(s)" footer copy when goals overflow the cap, else `nil`.
    /// Grammatically pluralized so the card never reads "1 more goals".
    public var overflowLabel: String? {
        guard overflowCount > 0 else { return nil }
        return overflowCount == 1 ? "1 more goal" : "\(overflowCount) more goals"
    }

    /// Generic goal title used while Privacy Mask is active. Goal names can carry
    /// real-world plan metadata ("House down payment", "Medical fund"), so the
    /// dashboard must not render them while masked.
    public static let maskedGoalTitle = "Goal hidden"

    /// Generic overflow copy used while Privacy Mask is active. The exact hidden
    /// goal count is metadata, so the dashboard keeps the route affordance without
    /// exposing `overflowCount`.
    public static let maskedOverflowLabel = "More goals"

    /// Dashboard-safe title copy for a featured goal.
    public static func displayTitle(for goal: Goal, isMasked: Bool) -> String {
        isMasked ? maskedGoalTitle : goal.name
    }

    /// Dashboard-safe overflow copy. Unmasked copy preserves the existing
    /// pluralized "+N more" semantics; masked copy withholds the exact count.
    public func displayOverflowLabel(isMasked: Bool) -> String? {
        guard overflowCount > 0 else { return nil }
        return isMasked ? Self.maskedOverflowLabel : overflowLabel
    }

    /// The default number of goals the dashboard features.
    public static let defaultLimit = 3

    /// Build a dashboard preview from the full goal list, evaluating pace `asOf` a
    /// reference date and capping at `limit` featured goals.
    public static func make(
        from goals: [Goal],
        limit: Int = defaultLimit,
        asOf now: Date = Date()
    ) -> DashboardGoalsPreview {
        let cap = max(limit, 0)
        let ranked = goals.sorted { lhs, rhs in
            let l = priority(of: lhs, asOf: now)
            let r = priority(of: rhs, asOf: now)
            if l != r { return l < r }
            // Within the same bucket, the more-complete goal leads (closest to
            // target for in-progress; both 1.0 for funded — falls through to date).
            if lhs.fractionComplete != rhs.fractionComplete {
                return lhs.fractionComplete > rhs.fractionComplete
            }
            // Stable tie-break: newest-created first, then name, then id — matching
            // the Goals list's display order.
            if lhs.createdAt != rhs.createdAt { return lhs.createdAt > rhs.createdAt }
            if lhs.name != rhs.name { return lhs.name < rhs.name }
            return lhs.id.uuidString < rhs.id.uuidString
        }
        let featured = Array(ranked.prefix(cap))
        return DashboardGoalsPreview(
            goals: featured,
            totalGoalCount: goals.count,
            overflowCount: max(goals.count - featured.count, 0)
        )
    }

    /// Lower sorts earlier: behind-pace (0) lead, then in-progress (1), then funded
    /// (2). Behind goals need attention; funded ones are done, so they sit last.
    private static func priority(of goal: Goal, asOf now: Date) -> Int {
        if goal.isComplete { return 2 }
        return goal.pace(asOf: now) == .behind ? 0 : 1
    }
}
