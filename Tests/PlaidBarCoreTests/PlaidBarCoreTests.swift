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

    @Test("Account transaction feed sorts latest first with pending tie-breaker")
    func accountTransactionFeedSortsLatestFirstWithPendingTieBreaker() {
        let transactions = [
            TransactionDTO(id: "old", accountId: "checking", amount: 10, date: "2026-01-13", name: "Old"),
            TransactionDTO(id: "other", accountId: "credit", amount: 999, date: "2026-01-16", name: "Other"),
            TransactionDTO(id: "posted-small", accountId: "checking", amount: 20, date: "2026-01-15", name: "Posted Small"),
            TransactionDTO(id: "pending", accountId: "checking", amount: 30, date: "2026-01-15", name: "Pending", pending: true),
            TransactionDTO(id: "posted-large", accountId: "checking", amount: 50, date: "2026-01-15", name: "Posted Large"),
        ]

        let feed = AccountTransactionFeed.transactions(forAccountId: "checking", in: transactions)

        #expect(feed.map(\.id) == ["pending", "posted-large", "posted-small", "old"])
    }

    @Test("Account transaction feed keeps invalid dates behind dated transactions")
    func accountTransactionFeedKeepsInvalidDatesBehindDatedTransactions() {
        let transactions = [
            TransactionDTO(id: "invalid", accountId: "checking", amount: 10, date: "not-a-date", name: "Invalid"),
            TransactionDTO(id: "dated", accountId: "checking", amount: 20, date: "2026-01-15", name: "Dated"),
        ]

        let feed = AccountTransactionFeed.transactions(forAccountId: "checking", in: transactions)

        #expect(feed.map(\.id) == ["dated", "invalid"])
    }

    @Test("Account transaction feed sorts related merchant transactions")
    func accountTransactionFeedSortsRelatedMerchantTransactions() {
        let transactions = [
            TransactionDTO(id: "current", accountId: "a", amount: 20, date: "2026-01-15", name: "Current", merchantName: "Netflix"),
            TransactionDTO(id: "old", accountId: "a", amount: 20, date: "2026-01-13", name: "Old", merchantName: "Netflix"),
            TransactionDTO(id: "pending", accountId: "a", amount: 20, date: "2026-01-14", name: "Pending", merchantName: "Netflix", pending: true),
            TransactionDTO(id: "other", accountId: "a", amount: 20, date: "2026-01-16", name: "Other", merchantName: "Spotify"),
        ]

        let feed = AccountTransactionFeed.relatedMerchantTransactions(
            merchantName: "Netflix",
            excluding: "current",
            in: transactions
        )

        #expect(feed.map(\.id) == ["pending", "old"])
    }

    @Test("Account activity empty state is nil when transactions exist")
    func accountActivityEmptyStateNilWithTransactions() {
        let presentation = AccountActivityEmptyState.evaluate(
            transactionCount: 1,
            isDemoMode: false,
            serverConnected: true,
            connectionLevel: .healthy,
            accountDisplayName: "Chase Checking"
        )

        #expect(presentation == nil)
    }

    @Test("Account activity empty state explains offline server")
    func accountActivityEmptyStateOfflineServer() {
        let presentation = AccountActivityEmptyState.evaluate(
            transactionCount: 0,
            isDemoMode: false,
            serverConnected: false,
            connectionLevel: .offline,
            accountDisplayName: "Chase Checking"
        )

        #expect(presentation?.title == "Server offline")
        #expect(presentation?.tone == .offline)
        #expect(presentation?.detail.contains("Start PlaidBarServer") == true)
    }

    @Test("Account activity empty state explains login recovery")
    func accountActivityEmptyStateLoginRecovery() {
        let presentation = AccountActivityEmptyState.evaluate(
            transactionCount: 0,
            isDemoMode: false,
            serverConnected: true,
            connectionLevel: .loginRequired,
            accountDisplayName: "Amex Gold"
        )

        #expect(presentation?.title == "Reconnect to sync activity")
        #expect(presentation?.tone == .warning)
        #expect(presentation?.detail.contains("fresh bank login") == true)
    }

    @Test("Account activity empty state explains healthy no history")
    func accountActivityEmptyStateHealthyNoHistory() {
        let presentation = AccountActivityEmptyState.evaluate(
            transactionCount: 0,
            isDemoMode: false,
            serverConnected: true,
            connectionLevel: .healthy,
            accountDisplayName: "Savings"
        )

        #expect(presentation?.title == "No recent activity")
        #expect(presentation?.tone == .healthy)
        #expect(presentation?.detail.contains("linked") == true)
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

    @Test("Spending heatmap excludes non-canonical date strings")
    func spendingHeatmapExcludesNonCanonicalDateStrings() {
        let start = Formatters.parseTransactionDate("2026-06-01")!
        let end = Formatters.parseTransactionDate("2026-06-03")!

        let days = SpendingHeatmap.days(
            from: [
                TransactionDTO(id: "1", accountId: "a", amount: 25, date: "2026-06-02", name: "Canonical"),
                TransactionDTO(id: "2", accountId: "a", amount: 30, date: "2026-6-2", name: "Unpadded"),
                TransactionDTO(id: "3", accountId: "a", amount: 35, date: "not-a-date!", name: "Garbage"),
            ],
            startDate: start,
            endDate: end,
            mode: .spending
        )

        #expect(days.map(\.value) == [0, 25, 0])
        #expect(days.map(\.transactionCount) == [0, 1, 0])
    }

    @Test("Spending heatmap day aggregation matches parse-based reference")
    func spendingHeatmapMatchesParseBasedReference() {
        let start = Formatters.parseTransactionDate("2026-04-01")!
        let end = Formatters.parseTransactionDate("2026-05-31")!
        let transactions = (0 ..< 240).map { index -> TransactionDTO in
            let day = String(format: "2026-%02d-%02d", 4 + (index % 2), 1 + (index % 28))
            let category: SpendingCategory? = index % 11 == 0 ? .transfer : (index % 7 == 0 ? .income : .shopping)
            return TransactionDTO(
                id: "ref_\(index)",
                accountId: "a",
                amount: index % 7 == 0 ? -Double(index) : Double(index) * 1.37,
                date: day,
                name: "Merchant \(index % 9)",
                category: category
            )
        }

        for mode in [SpendingHeatmapMode.spending, .netCashflow] {
            let fast = SpendingHeatmap.days(from: transactions, startDate: start, endDate: end, mode: mode)
            let reference = parseBasedHeatmapReference(from: transactions, startDate: start, endDate: end, mode: mode)
            #expect(fast.count == reference.count)
            for (lhs, rhs) in zip(fast, reference) {
                #expect(lhs.date == rhs.date)
                #expect(abs(lhs.value - rhs.value) < 0.000001)
                #expect(lhs.transactionCount == rhs.transactionCount)
            }
        }
    }

    @Test("Spending heatmap layout matches individually derived values")
    func spendingHeatmapLayoutMatchesDerivedValues() {
        let start = Formatters.parseTransactionDate("2026-01-01")!
        let end = Formatters.parseTransactionDate("2026-01-10")!
        let transactions = [
            TransactionDTO(id: "1", accountId: "a", amount: 25, date: "2026-01-02", name: "Coffee"),
            TransactionDTO(id: "2", accountId: "a", amount: 75, date: "2026-01-05", name: "Groceries"),
            TransactionDTO(id: "3", accountId: "a", amount: -200, date: "2026-01-06", name: "Refund"),
        ]

        let layout = SpendingHeatmapLayout.compute(
            from: transactions,
            startDate: start,
            endDate: end,
            mode: .spending
        )
        let days = SpendingHeatmap.days(from: transactions, startDate: start, endDate: end, mode: .spending)

        #expect(layout.days == days)
        #expect(layout.peakValue == max(days.map { abs($0.value) }.max() ?? 0, 1))
        #expect(abs(layout.totalValue - days.reduce(0) { $0 + $1.value }) < 0.000001)
        #expect(layout.activeDayCount == days.count(where: { $0.transactionCount > 0 }))
        #expect(layout.weekColumns.flatMap(\.self).compactMap(\.self) == days)
    }

    @Test("Spending heatmap layout aligns week columns to first weekday")
    func spendingHeatmapLayoutWeekColumnAlignment() {
        var calendar = Calendar(identifier: .gregorian)
        calendar.firstWeekday = 1
        // 2026-01-01 is a Thursday (weekday 5), so a Sunday-first grid pads 4 cells.
        let start = Formatters.parseTransactionDate("2026-01-01")!
        let end = Formatters.parseTransactionDate("2026-01-10")!

        let layout = SpendingHeatmapLayout.compute(
            from: [TransactionDTO(id: "1", accountId: "a", amount: 25, date: "2026-01-02", name: "Coffee")],
            startDate: start,
            endDate: end,
            mode: .spending,
            calendar: calendar
        )

        #expect(layout.weekColumns.count == 2)
        #expect(layout.weekColumns.allSatisfy { $0.count == 7 })
        #expect(layout.weekColumns[0].prefix(4).allSatisfy { $0 == nil })
        #expect(layout.weekColumns[0][4]?.date == "2026-01-01")
        #expect(layout.weekColumns.flatMap(\.self).compactMap(\.self).count == 10)
    }

    @Test("Spending heatmap layout dedupes month markers per month")
    func spendingHeatmapLayoutMonthMarkers() {
        let calendar = Calendar.current
        // Range spans late December through early February: December has no
        // day-of-month <= 7 in range, so only January and February get markers.
        let start = Formatters.parseTransactionDate("2025-12-25")!
        let end = Formatters.parseTransactionDate("2026-02-10")!

        let layout = SpendingHeatmapLayout.compute(
            from: [],
            startDate: start,
            endDate: end,
            mode: .spending,
            calendar: calendar
        )

        #expect(layout.monthMarkers.count == 2)
        #expect(layout.monthMarkers[0].label == calendar.shortMonthSymbols[0])
        #expect(layout.monthMarkers[1].label == calendar.shortMonthSymbols[1])
        #expect(layout.monthMarkers[0].weekIndex < layout.monthMarkers[1].weekIndex)
    }

    @Test("Canonical transaction date key validation")
    func canonicalTransactionDateKeyValidation() {
        #expect(Formatters.isCanonicalTransactionDateKey("2026-06-10"))
        #expect(Formatters.isCanonicalTransactionDateKey("1999-01-01"))
        #expect(!Formatters.isCanonicalTransactionDateKey("2026-6-10"))
        #expect(!Formatters.isCanonicalTransactionDateKey("2026-06-1"))
        #expect(!Formatters.isCanonicalTransactionDateKey("2026/06/10"))
        #expect(!Formatters.isCanonicalTransactionDateKey("2026-06-10T00:00:00"))
        #expect(!Formatters.isCanonicalTransactionDateKey(""))
        #expect(!Formatters.isCanonicalTransactionDateKey("yyyy-MM-dd"))
    }

    /// Pre-optimization reference implementation of `SpendingHeatmap.days`.
    /// The transfer exclusion mirrors production's `isTransfer`, which is
    /// purely category-based (`.transfer` / `.transferOut`); if production
    /// ever adds non-category transfer detection, update this to match.
    private func parseBasedHeatmapReference(
        from transactions: [TransactionDTO],
        startDate: Date,
        endDate: Date,
        mode: SpendingHeatmapMode,
        calendar: Calendar = .current
    ) -> [SpendingHeatmapDay] {
        let start = calendar.startOfDay(for: startDate)
        let end = calendar.startOfDay(for: endDate)
        guard start <= end else { return [] }

        let relevant = transactions.compactMap { transaction -> (String, Double)? in
            guard let date = Formatters.parseTransactionDate(transaction.date) else { return nil }
            let day = calendar.startOfDay(for: date)
            guard day >= start, day <= end else { return nil }
            guard transaction.category != .transfer, transaction.category != .transferOut else { return nil }

            switch mode {
            case .spending:
                guard !transaction.isIncome else { return nil }
                return (transaction.date, transaction.displayAmount)
            case .netCashflow:
                return (transaction.date, transaction.amount)
            }
        }

        let grouped = Dictionary(grouping: relevant) { $0.0 }
        let dayCount = calendar.dateComponents([.day], from: start, to: end).day ?? 0

        return (0 ... dayCount).compactMap { offset in
            guard let day = calendar.date(byAdding: .day, value: offset, to: start) else { return nil }
            let dateString = Formatters.transactionDateString(day)
            let entries = grouped[dateString] ?? []
            return SpendingHeatmapDay(
                date: dateString,
                value: entries.reduce(0) { $0 + $1.1 },
                transactionCount: entries.count
            )
        }
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

    @Test("Menu bar summary recent spend respects window boundaries")
    func menuBarSummaryRecentSpendWindowBoundaries() {
        let now = Formatters.parseTransactionDate("2026-03-10")!
        let transactions = [
            TransactionDTO(id: "1", accountId: "a", amount: 10, date: "2026-03-10", name: "Today"),
            TransactionDTO(id: "2", accountId: "a", amount: 20, date: "2026-03-04", name: "Window start"),
            TransactionDTO(id: "3", accountId: "a", amount: 40, date: "2026-03-03", name: "Before window"),
            TransactionDTO(id: "4", accountId: "a", amount: 80, date: "2026-03-11", name: "Future"),
            TransactionDTO(id: "5", accountId: "a", amount: 160, date: "2026-3-9", name: "Non-canonical date"),
        ]

        // 7-day window ending 2026-03-10 starts at 2026-03-04: the boundary day
        // counts, earlier days and future-dated or malformed entries do not.
        #expect(MenuBarSummary.recentSpend(from: transactions, now: now) == 30)
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

    @Test("Account activity summary defaults to latest transaction date")
    func accountActivitySummaryDefaultsToLatestTransactionDate() {
        let transactions = [
            TransactionDTO(id: "recent", accountId: "a", amount: 100, date: "2026-01-30", name: "Groceries"),
            TransactionDTO(id: "included", accountId: "a", amount: -2_000, date: "2026-01-10", name: "Payroll", category: .income),
            TransactionDTO(id: "old", accountId: "a", amount: 75, date: "2025-12-01", name: "Old"),
            TransactionDTO(id: "invalid", accountId: "a", amount: 25, date: "not-a-date", name: "Invalid")
        ]

        let summary = AccountActivitySummary.recent(from: transactions)

        #expect(summary.transactionCount == 2)
        #expect(summary.outflowTotal == 100)
        #expect(summary.inflowTotal == 2_000)
    }

    @Test("Account activity summary explicit now excludes future transactions")
    func accountActivitySummaryExplicitNowExcludesFutureTransactions() {
        let now = Formatters.parseTransactionDate("2026-01-15")!
        let transactions = [
            TransactionDTO(id: "current", accountId: "a", amount: 25, date: "2026-01-15", name: "Coffee"),
            TransactionDTO(id: "future", accountId: "a", amount: 100, date: "2026-01-30", name: "Future")
        ]

        let summary = AccountActivitySummary.recent(from: transactions, now: now)

        #expect(summary.transactionCount == 1)
        #expect(summary.outflowTotal == 25)
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
        #expect(AccountPresentation.dashboardTrailingDetailText(
            for: checking,
            connectionLabel: "2m ago"
        ) == "2m ago")
        #expect(AccountPresentation.dashboardTrailingDetailText(
            for: credit,
            connectionLabel: "2m ago"
        ) == "45% • $550 available • due not synced")
        #expect(AccountPresentation.creditDueMetadataText(for: credit) == "due not synced")
        #expect(AccountPresentation.dashboardAvailableTitle(for: checking) == "Available")
        #expect(AccountPresentation.dashboardAvailableTitle(for: credit) == "Avail Credit")
        #expect(AccountPresentation.dashboardCurrentTitle(for: checking) == "Current")
        #expect(AccountPresentation.dashboardCurrentTitle(for: credit) == "Owed")
        #expect(AccountPresentation.dashboardUtilizationDetailText(for: credit) == "45% of $1,000, Warning")
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
        ) == "Rewards, Amex, Credit, Ending in 0005, $450.00 owed, 45% utilization, Warning, $550.00 available credit, due not synced, 2m ago, selected")
    }

    @Test("Account drill-in summary includes balances transactions freshness and sync")
    func accountDrillInSummaryIncludesCoreSurfaces() {
        let lastSync = Date(timeIntervalSince1970: 1_700_000_000)
        let account = AccountDTO(
            id: "acct-internal-123",
            itemId: "item-internal-456",
            name: "Rewards",
            type: .credit,
            mask: "0005",
            balances: BalanceDTO(current: -450, limit: 1_000),
            institutionName: "Amex"
        )
        let summary = DashboardAccountDrillInSummary.presentation(
            for: account,
            transactions: [
                TransactionDTO(id: "tx-1", accountId: account.id, amount: 24, date: "2026-06-01", name: "Coffee"),
                TransactionDTO(id: "tx-2", accountId: account.id, amount: -100, date: "2026-06-03", name: "Refund", pending: true),
                TransactionDTO(id: "tx-other", accountId: "other", amount: 7, date: "2026-06-04", name: "Other"),
            ],
            itemStatus: ItemStatus(id: account.itemId, institutionName: "Amex", status: .loginRequired, lastSync: lastSync),
            fallbackFreshnessLabel: "Not synced"
        )

        #expect(summary.displayName == "Rewards")
        #expect(summary.subtitle == "Credit • Credit •••• 0005")
        #expect(summary.availableTitle == "Avail Credit")
        #expect(summary.availableBalance == 550)
        #expect(summary.currentTitle == "Owed")
        #expect(summary.currentBalance == 450)
        #expect(summary.utilizationPercent == 45)
        #expect(summary.limit == 1_000)
        #expect(summary.transactionCount == 2)
        #expect(summary.pendingTransactionCount == 1)
        #expect(summary.latestTransactionDate == "2026-06-03")
        #expect(summary.syncState == .loginRequired)
        #expect(summary.freshnessLabel != "Not synced")
        #expect(!summary.displayName.contains(account.id))
        #expect(!summary.subtitle.contains(account.itemId))
    }

    @Test("Account drill-in summary accessibility stays display safe")
    func accountDrillInSummaryAccessibilityStaysDisplaySafe() {
        let account = AccountDTO(
            id: "acct-internal-123",
            itemId: "item-internal-456",
            name: "Everyday",
            type: .depository,
            subtype: "checking",
            mask: "1234",
            balances: BalanceDTO(available: 500, current: 520),
            institutionName: "Chase"
        )
        let summary = DashboardAccountDrillInSummary.presentation(
            for: account,
            transactions: [
                TransactionDTO(id: "tx-1", accountId: account.id, amount: 24, date: "2026-06-01", name: "Coffee", pending: true)
            ],
            itemStatus: ItemStatus(id: account.itemId, institutionName: "Chase", status: .connected, lastSync: nil),
            fallbackFreshnessLabel: "Fresh"
        )

        #expect(summary.accessibilityLabel.contains("Selected account drill-in"))
        #expect(summary.accessibilityLabel.contains("Everyday"))
        #expect(summary.accessibilityLabel.contains("Available $500.00"))
        #expect(summary.accessibilityLabel.contains("1 synced transaction"))
        #expect(summary.accessibilityLabel.contains("1 pending transaction"))
        #expect(summary.accessibilityLabel.contains("Latest transaction Jun 1, 2026"))
        #expect(!summary.accessibilityLabel.contains(account.id))
        #expect(!summary.accessibilityLabel.contains(account.itemId))
    }

    @Test("Drill-in action accessibility labels include display names only")
    func drillInActionAccessibilityLabelsUseDisplayNamesOnly() {
        let displayName = "Everyday Checking"

        #expect(DashboardDrillInAction.reconnect.accessibilityLabel(accountDisplayName: displayName) == "Reconnect Everyday Checking")
        #expect(DashboardDrillInAction.remove.accessibilityLabel(accountDisplayName: displayName) == "Remove institution for Everyday Checking")
        #expect(DashboardDrillInAction.settings.accessibilityLabel(accountDisplayName: displayName) == "Open PlaidBar settings from Everyday Checking")
        #expect(DashboardDrillInAction.remove.accessibilityHint.contains("Requires confirmation"))
    }

    @Test("Account activity empty-state accessibility combines title and recovery detail")
    func accountActivityEmptyStateAccessibilityCombinesTitleAndDetail() {
        let presentation = AccountActivityEmptyState.evaluate(
            transactionCount: 0,
            isDemoMode: false,
            serverConnected: false,
            connectionLevel: .offline,
            accountDisplayName: "Everyday Checking"
        )

        #expect(presentation?.accessibilityLabel == "Server offline. Start PlaidBarServer, then refresh to load recent activity for Everyday Checking.")
    }

    @Test("Account presentation keeps credit metadata readable without due dates")
    func accountPresentationCreditMetadataWithoutDueDates() {
        let creditWithoutLimit = AccountDTO(
            id: "2",
            itemId: "i",
            name: "Rewards",
            type: .credit,
            mask: "0005",
            balances: BalanceDTO(available: 125, current: -450),
            institutionName: "Amex"
        )

        #expect(AccountPresentation.dashboardTrailingDetailText(
            for: creditWithoutLimit,
            connectionLabel: "Synced"
        ) == "$125 available • due not synced")
        #expect(AccountPresentation.rowAccessibilityLabel(
            for: creditWithoutLimit,
            amountText: "$450.00",
            connectionLabel: "Synced"
        ) == "Rewards, Amex, Credit, Ending in 0005, $450.00 owed, $125.00 available credit, due not synced, Synced")
    }

    @Test("Account presentation row accessibility stays scoped to display-safe fields")
    func accountPresentationRowAccessibilityUsesDisplaySafeFields() {
        let account = AccountDTO(
            id: "acct-internal-123",
            itemId: "item-internal-456",
            name: "Everyday",
            type: .depository,
            subtype: "checking",
            mask: "1234",
            balances: BalanceDTO(current: 500),
            institutionName: "Chase"
        )

        let label = AccountPresentation.rowAccessibilityLabel(
            for: account,
            amountText: "$500.00",
            connectionLabel: "Fresh",
            pendingCount: 2,
            isSelected: true
        )

        #expect(label == "Everyday, Chase, Depository, Ending in 1234, $500.00, Fresh, 2 pending transactions, selected")
        #expect(!label.contains(account.id))
        #expect(!label.contains(account.itemId))
    }

    @Test("Account drill-in path gives selected rows predictable activation copy")
    func accountDrillInPathActivationCopy() {
        let account = AccountDTO(
            id: "acct-internal-123",
            itemId: "item-internal-456",
            name: "Everyday",
            type: .depository,
            subtype: "checking",
            mask: "1234",
            balances: BalanceDTO(current: 500),
            institutionName: "Chase"
        )

        let collapsed = DashboardAccountDrillInPath.presentation(for: account, isSelected: false)
        let expanded = DashboardAccountDrillInPath.presentation(for: account, isSelected: true)

        #expect(collapsed.accessibilityHint == "Press Return or Space to open the account drill-in below this row.")
        #expect(collapsed.accessibilityActionName == "Open account details")
        #expect(collapsed.pointerHelp == "Open details for Everyday")
        #expect(expanded.accessibilityHint == "Press Return or Space to collapse the account drill-in.")
        #expect(expanded.accessibilityActionName == "Collapse account details")
        #expect(expanded.pointerHelp == "Collapse details for Everyday")
        #expect(!collapsed.pointerHelp.contains(account.id))
        #expect(!collapsed.pointerHelp.contains(account.itemId))
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
        #expect(stale.rowLabel == "Stale • 2h ago")
        #expect(stale.detailLabel == "Last sync 2h ago")
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
        #expect(loginRequired.rowLabel == "Reconnect Item")
        #expect(loginRequired.detailLabel == "Login required")
        #expect(loginRequired.signalLabel == "Login")
        #expect(loginRequired.recoveryActionTitle == "Reconnect Item")
        #expect(loginRequired.itemSyncLabel == "No sync recorded")
        #expect(loginRequired.statusFilterSubtitle == "Login required • No sync recorded")
        #expect(loginRequired.recoveryDetailLabel == "Plaid requires a fresh bank login. Reconnect this item, then refresh.")
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
        #expect(errored.recoveryActionTitle == "Reconnect Item")
        #expect(errored.statusFilterSubtitle == "Item error • No sync recorded")
        #expect(errored.recoveryDetailLabel == "Plaid reported an item error. Reconnect this item, then refresh.")
        #expect(errored.showsRecoveryActions)
    }

    @Test("Account connection presentation surfaces item sync for status recovery")
    func accountConnectionPresentationSurfacesItemSyncForStatusRecovery() {
        let loginRequired = AccountConnectionPresentation.evaluate(
            isDemoMode: false,
            serverConnected: true,
            isSyncStale: false,
            statusSyncText: "2m ago",
            itemStatus: .loginRequired,
            institutionName: "Chase",
            itemLastSyncRelative: "3h ago"
        )

        #expect(loginRequired.itemSyncLabel == "Last sync 3h ago")
        #expect(loginRequired.statusFilterSubtitle == "Login required • Last sync 3h ago")
        #expect(loginRequired.recoveryDetailLabel == "Plaid requires a fresh Chase login. Reconnect this item, then refresh.")

        let errored = AccountConnectionPresentation.evaluate(
            isDemoMode: false,
            serverConnected: true,
            isSyncStale: false,
            statusSyncText: "2m ago",
            itemStatus: .error,
            institutionName: "Amex",
            itemLastSyncRelative: "yesterday"
        )

        #expect(errored.itemSyncLabel == "Last sync yesterday")
        #expect(errored.statusFilterSubtitle == "Item error • Last sync yesterday")
        #expect(errored.recoveryDetailLabel == "Plaid reported an item error for Amex. Reconnect this item, then refresh.")
    }

    @Test("Account connection presentation names degraded institutions")
    func accountConnectionPresentationNamesDegradedInstitutions() {
        let loginRequired = AccountConnectionPresentation.evaluate(
            isDemoMode: false,
            serverConnected: true,
            isSyncStale: false,
            statusSyncText: "2m ago",
            itemStatus: .loginRequired,
            institutionName: "Chase"
        )

        #expect(loginRequired.rowLabel == "Reconnect Chase")
        #expect(loginRequired.detailLabel == "Chase login required")
        #expect(loginRequired.recoveryActionTitle == "Reconnect Chase")

        let errored = AccountConnectionPresentation.evaluate(
            isDemoMode: false,
            serverConnected: true,
            isSyncStale: false,
            statusSyncText: "2m ago",
            itemStatus: .error,
            institutionName: " American Express "
        )

        #expect(errored.rowLabel == "American Express item error")
        #expect(errored.detailLabel == "American Express item error")
        #expect(errored.recoveryActionTitle == "Reconnect American Express")
    }

    @Test("Item recovery target prioritizes item errors")
    func itemRecoveryTargetPrioritizesItemErrors() {
        let statuses = [
            ItemStatus(id: "login", institutionName: "Chase", status: .loginRequired),
            ItemStatus(id: "error", institutionName: "Amex", status: .error),
        ]

        #expect(ItemRecoveryTarget.itemId(from: statuses) == "error")
        #expect(ItemRecoveryTarget.actionTitle(from: statuses) == "Reconnect Amex")
        #expect(ItemRecoveryTarget.recoveryDetail(from: statuses) == "Plaid reported an item error for Amex. Reconnect it, then refresh balances.")
    }

    @Test("Item recovery target explains login required recovery")
    func itemRecoveryTargetExplainsLoginRequiredRecovery() {
        let statuses = [
            ItemStatus(id: "connected", institutionName: "Bank", status: .connected),
            ItemStatus(id: "login", institutionName: " Chase ", status: .loginRequired),
        ]

        #expect(ItemRecoveryTarget.itemId(from: statuses) == "login")
        #expect(ItemRecoveryTarget.actionTitle(from: statuses) == "Reconnect Chase")
        #expect(ItemRecoveryTarget.recoveryDetail(from: statuses) == "Plaid requires a fresh Chase login before account rows can be recovered.")
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

    @Test("Heatmap mode labels distinguish spend from net cashflow semantics")
    func heatmapModeLabelsDistinguishSemantics() {
        #expect(SpendingHeatmapMode.spending.shortLabel == "Spend")
        #expect(SpendingHeatmapMode.spending.summaryTitle == "365D Spend")
        #expect(SpendingHeatmapMode.spending.semanticDescription.contains("Outflows only"))
        #expect(SpendingHeatmapMode.netCashflow.shortLabel == "Cashflow")
        #expect(SpendingHeatmapMode.netCashflow.summaryTitle == "365D Net Cashflow")
        #expect(SpendingHeatmapMode.netCashflow.semanticDescription.contains("Income minus outflows"))
    }

    @Test("Heatmap strongest signals identify largest spend days")
    func heatmapStrongestSignalsIdentifyLargestSpendDays() {
        let signals = SpendingHeatmap.strongestSignals(
            from: [
                SpendingHeatmapDay(date: "2026-01-01", value: 20, transactionCount: 1),
                SpendingHeatmapDay(date: "2026-01-02", value: 150, transactionCount: 3),
                SpendingHeatmapDay(date: "2026-01-03", value: 90, transactionCount: 2),
                SpendingHeatmapDay(date: "2026-01-04", value: 0, transactionCount: 0),
            ],
            mode: .spending
        )

        #expect(signals.map { $0.day.date } == ["2026-01-02", "2026-01-03"])
        #expect(signals.first?.label == "Highest spend")
        #expect(signals.first?.accessibilitySummary.contains("Highest spend was") == true)
        #expect(signals.first?.accessibilitySummary.contains("3 transactions") == true)
    }

    @Test("Net cashflow strongest signals rank income and outflows by magnitude")
    func netCashflowStrongestSignalsRankIncomeAndOutflowsByMagnitude() {
        let signals = SpendingHeatmap.strongestSignals(
            from: [
                SpendingHeatmapDay(date: "2026-01-01", value: 120, transactionCount: 1),
                SpendingHeatmapDay(date: "2026-01-02", value: -300, transactionCount: 2),
                SpendingHeatmapDay(date: "2026-01-03", value: 250, transactionCount: 4),
            ],
            mode: .netCashflow
        )

        #expect(signals.map { $0.day.date } == ["2026-01-02", "2026-01-03"])
        #expect(signals.first?.label == "Strongest income")
        #expect(signals.last?.label == "Next strongest outflow")
        #expect(signals.first?.accessibilitySummary.contains("income") == true)
        #expect(signals.last?.accessibilitySummary.contains("outflow") == true)
    }

    @Test("Net cashflow strongest signals preserve both directions when available")
    func netCashflowStrongestSignalsPreserveBothDirectionsWhenAvailable() {
        let signals = SpendingHeatmap.strongestSignals(
            from: [
                SpendingHeatmapDay(date: "2026-01-01", value: -500, transactionCount: 1),
                SpendingHeatmapDay(date: "2026-01-02", value: -400, transactionCount: 1),
                SpendingHeatmapDay(date: "2026-01-03", value: 75, transactionCount: 2),
            ],
            mode: .netCashflow
        )

        #expect(signals.map { $0.day.date } == ["2026-01-01", "2026-01-03"])
        #expect(signals.first?.label == "Strongest income")
        #expect(signals.last?.label == "Next strongest outflow")
    }

    @Test("Heatmap empty copy distinguishes missing data from filtered-zero spend")
    func heatmapEmptyCopyDistinguishesMissingDataFromFilteredZeroSpend() {
        let missing = SpendingHeatmap.emptyPresentation(transactionCount: 0, mode: .spending)
        let filtered = SpendingHeatmap.emptyPresentation(transactionCount: 3, mode: .spending)

        #expect(missing.title == "No Heatmap Data")
        #expect(missing.description.contains("after syncing transactions"))
        #expect(filtered.title == "No Spending in This View")
        #expect(filtered.description.contains("Transactions exist"))
        #expect(filtered.description.contains("filters"))
    }

    @Test("Heatmap empty copy names filtered-zero cashflow separately")
    func heatmapEmptyCopyNamesFilteredZeroCashflowSeparately() {
        let filtered = SpendingHeatmap.emptyPresentation(transactionCount: 2, mode: .netCashflow)

        #expect(filtered.title == "No Cashflow in This View")
        #expect(filtered.description.contains("net cashflow"))
        #expect(filtered.description.contains("transfers are excluded"))
    }

    @Test("Heatmap cell intensity clamps and ignores empty days")
    func heatmapCellIntensityClampsAndIgnoresEmptyDays() {
        #expect(SpendingHeatmap.cellIntensity(for: SpendingHeatmapDay(date: "2026-01-01", value: 50, transactionCount: 1), peakValue: 200) == 0.25)
        #expect(SpendingHeatmap.cellIntensity(for: SpendingHeatmapDay(date: "2026-01-02", value: -75, transactionCount: 2), peakValue: 150) == 0.5)
        #expect(SpendingHeatmap.cellIntensity(for: SpendingHeatmapDay(date: "2026-01-03", value: 300, transactionCount: 1), peakValue: 100) == 1)
        #expect(SpendingHeatmap.cellIntensity(for: SpendingHeatmapDay(date: "2026-01-04", value: 90, transactionCount: 0), peakValue: 100) == 0)
        #expect(SpendingHeatmap.cellIntensity(for: SpendingHeatmapDay(date: "2026-01-05", value: 90, transactionCount: 1), peakValue: 0) == 0)
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
        #expect(state.title == "No linked item returned")
        #expect(state.detail == "PlaidBar cannot see a linked item yet. Finish Plaid Link in the browser, then check again.")
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
        #expect(readiness.primaryActionTitle == "Connect Bank")
        #expect(readiness.primaryActionIconName == "plus.circle")
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
        #expect(readiness.secondaryActions.isEmpty)
    }

    @Test("Dashboard status readiness blocks on missing local server auth")
    func dashboardStatusReadinessBlocksOnMissingLocalServerAuth() {
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
            errorMessage: "PlaidBar server auth token is unavailable"
        )

        #expect(readiness.level == .blocked)
        #expect(readiness.title == "Local server auth missing")
        #expect(readiness.detail.contains("auth token"))
        #expect(readiness.primaryAction == .openSettings)
        #expect(readiness.secondaryActions.isEmpty)
    }

    @Test("Dashboard status readiness blocks on rejected local server auth")
    func dashboardStatusReadinessBlocksOnRejectedLocalServerAuth() {
        let readiness = DashboardStatusReadiness.evaluate(
            isDemoMode: false,
            serverConnected: true,
            credentialsConfigured: nil,
            linkedItemCount: 0,
            accountCount: 0,
            syncedItemCount: 0,
            needsLoginItemCount: 0,
            erroredItemCount: 0,
            isSyncStale: true,
            lastSyncRelative: nil,
            errorMessage: "PlaidBar server returned 401: unauthorized"
        )

        #expect(readiness.level == .blocked)
        #expect(readiness.title == "Local server auth rejected")
        #expect(readiness.detail.contains("rejected"))
        #expect(readiness.primaryAction == .openSettings)
        #expect(readiness.secondaryActions.isEmpty)
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
        #expect(readiness.primaryActionTitle == "Connect Bank")
    }

    @Test("Server connection presentation labels local auth failures")
    func serverConnectionPresentationLabelsLocalAuthFailures() {
        let missing = ServerConnectionPresentation.evaluate(
            isDemoMode: false,
            isLoading: false,
            serverConnected: false,
            errorMessage: "PlaidBar server auth token is unavailable"
        )
        let rejected = ServerConnectionPresentation.evaluate(
            isDemoMode: false,
            isLoading: false,
            serverConnected: true,
            errorMessage: "PlaidBar server returned 403: forbidden"
        )

        #expect(missing.issue == .localAuthMissing)
        #expect(missing.statusText == "Auth missing")
        #expect(missing.diagnosticsSummary == "Local server auth missing")
        #expect(missing.attentionText == "Auth")
        #expect(rejected.issue == .localAuthRejected)
        #expect(rejected.statusText == "Auth rejected")
        #expect(rejected.diagnosticsSummary == "Local server auth rejected")
        #expect(rejected.attentionText == "Auth")
    }

    @Test("Server connection presentation distinguishes offline and generic errors")
    func serverConnectionPresentationDistinguishesOfflineAndGenericErrors() {
        let offline = ServerConnectionPresentation.evaluate(
            isDemoMode: false,
            isLoading: false,
            serverConnected: false,
            errorMessage: nil
        )
        let genericError = ServerConnectionPresentation.evaluate(
            isDemoMode: false,
            isLoading: false,
            serverConnected: true,
            errorMessage: "PlaidBar server returned 500: internal server error"
        )

        #expect(offline.issue == .offline)
        #expect(offline.statusText == "Offline")
        #expect(offline.diagnosticsSummary == "Server offline")
        #expect(offline.attentionText == "Offline")
        #expect(genericError.issue == .error)
        #expect(genericError.statusText == "Error")
        #expect(genericError.diagnosticsSummary == "Recent action failed")
        #expect(genericError.attentionText == "Error")
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
            errorMessage: "Plaid sync failed."
        )

        #expect(readiness.level == .warning)
        #expect(readiness.title == "Recent action failed")
        #expect(readiness.detail.contains("Plaid sync failed"))
        #expect(readiness.primaryAction == .refresh)
        #expect(readiness.secondaryActions.isEmpty)
    }

    @Test("User-facing error detail redacts Plaid identifiers and tokens")
    func userFacingErrorDetailRedactsPlaidIdentifiersAndTokens() {
        let tokenKey = "access" + "_token"
        let tokenValue = "access" + "-sandbox-secretvalue"
        let publicTokenValue = "public" + "-sandbox-publicvalue"
        let detail = UserFacingError.sanitizedDetail(
            from: "Plaid failed for item_id=item_123456789abcdef account_id=account_abcdef123456 \(tokenKey)=\(tokenValue) bare=\(publicTokenValue) Authorization: Bearer local-token-1234567890"
        )

        #expect(detail?.contains("item_123456789abcdef") == false)
        #expect(detail?.contains("account_abcdef123456") == false)
        #expect(detail?.contains(tokenValue) == false)
        #expect(detail?.contains(publicTokenValue) == false)
        #expect(detail?.contains("local-token-1234567890") == false)
        #expect(detail?.contains("Authorization: Bearer [redacted]") == true)
        #expect(detail?.contains("[redacted") == true)
    }

    @Test("User-facing error detail removes stack traces and truncates bodies")
    func userFacingErrorDetailRemovesStackTracesAndTruncatesBodies() {
        let detail = UserFacingError.sanitizedDetail(
            from: "Plaid sync failed. Stack trace: Sources/PlaidBarServer/PlaidClient.swift:42 \(String(repeating: "payload ", count: 80))",
            maxLength: 80
        )

        #expect(detail == "Plaid sync failed.")
        #expect(detail?.contains("PlaidClient.swift") == false)

        let longDetail = UserFacingError.sanitizedDetail(
            from: String(repeating: "server body ", count: 40),
            maxLength: 80
        )

        #expect(longDetail?.count == 83)
        #expect(longDetail?.hasSuffix("...") == true)
    }

    @Test("First run completion sanitizes blocking server errors")
    func firstRunCompletionSanitizesBlockingServerErrors() {
        let tokenKey = "access" + "_token"
        let tokenValue = "access" + "-sandbox-secretvalue"
        let state = FirstRunCompletionState.evaluate(
            isDemoMode: false,
            serverConnected: true,
            linkedItemCount: 0,
            accountCount: 0,
            transactionCount: 0,
            syncedItemCount: 0,
            errorMessage: "PlaidBar server returned 500: {\"\(tokenKey)\":\"\(tokenValue)\",\"item_id\":\"item_123456789abcdef\"}"
        )

        #expect(state.step == .blocked)
        #expect(state.detail.contains(tokenValue) == false)
        #expect(state.detail.contains("item_123456789abcdef") == false)
        #expect(state.detail.contains("[redacted") == true)
    }

    @Test("Secondary unavailable state sanitizes recent action failures")
    func secondaryUnavailableStateSanitizesRecentActionFailures() {
        let state = SecondaryContentUnavailableState.transactions(
            isDemoMode: false,
            serverConnected: true,
            linkedItemCount: 0,
            accountCount: 0,
            syncedItemCount: 0,
            transactionCount: 0,
            hasSearchText: false,
            hasActiveFilters: false,
            errorMessage: "Sync failed for transaction_abcdef1234567890 at /private/tmp/PlaidClient.swift:12"
        )

        #expect(state.title == "Recent action failed")
        #expect(state.detail.contains("transaction_abcdef1234567890") == false)
        #expect(state.detail.contains("/private/tmp") == false)
    }

    @Test("Dashboard status readiness identifies server mode mismatch")
    func dashboardStatusReadinessIdentifiesServerModeMismatch() {
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
            errorMessage: "Server is running in production, not sandbox. Restart with ./Scripts/run.sh --sandbox."
        )

        #expect(readiness.level == .blocked)
        #expect(readiness.title == "Server mode mismatch")
        #expect(readiness.primaryAction == .checkServer)
        #expect(readiness.primaryActionTitle == "Check Server")
        #expect(readiness.secondaryActions.isEmpty)
    }

    @Test("Notification permission presentation gives denied state one settings action")
    func notificationPermissionPresentationDeniedAction() {
        let presentation = NotificationPermissionPresentation.evaluate(kind: .denied)

        #expect(presentation.label == "Denied")
        #expect(presentation.recoveryAction == .openSystemSettings)
        #expect(presentation.recoveryActionTitle == "Open System Settings")
        #expect(presentation.recoveryActionIconName == "gearshape")
        #expect(presentation.isRecoveryActionInteractive)
        #expect(presentation.isNotificationToggleDisabled)
        #expect(presentation.shouldDisableNotifications)
    }

    @Test("Notification permission presentation requests permission before first use")
    func notificationPermissionPresentationNotDeterminedAction() {
        let presentation = NotificationPermissionPresentation.evaluate(kind: .notDetermined)

        #expect(presentation.label == "Not requested")
        #expect(presentation.recoveryAction == .requestPermission)
        #expect(presentation.recoveryActionTitle == "Request Permission")
        #expect(!presentation.isNotificationToggleDisabled)
        #expect(presentation.shouldDisableNotifications)
    }

    @Test("Notification permission presentation handles unsupported launches")
    func notificationPermissionPresentationUnsupportedAction() {
        let presentation = NotificationPermissionPresentation.evaluate(kind: .unsupported)

        #expect(presentation.label == "Unavailable")
        #expect(presentation.recoveryAction == .runBundledApp)
        #expect(presentation.recoveryActionTitle == "Run App Bundle")
        #expect(!presentation.isRecoveryActionInteractive)
        #expect(presentation.isNotificationToggleDisabled)
        #expect(presentation.shouldDisableNotifications)
    }

    @Test("Dashboard status readiness converges notification permission recovery")
    func dashboardStatusReadinessSurfacesNotificationPermissionRecovery() {
        let readiness = DashboardStatusReadiness.evaluate(
            isDemoMode: false,
            serverConnected: true,
            credentialsConfigured: true,
            linkedItemCount: 1,
            accountCount: 1,
            syncedItemCount: 1,
            needsLoginItemCount: 0,
            erroredItemCount: 0,
            isSyncStale: false,
            lastSyncRelative: "just now",
            errorMessage: nil,
            notificationsEnabled: true,
            notificationPermission: NotificationPermissionPresentation.evaluate(kind: .denied)
        )

        #expect(readiness.level == .warning)
        #expect(readiness.title == "Notifications blocked")
        #expect(readiness.primaryAction == .openNotificationSettings)
        #expect(readiness.primaryActionTitle == "Open System Settings")
        #expect(readiness.secondaryActions == [.openSettings])
    }

    @Test("Dashboard account filters include only matching account kinds")
    func dashboardAccountFiltersMatchAccountKinds() {
        let checking = AccountDTO(id: "checking", itemId: "item_cash", name: "Checking", type: .depository, subtype: "checking", balances: BalanceDTO())
        let savings = AccountDTO(id: "savings", itemId: "item_cash", name: "Savings", type: .depository, subtype: "savings", balances: BalanceDTO())
        let credit = AccountDTO(id: "credit", itemId: "item_card", name: "Card", type: .credit, balances: BalanceDTO())
        let loan = AccountDTO(id: "loan", itemId: "item_loan", name: "Loan", type: .loan, balances: BalanceDTO())

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
        let healthy = AccountDTO(id: "checking", itemId: "item_cash", name: "Checking", type: .depository, balances: BalanceDTO())
        let degraded = AccountDTO(id: "card", itemId: "item_card", name: "Card", type: .credit, balances: BalanceDTO())

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
            degradedItemCount: 1,
            degradedItemRecoveryTitle: "Reconnect Chase",
            degradedItemRecoveryDetail: "Plaid requires a fresh Chase login before account rows can be recovered."
        )

        #expect(emptyState.title == "1 item needs attention")
        #expect(emptyState.detail == "Plaid requires a fresh Chase login before account rows can be recovered.")
        #expect(emptyState.iconName == "exclamationmark.triangle.fill")
        #expect(emptyState.tone == .warning)
        #expect(!emptyState.showsAddAccount)
        #expect(emptyState.action == .reconnect)
        #expect(emptyState.actionTitle == "Reconnect Chase")
        #expect(emptyState.actionIconName == "link.badge.plus")
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
            credentialsConfigured: false,
            linkedItemCount: 1,
            accountCount: 0,
            degradedItemCount: 1
        )

        #expect(emptyState.title == "Server offline")
        #expect(emptyState.action == .checkServer)
        #expect(emptyState.actionTitle == "Check Server")
        #expect(emptyState.actionIconName == "server.rack")
    }

    @Test("Dashboard account empty state distinguishes missing credentials before no linked bank")
    func dashboardAccountEmptyStateCredentialsMissingBeforeLinkPrompt() {
        let emptyState = DashboardAccountEmptyState.evaluate(
            filter: .all,
            isDemoMode: false,
            serverConnected: true,
            credentialsConfigured: false,
            linkedItemCount: 0,
            accountCount: 0,
            degradedItemCount: 0
        )

        #expect(emptyState.title == "Plaid credentials missing")
        #expect(emptyState.detail.contains("local server environment"))
        #expect(emptyState.tone == .warning)
        #expect(!emptyState.showsAddAccount)
        #expect(emptyState.action == .refresh)
        #expect(emptyState.actionTitle == "Check Credentials")
        #expect(emptyState.actionIconName == "key")
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

    @Test("Secondary transaction empty state clears filters before recovery errors")
    func secondaryTransactionEmptyStateClearsFiltersFirst() {
        let state = SecondaryContentUnavailableState.transactions(
            isDemoMode: false,
            serverConnected: true,
            linkedItemCount: 1,
            accountCount: 2,
            syncedItemCount: 1,
            transactionCount: 12,
            hasSearchText: true,
            hasActiveFilters: false,
            errorMessage: "Refresh failed"
        )

        #expect(state.title == "No matching transactions")
        #expect(state.action == .clearFilters)
        #expect(state.actionTitle == "Clear Filters")
    }

    @Test("Secondary transaction empty state does not blame filters before history exists")
    func secondaryTransactionEmptyStateNeedsHistoryBeforeFilteredZero() {
        let state = SecondaryContentUnavailableState.transactions(
            isDemoMode: false,
            serverConnected: true,
            linkedItemCount: 1,
            accountCount: 2,
            syncedItemCount: 0,
            transactionCount: 0,
            hasSearchText: true,
            hasActiveFilters: true,
            errorMessage: nil
        )

        #expect(state.title == "First sync needed")
        #expect(state.action == .syncTransactions)
        #expect(state.actionTitle == "Sync Transactions")
    }

    @Test("Secondary accounts empty state distinguishes offline linked and unloaded data")
    func secondaryAccountsEmptyStateDistinguishesRecovery() {
        let offline = SecondaryContentUnavailableState.accounts(
            isDemoMode: false,
            serverConnected: false,
            linkedItemCount: 1
        )
        let unlinked = SecondaryContentUnavailableState.accounts(
            isDemoMode: false,
            serverConnected: true,
            linkedItemCount: 0
        )
        let unloaded = SecondaryContentUnavailableState.accounts(
            isDemoMode: false,
            serverConnected: true,
            linkedItemCount: 1
        )

        #expect(offline.title == "Server offline")
        #expect(offline.action == .checkServer)
        #expect(unlinked.title == "No bank linked")
        #expect(unlinked.action == .addAccount)
        #expect(unloaded.title == "Accounts not loaded")
        #expect(unloaded.action == .refreshAccounts)
    }

    @Test("Secondary credit empty state points credit gaps at card setup")
    func secondaryCreditEmptyStateDistinguishesCreditGap() {
        let noAccounts = SecondaryContentUnavailableState.credit(
            isDemoMode: false,
            serverConnected: true,
            linkedItemCount: 1,
            accountCount: 0
        )
        let noCredit = SecondaryContentUnavailableState.credit(
            isDemoMode: false,
            serverConnected: true,
            linkedItemCount: 1,
            accountCount: 2
        )

        #expect(noAccounts.title == "Accounts not loaded")
        #expect(noAccounts.action == .refreshAccounts)
        #expect(noCredit.title == "No credit card linked")
        #expect(noCredit.action == .addAccount)
        #expect(noCredit.actionTitle == "Link Credit Card")
    }

    @Test("Secondary transaction empty state keeps recent error ahead of missing history")
    func secondaryTransactionEmptyStateRecentErrorPriority() {
        let state = SecondaryContentUnavailableState.transactions(
            isDemoMode: false,
            serverConnected: true,
            linkedItemCount: 1,
            accountCount: 2,
            syncedItemCount: 0,
            transactionCount: 0,
            hasSearchText: false,
            hasActiveFilters: false,
            errorMessage: "Plaid sync failed"
        )

        #expect(state.title == "Recent action failed")
        #expect(state.detail == "Plaid sync failed")
        #expect(state.action == .refresh)
    }

    @Test("Secondary spending empty state points offline users at server check")
    func secondarySpendingEmptyStateServerOffline() {
        let state = SecondaryContentUnavailableState.spendingActivity(
            isDemoMode: false,
            serverConnected: false,
            linkedItemCount: 1,
            accountCount: 2,
            syncedItemCount: 1,
            transactionCount: 0,
            errorMessage: nil
        )

        #expect(state.title == "Server offline")
        #expect(state.action == .checkServer)
        #expect(state.actionTitle == "Check Connection")
    }

    @Test("Secondary spending period empty state widens before refresh")
    func secondarySpendingPeriodEmptyStateWidening() {
        let week = SecondaryContentUnavailableState.spendingPeriod(
            periodLabel: "Week",
            canShowWiderPeriod: true
        )
        let widest = SecondaryContentUnavailableState.spendingPeriod(
            periodLabel: "90D",
            canShowWiderPeriod: false
        )

        #expect(week.action == .showWiderPeriod)
        #expect(week.actionTitle == "Show 90 Days")
        #expect(widest.action == .refresh)
        #expect(widest.actionTitle == "Refresh")
    }

    @Test("Secondary recurring empty state explains minimum synced history")
    func secondaryRecurringEmptyStateNeedsHistory() {
        let noTransactions = SecondaryContentUnavailableState.recurring(
            isDemoMode: false,
            serverConnected: true,
            linkedItemCount: 1,
            accountCount: 2,
            syncedItemCount: 1,
            transactionCount: 0,
            errorMessage: nil
        )
        let noPattern = SecondaryContentUnavailableState.recurring(
            isDemoMode: false,
            serverConnected: true,
            linkedItemCount: 1,
            accountCount: 2,
            syncedItemCount: 1,
            transactionCount: 20,
            errorMessage: nil
        )

        #expect(noTransactions.title == "No synced transactions")
        #expect(noTransactions.action == .syncTransactions)
        #expect(noPattern.title == "No recurring charges found")
        #expect(noPattern.detail.contains("2 months"))
        #expect(noPattern.actionTitle == "Sync Latest Transactions")
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
        #expect(readiness.title == "1 item needs attention")
        #expect(readiness.secondaryActions.isEmpty)
    }

    @Test("Dashboard status readiness pluralizes multiple item errors")
    func dashboardStatusReadinessPluralizesMultipleItemErrors() {
        let readiness = DashboardStatusReadiness.evaluate(
            isDemoMode: false,
            serverConnected: true,
            credentialsConfigured: true,
            linkedItemCount: 3,
            accountCount: 5,
            syncedItemCount: 3,
            needsLoginItemCount: 0,
            erroredItemCount: 2,
            isSyncStale: false,
            lastSyncRelative: "2m ago",
            errorMessage: nil
        )

        #expect(readiness.title == "2 items need attention")
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
        #expect(readiness.title == "1 item needs login")
    }

    @Test("Dashboard status readiness pluralizes multiple login recovery items")
    func dashboardStatusReadinessPluralizesMultipleLoginRecoveryItems() {
        let readiness = DashboardStatusReadiness.evaluate(
            isDemoMode: false,
            serverConnected: true,
            credentialsConfigured: true,
            linkedItemCount: 3,
            accountCount: 5,
            syncedItemCount: 3,
            needsLoginItemCount: 2,
            erroredItemCount: 0,
            isSyncStale: false,
            lastSyncRelative: "2m ago",
            errorMessage: nil
        )

        #expect(readiness.title == "2 items need login")
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
        #expect(readiness.title == "1 item needs login")
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
        #expect(readiness.detail == "1 of 2 linked items have completed transaction sync. Refresh to finish the remaining item.")
        #expect(readiness.primaryActionTitle == "Finish Sync")
        #expect(readiness.primaryActionIconName == "arrow.clockwise")
        #expect(readiness.secondaryActions.isEmpty)
    }

    @Test("Dashboard status readiness distinguishes first sync not started")
    func dashboardStatusReadinessDetectsFirstSyncNotStarted() {
        let readiness = DashboardStatusReadiness.evaluate(
            isDemoMode: false,
            serverConnected: true,
            credentialsConfigured: true,
            linkedItemCount: 2,
            accountCount: 4,
            syncedItemCount: 0,
            needsLoginItemCount: 0,
            erroredItemCount: 0,
            isSyncStale: false,
            lastSyncRelative: nil,
            errorMessage: nil
        )

        #expect(readiness.level == .warning)
        #expect(readiness.primaryAction == .refresh)
        #expect(readiness.title == "First sync needed")
        #expect(readiness.detail == "Accounts are loaded, but no linked item has completed transaction sync yet. Refresh to run the first sync.")
        #expect(readiness.primaryActionTitle == "Run First Sync")
        #expect(readiness.secondaryActions.isEmpty)
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
        #expect(readiness.primaryActionTitle == "Refresh Now")
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
        #expect(readiness.primaryActionTitle == "Refresh Data")
        #expect(readiness.secondaryActions.contains(.addAccount))
    }

    @Test("Item recovery target prioritizes errored items")
    func itemRecoveryTargetPrioritizesErroredItems() {
        let statuses = [
            ItemStatus(id: "login", institutionName: "Chase", status: .loginRequired),
            ItemStatus(id: "error", institutionName: "Amex", status: .error),
            ItemStatus(id: "connected", status: .connected),
        ]

        #expect(ItemRecoveryTarget.item(from: statuses)?.institutionName == "Amex")
        #expect(ItemRecoveryTarget.itemId(from: statuses) == "error")
        #expect(ItemRecoveryTarget.actionTitle(from: statuses) == "Reconnect Amex")
    }

    @Test("Item recovery target falls back to login-required items")
    func itemRecoveryTargetFallsBackToLoginRequiredItems() {
        let statuses = [
            ItemStatus(id: "connected", status: .connected),
            ItemStatus(id: "login", institutionName: "Chase", status: .loginRequired),
        ]

        #expect(ItemRecoveryTarget.item(from: statuses)?.institutionName == "Chase")
        #expect(ItemRecoveryTarget.itemId(from: statuses) == "login")
        #expect(ItemRecoveryTarget.actionTitle(from: statuses) == "Reconnect Chase")
    }

    @Test("Item recovery target uses generic title without institution")
    func itemRecoveryTargetUsesGenericTitleWithoutInstitution() {
        let statuses = [
            ItemStatus(id: "login", status: .loginRequired),
        ]

        #expect(ItemRecoveryTarget.actionTitle(from: statuses) == "Reconnect Item")
    }

    @Test("Item recovery target ignores healthy items")
    func itemRecoveryTargetIgnoresHealthyItems() {
        let statuses = [
            ItemStatus(id: "connected", status: .connected),
        ]

        #expect(ItemRecoveryTarget.item(from: statuses)?.id == nil)
        #expect(ItemRecoveryTarget.itemId(from: statuses) == nil)
        #expect(ItemRecoveryTarget.actionTitle(from: statuses) == nil)
    }

    // MARK: - Balance Trend Tests

    @Test("Balance trend reports an upward delta with honest span")
    func balanceTrendReportsUpwardDelta() throws {
        let calendar = Calendar.current
        let now = try #require(Formatters.parseTransactionDate("2026-06-10"))
        let history = (0 ..< 30).map { daysAgo in
            BalanceSnapshot(
                date: calendar.date(byAdding: .day, value: -daysAgo, to: now)!,
                balance: 17_000 - Double(daysAgo) * 40
            )
        }

        let trend = try #require(BalanceTrend.evaluate(history: history, now: now, calendar: calendar))

        #expect(trend.direction == .up)
        #expect(abs(trend.delta - 1_160) < 0.01)
        #expect(trend.spanDays == 29)
        #expect(trend.spanText == "29D")
        #expect(trend.deltaText.hasPrefix("+$"))
        #expect(trend.accessibilitySummary.contains("up"))
        #expect(trend.points.count == 30)
        #expect(trend.points.map(\.date) == trend.points.map(\.date).sorted())
    }

    @Test("Balance trend reports downward and flat directions")
    func balanceTrendReportsDownwardAndFlat() throws {
        let calendar = Calendar.current
        let now = try #require(Formatters.parseTransactionDate("2026-06-10"))
        let yesterday = try #require(calendar.date(byAdding: .day, value: -1, to: now))

        let down = try #require(BalanceTrend.evaluate(
            history: [
                BalanceSnapshot(date: yesterday, balance: 10_000),
                BalanceSnapshot(date: now, balance: 9_400),
            ],
            now: now,
            calendar: calendar
        ))
        #expect(down.direction == .down)
        #expect(down.deltaText.hasPrefix("-$"))
        #expect(down.accessibilitySummary.contains("down"))

        let flat = try #require(BalanceTrend.evaluate(
            history: [
                BalanceSnapshot(date: yesterday, balance: 10_000),
                BalanceSnapshot(date: now, balance: 10_000),
            ],
            now: now,
            calendar: calendar
        ))
        #expect(flat.direction == .flat)
        #expect(flat.accessibilitySummary.contains("unchanged"))
    }

    @Test("Balance trend needs two points inside the window")
    func balanceTrendNeedsTwoPointsInWindow() throws {
        let calendar = Calendar.current
        let now = try #require(Formatters.parseTransactionDate("2026-06-10"))
        let ancient = try #require(calendar.date(byAdding: .day, value: -200, to: now))

        #expect(BalanceTrend.evaluate(history: [], now: now, calendar: calendar) == nil)
        #expect(BalanceTrend.evaluate(
            history: [BalanceSnapshot(date: now, balance: 5_000)],
            now: now,
            calendar: calendar
        ) == nil)
        // A second point outside the 90-day window does not count.
        #expect(BalanceTrend.evaluate(
            history: [
                BalanceSnapshot(date: ancient, balance: 4_000),
                BalanceSnapshot(date: now, balance: 5_000),
            ],
            now: now,
            calendar: calendar
        ) == nil)
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
        let sandboxDatabase = directory.appendingPathComponent("plaidbar-sandbox.sqlite")
        let databaseWAL = directory.appendingPathComponent("plaidbar.sqlite-wal")
        let transactionCache = directory.appendingPathComponent("transactions-sandbox-abc123.json")
        let pendingLinkSessions = directory.appendingPathComponent("pending-link-sessions.json")
        let pendingLinkSessionsBackup = directory.appendingPathComponent("pending-link-sessions.json.backup-20260604")
        let authToken = directory.appendingPathComponent("auth-token")
        let serverConfig = directory.appendingPathComponent("server.conf")
        let unrelatedFile = directory.appendingPathComponent("notes.txt")
        let unrelatedDirectory = directory.appendingPathComponent("exports", isDirectory: true)

        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        try "db".write(to: database, atomically: true, encoding: .utf8)
        try "sandbox".write(to: sandboxDatabase, atomically: true, encoding: .utf8)
        try "wal".write(to: databaseWAL, atomically: true, encoding: .utf8)
        try "cache".write(to: transactionCache, atomically: true, encoding: .utf8)
        try "sessions".write(to: pendingLinkSessions, atomically: true, encoding: .utf8)
        try "old sessions".write(to: pendingLinkSessionsBackup, atomically: true, encoding: .utf8)
        try "token".write(to: authToken, atomically: true, encoding: .utf8)
        try "PLAID_ENV=sandbox".write(to: serverConfig, atomically: true, encoding: .utf8)
        try "keep me".write(to: unrelatedFile, atomically: true, encoding: .utf8)
        try FileManager.default.createDirectory(at: unrelatedDirectory, withIntermediateDirectories: true)
        try FileManager.default.setAttributes([.posixPermissions: 0o644], ofItemAtPath: authToken.path)
        try FileManager.default.setAttributes([.posixPermissions: 0o644], ofItemAtPath: serverConfig.path)
        defer { try? FileManager.default.removeItem(at: root) }

        var didResetKeychainTokens = false
        let result = try LocalDataStore.resetLocalData(at: directory) {
            didResetKeychainTokens = true
        }

        #expect(result.directoryPath == directory.path)
        #expect(result.removedEntries == [
            "pending-link-sessions.json",
            "pending-link-sessions.json.backup-20260604",
            "plaidbar-sandbox.sqlite",
            "plaidbar.sqlite",
            "plaidbar.sqlite-wal",
            "transactions-sandbox-abc123.json",
        ])
        #expect(result.preservedEntries == ["auth-token", "exports", "notes.txt", "server.conf"])
        #expect(result.keychainTokensCleared)
        #expect(didResetKeychainTokens)

        var isDirectory: ObjCBool = false
        #expect(FileManager.default.fileExists(atPath: directory.path, isDirectory: &isDirectory))
        #expect(isDirectory.boolValue)
        #expect(try FileManager.default.contentsOfDirectory(atPath: directory.path).sorted() == ["auth-token", "exports", "notes.txt", "server.conf"])
        #expect(try String(contentsOf: authToken, encoding: .utf8) == "token")
        #expect(try String(contentsOf: serverConfig, encoding: .utf8) == "PLAID_ENV=sandbox")
        #expect(try String(contentsOf: unrelatedFile, encoding: .utf8) == "keep me")
        #expect(FileManager.default.fileExists(atPath: unrelatedDirectory.path, isDirectory: &isDirectory))
        #expect(isDirectory.boolValue)
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
        #expect(result.preservedEntries == [])
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

    @Test("Local AI insight windows use deterministic current and prior ranges")
    func localAIInsightWindowsUseDeterministicRanges() throws {
        let anchor = try #require(Formatters.parseTransactionDate("2026-03-15"))

        let last7 = LocalAIInsightInputBuilder.dateRanges(for: .last7days, anchorDate: anchor)
        #expect(last7.current.startDate == "2026-03-09")
        #expect(last7.current.endDate == "2026-03-15")
        #expect(last7.prior?.startDate == "2026-03-02")
        #expect(last7.prior?.endDate == "2026-03-08")

        let lastMonth = LocalAIInsightInputBuilder.dateRanges(for: .lastMonth, anchorDate: anchor)
        #expect(lastMonth.current.startDate == "2026-02-14")
        #expect(lastMonth.current.endDate == "2026-03-15")
        #expect(lastMonth.prior?.startDate == "2026-01-15")
        #expect(lastMonth.prior?.endDate == "2026-02-13")
    }

    @Test("Local AI YoY window uses prior-year comparison range")
    func localAIYearOverYearRange() throws {
        let anchor = try #require(Formatters.parseTransactionDate("2026-03-15"))

        let ranges = LocalAIInsightInputBuilder.dateRanges(for: .yearOverYear, anchorDate: anchor)

        #expect(ranges.current.startDate == "2025-03-16")
        #expect(ranges.current.endDate == "2026-03-15")
        #expect(ranges.prior?.startDate == "2024-03-16")
        #expect(ranges.prior?.endDate == "2025-03-15")
    }

    @Test("Local AI summary input splits income, expenses, and transfers")
    func localAISummarySplitsIncomeExpensesAndTransfers() throws {
        let anchor = try #require(Formatters.parseTransactionDate("2026-03-15"))
        let transactions = [
            TransactionDTO(id: "expense", accountId: "checking", amount: 100, date: "2026-03-15", name: "Groceries", category: .foodAndDrink),
            TransactionDTO(id: "income", accountId: "checking", amount: -1000, date: "2026-03-14", name: "Payroll", category: .income),
            TransactionDTO(id: "transfer-out", accountId: "checking", amount: 250, date: "2026-03-14", name: "Savings Transfer", category: .transferOut),
            TransactionDTO(id: "transfer-in", accountId: "checking", amount: -250, date: "2026-03-14", name: "Savings Transfer", category: .transfer),
            TransactionDTO(id: "old", accountId: "checking", amount: 75, date: "2026-03-01", name: "Old", category: .shopping),
        ]

        let input = LocalAIInsightInputBuilder.buildInput(
            window: .last7days,
            accounts: [],
            transactions: transactions,
            recurringTransactions: [],
            anchorDate: anchor
        )

        #expect(input.current.transactionCount == 4)
        #expect(input.current.incomeTotal == 1000)
        #expect(input.current.expenseTotal == 100)
        #expect(input.current.netCashflow == 900)
        #expect(input.current.incomeTransactionIds == ["income"])
        #expect(input.current.expenseTransactionIds == ["expense"])
        #expect(Set(input.current.transferTransactionIds) == Set(["transfer-out", "transfer-in"]))
    }

    @Test("Local AI deterministic category suggestions preserve Plaid fallback evidence")
    func localAIDeterministicCategorySuggestionsPreservePlaidFallbackEvidence() throws {
        let anchor = try #require(Formatters.parseTransactionDate("2026-03-15"))
        let transaction = TransactionDTO(
            id: "amazon-miscoded",
            accountId: "checking",
            amount: 80,
            date: "2026-03-15",
            name: "AMAZON.COM",
            merchantName: "Amazon",
            category: .other
        )

        let input = LocalAIInsightInputBuilder.buildInput(
            window: .last7days,
            accounts: [],
            transactions: [transaction],
            recurringTransactions: [],
            anchorDate: anchor
        )

        let suggestion = try #require(input.categorySuggestions.first)
        #expect(suggestion.transactionId == "amazon-miscoded")
        #expect(suggestion.suggestedCategory == .shopping)
        #expect(suggestion.generatedBy == LocalAICategorySuggestionGenerator.generatedBy)
        #expect(suggestion.evidence.contains { $0.kind == .plaidCategory && $0.label == "Plaid category: Other" })
        #expect(input.current.categoryTotals.first?.category == .shopping)
    }

    @Test("Local AI deterministic transfer hints keep expenses auditable")
    func localAIDeterministicTransferHintsKeepExpensesAuditable() throws {
        let anchor = try #require(Formatters.parseTransactionDate("2026-03-15"))
        let transaction = TransactionDTO(
            id: "venmo-transfer",
            accountId: "checking",
            amount: 125,
            date: "2026-03-15",
            name: "VENMO TRANSFER",
            merchantName: "Venmo",
            category: .foodAndDrink
        )

        let input = LocalAIInsightInputBuilder.buildInput(
            window: .last7days,
            accounts: [],
            transactions: [transaction],
            recurringTransactions: [],
            anchorDate: anchor
        )

        #expect(input.categorySuggestions.first?.suggestedCategory == .transferOut)
        #expect(input.current.expenseTransactionIds.isEmpty)
        #expect(input.current.transferTransactionIds == ["venmo-transfer"])
    }

    @Test("Local AI transfer suggestions move rows out of expense totals")
    func localAITransferSuggestionsMoveRowsOutOfExpenseTotals() throws {
        let anchor = try #require(Formatters.parseTransactionDate("2026-03-15"))
        let transaction = TransactionDTO(
            id: "suggested-transfer",
            accountId: "checking",
            amount: 250,
            date: "2026-03-15",
            name: "Move to savings",
            category: .shopping
        )
        let suggestion = LocalAICategorySuggestion(
            transactionId: "suggested-transfer",
            suggestedCategory: .transferOut,
            confidence: 0.92,
            evidence: [
                LocalAIInsightEvidence(
                    kind: .transaction,
                    sourceId: "suggested-transfer",
                    label: "Move to savings",
                    transactionIds: ["suggested-transfer"]
                ),
            ]
        )

        let input = LocalAIInsightInputBuilder.buildInput(
            window: .last7days,
            accounts: [],
            transactions: [transaction],
            recurringTransactions: [],
            categorySuggestions: [suggestion],
            anchorDate: anchor
        )

        #expect(input.current.expenseTotal == 0)
        #expect(input.current.expenseTransactionIds == [])
        #expect(input.current.transferTransactionIds == ["suggested-transfer"])
        #expect(input.current.categoryTotals == [])
    }

    @Test("Local AI income suggestions move rows out of expense totals")
    func localAIIncomeSuggestionsMoveRowsOutOfExpenseTotals() throws {
        let anchor = try #require(Formatters.parseTransactionDate("2026-03-15"))
        let transaction = TransactionDTO(
            id: "suggested-income",
            accountId: "checking",
            amount: 125,
            date: "2026-03-15",
            name: "Refund credit",
            category: .shopping
        )
        let suggestion = LocalAICategorySuggestion(
            transactionId: "suggested-income",
            suggestedCategory: .income,
            confidence: 0.9,
            evidence: [
                LocalAIInsightEvidence(
                    kind: .transaction,
                    sourceId: "suggested-income",
                    label: "Refund credit",
                    transactionIds: ["suggested-income"]
                ),
            ]
        )

        let input = LocalAIInsightInputBuilder.buildInput(
            window: .last7days,
            accounts: [],
            transactions: [transaction],
            recurringTransactions: [],
            categorySuggestions: [suggestion],
            anchorDate: anchor
        )

        #expect(input.current.incomeTotal == 125)
        #expect(input.current.expenseTotal == 0)
        #expect(input.current.incomeTransactionIds == ["suggested-income"])
        #expect(input.current.expenseTransactionIds == [])
        #expect(input.current.categoryTotals == [])
    }

    @Test("Local AI builder preserves source transaction evidence")
    func localAIBuilderPreservesEvidence() throws {
        let anchor = try #require(Formatters.parseTransactionDate("2026-03-15"))
        let transactions = [
            TransactionDTO(id: "coffee", accountId: "checking", amount: 12, date: "2026-03-15", name: "CAFE", merchantName: "Cafe", category: .foodAndDrink),
            TransactionDTO(id: "market", accountId: "checking", amount: 88, date: "2026-03-14", name: "MARKET", merchantName: "Market", category: .foodAndDrink),
        ]

        let input = LocalAIInsightInputBuilder.buildInput(
            window: .last7days,
            accounts: [
                AccountDTO(id: "checking", itemId: "item", name: "Checking", type: .depository, balances: BalanceDTO(available: 1000)),
            ],
            transactions: transactions,
            recurringTransactions: [],
            anchorDate: anchor
        )

        let categoryTotal = try #require(input.current.categoryTotals.first)
        #expect(categoryTotal.category == .foodAndDrink)
        #expect(categoryTotal.transactionIds == ["market", "coffee"])
        #expect(categoryTotal.evidence.first?.transactionIds == ["market", "coffee"])
        #expect(input.current.topExpenses.map(\.transactionId) == ["market", "coffee"])
        #expect(input.current.topExpenses.first?.evidence.first?.sourceId == "market")
        #expect(input.evidence.contains { $0.transactionIds.contains("coffee") })
        #expect(input.accountSnapshot.accountIds == ["checking"])
    }

    @Test("Local AI category resolver overrides and falls back deterministically")
    func localAICategoryResolverOverridesAndFallsBack() {
        let plaidCategorized = TransactionDTO(id: "tx", accountId: "a", amount: 20, date: "2026-03-15", name: "Merchant", category: .foodAndDrink)
        let uncategorized = TransactionDTO(id: "uncat", accountId: "a", amount: 20, date: "2026-03-15", name: "Unknown")
        let evidence = [
            LocalAIInsightEvidence(kind: .transaction, sourceId: "tx", label: "Merchant", transactionIds: ["tx"]),
        ]

        let highConfidence = LocalAICategorySuggestion(
            transactionId: "tx",
            suggestedCategory: .shopping,
            confidence: 0.91,
            evidence: evidence
        )
        let lowConfidence = LocalAICategorySuggestion(
            transactionId: "tx",
            suggestedCategory: .shopping,
            confidence: 0.5,
            evidence: evidence
        )
        let accepted = LocalAICategorySuggestion(
            transactionId: "tx",
            suggestedCategory: .transportation,
            confidence: 0.4,
            status: .accepted,
            evidence: evidence
        )

        #expect(LocalAICategorizationResolver.resolve(transaction: plaidCategorized, suggestion: highConfidence).effectiveCategory == .shopping)
        #expect(LocalAICategorizationResolver.resolve(transaction: plaidCategorized, suggestion: highConfidence).source == .localAISuggestion)
        #expect(LocalAICategorizationResolver.resolve(transaction: plaidCategorized, suggestion: lowConfidence).effectiveCategory == .foodAndDrink)
        #expect(LocalAICategorizationResolver.resolve(transaction: plaidCategorized, suggestion: lowConfidence).source == .plaidCategory)
        #expect(LocalAICategorizationResolver.resolve(transaction: plaidCategorized, suggestion: accepted).effectiveCategory == .transportation)
        #expect(LocalAICategorizationResolver.resolve(transaction: uncategorized, suggestion: nil).effectiveCategory == .other)
        #expect(LocalAICategorizationResolver.resolve(transaction: uncategorized, suggestion: nil).source == .fallbackOther)
    }

    @Test("Local AI category overlays do not mutate raw TransactionDTO category")
    func localAICategoryOverlayPreservesRawTransactionRoundtrip() throws {
        let transaction = TransactionDTO(id: "raw", accountId: "checking", amount: 42, date: "2026-03-15", name: "RAW MERCHANT", category: .foodAndDrink)
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        let originalData = try encoder.encode(transaction)
        let suggestion = LocalAICategorySuggestion(
            transactionId: "raw",
            suggestedCategory: .shopping,
            confidence: 0.99,
            status: .accepted,
            evidence: [
                LocalAIInsightEvidence(kind: .transaction, sourceId: "raw", label: "RAW MERCHANT", transactionIds: ["raw"]),
            ]
        )

        let resolution = LocalAICategorizationResolver.resolve(
            transaction: transaction,
            suggestion: suggestion
        )
        let input = LocalAIInsightInputBuilder.buildInput(
            window: .last7days,
            accounts: [],
            transactions: [transaction],
            recurringTransactions: [],
            categorySuggestions: [suggestion],
            anchorDate: try #require(Formatters.parseTransactionDate("2026-03-15"))
        )
        let decoded = try JSONDecoder().decode(TransactionDTO.self, from: originalData)

        #expect(resolution.effectiveCategory == .shopping)
        #expect(transaction.category == .foodAndDrink)
        #expect(decoded.category == .foodAndDrink)
        #expect(input.current.categoryTotals.first?.category == .shopping)
        #expect(try encoder.encode(transaction) == originalData)
    }

    @Test("Account drill-in actions keep destructive remove explicit")
    func accountDrillInActionsExposeExplicitConfirmationCopy() {
        let actions = DashboardDrillInAction.accountDrillInActions

        #expect(actions == [.reconnect, .remove, .settings])
        #expect(DashboardDrillInAction.accountDrillInActions(isDemoMode: false) == [.reconnect, .remove, .settings])
        #expect(DashboardDrillInAction.accountDrillInActions(isDemoMode: true) == [.settings])
        #expect(DashboardDrillInAction.remove.title == "Remove Institution")
        #expect(DashboardDrillInAction.remove.iconName == "trash")
        #expect(DashboardDrillInAction.remove.accessibilityHint.localizedCaseInsensitiveContains("requires confirmation"))
        #expect(DashboardDrillInAction.remove.accessibilityHint.localizedCaseInsensitiveContains("disconnecting this Plaid institution"))
        #expect(DashboardDrillInAction.remove.accessibilityHint.localizedCaseInsensitiveContains("local PlaidBar data"))
        #expect(DashboardDrillInAction.settings.accessibilityHint.localizedCaseInsensitiveContains("settings"))
    }

    private func posixPermissions(at url: URL) throws -> Int {
        let attributes = try FileManager.default.attributesOfItem(atPath: url.path)
        return (attributes[.posixPermissions] as? NSNumber)?.intValue ?? -1
    }
}
