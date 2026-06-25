import Foundation
import Testing
@testable import PlaidBarCore

@Suite("Dashboard drill-in surfaces and actions")
struct DashboardDrillInSurfaceTests {
    private func account(type: AccountType) -> AccountDTO {
        AccountDTO(id: "a", itemId: "i", name: "Acct", type: type, balances: BalanceDTO(current: 0))
    }

    // MARK: Surfaces

    @Test("Every surface exposes title, icon, and accessibility summary")
    func surfaceCopy() {
        for surface in DashboardDrillInSurface.allCases {
            #expect(!surface.title.isEmpty)
            #expect(!surface.iconName.isEmpty)
            #expect(!surface.accessibilitySummary.isEmpty)
        }
    }

    @Test("Credit surface is relevant only for credit and loan accounts")
    func creditRelevance() {
        #expect(DashboardDrillInSurface.credit.isRelevant(for: account(type: .credit)))
        #expect(DashboardDrillInSurface.credit.isRelevant(for: account(type: .loan)))
        #expect(!DashboardDrillInSurface.credit.isRelevant(for: account(type: .depository)))
        #expect(DashboardDrillInSurface.account.isRelevant(for: account(type: .depository)))
        #expect(DashboardDrillInSurface.activity.isRelevant(for: account(type: .investment)))
        #expect(DashboardDrillInSurface.status.isRelevant(for: account(type: .other)))
    }

    @Test("surfaces(for:) drops the credit surface for non-credit accounts")
    func surfacesFilter() {
        #expect(DashboardDrillInSurface.surfaces(for: account(type: .depository)) == [.account, .activity, .status])
        #expect(DashboardDrillInSurface.surfaces(for: account(type: .credit)) == [.account, .activity, .credit, .status])
    }

    // MARK: Actions

    @Test("Every action exposes title, icon, and hint")
    func actionCopy() {
        for action in DashboardDrillInAction.allCases {
            #expect(!action.title.isEmpty)
            #expect(!action.iconName.isEmpty)
            #expect(!action.accessibilityHint.isEmpty)
        }
    }

    @Test("Action accessibility labels name the account")
    func actionLabels() {
        #expect(DashboardDrillInAction.reconnect.accessibilityLabel(accountDisplayName: "Chase") == "Reconnect Chase")
        #expect(DashboardDrillInAction.remove.accessibilityLabel(accountDisplayName: "Chase") == "Remove institution for Chase")
        #expect(DashboardDrillInAction.settings.accessibilityLabel(accountDisplayName: "Chase") == "Open VaultPeek settings from Chase")
    }

    @Test("Demo mode keeps only Settings; real mode keeps all three actions")
    func demoModeActions() {
        #expect(DashboardDrillInAction.accountDrillInActions(isDemoMode: true) == [.settings])
        #expect(DashboardDrillInAction.accountDrillInActions(isDemoMode: false) == [.reconnect, .remove, .settings])
        #expect(DashboardDrillInAction.accountDrillInActions == [.reconnect, .remove, .settings])
    }

    // MARK: Drill-in path

    @Test("Drill-in path copy differs by selection state")
    func drillInPath() {
        let selected = DashboardAccountDrillInPath.presentation(for: account(type: .depository), isSelected: true)
        let unselected = DashboardAccountDrillInPath.presentation(for: account(type: .depository), isSelected: false)
        #expect(selected.accessibilityActionName == "Close account details")
        #expect(unselected.accessibilityActionName == "Open account details")
        #expect(selected.pointerHelp.contains("Close"))
        #expect(unselected.pointerHelp.contains("Open"))
    }

    // MARK: Summary accessibility label

    private func summary(
        utilizationPercent: Double?,
        transactionCount: Int,
        pendingTransactionCount: Int,
        latestTransactionDate: String?
    ) -> DashboardAccountDrillInSummary {
        DashboardAccountDrillInSummary(
            displayName: "Checking",
            subtitle: "Bank • Checking",
            availableTitle: "Available",
            availableBalance: 1_000,
            currentTitle: "Current",
            currentBalance: 1_050,
            currency: .usd,
            utilizationPercent: utilizationPercent,
            limit: utilizationPercent == nil ? nil : 2_000,
            transactionCount: transactionCount,
            pendingTransactionCount: pendingTransactionCount,
            latestTransactionDate: latestTransactionDate,
            syncState: .connected,
            freshnessLabel: "just now"
        )
    }

    @Test("Public label includes counts, plural suffixes, and latest date")
    func summaryLabelPublic() {
        let label = summary(
            utilizationPercent: nil, transactionCount: 3, pendingTransactionCount: 2,
            latestTransactionDate: "2026-06-13"
        ).accessibilityLabel
        #expect(label.contains("Selected account drill-in"))
        #expect(label.contains("Checking"))
        #expect(label.contains("3 synced transactions"))
        #expect(label.contains("2 pending transactions"))
        #expect(label.contains("Latest transaction"))
        #expect(!label.contains("Utilization"))
    }

    @Test("Private label hides counts and latest date but keeps utilization")
    func summaryLabelPrivate() {
        let label = summary(
            utilizationPercent: 30, transactionCount: 1, pendingTransactionCount: 1,
            latestTransactionDate: "2026-06-13"
        ).accessibilityLabel(privacyMaskEnabled: true)
        #expect(label.contains("Checking"))
        #expect(!label.contains("synced transaction"))
        #expect(!label.contains("Latest transaction"))
        #expect(label.contains("Utilization"))
    }

    @Test("Public label uses singular suffixes for single transactions")
    func summaryLabelSingular() {
        let label = summary(
            utilizationPercent: nil, transactionCount: 1, pendingTransactionCount: 1,
            latestTransactionDate: nil
        ).accessibilityLabel
        #expect(label.contains("1 synced transaction"))
        #expect(label.contains("1 pending transaction"))
        #expect(!label.contains("Latest transaction"))
    }

    @Test("Summary presentation derives counts and sync state from inputs")
    func summaryPresentation() {
        let acct = AccountDTO(
            id: "a1", itemId: "i1", name: "Checking", type: .depository,
            balances: BalanceDTO(available: 500, current: 520)
        )
        let txns = [
            TransactionDTO(id: "t1", accountId: "a1", amount: 10, date: "2026-06-10", name: "A", merchantName: "A", category: .foodAndDrink, pending: false),
            TransactionDTO(id: "t2", accountId: "a1", amount: 20, date: "2026-06-12", name: "B", merchantName: "B", category: .shopping, pending: true),
            TransactionDTO(id: "t3", accountId: "other", amount: 5, date: "2026-06-12", name: "C", merchantName: "C", category: .foodAndDrink, pending: false),
        ]
        let status = ItemStatus(id: "i1", status: .connected, lastSync: nil)
        let result = DashboardAccountDrillInSummary.presentation(
            for: acct, transactions: txns, itemStatus: status, fallbackFreshnessLabel: "never"
        )
        #expect(!result.displayName.isEmpty)
        #expect(result.transactionCount == 2)
        #expect(result.pendingTransactionCount == 1)
        #expect(result.syncState == .connected)
        #expect(result.freshnessLabel == "never")
    }
}
