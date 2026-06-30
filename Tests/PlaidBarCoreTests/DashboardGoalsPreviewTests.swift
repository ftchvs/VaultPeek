import Foundation
import Testing
@testable import PlaidBarCore

@Suite("Dashboard goals preview (AND-730)")
struct DashboardGoalsPreviewTests {
    private let base = Date(timeIntervalSince1970: 1_700_000_000)
    private func day(_ n: Int) -> Date { base.addingTimeInterval(Double(n) * 86_400) }

    @Test("Empty goal list previews as empty")
    func empty() {
        let preview = DashboardGoalsPreview.make(from: [], asOf: base)
        #expect(preview.isEmpty)
        #expect(preview.goals.isEmpty)
        #expect(preview.totalGoalCount == 0)
        #expect(preview.overflowCount == 0)
    }

    @Test("Caps the featured goals at the limit and reports the overflow")
    func capsAndReportsOverflow() {
        let goals = (0..<5).map { i in
            Goal(name: "G\(i)", targetAmount: 1000, contributedAmount: Double(i) * 100, createdAt: day(i))
        }
        let preview = DashboardGoalsPreview.make(from: goals, limit: 3, asOf: base)
        #expect(preview.goals.count == 3)
        #expect(preview.totalGoalCount == 5)
        #expect(preview.overflowCount == 2)
        #expect(!preview.isEmpty)
    }

    @Test("Fewer goals than the limit reports no overflow")
    func noOverflowWhenFew() {
        let goals = [
            Goal(name: "A", targetAmount: 1000, contributedAmount: 250, createdAt: day(0)),
            Goal(name: "B", targetAmount: 2000, contributedAmount: 500, createdAt: day(1)),
        ]
        let preview = DashboardGoalsPreview.make(from: goals, limit: 3, asOf: base)
        #expect(preview.goals.count == 2)
        #expect(preview.totalGoalCount == 2)
        #expect(preview.overflowCount == 0)
    }

    @Test("Behind-pace goals are surfaced ahead of comfortable ones")
    func behindFirst() {
        // A: on track (no deadline). B: behind pace. C: funded.
        let onTrack = Goal(name: "A", targetAmount: 1000, contributedAmount: 100, createdAt: day(0))
        let behind = Goal(
            name: "B",
            targetAmount: 1000,
            targetDate: day(100),
            contributedAmount: 50,
            createdAt: day(0)
        )
        let funded = Goal(name: "C", targetAmount: 500, contributedAmount: 500, createdAt: day(0))
        let preview = DashboardGoalsPreview.make(from: [onTrack, behind, funded], limit: 1, asOf: day(50))
        #expect(preview.goals.first?.name == "B")
    }

    @Test("Overflow label pluralizes the remaining count")
    func overflowLabel() {
        let one = DashboardGoalsPreview(goals: [], totalGoalCount: 4, overflowCount: 1)
        #expect(one.overflowLabel == "1 more goal")
        let many = DashboardGoalsPreview(goals: [], totalGoalCount: 6, overflowCount: 3)
        #expect(many.overflowLabel == "3 more goals")
        let none = DashboardGoalsPreview(goals: [], totalGoalCount: 0, overflowCount: 0)
        #expect(none.overflowLabel == nil)
    }

    @Test("Privacy Mask withholds dashboard goal names and exact overflow counts")
    func privacyMaskWithholdsMetadata() {
        let goal = Goal(name: "Emergency Fund", targetAmount: 1000, contributedAmount: 500, createdAt: base)
        let preview = DashboardGoalsPreview(goals: [goal], totalGoalCount: 4, overflowCount: 3)

        #expect(DashboardGoalsPreview.displayTitle(for: goal, isMasked: false) == "Emergency Fund")
        #expect(DashboardGoalsPreview.displayTitle(for: goal, isMasked: true) == "Goal hidden")
        #expect(preview.displayOverflowLabel(isMasked: false) == "3 more goals")
        #expect(preview.displayOverflowLabel(isMasked: true) == "More goals")
    }
}
