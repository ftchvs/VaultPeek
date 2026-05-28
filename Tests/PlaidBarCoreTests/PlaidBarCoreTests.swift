import Testing
@testable import PlaidBarCore
// Foundation symbols available via PlaidBarCore's transitive import

@Suite("PlaidBarCore Tests")
struct PlaidBarCoreTests {

    // MARK: - BalanceDTO Tests

    @Test("BalanceDTO effectiveBalance prefers available")
    func effectiveBalanceAvailable() {
        let balance = BalanceDTO(available: 1000, current: 1200)
        #expect(balance.effectiveBalance == 1000)
    }

    @Test("BalanceDTO effectiveBalance falls back to current")
    func effectiveBalanceCurrent() {
        let balance = BalanceDTO(available: nil, current: 1200)
        #expect(balance.effectiveBalance == 1200)
    }

    @Test("BalanceDTO effectiveBalance defaults to 0")
    func effectiveBalanceDefault() {
        let balance = BalanceDTO()
        #expect(balance.effectiveBalance == 0)
    }

    @Test("BalanceDTO utilization calculated correctly")
    func utilizationPercent() {
        let balance = BalanceDTO(current: 300, limit: 1000)
        #expect(balance.utilizationPercent! == 30.0)
    }

    @Test("BalanceDTO utilization nil without limit")
    func utilizationNilWithoutLimit() {
        let balance = BalanceDTO(current: 300)
        #expect(balance.utilizationPercent == nil)
    }

    @Test("BalanceDTO utilization nil without current")
    func utilizationNilWithoutCurrent() {
        let balance = BalanceDTO(available: 500, limit: 1000)
        #expect(balance.utilizationPercent == nil)
    }

    @Test("BalanceDTO utilization with negative current")
    func utilizationNegativeCurrent() {
        let balance = BalanceDTO(current: -850, limit: 10000)
        #expect(balance.utilizationPercent! == 8.5)
    }

    // MARK: - TransactionDTO Tests

    @Test("TransactionDTO income detection (negative amount)")
    func transactionIncome() {
        let tx = TransactionDTO(id: "1", accountId: "a", amount: -1200, date: "2026-01-15", name: "Stripe")
        #expect(tx.isIncome == true)
        #expect(tx.displayAmount == 1200)
    }

    @Test("TransactionDTO expense detection (positive amount)")
    func transactionExpense() {
        let tx = TransactionDTO(id: "2", accountId: "a", amount: 67, date: "2026-01-15", name: "Whole Foods")
        #expect(tx.isIncome == false)
        #expect(tx.displayAmount == 67)
    }

    @Test("TransactionDTO displayName prefers merchantName")
    func transactionDisplayName() {
        let tx = TransactionDTO(id: "3", accountId: "a", amount: 15, date: "2026-01-15", name: "NFLX*STREAMING", merchantName: "Netflix")
        #expect(tx.displayName == "Netflix")
    }

    @Test("TransactionDTO displayName falls back to name")
    func transactionDisplayNameFallback() {
        let tx = TransactionDTO(id: "4", accountId: "a", amount: 15, date: "2026-01-15", name: "Some Payment")
        #expect(tx.displayName == "Some Payment")
    }

    @Test("TransactionDTO zero amount is not income")
    func transactionZeroAmount() {
        let tx = TransactionDTO(id: "5", accountId: "a", amount: 0, date: "2026-01-15", name: "Void")
        #expect(tx.isIncome == false)
        #expect(tx.displayAmount == 0)
    }

    @Test("Spending heatmap fills every day in range")
    func spendingHeatmapFillsDateRange() {
        let start = Formatters.parseTransactionDate("2026-01-01")!
        let end = Formatters.parseTransactionDate("2026-01-03")!

        let days = SpendingHeatmap.days(
            from: [
                TransactionDTO(id: "1", accountId: "a", amount: 25, date: "2026-01-02", name: "Coffee")
            ],
            startDate: start,
            endDate: end,
            mode: .spending
        )

        #expect(days.map(\.date) == ["2026-01-01", "2026-01-02", "2026-01-03"])
        #expect(days[0].value == 0)
        #expect(days[1].value == 25)
        #expect(days[1].transactionCount == 1)
    }

    @Test("Spending heatmap excludes income and transfers")
    func spendingHeatmapExcludesIncomeAndTransfers() {
        let day = Formatters.parseTransactionDate("2026-01-02")!

        let days = SpendingHeatmap.days(
            from: [
                TransactionDTO(id: "1", accountId: "a", amount: 25, date: "2026-01-02", name: "Coffee"),
                TransactionDTO(id: "2", accountId: "a", amount: -100, date: "2026-01-02", name: "Refund"),
                TransactionDTO(id: "3", accountId: "a", amount: 200, date: "2026-01-02", name: "Transfer", category: .transfer)
            ],
            startDate: day,
            endDate: day,
            mode: .spending
        )

        #expect(days.first?.value == 25)
        #expect(days.first?.transactionCount == 1)
    }

    // MARK: - Menu Bar Summary Tests

    @Test("Menu bar summary calculates net cash")
    func menuBarSummaryNetCash() {
        let accounts = [
            AccountDTO(id: "1", itemId: "i", name: "Checking", type: .depository, balances: BalanceDTO(available: 8_200)),
            AccountDTO(id: "2", itemId: "i", name: "Savings", type: .depository, balances: BalanceDTO(available: 5_100)),
            AccountDTO(id: "3", itemId: "i", name: "Amex", type: .credit, balances: BalanceDTO(current: -850.68)),
        ]

        #expect(abs(MenuBarSummary.netCash(from: accounts) - 12_449.32) < 0.01)
    }

    @Test("Menu bar summary total cash uses depository accounts only")
    func menuBarSummaryTotalCash() {
        let accounts = [
            AccountDTO(id: "1", itemId: "i", name: "Checking", type: .depository, balances: BalanceDTO(available: 8_200)),
            AccountDTO(id: "2", itemId: "i", name: "Brokerage", type: .investment, balances: BalanceDTO(current: 50_000)),
            AccountDTO(id: "3", itemId: "i", name: "Visa", type: .credit, balances: BalanceDTO(current: -1_500, limit: 10_000)),
        ]

        #expect(MenuBarSummary.totalCash(from: accounts) == 8_200)
    }

    @Test("Menu bar summary totals credit and loan debt")
    func menuBarSummaryTotalDebt() {
        let accounts = [
            AccountDTO(id: "1", itemId: "i", name: "Checking", type: .depository, balances: BalanceDTO(available: 8_200)),
            AccountDTO(id: "2", itemId: "i", name: "Visa", type: .credit, balances: BalanceDTO(current: -1_500, limit: 10_000)),
            AccountDTO(id: "3", itemId: "i", name: "Auto Loan", type: .loan, balances: BalanceDTO(current: -7_250)),
            AccountDTO(id: "4", itemId: "i", name: "Brokerage", type: .investment, balances: BalanceDTO(current: 50_000)),
        ]

        #expect(MenuBarSummary.totalDebt(from: accounts) == 8_750)
    }

    @Test("Menu bar summary aggregates credit utilization")
    func menuBarSummaryCreditUtilization() {
        let accounts = [
            AccountDTO(id: "1", itemId: "i", name: "Checking", type: .depository, balances: BalanceDTO(available: 8_200)),
            AccountDTO(id: "2", itemId: "i", name: "Amex", type: .credit, balances: BalanceDTO(current: -1_000, limit: 10_000)),
            AccountDTO(id: "3", itemId: "i", name: "Visa", type: .credit, balances: BalanceDTO(current: -2_000, limit: 5_000)),
        ]

        #expect(MenuBarSummary.creditUtilization(from: accounts) == 20)
    }

    @Test("Menu bar summary recent spend excludes income and transfers")
    func menuBarSummaryRecentSpend() {
        let now = Formatters.parseTransactionDate("2026-01-15")!
        let transactions = [
            TransactionDTO(id: "1", accountId: "a", amount: 25, date: "2026-01-15", name: "Coffee"),
            TransactionDTO(id: "2", accountId: "a", amount: 75, date: "2026-01-10", name: "Groceries"),
            TransactionDTO(id: "3", accountId: "a", amount: -200, date: "2026-01-15", name: "Refund"),
            TransactionDTO(id: "4", accountId: "a", amount: 500, date: "2026-01-15", name: "Transfer", category: .transfer),
            TransactionDTO(id: "5", accountId: "a", amount: 40, date: "2026-01-01", name: "Old")
        ]

        #expect(MenuBarSummary.recentSpend(from: transactions, now: now) == 100)
    }

    @Test("Account activity summary uses recent non-transfer cash flow")
    func accountActivitySummaryRecentCashFlow() {
        let now = Formatters.parseTransactionDate("2026-01-30")!
        let transactions = [
            TransactionDTO(id: "1", accountId: "a", amount: 100, date: "2026-01-30", name: "Groceries"),
            TransactionDTO(id: "2", accountId: "a", amount: -2_000, date: "2026-01-25", name: "Payroll", category: .income),
            TransactionDTO(id: "3", accountId: "a", amount: 250, date: "2026-01-20", name: "Transfer Out", category: .transferOut),
            TransactionDTO(id: "4", accountId: "a", amount: -500, date: "2026-01-18", name: "Transfer In", category: .transfer),
            TransactionDTO(id: "5", accountId: "a", amount: 40, date: "2026-01-10", name: "Pending", pending: true),
            TransactionDTO(id: "6", accountId: "a", amount: 75, date: "2025-12-01", name: "Old")
        ]

        let summary = AccountActivitySummary.recent(from: transactions, now: now)

        #expect(summary.transactionCount == 5)
        #expect(summary.pendingCount == 1)
        #expect(summary.outflowTotal == 140)
        #expect(summary.inflowTotal == 2_000)
        #expect(summary.days == 30)
    }

    @Test("Account presentation picks subtype-aware icons")
    func accountPresentationIcons() {
        let checking = AccountDTO(id: "1", itemId: "i", name: "Checking", type: .depository, subtype: "checking", balances: BalanceDTO(available: 100))
        let savings = AccountDTO(id: "2", itemId: "i", name: "Savings", type: .depository, subtype: "savings", balances: BalanceDTO(available: 100))
        let credit = AccountDTO(id: "3", itemId: "i", name: "Card", type: .credit, subtype: "credit card", balances: BalanceDTO(current: -10, limit: 100))
        let investment = AccountDTO(id: "4", itemId: "i", name: "Brokerage", type: .investment, balances: BalanceDTO(current: 100))
        let loan = AccountDTO(id: "5", itemId: "i", name: "Loan", type: .loan, balances: BalanceDTO(current: -100))

        #expect(AccountPresentation.iconName(for: checking) == "banknote.fill")
        #expect(AccountPresentation.iconName(for: savings) == "tray.full.fill")
        #expect(AccountPresentation.iconName(for: credit) == "creditcard.fill")
        #expect(AccountPresentation.iconName(for: investment) == "chart.line.uptrend.xyaxis")
        #expect(AccountPresentation.iconName(for: loan) == "dollarsign.circle.fill")
    }

    @Test("Account presentation normalizes debt balances")
    func accountPresentationDebtBalances() {
        let checking = AccountDTO(id: "1", itemId: "i", name: "Checking", type: .depository, balances: BalanceDTO(current: 500))
        let credit = AccountDTO(id: "2", itemId: "i", name: "Card", type: .credit, balances: BalanceDTO(current: -125))
        let loan = AccountDTO(id: "3", itemId: "i", name: "Loan", type: .loan, balances: BalanceDTO(current: -750))
        let availableCredit = AccountDTO(id: "4", itemId: "i", name: "Available", type: .credit, balances: BalanceDTO(available: 900))

        #expect(AccountPresentation.isDebt(checking) == false)
        #expect(AccountPresentation.isDebt(credit))
        #expect(AccountPresentation.isDebt(loan))
        #expect(AccountPresentation.displayBalance(for: checking) == 500)
        #expect(AccountPresentation.displayBalance(for: credit) == 125)
        #expect(AccountPresentation.displayBalance(for: loan) == 750)
        #expect(AccountPresentation.displayBalance(for: availableCredit) == 0)
    }

    @Test("Menu bar summary estimates runway from recent monthly spend")
    func menuBarSummaryRunwayMonths() {
        let now = Formatters.parseTransactionDate("2026-01-30")!
        let transactions = [
            TransactionDTO(id: "1", accountId: "a", amount: 1_000, date: "2026-01-30", name: "Rent"),
            TransactionDTO(id: "2", accountId: "a", amount: 500, date: "2026-01-20", name: "Groceries"),
            TransactionDTO(id: "3", accountId: "a", amount: -2_000, date: "2026-01-15", name: "Payroll"),
            TransactionDTO(id: "4", accountId: "a", amount: 200, date: "2025-12-01", name: "Old spend")
        ]

        let months = MenuBarSummary.runwayMonths(cash: 6_000, transactions: transactions, now: now)
        let monthlySpend = MenuBarSummary.runwayMonthlySpend(from: transactions, now: now)

        #expect(months == 4)
        #expect(monthlySpend == 1_500)
        #expect(MenuBarSummary.runwayMonths(cash: 6_000, monthlySpend: monthlySpend) == 4)
        #expect(MenuBarSummary.runwayText(months: months) == "4.0 mo")
        #expect(MenuBarSummary.runwayText(months: nil) == "No spend")
        #expect(MenuBarSummary.runwayText(months: 0.5) == "15d")
        #expect(MenuBarSummary.runwayBasisText(cash: 6_000, monthlySpend: monthlySpend) == "30D spend $1,500")
        #expect(MenuBarSummary.runwayBasisText(cash: 0, monthlySpend: monthlySpend) == "No cash buffer")
        #expect(MenuBarSummary.runwayBasisText(cash: 6_000, monthlySpend: 0) == "No 30D spend")
    }

    @Test("Menu bar summary text supports every mode")
    func menuBarSummaryTextModes() {
        let accounts = [
            AccountDTO(id: "1", itemId: "i", name: "Checking", type: .depository, balances: BalanceDTO(available: 8_200)),
            AccountDTO(id: "2", itemId: "i", name: "Visa", type: .credit, balances: BalanceDTO(current: -1_500, limit: 10_000)),
        ]
        let transactions = [
            TransactionDTO(id: "1", accountId: "a", amount: 25, date: Formatters.transactionDateString(Date()), name: "Coffee")
        ]

        #expect(!MenuBarSummary.text(mode: .netCash, accounts: accounts, transactions: transactions, currencyFormat: .compact).isEmpty)
        #expect(!MenuBarSummary.text(mode: .totalCash, accounts: accounts, transactions: transactions, currencyFormat: .compact).isEmpty)
        #expect(MenuBarSummary.text(mode: .creditUtilization, accounts: accounts, transactions: transactions, currencyFormat: .compact) == "15%")
        #expect(!MenuBarSummary.text(mode: .recentSpend, accounts: accounts, transactions: transactions, currencyFormat: .compact).isEmpty)
        #expect(MenuBarSummary.text(mode: .iconOnly, accounts: accounts, transactions: transactions, currencyFormat: .compact).isEmpty)
    }

    @Test("Server endpoints percent encode item IDs in query and path components")
    func serverEndpointsEncodeItemIds() throws {
        let baseURL = "http://127.0.0.1:8484"
        let itemId = "item with/slash?and&symbols"

        let syncURL = try #require(ServerEndpoint.transactionSyncURL(baseURL: baseURL, itemId: itemId))
        let updateURL = try #require(ServerEndpoint.updateLinkTokenURL(baseURL: baseURL, itemId: itemId))
        let removeURL = try #require(ServerEndpoint.removeItemURL(baseURL: baseURL, itemId: itemId))

        #expect(syncURL.absoluteString == "http://127.0.0.1:8484/api/transactions/sync?item_id=item%20with%2Fslash%3Fand%26symbols")
        #expect(updateURL.absoluteString == "http://127.0.0.1:8484/api/link/update/item%20with%2Fslash%3Fand%26symbols")
        #expect(removeURL.absoluteString == "http://127.0.0.1:8484/api/accounts/item%20with%2Fslash%3Fand%26symbols")
    }

    @Test("Transaction sync reducer upserts and removes transactions")
    func transactionSyncReducerUpsertsAndRemoves() {
        let existing = [
            TransactionDTO(id: "old", accountId: "a", amount: 10, date: "2026-01-01", name: "Old"),
            TransactionDTO(id: "changed", accountId: "a", amount: 20, date: "2026-01-02", name: "Before"),
            TransactionDTO(id: "duplicate", accountId: "a", amount: 30, date: "2026-01-03", name: "First duplicate"),
            TransactionDTO(id: "duplicate", accountId: "a", amount: 40, date: "2026-01-04", name: "Second duplicate")
        ]
        let response = SyncResponse(
            added: [
                TransactionDTO(id: "new", accountId: "a", amount: 50, date: "2026-01-05", name: "New"),
                TransactionDTO(id: "old", accountId: "a", amount: 15, date: "2026-01-01", name: "Old replacement")
            ],
            modified: [
                TransactionDTO(id: "changed", accountId: "a", amount: 25, date: "2026-01-02", name: "After")
            ],
            removed: ["duplicate"],
            hasMore: false
        )

        let transactions = TransactionSyncReducer.applying(response, to: existing)

        #expect(transactions.map(\.id) == ["old", "changed", "new"])
        #expect(transactions.first { $0.id == "old" }?.amount == 15)
        #expect(transactions.first { $0.id == "changed" }?.name == "After")
        #expect(transactions.first { $0.id == "new" }?.amount == 50)
    }

    @Test("Net cashflow heatmap keeps Plaid amount signs")
    func netCashflowHeatmapKeepsSigns() {
        let day = Formatters.parseTransactionDate("2026-01-02")!

        let days = SpendingHeatmap.days(
            from: [
                TransactionDTO(id: "1", accountId: "a", amount: 75, date: "2026-01-02", name: "Groceries"),
                TransactionDTO(id: "2", accountId: "a", amount: -250, date: "2026-01-02", name: "Payroll")
            ],
            startDate: day,
            endDate: day,
            mode: .netCashflow
        )

        #expect(days.first?.value == -175)
        #expect(days.first?.transactionCount == 2)
    }

    // MARK: - AccountDTO Tests

    @Test("AccountDTO Codable roundtrip")
    func accountCodable() throws {
        let account = AccountDTO(
            id: "acc_123",
            itemId: "item_456",
            name: "Chase Checking",
            type: .depository,
            mask: "4567",
            balances: BalanceDTO(available: 8200, current: 8200)
        )
        let data = try JSONEncoder().encode(account)
        let decoded = try JSONDecoder().decode(AccountDTO.self, from: data)
        #expect(decoded.id == "acc_123")
        #expect(decoded.itemId == "item_456")
        #expect(decoded.name == "Chase Checking")
        #expect(decoded.type == .depository)
        #expect(decoded.mask == "4567")
        #expect(decoded.balances.effectiveBalance == 8200)
    }

    @Test("AccountDTO all types")
    func accountTypes() {
        let types: [AccountType] = [.depository, .credit, .loan, .investment, .other]
        for accountType in types {
            let account = AccountDTO(id: "id", itemId: "item", name: "Test", type: accountType, balances: BalanceDTO())
            #expect(account.type == accountType)
        }
    }

    @Test("AccountType Codable roundtrip")
    func accountTypeCodable() throws {
        for accountType in [AccountType.depository, .credit, .loan, .investment, .other] {
            let data = try JSONEncoder().encode(accountType)
            let decoded = try JSONDecoder().decode(AccountType.self, from: data)
            #expect(decoded == accountType)
        }
    }

    // MARK: - SpendingCategory Tests

    @Test("SpendingCategory has display names for all cases")
    func categoryDisplayNames() {
        for category in SpendingCategory.allCases {
            #expect(!category.displayName.isEmpty)
            #expect(!category.iconName.isEmpty)
            #expect(!category.colorHex.isEmpty)
        }
    }

    @Test("SpendingCategory Codable with Plaid values")
    func categoryCodable() throws {
        let json = "\"FOOD_AND_DRINK\""
        let data = json.data(using: .utf8)!
        let decoded = try JSONDecoder().decode(SpendingCategory.self, from: data)
        #expect(decoded == .foodAndDrink)
        #expect(decoded.displayName == "Food & Drink")
    }

    @Test("SpendingCategory all raw values roundtrip")
    func categoryAllRawValues() throws {
        for category in SpendingCategory.allCases {
            let encoded = try JSONEncoder().encode(category)
            let decoded = try JSONDecoder().decode(SpendingCategory.self, from: encoded)
            #expect(decoded == category)
        }
    }

    @Test("SpendingCategory color hex format")
    func categoryColorFormat() {
        for category in SpendingCategory.allCases {
            #expect(category.colorHex.hasPrefix("#"))
            #expect(category.colorHex.count == 7)
        }
    }

    // MARK: - Formatters Tests

    @Test("Currency full format")
    func currencyFull() {
        let result = Formatters.currency(12450.32, format: .full)
        #expect(result.contains("12,450.32") || result.contains("12450.32") || result.contains("12.450,32"))
    }

    @Test("Currency abbreviated format thousands")
    func currencyAbbreviated() {
        let result = Formatters.currency(12450.32, format: .abbreviated)
        #expect(result.contains("12.5K") || result.contains("12.4K"))
    }

    @Test("Currency abbreviated millions")
    func currencyMillions() {
        let result = Formatters.currency(2_500_000, format: .abbreviated)
        #expect(result.contains("2.5M"))
    }

    @Test("Currency abbreviated small amount")
    func currencySmall() {
        let result = Formatters.currency(42.50, format: .abbreviated)
        #expect(result.contains("$43") || result.contains("$42"))
    }

    @Test("Currency abbreviated negative")
    func currencyNegative() {
        let result = Formatters.currency(-5000, format: .abbreviated)
        #expect(result.contains("-"))
        #expect(result.contains("5.0K"))
    }

    @Test("Percent formatting")
    func percentFormat() {
        #expect(Formatters.percent(30.5) == "30.5%")
        #expect(Formatters.percent(100.0, decimals: 0) == "100%")
        #expect(Formatters.percent(0.0) == "0.0%")
    }

    @Test("Date parsing valid")
    func dateParsingValid() {
        let date = Formatters.parseTransactionDate("2026-01-15")
        #expect(date != nil)
    }

    @Test("Date parsing invalid")
    func dateParsingInvalid() {
        let invalid = Formatters.parseTransactionDate("not-a-date")
        #expect(invalid == nil)
    }

    @Test("Date parsing empty string")
    func dateParsingEmpty() {
        let empty = Formatters.parseTransactionDate("")
        #expect(empty == nil)
    }

    // MARK: - SyncResponse Tests

    @Test("SyncResponse Codable")
    func syncResponseCodable() throws {
        let response = SyncResponse(
            added: [TransactionDTO(id: "1", accountId: "a", amount: 50, date: "2026-01-15", name: "Test")],
            modified: [],
            removed: ["old_id"],
            hasMore: false,
            nextCursor: "cursor_abc"
        )
        let data = try JSONEncoder().encode(response)
        let decoded = try JSONDecoder().decode(SyncResponse.self, from: data)
        #expect(decoded.added.count == 1)
        #expect(decoded.added[0].id == "1")
        #expect(decoded.removed == ["old_id"])
        #expect(decoded.hasMore == false)
        #expect(decoded.nextCursor == "cursor_abc")
    }

    @Test("SyncResponse empty")
    func syncResponseEmpty() throws {
        let response = SyncResponse(added: [], modified: [], removed: [], hasMore: false)
        let data = try JSONEncoder().encode(response)
        let decoded = try JSONDecoder().decode(SyncResponse.self, from: data)
        #expect(decoded.added.isEmpty)
        #expect(decoded.modified.isEmpty)
        #expect(decoded.removed.isEmpty)
        #expect(decoded.hasMore == false)
        #expect(decoded.nextCursor == nil)
    }

    // MARK: - LinkResponse Tests

    @Test("LinkResponse Codable")
    func linkResponseCodable() throws {
        let response = LinkResponse(linkToken: "token_123", linkUrl: "https://example.com/link")
        let data = try JSONEncoder().encode(response)
        let decoded = try JSONDecoder().decode(LinkResponse.self, from: data)
        #expect(decoded.linkToken == "token_123")
        #expect(decoded.linkUrl == "https://example.com/link")
    }

    // MARK: - ServerStatus Tests

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
        #expect(decoded.lastSync == nil)
        #expect(decoded.credentialsConfigured)
        #expect(decoded.storagePath == LocalDataStore.displayPath)
        #expect(decoded.syncReady)
    }

    @Test("ServerStatus with lastSync")
    func serverStatusWithLastSync() throws {
        let now = Date()
        let status = ServerStatus(version: "0.1.0", environment: .production, itemCount: 1, lastSync: now)
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        let data = try encoder.encode(status)
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        let decoded = try decoder.decode(ServerStatus.self, from: data)
        #expect(decoded.environment == .production)
        #expect(decoded.lastSync != nil)
    }

    @Test("ServerStatus preflight fields")
    func serverStatusPreflightFields() throws {
        let status = ServerStatus(
            version: "0.1.0",
            environment: .sandbox,
            itemCount: 0,
            credentialsConfigured: false,
            storagePath: "/tmp/plaidbar.sqlite",
            syncReady: false
        )

        let data = try JSONEncoder().encode(status)
        let decoded = try JSONDecoder().decode(ServerStatus.self, from: data)

        #expect(decoded.credentialsConfigured == false)
        #expect(decoded.storagePath == "/tmp/plaidbar.sqlite")
        #expect(decoded.syncReady == false)
    }

    // MARK: - ItemStatus Tests

    @Test("ItemStatus Codable")
    func itemStatusCodable() throws {
        let status = ItemStatus(id: "item_1", institutionName: "Chase", status: .connected)
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        let data = try encoder.encode(status)
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        let decoded = try decoder.decode(ItemStatus.self, from: data)
        #expect(decoded.id == "item_1")
        #expect(decoded.institutionName == "Chase")
        #expect(decoded.status == .connected)
    }

    @Test("ItemConnectionStatus all values")
    func itemConnectionStatuses() throws {
        let statuses: [ItemConnectionStatus] = [.connected, .loginRequired, .error]
        for status in statuses {
            let data = try JSONEncoder().encode(status)
            let decoded = try JSONDecoder().decode(ItemConnectionStatus.self, from: data)
            #expect(decoded == status)
        }
    }

    // MARK: - PlaidEnvironment Tests

    @Test("PlaidEnvironment raw values")
    func plaidEnvironmentRawValues() {
        #expect(PlaidEnvironment.sandbox.rawValue == "sandbox")
        #expect(PlaidEnvironment.production.rawValue == "production")
    }

    // MARK: - Constants Tests

    @Test("Server URL uses correct port and host")
    func serverURL() {
        #expect(PlaidBarConstants.serverBaseURL(environment: [:]) == "http://127.0.0.1:8484")
        #expect(PlaidBarConstants.serverBaseURL(environment: [
            PlaidBarConstants.serverPortEnvironmentVariable: "9494",
        ]) == "http://127.0.0.1:9494")
        #expect(PlaidBarConstants.serverBaseURL(environment: [
            PlaidBarConstants.serverPortEnvironmentVariable: "not-a-port",
        ]) == "http://127.0.0.1:8484")
        #expect(PlaidBarConstants.defaultServerPort == 8484)
        #expect(PlaidBarConstants.defaultServerHost == "127.0.0.1")
    }

    @Test("Constants have reasonable values")
    func constantsReasonable() {
        #expect(PlaidBarConstants.backgroundRefreshInterval > 0)
        #expect(PlaidBarConstants.transactionSyncInterval > 0)
        #expect(PlaidBarConstants.creditUtilizationWarningThreshold > 0)
        #expect(PlaidBarConstants.maxRecentTransactions > 0)
        #expect(PlaidBarConstants.initialSyncDays > 0)
        #expect(!PlaidBarConstants.keychainServiceName.isEmpty)
        #expect(!PlaidBarConstants.appVersion.isEmpty)
        #expect(!PlaidBarConstants.appName.isEmpty)
    }

    @Test("Version bumped to 0.3.0")
    func versionBump() {
        #expect(PlaidBarConstants.appVersion == "0.3.0")
    }

    // MARK: - RecurringTransaction Model Tests

    @Test("RecurringTransaction identity by merchantName")
    func recurringIdentity() {
        let r = RecurringTransaction(
            merchantName: "Netflix",
            frequency: .monthly,
            averageAmount: 15.99,
            lastDate: "2026-03-15",
            nextExpectedDate: "2026-04-15",
            category: .entertainment,
            transactionCount: 3,
            confidence: 0.95
        )
        #expect(r.id == "Netflix-monthly")
    }

    @Test("RecurringFrequency display names")
    func recurringFrequencyDisplay() {
        for freq in RecurringFrequency.allCases {
            #expect(!freq.displayName.isEmpty)
            #expect(!freq.iconName.isEmpty)
            #expect(freq.estimatedDays > 0)
        }
    }

    @Test("RecurringFrequency estimated days")
    func recurringFrequencyDays() {
        #expect(RecurringFrequency.weekly.estimatedDays == 7)
        #expect(RecurringFrequency.biweekly.estimatedDays == 14)
        #expect(RecurringFrequency.monthly.estimatedDays == 30)
        #expect(RecurringFrequency.quarterly.estimatedDays == 90)
        #expect(RecurringFrequency.annual.estimatedDays == 365)
    }

    @Test("RecurringFrequency monthly multiplier normalization")
    func recurringFrequencyMultiplier() {
        #expect(RecurringFrequency.monthly.monthlyMultiplier == 1.0)
        #expect(abs(RecurringFrequency.weekly.monthlyMultiplier - 4.333) < 0.01)
        #expect(abs(RecurringFrequency.quarterly.monthlyMultiplier - 0.333) < 0.01)
        #expect(abs(RecurringFrequency.annual.monthlyMultiplier - 0.0833) < 0.01)
    }

    // MARK: - RecurringDetector Tests

    @Test("RecurringDetector detects monthly pattern")
    func detectMonthly() {
        let txns = [
            TransactionDTO(id: "1", accountId: "a", amount: 15.99, date: "2026-01-15", name: "NETFLIX", merchantName: "Netflix", category: .entertainment),
            TransactionDTO(id: "2", accountId: "a", amount: 15.99, date: "2026-02-15", name: "NETFLIX", merchantName: "Netflix", category: .entertainment),
            TransactionDTO(id: "3", accountId: "a", amount: 15.99, date: "2026-03-15", name: "NETFLIX", merchantName: "Netflix", category: .entertainment),
        ]

        let recurring = RecurringDetector.detect(from: txns)
        #expect(recurring.count == 1)
        #expect(recurring[0].merchantName == "Netflix")
        #expect(recurring[0].frequency == .monthly)
        #expect(abs(recurring[0].averageAmount - 15.99) < 0.01)
        #expect(recurring[0].confidence > 0.5)
    }

    @Test("RecurringDetector ignores single-occurrence merchants")
    func detectSingleOccurrence() {
        let txns = [
            TransactionDTO(id: "1", accountId: "a", amount: 50.00, date: "2026-01-15", name: "Random Store", merchantName: "Random Store"),
        ]

        let recurring = RecurringDetector.detect(from: txns)
        #expect(recurring.isEmpty)
    }

    @Test("RecurringDetector ignores income")
    func detectIgnoresIncome() {
        let txns = [
            TransactionDTO(id: "1", accountId: "a", amount: -3000, date: "2026-01-15", name: "Salary", merchantName: "Employer", category: .income),
            TransactionDTO(id: "2", accountId: "a", amount: -3000, date: "2026-02-15", name: "Salary", merchantName: "Employer", category: .income),
            TransactionDTO(id: "3", accountId: "a", amount: -3000, date: "2026-03-15", name: "Salary", merchantName: "Employer", category: .income),
        ]

        let recurring = RecurringDetector.detect(from: txns)
        #expect(recurring.isEmpty)
    }

    @Test("RecurringDetector empty input")
    func detectEmpty() {
        let recurring = RecurringDetector.detect(from: [])
        #expect(recurring.isEmpty)
    }

    @Test("RecurringDetector rejects irregular intervals")
    func detectIrregular() {
        let txns = [
            TransactionDTO(id: "1", accountId: "a", amount: 50, date: "2026-01-01", name: "Shop", merchantName: "Shop"),
            TransactionDTO(id: "2", accountId: "a", amount: 50, date: "2026-01-10", name: "Shop", merchantName: "Shop"),
            TransactionDTO(id: "3", accountId: "a", amount: 50, date: "2026-03-15", name: "Shop", merchantName: "Shop"),
        ]

        let recurring = RecurringDetector.detect(from: txns)
        #expect(recurring.isEmpty)
    }

    @Test("RecurringDetector ignores nil merchantName")
    func detectNilMerchant() {
        let txns = [
            TransactionDTO(id: "1", accountId: "a", amount: 10, date: "2026-01-15", name: "Payment"),
            TransactionDTO(id: "2", accountId: "a", amount: 10, date: "2026-02-15", name: "Payment"),
        ]

        let recurring = RecurringDetector.detect(from: txns)
        #expect(recurring.isEmpty)
    }

    @Test("RecurringDetector computes next expected date")
    func detectNextDate() {
        let txns = [
            TransactionDTO(id: "1", accountId: "a", amount: 75, date: "2026-01-15", name: "Gym", merchantName: "Planet Fitness"),
            TransactionDTO(id: "2", accountId: "a", amount: 75, date: "2026-02-15", name: "Gym", merchantName: "Planet Fitness"),
            TransactionDTO(id: "3", accountId: "a", amount: 75, date: "2026-03-15", name: "Gym", merchantName: "Planet Fitness"),
        ]

        let recurring = RecurringDetector.detect(from: txns)
        #expect(recurring.count == 1)
        #expect(recurring[0].nextExpectedDate == "2026-04-15")
    }

    @Test("RecurringDetector median calculation")
    func medianCalculation() {
        #expect(RecurringDetector.median([1, 2, 3]) == 2.0)
        #expect(RecurringDetector.median([1, 3]) == 2.0)
        #expect(RecurringDetector.median([5]) == 5.0)
        #expect(RecurringDetector.median([]) == 0.0)
        #expect(RecurringDetector.median([10, 20, 30, 40]) == 25.0)
    }

    @Test("RecurringDetector frequency classification")
    func frequencyClassification() {
        #expect(RecurringDetector.classifyFrequency(medianInterval: 7) == .weekly)
        #expect(RecurringDetector.classifyFrequency(medianInterval: 14) == .biweekly)
        #expect(RecurringDetector.classifyFrequency(medianInterval: 30) == .monthly)
        #expect(RecurringDetector.classifyFrequency(medianInterval: 90) == .quarterly)
        #expect(RecurringDetector.classifyFrequency(medianInterval: 365) == .annual)
        #expect(RecurringDetector.classifyFrequency(medianInterval: 3) == nil)
        #expect(RecurringDetector.classifyFrequency(medianInterval: 50) == nil)
    }

    @Test("RecurringDetector confidence calculation")
    func confidenceCalculation() {
        // Perfect consistency
        let perfect = RecurringDetector.computeConfidence(intervals: [30, 30, 30], medianInterval: 30)
        #expect(perfect == 1.0)

        // Some variance
        let moderate = RecurringDetector.computeConfidence(intervals: [28, 30, 32], medianInterval: 30)
        #expect(moderate > 0.9)
        #expect(moderate < 1.0)

        // High variance
        let high = RecurringDetector.computeConfidence(intervals: [10, 30, 50], medianInterval: 30)
        #expect(high < 0.6)
    }

    @Test("RecurringDetector multiple merchants")
    func detectMultipleMerchants() {
        let txns = [
            // Netflix monthly
            TransactionDTO(id: "n1", accountId: "a", amount: 15.99, date: "2026-01-15", name: "NETFLIX", merchantName: "Netflix"),
            TransactionDTO(id: "n2", accountId: "a", amount: 15.99, date: "2026-02-15", name: "NETFLIX", merchantName: "Netflix"),
            TransactionDTO(id: "n3", accountId: "a", amount: 15.99, date: "2026-03-15", name: "NETFLIX", merchantName: "Netflix"),
            // Spotify monthly
            TransactionDTO(id: "s1", accountId: "a", amount: 9.99, date: "2026-01-10", name: "SPOTIFY", merchantName: "Spotify"),
            TransactionDTO(id: "s2", accountId: "a", amount: 9.99, date: "2026-02-10", name: "SPOTIFY", merchantName: "Spotify"),
            TransactionDTO(id: "s3", accountId: "a", amount: 9.99, date: "2026-03-10", name: "SPOTIFY", merchantName: "Spotify"),
            // Random one-off
            TransactionDTO(id: "r1", accountId: "a", amount: 500, date: "2026-02-20", name: "Random", merchantName: "Random"),
        ]

        let recurring = RecurringDetector.detect(from: txns)
        #expect(recurring.count == 2)
        let merchants = Set(recurring.map(\.merchantName))
        #expect(merchants.contains("Netflix"))
        #expect(merchants.contains("Spotify"))
    }

    @Test("RecurringDetector sorted by amount descending")
    func detectSortedByAmount() {
        let txns = [
            TransactionDTO(id: "a1", accountId: "a", amount: 10, date: "2026-01-15", name: "A", merchantName: "Cheap"),
            TransactionDTO(id: "a2", accountId: "a", amount: 10, date: "2026-02-15", name: "A", merchantName: "Cheap"),
            TransactionDTO(id: "b1", accountId: "a", amount: 100, date: "2026-01-15", name: "B", merchantName: "Expensive"),
            TransactionDTO(id: "b2", accountId: "a", amount: 100, date: "2026-02-15", name: "B", merchantName: "Expensive"),
        ]

        let recurring = RecurringDetector.detect(from: txns)
        #expect(recurring.count == 2)
        #expect(recurring[0].merchantName == "Expensive")
        #expect(recurring[1].merchantName == "Cheap")
    }

    // MARK: - Local Data Store

    @Test("Local data store resolves hidden PlaidBar directory")
    func localDataStorePathResolution() {
        let home = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent(UUID().uuidString, isDirectory: true)

        let directory = LocalDataStore.storageDirectoryURL(homeDirectory: home)

        #expect(LocalDataStore.displayPath == "~/.plaidbar/")
        #expect(directory.lastPathComponent == ".plaidbar")
        #expect(directory.deletingLastPathComponent() == home)
    }

    @Test("Local data store resolves from account home by default")
    func localDataStoreDefaultPathUsesAccountHome() {
        let directory = LocalDataStore.storageDirectoryURL()

        #expect(directory.lastPathComponent == ".plaidbar")
        #expect(directory.deletingLastPathComponent() == LocalDataStore.accountHomeDirectoryURL())
    }

    @Test("Local data store supports data directory override")
    func localDataStorePathOverride() {
        let root = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        let directory = root.appendingPathComponent("plaidbar-smoke", isDirectory: true)

        let resolved = LocalDataStore.storageDirectoryURL(
            environment: [LocalDataStore.dataDirectoryEnvironmentVariable: directory.path]
        )

        #expect(resolved == directory)
    }

    @Test("Local data reset removes data files and keeps server auth token")
    func localDataResetRemovesDataFilesAndKeepsAuthToken() throws {
        let root = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        let directory = root.appendingPathComponent(".plaidbar", isDirectory: true)
        let database = directory.appendingPathComponent("plaidbar.sqlite")
        let authToken = directory.appendingPathComponent("auth-token")

        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        try "db".write(to: database, atomically: true, encoding: .utf8)
        try "token".write(to: authToken, atomically: true, encoding: .utf8)
        defer { try? FileManager.default.removeItem(at: root) }

        let result = try LocalDataStore.resetLocalData(at: directory)

        #expect(result.directoryPath == directory.path)
        #expect(result.removedEntries == ["plaidbar.sqlite"])

        var isDirectory: ObjCBool = false
        #expect(FileManager.default.fileExists(atPath: directory.path, isDirectory: &isDirectory))
        #expect(isDirectory.boolValue)
        #expect(try FileManager.default.contentsOfDirectory(atPath: directory.path) == ["auth-token"])
        #expect(try String(contentsOf: authToken, encoding: .utf8) == "token")
    }

    @Test("Transaction cache survives incremental sync from existing cursor")
    func transactionCacheMergesIncrementalSync() throws {
        let root = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        let directory = root.appendingPathComponent(".plaidbar", isDirectory: true)
        let context = TransactionCacheContext(environment: .sandbox, storagePath: "\(directory.path)/plaidbar.sqlite")
        defer { try? FileManager.default.removeItem(at: root) }

        let cached = [
            TransactionDTO(id: "old", accountId: "checking", amount: 12, date: "2026-01-01", name: "Coffee")
        ]
        try LocalDataStore.saveTransactions(cached, to: directory, context: context)

        let loaded = try LocalDataStore.loadTransactions(from: directory, context: context)
        let delta = SyncResponse(
            added: [
                TransactionDTO(id: "new", accountId: "checking", amount: 25, date: "2026-01-02", name: "Lunch")
            ],
            modified: [],
            removed: [],
            hasMore: false
        )
        let merged = TransactionSyncReducer.applying(delta, to: loaded)
        try LocalDataStore.saveTransactions(merged, to: directory, context: context)

        let reloaded = try LocalDataStore.loadTransactions(from: directory, context: context)
        #expect(reloaded.map(\.id) == ["old", "new"])
        #expect(try LocalDataStore.loadTransactions(
            from: directory,
            context: TransactionCacheContext(environment: .production, storagePath: context.storagePath)
        ).isEmpty)
        #expect(LocalDataStore.transactionCacheURL(in: directory).lastPathComponent == LocalDataStore.transactionCacheFilename)
        #expect(LocalDataStore.transactionCacheURL(in: directory, context: context).lastPathComponent != LocalDataStore.transactionCacheFilename)
    }

    @Test("Transaction cache persists account removal cleanup")
    func transactionCachePersistsAccountRemovalCleanup() throws {
        let root = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        let directory = root.appendingPathComponent(".plaidbar", isDirectory: true)
        let context = TransactionCacheContext(environment: .production, storagePath: "\(directory.path)/plaidbar.sqlite")
        defer { try? FileManager.default.removeItem(at: root) }

        let transactions = [
            TransactionDTO(id: "keep", accountId: "checking", amount: 10, date: "2026-01-01", name: "Coffee"),
            TransactionDTO(id: "drop", accountId: "closed", amount: 100, date: "2026-01-02", name: "Old card")
        ]
        try LocalDataStore.saveTransactions(transactions, to: directory, context: context)

        let cleaned = try LocalDataStore.loadTransactions(from: directory, context: context)
            .filter { $0.accountId != "closed" }
        try LocalDataStore.saveTransactions(cleaned, to: directory, context: context)

        let reloaded = try LocalDataStore.loadTransactions(from: directory, context: context)
        #expect(reloaded.map(\.id) == ["keep"])
    }
}
