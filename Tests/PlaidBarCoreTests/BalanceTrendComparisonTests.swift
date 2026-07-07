import Foundation
import Testing
@testable import PlaidBarCore

@Suite("BalanceTrendComparison ghost overlay")
struct BalanceTrendComparisonTests {
    private static let calendar = Calendar(identifier: .gregorian)
    private static var now: Date { Formatters.parseTransactionDate("2026-06-15")! }

    private static func snapshot(_ key: String, _ balance: Double) -> BalanceSnapshot {
        BalanceSnapshot(date: Formatters.parseTransactionDate(key)!, balance: balance)
    }

    @Test("Ghost points are the prior window's, date-shifted forward by exactly windowDays")
    func ghostDatesShifted() {
        let windowDays = 30
        // Prior window (ending 30 days before now = May 16): points in early May.
        let history = [
            Self.snapshot("2026-05-01", 40_000),
            Self.snapshot("2026-05-10", 41_000),
            Self.snapshot("2026-05-16", 42_000),
            // Current-window points must not appear in the ghost.
            Self.snapshot("2026-06-01", 43_000),
            Self.snapshot("2026-06-14", 44_000),
        ]
        let ghost = BalanceTrendComparison.evaluate(
            history: history, now: Self.now, windowDays: windowDays, calendar: Self.calendar
        )!
        #expect(ghost.points.count == 3)
        // Each prior date + 30 days, balances untouched.
        #expect(ghost.points[0].date == Self.calendar.date(
            byAdding: .day, value: windowDays, to: Formatters.parseTransactionDate("2026-05-01")!
        ))
        #expect(ghost.points[0].balance == 40_000)
        #expect(ghost.points[2].date == Self.calendar.date(
            byAdding: .day, value: windowDays, to: Formatters.parseTransactionDate("2026-05-16")!
        ))
        #expect(ghost.points[2].balance == 42_000)
        #expect(ghost.label == "Previous 30 days")
        // The spoken summary describes the prior movement in words, no glyphs.
        #expect(ghost.accessibilitySummary.contains("Previous 30-day period"))
        #expect(ghost.accessibilitySummary.contains("rose"))
    }

    @Test("Nil when the prior window lacks BalanceTrend's required point count")
    func nilOnThinPriorWindow() {
        // Only one prior-window point — under requiredPointCount (2), so the
        // same honesty gate that blanks the sparkline blanks the ghost.
        let history = [
            Self.snapshot("2026-05-10", 41_000),
            Self.snapshot("2026-06-01", 43_000),
            Self.snapshot("2026-06-14", 44_000),
        ]
        #expect(BalanceTrendComparison.evaluate(
            history: history, now: Self.now, windowDays: 30, calendar: Self.calendar
        ) == nil)
        #expect(BalanceTrendComparison.evaluate(
            history: [], now: Self.now, windowDays: 30, calendar: Self.calendar
        ) == nil)
    }

    @Test("Non-positive window is nil")
    func nilOnInvalidWindow() {
        let history = [
            Self.snapshot("2026-05-01", 40_000),
            Self.snapshot("2026-05-10", 41_000),
        ]
        #expect(BalanceTrendComparison.evaluate(
            history: history, now: Self.now, windowDays: 0, calendar: Self.calendar
        ) == nil)
    }

    @Test("Average baseline formats mask-aware text and keeps the numeric value")
    func averageBaseline() {
        let baseline = PeriodComparison.averageBaseline(
            values: [100, 200, 300], label: "Daily average", isMasked: false
        )!
        #expect(baseline.value == 200)
        #expect(baseline.valueText == Formatters.currency(200, format: .compact))
        #expect(baseline.accessibilityText == "Daily average: \(Formatters.currency(200, format: .full)).")

        let masked = PeriodComparison.averageBaseline(
            values: [100, 200, 300], label: "Daily average", isMasked: true
        )!
        // The drawn value stays real (the chart itself is mask-governed);
        // every rendered string is masked.
        #expect(masked.value == 200)
        #expect(masked.valueText == PrivacyMaskPresentation.compactValue)
        #expect(!masked.accessibilityText.contains("$"))

        #expect(PeriodComparison.averageBaseline(values: [], label: "x", isMasked: false) == nil)
    }
}
