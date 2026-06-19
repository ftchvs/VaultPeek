import Foundation
import Testing
@testable import PlaidBarCore

@Suite("Projected balance presentation (AND-498)")
struct ProjectedBalancePresentationTests {
    private let calendar = Calendar(identifier: .gregorian)
    private let now = Date(timeIntervalSince1970: 1_700_000_000)

    private func snap(daysAgo: Int, balance: Double) -> BalanceSnapshot {
        BalanceSnapshot(date: now.addingTimeInterval(TimeInterval(-daysAgo) * 86_400), balance: balance)
    }

    @Test("Too little history yields insufficient with the raw point count")
    func insufficientHistory() {
        let presentation = ProjectedBalancePresentation.evaluate(
            history: [snap(daysAgo: 1, balance: 1_000)],
            recurring: [],
            now: now,
            calendar: calendar
        )
        guard case let .insufficientHistory(pointCount, requiredPointCount) = presentation else {
            Issue.record("expected .insufficientHistory, got \(presentation)")
            return
        }
        #expect(pointCount == 1)
        #expect(requiredPointCount == PlaidBarConstants.projectedBalanceMinimumHistoryPoints)
        #expect(presentation.projection == nil)
    }

    @Test("Enough history with no recurring signal still produces an indicative forecast")
    func availableWithoutRecurring() {
        let history = [snap(daysAgo: 2, balance: 900), snap(daysAgo: 0, balance: 1_000)]
        let presentation = ProjectedBalancePresentation.evaluate(
            history: history,
            recurring: [],
            now: now,
            horizonDays: 30,
            calendar: calendar
        )
        guard case let .available(projection) = presentation else {
            Issue.record("expected .available, got \(presentation)")
            return
        }
        // No recurring deltas -> a flat line anchored on the latest balance.
        #expect(projection.anchorBalance == 1_000)
        #expect(projection.endBalance == 1_000)
        #expect(projection.confidence == .insufficientData)
        #expect(presentation.projection == projection)
    }

    @Test("Accessibility summary mirrors the projection when available")
    func accessibilityAvailable() {
        let history = [snap(daysAgo: 2, balance: 900), snap(daysAgo: 0, balance: 1_000)]
        let presentation = ProjectedBalancePresentation.evaluate(
            history: history, recurring: [], now: now, calendar: calendar
        )
        guard case let .available(projection) = presentation else {
            Issue.record("expected .available")
            return
        }
        #expect(presentation.accessibilitySummary == projection.accessibilitySummary)
    }

    @Test("Insufficient accessibility summary pluralizes the needed snapshots")
    func accessibilityInsufficientPlural() {
        let presentation = ProjectedBalancePresentation.evaluate(
            history: [], recurring: [], now: now, requiredPointCount: 3, calendar: calendar
        )
        #expect(presentation.accessibilitySummary.contains("Needs 3 more local balance snapshots."))
    }

    @Test("Insufficient accessibility summary is singular for one needed snapshot")
    func accessibilityInsufficientSingular() {
        let presentation = ProjectedBalancePresentation.evaluate(
            history: [snap(daysAgo: 1, balance: 1)], recurring: [], now: now, requiredPointCount: 2, calendar: calendar
        )
        #expect(presentation.accessibilitySummary.contains("Needs 1 more local balance snapshot."))
        #expect(!presentation.accessibilitySummary.contains("snapshots"))
    }

    @Test("A zero requirement with empty history still fails for lack of an anchor")
    func zeroRequirementNoAnchor() {
        let presentation = ProjectedBalancePresentation.evaluate(
            history: [], recurring: [], now: now, requiredPointCount: 0, calendar: calendar
        )
        guard case let .insufficientHistory(pointCount, requiredPointCount) = presentation else {
            Issue.record("expected .insufficientHistory, got \(presentation)")
            return
        }
        #expect(pointCount == 0)
        #expect(requiredPointCount == 0)
    }
}
