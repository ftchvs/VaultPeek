import Foundation
import Testing
@testable import PlaidBarCore

@Suite("Net worth trend presentation (AND-498)")
struct NetWorthTrendPresentationTests {
    private let calendar = Calendar(identifier: .gregorian)
    private let now = Date(timeIntervalSince1970: 1_700_000_000)

    private func snap(daysAgo: Int, balance: Double) -> BalanceSnapshot {
        BalanceSnapshot(date: now.addingTimeInterval(TimeInterval(-daysAgo) * 86_400), balance: balance)
    }

    @Test("Available when enough in-window points exist, mirroring BalanceTrend")
    func availableWithHistory() {
        let history = [snap(daysAgo: 30, balance: 1_000), snap(daysAgo: 1, balance: 1_500)]
        let presentation = NetWorthTrendPresentation.evaluate(
            history: history, now: now, windowDays: 90, calendar: calendar
        )
        guard case let .available(trend) = presentation else {
            Issue.record("expected .available, got \(presentation)")
            return
        }
        #expect(trend.direction == .up)
        #expect(trend.delta == 500)
    }

    @Test("Insufficient history reports in-window point count and required count")
    func insufficientHistory() {
        let presentation = NetWorthTrendPresentation.evaluate(
            history: [snap(daysAgo: 5, balance: 1_000)], now: now, windowDays: 90, calendar: calendar
        )
        guard case let .insufficientHistory(pointCount, requiredPointCount) = presentation else {
            Issue.record("expected .insufficientHistory, got \(presentation)")
            return
        }
        #expect(pointCount == 1)
        #expect(requiredPointCount == BalanceTrend.requiredPointCount)
    }

    @Test("Accessibility summary mirrors the trend when available")
    func accessibilityAvailable() {
        let history = [snap(daysAgo: 30, balance: 1_000), snap(daysAgo: 1, balance: 1_500)]
        let presentation = NetWorthTrendPresentation.evaluate(
            history: history, now: now, windowDays: 90, calendar: calendar
        )
        guard case let .available(trend) = presentation else {
            Issue.record("expected .available")
            return
        }
        #expect(presentation.accessibilitySummary == trend.accessibilitySummary)
    }

    @Test("Accessibility summary pluralizes when two more snapshots are needed")
    func accessibilityInsufficientPlural() {
        let presentation = NetWorthTrendPresentation.evaluate(
            history: [], now: now, windowDays: 90, calendar: calendar
        )
        #expect(presentation.accessibilitySummary.contains("Needs 2 more local balance snapshots."))
    }

    @Test("Accessibility summary is singular when exactly one snapshot is needed")
    func accessibilityInsufficientSingular() {
        let presentation = NetWorthTrendPresentation.evaluate(
            history: [snap(daysAgo: 5, balance: 1_000)], now: now, windowDays: 90, calendar: calendar
        )
        #expect(presentation.accessibilitySummary.contains("Needs 1 more local balance snapshot."))
        #expect(!presentation.accessibilitySummary.contains("snapshots"))
    }

    @Test("Non-positive window yields insufficient history with zero points")
    func nonPositiveWindow() {
        let history = [snap(daysAgo: 1, balance: 1), snap(daysAgo: 2, balance: 2)]
        let presentation = NetWorthTrendPresentation.evaluate(
            history: history, now: now, windowDays: 0, calendar: calendar
        )
        guard case let .insufficientHistory(pointCount, _) = presentation else {
            Issue.record("expected .insufficientHistory")
            return
        }
        #expect(pointCount == 0)
    }
}
