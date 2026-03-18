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
    var lastSyncDate: Date?

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

    var lastSyncRelative: String? {
        guard let lastSyncDate else { return nil }
        return Formatters.relativeDate(lastSyncDate)
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
            lastSyncDate = Date()
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
            lastSyncDate = Date()
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
        if CommandLine.arguments.contains("--demo") {
            loadDemoData()
            // Allow --tab flag to set initial tab for screenshots
            if let tabIdx = CommandLine.arguments.firstIndex(of: "--tab"),
               tabIdx + 1 < CommandLine.arguments.count,
               let tab = PopoverTab.allCases.first(where: { $0.rawValue.lowercased() == CommandLine.arguments[tabIdx + 1].lowercased() }) {
                selectedTab = tab
            }
            return
        }
        await checkServerConnection()
        if serverConnected {
            await refreshAccounts()
            await syncTransactions()
            startBackgroundRefresh()
        }
    }

    // MARK: - Demo Data

    func loadDemoData() {
        let today = Self.dateString(daysAgo: 0)
        let yesterday = Self.dateString(daysAgo: 1)
        let twoDaysAgo = Self.dateString(daysAgo: 2)
        let threeDaysAgo = Self.dateString(daysAgo: 3)

        accounts = [
            AccountDTO(
                id: "demo_checking", itemId: "demo_chase", name: "Chase Checking",
                officialName: "Chase Total Checking", type: .depository, subtype: "checking",
                mask: "4892", balances: BalanceDTO(available: 8_241.56, current: 8_241.56, isoCurrencyCode: "USD"),
                institutionName: "Chase"
            ),
            AccountDTO(
                id: "demo_savings", itemId: "demo_chase", name: "Chase Savings",
                officialName: "Chase Savings", type: .depository, subtype: "savings",
                mask: "7731", balances: BalanceDTO(available: 15_420.00, current: 15_420.00, isoCurrencyCode: "USD"),
                institutionName: "Chase"
            ),
            AccountDTO(
                id: "demo_amex", itemId: "demo_amex_item", name: "Amex Platinum",
                officialName: "American Express Platinum Card", type: .credit, subtype: "credit card",
                mask: "1008", balances: BalanceDTO(current: -1_847.32, limit: 20_000, isoCurrencyCode: "USD"),
                institutionName: "American Express"
            ),
            AccountDTO(
                id: "demo_visa", itemId: "demo_chase", name: "Chase Freedom",
                officialName: "Chase Freedom Unlimited", type: .credit, subtype: "credit card",
                mask: "3345", balances: BalanceDTO(current: -4_210.00, limit: 5_000, isoCurrencyCode: "USD"),
                institutionName: "Chase"
            ),
        ]

        transactions = [
            // Today
            TransactionDTO(id: "tx1", accountId: "demo_checking", amount: 67.42, date: today, name: "WHOLEFDS MKT 10234", merchantName: "Whole Foods", category: .foodAndDrink),
            TransactionDTO(id: "tx2", accountId: "demo_checking", amount: 23.50, date: today, name: "UBER TRIP", merchantName: "Uber", category: .transportation),
            TransactionDTO(id: "tx3", accountId: "demo_checking", amount: -3_200.00, date: today, name: "STRIPE TRANSFER", merchantName: "Stripe", category: .income),
            TransactionDTO(id: "tx4", accountId: "demo_amex", amount: 142.80, date: today, name: "AMAZON.COM", merchantName: "Amazon", category: .shopping),
            // Yesterday
            TransactionDTO(id: "tx5", accountId: "demo_checking", amount: 15.99, date: yesterday, name: "NETFLIX.COM", merchantName: "Netflix", category: .entertainment),
            TransactionDTO(id: "tx6", accountId: "demo_checking", amount: 45.00, date: yesterday, name: "SHELL OIL 57422", merchantName: "Shell", category: .transportation),
            TransactionDTO(id: "tx7", accountId: "demo_amex", amount: 89.00, date: yesterday, name: "BLUE APRON", merchantName: "Blue Apron", category: .foodAndDrink),
            TransactionDTO(id: "tx8", accountId: "demo_visa", amount: 34.50, date: yesterday, name: "SPOTIFY", merchantName: "Spotify", category: .entertainment),
            // 2 days ago
            TransactionDTO(id: "tx9", accountId: "demo_checking", amount: 250.00, date: twoDaysAgo, name: "VERIZON WIRELESS", merchantName: "Verizon", category: .billsAndUtilities),
            TransactionDTO(id: "tx10", accountId: "demo_amex", amount: 320.00, date: twoDaysAgo, name: "DELTA AIR LINES", merchantName: "Delta Airlines", category: .travel),
            TransactionDTO(id: "tx11", accountId: "demo_checking", amount: 12.50, date: twoDaysAgo, name: "STARBUCKS 8823", merchantName: "Starbucks", category: .foodAndDrink),
            // 3 days ago
            TransactionDTO(id: "tx12", accountId: "demo_visa", amount: 75.00, date: threeDaysAgo, name: "PLANET FITNESS", merchantName: "Planet Fitness", category: .healthAndFitness),
            TransactionDTO(id: "tx13", accountId: "demo_checking", amount: -1_500.00, date: threeDaysAgo, name: "VENMO PAYMENT", merchantName: "Venmo", category: .income),
            TransactionDTO(id: "tx14", accountId: "demo_amex", amount: 55.00, date: threeDaysAgo, name: "TARGET 0392", merchantName: "Target", category: .shopping),
            TransactionDTO(id: "tx15", accountId: "demo_checking", amount: 1_850.00, date: threeDaysAgo, name: "RENT PAYMENT", merchantName: "Landlord", category: .billsAndUtilities),
        ]

        isSetupComplete = true
        serverConnected = true
        lastSyncDate = Date()
    }

    private static func dateString(daysAgo: Int) -> String {
        let date = Calendar.current.date(byAdding: .day, value: -daysAgo, to: Date())!
        return Formatters.transactionDateString(date)
    }
}

enum PopoverTab: String, CaseIterable, Sendable {
    case accounts = "Accounts"
    case transactions = "Transactions"
    case spending = "Spending"
    case credit = "Credit"
}
