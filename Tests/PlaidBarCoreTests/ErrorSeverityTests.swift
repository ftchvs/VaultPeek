import Foundation
@testable import PlaidBarCore
import Testing

@Suite("Error severity model")
struct ErrorSeverityTests {
    // MARK: - Severity ordering

    @Test("Blocking outranks advisory")
    func blockingOutranksAdvisory() {
        #expect(ErrorSeverity.advisory < ErrorSeverity.blocking)
        #expect([ErrorSeverity.advisory, .blocking].max() == .blocking)
        #expect([ErrorSeverity.advisory, .advisory].max() == .advisory)
    }

    // MARK: - Severity is a property of the existing mappings

    @Test("Attention queue severities map to error severity tiers")
    func attentionQueueSeverityMapsToErrorSeverity() {
        #expect(AttentionQueueSeverity.healthy.errorSeverity == nil)
        #expect(AttentionQueueSeverity.warning.errorSeverity == .advisory)
        #expect(AttentionQueueSeverity.blocked.errorSeverity == .blocking)
    }

    @Test("Dashboard readiness levels map to error severity tiers")
    func dashboardReadinessLevelMapsToErrorSeverity() {
        #expect(DashboardStatusReadinessLevel.healthy.errorSeverity == nil)
        #expect(DashboardStatusReadinessLevel.warning.errorSeverity == .advisory)
        #expect(DashboardStatusReadinessLevel.blocked.errorSeverity == .blocking)
    }

    @Test("Connection issues reserve blocking for connection-gating states")
    func connectionIssueMapsToErrorSeverity() {
        #expect(ServerConnectionIssue.demo.errorSeverity == nil)
        #expect(ServerConnectionIssue.syncing.errorSeverity == nil)
        #expect(ServerConnectionIssue.connected.errorSeverity == nil)
        #expect(ServerConnectionIssue.offline.errorSeverity == .blocking)
        #expect(ServerConnectionIssue.localAuthMissing.errorSeverity == .blocking)
        #expect(ServerConnectionIssue.localAuthRejected.errorSeverity == .blocking)
        #expect(ServerConnectionIssue.serverModeMismatch.errorSeverity == .blocking)
        #expect(ServerConnectionIssue.error.errorSeverity == .advisory)
    }

    @Test("Readiness presentation exposes the severity of its level")
    func readinessPresentationExposesSeverity() {
        let blocked = DashboardStatusReadiness.evaluate(
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
        let advisory = DashboardStatusReadiness.evaluate(
            isDemoMode: false,
            serverConnected: true,
            credentialsConfigured: true,
            linkedItemCount: 1,
            accountCount: 1,
            syncedItemCount: 1,
            needsLoginItemCount: 0,
            erroredItemCount: 0,
            isSyncStale: false,
            lastSyncRelative: "now",
            errorMessage: "Plaid sync failed."
        )
        let healthy = DashboardStatusReadiness.evaluate(
            isDemoMode: false,
            serverConnected: true,
            credentialsConfigured: true,
            linkedItemCount: 1,
            accountCount: 1,
            syncedItemCount: 1,
            needsLoginItemCount: 0,
            erroredItemCount: 0,
            isSyncStale: false,
            lastSyncRelative: "now",
            errorMessage: nil
        )

        #expect(blocked.errorSeverity == .blocking)
        #expect(advisory.errorSeverity == .advisory)
        #expect(healthy.errorSeverity == nil)
    }

    // MARK: - Attention queue ordering and rollup

    @Test("Queue rolls up the highest severity across visible rows")
    func queueRollsUpHighestSeverity() {
        let blockedAndWarning = AttentionQueue.evaluate(
            isDemoMode: false,
            serverConnected: false,
            credentialsConfigured: nil,
            linkedItemCount: 1,
            accountCount: 1,
            syncedItemCount: 1,
            itemStatuses: [],
            isSyncStale: true,
            lastSyncRelative: "3 days ago",
            errorMessage: nil
        )
        let advisoryOnly = AttentionQueue.evaluate(
            isDemoMode: false,
            serverConnected: true,
            credentialsConfigured: true,
            linkedItemCount: 1,
            accountCount: 1,
            syncedItemCount: 1,
            itemStatuses: [],
            isSyncStale: true,
            lastSyncRelative: "3 days ago",
            errorMessage: nil
        )
        let healthy = AttentionQueue.evaluate(
            isDemoMode: false,
            serverConnected: true,
            credentialsConfigured: true,
            linkedItemCount: 1,
            accountCount: 1,
            syncedItemCount: 1,
            itemStatuses: [],
            isSyncStale: false,
            lastSyncRelative: "now",
            errorMessage: nil
        )

        #expect(blockedAndWarning.highestErrorSeverity == .blocking)
        #expect(advisoryOnly.highestErrorSeverity == .advisory)
        #expect(healthy.highestErrorSeverity == nil)
    }

    @Test("Queue orders blocking rows ahead of advisory rows")
    func queueOrdersBlockingBeforeAdvisory() {
        let queue = AttentionQueue.evaluate(
            isDemoMode: false,
            serverConnected: true,
            credentialsConfigured: true,
            linkedItemCount: 2,
            accountCount: 2,
            syncedItemCount: 2,
            itemStatuses: [
                ItemStatus(id: "item-login", institutionName: "Example Bank", status: .loginRequired),
                ItemStatus(id: "item-error", institutionName: "City Credit", status: .error),
            ],
            isSyncStale: true,
            lastSyncRelative: "3 days ago",
            errorMessage: "Plaid sync failed."
        )

        let severities = queue.rows.compactMap(\.errorSeverity)
        #expect(severities == severities.sorted(by: >))
        #expect(queue.rows.first?.errorSeverity == .blocking)
    }

    // MARK: - Connection presentation

    @Test("Offline wins over a stale advisory error message")
    func offlineWinsOverAdvisoryError() {
        let presentation = ServerConnectionPresentation.evaluate(
            isDemoMode: false,
            isLoading: false,
            serverConnected: false,
            errorMessage: "Request to the VaultPeek companion server failed"
        )

        #expect(presentation.issue == .offline)
        #expect(presentation.statusText == "Offline")
        #expect(presentation.errorSeverity == .blocking)
    }

    @Test("A reachable server with a recent failure stays advisory")
    func reachableServerWithRecentFailureIsAdvisory() {
        let presentation = ServerConnectionPresentation.evaluate(
            isDemoMode: false,
            isLoading: false,
            serverConnected: true,
            errorMessage: "VaultPeek companion server returned 500: internal server error"
        )

        #expect(presentation.issue == .error)
        #expect(presentation.errorSeverity == .advisory)
    }

    @Test("Server mode mismatch remains blocking even when the server is reachable")
    func serverModeMismatchIsBlocking() {
        let presentation = ServerConnectionPresentation.evaluate(
            isDemoMode: false,
            isLoading: false,
            serverConnected: true,
            errorMessage: "Server is running in production, not sandbox. Restart with ./Scripts/run.sh --sandbox."
        )

        #expect(presentation.issue == .serverModeMismatch)
        #expect(presentation.statusText == "Mode mismatch")
        #expect(presentation.attentionText == "Mode")
        #expect(presentation.errorSeverity == .blocking)
    }

    // MARK: - Menu bar chrome

    @Test("Advisory failures never paint the menu bar attention text")
    func advisoryFailureDoesNotPaintMenuBar() {
        let presentation = MenuBarStatusPresentation.evaluate(
            isDemoMode: false,
            isLoading: false,
            serverConnected: true,
            errorMessage: "Failed to read cached transactions",
            erroredItemCount: 0,
            needsLoginItemCount: 0,
            isSyncStale: false,
            hasEverSynced: true
        )

        #expect(presentation.attentionText == nil)
        #expect(presentation.symbolName == "exclamationmark.triangle")
        #expect(presentation.severity == .advisory)
    }

    @Test("Offline keeps its menu bar attention text and glyph")
    func offlineKeepsMenuBarChrome() {
        let presentation = MenuBarStatusPresentation.evaluate(
            isDemoMode: false,
            isLoading: false,
            serverConnected: false,
            errorMessage: nil,
            erroredItemCount: 0,
            needsLoginItemCount: 0,
            isSyncStale: true,
            hasEverSynced: true
        )

        #expect(presentation.attentionText == "Offline")
        #expect(presentation.symbolName == "network.slash")
        #expect(presentation.severity == .blocking)
    }

    @Test("Offline glyph and text win over a stale advisory error message")
    func offlineWinsMenuBarChromeOverAdvisoryError() {
        let presentation = MenuBarStatusPresentation.evaluate(
            isDemoMode: false,
            isLoading: false,
            serverConnected: false,
            errorMessage: "Request to the VaultPeek companion server failed",
            erroredItemCount: 0,
            needsLoginItemCount: 0,
            isSyncStale: true,
            hasEverSynced: true
        )

        #expect(presentation.attentionText == "Offline")
        #expect(presentation.symbolName == "network.slash")
        #expect(presentation.severity == .blocking)
    }

    @Test("Local auth failures keep the hard-failure menu bar chrome")
    func localAuthFailureKeepsMenuBarChrome() {
        let presentation = MenuBarStatusPresentation.evaluate(
            isDemoMode: false,
            isLoading: false,
            serverConnected: true,
            errorMessage: "VaultPeek companion server returned 401: unauthorized",
            erroredItemCount: 0,
            needsLoginItemCount: 0,
            isSyncStale: false,
            hasEverSynced: true
        )

        #expect(presentation.attentionText == "Auth")
        #expect(presentation.symbolName == "exclamationmark.octagon")
        #expect(presentation.severity == .blocking)
    }

    @Test("Item errors keep the hard-failure menu bar chrome")
    func itemErrorsKeepMenuBarChrome() {
        let presentation = MenuBarStatusPresentation.evaluate(
            isDemoMode: false,
            isLoading: false,
            serverConnected: true,
            errorMessage: nil,
            erroredItemCount: 1,
            needsLoginItemCount: 0,
            isSyncStale: false,
            hasEverSynced: true
        )

        #expect(presentation.attentionText == "Error")
        #expect(presentation.symbolName == "exclamationmark.octagon")
        #expect(presentation.severity == .blocking)
    }

    @Test("Login and stale states stay advisory in the menu bar")
    func loginAndStaleStatesStayAdvisory() {
        let login = MenuBarStatusPresentation.evaluate(
            isDemoMode: false,
            isLoading: false,
            serverConnected: true,
            errorMessage: nil,
            erroredItemCount: 0,
            needsLoginItemCount: 1,
            isSyncStale: false,
            hasEverSynced: true
        )
        let stale = MenuBarStatusPresentation.evaluate(
            isDemoMode: false,
            isLoading: false,
            serverConnected: true,
            errorMessage: nil,
            erroredItemCount: 0,
            needsLoginItemCount: 0,
            isSyncStale: true,
            hasEverSynced: true
        )
        let neverSynced = MenuBarStatusPresentation.evaluate(
            isDemoMode: false,
            isLoading: false,
            serverConnected: true,
            errorMessage: nil,
            erroredItemCount: 0,
            needsLoginItemCount: 0,
            isSyncStale: true,
            hasEverSynced: false
        )

        #expect(login.attentionText == "Login")
        #expect(login.symbolName == "exclamationmark.triangle")
        #expect(login.severity == .advisory)
        #expect(stale.attentionText == "Stale")
        #expect(stale.symbolName == "exclamationmark.triangle")
        #expect(neverSynced.attentionText == "Never")
        #expect(neverSynced.severity == .advisory)
    }

    @Test("Healthy and demo states show no menu bar attention chrome")
    func healthyAndDemoShowNoAttentionChrome() {
        let healthy = MenuBarStatusPresentation.evaluate(
            isDemoMode: false,
            isLoading: false,
            serverConnected: true,
            errorMessage: nil,
            erroredItemCount: 0,
            needsLoginItemCount: 0,
            isSyncStale: false,
            hasEverSynced: true
        )
        let demo = MenuBarStatusPresentation.evaluate(
            isDemoMode: true,
            isLoading: false,
            serverConnected: false,
            errorMessage: nil,
            erroredItemCount: 0,
            needsLoginItemCount: 0,
            isSyncStale: false,
            hasEverSynced: false
        )

        #expect(healthy.attentionText == nil)
        #expect(healthy.symbolName == "dollarsign.circle")
        #expect(healthy.severity == nil)
        #expect(demo.attentionText == nil)
        #expect(demo.symbolName == "dollarsign.circle")
        #expect(demo.severity == nil)
    }

    @Test("Demo recovery scenarios keep the item-error glyph without text")
    func demoRecoveryKeepsItemErrorGlyph() {
        let presentation = MenuBarStatusPresentation.evaluate(
            isDemoMode: true,
            isLoading: false,
            serverConnected: false,
            errorMessage: nil,
            erroredItemCount: 1,
            needsLoginItemCount: 0,
            isSyncStale: false,
            hasEverSynced: false
        )

        #expect(presentation.attentionText == nil)
        #expect(presentation.symbolName == "exclamationmark.octagon")
        #expect(presentation.severity == .blocking)
    }
}
