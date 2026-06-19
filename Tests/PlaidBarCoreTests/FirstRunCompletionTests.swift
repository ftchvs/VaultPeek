import Foundation
import Testing
@testable import PlaidBarCore

@Suite("First run completion state")
struct FirstRunCompletionTests {
    private func evaluate(
        isDemoMode: Bool = false,
        serverConnected: Bool = true,
        linkedItemCount: Int = 1,
        accountCount: Int = 1,
        transactionCount: Int = 5,
        syncedItemCount: Int = 1,
        errorMessage: String? = nil
    ) -> FirstRunCompletionState {
        FirstRunCompletionState.evaluate(
            isDemoMode: isDemoMode,
            serverConnected: serverConnected,
            linkedItemCount: linkedItemCount,
            accountCount: accountCount,
            transactionCount: transactionCount,
            syncedItemCount: syncedItemCount,
            errorMessage: errorMessage
        )
    }

    @Test("Demo mode is immediately ready")
    func demo() {
        let state = evaluate(isDemoMode: true, serverConnected: false, linkedItemCount: 0)
        #expect(state.step == .ready)
        #expect(state.title == "Demo ready")
        #expect(state.isReady)
        #expect(!state.canRetry)
    }

    @Test("An error message blocks with a retry")
    func errorBlocks() {
        let state = evaluate(errorMessage: "Plaid Link failed")
        #expect(state.step == .blocked)
        #expect(state.title == "Connection needs attention")
        #expect(state.canRetry)
        #expect(!state.isReady)
    }

    @Test("Offline server blocks")
    func offline() {
        let state = evaluate(serverConnected: false)
        #expect(state.step == .blocked)
        #expect(state.title == "Server offline")
    }

    @Test("No linked item routes back to Plaid Link")
    func noLinkedItem() {
        #expect(evaluate(linkedItemCount: 0).step == .openPlaidLink)
    }

    @Test("No accounts routes to load accounts")
    func noAccounts() {
        #expect(evaluate(accountCount: 0).step == .loadAccounts)
    }

    @Test("Partial sync stays on the sync step with progress detail")
    func partialSync() {
        let state = evaluate(linkedItemCount: 2, accountCount: 2, transactionCount: 10, syncedItemCount: 1)
        #expect(state.step == .syncTransactions)
        #expect(state.title == "First sync incomplete")
        #expect(state.detail.contains("1 of 2 linked items synced"))
    }

    @Test("Accounts loaded but unsynced explains the pending first sync")
    func accountsLoadedNoSync() {
        let withTransactions = evaluate(linkedItemCount: 1, accountCount: 1, transactionCount: 3, syncedItemCount: 0)
        #expect(withTransactions.step == .syncTransactions)
        #expect(withTransactions.title == "Accounts loaded")
        #expect(withTransactions.detail.contains("Transactions are present"))

        let noTransactions = evaluate(linkedItemCount: 1, accountCount: 1, transactionCount: 0, syncedItemCount: 0)
        #expect(noTransactions.detail.contains("Run the first transaction sync check"))
    }

    @Test("Fully synced is ready, with singular and plural transaction copy")
    func ready() {
        let plural = evaluate(transactionCount: 5, syncedItemCount: 1)
        #expect(plural.step == .ready)
        #expect(plural.title == "Dashboard ready")
        #expect(plural.detail.contains("5 transactions synced"))

        let singular = evaluate(transactionCount: 1, syncedItemCount: 1)
        #expect(singular.detail.contains("1 transaction synced"))
        #expect(!singular.detail.contains("1 transactions"))
    }
}
