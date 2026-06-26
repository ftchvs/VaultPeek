import Testing
@testable import PlaidBarCore

@Suite("Wealth summary presentation")
struct WealthSummaryPresentationTests {
    private let now = Formatters.parseTransactionDate("2026-06-11")!

    @Test("Computes net worth, assets, debt, and active balance mix")
    func computesBalanceOverview() {
        let presentation = makePresentation(
            accounts: [
                AccountDTO(id: "checking", itemId: "item-a", name: "Checking", type: .depository, balances: BalanceDTO(current: 900)),
                AccountDTO(id: "brokerage", itemId: "item-a", name: "Brokerage", type: .investment, balances: BalanceDTO(current: 1_500)),
                AccountDTO(id: "card", itemId: "item-b", name: "Card", type: .credit, balances: BalanceDTO(current: -400, limit: 2_000)),
                AccountDTO(id: "loan", itemId: "item-c", name: "Loan", type: .loan, balances: BalanceDTO(current: -700)),
            ],
            linkedItemCount: 3,
            syncedItemCount: 3
        )

        #expect(presentation.accountCount == 4)
        #expect(presentation.netWorth == 1_300)
        #expect(presentation.totalAssets == 2_400)
        #expect(presentation.totalDebt == 1_100)
        #expect(presentation.balanceMix.segments.map(\.id) == ["cash", "investments", "credit", "loans"])
        #expect(presentation.balanceMix.segments.map(\.value) == [900, 1_500, 400, 700])
    }

    @Test("Computes 30 day cashflow and excludes transfers")
    func computesCashflowWindow() {
        let presentation = makePresentation(
            transactions: [
                expense("current-spend", amount: 80, date: "2026-06-10"),
                income("current-income", amount: 500, date: "2026-06-09"),
                expense("boundary-spend", amount: 20, date: "2026-05-13"),
                expense("previous-spend", amount: 40, date: "2026-05-12"),
                expense("transfer-out", amount: 900, date: "2026-06-10", category: .transferOut),
                income("transfer-in", amount: 900, date: "2026-06-10", category: .transfer),
            ]
        )

        #expect(presentation.cashflow.windowDays == 30)
        #expect(presentation.cashflow.spending == 100)
        #expect(presentation.cashflow.income == 500)
        #expect(presentation.cashflow.net == 400)
        #expect(presentation.cashflow.transactionCount == 3)
    }

    @Test("Computes credit utilization against the configured threshold")
    func computesCreditUtilization() {
        let presentation = makePresentation(
            accounts: [
                AccountDTO(id: "card-a", itemId: "item-a", name: "Card A", type: .credit, balances: BalanceDTO(current: -400, limit: 1_000, isoCurrencyCode: "USD")),
                AccountDTO(id: "card-b", itemId: "item-b", name: "Card B", type: .credit, balances: BalanceDTO(current: -200, limit: 1_000, isoCurrencyCode: "USD")),
            ],
            creditUtilizationThreshold: 25
        )

        // Two USD cards stay pooled WITHIN USD (single currency), so the ratio is
        // unchanged from the pre-AND-660 behavior — per-currency only changes
        // mixed-currency portfolios.
        #expect(presentation.creditUtilization?.usedCredit == 600)
        #expect(presentation.creditUtilization?.totalLimit == 2_000)
        #expect(presentation.creditUtilization?.percent == 30)
        #expect(presentation.creditUtilization?.statusLabel == "Warning")
        #expect(presentation.creditUtilization?.exceedsThreshold == true)
        #expect(presentation.creditUtilization?.currency == CurrencyCode("USD"))
        #expect(presentation.creditUtilization?.isMultiCurrency == false)
    }

    // AND-660 #3 (highest stakes): used credit and limits must NEVER pool across
    // currencies. A USD card at 10% utilization and a EUR card at 90% must report
    // the WORST single-currency ratio (90% / EUR), not a fabricated cross-currency
    // pooled number — and the threshold must still fire on the maxed EUR card.
    @Test("Credit utilization is per-currency: USD+EUR mix does not pool into one ratio (AND-660)")
    func creditUtilizationPerCurrency() {
        // USD: 1,000 used of 10,000 limit = 10%.
        // EUR: 900 used of 1,000 limit = 90%.
        // Pooling (the old bug) would give (1,900 / 11,000) ≈ 17.3% — UNDER a 30%
        // threshold, silently hiding the maxed EUR card. Per-currency must surface
        // the 90% EUR group and trip the threshold.
        let accounts = [
            AccountDTO(id: "usd-card", itemId: "item-a", name: "USD Card", type: .credit, balances: BalanceDTO(current: -1_000, limit: 10_000, isoCurrencyCode: "USD")),
            AccountDTO(id: "eur-card", itemId: "item-b", name: "EUR Card", type: .credit, balances: BalanceDTO(current: -900, limit: 1_000, isoCurrencyCode: "EUR")),
        ]
        let presentation = makePresentation(accounts: accounts, creditUtilizationThreshold: 30)

        let util = presentation.creditUtilization
        // Headline reports the worst currency group: EUR at 90%, NOT the ~17.3%
        // pooled ratio.
        #expect(util?.percent == 90)
        #expect(util?.currency == CurrencyCode("EUR"))
        #expect(util?.usedCredit == 900)
        #expect(util?.totalLimit == 1_000)
        #expect(util?.isMultiCurrency == true)
        // The maxed EUR card trips the threshold even though a pooled ratio would
        // have stayed under it.
        #expect(util?.exceedsThreshold == true)
        // Guard against regression to the pooled denominator/numerator.
        #expect(util?.totalLimit != 11_000)
        #expect(util?.usedCredit != 1_900)

        // The shared menu-bar/alert path (feeds AttentionQueue → notifications +
        // App Intents) must report the same worst-currency figure, NOT ~17.3%.
        #expect(MenuBarSummary.creditUtilization(from: accounts) == 90)

        // The per-currency groups expose BOTH currencies, each with its own
        // self-consistent used/limit (never cross-currency summed).
        let groups = MenuBarSummary.creditUtilizationByCurrency(from: accounts)
        #expect(groups.count == 2)
        #expect(groups.first?.currency == CurrencyCode("EUR")) // worst is first
        #expect(groups.first?.percent == 90)
        let usd = groups.first { $0.currency == CurrencyCode("USD") }
        #expect(usd?.percent == 10)
        #expect(usd?.usedCredit == 1_000)
        #expect(usd?.totalLimit == 10_000)
    }

    @Test("Per-currency utilization keeps a low foreign card from inflating a high domestic one")
    func creditUtilizationPerCurrencyDoesNotMaskGoodCard() {
        // USD: 9,000 used of 10,000 = 90% (the worst). EUR: 100 used of 5,000 = 2%.
        // Per-currency reports USD 90%; a naive pool would have been
        // (9,100 / 15,000) ≈ 60.7%, understating the maxed USD card.
        let presentation = makePresentation(
            accounts: [
                AccountDTO(id: "usd-card", itemId: "item-a", name: "USD Card", type: .credit, balances: BalanceDTO(current: -9_000, limit: 10_000, isoCurrencyCode: "USD")),
                AccountDTO(id: "eur-card", itemId: "item-b", name: "EUR Card", type: .credit, balances: BalanceDTO(current: -100, limit: 5_000, isoCurrencyCode: "EUR")),
            ],
            creditUtilizationThreshold: 30
        )
        #expect(presentation.creditUtilization?.percent == 90)
        #expect(presentation.creditUtilization?.currency == CurrencyCode("USD"))
        #expect(presentation.creditUtilization?.exceedsThreshold == true)
    }

    @Test("Surfaces an available net worth trend from local balance history")
    func surfacesAvailableNetWorthTrend() {
        let older = Calendar.current.date(byAdding: .day, value: -6, to: now)!
        let presentation = makePresentation(
            balanceHistory: [
                BalanceSnapshot(date: older, balance: 1_000),
                BalanceSnapshot(date: now, balance: 1_250),
            ]
        )

        guard case let .available(trend) = presentation.netWorthTrend else {
            Issue.record("Expected available trend")
            return
        }

        #expect(trend.delta == 250)
        #expect(trend.direction == .up)
        #expect(trend.spanDays == 6)
        #expect(trend.accessibilitySummary.contains("up $250.00"))
    }

    @Test("Surfaces insufficient history when local snapshots are unavailable")
    func surfacesInsufficientNetWorthHistory() {
        let presentation = makePresentation(balanceHistory: [])

        guard case let .insufficientHistory(pointCount, requiredPointCount) = presentation.netWorthTrend else {
            Issue.record("Expected insufficient trend history")
            return
        }

        #expect(pointCount == 0)
        #expect(requiredPointCount == 2)
        #expect(presentation.netWorthTrend.accessibilitySummary.contains("Needs 2 more local balance snapshots"))
    }

    @Test("Insufficient net worth trend counts only snapshots inside the trend window")
    func insufficientNetWorthTrendCountsOnlyWindowSnapshots() {
        let oldFirst = Calendar.current.date(byAdding: .day, value: -130, to: now)!
        let oldSecond = Calendar.current.date(byAdding: .day, value: -120, to: now)!
        let recent = Calendar.current.date(byAdding: .day, value: -3, to: now)!
        let presentation = makePresentation(
            balanceHistory: [
                BalanceSnapshot(date: oldFirst, balance: 900),
                BalanceSnapshot(date: oldSecond, balance: 950),
                BalanceSnapshot(date: recent, balance: 1_000),
            ]
        )

        guard case let .insufficientHistory(pointCount, requiredPointCount) = presentation.netWorthTrend else {
            Issue.record("Expected insufficient trend history")
            return
        }

        #expect(pointCount == 1)
        #expect(requiredPointCount == 2)
        #expect(presentation.netWorthTrend.accessibilitySummary.contains("Needs 1 more local balance snapshot"))
    }

    @Test("Net worth trend summary does not expose account or item identifiers")
    func netWorthTrendSummaryExcludesIdentifiers() {
        let older = Calendar.current.date(byAdding: .day, value: -2, to: now)!
        let presentation = makePresentation(
            accounts: [
                AccountDTO(
                    id: "accountSecretIdentifier",
                    itemId: "itemSecretIdentifier",
                    name: "Checking",
                    type: .depository,
                    balances: BalanceDTO(current: 1_250)
                ),
            ],
            balanceHistory: [
                BalanceSnapshot(date: older, balance: 1_000),
                BalanceSnapshot(date: now, balance: 1_250),
            ]
        )

        let summary = presentation.netWorthTrend.accessibilitySummary
        #expect(!summary.contains("accountSecretIdentifier"))
        #expect(!summary.contains("itemSecretIdentifier"))
    }

    @Test("Uses existing attention and sync status inputs")
    func derivesAttentionAndSyncHealthFromStatusInputs() {
        let presentation = makePresentation(
            accounts: [
                AccountDTO(id: "checking", itemId: "item-a", name: "Checking", type: .depository, balances: BalanceDTO(current: 100)),
            ],
            linkedItemCount: 1,
            syncedItemCount: 1,
            itemStatuses: [
                ItemStatus(id: "item-a", institutionName: "Example Bank", status: .loginRequired),
            ],
            isSyncStale: true,
            lastSyncRelative: "3 days ago",
            statusSyncText: "Stale 3 days ago"
        )

        #expect(presentation.attention.severity == .warning)
        #expect(presentation.attention.title == "Example Bank needs login")
        #expect(presentation.syncHealth.severity == .warning)
        #expect(presentation.syncHealth.title == "Example Bank needs login")
        #expect(presentation.syncHealth.statusText == "Stale 3 days ago")
        #expect(presentation.syncHealth.iconName == "exclamationmark.triangle.fill")
    }

    @Test("Demo mode renders as healthy local data")
    func demoModeRendersHealthy() {
        let presentation = makePresentation(
            isDemoMode: true,
            serverConnected: true,
            linkedItemCount: 2,
            syncedItemCount: 2,
            statusSyncText: "Synced now"
        )

        #expect(presentation.attention.severity == .healthy)
        #expect(presentation.attention.title == "Demo data ready")
        #expect(presentation.syncHealth.severity == .healthy)
        #expect(presentation.syncHealth.title == "Demo data ready")
        #expect(presentation.syncHealth.iconName == "play.circle.fill")
    }

    private func makePresentation(
        accounts: [AccountDTO] = [],
        transactions: [TransactionDTO] = [],
        isDemoMode: Bool = false,
        serverConnected: Bool = true,
        credentialsConfigured: Bool? = true,
        linkedItemCount: Int = 0,
        syncedItemCount: Int = 0,
        itemStatuses: [ItemStatus] = [],
        isSyncStale: Bool = false,
        lastSyncRelative: String? = "now",
        statusSyncText: String = "Synced now",
        errorMessage: String? = nil,
        creditUtilizationThreshold: Double = 30,
        balanceHistory: [BalanceSnapshot] = []
    ) -> WealthSummaryPresentation {
        WealthSummaryPresentation.evaluate(
            accounts: accounts,
            transactions: transactions,
            isDemoMode: isDemoMode,
            serverConnected: serverConnected,
            credentialsConfigured: credentialsConfigured,
            linkedItemCount: linkedItemCount,
            syncedItemCount: syncedItemCount,
            itemStatuses: itemStatuses,
            isSyncStale: isSyncStale,
            lastSyncRelative: lastSyncRelative,
            statusSyncText: statusSyncText,
            errorMessage: errorMessage,
            creditUtilizationThreshold: creditUtilizationThreshold,
            balanceHistory: balanceHistory,
            now: now
        )
    }

    private func expense(
        _ id: String,
        amount: Double,
        date: String,
        category: SpendingCategory? = nil
    ) -> TransactionDTO {
        TransactionDTO(
            id: id,
            accountId: "checking",
            amount: amount,
            date: date,
            name: id,
            category: category
        )
    }

    private func income(
        _ id: String,
        amount: Double,
        date: String,
        category: SpendingCategory? = .income
    ) -> TransactionDTO {
        TransactionDTO(
            id: id,
            accountId: "checking",
            amount: -amount,
            date: date,
            name: id,
            category: category
        )
    }
}
