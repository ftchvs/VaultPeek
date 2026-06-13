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
                AccountDTO(id: "card-a", itemId: "item-a", name: "Card A", type: .credit, balances: BalanceDTO(current: -400, limit: 1_000)),
                AccountDTO(id: "card-b", itemId: "item-b", name: "Card B", type: .credit, balances: BalanceDTO(current: -200, limit: 1_000)),
            ],
            creditUtilizationThreshold: 25
        )

        #expect(presentation.creditUtilization?.usedCredit == 600)
        #expect(presentation.creditUtilization?.totalLimit == 2_000)
        #expect(presentation.creditUtilization?.percent == 30)
        #expect(presentation.creditUtilization?.statusLabel == "Warning")
        #expect(presentation.creditUtilization?.exceedsThreshold == true)
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
        creditUtilizationThreshold: Double = 30
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
