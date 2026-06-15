import Foundation
import Testing
@testable import PlaidBarCore

@Suite("TransactionDerivedIndex")
struct TransactionDerivedIndexTests {
    @Test("Index precomputes buckets, flags, dates, and category totals")
    func precomputesBucketsFlagsDatesAndTotals() throws {
        let transactions = [
            Self.tx("coffee", accountId: "checking", itemId: "item-a", amount: 6, date: "2026-06-10", merchant: "Cafe", category: .foodAndDrink),
            Self.tx("payroll", accountId: "checking", itemId: "item-a", amount: -2_000, date: "2026-06-09", merchant: "Acme", category: .income),
            Self.tx("transfer", accountId: "savings", itemId: "item-b", amount: 250, date: "2026-06-08", merchant: "Bank", category: .transferOut),
            Self.tx("invalid", accountId: "checking", itemId: "item-a", amount: 12, date: "not-a-date", merchant: "Cafe", category: nil),
        ]

        let index = TransactionDerivedIndex(transactions: transactions)

        #expect(index.entries.count == 4)
        #expect(index.entries(forAccountId: "checking").map(\.transaction.id) == ["coffee", "payroll", "invalid"])
        #expect(index.entries(forItemId: "item-b").map(\.transaction.id) == ["transfer"])
        #expect(index.entries(forMerchantName: "Cafe").map(\.transaction.id) == ["coffee", "invalid"])
        #expect(index.categoryTotals[.foodAndDrink] == 6)
        #expect(index.categoryTotals[.other] == 12)
        #expect(index.categoryTotals[.income] == nil)
        #expect(index.recentFeedEntries.map(\.transaction.id) == ["coffee", "payroll", "transfer", "invalid"])
        #expect(index.latestTransactionDate == Formatters.parseTransactionDate("2026-06-10"))
        #expect(index.entries.first?.isExpense == true)
        #expect(index.entries[1].isIncome == true)
        #expect(index.entries[2].isTransfer == true)
        #expect(index.entries[3].parsedDate == nil)
    }

    @Test("Account activity summary and feed output match indexed adapter")
    func accountActivitySummaryAndFeedUseIndex() {
        let transactions = [
            Self.tx("old", accountId: "checking", amount: 10, date: "2026-01-13", category: .foodAndDrink),
            Self.tx("other", accountId: "credit", amount: 999, date: "2026-01-16", category: .shopping),
            Self.tx("pending", accountId: "checking", amount: 30, date: "2026-01-15", category: .foodAndDrink, pending: true),
            Self.tx("income", accountId: "checking", amount: -100, date: "2026-01-14", category: .income),
            Self.tx("invalid", accountId: "checking", amount: 8, date: "not-a-date", category: .other),
        ]
        let index = TransactionDerivedIndex(transactions: transactions)

        let arraySummary = AccountActivitySummary.recent(
            from: transactions.filter { $0.accountId == "checking" },
            now: Formatters.parseTransactionDate("2026-01-15"),
            days: 3
        )
        let indexedSummary = AccountActivitySummary.recent(
            from: index.entries(forAccountId: "checking"),
            now: Formatters.parseTransactionDate("2026-01-15"),
            days: 3
        )
        let snapshot = AccountTransactionFeed.activitySnapshot(forAccountId: "checking", in: index)

        #expect(indexedSummary == arraySummary)
        #expect(snapshot.transactions.map(\.id) == ["pending", "income", "old", "invalid"])
        #expect(snapshot.latestTransactionDate == "2026-01-15")
        #expect(snapshot.recentSummary == AccountActivitySummary.recent(from: snapshot.transactions))
    }

    @Test("Recurring detector accepts a shared transaction index")
    func recurringDetectorAcceptsIndex() throws {
        let transactions = [
            Self.tx("jan", amount: 10, date: "2026-01-15", merchant: "StreamCo", category: .subscriptions),
            Self.tx("feb", amount: 10, date: "2026-02-15", merchant: "StreamCo", category: .subscriptions),
            Self.tx("mar", amount: 11, date: "2026-03-15", merchant: "StreamCo", category: .subscriptions),
            Self.tx("income", amount: -100, date: "2026-03-15", merchant: "StreamCo", category: .income),
        ]

        let recurring = try #require(RecurringDetector.detect(from: TransactionDerivedIndex(transactions: transactions)).first)

        #expect(recurring.merchantName == "StreamCo")
        #expect(recurring.frequency == .monthly)
        #expect(recurring.transactionCount == 3)
        #expect(abs(recurring.averageAmount - (31.0 / 3.0)) < 0.001)
        #expect(recurring.latestAmount == 11)
        #expect(recurring.lastDate == "2026-03-15")
        #expect(recurring.nextExpectedDate == "2026-04-15")
    }

    @Test("Synthetic 5k transaction index parses dates once during reusable construction")
    func syntheticIndexParsesDatesOnce() {
        let transactions = (0..<5_200).map { offset in
            let day = (offset % 28) + 1
            return Self.tx(
                "tx-\(offset)",
                accountId: offset.isMultiple(of: 2) ? "checking" : "card",
                amount: offset.isMultiple(of: 17) ? -2_000 : Double((offset % 90) + 1),
                date: String(format: "2026-05-%02d", day),
                merchant: "Merchant \(offset % 40)",
                category: offset.isMultiple(of: 17) ? .income : .foodAndDrink,
                pending: offset.isMultiple(of: 23)
            )
        }
        let counter = ParseCounter()

        let index = TransactionDerivedIndex(transactions: transactions) { rawDate in
            counter.increment()
            return Formatters.parseTransactionDate(rawDate)
        }

        #expect(counter.value == transactions.count)
        _ = AccountActivitySummary.recent(from: index, now: Formatters.parseTransactionDate("2026-05-28"))
        _ = AccountTransactionFeed.activitySnapshot(forAccountId: "checking", in: index)
        _ = RecurringDetector.detect(from: index)
        _ = index.categoryTotals
        #expect(counter.value == transactions.count)
        #expect(index.entries.count == 5_200)
        #expect(index.accountBuckets.count == 2)
        #expect(index.merchantBuckets.count == 40)
    }

    private static func tx(
        _ id: String,
        accountId: String = "checking",
        itemId: String? = "item",
        amount: Double,
        date: String,
        merchant: String? = nil,
        category: SpendingCategory? = nil,
        pending: Bool = false
    ) -> TransactionDTO {
        TransactionDTO(
            id: id,
            itemId: itemId,
            accountId: accountId,
            amount: amount,
            date: date,
            name: merchant ?? id,
            merchantName: merchant,
            category: category,
            pending: pending
        )
    }
}

private final class ParseCounter: @unchecked Sendable {
    private let lock = NSLock()
    private var count = 0

    var value: Int {
        lock.lock()
        defer { lock.unlock() }
        return count
    }

    func increment() {
        lock.lock()
        count += 1
        lock.unlock()
    }
}
