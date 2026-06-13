import Foundation
import Testing
@testable import PlaidBarCore

@Suite("AccountSparkline")
struct AccountSparklineTests {
    private let calendar = Calendar.current

    private func date(_ string: String) throws -> Date {
        try #require(Formatters.parseTransactionDate(string))
    }

    private func history(_ balances: [Double], endingAt end: Date) -> [BalanceSnapshot] {
        // Oldest first; one point per day ending at `end`.
        balances.enumerated().map { offset, balance in
            let daysAgo = balances.count - 1 - offset
            let pointDate = calendar.date(byAdding: .day, value: -daysAgo, to: end) ?? end
            return BalanceSnapshot(date: pointDate, balance: balance)
        }
    }

    @Test("Insufficient history renders nothing")
    func insufficientHistoryRendersNothing() throws {
        let now = try date("2026-06-10")

        // Empty history.
        #expect(AccountSparkline.evaluate(history: [], now: now, calendar: calendar) == nil)

        // Single point cannot establish a direction or a line.
        #expect(
            AccountSparkline.evaluate(
                history: history([5_000], endingAt: now),
                now: now,
                calendar: calendar
            ) == nil
        )

        // Two points, but a higher custom minimum is not met.
        #expect(
            AccountSparkline.evaluate(
                history: history([5_000, 5_200], endingAt: now),
                minimumPointCount: 3,
                now: now,
                calendar: calendar
            ) == nil
        )
    }

    @Test("Single in-window point renders nothing even with old history")
    func singlePointInWindowRendersNothing() throws {
        let now = try date("2026-06-10")
        let ancient = try #require(calendar.date(byAdding: .day, value: -200, to: now))

        // One recent point plus one outside the 90-day window: only one point
        // counts, so there is no honest line.
        let series = AccountSparkline.evaluate(
            history: [
                BalanceSnapshot(date: ancient, balance: 4_000),
                BalanceSnapshot(date: now, balance: 5_000),
            ],
            now: now,
            calendar: calendar
        )
        #expect(series == nil)
    }

    @Test("Upward history yields an up direction and a rising normalized series")
    func upwardHistory() throws {
        let now = try date("2026-06-10")
        let series = try #require(
            AccountSparkline.evaluate(
                history: history([8_000, 8_300, 8_900, 9_400], endingAt: now),
                now: now,
                calendar: calendar
            )
        )

        #expect(series.direction == .up)
        #expect(series.normalizedValues.count == 4)
        // Min maps to 0, max maps to 1, oldest first.
        #expect(series.normalizedValues.first == 0)
        #expect(series.normalizedValues.last == 1)
        #expect(series.normalizedValues == series.normalizedValues.sorted())
    }

    @Test("Downward history yields a down direction and a falling normalized series")
    func downwardHistory() throws {
        let now = try date("2026-06-10")
        let series = try #require(
            AccountSparkline.evaluate(
                history: history([9_400, 8_900, 8_300, 8_000], endingAt: now),
                now: now,
                calendar: calendar
            )
        )

        #expect(series.direction == .down)
        #expect(series.normalizedValues.count == 4)
        // Oldest (highest) maps to 1, newest (lowest) maps to 0.
        #expect(series.normalizedValues.first == 1)
        #expect(series.normalizedValues.last == 0)
        #expect(series.normalizedValues == series.normalizedValues.sorted(by: >))
    }

    @Test("Flat history yields a flat direction and a level mid-line")
    func flatHistory() throws {
        let now = try date("2026-06-10")
        let series = try #require(
            AccountSparkline.evaluate(
                history: history([10_000, 10_000, 10_000], endingAt: now),
                now: now,
                calendar: calendar
            )
        )

        #expect(series.direction == .flat)
        #expect(series.normalizedValues == [0.5, 0.5, 0.5])
    }

    @Test("Indexed points are ordered oldest-first by x")
    func indexedPointsOrdered() throws {
        let now = try date("2026-06-10")
        let series = try #require(
            AccountSparkline.evaluate(
                history: history([1_000, 2_000, 3_000], endingAt: now),
                now: now,
                calendar: calendar
            )
        )

        let points = series.indexedPoints
        #expect(points.map(\.x) == [0, 1, 2])
        #expect(points.map(\.y) == series.normalizedValues)
    }

    @Test("Normalize collapses a zero-spread series to a mid-line")
    func normalizeZeroSpread() {
        #expect(AccountSparkline.normalize([]) == [])
        #expect(AccountSparkline.normalize([42, 42, 42]) == [0.5, 0.5, 0.5])
        #expect(AccountSparkline.normalize([0, 5, 10]) == [0, 0.5, 1])
    }

    @Test("Credit-account debt paydown reads as an up direction")
    func creditAccountPaydownReadsUp() throws {
        let now = try date("2026-06-10")
        // Paying a card down (-2000 → -1000) is a positive trend for the user;
        // normalize is sign-agnostic, so the oldest (lowest) balance maps to 0.
        let series = try #require(
            AccountSparkline.evaluate(
                history: history([-2_000, -1_600, -1_000], endingAt: now),
                now: now,
                calendar: calendar
            )
        )
        #expect(series.direction == .up)
        #expect(series.normalizedValues.first == 0)
        #expect(series.normalizedValues.last == 1)
    }
}
