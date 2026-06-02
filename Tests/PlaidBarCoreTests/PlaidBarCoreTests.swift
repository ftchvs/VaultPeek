import Foundation
import Testing
@testable import PlaidBarCore

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

    @Test("TransactionDTO preserves item ID when encoded")
    func transactionItemIdCodable() throws {
        let tx = TransactionDTO(
            id: "6",
            itemId: "item_1",
            accountId: "a",
            amount: 42,
            date: "2026-01-15",
            name: "Coffee"
        )

        let data = try JSONEncoder().encode(tx)
        let decoded = try JSONDecoder().decode(TransactionDTO.self, from: data)

        #expect(decoded.itemId == "item_1")
    }

    @Test("TransactionDTO decodes legacy cache without item ID")
    func transactionLegacyCacheDecodesWithoutItemId() throws {
        let data = Data("""
        {
          "id": "legacy",
          "accountId": "a",
          "amount": 42,
          "date": "2026-01-15",
          "name": "Coffee",
          "pending": false
        }
        """.utf8)

        let decoded = try JSONDecoder().decode(TransactionDTO.self, from: data)

        #expect(decoded.itemId == nil)
        #expect(decoded.id == "legacy")
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

    @Test("Account presentation derives account detail balances")
    func accountPresentationDetailBalances() {
        let checking = AccountDTO(id: "1", itemId: "i", name: "Checking", type: .depository, balances: BalanceDTO(available: 450, current: 500))
        let creditWithAvailable = AccountDTO(id: "2", itemId: "i", name: "Card", type: .credit, balances: BalanceDTO(available: 850, current: -150, limit: 1_000))
        let creditWithoutAvailable = AccountDTO(id: "3", itemId: "i", name: "Backup Card", type: .credit, balances: BalanceDTO(current: -200, limit: 1_000))
        let overLimitCredit = AccountDTO(id: "4", itemId: "i", name: "Over Limit", type: .credit, balances: BalanceDTO(current: -1_200, limit: 1_000))
        let loan = AccountDTO(id: "5", itemId: "i", name: "Loan", type: .loan, balances: BalanceDTO(current: -5_000))

        #expect(AccountPresentation.availableBalance(for: checking) == 450)
        #expect(AccountPresentation.availableBalance(for: creditWithAvailable) == 850)
        #expect(AccountPresentation.availableBalance(for: creditWithoutAvailable) == 800)
        #expect(AccountPresentation.availableBalance(for: overLimitCredit) == 0)
        #expect(AccountPresentation.availableBalance(for: loan) == 0)
    }

    @Test("Account presentation aggregates positive and debt balances")
    func accountPresentationBalanceTotals() {
        let accounts = [
            AccountDTO(id: "1", itemId: "i", name: "Checking", type: .depository, balances: BalanceDTO(current: 500)),
            AccountDTO(id: "2", itemId: "i", name: "Overdrawn", type: .depository, balances: BalanceDTO(current: -20)),
            AccountDTO(id: "3", itemId: "i", name: "Brokerage", type: .investment, balances: BalanceDTO(current: 1_200)),
            AccountDTO(id: "4", itemId: "i", name: "Card", type: .credit, balances: BalanceDTO(current: -125)),
            AccountDTO(id: "5", itemId: "i", name: "Loan", type: .loan, balances: BalanceDTO(current: -750)),
        ]

        #expect(AccountPresentation.positiveBalanceTotal(from: accounts, type: .depository) == 500)
        #expect(AccountPresentation.positiveBalanceTotal(from: accounts, type: .investment) == 1_200)
        #expect(AccountPresentation.debtBalanceTotal(from: accounts, type: .credit) == 125)
        #expect(AccountPresentation.debtBalanceTotal(from: accounts, type: .loan) == 750)
    }

    @Test("Account presentation derives account detail labels")
    func accountPresentationDetailLabels() {
        let account = AccountDTO(
            id: "1",
            itemId: "i",
            name: "Everyday",
            officialName: "Everyday Checking",
            type: .depository,
            subtype: "checking",
            mask: "1234",
            balances: BalanceDTO(current: 500)
        )
        let fallback = AccountDTO(id: "2", itemId: "i", name: "Card", type: .credit, balances: BalanceDTO(current: -100))

        #expect(AccountPresentation.displayName(for: account) == "Everyday Checking")
        #expect(AccountPresentation.subtitle(for: account) == "Depository • Checking •••• 1234")
        #expect(AccountPresentation.displayName(for: fallback) == "Card")
        #expect(AccountPresentation.subtitle(for: fallback) == "Credit • Credit")
    }

    @Test("Account presentation derives dashboard row labels")
    func accountPresentationDashboardRowLabels() {
        let checking = AccountDTO(
            id: "1",
            itemId: "i",
            name: "Everyday",
            type: .depository,
            mask: "1234",
            balances: BalanceDTO(current: 500),
            institutionName: "Chase"
        )
        let credit = AccountDTO(
            id: "2",
            itemId: "i",
            name: "Rewards",
            type: .credit,
            mask: "0005",
            balances: BalanceDTO(current: -450, limit: 1_000),
            institutionName: "Amex"
        )

        #expect(AccountPresentation.rowAmountText(for: checking, format: .compact) == "$500")
        #expect(AccountPresentation.dashboardRowSubtitle(
            for: checking,
            connectionLabel: "2m ago",
            pendingCount: 2
        ) == "Chase •••• 1234 • 2m ago • 2 pending")
        #expect(AccountPresentation.rowAccessibilityLabel(
            for: checking,
            connectionLabel: "2m ago",
            pendingCount: 1,
            isSelected: false
        ) == "Everyday, Chase, Depository, Ending in 1234, $500.00, 2m ago, 1 pending transaction, collapsed")
        #expect(AccountPresentation.rowAccessibilityLabel(
            for: credit,
            amountText: "$450.00",
            connectionLabel: "2m ago",
            isSelected: true
        ) == "Rewards, Amex, Credit, Ending in 0005, $450.00 owed, 45% utilization, Warning, selected")
    }

    @Test("Account presentation labels credit utilization status")
    func accountPresentationUtilizationStatusLabels() {
        #expect(AccountPresentation.utilizationStatusLabel(for: 12) == "Good")
        #expect(AccountPresentation.utilizationStatusLabel(for: 30) == "Warning")
        #expect(AccountPresentation.utilizationStatusLabel(for: 50) == "High")
        #expect(AccountPresentation.utilizationStatusLabel(for: 75) == "Very high")
        #expect(AccountPresentation.utilizationStatusLabel(for: 25, threshold: 20) == "Warning")
    }

    @Test("Account connection presentation covers demo, offline, and healthy sync")
    func accountConnectionPresentationCoreStates() {
        let demo = AccountConnectionPresentation.evaluate(
            isDemoMode: true,
            serverConnected: false,
            isSyncStale: true,
            statusSyncText: "Never synced",
            itemStatus: nil
        )

        #expect(demo.level == .demo)
        #expect(demo.rowLabel == "Demo")
        #expect(demo.detailLabel == "Demo data")
        #expect(demo.iconName == "play.circle.fill")
        #expect(!demo.showsRecoveryActions)

        let offline = AccountConnectionPresentation.evaluate(
            isDemoMode: false,
            serverConnected: false,
            isSyncStale: true,
            statusSyncText: "Never synced",
            itemStatus: nil
        )

        #expect(offline.level == .offline)
        #expect(offline.rowLabel == "Server offline")
        #expect(offline.signalLabel == "Offline")
        #expect(!offline.showsRecoveryActions)

        let healthy = AccountConnectionPresentation.evaluate(
            isDemoMode: false,
            serverConnected: true,
            isSyncStale: false,
            statusSyncText: "2m ago",
            itemStatus: .connected
        )

        #expect(healthy.level == .healthy)
        #expect(healthy.rowLabel == "2m ago")
        #expect(healthy.signalLabel == "Fresh")
        #expect(healthy.iconName == "checkmark.circle.fill")

        let unknownItem = AccountConnectionPresentation.evaluate(
            isDemoMode: false,
            serverConnected: true,
            isSyncStale: false,
            statusSyncText: "2m ago",
            itemStatus: nil
        )

        #expect(unknownItem.level == .unknown)
        #expect(unknownItem.rowLabel == "Item unknown")
        #expect(unknownItem.detailLabel == "Item status unavailable")
        #expect(unknownItem.signalLabel == "Unknown")
        #expect(unknownItem.iconName == "link.circle.fill")
        #expect(!unknownItem.showsRecoveryActions)
    }

    @Test("Account connection presentation keeps unknown item ahead of stale sync")
    func accountConnectionPresentationUnknownItemBeatsStaleSync() {
        let unknownItem = AccountConnectionPresentation.evaluate(
            isDemoMode: false,
            serverConnected: true,
            isSyncStale: true,
            statusSyncText: "2h ago",
            itemStatus: nil
        )

        #expect(unknownItem.level == .unknown)
        #expect(unknownItem.rowLabel == "Item unknown")
        #expect(unknownItem.detailLabel == "Item status unavailable")
        #expect(unknownItem.signalLabel == "Unknown")
        #expect(unknownItem.iconName == "link.circle.fill")
        #expect(!unknownItem.showsRecoveryActions)
    }

    @Test("Account connection presentation flags stale and reconnectable items")
    func accountConnectionPresentationRecoveryStates() {
        let stale = AccountConnectionPresentation.evaluate(
            isDemoMode: false,
            serverConnected: true,
            isSyncStale: true,
            statusSyncText: "2h ago",
            itemStatus: .connected
        )

        #expect(stale.level == .stale)
        #expect(stale.signalLabel == "Stale")
        #expect(stale.iconName == "clock.badge.exclamationmark.fill")
        #expect(stale.showsRecoveryActions)

        let loginRequired = AccountConnectionPresentation.evaluate(
            isDemoMode: false,
            serverConnected: true,
            isSyncStale: false,
            statusSyncText: "2m ago",
            itemStatus: .loginRequired
        )

        #expect(loginRequired.level == .loginRequired)
        #expect(loginRequired.rowLabel == "Reconnect")
        #expect(loginRequired.detailLabel == "Login required")
        #expect(loginRequired.signalLabel == "Login")
        #expect(loginRequired.showsRecoveryActions)

        let errored = AccountConnectionPresentation.evaluate(
            isDemoMode: false,
            serverConnected: true,
            isSyncStale: false,
            statusSyncText: "2m ago",
            itemStatus: .error
        )

        #expect(errored.level == .error)
        #expect(errored.rowLabel == "Item error")
        #expect(errored.signalLabel == "Error")
        #expect(errored.showsRecoveryActions)
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
        let cursorCommitURL = try #require(ServerEndpoint.transactionCursorCommitURL(baseURL: baseURL))
        let updateURL = try #require(ServerEndpoint.updateLinkTokenURL(baseURL: baseURL, itemId: itemId))
        let removeURL = try #require(ServerEndpoint.removeItemURL(baseURL: baseURL, itemId: itemId))

        #expect(syncURL.absoluteString == "http://127.0.0.1:8484/api/transactions/sync?item_id=item%20with%2Fslash%3Fand%26symbols")
        #expect(cursorCommitURL.absoluteString == "http://127.0.0.1:8484/api/transactions/sync/cursors")
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

    @Test("Net cashflow display flips Plaid signs for finance presentation")
    func netCashflowDisplayFlipsPlaidSigns() {
        #expect(SpendingHeatmap.displayCashflowAmount(-175) == 175)
        #expect(SpendingHeatmap.displayCashflowAmount(75) == -75)
        #expect(SpendingHeatmap.displayCashflowAmount(0) == 0)
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
            nextCursor: "cursor_abc",
            pendingCursors: ["item_1": "cursor_abc"]
        )
        let data = try JSONEncoder().encode(response)
        let decoded = try JSONDecoder().decode(SyncResponse.self, from: data)
        #expect(decoded.added.count == 1)
        #expect(decoded.added[0].id == "1")
        #expect(decoded.removed == ["old_id"])
        #expect(decoded.hasMore == false)
        #expect(decoded.nextCursor == "cursor_abc")
        #expect(decoded.pendingCursors == ["item_1": "cursor_abc"])
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
        #expect(decoded.pendingCursors.isEmpty)
    }

    @Test("SyncResponse decodes legacy responses without pending cursors")
    func syncResponseDecodesLegacyPayload() throws {
        let data = Data("""
        {"added":[],"modified":[],"removed":[],"hasMore":false,"nextCursor":"cursor_legacy"}
        """.utf8)

        let decoded = try JSONDecoder().decode(SyncResponse.self, from: data)

        #expect(decoded.nextCursor == "cursor_legacy")
        #expect(decoded.pendingCursors.isEmpty)
    }

    // MARK: - Transaction Filter Tests

    @Test("Transaction filter groups recent transactions by descending date")
    func transactionFilterGroupsRecentTransactions() {
        let transactions = [
            TransactionDTO(id: "old", accountId: "checking", amount: 20, date: "2026-01-01", name: "Old"),
            TransactionDTO(id: "new", accountId: "checking", amount: 30, date: "2026-01-03", name: "New"),
            TransactionDTO(id: "middle", accountId: "checking", amount: 40, date: "2026-01-02", name: "Middle"),
        ]

        let grouped = TransactionFilter.groupedRecent(from: transactions, maxCount: 2)

        #expect(grouped.map(\.0) == ["2026-01-03", "2026-01-02"])
        #expect(grouped.flatMap(\.1).map(\.id) == ["new", "middle"])
    }

    @Test("Transaction filter applies search category account and date")
    func transactionFilterAppliesCriteria() {
        let transactions = [
            TransactionDTO(id: "1", accountId: "checking", amount: 50, date: "2026-01-15", name: "Whole Foods", category: .foodAndDrink),
            TransactionDTO(id: "2", accountId: "credit", amount: 30, date: "2026-01-15", name: "Whole Foods", category: .foodAndDrink),
            TransactionDTO(id: "3", accountId: "checking", amount: 20, date: "2026-01-14", name: "Gas", category: .transportation),
            TransactionDTO(id: "4", accountId: "checking", amount: 12, date: "2026-01-01", name: "Coffee", category: .foodAndDrink),
        ]

        let filtered = TransactionFilter.filtered(
            transactions,
            criteria: TransactionFilterCriteria(
                searchText: "food",
                category: .foodAndDrink,
                accountId: "checking",
                startDate: "2026-01-10"
            )
        )

        #expect(filtered.map(\.id) == ["1"])
    }

    @Test("Transaction filter search matches category display name")
    func transactionFilterSearchMatchesCategoryDisplayName() {
        let transactions = [
            TransactionDTO(id: "1", accountId: "checking", amount: 50, date: "2026-01-15", name: "Cafe", category: .foodAndDrink),
            TransactionDTO(id: "2", accountId: "checking", amount: 30, date: "2026-01-15", name: "Gas", category: .transportation),
        ]

        let filtered = TransactionFilter.filtered(
            transactions,
            criteria: TransactionFilterCriteria(searchText: "transport")
        )

        #expect(filtered.map(\.id) == ["2"])
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
        #expect(decoded.syncedItemCount == 0)
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
        #expect(decoded.syncedItemCount == 1)
    }

    @Test("ServerStatus preflight fields")
    func serverStatusPreflightFields() throws {
        let status = ServerStatus(
            version: "0.1.0",
            environment: .sandbox,
            itemCount: 0,
            credentialsConfigured: false,
            storagePath: "/tmp/.plaidbar",
            syncReady: false,
            syncedItemCount: 0
        )

        let data = try JSONEncoder().encode(status)
        let decoded = try JSONDecoder().decode(ServerStatus.self, from: data)

        #expect(decoded.credentialsConfigured == false)
        #expect(decoded.storagePath == "/tmp/.plaidbar")
        #expect(decoded.syncReady == false)
        #expect(decoded.syncedItemCount == 0)
    }

    @Test("ServerStatus decodes legacy payload without synced item count")
    func serverStatusLegacyPayload() throws {
        let json = """
        {
          "version": "0.5.0",
          "environment": "sandbox",
          "itemCount": 2,
          "credentialsConfigured": true,
          "storagePath": "/tmp/.plaidbar",
          "syncReady": true
        }
        """.data(using: .utf8)!

        let decoded = try JSONDecoder().decode(ServerStatus.self, from: json)

        #expect(decoded.itemCount == 2)
        #expect(decoded.syncedItemCount == 0)
    }

    // MARK: - First-run Completion Tests

    @Test("First-run completion waits for Plaid Link")
    func firstRunCompletionWaitsForLink() {
        let state = FirstRunCompletionState.evaluate(
            isDemoMode: false,
            serverConnected: true,
            linkedItemCount: 0,
            accountCount: 0,
            transactionCount: 0,
            syncedItemCount: 0,
            errorMessage: nil
        )

        #expect(state.step == .openPlaidLink)
        #expect(!state.isReady)
        #expect(state.canRetry)
    }

    @Test("First-run completion requires accounts after item link")
    func firstRunCompletionRequiresAccounts() {
        let state = FirstRunCompletionState.evaluate(
            isDemoMode: false,
            serverConnected: true,
            linkedItemCount: 1,
            accountCount: 0,
            transactionCount: 0,
            syncedItemCount: 0,
            errorMessage: nil
        )

        #expect(state.step == .loadAccounts)
        #expect(!state.isReady)
    }

    @Test("First-run completion requires sync attempt after accounts load")
    func firstRunCompletionRequiresSyncAttempt() {
        let state = FirstRunCompletionState.evaluate(
            isDemoMode: false,
            serverConnected: true,
            linkedItemCount: 1,
            accountCount: 2,
            transactionCount: 0,
            syncedItemCount: 0,
            errorMessage: nil
        )

        #expect(state.step == .syncTransactions)
        #expect(!state.isReady)
        #expect(state.canRetry)
    }

    @Test("First-run completion reports partial item sync")
    func firstRunCompletionReportsPartialItemSync() {
        let state = FirstRunCompletionState.evaluate(
            isDemoMode: false,
            serverConnected: true,
            linkedItemCount: 2,
            accountCount: 4,
            transactionCount: 12,
            syncedItemCount: 1,
            errorMessage: nil
        )

        #expect(state.step == .syncTransactions)
        #expect(state.title == "First sync incomplete")
        #expect(state.detail == "1 of 2 linked items synced. Run one more check to finish setup.")
        #expect(!state.isReady)
        #expect(state.canRetry)
    }

    @Test("First-run completion distinguishes uncommitted sync state")
    func firstRunCompletionDistinguishesUncommittedSyncState() {
        let state = FirstRunCompletionState.evaluate(
            isDemoMode: false,
            serverConnected: true,
            linkedItemCount: 1,
            accountCount: 2,
            transactionCount: 8,
            syncedItemCount: 0,
            errorMessage: nil
        )

        #expect(state.step == .syncTransactions)
        #expect(state.title == "Accounts loaded")
        #expect(state.detail == "Transactions are present, but no linked item has completed its first sync. Check again to commit sync state.")
        #expect(state.canRetry)
    }

    @Test("First-run completion is ready after accounts and sync")
    func firstRunCompletionReadyAfterSync() {
        let state = FirstRunCompletionState.evaluate(
            isDemoMode: false,
            serverConnected: true,
            linkedItemCount: 1,
            accountCount: 2,
            transactionCount: 0,
            syncedItemCount: 1,
            errorMessage: nil
        )

        #expect(state.step == .ready)
        #expect(state.isReady)
        #expect(!state.canRetry)
    }

    // MARK: - Dashboard Status Readiness Tests

    @Test("Dashboard status readiness treats demo mode as local data")
    func dashboardStatusReadinessTreatsDemoModeAsLocalData() {
        let readiness = DashboardStatusReadiness.evaluate(
            isDemoMode: true,
            serverConnected: false,
            credentialsConfigured: nil,
            linkedItemCount: 0,
            accountCount: 0,
            syncedItemCount: 0,
            needsLoginItemCount: 0,
            erroredItemCount: 0,
            isSyncStale: true,
            lastSyncRelative: nil,
            errorMessage: "PlaidBar server is not running"
        )

        #expect(readiness.level == .healthy)
        #expect(readiness.title == "Demo data ready")
        #expect(readiness.detail.contains("Local demo accounts"))
        #expect(readiness.primaryAction == .addAccount)
    }

    @Test("Dashboard status readiness blocks on offline server")
    func dashboardStatusReadinessBlocksOnOfflineServer() {
        let readiness = DashboardStatusReadiness.evaluate(
            isDemoMode: false,
            serverConnected: false,
            credentialsConfigured: nil,
            linkedItemCount: 0,
            accountCount: 0,
            syncedItemCount: 0,
            needsLoginItemCount: 0,
            erroredItemCount: 0,
            isSyncStale: true,
            lastSyncRelative: nil,
            errorMessage: nil
        )

        #expect(readiness.level == .blocked)
        #expect(readiness.primaryAction == .checkServer)
        #expect(readiness.secondaryActions.contains(.openSettings))
    }

    @Test("Dashboard status readiness prompts add account with no items")
    func dashboardStatusReadinessPromptsAddAccount() {
        let readiness = DashboardStatusReadiness.evaluate(
            isDemoMode: false,
            serverConnected: true,
            credentialsConfigured: true,
            linkedItemCount: 0,
            accountCount: 0,
            syncedItemCount: 0,
            needsLoginItemCount: 0,
            erroredItemCount: 0,
            isSyncStale: true,
            lastSyncRelative: nil,
            errorMessage: nil
        )

        #expect(readiness.level == .warning)
        #expect(readiness.primaryAction == .addAccount)
    }

    @Test("Dashboard status readiness surfaces recent action failure before empty data")
    func dashboardStatusReadinessSurfacesRecentActionFailureBeforeEmptyData() {
        let readiness = DashboardStatusReadiness.evaluate(
            isDemoMode: false,
            serverConnected: true,
            credentialsConfigured: true,
            linkedItemCount: 0,
            accountCount: 0,
            syncedItemCount: 0,
            needsLoginItemCount: 0,
            erroredItemCount: 0,
            isSyncStale: true,
            lastSyncRelative: nil,
            errorMessage: "Server is running in production, not sandbox."
        )

        #expect(readiness.level == .warning)
        #expect(readiness.title == "Recent action failed")
        #expect(readiness.detail.contains("production"))
        #expect(readiness.primaryAction == .refresh)
        #expect(readiness.secondaryActions.contains(.openSettings))
    }

    @Test("Dashboard account filters include only matching account kinds")
    func dashboardAccountFiltersMatchAccountKinds() {
        let checking = AccountDTO(id: "checking", itemId: "item_cash", name: "Checking", type: .depository, subtype: "checking")
        let savings = AccountDTO(id: "savings", itemId: "item_cash", name: "Savings", type: .depository, subtype: "savings")
        let credit = AccountDTO(id: "credit", itemId: "item_card", name: "Card", type: .credit)
        let loan = AccountDTO(id: "loan", itemId: "item_loan", name: "Loan", type: .loan)

        #expect(DashboardAccountFilterKind.all.includes(checking))
        #expect(DashboardAccountFilterKind.cash.includes(checking))
        #expect(DashboardAccountFilterKind.cash.includes(savings))
        #expect(!DashboardAccountFilterKind.cash.includes(credit))
        #expect(DashboardAccountFilterKind.savings.includes(savings))
        #expect(!DashboardAccountFilterKind.savings.includes(checking))
        #expect(DashboardAccountFilterKind.credit.includes(credit))
        #expect(DashboardAccountFilterKind.debt.includes(credit))
        #expect(DashboardAccountFilterKind.debt.includes(loan))
        #expect(!DashboardAccountFilterKind.debt.includes(checking))
    }

    @Test("Dashboard status filter only shows degraded item accounts")
    func dashboardStatusFilterOnlyShowsDegradedItemAccounts() {
        let healthy = AccountDTO(id: "checking", itemId: "item_cash", name: "Checking", type: .depository)
        let degraded = AccountDTO(id: "card", itemId: "item_card", name: "Card", type: .credit)

        #expect(!DashboardAccountFilterKind.status.includes(healthy))
        #expect(!DashboardAccountFilterKind.status.includes(degraded))
        #expect(!DashboardAccountFilterKind.status.includes(healthy, degradedItemIds: ["item_card"]))
        #expect(DashboardAccountFilterKind.status.includes(degraded, degradedItemIds: ["item_card"]))
    }

    @Test("Dashboard account empty state points status filter at degraded item recovery")
    func dashboardAccountEmptyStateStatusFilterWithDegradedItems() {
        let emptyState = DashboardAccountEmptyState.evaluate(
            filter: .status,
            isDemoMode: false,
            serverConnected: true,
            linkedItemCount: 1,
            accountCount: 3,
            degradedItemCount: 1
        )

        #expect(emptyState.title == "1 item needs attention")
        #expect(emptyState.detail.contains("needs recovery"))
        #expect(emptyState.iconName == "exclamationmark.triangle.fill")
        #expect(emptyState.tone == .warning)
        #expect(!emptyState.showsAddAccount)
        #expect(emptyState.action == .refresh)
    }

    @Test("Dashboard account empty state keeps healthy status copy when no items are degraded")
    func dashboardAccountEmptyStateStatusFilterHealthy() {
        let emptyState = DashboardAccountEmptyState.evaluate(
            filter: .status,
            isDemoMode: false,
            serverConnected: true,
            linkedItemCount: 2,
            accountCount: 4,
            degradedItemCount: 0
        )

        #expect(emptyState.title == "No accounts need attention")
        #expect(emptyState.tone == .healthy)
        #expect(emptyState.iconName == "checkmark.circle.fill")
        #expect(emptyState.action == .refresh)
    }

    @Test("Dashboard account empty state keeps server offline recovery first")
    func dashboardAccountEmptyStateServerOfflineFirst() {
        let emptyState = DashboardAccountEmptyState.evaluate(
            filter: .status,
            isDemoMode: false,
            serverConnected: false,
            linkedItemCount: 1,
            accountCount: 0,
            degradedItemCount: 1
        )

        #expect(emptyState.title == "Server offline")
        #expect(emptyState.action == .checkServer)
        #expect(emptyState.actionTitle == "Check Server")
        #expect(emptyState.actionIconName == "server.rack")
    }

    @Test("Dashboard account empty state uses status check copy before a bank is linked")
    func dashboardAccountEmptyStateNoLinkedBankActionCopy() {
        let emptyState = DashboardAccountEmptyState.evaluate(
            filter: .all,
            isDemoMode: false,
            serverConnected: true,
            linkedItemCount: 0,
            accountCount: 0,
            degradedItemCount: 0
        )

        #expect(emptyState.title == "No bank linked")
        #expect(emptyState.showsAddAccount)
        #expect(emptyState.action == .refresh)
        #expect(emptyState.actionTitle == "Check Status")
        #expect(emptyState.actionIconName == "arrow.clockwise")
    }

    @Test("Dashboard account empty state uses sync copy when linked balances are missing")
    func dashboardAccountEmptyStateNoBalanceDataActionCopy() {
        let emptyState = DashboardAccountEmptyState.evaluate(
            filter: .all,
            isDemoMode: false,
            serverConnected: true,
            linkedItemCount: 1,
            accountCount: 0,
            degradedItemCount: 0
        )

        #expect(emptyState.title == "No account data")
        #expect(emptyState.action == .sync)
        #expect(emptyState.actionTitle == "Sync Balances")
        #expect(emptyState.actionIconName == "arrow.clockwise")
    }

    @Test("Dashboard account empty state uses refresh data copy for empty filters")
    func dashboardAccountEmptyStateFilteredEmptyActionCopy() {
        let emptyState = DashboardAccountEmptyState.evaluate(
            filter: .cash,
            isDemoMode: false,
            serverConnected: true,
            linkedItemCount: 1,
            accountCount: 2,
            degradedItemCount: 0
        )

        #expect(emptyState.title == "No cash accounts")
        #expect(emptyState.action == .refresh)
        #expect(emptyState.actionTitle == "Refresh Data")
        #expect(emptyState.actionIconName == "arrow.clockwise")
    }

    @Test("Dashboard status readiness ignores blank recent action failures")
    func dashboardStatusReadinessIgnoresBlankRecentActionFailures() {
        let readiness = DashboardStatusReadiness.evaluate(
            isDemoMode: false,
            serverConnected: true,
            credentialsConfigured: true,
            linkedItemCount: 0,
            accountCount: 0,
            syncedItemCount: 0,
            needsLoginItemCount: 0,
            erroredItemCount: 0,
            isSyncStale: true,
            lastSyncRelative: nil,
            errorMessage: " \n\t "
        )

        #expect(readiness.level == .warning)
        #expect(readiness.title == "No institution linked")
        #expect(readiness.primaryAction == .addAccount)
    }

    @Test("Dashboard status readiness normalizes and truncates recent action failures")
    func dashboardStatusReadinessNormalizesAndTruncatesRecentActionFailures() {
        let longMessage = "Server failed:\n" + String(repeating: "Plaid upstream payload ", count: 20)

        let readiness = DashboardStatusReadiness.evaluate(
            isDemoMode: false,
            serverConnected: true,
            credentialsConfigured: true,
            linkedItemCount: 1,
            accountCount: 1,
            syncedItemCount: 0,
            needsLoginItemCount: 0,
            erroredItemCount: 0,
            isSyncStale: true,
            lastSyncRelative: nil,
            errorMessage: longMessage
        )

        #expect(readiness.title == "Recent action failed")
        #expect(!readiness.detail.contains("\n"))
        #expect(readiness.detail.count == 243)
        #expect(readiness.detail.hasSuffix("..."))
        #expect(readiness.primaryAction == .refresh)
    }

    @Test("Dashboard status readiness blocks on missing credentials")
    func dashboardStatusReadinessBlocksOnMissingCredentials() {
        let readiness = DashboardStatusReadiness.evaluate(
            isDemoMode: false,
            serverConnected: true,
            credentialsConfigured: false,
            linkedItemCount: 0,
            accountCount: 0,
            syncedItemCount: 0,
            needsLoginItemCount: 0,
            erroredItemCount: 0,
            isSyncStale: true,
            lastSyncRelative: nil,
            errorMessage: nil
        )

        #expect(readiness.level == .blocked)
        #expect(readiness.primaryAction == .openSettings)
        #expect(readiness.title == "Plaid credentials missing")
    }

    @Test("Dashboard status readiness prioritizes item errors")
    func dashboardStatusReadinessPrioritizesItemErrors() {
        let readiness = DashboardStatusReadiness.evaluate(
            isDemoMode: false,
            serverConnected: true,
            credentialsConfigured: true,
            linkedItemCount: 2,
            accountCount: 4,
            syncedItemCount: 2,
            needsLoginItemCount: 1,
            erroredItemCount: 1,
            isSyncStale: false,
            lastSyncRelative: "2m ago",
            errorMessage: nil
        )

        #expect(readiness.level == .blocked)
        #expect(readiness.primaryAction == .reconnect)
        #expect(readiness.title.contains("need attention"))
        #expect(readiness.secondaryActions.contains(.openSettings))
    }

    @Test("Dashboard status readiness prioritizes item recovery")
    func dashboardStatusReadinessPrioritizesItemRecovery() {
        let readiness = DashboardStatusReadiness.evaluate(
            isDemoMode: false,
            serverConnected: true,
            credentialsConfigured: true,
            linkedItemCount: 2,
            accountCount: 4,
            syncedItemCount: 2,
            needsLoginItemCount: 1,
            erroredItemCount: 0,
            isSyncStale: false,
            lastSyncRelative: "2m ago",
            errorMessage: nil
        )

        #expect(readiness.level == .warning)
        #expect(readiness.primaryAction == .reconnect)
        #expect(readiness.title.contains("need login"))
    }

    @Test("Dashboard status readiness keeps item recovery ahead of recent action failure")
    func dashboardStatusReadinessKeepsItemRecoveryAheadOfRecentActionFailure() {
        let readiness = DashboardStatusReadiness.evaluate(
            isDemoMode: false,
            serverConnected: true,
            credentialsConfigured: true,
            linkedItemCount: 2,
            accountCount: 4,
            syncedItemCount: 2,
            needsLoginItemCount: 1,
            erroredItemCount: 0,
            isSyncStale: false,
            lastSyncRelative: "2m ago",
            errorMessage: "Refresh failed"
        )

        #expect(readiness.level == .warning)
        #expect(readiness.primaryAction == .reconnect)
        #expect(readiness.title.contains("need login"))
    }

    @Test("Dashboard status readiness detects incomplete first sync")
    func dashboardStatusReadinessDetectsIncompleteFirstSync() {
        let readiness = DashboardStatusReadiness.evaluate(
            isDemoMode: false,
            serverConnected: true,
            credentialsConfigured: true,
            linkedItemCount: 2,
            accountCount: 4,
            syncedItemCount: 1,
            needsLoginItemCount: 0,
            erroredItemCount: 0,
            isSyncStale: false,
            lastSyncRelative: "just now",
            errorMessage: nil
        )

        #expect(readiness.level == .warning)
        #expect(readiness.primaryAction == .refresh)
        #expect(readiness.title == "First sync incomplete")
    }

    @Test("Dashboard status readiness detects stale sync")
    func dashboardStatusReadinessDetectsStaleSync() {
        let readiness = DashboardStatusReadiness.evaluate(
            isDemoMode: false,
            serverConnected: true,
            credentialsConfigured: true,
            linkedItemCount: 2,
            accountCount: 4,
            syncedItemCount: 2,
            needsLoginItemCount: 0,
            erroredItemCount: 0,
            isSyncStale: true,
            lastSyncRelative: "2h ago",
            errorMessage: nil
        )

        #expect(readiness.level == .warning)
        #expect(readiness.primaryAction == .refresh)
        #expect(readiness.title == "Sync is stale")
    }

    @Test("Dashboard status readiness reports healthy sync")
    func dashboardStatusReadinessReportsHealthySync() {
        let readiness = DashboardStatusReadiness.evaluate(
            isDemoMode: false,
            serverConnected: true,
            credentialsConfigured: true,
            linkedItemCount: 2,
            accountCount: 4,
            syncedItemCount: 2,
            needsLoginItemCount: 0,
            erroredItemCount: 0,
            isSyncStale: false,
            lastSyncRelative: "2m ago",
            errorMessage: nil
        )

        #expect(readiness.level == .healthy)
        #expect(readiness.primaryAction == .refresh)
        #expect(readiness.secondaryActions.contains(.addAccount))
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
        #expect(PlaidBarConstants.minimumBackgroundRefreshInterval > 0)
        #expect(PlaidBarConstants.transactionSyncInterval > 0)
        #expect(PlaidBarConstants.creditUtilizationWarningThreshold > 0)
        #expect(PlaidBarConstants.maxRecentTransactions > 0)
        #expect(PlaidBarConstants.initialSyncDays > 0)
        #expect(!PlaidBarConstants.keychainServiceName.isEmpty)
        #expect(!PlaidBarConstants.appVersion.isEmpty)
        #expect(!PlaidBarConstants.appName.isEmpty)
    }

    @Test("Background refresh interval rejects invalid persisted values")
    func backgroundRefreshIntervalNormalization() {
        #expect(PlaidBarConstants.normalizedBackgroundRefreshInterval(5 * 60) == 5 * 60)
        #expect(PlaidBarConstants.normalizedBackgroundRefreshInterval(60 * 60) == 60 * 60)
        #expect(PlaidBarConstants.normalizedBackgroundRefreshInterval(0) == PlaidBarConstants.backgroundRefreshInterval)
        #expect(PlaidBarConstants.normalizedBackgroundRefreshInterval(-1) == PlaidBarConstants.backgroundRefreshInterval)
        #expect(PlaidBarConstants.normalizedBackgroundRefreshInterval(.infinity) == PlaidBarConstants.backgroundRefreshInterval)
        #expect(PlaidBarConstants.normalizedBackgroundRefreshInterval(.nan) == PlaidBarConstants.backgroundRefreshInterval)
    }

    @Test("Transaction sync page cap is generous and finite")
    func transactionSyncPageCapIsGenerousAndFinite() {
        #expect(PlaidBarConstants.maxTransactionSyncPages >= 50)
        #expect(PlaidBarConstants.maxTransactionSyncPages < Int.max)
    }

    @Test("Version bumped to 1.0.0")
    func versionBump() {
        #expect(PlaidBarConstants.appVersion == "1.0.0")
    }

    // MARK: - CommandLineOptions Tests

    @Test("Command line options return explicit values")
    func commandLineOptionsReturnExplicitValues() {
        let arguments = ["PlaidBar", "--demo", "--screenshot-account", "acc_123"]

        #expect(CommandLineOptions.value(for: "--screenshot-account", in: arguments) == "acc_123")
    }

    @Test("Command line options reject missing values and following flags")
    func commandLineOptionsRejectMissingValuesAndFollowingFlags() {
        let arguments = ["PlaidBar", "--demo", "--screenshot-account", "--settings-tab", "status"]

        #expect(CommandLineOptions.value(for: "--screenshot-account", in: arguments) == nil)
        #expect(CommandLineOptions.value(for: "--settings-tab", in: ["PlaidBar", "--settings-tab"]) == nil)
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

    @Test("Local data store resolves active directory from server database path")
    func localDataStoreResolvesActiveDirectoryFromServerDatabasePath() {
        let root = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        let database = root
            .appendingPathComponent("custom-plaidbar", isDirectory: true)
            .appendingPathComponent("plaidbar-production.sqlite")

        let directory = LocalDataStore.storageDirectoryURL(
            forServerStoragePath: database.path
        )

        #expect(directory == database.deletingLastPathComponent())
    }

    @Test("Local data store resolves active directory from server storage directory")
    func localDataStoreResolvesActiveDirectoryFromServerStorageDirectory() {
        let directory = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
            .appendingPathComponent(".plaidbar", isDirectory: true)

        let resolved = LocalDataStore.storageDirectoryURL(
            forServerStoragePath: directory.path
        )

        #expect(resolved == directory)
    }

    @Test("Local data store falls back for demo display path")
    func localDataStoreFallsBackForDemoDisplayPath() {
        let fallback = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent(UUID().uuidString, isDirectory: true)

        let directory = LocalDataStore.storageDirectoryURL(
            forServerStoragePath: LocalDataStore.displayPath,
            fallback: fallback
        )

        #expect(directory == fallback)
    }

    @Test("Local data store display path abbreviates home")
    func localDataStoreDisplayPathAbbreviatesHome() {
        let home = URL(fileURLWithPath: "/Users/example", isDirectory: true)
        let directory = home.appendingPathComponent(".plaidbar", isDirectory: true)

        #expect(LocalDataStore.displayPath(for: directory, homeDirectory: home) == "~/.plaidbar")
        #expect(LocalDataStore.displayPath(for: home, homeDirectory: home) == "~")
        #expect(LocalDataStore.displayPath(for: URL(fileURLWithPath: "/var/tmp/plaidbar"), homeDirectory: home) == "/var/tmp/plaidbar")
    }

    @Test("Local data reset removes data files and keeps local server configuration")
    func localDataResetRemovesDataFilesAndKeepsLocalServerConfiguration() throws {
        let root = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        let directory = root.appendingPathComponent(".plaidbar", isDirectory: true)
        let database = directory.appendingPathComponent("plaidbar.sqlite")
        let authToken = directory.appendingPathComponent("auth-token")
        let serverConfig = directory.appendingPathComponent("server.conf")

        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        try "db".write(to: database, atomically: true, encoding: .utf8)
        try "token".write(to: authToken, atomically: true, encoding: .utf8)
        try "PLAID_ENV=sandbox".write(to: serverConfig, atomically: true, encoding: .utf8)
        try FileManager.default.setAttributes([.posixPermissions: 0o644], ofItemAtPath: authToken.path)
        try FileManager.default.setAttributes([.posixPermissions: 0o644], ofItemAtPath: serverConfig.path)
        defer { try? FileManager.default.removeItem(at: root) }

        var didResetKeychainTokens = false
        let result = try LocalDataStore.resetLocalData(at: directory) {
            didResetKeychainTokens = true
        }

        #expect(result.directoryPath == directory.path)
        #expect(result.removedEntries == ["plaidbar.sqlite"])
        #expect(result.keychainTokensCleared)
        #expect(didResetKeychainTokens)

        var isDirectory: ObjCBool = false
        #expect(FileManager.default.fileExists(atPath: directory.path, isDirectory: &isDirectory))
        #expect(isDirectory.boolValue)
        #expect(try FileManager.default.contentsOfDirectory(atPath: directory.path).sorted() == ["auth-token", "server.conf"])
        #expect(try String(contentsOf: authToken, encoding: .utf8) == "token")
        #expect(try String(contentsOf: serverConfig, encoding: .utf8) == "PLAID_ENV=sandbox")
        #expect(try posixPermissions(at: authToken) == 0o600)
        #expect(try posixPermissions(at: serverConfig) == 0o600)
    }

    @Test("Local data reset keeps data directory private")
    func localDataResetKeepsDirectoryPrivate() throws {
        let root = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        let directory = root.appendingPathComponent(".plaidbar", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: root) }

        try FileManager.default.createDirectory(
            at: directory,
            withIntermediateDirectories: true,
            attributes: [.posixPermissions: 0o777]
        )

        var didResetKeychainTokens = false
        try LocalDataStore.resetLocalData(at: directory) {
            didResetKeychainTokens = true
        }

        #expect(try posixPermissions(at: directory) == 0o700)
        #expect(didResetKeychainTokens)
    }

    @Test("Local data reset can skip Keychain token cleanup")
    func localDataResetCanSkipKeychainTokenCleanup() throws {
        let root = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        let directory = root.appendingPathComponent(".plaidbar", isDirectory: true)
        let database = directory.appendingPathComponent("plaidbar.sqlite")

        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        try "db".write(to: database, atomically: true, encoding: .utf8)
        defer { try? FileManager.default.removeItem(at: root) }

        var didResetKeychainTokens = false
        let result = try LocalDataStore.resetLocalData(
            at: directory,
            resetKeychainTokens: false
        ) {
            didResetKeychainTokens = true
        }

        #expect(result.removedEntries == ["plaidbar.sqlite"])
        #expect(!result.keychainTokensCleared)
        #expect(!didResetKeychainTokens)
    }

    @Test("Preparing storage directory keeps it private")
    func prepareStorageDirectoryKeepsDirectoryPrivate() throws {
        let root = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        let directory = root.appendingPathComponent(".plaidbar", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: root) }

        try LocalDataStore.prepareStorageDirectory(at: directory)

        #expect(try posixPermissions(at: directory) == 0o700)
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

    @Test("Transaction cache saves with private file permissions")
    func transactionCacheSavesWithPrivatePermissions() throws {
        let root = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        let directory = root.appendingPathComponent(".plaidbar", isDirectory: true)
        let context = TransactionCacheContext(environment: .sandbox, storagePath: "\(directory.path)/plaidbar.sqlite")
        defer { try? FileManager.default.removeItem(at: root) }

        try LocalDataStore.saveTransactions(
            [TransactionDTO(id: "txn", accountId: "checking", amount: 12, date: "2026-01-01", name: "Coffee")],
            to: directory,
            context: context
        )

        #expect(try posixPermissions(at: directory) == 0o700)
        #expect(try posixPermissions(at: LocalDataStore.transactionCacheURL(in: directory, context: context)) == 0o600)
    }

    @Test("Transaction cache overwrite repairs existing file permissions")
    func transactionCacheOverwriteRepairsExistingPermissions() throws {
        let root = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        let directory = root.appendingPathComponent(".plaidbar", isDirectory: true)
        let context = TransactionCacheContext(environment: .sandbox, storagePath: "\(directory.path)/plaidbar.sqlite")
        let cacheURL = LocalDataStore.transactionCacheURL(in: directory, context: context)
        defer { try? FileManager.default.removeItem(at: root) }

        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        try Data("old-cache".utf8).write(to: cacheURL)
        try FileManager.default.setAttributes([.posixPermissions: 0o644], ofItemAtPath: cacheURL.path)

        try LocalDataStore.saveTransactions(
            [TransactionDTO(id: "txn", accountId: "checking", amount: 12, date: "2026-01-01", name: "Coffee")],
            to: directory,
            context: context
        )

        #expect(try LocalDataStore.loadTransactions(from: directory, context: context).map(\.id) == ["txn"])
        #expect(try posixPermissions(at: directory) == 0o700)
        #expect(try posixPermissions(at: cacheURL) == 0o600)
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

    @Test("Spending summary groups expenses and excludes income and transfers")
    func spendingSummaryGroupsExpenses() {
        let transactions = [
            TransactionDTO(id: "1", accountId: "a", amount: 67, date: "2026-01-15", name: "Whole Foods", category: .foodAndDrink),
            TransactionDTO(id: "2", accountId: "a", amount: 23, date: "2026-01-15", name: "Uber", category: .transportation),
            TransactionDTO(id: "3", accountId: "a", amount: 45, date: "2026-01-14", name: "Restaurant", category: .foodAndDrink),
            TransactionDTO(id: "4", accountId: "a", amount: -1200, date: "2026-01-14", name: "Stripe", category: .income),
            TransactionDTO(id: "5", accountId: "a", amount: 500, date: "2026-01-14", name: "Transfer", category: .transfer),
        ]

        let spending = SpendingSummary.spendingByCategory(from: transactions)

        #expect(spending.first { $0.0 == .foodAndDrink }?.1 == 112)
        #expect(spending.first { $0.0 == .transportation }?.1 == 23)
        #expect(spending.allSatisfy { $0.0 != .income && $0.0 != .transfer })
    }

    @Test("Spending summary calculates period delta")
    func spendingSummaryPeriodDelta() {
        let transactions = [
            TransactionDTO(id: "1", accountId: "a", amount: 100, date: "2026-03-15", name: "A", category: .foodAndDrink),
            TransactionDTO(id: "2", accountId: "a", amount: 200, date: "2026-03-10", name: "B", category: .shopping),
            TransactionDTO(id: "3", accountId: "a", amount: 150, date: "2026-02-15", name: "C", category: .foodAndDrink),
            TransactionDTO(id: "4", accountId: "a", amount: 100, date: "2026-02-10", name: "D", category: .shopping),
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

    @Test("Recurring summary normalizes estimated monthly total")
    func recurringSummaryMonthlyTotal() {
        let recurring = [
            RecurringTransaction(merchantName: "Netflix", frequency: .monthly, averageAmount: 15.99, lastDate: "2026-03-15", nextExpectedDate: "2026-04-15", category: .entertainment, transactionCount: 3, confidence: 0.95),
            RecurringTransaction(merchantName: "Gym", frequency: .monthly, averageAmount: 75.00, lastDate: "2026-03-15", nextExpectedDate: "2026-04-15", category: .healthAndFitness, transactionCount: 3, confidence: 0.90),
            RecurringTransaction(merchantName: "Weekly Sub", frequency: .weekly, averageAmount: 5.00, lastDate: "2026-03-15", nextExpectedDate: "2026-03-22", category: .entertainment, transactionCount: 5, confidence: 0.85),
        ]

        let estimated = RecurringSummary.estimatedMonthlyTotal(from: recurring)

        #expect(abs(estimated - 112.66) < 0.01)
    }

    private func posixPermissions(at url: URL) throws -> Int {
        let attributes = try FileManager.default.attributesOfItem(atPath: url.path)
        return (attributes[.posixPermissions] as? NSNumber)?.intValue ?? -1
    }
}
