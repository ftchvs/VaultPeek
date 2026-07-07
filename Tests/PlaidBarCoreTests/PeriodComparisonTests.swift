import Foundation
import Testing
@testable import PlaidBarCore

// MARK: - Window derivation

@Suite("PeriodComparison windows")
struct PeriodComparisonWindowTests {
    private static let calendar = Calendar(identifier: .gregorian)

    private static func day(_ key: String) -> Date {
        Formatters.parseTransactionDate(key)!
    }

    @Test("Trailing-30 windows are adjacent with no gap or overlap")
    func trailingThirtyAdjacency() {
        let windows = PeriodComparison.windows(
            for: .trailingDays(30), asOf: Self.day("2026-06-15"), calendar: Self.calendar
        )!
        // Current: the 30 days ending today (end exclusive = tomorrow).
        #expect(windows.current.startKey == "2026-05-17")
        #expect(windows.current.endKey == "2026-06-16")
        // Prior: the 30 days immediately before, sharing the boundary key.
        #expect(windows.prior.startKey == "2026-04-17")
        #expect(windows.prior.endKey == windows.current.startKey)
    }

    @Test("Full month-over-month windows are adjacent calendar months")
    func fullMonthAdjacency() {
        let windows = PeriodComparison.windows(
            for: .fullMonthOverMonth, asOf: Self.day("2026-06-15"), calendar: Self.calendar
        )!
        #expect(windows.current.startKey == "2026-06-01")
        #expect(windows.current.endKey == "2026-07-01")
        #expect(windows.prior.startKey == "2026-05-01")
        #expect(windows.prior.endKey == windows.current.startKey)
    }

    @Test("Month-to-date compares against the prior month to the same day")
    func monthToDateSameDay() {
        let windows = PeriodComparison.windows(
            for: .monthToDate, asOf: Self.day("2026-06-15"), calendar: Self.calendar
        )!
        // Current: June 1 through end of June 15 (15 elapsed days).
        #expect(windows.current.startKey == "2026-06-01")
        #expect(windows.current.endKey == "2026-06-16")
        // Prior: May 1 through the same 15 elapsed days — NOT the full month.
        #expect(windows.prior.startKey == "2026-05-01")
        #expect(windows.prior.endKey == "2026-05-16")
    }

    @Test("Month-to-date on Mar 31 clamps the prior window to February's length")
    func monthToDateClampsShortMonth() {
        // 2026: February has 28 days.
        let windows = PeriodComparison.windows(
            for: .monthToDate, asOf: Self.day("2026-03-31"), calendar: Self.calendar
        )!
        #expect(windows.prior.startKey == "2026-02-01")
        #expect(windows.prior.endKey == "2026-03-01") // all 28 days, no spill
    }

    @Test("Month-to-date clamp honors a leap-year February")
    func monthToDateLeapClamp() {
        // 2024: February has 29 days.
        let windows = PeriodComparison.windows(
            for: .monthToDate, asOf: Self.day("2024-03-31"), calendar: Self.calendar
        )!
        #expect(windows.prior.startKey == "2024-02-01")
        #expect(windows.prior.endKey == "2024-03-01") // all 29 days
        // A mid-leap-February same-day compare stays unclamped.
        let midMonth = PeriodComparison.windows(
            for: .monthToDate, asOf: Self.day("2024-03-15"), calendar: Self.calendar
        )!
        #expect(midMonth.prior.endKey == "2024-02-16")
    }

    @Test("January month-to-date wraps to December of the prior year")
    func januaryYearWrap() {
        let windows = PeriodComparison.windows(
            for: .monthToDate, asOf: Self.day("2026-01-10"), calendar: Self.calendar
        )!
        #expect(windows.current.startKey == "2026-01-01")
        #expect(windows.prior.startKey == "2025-12-01")
        #expect(windows.prior.endKey == "2025-12-11")

        let fullMonth = PeriodComparison.windows(
            for: .fullMonthOverMonth, asOf: Self.day("2026-01-10"), calendar: Self.calendar
        )!
        #expect(fullMonth.prior.startKey == "2025-12-01")
        #expect(fullMonth.prior.endKey == "2026-01-01")
    }

    @Test("All window keys are canonical yyyy-MM-dd transaction keys")
    func allKeysCanonical() {
        let periods: [ComparisonPeriod] = [.trailingDays(7), .trailingDays(30), .monthToDate, .fullMonthOverMonth]
        for period in periods {
            let windows = PeriodComparison.windows(
                for: period, asOf: Self.day("2026-01-03"), calendar: Self.calendar
            )!
            for key in [
                windows.current.startKey, windows.current.endKey,
                windows.prior.startKey, windows.prior.endKey,
            ] {
                #expect(Formatters.isCanonicalTransactionDateKey(key), "non-canonical key \(key) for \(period)")
            }
        }
    }

    @Test("Non-positive trailing day counts produce no windows")
    func invalidTrailingDays() {
        #expect(PeriodComparison.windows(for: .trailingDays(0), asOf: Self.day("2026-06-15"), calendar: Self.calendar) == nil)
        #expect(PeriodComparison.windows(for: .trailingDays(-5), asOf: Self.day("2026-06-15"), calendar: Self.calendar) == nil)
    }

    @Test("Comparison labels pair with the period semantics")
    func comparisonLabels() {
        #expect(ComparisonPeriod.trailingDays(30).comparisonLabel == "vs prior 30 days")
        #expect(ComparisonPeriod.monthToDate.comparisonLabel == "vs last month to date")
        #expect(ComparisonPeriod.fullMonthOverMonth.comparisonLabel == "vs last month")
    }
}

// MARK: - Domain builders

@Suite("PeriodComparison engine")
struct PeriodComparisonEngineTests {
    private static let calendar = Calendar(identifier: .gregorian)
    /// June 15, 2026 — month-to-date windows: current [Jun 1, Jun 16),
    /// prior [May 1, May 16).
    private static var asOf: Date { Formatters.parseTransactionDate("2026-06-15")! }

    private static func tx(
        id: String,
        amount: Double,
        date: String,
        category: SpendingCategory?
    ) -> TransactionDTO {
        TransactionDTO(id: id, accountId: "acc", amount: amount, date: date, name: id, category: category)
    }

    /// Transactions straddling both month-to-date windows, plus rows that must
    /// never count as spend (income, transfer) and rows outside both windows.
    private static var fixture: [TransactionDTO] {
        [
            // Current window (June 1–15).
            tx(id: "cur-food", amount: 120, date: "2026-06-03", category: .foodAndDrink),
            tx(id: "cur-shop", amount: 80, date: "2026-06-10", category: .shopping),
            tx(id: "cur-income", amount: -3_000, date: "2026-06-01", category: .income),
            tx(id: "cur-transfer", amount: 500, date: "2026-06-05", category: .transferOut),
            // Prior window (May 1–15).
            tx(id: "pri-food", amount: 200, date: "2026-05-04", category: .foodAndDrink),
            tx(id: "pri-shop", amount: 50, date: "2026-05-12", category: .shopping),
            tx(id: "pri-income", amount: -2_800, date: "2026-05-01", category: .income),
            // Outside both windows: late May (after the same-day cut) and April.
            tx(id: "gap-food", amount: 999, date: "2026-05-20", category: .foodAndDrink),
            tx(id: "old-shop", amount: 999, date: "2026-04-10", category: .shopping),
        ]
    }

    @Test("Fixture rows split into the correct windows; transfers and income excluded")
    func totalSpendSplitsWindows() {
        let delta = PeriodComparison.totalSpendDelta(
            transactions: Self.fixture,
            period: .monthToDate,
            asOf: Self.asOf,
            calendar: Self.calendar
        )!
        // Current spend 120 + 80 = 200; prior spend 200 + 50 = 250. The
        // transfer, both paychecks, the post-cut May row, and April never count.
        #expect(delta.current == 200)
        #expect(delta.previous == 250)
        #expect(delta.delta == -50)
        #expect(delta.direction == .down)
        // Spend falling is good news.
        #expect(delta.sentiment == .positive)
    }

    @Test("Income delta uses the inflow gate and higher-is-better polarity")
    func incomeDeltaBuilds() {
        let delta = PeriodComparison.incomeDelta(
            transactions: Self.fixture,
            period: .monthToDate,
            asOf: Self.asOf,
            calendar: Self.calendar
        )!
        #expect(delta.current == 3_000)
        #expect(delta.previous == 2_800)
        #expect(delta.direction == .up)
        #expect(delta.sentiment == .positive)
    }

    @Test("Category deltas cover the union of both windows' categories")
    func categoryDeltasUnion() {
        let onlyPrior = Self.fixture + [
            Self.tx(id: "pri-travel", amount: 300, date: "2026-05-08", category: .travel),
        ]
        let deltas = PeriodComparison.categorySpendDeltas(
            transactions: onlyPrior,
            period: .monthToDate,
            asOf: Self.asOf,
            calendar: Self.calendar
        )
        #expect(deltas[.foodAndDrink]?.delta == -80) // 120 vs 200
        #expect(deltas[.shopping]?.delta == 30) // 80 vs 50
        // Travel exists only in the prior window but still gets a delta.
        #expect(deltas[.travel]?.current == 0)
        #expect(deltas[.travel]?.previous == 300)
        #expect(deltas[.travel]?.direction == .down)
        // Income/transfers never appear as spend categories.
        #expect(deltas[.income] == nil)
        #expect(deltas[.transferOut] == nil)
    }

    @Test("An override recategorizing a PRIOR-window transaction moves both windows")
    func overridesMoveBothWindows() {
        // Recategorize the prior-window shopping row to food. Because both
        // windows run through the same kernel with the same metadata, food's
        // prior total gains 50 and shopping's prior total loses 50 — the delta
        // can never be manufactured by one window ignoring the override.
        let metadata = [TransactionReviewMetadata(id: "pri-shop", userCategory: .foodAndDrink)]
        let deltas = PeriodComparison.categorySpendDeltas(
            transactions: Self.fixture,
            period: .monthToDate,
            asOf: Self.asOf,
            calendar: Self.calendar,
            metadata: metadata
        )
        #expect(deltas[.foodAndDrink]?.previous == 250) // 200 + moved 50
        #expect(deltas[.foodAndDrink]?.delta == -130) // 120 vs 250
        #expect(deltas[.shopping]?.previous == 0)
        #expect(deltas[.shopping]?.current == 80)

        // The total is invariant under recategorization (it only moves buckets).
        let total = PeriodComparison.totalSpendDelta(
            transactions: Self.fixture,
            period: .monthToDate,
            asOf: Self.asOf,
            calendar: Self.calendar,
            metadata: metadata
        )!
        #expect(total.current == 200)
        #expect(total.previous == 250)
    }

    // MARK: - Net worth

    @Test("Net-worth delta picks the boundary snapshot for the previous value")
    func netWorthBoundarySelection() {
        // Trailing-30 asOf Jun 15: prior window ends (exclusively) Jun 16-30 =
        // May 17. The previous value must be the latest snapshot strictly
        // before that boundary — May 16, not the boundary-day May 17 snapshot
        // (which belongs to the current window).
        let history = [
            BalanceSnapshot(date: Formatters.parseTransactionDate("2026-05-10")!, balance: 40_000),
            BalanceSnapshot(date: Formatters.parseTransactionDate("2026-05-16")!, balance: 41_000),
            BalanceSnapshot(date: Formatters.parseTransactionDate("2026-05-17")!, balance: 45_000),
            BalanceSnapshot(date: Formatters.parseTransactionDate("2026-06-14")!, balance: 43_500),
        ]
        let delta = PeriodComparison.netWorthDelta(
            history: history,
            period: .trailingDays(30),
            asOf: Self.asOf,
            calendar: Self.calendar
        )!
        #expect(delta.current == 43_500)
        #expect(delta.previous == 41_000)
        #expect(delta.direction == .up)
        #expect(delta.sentiment == .positive)
    }

    @Test("Young history that misses the prior window yields nil, never a zero baseline")
    func youngHistoryYieldsNil() {
        // All snapshots inside the current window: a fresh install. A naive
        // implementation would compare against 0 and show "+$48K this month".
        let history = [
            BalanceSnapshot(date: Formatters.parseTransactionDate("2026-06-10")!, balance: 48_000),
            BalanceSnapshot(date: Formatters.parseTransactionDate("2026-06-14")!, balance: 48_200),
        ]
        let delta = PeriodComparison.netWorthDelta(
            history: history,
            period: .trailingDays(30),
            asOf: Self.asOf,
            calendar: Self.calendar
        )
        #expect(delta == nil)
        #expect(PeriodComparison.netWorthDelta(
            history: [],
            period: .trailingDays(30),
            asOf: Self.asOf,
            calendar: Self.calendar
        ) == nil)
    }

    // MARK: - Daily spend spark

    @Test("Daily spend spark buckets by day over the current window and normalizes")
    func dailySpendSpark() {
        let spark = PeriodComparison.dailySpendSpark(
            transactions: Self.fixture,
            period: .monthToDate,
            asOf: Self.asOf,
            calendar: Self.calendar
        )!
        // June 1–15 inclusive = 15 daily buckets.
        #expect(spark.count == 15)
        // Normalized to 0...1: the heaviest day (June 3, $120) is 1, quiet days 0.
        #expect(spark[2] == 1)
        #expect(spark[9] == 80.0 / 120.0)
        #expect(spark[0] == 0)
        #expect(spark.allSatisfy { $0 >= 0 && $0 <= 1 })
    }

    @Test("Daily spend spark is nil with no expense activity in the window")
    func dailySpendSparkNilWhenQuiet() {
        let quiet = [
            Self.tx(id: "inc", amount: -3_000, date: "2026-06-01", category: .income),
            Self.tx(id: "move", amount: 500, date: "2026-06-05", category: .transferOut),
        ]
        let spark = PeriodComparison.dailySpendSpark(
            transactions: quiet,
            period: .monthToDate,
            asOf: Self.asOf,
            calendar: Self.calendar
        )
        #expect(spark == nil)
    }

    @Test("Deterministic across repeated calls with identical inputs")
    func deterministic() {
        let a = PeriodComparison.totalSpendDelta(
            transactions: Self.fixture, period: .monthToDate, asOf: Self.asOf, calendar: Self.calendar
        )
        let b = PeriodComparison.totalSpendDelta(
            transactions: Self.fixture, period: .monthToDate, asOf: Self.asOf, calendar: Self.calendar
        )
        #expect(a == b)
    }
}
