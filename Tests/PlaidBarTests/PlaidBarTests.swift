import Testing
@testable import PlaidBarCore
// Foundation symbols available via PlaidBarCore's transitive import

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

        // Net = 8200 + 5100 - 850.68 = 12449.32 (mirrors AppState.netBalance)
        let net = accounts.reduce(0.0) { total, account in
            switch account.type {
            case .depository, .investment:
                return total + account.balances.effectiveBalance
            case .credit, .loan:
                return total - abs(account.balances.current ?? 0)
            case .other:
                return total + account.balances.effectiveBalance
            }
        }

        #expect(abs(net - 12449.32) < 0.01)
    }

    @Test("Net balance empty accounts")
    func netBalanceEmpty() {
        let accounts: [AccountDTO] = []
        let net = accounts.reduce(0.0) { total, account in
            switch account.type {
            case .depository, .investment:
                return total + account.balances.effectiveBalance
            case .credit, .loan:
                return total - abs(account.balances.current ?? 0)
            case .other:
                return total + account.balances.effectiveBalance
            }
        }
        #expect(net == 0.0)
    }

    @Test("Net balance with investment and loan")
    func netBalanceInvestmentLoan() {
        let accounts = [
            AccountDTO(id: "1", itemId: "i", name: "Brokerage", type: .investment, balances: BalanceDTO(available: 50000)),
            AccountDTO(id: "2", itemId: "i", name: "Auto Loan", type: .loan, balances: BalanceDTO(current: -12000)),
        ]

        let net = accounts.reduce(0.0) { total, account in
            switch account.type {
            case .depository, .investment:
                return total + account.balances.effectiveBalance
            case .credit, .loan:
                return total - abs(account.balances.current ?? 0)
            case .other:
                return total + account.balances.effectiveBalance
            }
        }

        #expect(abs(net - 38000) < 0.01)
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

        let expenses = transactions.filter { !$0.isIncome }
        let grouped = Dictionary(grouping: expenses) { $0.category ?? .other }
        let spending = grouped.map { ($0.key, $0.value.reduce(0.0) { $0 + $1.displayAmount }) }

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
        let expenses = transactions.filter { !$0.isIncome }
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
            TransactionDTO(id: "tx1", accountId: "a1", amount: 10, date: "2026-01-15", name: "X"),
            TransactionDTO(id: "tx2", accountId: "a3", amount: 20, date: "2026-01-15", name: "Y"),
        ]
        transactions.removeAll { accountIdsForItem.contains($0.accountId) }
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
}
