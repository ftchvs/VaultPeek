import Foundation
import Testing
@testable import PlaidBarCore

/// Tests for app-level logic: view model calculations, client-side data
/// processing, and business rules used by the PlaidBar macOS app.
///
/// Note: PlaidBar is an executable target with @main (SwiftUI app), so we
/// cannot @testable import it directly. These tests exercise the shared
/// PlaidBarCore types that the app depends on, verifying the calculations
/// and data transformations the app performs.
@Suite("PlaidBar App Tests")
struct PlaidBarTests {

    // MARK: - Account Type Categorization

    @Test("AccountDTO types correctly categorized")
    func accountTypes() {
        let checking = AccountDTO(id: "1", itemId: "i", name: "Checking", type: .depository, balances: BalanceDTO(current: 5000))
        let credit = AccountDTO(id: "2", itemId: "i", name: "Amex", type: .credit, balances: BalanceDTO(current: -850, limit: 10000))

        #expect(checking.type == .depository)
        #expect(credit.type == .credit)
        #expect(credit.balances.utilizationPercent! == 8.5)
    }

    // MARK: - Net Balance Calculation

    @Test("Net balance calculation")
    func netBalanceCalculation() {
        let accounts = [
            AccountDTO(id: "1", itemId: "i", name: "Checking", type: .depository, balances: BalanceDTO(available: 8200)),
            AccountDTO(id: "2", itemId: "i", name: "Savings", type: .depository, balances: BalanceDTO(available: 5100)),
            AccountDTO(id: "3", itemId: "i", name: "Amex", type: .credit, balances: BalanceDTO(current: -850.68)),
        ]

        let net = MenuBarSummary.netCash(from: accounts)

        #expect(abs(net - 12449.32) < 0.01)
    }

    @Test("Net balance empty accounts")
    func netBalanceEmpty() {
        let accounts: [AccountDTO] = []

        #expect(MenuBarSummary.netCash(from: accounts) == 0.0)
    }

    @Test("Net balance with investment and loan")
    func netBalanceInvestmentLoan() {
        let accounts = [
            AccountDTO(id: "1", itemId: "i", name: "Brokerage", type: .investment, balances: BalanceDTO(available: 50000)),
            AccountDTO(id: "2", itemId: "i", name: "Auto Loan", type: .loan, balances: BalanceDTO(current: -12000)),
        ]

        let net = MenuBarSummary.netCash(from: accounts)

        #expect(abs(net - 38000) < 0.01)
    }

    @Test("Credit summary debt excludes loans when card is labeled credit")
    func creditSummaryDebtExcludesLoans() {
        let accounts = [
            AccountDTO(id: "1", itemId: "i", name: "Auto Loan", type: .loan, balances: BalanceDTO(current: -12000)),
            AccountDTO(id: "2", itemId: "i", name: "Credit", type: .credit, balances: BalanceDTO(current: -450, limit: nil)),
        ]

        let creditOnlyDebt = MenuBarSummary.totalDebt(from: accounts.filter { $0.type == .credit })

        #expect(abs(creditOnlyDebt - 450) < 0.01)
    }

    // MARK: - Spending Aggregation

    @Test("Spending aggregation by category")
    func spendingAggregation() {
        let transactions = [
            TransactionDTO(id: "1", accountId: "a", amount: 67, date: "2026-01-15", name: "Whole Foods", category: .foodAndDrink),
            TransactionDTO(id: "2", accountId: "a", amount: 23, date: "2026-01-15", name: "Uber", category: .transportation),
            TransactionDTO(id: "3", accountId: "a", amount: 45, date: "2026-01-14", name: "Restaurant", category: .foodAndDrink),
            TransactionDTO(id: "4", accountId: "a", amount: -1200, date: "2026-01-14", name: "Stripe", category: .income),
        ]

        let spending = SpendingSummary.spendingByCategory(from: transactions)

        let foodTotal = spending.first { $0.0 == .foodAndDrink }?.1
        #expect(foodTotal == 112)

        let transportTotal = spending.first { $0.0 == .transportation }?.1
        #expect(transportTotal == 23)
    }

    @Test("Spending excludes income")
    func spendingExcludesIncome() {
        let transactions = [
            TransactionDTO(id: "1", accountId: "a", amount: -5000, date: "2026-01-15", name: "Salary", category: .income),
            TransactionDTO(id: "2", accountId: "a", amount: -200, date: "2026-01-15", name: "Refund", category: .income),
        ]
        let expenses = SpendingSummary.expenseTransactions(from: transactions)
        #expect(expenses.isEmpty)
    }

    // MARK: - Transaction Grouping

    @Test("Transaction grouping by date")
    func transactionGrouping() {
        let transactions = [
            TransactionDTO(id: "1", accountId: "a", amount: 67, date: "2026-01-15", name: "Whole Foods"),
            TransactionDTO(id: "2", accountId: "a", amount: 23, date: "2026-01-15", name: "Uber"),
            TransactionDTO(id: "3", accountId: "a", amount: 45, date: "2026-01-14", name: "Shell"),
        ]

        let grouped = Dictionary(grouping: transactions) { $0.date }
        #expect(grouped.count == 2)
        #expect(grouped["2026-01-15"]?.count == 2)
        #expect(grouped["2026-01-14"]?.count == 1)
    }

    @Test("Transaction sorting by date")
    func transactionSorting() {
        let transactions = [
            TransactionDTO(id: "1", accountId: "a", amount: 10, date: "2026-01-10", name: "Oldest"),
            TransactionDTO(id: "2", accountId: "a", amount: 20, date: "2026-01-15", name: "Newest"),
            TransactionDTO(id: "3", accountId: "a", amount: 30, date: "2026-01-12", name: "Middle"),
        ]

        let sorted = transactions.sorted { $0.date > $1.date }
        #expect(sorted[0].name == "Newest")
        #expect(sorted[1].name == "Middle")
        #expect(sorted[2].name == "Oldest")
    }

    // MARK: - Credit Utilization Warning

    @Test("Credit utilization warning threshold")
    func creditWarning() {
        let threshold = PlaidBarConstants.creditUtilizationWarningThreshold

        let low = BalanceDTO(current: -200, limit: 10000)
        #expect(low.utilizationPercent! < threshold)

        let high = BalanceDTO(current: -4200, limit: 5000)
        #expect(high.utilizationPercent! > threshold)
    }

    @Test("Credit utilization exact threshold")
    func creditExactThreshold() {
        let threshold = PlaidBarConstants.creditUtilizationWarningThreshold
        let atThreshold = BalanceDTO(current: -300, limit: 1000)
        #expect(atThreshold.utilizationPercent! == threshold)
    }

    // MARK: - LinkResponse

    @Test("LinkResponse Codable")
    func linkResponseCodable() throws {
        let response = LinkResponse(linkToken: "token_123", linkUrl: "https://example.com/link")
        let data = try JSONEncoder().encode(response)
        let decoded = try JSONDecoder().decode(LinkResponse.self, from: data)
        #expect(decoded.linkToken == "token_123")
        #expect(decoded.linkUrl == "https://example.com/link")
    }

    // MARK: - ServerStatus

    @Test("ServerStatus Codable")
    func serverStatusCodable() throws {
        let status = ServerStatus(version: "0.1.0", environment: .sandbox, itemCount: 2)
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        let data = try encoder.encode(status)
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        let decoded = try decoder.decode(ServerStatus.self, from: data)
        #expect(decoded.version == "0.1.0")
        #expect(decoded.environment == .sandbox)
        #expect(decoded.itemCount == 2)
        #expect(decoded.credentialsConfigured)
        #expect(decoded.storagePath == LocalDataStore.displayPath)
        #expect(decoded.syncReady)
    }

    // MARK: - Account Filtering (mirrors AppState computed properties)

    @Test("Filter credit accounts")
    func filterCreditAccounts() {
        let accounts = [
            AccountDTO(id: "1", itemId: "i", name: "Checking", type: .depository, balances: BalanceDTO()),
            AccountDTO(id: "2", itemId: "i", name: "Amex", type: .credit, balances: BalanceDTO()),
            AccountDTO(id: "3", itemId: "i", name: "Visa", type: .credit, balances: BalanceDTO()),
            AccountDTO(id: "4", itemId: "i", name: "Savings", type: .depository, balances: BalanceDTO()),
        ]

        let creditAccounts = accounts.filter { $0.type == .credit }
        #expect(creditAccounts.count == 2)

        let depositoryAccounts = accounts.filter { $0.type == .depository }
        #expect(depositoryAccounts.count == 2)
    }

    // MARK: - Transaction Removal (mirrors AppState.syncTransactions)

    @Test("Transaction removal by IDs")
    func transactionRemoval() {
        var transactions = [
            TransactionDTO(id: "tx1", accountId: "a", amount: 10, date: "2026-01-15", name: "A"),
            TransactionDTO(id: "tx2", accountId: "a", amount: 20, date: "2026-01-15", name: "B"),
            TransactionDTO(id: "tx3", accountId: "a", amount: 30, date: "2026-01-15", name: "C"),
        ]

        let removedIds = ["tx1", "tx3"]
        transactions.removeAll { removedIds.contains($0.id) }

        #expect(transactions.count == 1)
        #expect(transactions[0].id == "tx2")
    }

    // MARK: - Account Removal (mirrors AppState.removeAccount)

    @Test("Account removal by itemId")
    func accountRemoval() {
        var accounts = [
            AccountDTO(id: "a1", itemId: "item_1", name: "Checking", type: .depository, balances: BalanceDTO()),
            AccountDTO(id: "a2", itemId: "item_1", name: "Savings", type: .depository, balances: BalanceDTO()),
            AccountDTO(id: "a3", itemId: "item_2", name: "Amex", type: .credit, balances: BalanceDTO()),
        ]

        let removedItemId = "item_1"
        let accountIdsForItem = Set(accounts.filter { $0.itemId == removedItemId }.map(\.id))
        accounts.removeAll { $0.itemId == removedItemId }

        #expect(accounts.count == 1)
        #expect(accounts[0].id == "a3")
        #expect(accountIdsForItem == Set(["a1", "a2"]))

        // Verify transaction cleanup would work
        var transactions = [
            TransactionDTO(id: "tx1", itemId: "item_1", accountId: "stale_a1", amount: 10, date: "2026-01-15", name: "X"),
            TransactionDTO(id: "tx2", itemId: "item_2", accountId: "a3", amount: 20, date: "2026-01-15", name: "Y"),
            TransactionDTO(id: "tx3", accountId: "a2", amount: 30, date: "2026-01-15", name: "Legacy")
        ]
        transactions.removeAll { transaction in
            transaction.itemId == removedItemId ||
                (transaction.itemId == nil && accountIdsForItem.contains(transaction.accountId))
        }
        #expect(transactions.count == 1)
        #expect(transactions[0].accountId == "a3")
    }

    // MARK: - Currency Format

    @Test("Currency format compact has no decimals")
    func currencyCompact() {
        let compact = Formatters.currency(1234.56, format: .compact)
        #expect(!compact.isEmpty)
        #expect(!compact.contains(".56"))
    }

    @Test("Currency format abbreviated")
    func currencyAbbreviated() {
        let abbreviated = Formatters.currency(1234.56, format: .abbreviated)
        #expect(abbreviated.contains("1.2K"))
    }

    // MARK: - Max Recent Transactions

    @Test("Max recent transactions limit")
    func maxRecentTransactions() {
        var transactions: [TransactionDTO] = []
        for i in 0..<100 {
            transactions.append(TransactionDTO(
                id: "tx_\(i)",
                accountId: "a",
                amount: Double(i),
                date: "2026-01-\(String(format: "%02d", (i % 28) + 1))",
                name: "Transaction \(i)"
            ))
        }

        let recent = Array(
            transactions.sorted { $0.date > $1.date }
                .prefix(PlaidBarConstants.maxRecentTransactions)
        )

        #expect(recent.count == PlaidBarConstants.maxRecentTransactions)
        #expect(recent.count == 50)
    }

    // MARK: - Account Transaction Filtering (mirrors AppState.transactionsForAccount)

    @Test("Filter transactions by account ID")
    func transactionsByAccount() {
        let transactions = [
            TransactionDTO(id: "1", accountId: "checking", amount: 50, date: "2026-01-15", name: "A"),
            TransactionDTO(id: "2", accountId: "credit", amount: 30, date: "2026-01-15", name: "B"),
            TransactionDTO(id: "3", accountId: "checking", amount: 20, date: "2026-01-14", name: "C"),
            TransactionDTO(id: "4", accountId: "savings", amount: 10, date: "2026-01-13", name: "D"),
        ]

        let checkingTxns = transactions.filter { $0.accountId == "checking" }
            .sorted { $0.date > $1.date }
        #expect(checkingTxns.count == 2)
        #expect(checkingTxns[0].id == "1")
        #expect(checkingTxns[1].id == "3")
    }

    // MARK: - Merchant Transaction Filtering (mirrors AppState.transactionsForMerchant)

    @Test("Filter transactions by merchant excluding current")
    func transactionsByMerchant() {
        let transactions = [
            TransactionDTO(id: "1", accountId: "a", amount: 15.99, date: "2026-03-15", name: "NETFLIX", merchantName: "Netflix"),
            TransactionDTO(id: "2", accountId: "a", amount: 15.99, date: "2026-02-15", name: "NETFLIX", merchantName: "Netflix"),
            TransactionDTO(id: "3", accountId: "a", amount: 15.99, date: "2026-01-15", name: "NETFLIX", merchantName: "Netflix"),
            TransactionDTO(id: "4", accountId: "a", amount: 50, date: "2026-03-15", name: "Other", merchantName: "Other"),
        ]

        let otherNetflix = transactions.filter { $0.merchantName == "Netflix" && $0.id != "1" }
            .sorted { $0.date > $1.date }
        #expect(otherNetflix.count == 2)
        #expect(otherNetflix[0].id == "2")
        #expect(otherNetflix[1].id == "3")
    }

    // MARK: - Spending Delta Calculation (mirrors SpendingView logic)

    @Test("Spending delta calculation")
    func spendingDelta() {
        let transactions = [
            // Current month
            TransactionDTO(id: "1", accountId: "a", amount: 100, date: "2026-03-15", name: "A", category: .foodAndDrink),
            TransactionDTO(id: "2", accountId: "a", amount: 200, date: "2026-03-10", name: "B", category: .shopping),
            // Previous month
            TransactionDTO(id: "3", accountId: "a", amount: 150, date: "2026-02-15", name: "C", category: .foodAndDrink),
            TransactionDTO(id: "4", accountId: "a", amount: 100, date: "2026-02-10", name: "D", category: .shopping),
            // Income (should be excluded)
            TransactionDTO(id: "5", accountId: "a", amount: -3000, date: "2026-03-01", name: "Salary", category: .income),
        ]

        let summary = SpendingSummary.periodSummary(
            from: transactions,
            currentStart: "2026-03-01",
            previousStart: "2026-02-01"
        )

        #expect(summary.currentTotal == 300)
        #expect(summary.previousTotal == 250)
        #expect(summary.delta == 50)
        #expect(abs(summary.deltaPercent - 20.0) < 0.01)
    }

    // MARK: - Category Filter Logic (mirrors TransactionsView)

    @Test("Category filter")
    func categoryFilter() {
        let transactions = [
            TransactionDTO(id: "1", accountId: "a", amount: 50, date: "2026-01-15", name: "Food", category: .foodAndDrink),
            TransactionDTO(id: "2", accountId: "a", amount: 30, date: "2026-01-15", name: "Gas", category: .transportation),
            TransactionDTO(id: "3", accountId: "a", amount: 20, date: "2026-01-14", name: "Lunch", category: .foodAndDrink),
        ]

        let foodOnly = transactions.filter { $0.category == .foodAndDrink }
        #expect(foodOnly.count == 2)
        #expect(foodOnly.allSatisfy { $0.category == .foodAndDrink })
    }

    @Test("Combined category and account filter")
    func combinedFilter() {
        let transactions = [
            TransactionDTO(id: "1", accountId: "checking", amount: 50, date: "2026-01-15", name: "Food", category: .foodAndDrink),
            TransactionDTO(id: "2", accountId: "credit", amount: 30, date: "2026-01-15", name: "Food", category: .foodAndDrink),
            TransactionDTO(id: "3", accountId: "checking", amount: 20, date: "2026-01-14", name: "Gas", category: .transportation),
        ]

        let filtered = transactions.filter { $0.category == .foodAndDrink && $0.accountId == "checking" }
        #expect(filtered.count == 1)
        #expect(filtered[0].id == "1")
    }

    // MARK: - Dashboard Drill-In Surfaces

    @Test("Depository account keeps deeper surfaces as selected-row drill-ins")
    func depositoryDashboardDrillIns() {
        let account = AccountDTO(
            id: "checking",
            itemId: "item",
            name: "Checking",
            type: .depository,
            balances: BalanceDTO(available: 1200)
        )

        #expect(DashboardDrillInSurface.surfaces(for: account) == [.account, .activity, .status])
    }

    @Test("Credit account includes credit detail in selected-row drill-ins")
    func creditDashboardDrillIns() {
        let account = AccountDTO(
            id: "credit",
            itemId: "item",
            name: "Visa",
            type: .credit,
            balances: BalanceDTO(current: -450, limit: 2000)
        )

        #expect(DashboardDrillInSurface.surfaces(for: account) == [.account, .activity, .credit, .status])
    }

    // MARK: - Dashboard Overview Fallback

    @Test("Dashboard overview shows fallback when setup has no demo or synced data")
    func dashboardOverviewFallbackWithoutDemoData() {
        let fallback = DashboardOverviewFallbackState.evaluate(
            isSetupComplete: false,
            isDemoMode: false,
            accountCount: 0,
            transactionCount: 0
        )

        #expect(fallback?.title == "Overview needs data")
        #expect(fallback?.actionTitle == "Choose Data Source")
        #expect(fallback?.detail.contains("Demo data is not loaded yet") == true)
    }

    @Test("Dashboard overview fallback stays hidden once demo or local data exists")
    func dashboardOverviewFallbackHiddenWithData() {
        #expect(DashboardOverviewFallbackState.evaluate(
            isSetupComplete: false,
            isDemoMode: true,
            accountCount: 0,
            transactionCount: 0
        ) == nil)

        #expect(DashboardOverviewFallbackState.evaluate(
            isSetupComplete: true,
            isDemoMode: false,
            accountCount: 1,
            transactionCount: 0
        ) == nil)
    }

    // MARK: - Dashboard Overview Height Budget

    @Test("Dashboard overview budget fits realistic menu-bar height")
    func dashboardOverviewBudgetFitsRealisticPopoverHeight() {
        let budget = DashboardOverviewHeightBudget()

        #expect(DashboardOverviewHeightBudget.realisticPopoverHeight == 660)
        #expect(budget.fitsFirstGlance(visibleAccountRows: 1, includesSelectedDrillIn: true))
        #expect(!budget.fitsFirstGlance(visibleAccountRows: 3, includesSelectedDrillIn: true))
        #expect(budget.estimatedFirstGlanceHeight(visibleAccountRows: 1, includesSelectedDrillIn: true) <= DashboardOverviewHeightBudget.firstGlanceVisibleHeight)
    }

    @Test("Dashboard overview budget expects overflow for longer account lists")
    func dashboardOverviewBudgetScrollsLongerAccountLists() {
        let budget = DashboardOverviewHeightBudget()

        #expect(!budget.fitsFirstGlance(visibleAccountRows: 6, includesSelectedDrillIn: true))
        #expect(budget.fitsFirstGlance(visibleAccountRows: 6, includesSelectedDrillIn: false))
    }

    // MARK: - Notification Trigger Logic

    @Test("Large transaction detection")
    func largeTransactionTrigger() {
        let transactions = [
            TransactionDTO(id: "1", accountId: "a", amount: 650, date: "2026-03-15", name: "Big Purchase"),
            TransactionDTO(id: "4", accountId: "a", amount: 500, date: "2026-03-15", name: "Threshold Purchase"),
            TransactionDTO(id: "2", accountId: "a", amount: 50, date: "2026-03-15", name: "Small"),
            TransactionDTO(id: "3", accountId: "a", amount: -1000, date: "2026-03-15", name: "Income", category: .income),
        ]

        let threshold = 500.0
        let large = NotificationTriggerSelection.largeTransactions(
            from: transactions,
            threshold: threshold
        )
        #expect(large.count == 2)
        #expect(large[0].id == "1")
        #expect(large[1].id == "4")

        let newLarge = NotificationTriggerSelection.largeTransactions(
            from: transactions,
            threshold: threshold,
            excluding: ["1"]
        )
        #expect(newLarge.map(\.id) == ["4"])
    }

    @Test("Low balance detection")
    func lowBalanceTrigger() {
        let accounts = [
            AccountDTO(id: "1", itemId: "i", name: "Checking", type: .depository, balances: BalanceDTO(available: 50)),
            AccountDTO(id: "2", itemId: "i", name: "Savings", type: .depository, balances: BalanceDTO(available: 5000)),
            AccountDTO(id: "3", itemId: "i", name: "Credit", type: .credit, balances: BalanceDTO(current: -100, limit: 1000)),
        ]

        let threshold = 100.0
        let lowBalance = NotificationTriggerSelection.lowBalanceAccounts(
            from: accounts,
            threshold: threshold
        )
        #expect(lowBalance.count == 1)
        #expect(lowBalance[0].id == "1")
    }

    @Test("High utilization detection")
    func highUtilizationTrigger() {
        let accounts = [
            AccountDTO(id: "1", itemId: "i", name: "Amex", type: .credit, balances: BalanceDTO(current: -200, limit: 10000)),
            AccountDTO(id: "2", itemId: "i", name: "Visa", type: .credit, balances: BalanceDTO(current: -4500, limit: 5000)),
            AccountDTO(id: "3", itemId: "i", name: "Store Card", type: .credit, balances: BalanceDTO(current: -300, limit: 1000)),
        ]

        let threshold = 30.0
        let highUtil = NotificationTriggerSelection.highUtilizationAccounts(
            from: accounts,
            threshold: threshold
        )
        #expect(highUtil.count == 1)
        #expect(highUtil[0].id == "2")
    }

    // MARK: - Estimated Monthly Recurring Total

    @Test("Estimated monthly recurring normalizes all frequencies")
    func estimatedMonthlyRecurring() {
        let recurring = [
            RecurringTransaction(merchantName: "Netflix", frequency: .monthly, averageAmount: 15.99, lastDate: "2026-03-15", nextExpectedDate: "2026-04-15", category: .entertainment, transactionCount: 3, confidence: 0.95),
            RecurringTransaction(merchantName: "Gym", frequency: .monthly, averageAmount: 75.00, lastDate: "2026-03-15", nextExpectedDate: "2026-04-15", category: .healthAndFitness, transactionCount: 3, confidence: 0.90),
            RecurringTransaction(merchantName: "Weekly Sub", frequency: .weekly, averageAmount: 5.00, lastDate: "2026-03-15", nextExpectedDate: "2026-03-22", category: .entertainment, transactionCount: 5, confidence: 0.85),
        ]

        // Monthly: 15.99 + 75.00 = 90.99
        // Weekly $5 * (52/12) = ~$21.67
        // Total ≈ $112.66
        let estimated = RecurringSummary.estimatedMonthlyTotal(from: recurring)

        #expect(abs(estimated - 112.66) < 0.01)
    }
}
