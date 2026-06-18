import Foundation
import Testing
@testable import PlaidBarCore

@Suite("Watchlist evaluator (AND-501)")
struct WatchlistEvaluatorTests {
    private static let calendar = Calendar(identifier: .gregorian)
    // Mid-month reference so prior/current-month boundaries are unambiguous.
    private static var now: Date { Formatters.parseTransactionDate("2026-05-15")! }

    @Test("Merchant target crossing threshold yields one match with summed MTD spend")
    func merchantCrossingProducesMatch() {
        let target = WatchlistTarget.merchant("Starbucks", threshold: 10)
        let transactions = [
            Self.tx(id: "a", amount: 6, date: "2026-05-03", merchant: "Starbucks"),
            Self.tx(id: "b", amount: 5, date: "2026-05-10", merchant: "Starbucks"),
        ]
        let matches = WatchlistEvaluator.evaluate(
            transactions: transactions,
            targets: [target],
            now: Self.now,
            calendar: Self.calendar
        )
        #expect(matches.count == 1)
        #expect(abs((matches.first?.currentSpend ?? 0) - 11) < 0.001)
        #expect(matches.first?.monthKey == "2026-05")
    }

    @Test("Merchant target below threshold yields no match")
    func merchantBelowThresholdNoMatch() {
        let target = WatchlistTarget.merchant("Starbucks", threshold: 50)
        let transactions = [Self.tx(id: "a", amount: 6, date: "2026-05-03", merchant: "Starbucks")]
        #expect(WatchlistEvaluator.evaluate(
            transactions: transactions,
            targets: [target],
            now: Self.now,
            calendar: Self.calendar
        ).isEmpty)
    }

    @Test("Category target sums only its expense rows and ignores income/transfers")
    func categorySumsExpensesOnly() {
        let target = WatchlistTarget.category(.shopping, threshold: 100)
        let transactions = [
            Self.tx(id: "a", amount: 80, date: "2026-05-02", merchant: "StoreA", category: .shopping),
            Self.tx(id: "b", amount: 40, date: "2026-05-04", merchant: "StoreB", category: .shopping),
            // Income (negative) at the same category should be excluded.
            Self.tx(id: "c", amount: -500, date: "2026-05-05", merchant: "Job", category: .income),
            // A transfer-in row excluded by expenseTransactions.
            Self.tx(id: "d", amount: 200, date: "2026-05-06", merchant: "Move", category: .transfer),
        ]
        let matches = WatchlistEvaluator.evaluate(
            transactions: transactions,
            targets: [target],
            now: Self.now,
            calendar: Self.calendar
        )
        #expect(matches.count == 1)
        #expect(abs((matches.first?.currentSpend ?? 0) - 120) < 0.001)
    }

    @Test("Merchant matching is normalization-insensitive")
    func merchantMatchingNormalized() {
        let target = WatchlistTarget.merchant("Whole Foods", threshold: 10)
        let transactions = [
            Self.tx(id: "a", amount: 15, date: "2026-05-02", merchant: " whole foods "),
        ]
        let matches = WatchlistEvaluator.evaluate(
            transactions: transactions,
            targets: [target],
            now: Self.now,
            calendar: Self.calendar
        )
        #expect(matches.count == 1)
    }

    @Test("Only current-month rows count toward the threshold")
    func onlyCurrentMonthCounts() {
        let target = WatchlistTarget.merchant("Starbucks", threshold: 20)
        let transactions = [
            // Prior month — must NOT count.
            Self.tx(id: "a", amount: 18, date: "2026-04-28", merchant: "Starbucks"),
            // Current month — alone is below threshold.
            Self.tx(id: "b", amount: 10, date: "2026-05-02", merchant: "Starbucks"),
        ]
        #expect(WatchlistEvaluator.evaluate(
            transactions: transactions,
            targets: [target],
            now: Self.now,
            calendar: Self.calendar
        ).isEmpty)
    }

    @Test("Zero-threshold targets never match")
    func zeroThresholdNeverMatches() {
        let target = WatchlistTarget.merchant("Starbucks", threshold: 0)
        let transactions = [Self.tx(id: "a", amount: 5, date: "2026-05-02", merchant: "Starbucks")]
        #expect(WatchlistEvaluator.evaluate(
            transactions: transactions,
            targets: [target],
            now: Self.now,
            calendar: Self.calendar
        ).isEmpty)
    }

    @Test("Demo watchlist targets cross against demo transactions")
    func demoTargetsCross() {
        // Use a fixed mid-month 'now' so the explicit recent Starbucks/shopping
        // rows fall inside the current month deterministically.
        let demoNow = Formatters.parseTransactionDate("2026-05-15")!
        let transactions = DemoFixtures.transactions(now: demoNow, calendar: Self.calendar)
        let matches = WatchlistEvaluator.evaluate(
            transactions: transactions,
            targets: DemoFixtures.watchlistTargets(),
            now: demoNow,
            calendar: Self.calendar
        )
        // At least the Starbucks merchant watch should fire ($12.50 recent coffee).
        #expect(matches.contains { $0.target.kind == .merchant })
    }

    // MARK: - NotificationTriggerSelection integration

    @Test("config.watchlist=false suppresses watchlist decisions")
    func gateOff() {
        let target = WatchlistTarget.merchant("Starbucks", threshold: 10)
        let transactions = [Self.tx(id: "a", amount: 20, date: "2026-05-02", merchant: "Starbucks")]
        let evaluation = NotificationTriggerSelection.evaluate(
            transactions: transactions,
            watchlistTargets: [target],
            now: Self.now,
            calendar: Self.calendar,
            config: NotificationTriggers(watchlist: false)
        )
        #expect(!evaluation.decisions.contains { $0.kind == .merchantWatch })
    }

    @Test("Crossed target appears in decisions and is suppressed once delivered")
    func crossedAppearsAndDedupes() {
        let target = WatchlistTarget.merchant("Starbucks", threshold: 10)
        let transactions = [Self.tx(id: "a", amount: 20, date: "2026-05-02", merchant: "Starbucks")]
        let config = NotificationTriggers(watchlist: true)

        let first = NotificationTriggerSelection.evaluate(
            transactions: transactions,
            watchlistTargets: [target],
            now: Self.now,
            calendar: Self.calendar,
            config: config
        )
        let decision = try? #require(first.decisions.first { $0.kind == .merchantWatch })
        #expect(decision != nil)

        let second = NotificationTriggerSelection.evaluate(
            transactions: transactions,
            watchlistTargets: [target],
            now: Self.now,
            calendar: Self.calendar,
            config: config,
            deliveredDedupKeys: [decision!.dedupKey]
        )
        #expect(!second.decisions.contains { $0.dedupKey == decision!.dedupKey })
    }

    @Test("dedupKey is stable per target+month+threshold but changes when any of them changes")
    func dedupKeyStability() {
        let base = WatchlistTarget.merchant("Starbucks", threshold: 10, id: UUID(uuidString: "00000000-0000-0000-0000-000000000001")!)
        let raised = WatchlistTarget.merchant("Starbucks", threshold: 25, id: base.id)
        let transactions = [Self.tx(id: "a", amount: 30, date: "2026-05-02", merchant: "Starbucks")]
        let config = NotificationTriggers(watchlist: true)

        func key(target: WatchlistTarget, now: Date) -> String? {
            NotificationTriggerSelection.evaluate(
                transactions: transactions,
                watchlistTargets: [target],
                now: now,
                calendar: Self.calendar,
                config: config
            ).decisions.first { $0.kind == .merchantWatch }?.dedupKey
        }

        let mayKey = key(target: base, now: Self.now)
        let mayKeyAgain = key(target: base, now: Self.now)
        let raisedKey = key(target: raised, now: Self.now)
        let juneKey = key(target: base, now: Formatters.parseTransactionDate("2026-06-15")!)

        #expect(mayKey != nil)
        #expect(mayKey == mayKeyAgain) // stable for same target+month+threshold
        #expect(mayKey != raisedKey)   // raising threshold re-arms
        // June has no current-month Starbucks spend so no key — month change
        // either re-arms (different key) or yields no decision.
        #expect(juneKey == nil || juneKey != mayKey)
    }

    // MARK: - Helpers

    private static func tx(
        id: String,
        amount: Double,
        date: String,
        merchant: String,
        category: SpendingCategory = .foodAndDrink
    ) -> TransactionDTO {
        TransactionDTO(
            id: id,
            accountId: "checking",
            amount: amount,
            date: date,
            name: merchant,
            merchantName: merchant,
            category: category
        )
    }
}
