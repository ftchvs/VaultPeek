import Foundation
@testable import PlaidBarCore
import Testing

@Suite("DashboardLoadState Tests")
struct DashboardLoadStateTests {
    private func evaluate(
        surface: DashboardLoadSurface = .accounts,
        isDemoMode: Bool = false,
        isBooting: Bool = false,
        isLoading: Bool = false,
        serverConnected: Bool = false,
        hasContent: Bool = false,
        errorMessage: String? = nil
    ) -> DashboardLoadState {
        DashboardLoadState.evaluate(
            surface: surface,
            isDemoMode: isDemoMode,
            isBooting: isBooting,
            isLoading: isLoading,
            serverConnected: serverConnected,
            hasContent: hasContent,
            errorMessage: errorMessage
        )
    }

    @Test("Boot without content is loading and shows a skeleton, not offline")
    func bootWithoutContentLoads() {
        let state = evaluate(isBooting: true)

        #expect(state.phase == .loading)
        #expect(state.isInitialLoad)
        #expect(state.showsSkeleton)
        #expect(state
            .loadingAccessibilityLabel ==
            "Loading accounts. Fetching linked account balances from the local VaultPeek server.")
    }

    @Test("In-flight refresh without content is loading")
    func refreshWithoutContentLoads() {
        let state = evaluate(isLoading: true, serverConnected: true)

        #expect(state.phase == .loading)
        #expect(state.showsSkeleton)
    }

    @Test("Cached content wins over an in-flight boot — no skeleton regression")
    func cachedContentWinsDuringBoot() {
        let state = evaluate(isBooting: true, isLoading: true, hasContent: true)

        #expect(state.phase == .loaded)
        #expect(!state.showsSkeleton)
        #expect(state.loadingAccessibilityLabel == nil)
    }

    @Test("Demo mode never skeletons")
    func demoModeNeverSkeletons() {
        let empty = evaluate(isDemoMode: true, isBooting: true)
        let loaded = evaluate(isDemoMode: true, hasContent: true)

        #expect(empty.phase == .idle)
        #expect(!empty.showsSkeleton)
        #expect(loaded.phase == .loaded)
    }

    @Test("Completed check without server is offline, with error is error")
    func completedCheckVerdicts() {
        #expect(evaluate().phase == .offline)
        #expect(evaluate(serverConnected: true, errorMessage: "Recent action failed").phase == .error)
        #expect(evaluate(errorMessage: "boom").phase == .error)
    }

    @Test("Whitespace-only error does not count as an error verdict")
    func whitespaceErrorIgnored() {
        #expect(evaluate(errorMessage: "  \n ").phase == .offline)
        #expect(evaluate(serverConnected: true, errorMessage: "  ").phase == .idle)
    }

    @Test("Connected with no content and no fetch is idle")
    func connectedEmptyIsIdle() {
        let state = evaluate(serverConnected: true)

        #expect(state.phase == .idle)
        #expect(!state.showsSkeleton)
    }

    @Test("Every surface has loading copy")
    func everySurfaceHasLoadingCopy() {
        for surface in DashboardLoadSurface.allCases {
            #expect(!surface.loadingTitle.isEmpty)
            #expect(!surface.loadingDetail.isEmpty)
            let state = DashboardLoadState(surface: surface, phase: .loading)
            #expect(state.loadingAccessibilityLabel == "\(surface.loadingTitle). \(surface.loadingDetail)")
        }
    }
}

@Suite("Empty-state evaluator loading cases")
struct EmptyStateLoadingCaseTests {
    @Test("Dashboard account empty state renders loading before offline during the first fetch")
    func dashboardAccountEmptyStateLoading() {
        let state = DashboardAccountEmptyState.evaluate(
            filter: .all,
            isDemoMode: false,
            isInitialLoad: true,
            serverConnected: false,
            linkedItemCount: 0,
            accountCount: 0,
            degradedItemCount: 0
        )

        #expect(state.tone == .loading)
        #expect(state.isLoading)
        #expect(state.title == "Loading accounts")
        #expect(!state.showsAddAccount)
    }

    @Test("Demo mode ignores the initial-load flag for the dashboard empty state")
    func dashboardAccountEmptyStateDemoIgnoresLoading() {
        let state = DashboardAccountEmptyState.evaluate(
            filter: .all,
            isDemoMode: true,
            isInitialLoad: true,
            serverConnected: true,
            linkedItemCount: 0,
            accountCount: 0,
            degradedItemCount: 0
        )

        #expect(state.tone != .loading)
        #expect(!state.isLoading)
    }

    @Test("Dashboard account empty state still reports offline once boot completes")
    func dashboardAccountEmptyStateOfflineAfterBoot() {
        let state = DashboardAccountEmptyState.evaluate(
            filter: .all,
            isDemoMode: false,
            isInitialLoad: false,
            serverConnected: false,
            linkedItemCount: 0,
            accountCount: 0,
            degradedItemCount: 0
        )

        #expect(state.tone == .offline)
        #expect(state.title == "Server offline")
    }

    @Test("Secondary surfaces render passive loading states during the first fetch")
    func secondarySurfacesLoading() {
        let accounts = SecondaryContentUnavailableState.accounts(
            isDemoMode: false,
            isInitialLoad: true,
            serverConnected: false,
            linkedItemCount: 0
        )
        let credit = SecondaryContentUnavailableState.credit(
            isDemoMode: false,
            isInitialLoad: true,
            serverConnected: false,
            linkedItemCount: 0,
            accountCount: 0
        )
        let transactions = SecondaryContentUnavailableState.transactions(
            isDemoMode: false,
            isInitialLoad: true,
            serverConnected: false,
            linkedItemCount: 0,
            accountCount: 0,
            syncedItemCount: 0,
            transactionCount: 0,
            hasSearchText: false,
            hasActiveFilters: false,
            errorMessage: nil
        )
        let spending = SecondaryContentUnavailableState.spendingActivity(
            isDemoMode: false,
            isInitialLoad: true,
            serverConnected: false,
            linkedItemCount: 0,
            accountCount: 0,
            syncedItemCount: 0,
            transactionCount: 0,
            errorMessage: nil
        )
        let recurring = SecondaryContentUnavailableState.recurring(
            isDemoMode: false,
            isInitialLoad: true,
            serverConnected: false,
            linkedItemCount: 0,
            accountCount: 0,
            syncedItemCount: 0,
            transactionCount: 0,
            errorMessage: nil
        )

        for state in [accounts, credit, transactions, spending, recurring] {
            #expect(state.isLoading)
            #expect(state.title.hasPrefix("Loading"))
            #expect(state.iconName == "arrow.triangle.2.circlepath")
        }
    }

    @Test("Filtered-zero results beat the loading state — synced content exists")
    func filteredZeroBeatsLoading() {
        let state = SecondaryContentUnavailableState.transactions(
            isDemoMode: false,
            isInitialLoad: true,
            serverConnected: true,
            linkedItemCount: 1,
            accountCount: 2,
            syncedItemCount: 1,
            transactionCount: 12,
            hasSearchText: true,
            hasActiveFilters: false,
            errorMessage: nil
        )

        #expect(!state.isLoading)
        #expect(state.title == "No matching transactions")
        #expect(state.action == .clearFilters)
    }

    @Test("Loading outranks a stale error message while the first fetch is in flight")
    func loadingOutranksStaleError() {
        let state = SecondaryContentUnavailableState.transactions(
            isDemoMode: false,
            isInitialLoad: true,
            serverConnected: true,
            linkedItemCount: 1,
            accountCount: 2,
            syncedItemCount: 0,
            transactionCount: 0,
            hasSearchText: false,
            hasActiveFilters: false,
            errorMessage: "Recent action failed"
        )

        #expect(state.isLoading)
        #expect(state.title == "Loading transactions")
    }

    @Test("Secondary surfaces keep offline verdicts once boot completes")
    func secondarySurfacesOfflineAfterBoot() {
        let state = SecondaryContentUnavailableState.accounts(
            isDemoMode: false,
            isInitialLoad: false,
            serverConnected: false,
            linkedItemCount: 0
        )

        #expect(!state.isLoading)
        #expect(state.title == "Server offline")
    }

    @Test("Account activity empty state loads before offline/stale verdicts")
    func accountActivityLoading() {
        let state = AccountActivityEmptyState.evaluate(
            transactionCount: 0,
            isDemoMode: false,
            isInitialLoad: true,
            serverConnected: false,
            connectionLevel: .offline,
            accountDisplayName: "Chase Checking"
        )

        #expect(state?.tone == .loading)
        #expect(state?.title == "Loading activity")
        #expect(state?.detail.contains("Chase Checking") == true)
    }

    @Test("Account activity returns nil when transactions exist, even mid-load")
    func accountActivityContentWins() {
        let state = AccountActivityEmptyState.evaluate(
            transactionCount: 4,
            isDemoMode: false,
            isInitialLoad: true,
            serverConnected: true,
            connectionLevel: .healthy,
            accountDisplayName: "Chase Checking"
        )

        #expect(state == nil)
    }
}

@Suite("Status readiness and connection loading states")
struct StatusLoadingStateTests {
    @Test("Readiness reports a neutral loading level with no action during boot")
    func readinessLoadingLevel() {
        let readiness = DashboardStatusReadiness.evaluate(
            isDemoMode: false,
            isInitialLoad: true,
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

        #expect(readiness.level == .loading)
        #expect(readiness.title == "Loading financial data")
        #expect(readiness.primaryAction == nil)
    }

    @Test("Demo readiness wins over the initial-load flag")
    func readinessDemoWins() {
        let readiness = DashboardStatusReadiness.evaluate(
            isDemoMode: true,
            isInitialLoad: true,
            serverConnected: true,
            credentialsConfigured: true,
            linkedItemCount: 2,
            accountCount: 4,
            syncedItemCount: 2,
            needsLoginItemCount: 0,
            erroredItemCount: 0,
            isSyncStale: false,
            lastSyncRelative: "just now",
            errorMessage: nil
        )

        #expect(readiness.level == .healthy)
        #expect(readiness.title == "Demo data ready")
    }

    @Test("Readiness keeps the blocked offline verdict once boot completes")
    func readinessOfflineAfterBoot() {
        let readiness = DashboardStatusReadiness.evaluate(
            isDemoMode: false,
            isInitialLoad: false,
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
        #expect(readiness.title == "Server offline")
    }

    @Test("Server connection presents Connecting without an attention badge during boot")
    func serverConnectionConnecting() {
        let presentation = ServerConnectionPresentation.evaluate(
            isDemoMode: false,
            isInitialLoad: true,
            isLoading: false,
            serverConnected: false,
            errorMessage: nil
        )

        #expect(presentation.issue == .syncing)
        #expect(presentation.statusText == "Connecting")
        #expect(presentation.attentionText == nil)
    }

    @Test("Local auth issues outrank the boot connecting state")
    func authIssueOutranksConnecting() {
        let presentation = ServerConnectionPresentation.evaluate(
            isDemoMode: false,
            isInitialLoad: true,
            isLoading: false,
            serverConnected: false,
            errorMessage: "The local app-server auth token is unavailable"
        )

        #expect(presentation.issue == .localAuthMissing)
        #expect(presentation.attentionText == "Auth")
    }

    @Test("Menu bar recent spend shows the neutral app name during boot, not a zero verdict")
    func menuBarRecentSpendNeutralDuringBoot() {
        let booting = MenuBarSummary.text(
            mode: .recentSpend,
            accounts: [],
            transactions: [],
            currencyFormat: .abbreviated,
            isInitialLoad: true
        )
        let settled = MenuBarSummary.text(
            mode: .recentSpend,
            accounts: [],
            transactions: [],
            currencyFormat: .abbreviated,
            isInitialLoad: false
        )

        #expect(booting == PlaidBarConstants.appName)
        #expect(settled == "No spend")
    }
}
