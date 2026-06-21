import Foundation
import Testing
@testable import PlaidBarCore

@Suite("Goals summary rollup (AND-606)")
struct GoalsSummaryTests {
    private let base = Date(timeIntervalSince1970: 1_700_000_000)
    private func day(_ n: Int) -> Date { base.addingTimeInterval(Double(n) * 86_400) }

    @Test("Empty goal list summarizes to empty")
    func empty() {
        let summary = GoalsSummary.make(from: [])
        #expect(summary.isEmpty)
        #expect(summary.goalCount == 0)
        #expect(summary.overallPercent == 0)
        #expect(summary.overallFraction == 0)
    }

    @Test("Totals sum across goals; overall percent is amount-weighted")
    func totals() {
        let goals = [
            Goal(name: "A", targetAmount: 1000, contributedAmount: 250),
            Goal(name: "B", targetAmount: 3000, contributedAmount: 750),
        ]
        let summary = GoalsSummary.make(from: goals)
        #expect(summary.goalCount == 2)
        #expect(summary.totalSaved == 1000)
        #expect(summary.totalTarget == 4000)
        #expect(summary.overallPercent == 25) // 1000/4000
    }

    @Test("Funded and behind counts are computed against pace")
    func fundedAndBehind() {
        let goals = [
            // Funded
            Goal(name: "Done", targetAmount: 500, contributedAmount: 500, createdAt: day(0)),
            // Behind: halfway through the window but barely funded
            Goal(
                name: "Behind",
                targetAmount: 1000,
                targetDate: day(100),
                contributedAmount: 50,
                createdAt: day(0)
            ),
            // On track: no deadline, partial
            Goal(name: "OnTrack", targetAmount: 1000, contributedAmount: 100, createdAt: day(0)),
        ]
        let summary = GoalsSummary.make(from: goals, asOf: day(50))
        #expect(summary.fundedCount == 1)
        #expect(summary.behindCount == 1)
    }

    @Test("Overall fraction clamps to 1 when over-funded in aggregate")
    func overFundedClamps() {
        let goals = [
            Goal(name: "A", targetAmount: 100, contributedAmount: 200),
        ]
        let summary = GoalsSummary.make(from: goals)
        #expect(summary.overallFraction == 1.0)
        #expect(summary.overallPercent == 100)
    }

    @Test("Total remaining is per-goal clamped — an over-funded goal can't mask another's shortfall")
    func totalRemainingPerGoalClamped() {
        let goals = [
            // Over-funded: contributes 0 to remaining (not −500).
            Goal(name: "Over", targetAmount: 1000, contributedAmount: 1500),
            // Untouched: a genuine 1000 shortfall.
            Goal(name: "Behind", targetAmount: 1000, contributedAmount: 0),
        ]
        let summary = GoalsSummary.make(from: goals)
        // Per-goal clamp: max(1000−1500,0) + max(1000−0,0) == 0 + 1000.
        #expect(summary.totalRemaining == 1000)
        // The naive flat-totals formula would (wrongly) report 500.
        #expect(summary.totalTarget - summary.totalSaved == 500)
        // Overall fraction still clamps to 1 (totalSaved 1500 / totalTarget 2000 = 0.75).
        #expect(summary.overallFraction == 0.75)
    }
}
