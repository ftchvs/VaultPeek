import Foundation
import Testing
@testable import PlaidBarCore

@Suite("Finance snapshot builder")
struct FinanceSnapshotBuilderTests {
    private let asOf = Date(timeIntervalSince1970: 1_780_000_000) // fixed reference

    @Test("Builder reuses SafeToSpendCalculator and MenuBarSummary for headline figures")
    func builderReusesCoreMath() throws {
        let accounts = [
            depository(name: "Checking", available: 3_000),
            depository(name: "Savings", available: 5_000),
            credit(name: "Card", current: 400, limit: 2_000),
        ]
        let recurring: [RecurringTransaction] = []

        let snapshot = FinanceSnapshotBuilder.make(
            accounts: accounts,
            recurringTransactions: recurring,
            isMasked: false,
            generatedAt: asOf
        )

        let expectedSafeToSpend = SafeToSpendCalculator.compute(
            accounts: accounts,
            recurringTransactions: recurring,
            asOf: asOf
        )
        #expect(snapshot.safeToSpend == expectedSafeToSpend.amount)
        // totalBalance is the sum of included cash accounts (spendable balance),
        // NOT net worth — investments are excluded and credit debt is not
        // subtracted. Here: 3_000 + 5_000 = 8_000.
        #expect(snapshot.totalBalance == 8_000)
        // Two depository accounts surface as display-safe balances.
        #expect(snapshot.accountBalances.count == 2)
        #expect(snapshot.accountBalances.contains { $0.displayName == "Checking" })
        // Credit account is not a "spendable cash" account, so it's excluded from
        // the per-account balances list but still drives utilization.
        #expect(!snapshot.accountBalances.contains { $0.displayName == "Card" })
        #expect(snapshot.creditUtilization == 20) // 400 / 2000 * 100
    }

    @Test("Masked snapshot is value-free on disk (defense in depth)")
    func maskedSnapshotIsValueFree() {
        // Even with real accounts, credit, and bills, a masked snapshot must carry
        // no real figures — only the flag, timestamp, and currency survive.
        let referenceDay = Calendar.current.startOfDay(for: asOf)
        let recurring = [
            recurringStream(
                merchant: "Rent",
                amount: 1_800,
                next: dateString(byAdding: 1, to: referenceDay),
                category: .billsAndUtilities
            ),
        ]
        let snapshot = FinanceSnapshotBuilder.make(
            accounts: [
                depository(name: "Checking", available: 1_000),
                credit(name: "Card", current: 400, limit: 2_000),
            ],
            recurringTransactions: recurring,
            safeToSpendInputs: SafeToSpendInputs(horizon: .days(2)),
            isMasked: true,
            generatedAt: asOf
        )
        #expect(snapshot.isMasked)
        #expect(snapshot.safeToSpend == 0)
        #expect(snapshot.totalBalance == 0)
        #expect(snapshot.accountBalances.isEmpty)
        #expect(snapshot.nextRecurringBills.isEmpty)
        #expect(snapshot.creditUtilization == nil)
        #expect(snapshot.generatedAt == asOf)
    }

    @Test("Credit-only snapshot is not considered empty")
    func creditOnlySnapshotIsNotEmpty() {
        // A paid-off credit user has no cash accounts and no bills, but a usable
        // utilization — the intents must not treat that as "no data".
        let snapshot = FinanceSnapshotBuilder.make(
            accounts: [credit(name: "Card", current: 400, limit: 2_000)],
            recurringTransactions: [],
            isMasked: false,
            generatedAt: asOf
        )
        #expect(snapshot.accountBalances.isEmpty)
        #expect(snapshot.totalBalance == 0)
        #expect(snapshot.creditUtilization == 20)
        #expect(!snapshot.isEmpty)
    }

    @Test("Upcoming bills include dated outflows in-window and exclude income")
    func upcomingBillsFilterToOutflowsInWindow() throws {
        // asOf is 2026-05-29; end-of-month horizon is 2026-05-31. Build dated
        // recurrings relative to that window.
        let referenceDay = Calendar.current.startOfDay(for: asOf)
        let inWindow = dateString(byAdding: 1, to: referenceDay)
        let outOfWindow = dateString(byAdding: 120, to: referenceDay)

        let recurring = [
            recurringStream(merchant: "Rent", amount: 1_800, next: inWindow, category: .billsAndUtilities),
            recurringStream(merchant: "Paycheck", amount: 5_000, next: inWindow, category: .income),
            recurringStream(merchant: "FarOff", amount: 30, next: outOfWindow, category: .subscriptions),
        ]

        let snapshot = FinanceSnapshotBuilder.make(
            accounts: [depository(name: "Checking", available: 4_000)],
            recurringTransactions: recurring,
            safeToSpendInputs: SafeToSpendInputs(horizon: .days(2)),
            isMasked: false,
            generatedAt: asOf
        )

        let merchants = snapshot.nextRecurringBills.map(\.merchantName)
        #expect(merchants.contains("Rent"))
        #expect(!merchants.contains("Paycheck"))    // income excluded
        #expect(!merchants.contains("FarOff"))      // out of horizon
    }

    @Test("Upcoming bills are sorted soonest-first")
    func upcomingBillsSortedSoonestFirst() throws {
        let referenceDay = Calendar.current.startOfDay(for: asOf)
        let soon = dateString(byAdding: 1, to: referenceDay)
        let later = dateString(byAdding: 3, to: referenceDay)

        let recurring = [
            recurringStream(merchant: "Later", amount: 50, next: later, category: .subscriptions),
            recurringStream(merchant: "Soon", amount: 20, next: soon, category: .billsAndUtilities),
        ]

        let snapshot = FinanceSnapshotBuilder.make(
            accounts: [depository(name: "Checking", available: 4_000)],
            recurringTransactions: recurring,
            safeToSpendInputs: SafeToSpendInputs(horizon: .days(5)),
            isMasked: false,
            generatedAt: asOf
        )

        #expect(snapshot.nextRecurringBills.map(\.merchantName) == ["Soon", "Later"])
    }

    // MARK: - Spending this period (AND-586)

    @Test("Builder computes month-to-date spend + top categories from transactions")
    func builderComputesMonthToDateSpending() {
        // asOf is 2026-05-28; month-to-date covers 2026-05-01 onward.
        let transactions = [
            expense("a", amount: 120, date: "2026-05-03", category: .foodAndDrink),
            expense("b", amount: 80, date: "2026-05-10", category: .foodAndDrink),
            expense("c", amount: 150, date: "2026-05-20", category: .shopping),
            // Income (negative) must not count as spend.
            income("d", amount: 5_000, date: "2026-05-15"),
            // Prior-month expense must be excluded from the month-to-date total.
            expense("e", amount: 999, date: "2026-04-29", category: .travel),
        ]

        let snapshot = FinanceSnapshotBuilder.make(
            accounts: [depository(name: "Checking", available: 4_000)],
            recurringTransactions: [],
            isMasked: false,
            transactions: transactions,
            generatedAt: asOf
        )

        // 120 + 80 + 150 = 350; the prior-month 999 and the income are excluded.
        #expect(snapshot.periodSpending == 350)
        // Food & Drink (200) leads Shopping (150).
        #expect(snapshot.topSpendingCategories.first?.category == .foodAndDrink)
        #expect(snapshot.topSpendingCategories.first?.amount == 200)
        #expect(snapshot.topSpendingCategories.count == 2)
    }

    @Test("Masked snapshot carries no spending figures (defense in depth)")
    func maskedSnapshotHasNoSpending() {
        let transactions = [expense("a", amount: 500, date: "2026-05-03", category: .shopping)]
        let snapshot = FinanceSnapshotBuilder.make(
            accounts: [depository(name: "Checking", available: 4_000)],
            recurringTransactions: [],
            isMasked: true,
            transactions: transactions,
            generatedAt: asOf
        )
        #expect(snapshot.periodSpending == 0)
        #expect(snapshot.topSpendingCategories.isEmpty)
    }

    @Test("No transactions yields zero spend (server-less / demo path)")
    func noTransactionsYieldsZeroSpend() {
        let snapshot = FinanceSnapshotBuilder.make(
            accounts: [depository(name: "Checking", available: 4_000)],
            recurringTransactions: [],
            isMasked: false,
            generatedAt: asOf
        )
        #expect(snapshot.periodSpending == 0)
        #expect(snapshot.topSpendingCategories.isEmpty)
    }

    // MARK: - Helpers

    private func expense(
        _ id: String,
        amount: Double,
        date: String,
        category: SpendingCategory
    ) -> TransactionDTO {
        TransactionDTO(id: id, accountId: "checking", amount: amount, date: date, name: id, category: category)
    }

    private func income(_ id: String, amount: Double, date: String) -> TransactionDTO {
        TransactionDTO(id: id, accountId: "checking", amount: -amount, date: date, name: id, category: .income)
    }


    private func depository(name: String, available: Double) -> AccountDTO {
        AccountDTO(
            id: "acct-\(name)",
            itemId: "item-1",
            name: name,
            type: .depository,
            balances: BalanceDTO(available: available, current: available)
        )
    }

    private func credit(name: String, current: Double, limit: Double) -> AccountDTO {
        AccountDTO(
            id: "acct-\(name)",
            itemId: "item-1",
            name: name,
            type: .credit,
            balances: BalanceDTO(current: current, limit: limit)
        )
    }

    private func recurringStream(
        merchant: String,
        amount: Double,
        next: String,
        category: SpendingCategory
    ) -> RecurringTransaction {
        RecurringTransaction(
            merchantName: merchant,
            frequency: .monthly,
            averageAmount: amount,
            lastDate: "2026-04-29",
            nextExpectedDate: next,
            category: category,
            transactionCount: 4,
            confidence: 0.9
        )
    }

    private func dateString(byAdding days: Int, to date: Date) -> String {
        let target = Calendar.current.date(byAdding: .day, value: days, to: date) ?? date
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd"
        formatter.timeZone = .current
        return formatter.string(from: target)
    }
}
