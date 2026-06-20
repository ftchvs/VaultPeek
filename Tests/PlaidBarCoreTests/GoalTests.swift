import Foundation
import Testing
@testable import PlaidBarCore

@Suite("Goal progress math (AND-606)")
struct GoalTests {
    private func date(_ offsetDays: Int, from base: Date = Date(timeIntervalSince1970: 1_700_000_000)) -> Date {
        base.addingTimeInterval(Double(offsetDays) * 86_400)
    }

    // MARK: - fractionComplete / percentComplete

    @Test("Fraction and percent reflect contribution over target")
    func basicProgress() {
        let goal = Goal(name: "Fund", targetAmount: 1000, contributedAmount: 250)
        #expect(goal.fractionComplete == 0.25)
        #expect(goal.percentComplete == 25)
    }

    @Test("Percent rounds to the nearest integer")
    func percentRounds() {
        let goal = Goal(name: "Fund", targetAmount: 3, contributedAmount: 1) // 33.33%
        #expect(goal.percentComplete == 33)
        let goal2 = Goal(name: "Fund", targetAmount: 8, contributedAmount: 7) // 87.5% -> 88
        #expect(goal2.percentComplete == 88)
    }

    @Test("Over-contribution clamps to 100% and zero remaining")
    func overContributionClamps() {
        let goal = Goal(name: "Fund", targetAmount: 1000, contributedAmount: 1500)
        #expect(goal.fractionComplete == 1.0)
        #expect(goal.percentComplete == 100)
        #expect(goal.remainingAmount == 0)
        #expect(goal.isComplete)
    }

    @Test("A non-positive target never divides by zero")
    func zeroTargetGuard() {
        let goal = Goal(name: "Bad", targetAmount: 0, contributedAmount: 50)
        #expect(goal.fractionComplete == 0)
        #expect(goal.percentComplete == 0)
        #expect(!goal.isComplete, "A zero-target goal is never complete")
    }

    @Test("Remaining is target minus contributed, never negative")
    func remaining() {
        #expect(Goal(name: "F", targetAmount: 1000, contributedAmount: 300).remainingAmount == 700)
        #expect(Goal(name: "F", targetAmount: 1000, contributedAmount: 1000).remainingAmount == 0)
        #expect(Goal(name: "F", targetAmount: 1000, contributedAmount: 1200).remainingAmount == 0)
    }

    @Test("isComplete only when contributed reaches the target")
    func isComplete() {
        #expect(!Goal(name: "F", targetAmount: 1000, contributedAmount: 999).isComplete)
        #expect(Goal(name: "F", targetAmount: 1000, contributedAmount: 1000).isComplete)
    }

    // MARK: - pace

    @Test("A goal with no target date has no deadline pace")
    func paceNoDeadline() {
        let goal = Goal(name: "F", targetAmount: 1000, targetDate: nil, contributedAmount: 100)
        #expect(goal.pace(asOf: Date()) == .noDeadline)
    }

    @Test("A complete goal is always on track, even past its deadline")
    func paceCompleteIsOnTrack() {
        let created = date(0)
        let goal = Goal(
            name: "F",
            targetAmount: 1000,
            targetDate: date(30),
            contributedAmount: 1000,
            createdAt: created
        )
        #expect(goal.pace(asOf: date(60)) == .onTrack)
    }

    @Test("At the linear pace (halfway through, half funded) is on track")
    func paceOnTrackLinear() {
        let created = date(0)
        let goal = Goal(
            name: "F",
            targetAmount: 1000,
            targetDate: date(100),
            contributedAmount: 500,
            createdAt: created
        )
        #expect(goal.pace(asOf: date(50)) == .onTrack)
    }

    @Test("Below the linear pace is behind")
    func paceBehind() {
        let created = date(0)
        let goal = Goal(
            name: "F",
            targetAmount: 1000,
            targetDate: date(100),
            contributedAmount: 100, // expected ~500 by day 50
            createdAt: created
        )
        #expect(goal.pace(asOf: date(50)) == .behind)
    }

    @Test("Ahead of the linear pace is on track")
    func paceAhead() {
        let created = date(0)
        let goal = Goal(
            name: "F",
            targetAmount: 1000,
            targetDate: date(100),
            contributedAmount: 800, // expected ~500 by day 50
            createdAt: created
        )
        #expect(goal.pace(asOf: date(50)) == .onTrack)
    }

    @Test("Past the deadline while still short is behind")
    func pacePastDeadlineShort() {
        let created = date(0)
        let goal = Goal(
            name: "F",
            targetAmount: 1000,
            targetDate: date(30),
            contributedAmount: 900,
            createdAt: created
        )
        #expect(goal.pace(asOf: date(45)) == .behind)
    }

    @Test("A target date at or before creation, while short, is behind")
    func paceDegenerateDeadline() {
        let created = date(10)
        let goal = Goal(
            name: "F",
            targetAmount: 1000,
            targetDate: date(10),
            contributedAmount: 500,
            createdAt: created
        )
        #expect(goal.pace(asOf: date(11)) == .behind)
    }

    // MARK: - Codable

    @Test("Goal round-trips through Codable")
    func codable() throws {
        let goal = Goal(
            name: "Vacation",
            targetAmount: 2500,
            targetDate: date(120),
            linkedCategory: .travel,
            contributedAmount: 600,
            createdAt: date(0)
        )
        let data = try JSONEncoder().encode(goal)
        let decoded = try JSONDecoder().decode(Goal.self, from: data)
        #expect(decoded == goal)
    }
}
