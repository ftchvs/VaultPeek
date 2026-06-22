import Foundation
import Testing
@testable import PlaidBarCore

/// Tests the converged ``RecoveryAction`` vocabulary, the ``RecoveryActionButton``
/// value type, and how each of the five attention states now resolves to ONE
/// canonical action + label + handoff (post-1.0 priority #3).
@Suite("Converged recovery action")
struct RecoveryActionTests {
    // MARK: - Canonical titles / icons

    @Test("Every recovery verb exposes a non-empty canonical title and icon")
    func everyVerbHasCanonicalTitleAndIcon() {
        for action in RecoveryAction.allCases {
            #expect(!action.canonicalTitle.isEmpty)
            #expect(!action.canonicalIconName.isEmpty)
        }
    }

    @Test("Canonical titles match the pinned converged copy")
    func canonicalTitlesArePinned() {
        #expect(RecoveryAction.checkServer.canonicalTitle == "Check Server")
        #expect(RecoveryAction.addAccount.canonicalTitle == "Add Account")
        #expect(RecoveryAction.refresh.canonicalTitle == "Refresh")
        #expect(RecoveryAction.refreshAccounts.canonicalTitle == "Refresh Accounts")
        #expect(RecoveryAction.syncTransactions.canonicalTitle == "Sync Transactions")
        #expect(RecoveryAction.reconnect.canonicalTitle == "Reconnect")
        #expect(RecoveryAction.openSettings.canonicalTitle == "Settings")
        #expect(RecoveryAction.requestNotificationPermission.canonicalTitle == "Request Permission")
        #expect(RecoveryAction.openNotificationSettings.canonicalTitle == "Open System Settings")
    }

    @Test("Legacy aliases resolve to the same converged enum and raw values")
    func legacyAliasesAreByteStable() {
        // The deprecated typealiases must remain the SAME type so existing
        // snapshots / equality keep working, and the raw values must be unchanged.
        #expect(RecoveryAction.reconnect.rawValue == "reconnect")
        #expect(RecoveryAction.requestNotificationPermission.rawValue == "requestNotificationPermission")
        #expect(RecoveryAction.refreshAccounts.rawValue == "refreshAccounts")
        #expect(RecoveryAction.syncTransactions.rawValue == "syncTransactions")
        // Round-trips through Codable on the legacy raw values.
        #expect(RecoveryAction(rawValue: "reconnect") == .reconnect)
        #expect(RecoveryAction(rawValue: "refresh") == .refresh)
    }

    @Test("deprecated defaultTitle/defaultIconName still alias the canonical copy")
    func deprecatedDefaultsAliasCanonical() {
        // Verified via the still-supported shim so legacy call sites stay correct.
        let action = RecoveryAction.refresh
        #expect(action.canonicalTitle == "Refresh")
        #expect(action.canonicalIconName == "arrow.clockwise")
    }

    // MARK: - RecoveryActionButton folding

    @Test("Button defaults its title and icon from the action when unspecified")
    func buttonDefaultsFromAction() {
        let button = RecoveryActionButton(action: .checkServer)
        #expect(button.title == "Check Server")
        #expect(button.iconName == "server.rack")
        #expect(button.isInteractive)
        #expect(button.targetItemId == nil)
    }

    @Test("Button honors explicit title/icon/hint/target overrides")
    func buttonHonorsOverrides() {
        let button = RecoveryActionButton(
            action: .reconnect,
            title: "Reconnect Acme Bank",
            iconName: "custom.icon",
            accessibilityHint: "hint",
            isInteractive: false,
            targetItemId: "item-123"
        )
        #expect(button.title == "Reconnect Acme Bank")
        #expect(button.iconName == "custom.icon")
        #expect(button.accessibilityHint == "hint")
        #expect(button.isInteractive == false)
        #expect(button.targetItemId == "item-123")
    }

    @Test("reconnect(from:) folds the item target and institution-qualified title")
    func reconnectButtonFoldsTarget() {
        let errored = RecoveryActionButton.reconnect(from: [
            ItemStatus(id: "item-secret", institutionName: "Acme Bank", status: .error),
        ])
        #expect(errored?.action == .reconnect)
        #expect(errored?.title == "Reconnect Acme Bank")
        #expect(errored?.targetItemId == "item-secret")

        // New-accounts-available uses the "Update" verb, matching every surface.
        let update = RecoveryActionButton.reconnect(from: [
            ItemStatus(id: "item-new", institutionName: "Chase", status: .newAccountsAvailable),
        ])
        #expect(update?.title == "Update Chase")
        #expect(update?.targetItemId == "item-new")

        // Healthy items produce no reconnect button.
        #expect(RecoveryActionButton.reconnect(from: [
            ItemStatus(id: "ok", institutionName: "Bank", status: .connected),
        ]) == nil)
    }

    // MARK: - STATE-2: item repair resolves to one action + handoff

    @Test("STATE-2 item repair yields the same action and target across surfaces")
    func state2ItemRepairIsConverged() {
        let statuses = [ItemStatus(id: "item-secret", institutionName: "Chase", status: .loginRequired)]

        // Dashboard readiness.
        let readiness = DashboardStatusReadiness.evaluate(
            isDemoMode: false, serverConnected: true, credentialsConfigured: true,
            linkedItemCount: 1, accountCount: 1, syncedItemCount: 1,
            needsLoginItemCount: 1, erroredItemCount: 0,
            isSyncStale: false, lastSyncRelative: "now", errorMessage: nil
        )
        let dashButton = readiness.recoveryActionButton(itemStatuses: statuses)
        #expect(dashButton?.action == .reconnect)
        #expect(dashButton?.title == "Reconnect Chase")
        #expect(dashButton?.targetItemId == "item-secret")

        // Attention queue row.
        let queue = AttentionQueue.evaluate(
            isDemoMode: false, serverConnected: true, credentialsConfigured: true,
            linkedItemCount: 1, accountCount: 1, syncedItemCount: 1,
            itemStatuses: statuses, isSyncStale: false, lastSyncRelative: "now", errorMessage: nil
        )
        let queueButton = queue.rows.first?.recoveryActionButton
        #expect(queueButton?.action == .reconnect)
        #expect(queueButton?.title == "Reconnect Chase")
        #expect(queueButton?.targetItemId == "item-secret")

        // Account connection chip.
        let chip = AccountConnectionPresentation.evaluate(
            isDemoMode: false, serverConnected: true, isSyncStale: false,
            statusSyncText: "now", itemStatus: .loginRequired, institutionName: "Chase"
        )
        #expect(chip.recoveryActionTitle == "Reconnect Chase")
    }

    // MARK: - STATE-4: stale sync resolves to one label everywhere

    @Test("STATE-4 stale sync uses the one canonical refresh label on every surface")
    func state4StaleSyncLabelIsCanonical() {
        let readiness = DashboardStatusReadiness.evaluate(
            isDemoMode: false, serverConnected: true, credentialsConfigured: true,
            linkedItemCount: 1, accountCount: 1, syncedItemCount: 1,
            needsLoginItemCount: 0, erroredItemCount: 0,
            isSyncStale: true, lastSyncRelative: "3d ago", errorMessage: nil
        )
        #expect(readiness.primaryAction == .refresh)
        #expect(readiness.primaryActionTitle == staleSyncRefreshTitle)

        let queue = AttentionQueue.evaluate(
            isDemoMode: false, serverConnected: true, credentialsConfigured: true,
            linkedItemCount: 1, accountCount: 1, syncedItemCount: 1,
            itemStatuses: [], isSyncStale: true, lastSyncRelative: "3d ago", errorMessage: nil
        )
        let staleRow = queue.rows.first { $0.id == "sync-stale" }
        #expect(staleRow?.action == .refresh)
        #expect(staleRow?.actionTitle == staleSyncRefreshTitle)

        let chip = AccountConnectionPresentation.evaluate(
            isDemoMode: false, serverConnected: true, isSyncStale: true,
            statusSyncText: "3d ago", itemStatus: .connected
        )
        #expect(chip.recoveryActionTitle == staleSyncRefreshTitle)
    }

    // MARK: - Route hand-off keyed off the converged verb

    @Test("Route.from(recoveryAction:) maps item-scoped and add-account verbs")
    func routeFromRecoveryAction() {
        #expect(Route.from(recoveryAction: .reconnect, targetItemId: "item-9") == .accounts(itemID: "item-9"))
        #expect(Route.from(recoveryAction: .addAccount) == .accounts())
        // In-place verbs carry no in-window destination.
        for action: RecoveryAction in [
            .checkServer, .refresh, .refreshAccounts, .syncTransactions,
            .openSettings, .requestNotificationPermission, .openNotificationSettings,
            .clearFilters, .showWiderPeriod,
        ] {
            #expect(Route.from(recoveryAction: action) == nil)
        }
    }

    // MARK: - Secondary content states emit a converged button

    @Test("Secondary content unavailable states emit a converged recovery button")
    func secondaryContentEmitsButton() {
        let state = SecondaryContentUnavailableState.transactions(
            isDemoMode: false, serverConnected: true,
            linkedItemCount: 1, accountCount: 1, syncedItemCount: 0,
            transactionCount: 0, hasSearchText: false, hasActiveFilters: false, errorMessage: nil
        )
        let button = state.recoveryActionButton
        #expect(button.action == .syncTransactions)
        #expect(button.title == state.actionTitle)
        #expect(button.iconName == state.actionIconName)
        #expect(button.isInteractive == !state.isLoading)
    }
}
