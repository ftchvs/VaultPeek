import Foundation
import Testing
@testable import PlaidBarCore

@Suite("Account activity empty state")
struct AccountActivityEmptyStateTests {
    private func evaluate(
        transactionCount: Int = 0,
        isDemoMode: Bool = false,
        isInitialLoad: Bool = false,
        serverConnected: Bool = true,
        connectionLevel: AccountConnectionLevel = .healthy,
        accountDisplayName: String = "Everyday Checking"
    ) -> AccountActivityEmptyState? {
        AccountActivityEmptyState.evaluate(
            transactionCount: transactionCount,
            isDemoMode: isDemoMode,
            isInitialLoad: isInitialLoad,
            serverConnected: serverConnected,
            connectionLevel: connectionLevel,
            accountDisplayName: accountDisplayName
        )
    }

    @Test("No empty state when the account has transactions")
    func nonEmptyReturnsNil() {
        #expect(evaluate(transactionCount: 3) == nil)
    }

    @Test("Demo mode outranks every other reason")
    func demoMode() {
        let state = evaluate(isDemoMode: true, isInitialLoad: true, serverConnected: false, connectionLevel: .error)
        #expect(state?.title == "No demo activity")
        #expect(state?.tone == .secondary)
        #expect(state?.iconName == "play.circle")
        #expect(state?.detail.contains("Everyday Checking") == true)
    }

    @Test("Initial load reads as loading, not a degraded connection")
    func initialLoadOutranksOffline() {
        let state = evaluate(isInitialLoad: true, serverConnected: false, connectionLevel: .error)
        #expect(state?.title == "Loading activity")
        #expect(state?.tone == .loading)
        #expect(state?.iconName == "arrow.triangle.2.circlepath")
    }

    @Test("Offline server is reported before connection-level messaging")
    func serverOffline() {
        let state = evaluate(serverConnected: false, connectionLevel: .healthy)
        #expect(state?.title == "Server offline")
        #expect(state?.tone == .offline)
        #expect(state?.iconName == "server.rack")
    }

    @Test("Login-required connection prompts a reconnect")
    func loginRequired() {
        let state = evaluate(connectionLevel: .loginRequired)
        #expect(state?.title == "Reconnect to sync activity")
        #expect(state?.tone == .warning)
    }

    @Test("Item error warns and asks for a reconnect")
    func itemError() {
        let state = evaluate(connectionLevel: .error)
        #expect(state?.title == "Item error blocks activity")
        #expect(state?.tone == .warning)
        #expect(state?.iconName == "exclamationmark.triangle.fill")
    }

    @Test("Stale connection nudges a refresh")
    func stale() {
        let state = evaluate(connectionLevel: .stale)
        #expect(state?.title == "Activity may be stale")
        #expect(state?.tone == .warning)
    }

    @Test("Unknown status reads as status-unavailable, not an error")
    func unknown() {
        let state = evaluate(connectionLevel: .unknown)
        #expect(state?.title == "Item status unavailable")
        #expect(state?.tone == .secondary)
    }

    @Test("Demo and offline connection levels both read as plain no-activity")
    func demoAndOfflineLevels() {
        for level in [AccountConnectionLevel.demo, .offline] {
            let state = evaluate(connectionLevel: level)
            #expect(state?.title == "No recent activity")
            #expect(state?.tone == .secondary)
            #expect(state?.iconName == "tray")
        }
    }

    @Test("Healthy account with no activity stays positive in tone")
    func healthy() {
        let state = evaluate(connectionLevel: .healthy)
        #expect(state?.title == "No recent activity")
        #expect(state?.tone == .healthy)
        #expect(state?.detail.contains("linked") == true)
    }

    @Test("Accessibility label joins title and detail")
    func accessibilityLabel() {
        let state = AccountActivityEmptyState(
            title: "Title", detail: "Detail.", iconName: "tray", tone: .secondary
        )
        #expect(state.accessibilityLabel == "Title. Detail.")
    }
}
