import Foundation
import Testing
@testable import PlaidBarCore

@Suite("Secondary content unavailable state")
struct SecondaryContentUnavailableStateTests {
    // MARK: accounts

    @Test("Accounts: initial load is a passive loading state")
    func accountsLoading() {
        let state = SecondaryContentUnavailableState.accounts(
            isDemoMode: false, isInitialLoad: true, serverConnected: false, linkedItemCount: 0
        )
        #expect(state.title == "Loading accounts")
        #expect(state.isLoading)
        #expect(state.action == .refresh)
    }

    @Test("Accounts: server offline outranks linked-item checks")
    func accountsServerOffline() {
        let state = SecondaryContentUnavailableState.accounts(
            isDemoMode: false, serverConnected: false, linkedItemCount: 0
        )
        #expect(state.title == "Server offline")
        #expect(state.action == .checkServer)
        #expect(!state.isLoading)
    }

    @Test("Accounts: no linked bank prompts a link")
    func accountsNoBank() {
        let state = SecondaryContentUnavailableState.accounts(
            isDemoMode: false, serverConnected: true, linkedItemCount: 0
        )
        #expect(state.title == "No bank linked")
        #expect(state.action == .addAccount)
    }

    @Test("Accounts: linked but unloaded prompts a refresh")
    func accountsRefresh() {
        let state = SecondaryContentUnavailableState.accounts(
            isDemoMode: false, serverConnected: true, linkedItemCount: 2
        )
        #expect(state.title == "Accounts not loaded")
        #expect(state.action == .refreshAccounts)
    }

    @Test("Accounts: demo mode bypasses loading and offline gates")
    func accountsDemoBypass() {
        let state = SecondaryContentUnavailableState.accounts(
            isDemoMode: true, isInitialLoad: true, serverConnected: false, linkedItemCount: 0
        )
        #expect(state.title == "No bank linked")
    }

    // MARK: credit

    @Test("Credit: loading during initial load")
    func creditLoading() {
        let state = SecondaryContentUnavailableState.credit(
            isDemoMode: false, isInitialLoad: true, serverConnected: true, linkedItemCount: 1, accountCount: 1
        )
        #expect(state.title == "Loading credit accounts")
        #expect(state.isLoading)
    }

    @Test("Credit: server offline")
    func creditOffline() {
        let state = SecondaryContentUnavailableState.credit(
            isDemoMode: false, serverConnected: false, linkedItemCount: 1, accountCount: 1
        )
        #expect(state.title == "Server offline")
    }

    @Test("Credit: no bank linked offers Plaid Link")
    func creditNoBank() {
        let state = SecondaryContentUnavailableState.credit(
            isDemoMode: false, serverConnected: true, linkedItemCount: 0, accountCount: 0
        )
        #expect(state.title == "No bank linked")
        #expect(state.action == .addAccount)
        #expect(state.actionTitle == "Link Bank")
    }

    @Test("Credit: accounts not loaded")
    func creditAccountsNotLoaded() {
        let state = SecondaryContentUnavailableState.credit(
            isDemoMode: false, serverConnected: true, linkedItemCount: 1, accountCount: 0
        )
        #expect(state.title == "Accounts not loaded")
        #expect(state.action == .refreshAccounts)
    }

    @Test("Credit: linked accounts without a card")
    func creditNoCard() {
        let state = SecondaryContentUnavailableState.credit(
            isDemoMode: false, serverConnected: true, linkedItemCount: 1, accountCount: 2
        )
        #expect(state.title == "No credit card linked")
        #expect(state.actionTitle == "Link Credit Card")
    }

    // MARK: transactions

    private func transactions(
        isDemoMode: Bool = false,
        isInitialLoad: Bool = false,
        serverConnected: Bool = true,
        linkedItemCount: Int = 1,
        accountCount: Int = 1,
        syncedItemCount: Int = 1,
        transactionCount: Int = 0,
        hasSearchText: Bool = false,
        hasActiveFilters: Bool = false,
        errorMessage: String? = nil
    ) -> SecondaryContentUnavailableState {
        SecondaryContentUnavailableState.transactions(
            isDemoMode: isDemoMode, isInitialLoad: isInitialLoad, serverConnected: serverConnected,
            linkedItemCount: linkedItemCount, accountCount: accountCount, syncedItemCount: syncedItemCount,
            transactionCount: transactionCount, hasSearchText: hasSearchText, hasActiveFilters: hasActiveFilters,
            errorMessage: errorMessage
        )
    }

    @Test("Transactions: active filters over loaded history offer a clear action")
    func txFiltered() {
        let state = transactions(transactionCount: 5, hasSearchText: true)
        #expect(state.title == "No matching transactions")
        #expect(state.action == .clearFilters)
    }

    @Test("Transactions: loading")
    func txLoading() {
        let state = transactions(isInitialLoad: true)
        #expect(state.title == "Loading transactions")
        #expect(state.isLoading)
    }

    @Test("Transactions: a recent failure surfaces the sanitized error")
    func txError() {
        let state = transactions(errorMessage: "The request timed out.")
        #expect(state.title == "Recent action failed")
        #expect(state.detail.contains("timed out"))
        #expect(state.action == .refresh)
    }

    @Test("Transactions: server offline")
    func txOffline() {
        #expect(transactions(serverConnected: false).title == "Server offline")
    }

    @Test("Transactions: no bank linked")
    func txNoBank() {
        #expect(transactions(linkedItemCount: 0, accountCount: 0, syncedItemCount: 0).title == "No bank linked")
    }

    @Test("Transactions: accounts not loaded")
    func txAccountsNotLoaded() {
        #expect(transactions(accountCount: 0, syncedItemCount: 0).title == "Accounts not loaded")
    }

    @Test("Transactions: first sync needed")
    func txFirstSync() {
        let state = transactions(syncedItemCount: 0)
        #expect(state.title == "First sync needed")
        #expect(state.action == .syncTransactions)
    }

    @Test("Transactions: synced but empty uses the no-history title")
    func txEmptyHistory() {
        #expect(transactions(transactionCount: 0).title == "No transaction history")
    }

    @Test("Transactions: loaded count without filters uses the plain empty title")
    func txPlainEmpty() {
        #expect(transactions(transactionCount: 3).title == "No transactions")
    }

    // MARK: spending activity

    private func spending(
        isDemoMode: Bool = false,
        isInitialLoad: Bool = false,
        serverConnected: Bool = true,
        linkedItemCount: Int = 1,
        accountCount: Int = 1,
        syncedItemCount: Int = 1,
        transactionCount: Int = 1,
        errorMessage: String? = nil
    ) -> SecondaryContentUnavailableState {
        SecondaryContentUnavailableState.spendingActivity(
            isDemoMode: isDemoMode, isInitialLoad: isInitialLoad, serverConnected: serverConnected,
            linkedItemCount: linkedItemCount, accountCount: accountCount, syncedItemCount: syncedItemCount,
            transactionCount: transactionCount, errorMessage: errorMessage
        )
    }

    @Test("Spending: loading / error / offline / no-bank / accounts gates")
    func spendingGates() {
        #expect(spending(isInitialLoad: true).title == "Loading spending activity")
        #expect(spending(errorMessage: "Sync failed").title == "Recent action failed")
        #expect(spending(serverConnected: false).title == "Server offline")
        #expect(spending(linkedItemCount: 0).title == "No bank linked")
        #expect(spending(accountCount: 0).title == "Accounts not loaded")
    }

    @Test("Spending: titles vary on whether anything is synced")
    func spendingDefaults() {
        #expect(spending(syncedItemCount: 0).title == "No synced activity")
        #expect(spending(transactionCount: 0).title == "No synced activity")
        #expect(spending(syncedItemCount: 1, transactionCount: 2).title == "No spending activity")
    }

    // MARK: spending period

    @Test("Spending period: wider window available")
    func periodWider() {
        let state = SecondaryContentUnavailableState.spendingPeriod(periodLabel: "June", canShowWiderPeriod: true)
        #expect(state.title == "No activity in June")
        #expect(state.action == .showWiderPeriod)
        #expect(state.actionTitle == "Show 90 Days")
    }

    @Test("Spending period: no wider window offers a refresh")
    func periodRefresh() {
        let state = SecondaryContentUnavailableState.spendingPeriod(periodLabel: "June", canShowWiderPeriod: false)
        #expect(state.action == .refresh)
        #expect(state.actionTitle == "Refresh")
    }

    // MARK: recurring

    private func recurring(
        isDemoMode: Bool = false,
        isInitialLoad: Bool = false,
        serverConnected: Bool = true,
        linkedItemCount: Int = 1,
        accountCount: Int = 1,
        syncedItemCount: Int = 1,
        transactionCount: Int = 1,
        errorMessage: String? = nil
    ) -> SecondaryContentUnavailableState {
        SecondaryContentUnavailableState.recurring(
            isDemoMode: isDemoMode, isInitialLoad: isInitialLoad, serverConnected: serverConnected,
            linkedItemCount: linkedItemCount, accountCount: accountCount, syncedItemCount: syncedItemCount,
            transactionCount: transactionCount, errorMessage: errorMessage
        )
    }

    @Test("Recurring: loading / error / offline / no-bank / accounts gates")
    func recurringGates() {
        #expect(recurring(isInitialLoad: true).title == "Loading recurring charges")
        #expect(recurring(errorMessage: "Sync failed").title == "Recent action failed")
        #expect(recurring(serverConnected: false).title == "Server offline")
        #expect(recurring(linkedItemCount: 0).title == "No bank linked")
        #expect(recurring(accountCount: 0).title == "Accounts not loaded")
    }

    @Test("Recurring: needs synced transactions, then reports none found")
    func recurringDefaults() {
        #expect(recurring(syncedItemCount: 0).title == "No synced transactions")
        #expect(recurring(transactionCount: 0).title == "No synced transactions")
        #expect(recurring(syncedItemCount: 1, transactionCount: 5).title == "No recurring charges found")
    }
}
