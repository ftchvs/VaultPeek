import Foundation
import Testing
@testable import PlaidBarCore

@Suite("Dashboard status readiness")
struct DashboardStatusReadinessTests {
    private func evaluate(
        isDemoMode: Bool = false,
        isInitialLoad: Bool = false,
        serverConnected: Bool = true,
        credentialsConfigured: Bool? = true,
        linkedItemCount: Int = 2,
        accountCount: Int = 3,
        syncedItemCount: Int = 2,
        needsLoginItemCount: Int = 0,
        erroredItemCount: Int = 0,
        isSyncStale: Bool = false,
        lastSyncRelative: String? = "2m ago",
        errorMessage: String? = nil,
        notificationsEnabled: Bool = false,
        notificationPermission: NotificationPermissionPresentation? = nil
    ) -> DashboardStatusReadiness {
        DashboardStatusReadiness.evaluate(
            isDemoMode: isDemoMode,
            isInitialLoad: isInitialLoad,
            serverConnected: serverConnected,
            credentialsConfigured: credentialsConfigured,
            linkedItemCount: linkedItemCount,
            accountCount: accountCount,
            syncedItemCount: syncedItemCount,
            needsLoginItemCount: needsLoginItemCount,
            erroredItemCount: erroredItemCount,
            isSyncStale: isSyncStale,
            lastSyncRelative: lastSyncRelative,
            errorMessage: errorMessage,
            notificationsEnabled: notificationsEnabled,
            notificationPermission: notificationPermission
        )
    }

    @Test("Demo mode is healthy with a connect prompt")
    func demo() {
        let readiness = evaluate(isDemoMode: true)
        #expect(readiness.level == .healthy)
        #expect(readiness.title == "Demo data ready")
        #expect(readiness.primaryAction == .addAccount)
        #expect(readiness.secondaryActions == [.openSettings])
    }

    @Test("Initial load is a passive loading level")
    func loading() {
        #expect(evaluate(isInitialLoad: true).level == .loading)
    }

    @Test("Missing local auth token blocks toward settings")
    func authMissing() {
        let readiness = evaluate(errorMessage: "Auth token is unavailable")
        #expect(readiness.level == .blocked)
        #expect(readiness.title == "Local server auth missing")
        #expect(readiness.primaryAction == .openSettings)
    }

    @Test("Rejected local auth (401/403) blocks")
    func authRejected() {
        #expect(evaluate(errorMessage: "PlaidBar server returned 401").title == "Local server auth rejected")
        #expect(evaluate(errorMessage: "VaultPeek companion server returned 403").title == "Local server auth rejected")
    }

    @Test("Offline server blocks toward a connection check")
    func offline() {
        let readiness = evaluate(serverConnected: false)
        #expect(readiness.level == .blocked)
        #expect(readiness.primaryAction == .checkServer)
    }

    @Test("Missing Plaid credentials block")
    func credentialsMissing() {
        #expect(evaluate(credentialsConfigured: false).title == "Plaid credentials missing")
    }

    @Test("Server mode mismatch blocks before item guidance")
    func modeMismatch() {
        let readiness = evaluate(erroredItemCount: 1, errorMessage: "Server is running in production, not sandbox")
        #expect(readiness.level == .blocked)
        #expect(readiness.title == "Server mode mismatch")
        #expect(readiness.primaryAction == .checkServer)
    }

    @Test("Errored items block with reconnect (pluralized)")
    func erroredItems() {
        let readiness = evaluate(erroredItemCount: 2)
        #expect(readiness.level == .blocked)
        #expect(readiness.title == "2 items need attention")
        #expect(readiness.primaryAction == .reconnect)
    }

    @Test("Login-needed items warn with reconnect (singular)")
    func needsLogin() {
        let readiness = evaluate(needsLoginItemCount: 1)
        #expect(readiness.level == .warning)
        #expect(readiness.title == "1 item needs update")
        #expect(readiness.primaryAction == .reconnect)
    }

    @Test("A recent action failure warns with the sanitized detail")
    func recentError() {
        let readiness = evaluate(errorMessage: "Something failed")
        #expect(readiness.level == .warning)
        #expect(readiness.title == "Recent action failed")
    }

    @Test("No linked institution warns toward connect")
    func noLink() {
        #expect(evaluate(linkedItemCount: 0).title == "No institution linked")
    }

    @Test("No accounts loaded warns toward load")
    func noAccounts() {
        #expect(evaluate(accountCount: 0).title == "Balances not loaded")
    }

    @Test("First sync needed when nothing has synced")
    func firstSync() {
        #expect(evaluate(syncedItemCount: 0).title == "First sync needed")
    }

    @Test("Partial sync warns to finish")
    func partialSync() {
        #expect(evaluate(linkedItemCount: 3, accountCount: 3, syncedItemCount: 1).title == "First sync incomplete")
    }

    @Test("Stale sync warns to refresh, echoing the last sync time")
    func staleSync() {
        let readiness = evaluate(isSyncStale: true)
        #expect(readiness.title == "Sync is stale")
        #expect(readiness.detail.contains("2m ago"))
    }

    @Test("Stale sync with no timestamp says never")
    func staleNoTimestamp() {
        #expect(evaluate(isSyncStale: true, lastSyncRelative: nil).detail.contains("never"))
    }

    @Test("Fully healthy state offers refresh and add account")
    func healthy() {
        let readiness = evaluate()
        #expect(readiness.level == .healthy)
        #expect(readiness.title == "Plaid sync healthy")
        #expect(readiness.secondaryActions == [.addAccount])
    }

    @Test("Healthy with no last sync says just now")
    func healthyNoTimestamp() {
        #expect(evaluate(lastSyncRelative: nil).detail.contains("just now"))
    }

    @Test("Notification recovery surfaces for each permission action")
    func notificationRecovery() {
        func recovery(kind: NotificationPermissionKind) -> DashboardStatusReadiness {
            evaluate(notificationsEnabled: true, notificationPermission: .evaluate(kind: kind))
        }
        #expect(recovery(kind: .notDetermined).title == "Notification permission not requested")
        #expect(recovery(kind: .denied).title == "Notifications blocked")
        #expect(recovery(kind: .unknown).title == "Notification permission unknown")
        #expect(recovery(kind: .unsupported).title == "Notification identity unavailable")
    }

    @Test("Notification recovery with no action falls back to settings")
    func notificationRecoveryNilAction() {
        let permission = NotificationPermissionPresentation(
            label: "x", detail: "y", iconName: "i", tone: .secondary,
            recoveryAction: nil, isNotificationToggleDisabled: true, shouldDisableNotifications: true
        )
        let readiness = evaluate(notificationsEnabled: true, notificationPermission: permission)
        #expect(readiness.title == "Notifications unavailable")
        #expect(readiness.primaryAction == .openSettings)
    }

    @Test("Notifications disabled skips recovery and stays healthy")
    func notificationsDisabledNoRecovery() {
        #expect(evaluate(notificationsEnabled: false, notificationPermission: .evaluate(kind: .denied)).level == .healthy)
    }

    @Test("Every action exposes a default title and icon")
    func actionDefaults() {
        let actions: [DashboardStatusReadinessAction] = [
            .checkServer, .addAccount, .refresh, .reconnect, .openSettings,
            .requestNotificationPermission, .openNotificationSettings,
        ]
        for action in actions {
            #expect(!action.defaultTitle.isEmpty)
            #expect(!action.defaultIconName.isEmpty)
        }
    }

    @Test("Error severity tracks the readiness level")
    func errorSeverity() {
        #expect(evaluate().errorSeverity == nil)
        #expect(evaluate(isInitialLoad: true).errorSeverity == nil)
        #expect(evaluate(needsLoginItemCount: 1).errorSeverity == .advisory)
        #expect(evaluate(erroredItemCount: 1).errorSeverity == .blocking)
    }
}
