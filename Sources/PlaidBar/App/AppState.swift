import SwiftUI
import PlaidBarCore
import Combine

@Observable
@MainActor
final class AppState {
    // MARK: - State
    var accounts: [AccountDTO] = []
    var transactions: [TransactionDTO] = []
    var isLoading = false
    var error: String?
    var isPopoverPresented = false
    var selectedTab: PopoverTab = .accounts
    var isSetupComplete = false
    var serverConnected = false

    // MARK: - Settings
    var showBalanceInMenuBar = true
    var balanceFormat: CurrencyFormat = .abbreviated
    var creditUtilizationThreshold: Double = 30.0
    var refreshInterval: TimeInterval = PlaidBarConstants.backgroundRefreshInterval

    // MARK: - Services
    private let serverClient = ServerClient()
    private var refreshTask: Task<Void, Never>?

    // MARK: - Computed

    var netBalance: Double {
        accounts.reduce(0) { total, account in
            switch account.type {
            case .depository, .investment:
                return total + account.balances.effectiveBalance
            case .credit, .loan:
                return total - abs(account.balances.current ?? 0)
            case .other:
                return total + account.balances.effectiveBalance
            }
        }
    }

    var menuBarText: String {
        guard !accounts.isEmpty else { return "PlaidBar" }
        guard showBalanceInMenuBar else { return "\u{1F4B0}" }
        return Formatters.currency(netBalance, format: balanceFormat)
    }

    var creditAccounts: [AccountDTO] {
        accounts.filter { $0.type == .credit }
    }

    var depositoryAccounts: [AccountDTO] {
        accounts.filter { $0.type == .depository }
    }

    var recentTransactions: [TransactionDTO] {
        Array(transactions.sorted { $0.date > $1.date }.prefix(PlaidBarConstants.maxRecentTransactions))
    }

    var transactionsByDate: [(String, [TransactionDTO])] {
        let grouped = Dictionary(grouping: recentTransactions) { $0.date }
        return grouped.sorted { $0.key > $1.key }
    }

    var spendingByCategory: [(SpendingCategory, Double)] {
        let expenses = transactions.filter {
            !$0.isIncome && $0.category != .transfer && $0.category != .transferOut
        }
        let grouped = Dictionary(grouping: expenses) { $0.category ?? .other }
        return grouped.map { (category, txns) in
            (category, txns.reduce(0) { $0 + $1.displayAmount })
        }.sorted { $0.1 > $1.1 }
    }

    var totalSpending: Double {
        spendingByCategory.reduce(0) { $0 + $1.1 }
    }

    // MARK: - Actions

    func checkServerConnection() async {
        do {
            let status = try await serverClient.getStatus()
            serverConnected = true
            isSetupComplete = status.itemCount > 0
        } catch {
            serverConnected = false
            isSetupComplete = false
        }
    }

    func refreshAccounts() async {
        isLoading = true
        error = nil
        do {
            accounts = try await serverClient.getAccounts()
            isSetupComplete = !accounts.isEmpty
        } catch {
            self.error = error.localizedDescription
        }
        isLoading = false
    }

    func refreshBalances() async {
        isLoading = true
        error = nil
        do {
            accounts = try await serverClient.getBalances()
        } catch {
            self.error = error.localizedDescription
        }
        isLoading = false
    }

    func syncTransactions() async {
        do {
            let response = try await serverClient.syncTransactions()
            // Add new transactions
            transactions.append(contentsOf: response.added)
            // Update modified
            for modified in response.modified {
                if let index = transactions.firstIndex(where: { $0.id == modified.id }) {
                    transactions[index] = modified
                }
            }
            // Remove deleted
            transactions.removeAll { response.removed.contains($0.id) }

            // Continue if there's more
            if response.hasMore {
                await syncTransactions()
            }
        } catch {
            self.error = error.localizedDescription
        }
    }

    func addAccount() async {
        do {
            let linkResponse = try await serverClient.createLinkToken()
            // Open Plaid Link in browser
            if let url = URL(string: linkResponse.linkUrl) {
                NSWorkspace.shared.open(url)
            }
        } catch {
            self.error = error.localizedDescription
        }
    }

    func removeAccount(itemId: String) async {
        do {
            try await serverClient.removeItem(itemId: itemId)
            let removedItemId = itemId
            let accountIdsForItem = Set(
                accounts.filter { $0.itemId == removedItemId }.map(\.id)
            )
            accounts.removeAll { $0.itemId == removedItemId }
            transactions.removeAll { accountIdsForItem.contains($0.accountId) }
        } catch {
            self.error = error.localizedDescription
        }
    }

    func startBackgroundRefresh() {
        refreshTask?.cancel()
        refreshTask = Task {
            while !Task.isCancelled {
                await refreshAccounts()
                await syncTransactions()
                try? await Task.sleep(for: .seconds(refreshInterval))
            }
        }
    }

    func stopBackgroundRefresh() {
        refreshTask?.cancel()
        refreshTask = nil
    }

    func loadInitialData() async {
        await checkServerConnection()
        if serverConnected {
            await refreshAccounts()
            await syncTransactions()
            startBackgroundRefresh()
        }
    }
}

enum PopoverTab: String, CaseIterable, Sendable {
    case accounts = "Accounts"
    case transactions = "Transactions"
    case spending = "Spending"
    case credit = "Credit"
}
