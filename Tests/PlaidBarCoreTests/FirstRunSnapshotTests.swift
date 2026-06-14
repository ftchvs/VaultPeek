import Foundation
import Testing
@testable import PlaidBarCore

@Suite("First-run snapshot")
struct FirstRunSnapshotTests {
    private let now = Formatters.parseTransactionDate("2026-06-12")!

    @Test("Evaluates full first-run money snapshot")
    func evaluatesFullSnapshot() {
        let snapshot = FirstRunSnapshot.evaluate(
            accounts: [
                AccountDTO(id: "checking", itemId: "item-a", name: "Checking", type: .depository, balances: BalanceDTO(available: 8_200)),
                AccountDTO(id: "brokerage", itemId: "item-a", name: "Brokerage", type: .investment, balances: BalanceDTO(current: 50_000)),
                AccountDTO(id: "card", itemId: "item-b", name: "Visa", type: .credit, balances: BalanceDTO(current: -1_500, limit: 10_000)),
                AccountDTO(id: "loan", itemId: "item-c", name: "Auto Loan", type: .loan, balances: BalanceDTO(current: -7_250)),
            ],
            transactions: [
                expense("rent-internal", amount: 1_200, date: "2026-06-02", name: "Rent"),
                expense("dental-internal", amount: 900, date: "2026-06-12", name: "Dental"),
                expense("laptop-internal", amount: 750, date: "2026-06-11", name: "Laptop"),
                expense("grocery-internal", amount: 120, date: "2026-06-10", name: "Groceries"),
                expense("old-internal", amount: 300, date: "2026-05-31", name: "Old"),
                expense("future-internal", amount: 2_000, date: "2026-07-01", name: "Future"),
                income("payroll-internal", amount: 5_000, date: "2026-06-05", name: "Payroll"),
                expense("transfer-internal", amount: 1_000, date: "2026-06-07", name: "Transfer", category: .transfer),
            ],
            completionState: readyCompletion(transactionCount: 8),
            now: now
        )

        #expect(snapshot.accountCount == 4)
        #expect(snapshot.transactionCount == 8)
        #expect(snapshot.netWorth == 49_450)
        #expect(snapshot.cashAvailable == 8_200)
        #expect(snapshot.debtTotal == 8_750)
        #expect(snapshot.creditUtilization == 15)
        #expect(snapshot.monthToDateSpend == 2_970)
        #expect(snapshot.transactionState == .ready)
        #expect(snapshot.hasCreditAccounts)
        #expect(snapshot.hasDebtAccounts)
        #expect(snapshot.largeTransactions.map(\.displayName) == ["Dental", "Laptop", "Rent"])
        #expect(snapshot.largeTransactions.map(\.amount) == [900, 750, 1_200])
        #expect(snapshot.largeTransactions.allSatisfy { !$0.id.contains("internal") })
        #expect(snapshot.accessibilitySummary.contains("Net worth $49,450.00"))
        #expect(snapshot.accessibilitySummary.contains("3 recent large transactions"))
    }

    @Test("Handles no credit and no liabilities")
    func handlesNoCreditAndNoLiabilities() {
        let snapshot = FirstRunSnapshot.evaluate(
            accounts: [
                AccountDTO(id: "checking", itemId: "item-a", name: "Checking", type: .depository, balances: BalanceDTO(available: 1_200)),
            ],
            transactions: [
                expense("coffee", amount: 8, date: "2026-06-12", name: "Coffee"),
            ],
            completionState: readyCompletion(transactionCount: 1),
            now: now
        )

        #expect(snapshot.netWorth == 1_200)
        #expect(snapshot.debtTotal == 0)
        #expect(snapshot.creditUtilization == nil)
        #expect(!snapshot.hasCreditAccounts)
        #expect(!snapshot.hasDebtAccounts)
        #expect(snapshot.accessibilitySummary.contains("No credit utilization available"))
    }

    @Test("Marks empty transactions as syncing while first sync is incomplete")
    func marksTransactionsSyncing() {
        let snapshot = FirstRunSnapshot.evaluate(
            accounts: [
                AccountDTO(id: "checking", itemId: "item-a", name: "Checking", type: .depository, balances: BalanceDTO(available: 1_200)),
            ],
            transactions: [],
            completionState: FirstRunCompletionState(
                step: .syncTransactions,
                title: "Accounts loaded",
                detail: "Run the first transaction sync check to finish setup.",
                isReady: false,
                canRetry: true
            ),
            now: now
        )

        #expect(snapshot.transactionState == .syncing)
        #expect(snapshot.monthToDateSpend == nil)
        #expect(snapshot.largeTransactions.isEmpty)
        #expect(snapshot.accessibilitySummary.contains("Transactions are still syncing"))
    }

    @Test("Month-to-date spend is calendar anchored")
    func monthToDateSpendIsCalendarAnchored() {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "Pacific/Kiritimati")!
        let localNow = calendar.date(from: DateComponents(
            timeZone: calendar.timeZone,
            year: 2026,
            month: 6,
            day: 1,
            hour: 0,
            minute: 30
        ))!
        let transactions = [
            expense("month-start", amount: 40, date: "2026-06-01", name: "Month Start"),
            expense("previous-month", amount: 80, date: "2026-05-31", name: "Previous Month"),
            income("income", amount: 100, date: "2026-06-01", name: "Income"),
        ]

        #expect(MenuBarSummary.monthToDateSpend(from: transactions, now: localNow, calendar: calendar) == 40)
    }

    @Test("Presentation appears after first successful account and transaction sync")
    func presentationAppearsAfterFirstSuccessfulSync() {
        let presentation = FirstRunSnapshotPresentation.evaluate(
            accounts: [
                AccountDTO(id: "checking", itemId: "item-a", name: "Checking", type: .depository, balances: BalanceDTO(available: 2_000)),
                AccountDTO(id: "card", itemId: "item-a", name: "Card", type: .credit, balances: BalanceDTO(current: -250, limit: 1_000)),
            ],
            transactions: [
                expense("large", amount: 650, date: "2026-06-12", name: "Appliance"),
            ],
            completionState: readyCompletion(transactionCount: 1),
            isDismissed: false,
            isInitialLoad: false,
            isDemoMode: false,
            now: now
        )

        #expect(presentation?.snapshot.cashAvailable == 2_000)
        #expect(presentation?.snapshot.creditUtilization == 25)
        #expect(presentation?.snapshot.largeTransactions.map(\.displayName) == ["Appliance"])
        #expect(presentation?.subtitle == "Your local account and transaction sync is ready.")
    }

    @Test("Presentation stays hidden while loading, dismissed, demo, or not ready")
    func presentationGatingHidesWhenIneligible() {
        let accounts = [
            AccountDTO(id: "checking", itemId: "item-a", name: "Checking", type: .depository, balances: BalanceDTO(available: 2_000)),
        ]
        let transactions = [
            expense("coffee", amount: 8, date: "2026-06-12", name: "Coffee"),
        ]
        let completion = readyCompletion(transactionCount: 1)

        #expect(FirstRunSnapshotPresentation.evaluate(
            accounts: accounts,
            transactions: transactions,
            completionState: completion,
            isDismissed: true,
            isInitialLoad: false,
            isDemoMode: false,
            now: now
        ) == nil)
        #expect(FirstRunSnapshotPresentation.evaluate(
            accounts: accounts,
            transactions: transactions,
            completionState: completion,
            isDismissed: false,
            isInitialLoad: true,
            isDemoMode: false,
            now: now
        ) == nil)
        #expect(FirstRunSnapshotPresentation.evaluate(
            accounts: accounts,
            transactions: transactions,
            completionState: completion,
            isDismissed: false,
            isInitialLoad: false,
            isDemoMode: true,
            now: now
        ) == nil)
        #expect(FirstRunSnapshotPresentation.evaluate(
            accounts: accounts,
            transactions: [],
            completionState: FirstRunCompletionState(
                step: .syncTransactions,
                title: "Accounts loaded",
                detail: "Run the first transaction sync check to finish setup.",
                isReady: false,
                canRetry: true
            ),
            isDismissed: false,
            isInitialLoad: false,
            isDemoMode: false,
            now: now
        ) == nil)
    }

    @Test("Presentation handles no transaction rows after completed sync")
    func presentationHandlesNoTransactionRows() {
        let presentation = FirstRunSnapshotPresentation.evaluate(
            accounts: [
                AccountDTO(id: "checking", itemId: "item-a", name: "Checking", type: .depository, balances: BalanceDTO(available: 2_000)),
            ],
            transactions: [],
            completionState: readyCompletion(transactionCount: 0),
            isDismissed: false,
            isInitialLoad: false,
            isDemoMode: false,
            now: now
        )

        #expect(presentation?.snapshot.transactionState == .empty)
        #expect(presentation?.snapshot.monthToDateSpend == nil)
        #expect(presentation?.snapshot.largeTransactions.isEmpty == true)
        #expect(presentation?.subtitle == "Accounts are ready; no transaction rows are available yet.")
        #expect(presentation?.primaryAccessibilityLabel.contains("No transactions synced yet") == true)
    }

    @Test("Presentation keeps partial credit data explicit")
    func presentationHandlesPartialCreditData() {
        let presentation = FirstRunSnapshotPresentation.evaluate(
            accounts: [
                AccountDTO(id: "checking", itemId: "item-a", name: "Checking", type: .depository, balances: BalanceDTO(available: 1_200)),
            ],
            transactions: [
                expense("grocery", amount: 120, date: "2026-06-10", name: "Groceries"),
            ],
            completionState: readyCompletion(transactionCount: 1),
            isDismissed: false,
            isInitialLoad: false,
            isDemoMode: false,
            now: now
        )

        #expect(presentation?.snapshot.hasCreditAccounts == false)
        #expect(presentation?.snapshot.creditUtilization == nil)
        #expect(presentation?.primaryAccessibilityLabel.contains("No credit utilization available") == true)
    }

    private func readyCompletion(transactionCount: Int) -> FirstRunCompletionState {
        FirstRunCompletionState(
            step: .ready,
            title: "Dashboard ready",
            detail: "\(transactionCount) transactions synced. VaultPeek is ready.",
            isReady: true,
            canRetry: false
        )
    }

    private func expense(
        _ id: String,
        amount: Double,
        date: String,
        name: String,
        category: SpendingCategory? = nil
    ) -> TransactionDTO {
        TransactionDTO(
            id: id,
            accountId: "checking",
            amount: amount,
            date: date,
            name: name,
            category: category
        )
    }

    private func income(
        _ id: String,
        amount: Double,
        date: String,
        name: String
    ) -> TransactionDTO {
        TransactionDTO(
            id: id,
            accountId: "checking",
            amount: -amount,
            date: date,
            name: name,
            category: .income
        )
    }
}
