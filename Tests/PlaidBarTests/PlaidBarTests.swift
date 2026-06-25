import Foundation
import Synchronization
import Testing
@testable import PlaidBarCore

/// Anchor for `Bundle(for:)` so the render-harness E2E test can locate the test
/// bundle (and, beside it, the prebuilt `PlaidBar` binary).
private final class BundleAnchor {}

/// Tests for app-level logic: view model calculations, client-side data
/// processing, and business rules used by the PlaidBar macOS app.
///
/// Note: PlaidBar is an executable target with @main (SwiftUI app), so we
/// cannot @testable import it directly. These tests exercise the shared
/// PlaidBarCore types that the app depends on, verifying the calculations
/// and data transformations the app performs.
@Suite("PlaidBar App Tests")
struct PlaidBarTests {

    // MARK: - Window-first render harness (AND-624)

    /// End-to-end smoke test for `--demo --render-window-first <dir>`: runs the
    /// already-built demo binary with the flag, then asserts it wrote exactly one
    /// PNG per in-shell destination plus the whole-shell reference (10 total).
    ///
    /// Opt-in: gated on `VAULTPEEK_RENDER_HARNESS_E2E=1` because it launches the
    /// GUI executable, which needs a window server / GUI session and is far
    /// heavier than the rest of the suite. CI without that env var skips it; the
    /// harness's destination coverage and flag detection are still pinned by fast
    /// unit tests in `PlaidBarCoreTests`. Run locally with:
    ///
    ///     swift build        # build the PlaidBar binary first
    ///     VAULTPEEK_RENDER_HARNESS_E2E=1 swift test \
    ///         --filter renderWindowFirstHarnessWritesOnePNGPerDestination
    ///
    /// It invokes the **prebuilt** `.build/<arch>/<config>/PlaidBar` binary
    /// directly rather than `swift run`: nesting `swift run` inside `swift test`
    /// deadlocks on the shared SwiftPM `.build` lock the test process already
    /// holds. The binary sits next to this test bundle's executable (same
    /// `debug`/`release` directory), so it is located relative to that.
    @Test("--render-window-first writes one PNG per destination plus the shell")
    func renderWindowFirstHarnessWritesOnePNGPerDestination() throws {
        let env = ProcessInfo.processInfo.environment
        // Opt-in only: a no-op unless explicitly enabled, so CI (which lacks a
        // GUI session / window server) stays green without recording an issue.
        // Swift Testing has no XCTSkip equivalent, so an early return is the
        // idiom for a conditionally-disabled test.
        guard env["VAULTPEEK_RENDER_HARNESS_E2E"] == "1" else { return }

        let fm = FileManager.default

        // The PlaidBar executable lives in the same build-config directory as the
        // running test bundle (…/.build/<arch>/<config>/PlaidBar). Walk up from
        // this bundle's executable to find it.
        let bundleExecDir = Bundle(for: BundleAnchor.self).bundleURL
            .deletingLastPathComponent()
        let binary = bundleExecDir.appendingPathComponent("PlaidBar")
        try #require(
            fm.isExecutableFile(atPath: binary.path),
            "PlaidBar binary not found at \(binary.path) — run `swift build` first."
        )

        let outDir = fm.temporaryDirectory
            .appendingPathComponent("vaultpeek-render-harness-\(UUID().uuidString)", isDirectory: true)
        defer { try? fm.removeItem(at: outDir) }

        let process = Process()
        process.executableURL = binary
        process.arguments = ["--demo", "--render-window-first", outDir.path]
        try process.run()
        process.waitUntilExit()

        #expect(process.terminationStatus == 0, "render harness exited \(process.terminationStatus)")

        let pngs = (try? fm.contentsOfDirectory(atPath: outDir.path))?
            .filter { $0.hasSuffix(".png") }
            .sorted() ?? []

        // 9 in-shell destinations (Settings excluded) + window-shell.png == 10.
        let expectedDestinations = RouteDestination.allCases
            .filter { $0 != .settings }
            .map { "window-\($0.rawValue).png" }
        var expected = Set(expectedDestinations)
        expected.insert("window-shell.png")

        #expect(pngs.count == expected.count, "got PNGs: \(pngs)")
        #expect(Set(pngs) == expected, "got PNGs: \(pngs)")
    }

    @Test("Window-first Goals and Planning mask amount-derived progress while Privacy Mask is active")
    func windowFirstGoalsProgressUsesPrivacyMask() throws {
        let root = URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
        let goalsSource = try String(
            contentsOf: root.appending(path: "Sources/PlaidBar/Views/Destinations/GoalsDestinationView.swift"),
            encoding: .utf8
        )
        let planningSource = try String(
            contentsOf: root.appending(path: "Sources/PlaidBar/Views/Destinations/PlanningDestinationView.swift"),
            encoding: .utf8
        )

        #expect(!goalsSource.contains(#"\(summary.overallPercent)%"#))
        #expect(!goalsSource.contains(#"\(goal.percentComplete)%"#))
        #expect(goalsSource.contains("percent(summary.overallPercent)"))
        #expect(goalsSource.contains("percent(goal.percentComplete)"))
        #expect(goalsSource.contains("GoalProgressBar(goal: goal, isMasked: isMasked)"))
        #expect(goalsSource.contains("GoalsOverallProgressBar("))
        #expect(goalsSource.contains("isMasked: isMasked"))

        #expect(!planningSource.contains(#"\(summary.overallPercent)% of total"#))
        #expect(planningSource.contains("goalsPercent(summary.overallPercent)"))
        #expect(planningSource.contains("if isMasked"))
        #expect(planningSource.contains("ProgressView(value: summary.overallFraction)"))
    }

    @Test("Control and Focus privacy mask paths redact snapshots and clear Spotlight")
    func privacyMaskControlPathsRedactEveryPublishedSystemSurface() throws {
        let root = URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
        let widgetSource = try String(
            contentsOf: root.appending(path: "Sources/PlaidBarWidgetExtension/PlaidBarWidgetBundle.swift"),
            encoding: .utf8
        )
        let focusSource = try String(
            contentsOf: root.appending(path: "Sources/PlaidBar/Intents/FocusPrivacyFilterIntent.swift"),
            encoding: .utf8
        )
        let appStateSource = try String(
            contentsOf: root.appending(path: "Sources/PlaidBar/App/AppState.swift"),
            encoding: .utf8
        )

        let glanceMakeRange = try #require(appStateSource.range(of: "let snapshot = GlanceSnapshot.make"))
        let glanceMakeBlock = String(appStateSource[glanceMakeRange.lowerBound...].prefix(500))

        #expect(widgetSource.contains("GlanceSnapshotStore.redactIfAvailable()"))
        #expect(widgetSource.contains("deleteSearchableItems("))
        #expect(widgetSource.contains("withDomainIdentifiers: [PlaidBarConstants.accountSpotlightDomainIdentifier]"))
        #expect(focusSource.contains("PrivacyMaskControlCommandReader.redactPublishedSnapshots()"))
        #expect(focusSource.contains("MainActor.run"))
        #expect(focusSource.contains("AccountSpotlightIndexer.clear()"))
        #expect(appStateSource.contains("PrivacyMaskControlCommandReader.peek()?.maskEnabled"))
        #expect(glanceMakeBlock.contains("isMasked: systemSurfaceMaskEnabled"))
        #expect(!glanceMakeBlock.contains("isMasked: shouldMaskFinancialValues"))
        #expect(appStateSource.contains("queued OFF command must restore the"))
        #expect(appStateSource.contains("clearPublishedSystemSnapshotsForDemoEntry()"))
    }

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

    // MARK: - Rule Replacement (mirrors AppState.createRule)

    @Test("Creating a rule for an existing merchant replaces it instead of stacking")
    func createRuleReplacesSameMerchant() {
        // Mirrors AppState.createRule: before appending the new rule it drops any
        // existing rule whose `matchMerchantContains` case-insensitively equals the
        // new matcher, so re-categorizing the same merchant keeps a single rule
        // (the user's newest choice) rather than leaving a dead earlier rule behind.
        var transactionRules = [
            TransactionRule(matchMerchantContains: "Acme", category: .shopping),
        ]

        let matcher = "acme" // different case — must still match and replace
        transactionRules.removeAll {
            $0.matchMerchantContains?.compare(matcher, options: .caseInsensitive) == .orderedSame
        }
        transactionRules.append(TransactionRule(matchMerchantContains: matcher, category: .foodAndDrink))

        #expect(transactionRules.count == 1)
        #expect(transactionRules[0].category == .foodAndDrink)

        // And the resolver attributes spend to the surviving (newest) category.
        let transaction = TransactionDTO(
            id: "recat", accountId: "a", amount: 12, date: "2026-06-01",
            name: "ACME CORP", merchantName: "Acme Corp", category: nil
        )
        let resolution = EffectiveCategoryResolver.resolve(
            transaction: transaction,
            rules: transactionRules
        )
        #expect(resolution.category == .foodAndDrink)
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
        #expect(!budget.fitsFirstGlance(visibleAccountRows: 1, includesSelectedDrillIn: true, includesChangeReceipt: true))
        #expect(budget.fitsFirstGlance(visibleAccountRows: 3, includesSelectedDrillIn: false, includesChangeReceipt: true))
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
        // Inclusive boundary: the 90% account ("2") and the exactly-at-threshold
        // 30% account ("3", -300/1000) both fire, matching the in-app surfaces.
        #expect(highUtil.count == 2)
        #expect(highUtil.map(\.id) == ["2", "3"])
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

    // MARK: - Energy-aware loop restart gating (mirrors AppState.handleEnergyStateChange)
    //
    // AppState caches the last constrained verdict and only restarts the
    // background refresh loop (which issues a server HTTP probe) when that verdict
    // flips. The verdict itself is `EnergyConditions.isConstrained` (pure Core).
    // These pin the boundary semantics the cache relies on so a fair→serious style
    // change inside the same constrained band does NOT cross the boundary.

    @Test("Energy constrained verdict only flips across the constrained boundary")
    func energyConstrainedVerdictBoundary() {
        func constrained(_ lowPower: Bool, _ thermal: EnergyAwareRefreshPolicy.EnergyThermalState) -> Bool {
            EnergyAwareRefreshPolicy.EnergyConditions(lowPowerMode: lowPower, thermalState: thermal).isConstrained
        }

        // Same side of the boundary — a restart would be redundant.
        #expect(constrained(false, .nominal) == constrained(false, .fair)) // both unconstrained
        #expect(constrained(false, .serious) == constrained(false, .critical)) // both constrained
        #expect(constrained(true, .serious) == constrained(true, .critical)) // both constrained

        // Crossing the boundary — a restart is warranted.
        #expect(constrained(false, .fair) != constrained(false, .serious))
        #expect(constrained(false, .nominal) != constrained(true, .nominal)) // low power flips it
    }

    @Test("Constrained verdict flip emits exactly one restart across a fair→serious→critical→nominal walk")
    func energyVerdictFlipCount() {
        // Mirror AppState's cache: start with no baseline (nil), then feed a
        // sequence of conditions and count how many times the verdict flips —
        // i.e. how many loop restarts (and HTTP probes) AppState would issue.
        let walk: [EnergyAwareRefreshPolicy.EnergyConditions] = [
            .init(lowPowerMode: false, thermalState: .nominal),  // baseline: false
            .init(lowPowerMode: false, thermalState: .fair),     // false → no flip
            .init(lowPowerMode: false, thermalState: .serious),  // true  → flip #1
            .init(lowPowerMode: false, thermalState: .critical), // true  → no flip
            .init(lowPowerMode: false, thermalState: .nominal),  // false → flip #2
        ]
        var last: Bool?
        var restarts = 0
        for conditions in walk {
            let verdict = conditions.isConstrained
            if verdict != last {
                restarts += 1
                last = verdict
            }
        }
        // Naive "restart on every notification" would be 5; gating yields 3
        // (the initial baseline establish + the two real boundary crossings).
        #expect(restarts == 3)
    }

    // MARK: - Navigation state migration (mirrors AppState/NavigationModel façade, AND-594)
    //
    // The app's `NavigationModel` (app target, not @testable-importable here)
    // persists the dashboard filter / account selection / heatmap metric to the
    // SAME UserDefaults keys the retired view-level `@AppStorage` used, so a
    // relaunch restores identically. These pin the migrated-key contract at the
    // pure layer: the raw values stored are the enum raw values MainPopover read.

    @Test("Migrated NavigationState raw values match the retired @AppStorage keys' encoding")
    func navigationStateMatchesAppStorageEncoding() {
        // The popover read DashboardAccountFilter.rawValue ("Cash" …),
        // SpendingHeatmapMode.rawValue ("netCashflow"), and a "" account-id
        // sentinel. A persisted NavigationState carries exactly those raw values.
        let state = NavigationState(
            destination: .dashboard,
            dashboardFilter: .credit,
            selectedAccountID: "demo_visa",
            heatmapMode: .netCashflow
        )
        #expect(state.dashboardFilter.rawValue == "Credit")
        #expect(state.heatmapMode.rawValue == "netCashflow")
        #expect(state.selectedAccountID == "demo_visa")

        // Defaults match the popover's old @AppStorage defaults exactly.
        let defaults = NavigationState()
        #expect(defaults.dashboardFilter.rawValue == DashboardAccountFilterKind.all.rawValue)
        #expect(defaults.dashboardFilter.rawValue == "All")
        #expect(defaults.selectedAccountID == "")
        #expect(defaults.heatmapMode.rawValue == SpendingHeatmapMode.spending.rawValue)
    }

    @Test("Persisted raw values restore the same NavigationState (relaunch parity)")
    func navigationStateRestoreParity() {
        // Simulate the model's hydrate(): decode the three stored raw values into
        // a NavigationState exactly as NavigationModel.hydrate does, proving a
        // round-trip through the migrated keys preserves the user's selection.
        let storedFilter = "Debt"
        let storedAccountID = "demo_checking"
        let storedHeatmap = "netCashflow"

        var restored = NavigationState()
        if let filter = DashboardAccountFilterKind(rawValue: storedFilter) {
            restored.dashboardFilter = filter
        }
        restored.selectedAccountID = storedAccountID
        if let mode = SpendingHeatmapMode(rawValue: storedHeatmap) {
            restored.heatmapMode = mode
        }

        #expect(restored.dashboardFilter == .debt)
        #expect(restored.selectedAccountID == "demo_checking")
        #expect(restored.heatmapMode == .netCashflow)
    }

    @Test("Filter-change-clears-selection holds through the façade contract")
    func facadeFilterChangeClearsSelection() {
        // The popover relied on `.onChange(of: filter) { selectedAccountId = "" }`;
        // the migrated model folds that rule into setDashboardFilter, so the
        // façade behaves identically without the view-level onChange.
        var state = NavigationState(dashboardFilter: .all, selectedAccountID: "demo_visa")
        state.setDashboardFilter(.credit)
        #expect(state.selectedAccountID == "")
    }

    // MARK: - Destination restoration (mirrors NavigationModel.hydrate, AND-597)
    //
    // AND-597 adds a `navigation.destination` UserDefaults key so the window-first
    // shell reopens on the destination the user left off (selection
    // persistence). `NavigationModel` is in the app target (not @testable here), so
    // these pin the persist/restore contract at the pure layer: a stored
    // `RouteDestination.rawValue` decodes back to the same destination, and an
    // absent key falls back to Dashboard (the upgrading-user / flag-OFF default).

    @Test("Persisted destination raw value restores the same destination (relaunch parity)")
    func destinationRestoreParity() {
        // Simulate NavigationModel.hydrate's destination branch for every
        // destination: round-trip through the raw value the model writes.
        for destination in RouteDestination.allCases {
            let storedRaw = destination.rawValue // what persistDestination() writes
            var restored = NavigationState()
            if let decoded = RouteDestination(rawValue: storedRaw) {
                restored.destination = decoded
            }
            #expect(restored.destination == destination)
        }
    }

    @Test("Absent destination key falls back to Dashboard (upgrading user / flag-OFF default)")
    func destinationRestoreDefaultsToDashboard() {
        // hydrate() only overrides the default when the key is present and decodes;
        // a nil stored value (the pre-AND-597 / flag-OFF case) leaves Dashboard.
        let storedRaw: String? = nil
        var restored = NavigationState()
        if let raw = storedRaw, let decoded = RouteDestination(rawValue: raw) {
            restored.destination = decoded
        }
        #expect(restored.destination == .dashboard)
    }

    @Test("Applying a deep-link route restores its destination AND its selection")
    func routeRestoresDestinationAndSelection() {
        // The full AND-597 round-trip at the pure layer: apply an account
        // deep-link, persist what NavigationModel would (destination raw +
        // account id), then rehydrate and confirm both survive a relaunch.
        var live = NavigationState()
        live.apply(.accounts(itemID: "demo_visa"))
        let storedDestination = live.destination.rawValue
        let storedAccountID = live.selectedAccountID

        var restored = NavigationState()
        if let decoded = RouteDestination(rawValue: storedDestination) {
            restored.destination = decoded
        }
        restored.selectedAccountID = storedAccountID

        #expect(restored.destination == .accounts)
        #expect(restored.selectedAccountID == "demo_visa")
    }

    // MARK: - Spotlight index/clear serialization (mirrors AccountSpotlightIndexer, bug-hunt R2)
    //
    // BUG #5 (privacy race): `index()` (a refresh's delete+reindex) and `clear()`
    // (a mask's delete) each spawned an independent `Task { @MainActor in … }`.
    // Independent Tasks suspend at their own `await`s with no ordering guarantee,
    // so a `clear()` issued *after* an `index()` could finish *before* it — leaving
    // real account names re-indexed in Spotlight *after* the Privacy Mask cleared
    // them. The fix funnels BOTH ops through a single in-flight chain (`pending` +
    // `enqueue`) so each awaits the previous, making refresh-then-mask strictly
    // ordered. AccountSpotlightIndexer is in the app target (not @testable here,
    // and `CSSearchableIndex` can't run in CI), so — like the window-first masking
    // test above — this pins the fix as a source-level invariant.

    @Test("AccountSpotlightIndexer serializes index/clear through a single in-flight Task chain")
    func spotlightIndexClearSerialized() throws {
        let root = URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
        let source = try String(
            contentsOf: root.appending(path: "Sources/PlaidBar/Spotlight/AccountSpotlightIndexer.swift"),
            encoding: .utf8
        )

        // The serialization primitives exist: one in-flight slot + an enqueue that
        // chains each op after the previous one's completion.
        #expect(source.contains("private static var pending: Task<Void, Never>?"))
        #expect(source.contains("private static func enqueue("))
        #expect(source.contains("let previous = pending"))
        #expect(source.contains("await previous?.value"))

        // Both mutating ops route through enqueue rather than spawning their own
        // unordered Task. The only remaining `Task { @MainActor in … }` is the
        // single chained one INSIDE enqueue — index()/clear() must not spawn their
        // own. (The bug was two independent `Task { @MainActor in … }`, one per op.)
        let enqueueCallSites = source.components(separatedBy: "enqueue {").count - 1
        #expect(enqueueCallSites == 2, "expected index() and clear() to each route through enqueue")
        let chainedTasks = source.components(separatedBy: "Task { @MainActor in").count - 1
        #expect(chainedTasks == 1, "only enqueue's single chained Task should exist")
    }

    // MARK: - Foundation Models categorization tier (mirrors AppState.refreshFoundationModelsCategorySuggestions)

    @Test("FM categorizer produces a foundationModels suggestion when Apple Intelligence is available")
    func fmCategorizerProducesSuggestionWhenAvailable() async {
        let categorizer = FMMerchantCategorizer(
            foundationModelsState: .available,
            nlCategorizer: NLMerchantCategorizer(),
            fmCategorizer: StubFMCategorizer(result: .foodAndDrink)
        )
        let txn = TransactionDTO(id: "fm1", accountId: "a", amount: 12, date: "2026-01-15", name: "Local Cafe", category: nil)

        let suggestion = await categorizer.suggest(for: txn)

        #expect(suggestion?.tier == .foundationModels)
        #expect(suggestion?.category == .foodAndDrink)
        #expect(suggestion?.isTrusted == true)
    }

    @Test("FM categorizer skips the model when Apple Intelligence is not available")
    func fmCategorizerSkippedWhenUnavailable() async {
        // The stub would force a (wrong) FM result if it were ever consulted; an
        // unavailable state must bypass it entirely, matching AppState's guard
        // that makes the no-FM device never call the model.
        let stub = StubFMCategorizer(result: .travel)
        let categorizer = FMMerchantCategorizer(
            foundationModelsState: .unsupported,
            nlCategorizer: NLMerchantCategorizer(),
            fmCategorizer: stub
        )
        let txn = TransactionDTO(id: "fm2", accountId: "a", amount: 12, date: "2026-01-15", name: "Local Cafe", category: nil)

        let suggestion = await categorizer.suggest(for: txn)

        #expect(suggestion?.tier != .foundationModels)
        #expect(stub.callCount == 0)
    }

    // Regression for the bug-hunt R5 fix: AppState's
    // `_foundationModelsCategorySuggestions` cache was insert-only, so entries
    // for transactions that left the Review Inbox (categorized/approved/
    // ignored/dropped) were never evicted and memory grew with session-
    // cumulative throughput instead of live inbox size. AppState is an
    // executable @main target (not @testable-importable), so this pins the
    // exact prune expression the fix runs at the top of
    // `refreshFoundationModelsCategorySuggestions()`:
    //   cache = cache.filter { liveIDs.contains($0.key) }
    @Test("FM suggestion cache evicts entries whose transactions left the inbox")
    func fmSuggestionCacheEvictsDepartedInboxItems() {
        // Two items previously cached this session.
        var cache: [String: MerchantCategorySuggestion] = [
            "txn-still-here": MerchantCategorySuggestion(category: .foodAndDrink, tier: .foundationModels, isTrusted: true),
            "txn-left-inbox": MerchantCategorySuggestion(category: .travel, tier: .foundationModels, isTrusted: true),
        ]

        // The live inbox now contains only the first item; the second was
        // categorized/approved/dropped and no longer appears.
        let liveIDs = Set(["txn-still-here"])

        // The prune AppState performs after the availability guard.
        cache = cache.filter { liveIDs.contains($0.key) }

        #expect(cache["txn-still-here"] != nil, "live inbox item's suggestion must be retained")
        #expect(cache["txn-left-inbox"] == nil, "departed item's suggestion must be evicted")
        #expect(cache.count == 1, "cache must track live inbox size, not cumulative throughput")
    }

    @Test("FM suggestion cache prune is a no-op when every cached item is still live")
    func fmSuggestionCachePruneNoOpWhenAllLive() {
        var cache: [String: MerchantCategorySuggestion] = [
            "a": MerchantCategorySuggestion(category: .foodAndDrink, tier: .foundationModels, isTrusted: true),
            "b": MerchantCategorySuggestion(category: .travel, tier: .foundationModels, isTrusted: true),
        ]
        let liveIDs = Set(["a", "b"])

        cache = cache.filter { liveIDs.contains($0.key) }

        #expect(cache.count == 2, "no eviction when every cached id is still in the inbox")
    }

    // MARK: - Window-scale shared sub-components + unified search (AND-625)

    /// Source-invariant guard for AND-625 part (1): the shared sub-components that
    /// are re-hosted in both the popover and the window must carry a
    /// `ComponentScale` hint and reference the window type roles
    /// (`windowDataText` / `windowFigureCaption` / `windowBodyText` /
    /// `windowCardTitle`), so window canvases render them at desk-distance scale
    /// rather than shrunken popover caption-scale. Default `.popover` keeps the
    /// glance byte-for-byte. Asserts the call sites, not pixels — the app target is
    /// an `@main` executable that can't be `@testable import`ed.
    @Test("Shared sub-components adopt the window type roles when hosted in a window (AND-625)")
    func sharedSubComponentsScaleToWindowRoles() throws {
        let root = URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
        let recurringSource = try String(
            contentsOf: root.appending(path: "Sources/PlaidBar/Views/RecurringObligationsSection.swift"),
            encoding: .utf8
        )
        let balanceSource = try String(
            contentsOf: root.appending(path: "Sources/PlaidBar/Views/BalanceTimeMachineView.swift"),
            encoding: .utf8
        )

        // Both components must take a ComponentScale that defaults to .popover so
        // the glance is unaffected and only window callers opt into window scale.
        for source in [recurringSource, balanceSource] {
            #expect(source.contains("var scale: ComponentScale = .popover"))
            // The window branch must reach for the window roles, not the popover's
            // caption-scale microText/sectionTitle.
            #expect(source.contains("windowDataText()"))
            #expect(source.contains("windowFigureCaption()"))
            #expect(source.contains("windowBodyText()"))
            #expect(source.contains("windowCardTitle()"))
        }

        // The window call sites must pass `.window`; the popover call site keeps the
        // default. (Window: DashboardRecurringCard, PlanningDestinationView,
        // DashboardOverviewColumn. Popover: WealthSummaryFlyout, MainPopover.)
        let dashboardRecurring = try String(
            contentsOf: root.appending(path: "Sources/PlaidBar/Views/Destinations/DashboardRecurringCard.swift"),
            encoding: .utf8
        )
        let planning = try String(
            contentsOf: root.appending(path: "Sources/PlaidBar/Views/Destinations/PlanningDestinationView.swift"),
            encoding: .utf8
        )
        let overviewColumn = try String(
            contentsOf: root.appending(path: "Sources/PlaidBar/Views/Destinations/DashboardOverviewColumn.swift"),
            encoding: .utf8
        )
        let wealthFlyout = try String(
            contentsOf: root.appending(path: "Sources/PlaidBar/Views/WealthSummaryFlyout.swift"),
            encoding: .utf8
        )

        #expect(dashboardRecurring.contains("scale: .window"))
        #expect(planning.contains("scale: .window"))
        #expect(overviewColumn.contains("BalanceTimeMachineView(scale: .window)"))
        // The popover host must NOT opt into window scale (would inflate the glance).
        #expect(!wealthFlyout.contains("scale: .window"))
    }

    /// Source-invariant guard for AND-625 part (2): the window shell's unified
    /// `.searchable` field now propagates to a second destination (Accounts), which
    /// filters its account list by the shared `\.shellSearchQuery` environment value
    /// exactly like the Dashboard — one consistent toolbar field, no competing
    /// inline search, no leak across destinations.
    @Test("Accounts adopts the shell's unified search field via \\.shellSearchQuery (AND-625)")
    func accountsAdoptsUnifiedShellSearch() throws {
        let root = URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
        let shell = try String(
            contentsOf: root.appending(path: "Sources/PlaidBar/Views/AppShellView.swift"),
            encoding: .utf8
        )
        let accounts = try String(
            contentsOf: root.appending(path: "Sources/PlaidBar/Views/Destinations/AccountsDestinationView.swift"),
            encoding: .utf8
        )

        // The shell routes its single field to both Dashboard and Accounts and
        // injects the neutral, unified env key (not the old Dashboard-specific one).
        #expect(shell.contains("case .dashboard, .accounts: true"))
        #expect(shell.contains("let isSearchEnabled = destinationSupportsSearch(destination) && !appState.isContentLocked"))
        #expect(shell.contains(".environment(\\.shellSearchQuery,"))
        #expect(shell.contains("searchText = \"\""))
        #expect(!shell.contains("dashboardSearchQuery"))

        // Accounts reads the shared query and filters by display name (never a masked
        // amount), with a contextual no-results state.
        #expect(accounts.contains("@Environment(\\.shellSearchQuery)"))
        #expect(accounts.contains("localizedCaseInsensitiveContains(query)"))
        #expect(accounts.contains("ContentUnavailableView.search(text:"))
        #expect(accounts.contains(".onChange(of: filteredAccounts.map(\\.id))"))
        #expect(accounts.contains("visibleAccounts.map(\\.id)"))
    }
}

/// Deterministic `FMMerchantCategorizing` stub for the categorization-tier tests.
/// Mirrors the in-app FoundationModels seam without importing the app target
/// (which an executable target cannot expose to tests).
private final class StubFMCategorizer: FMMerchantCategorizing, @unchecked Sendable {
    private let result: SpendingCategory?
    private let callCountStorage = Mutex(0)
    var callCount: Int {
        callCountStorage.withLock { $0 }
    }

    init(result: SpendingCategory?) {
        self.result = result
    }

    func suggestCategory(merchant: String) async -> String? {
        callCountStorage.withLock { $0 += 1 }
        return result?.rawValue
    }
}
