import Foundation
import Testing
@testable import PlaidBarCore

@Suite("Balance projector (AND-498)")
struct BalanceProjectorTests {
    private static let calendar = Calendar(identifier: .gregorian)
    private static var asOf: Date { Formatters.parseTransactionDate("2026-06-01")! }

    @Test("Nil anchor yields nil projection")
    func nilAnchorReturnsNil() {
        let projection = BalanceProjector.project(
            anchor: nil,
            recurring: [],
            asOf: Self.asOf,
            horizonDays: 30,
            calendar: Self.calendar
        )
        #expect(projection == nil)
    }

    @Test("Empty history via presentation -> insufficientHistory with needed count")
    func emptyHistoryPresentation() {
        let presentation = ProjectedBalancePresentation.evaluate(
            history: [],
            recurring: [],
            now: Self.asOf,
            calendar: Self.calendar
        )
        guard case let .insufficientHistory(pointCount, requiredPointCount) = presentation else {
            Issue.record("expected insufficientHistory")
            return
        }
        #expect(pointCount == 0)
        #expect(requiredPointCount == PlaidBarConstants.projectedBalanceMinimumHistoryPoints)
    }

    @Test("Anchor + one monthly outflow due in 10 days steps down once on that day")
    func singleOutflowStepsDownOnce() {
        let anchor = BalanceSnapshot(date: Self.asOf, balance: 1_000)
        let stream = Self.recurring(
            "Rent", amount: 200, nextExpectedDate: "2026-06-11", category: .billsAndUtilities
        )
        let projection = BalanceProjector.project(
            anchor: anchor,
            recurring: [stream],
            asOf: Self.asOf,
            horizonDays: 30,
            calendar: Self.calendar
        )!
        // Series length = horizon + 1 (anchor + each future day).
        #expect(projection.series.count == 31)
        // First projected point equals the anchor.
        #expect(projection.series.first?.balance == 1_000)
        // Day 9 (the day before the charge) is still 1000; day 10 drops to 800.
        #expect(projection.series[9].balance == 1_000)
        #expect(projection.series[10].balance == 800)
        // The monthly stream recurs at +30 days = day 40, past the 30-day horizon,
        // so only one step occurs.
        #expect(projection.series.last?.balance == 800)
        // Projected low equals anchor - averageAmount on the due day.
        #expect(projection.projectedLow.balance == 800)
        #expect(projection.confidence == .lowConfidence)
    }

    @Test("Two streams accumulate on the correct days; low is the global minimum")
    func twoStreamsAccumulate() {
        let anchor = BalanceSnapshot(date: Self.asOf, balance: 1_000)
        let monthly = Self.recurring("Rent", amount: 300, nextExpectedDate: "2026-06-06", category: .billsAndUtilities)
        let biweekly = Self.recurring(
            "Bill", amount: 100, frequency: .biweekly, nextExpectedDate: "2026-06-04", category: .billsAndUtilities
        )
        let projection = BalanceProjector.project(
            anchor: anchor,
            recurring: [monthly, biweekly],
            asOf: Self.asOf,
            horizonDays: 30,
            calendar: Self.calendar
        )!
        // Biweekly: day 3 (-100 -> 900), day 17 (-100 -> 800 cumulative after rent).
        // Monthly rent: day 5 (-300).
        // Running: d3 900, d5 600, d17 500, d31 (biweekly again at day 31>30? day 3+14+14=31 just past) ...
        #expect(projection.series[3].balance == 900)
        #expect(projection.series[5].balance == 600)
        #expect(projection.series[17].balance == 500)
        // Global minimum is the lowest running balance.
        #expect(projection.projectedLow.balance == projection.series.map(\.balance).min())
    }

    @Test("Below-confidence and income/transfer streams are handled per gating")
    func gatingExcludesAndIncludes() {
        let anchor = BalanceSnapshot(date: Self.asOf, balance: 1_000)
        let lowConfidence = Self.recurring(
            "Weak", amount: 500, nextExpectedDate: "2026-06-05", category: .billsAndUtilities, confidence: 0.3
        )
        let transfer = Self.recurring(
            "Move", amount: 500, nextExpectedDate: "2026-06-05", category: .transferOut
        )
        let income = Self.recurring(
            "Paycheck", amount: 400, nextExpectedDate: "2026-06-10", category: .income
        )
        let projection = BalanceProjector.project(
            anchor: anchor,
            recurring: [lowConfidence, transfer, income],
            asOf: Self.asOf,
            horizonDays: 30,
            calendar: Self.calendar
        )!
        // Low-confidence + transfer excluded; income adds on day 10.
        #expect(projection.series[10].balance == 1_400)
        // No outflow at all, so the line only ever goes up -> low is the anchor.
        #expect(projection.projectedLow.balance == 1_000)
    }

    @Test("Horizon boundary: occurrence on the edge is included, one day past excluded")
    func horizonBoundary() {
        let anchor = BalanceSnapshot(date: Self.asOf, balance: 1_000)
        let onEdge = Self.recurring(
            "Edge", amount: 50, frequency: .annual, nextExpectedDate: "2026-07-01", category: .billsAndUtilities
        )
        // 2026-06-01 + 30 days = 2026-07-01 (the inclusive horizon edge).
        let projection = BalanceProjector.project(
            anchor: anchor,
            recurring: [onEdge],
            asOf: Self.asOf,
            horizonDays: 30,
            calendar: Self.calendar
        )!
        #expect(projection.series.last?.balance == 950)

        let pastEdge = Self.recurring(
            "Past", amount: 50, frequency: .annual, nextExpectedDate: "2026-07-02", category: .billsAndUtilities
        )
        let projection2 = BalanceProjector.project(
            anchor: anchor,
            recurring: [pastEdge],
            asOf: Self.asOf,
            horizonDays: 30,
            calendar: Self.calendar
        )!
        #expect(projection2.series.last?.balance == 1_000)
        #expect(projection2.confidence == .lowConfidence) // it is still a signal
    }

    @Test("Deterministic across two calls with the same inputs")
    func deterministic() {
        let anchor = BalanceSnapshot(date: Self.asOf, balance: 1_000)
        let stream = Self.recurring("Rent", amount: 200, nextExpectedDate: "2026-06-11", category: .billsAndUtilities)
        let a = BalanceProjector.project(anchor: anchor, recurring: [stream], asOf: Self.asOf, horizonDays: 30, calendar: Self.calendar)
        let b = BalanceProjector.project(anchor: anchor, recurring: [stream], asOf: Self.asOf, horizonDays: 30, calendar: Self.calendar)
        #expect(a == b)
    }

    @Test("No obligation signal -> insufficientData confidence")
    func noSignalInsufficient() {
        let anchor = BalanceSnapshot(date: Self.asOf, balance: 1_000)
        let projection = BalanceProjector.project(
            anchor: anchor,
            recurring: [],
            asOf: Self.asOf,
            horizonDays: 30,
            calendar: Self.calendar
        )!
        #expect(projection.confidence == .insufficientData)
        // Flat line: every point equals the anchor.
        #expect(projection.series.allSatisfy { $0.balance == 1_000 })
    }

    @Test("Presentation requires the minimum history points")
    func presentationRequiresHistory() {
        let oneSnapshot = [BalanceSnapshot(date: Self.asOf, balance: 1_000)]
        let presentation = ProjectedBalancePresentation.evaluate(
            history: oneSnapshot,
            recurring: [],
            now: Self.asOf,
            requiredPointCount: 2,
            calendar: Self.calendar
        )
        guard case let .insufficientHistory(pointCount, requiredPointCount) = presentation else {
            Issue.record("expected insufficientHistory")
            return
        }
        #expect(pointCount == 1)
        #expect(requiredPointCount == 2)
    }

    @Test("Anchor is the latest snapshot by date")
    func anchorsOnLatest() {
        let history = [
            BalanceSnapshot(date: Formatters.parseTransactionDate("2026-05-01")!, balance: 500),
            BalanceSnapshot(date: Formatters.parseTransactionDate("2026-05-31")!, balance: 1_200),
        ]
        let presentation = ProjectedBalancePresentation.evaluate(
            history: history,
            recurring: [],
            now: Self.asOf,
            calendar: Self.calendar
        )
        let projection = try? #require(presentation.projection)
        #expect(projection?.anchorBalance == 1_200)
    }

    @Test("Demo data produces a non-trivial projection in-window")
    func demoProducesProjection() {
        let now = Formatters.parseTransactionDate("2026-06-15")!
        let history = DemoFixtures.balanceHistory(now: now, calendar: Self.calendar)
        let recurring = RecurringDetector.detect(from: DemoFixtures.transactions(now: now, calendar: Self.calendar))
        let presentation = ProjectedBalancePresentation.evaluate(
            history: history,
            recurring: recurring,
            now: now,
            horizonDays: 30,
            calendar: Self.calendar
        )
        let projection = try? #require(presentation.projection)
        // The forward line should step (not stay perfectly flat) given demo bills.
        let balances = Set(projection?.series.map(\.balance) ?? [])
        #expect(balances.count > 1)
    }

    private static func recurring(
        _ merchant: String,
        amount: Double,
        frequency: RecurringFrequency = .monthly,
        nextExpectedDate: String,
        category: SpendingCategory?,
        confidence: Double = 0.9
    ) -> RecurringTransaction {
        RecurringTransaction(
            merchantName: merchant,
            frequency: frequency,
            averageAmount: amount,
            lastDate: "2026-05-20",
            nextExpectedDate: nextExpectedDate,
            category: category,
            transactionCount: 4,
            confidence: confidence
        )
    }
}
