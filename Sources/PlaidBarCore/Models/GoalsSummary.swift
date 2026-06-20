import Foundation

/// A read-only rollup of a user's ``Goal``s for the Planning destination's
/// goals-contribution overview (AND-606).
///
/// Pure value type, unit-tested in Core: it reduces the goal list into the
/// aggregate figures the Planning canvas previews (total saved vs total target,
/// overall progress, and how many goals are funded / behind), so Planning and the
/// Goals destination can never disagree on the headline numbers.
public struct GoalsSummary: Sendable, Equatable {
    /// Total number of goals.
    public let goalCount: Int
    /// Sum of every goal's contributed amount.
    public let totalSaved: Double
    /// Sum of every goal's target amount.
    public let totalTarget: Double
    /// Goals that have reached their target.
    public let fundedCount: Int
    /// Goals behind their target-date pace (excludes funded and no-deadline goals).
    public let behindCount: Int

    public init(
        goalCount: Int,
        totalSaved: Double,
        totalTarget: Double,
        fundedCount: Int,
        behindCount: Int
    ) {
        self.goalCount = goalCount
        self.totalSaved = totalSaved
        self.totalTarget = totalTarget
        self.fundedCount = fundedCount
        self.behindCount = behindCount
    }

    /// True when there are no goals to summarize (Planning self-hides / shows the
    /// "coming soon"-style empty state in that case).
    public var isEmpty: Bool { goalCount == 0 }

    /// Overall progress across all goals as a fraction in `0...1`, weighted by
    /// amount (total saved / total target). Guards a zero total.
    public var overallFraction: Double {
        guard totalTarget > 0 else { return 0 }
        return min(max(totalSaved / totalTarget, 0), 1)
    }

    /// Overall progress as a whole-number percent in `0...100`.
    public var overallPercent: Int {
        Int((overallFraction * 100).rounded())
    }

    /// Build the summary from a goal list, evaluating pace `asOf` a reference date.
    public static func make(from goals: [Goal], asOf now: Date = Date()) -> GoalsSummary {
        var totalSaved = 0.0
        var totalTarget = 0.0
        var fundedCount = 0
        var behindCount = 0

        for goal in goals {
            totalSaved += goal.contributedAmount
            totalTarget += goal.targetAmount
            if goal.isComplete {
                fundedCount += 1
            } else if goal.pace(asOf: now) == .behind {
                behindCount += 1
            }
        }

        return GoalsSummary(
            goalCount: goals.count,
            totalSaved: totalSaved,
            totalTarget: totalTarget,
            fundedCount: fundedCount,
            behindCount: behindCount
        )
    }
}
