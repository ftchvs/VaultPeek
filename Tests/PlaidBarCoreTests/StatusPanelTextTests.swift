import Foundation
@testable import PlaidBarCore
import Testing

@Suite("StatusPanelText Tests")
struct StatusPanelTextTests {
    private static func presentation(
        _ issue: ServerConnectionIssue,
        diag: String = "DIAG"
    ) -> ServerConnectionPresentation {
        ServerConnectionPresentation(issue: issue, statusText: "S", diagnosticsSummary: diag)
    }

    // MARK: - mode

    @Test("mode: demo wins over environment")
    func modeDemo() {
        #expect(StatusPanelText.mode(isDemoMode: true, environment: .production) == "Demo")
    }

    @Test("mode: environment label when not demo")
    func modeEnvironment() {
        #expect(StatusPanelText.mode(isDemoMode: false, environment: .sandbox) == "Sandbox")
        #expect(StatusPanelText.mode(isDemoMode: false, environment: .production) == "Production")
        #expect(StatusPanelText.mode(isDemoMode: false, environment: nil) == "Unknown")
    }

    // MARK: - serverCredentials

    @Test("serverCredentials: demo / unreachable / ready / missing")
    func serverCredentials() {
        #expect(StatusPanelText.serverCredentials(isDemoMode: true, serverConnected: false, credentialsConfigured: nil) == "Not required")
        #expect(StatusPanelText.serverCredentials(isDemoMode: false, serverConnected: false, credentialsConfigured: true) == "Unknown")
        #expect(StatusPanelText.serverCredentials(isDemoMode: false, serverConnected: true, credentialsConfigured: true) == "Ready")
        #expect(StatusPanelText.serverCredentials(isDemoMode: false, serverConnected: true, credentialsConfigured: false) == "Missing")
        // nil is not `== true`, so it reads as Missing.
        #expect(StatusPanelText.serverCredentials(isDemoMode: false, serverConnected: true, credentialsConfigured: nil) == "Missing")
    }

    // MARK: - serverSyncReadiness

    @Test("serverSyncReadiness: demo / unreachable / ready / no items")
    func serverSyncReadiness() {
        #expect(StatusPanelText.serverSyncReadiness(isDemoMode: true, serverConnected: false, syncReady: nil) == "Demo data")
        #expect(StatusPanelText.serverSyncReadiness(isDemoMode: false, serverConnected: false, syncReady: true) == "Unknown")
        #expect(StatusPanelText.serverSyncReadiness(isDemoMode: false, serverConnected: true, syncReady: true) == "Ready")
        #expect(StatusPanelText.serverSyncReadiness(isDemoMode: false, serverConnected: true, syncReady: false) == "No items")
        #expect(StatusPanelText.serverSyncReadiness(isDemoMode: false, serverConnected: true, syncReady: nil) == "No items")
    }

    // MARK: - refreshCadence

    @Test("refreshCadence: whole minutes")
    func refreshCadence() {
        #expect(StatusPanelText.refreshCadence(interval: 900) == "15 min")
        #expect(StatusPanelText.refreshCadence(interval: 60) == "1 min")
        #expect(StatusPanelText.refreshCadence(interval: 0) == "0 min")
        // Truncates toward zero like the original Int(_:) conversion.
        #expect(StatusPanelText.refreshCadence(interval: 119) == "1 min")
    }

    // MARK: - diagnosticsSummary ladder

    @Test("diagnostics: recovery demo errors win first (with pluralization)")
    func diagnosticsRecoveryErrored() {
        #expect(StatusPanelText.diagnosticsSummary(
            isDemoStatusRecoveryScenario: true, isDemoMode: true,
            serverConnection: Self.presentation(.demo), statusItemCount: 0,
            erroredItemCount: 1, needsLoginItemCount: 5
        ) == "1 demo item need attention")
        #expect(StatusPanelText.diagnosticsSummary(
            isDemoStatusRecoveryScenario: true, isDemoMode: true,
            serverConnection: Self.presentation(.demo), statusItemCount: 0,
            erroredItemCount: 2, needsLoginItemCount: 0
        ) == "2 demo items need attention")
    }

    @Test("diagnostics: recovery demo needs-update when no errors")
    func diagnosticsRecoveryNeedsUpdate() {
        #expect(StatusPanelText.diagnosticsSummary(
            isDemoStatusRecoveryScenario: true, isDemoMode: true,
            serverConnection: Self.presentation(.demo), statusItemCount: 0,
            erroredItemCount: 0, needsLoginItemCount: 3
        ) == "3 demo items need update")
    }

    @Test("diagnostics: recovery scenario with no flagged items falls through to the ladder")
    func diagnosticsRecoveryFallThrough() {
        // recovery == true but errored == 0 && needsLogin == 0 -> the demo block
        // returns nothing and execution proceeds into the isDemoMode/switch ladder.
        // Here: non-demo + connected + items > 0 with no problems -> healthy.
        #expect(StatusPanelText.diagnosticsSummary(
            isDemoStatusRecoveryScenario: true, isDemoMode: false,
            serverConnection: Self.presentation(.connected), statusItemCount: 3,
            erroredItemCount: 0, needsLoginItemCount: 0
        ) == "Plaid connection healthy")
    }

    @Test("diagnostics: demo mode defers to the server presentation summary")
    func diagnosticsDemoDefers() {
        #expect(StatusPanelText.diagnosticsSummary(
            isDemoStatusRecoveryScenario: false, isDemoMode: true,
            serverConnection: Self.presentation(.demo, diag: "DEMO-DIAG"),
            statusItemCount: 9, erroredItemCount: 9, needsLoginItemCount: 9
        ) == "DEMO-DIAG")
    }

    @Test("diagnostics: blocking server issues defer to the presentation summary")
    func diagnosticsBlockingDefers() {
        for issue in [ServerConnectionIssue.offline, .localAuthMissing, .localAuthRejected, .serverModeMismatch] {
            #expect(StatusPanelText.diagnosticsSummary(
                isDemoStatusRecoveryScenario: false, isDemoMode: false,
                serverConnection: Self.presentation(issue, diag: "BLOCK"),
                statusItemCount: 9, erroredItemCount: 9, needsLoginItemCount: 9
            ) == "BLOCK")
        }
    }

    @Test("diagnostics: no items connected")
    func diagnosticsNoItems() {
        #expect(StatusPanelText.diagnosticsSummary(
            isDemoStatusRecoveryScenario: false, isDemoMode: false,
            serverConnection: Self.presentation(.connected), statusItemCount: 0,
            erroredItemCount: 0, needsLoginItemCount: 0
        ) == "No Plaid items connected")
    }

    @Test("diagnostics: per-item attention then update, with pluralization")
    func diagnosticsPerItem() {
        #expect(StatusPanelText.diagnosticsSummary(
            isDemoStatusRecoveryScenario: false, isDemoMode: false,
            serverConnection: Self.presentation(.connected), statusItemCount: 5,
            erroredItemCount: 1, needsLoginItemCount: 4
        ) == "1 item need attention")
        #expect(StatusPanelText.diagnosticsSummary(
            isDemoStatusRecoveryScenario: false, isDemoMode: false,
            serverConnection: Self.presentation(.connected), statusItemCount: 5,
            erroredItemCount: 0, needsLoginItemCount: 2
        ) == "2 items need update")
    }

    @Test("diagnostics: .error issue with no per-item counts defers to the summary")
    func diagnosticsErrorIssueDefers() {
        #expect(StatusPanelText.diagnosticsSummary(
            isDemoStatusRecoveryScenario: false, isDemoMode: false,
            serverConnection: Self.presentation(.error, diag: "ERR"), statusItemCount: 3,
            erroredItemCount: 0, needsLoginItemCount: 0
        ) == "ERR")
    }

    @Test("diagnostics: healthy fallback")
    func diagnosticsHealthy() {
        #expect(StatusPanelText.diagnosticsSummary(
            isDemoStatusRecoveryScenario: false, isDemoMode: false,
            serverConnection: Self.presentation(.connected), statusItemCount: 3,
            erroredItemCount: 0, needsLoginItemCount: 0
        ) == "Plaid connection healthy")
    }
}
