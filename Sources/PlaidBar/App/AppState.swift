import SwiftUI
import PlaidBarCore
import Combine

@Observable
@MainActor
final class AppState {
    // MARK: - UserDefaults Keys
    private enum Keys {
        static let showBalanceInMenuBar = "showBalanceInMenuBar"
        static let balanceFormat = "balanceFormat"
        static let creditUtilizationThreshold = "creditUtilizationThreshold"
        static let refreshInterval = "refreshInterval"
        static let balanceHistory = "balanceHistory"
        static let notificationsEnabled = "notificationsEnabled"
        static let largeTransactionThreshold = "largeTransactionThreshold"
        static let lowBalanceThreshold = "lowBalanceThreshold"
        static let notifyLargeTransaction = "notifyLargeTransaction"
        static let notifyLowBalance = "notifyLowBalance"
        static let notifyHighUtilization = "notifyHighUtilization"
    }

    // MARK: - State
    var accounts: [AccountDTO] = []
    var transactions: [TransactionDTO] = [] {
        didSet { _cachedRecurringTransactions = nil }
    }
    var isLoading = false
    var error: String?
    var isPopoverPresented = false
    var selectedTab: PopoverTab = .accounts
    var isSetupComplete = false
    var serverConnected = false
    var lastSyncDate: Date?
    var balanceHistory: [BalanceSnapshot] = []

    // MARK: - Settings (persisted to UserDefaults)
    var showBalanceInMenuBar: Bool = true {
        didSet {
            guard showBalanceInMenuBar != oldValue else { return }
            UserDefaults.standard.set(showBalanceInMenuBar, forKey: Keys.showBalanceInMenuBar)
        }
    }
    var balanceFormat: CurrencyFormat = .abbreviated {
        didSet {
            guard balanceFormat != oldValue else { return }
            UserDefaults.standard.set(balanceFormat.rawValue, forKey: Keys.balanceFormat)
        }
    }
    var creditUtilizationThreshold: Double = 30.0 {
        didSet {
            guard creditUtilizationThreshold != oldValue else { return }
            UserDefaults.standard.set(creditUtilizationThreshold, forKey: Keys.creditUtilizationThreshold)
        }
    }
    var refreshInterval: TimeInterval = PlaidBarConstants.backgroundRefreshInterval {
        didSet {
            guard refreshInterval != oldValue else { return }
            UserDefaults.standard.set(refreshInterval, forKey: Keys.refreshInterval)
            // Restart background refresh with new interval
            if refreshTask != nil { startBackgroundRefresh() }
        }
    }
    var notificationsEnabled: Bool = false {
        didSet {
            guard notificationsEnabled != oldValue else { return }
            UserDefaults.standard.set(notificationsEnabled, forKey: Keys.notificationsEnabled)
        }
    }
    var largeTransactionThreshold: Double = 500.0 {
        didSet {
            guard largeTransactionThreshold != oldValue else { return }
            UserDefaults.standard.set(largeTransactionThreshold, forKey: Keys.largeTransactionThreshold)
        }
    }
    var lowBalanceThreshold: Double = 100.0 {
        didSet {
            guard lowBalanceThreshold != oldValue else { return }
            UserDefaults.standard.set(lowBalanceThreshold, forKey: Keys.lowBalanceThreshold)
        }
    }
    var notifyLargeTransaction: Bool = true {
        didSet {
            guard notifyLargeTransaction != oldValue else { return }
            UserDefaults.standard.set(notifyLargeTransaction, forKey: Keys.notifyLargeTransaction)
        }
    }
    var notifyLowBalance: Bool = true {
        didSet {
            guard notifyLowBalance != oldValue else { return }
            UserDefaults.standard.set(notifyLowBalance, forKey: Keys.notifyLowBalance)
        }
    }
    var notifyHighUtilization: Bool = true {
        didSet {
            guard notifyHighUtilization != oldValue else { return }
            UserDefaults.standard.set(notifyHighUtilization, forKey: Keys.notifyHighUtilization)
        }
    }

    var launchAtLogin: Bool = false {
        didSet {
            guard launchAtLogin != oldValue else { return }
            do {
                try LaunchService.setEnabled(launchAtLogin)
            } catch {
                self.error = "Launch at login failed: \(error.localizedDescription)"
                launchAtLogin = oldValue
            }
        }
    }

    // MARK: - Services
    private let serverClient = ServerClient()
    private let notificationService: any NotificationServiceProtocol
    private var refreshTask: Task<Void, Never>?

    // MARK: - Init

    init(notificationService: any NotificationServiceProtocol = NotificationService.shared) {
        self.notificationService = notificationService
        loadSettings()
    }

    private func loadSettings() {
        let defaults = UserDefaults.standard
        if defaults.object(forKey: Keys.showBalanceInMenuBar) != nil {
            showBalanceInMenuBar = defaults.bool(forKey: Keys.showBalanceInMenuBar)
        }
        if let format = defaults.string(forKey: Keys.balanceFormat),
           let f = CurrencyFormat(rawValue: format) {
            balanceFormat = f
        }
        if defaults.object(forKey: Keys.creditUtilizationThreshold) != nil {
            creditUtilizationThreshold = defaults.double(forKey: Keys.creditUtilizationThreshold)
        }
        if defaults.object(forKey: Keys.refreshInterval) != nil {
            refreshInterval = defaults.double(forKey: Keys.refreshInterval)
        }
        // Notification settings
        if defaults.object(forKey: Keys.notificationsEnabled) != nil {
            notificationsEnabled = defaults.bool(forKey: Keys.notificationsEnabled)
        }
        if defaults.object(forKey: Keys.largeTransactionThreshold) != nil {
            largeTransactionThreshold = defaults.double(forKey: Keys.largeTransactionThreshold)
        }
        if defaults.object(forKey: Keys.lowBalanceThreshold) != nil {
            lowBalanceThreshold = defaults.double(forKey: Keys.lowBalanceThreshold)
        }
        if defaults.object(forKey: Keys.notifyLargeTransaction) != nil {
            notifyLargeTransaction = defaults.bool(forKey: Keys.notifyLargeTransaction)
        }
        if defaults.object(forKey: Keys.notifyLowBalance) != nil {
            notifyLowBalance = defaults.bool(forKey: Keys.notifyLowBalance)
        }
        if defaults.object(forKey: Keys.notifyHighUtilization) != nil {
            notifyHighUtilization = defaults.bool(forKey: Keys.notifyHighUtilization)
        }
        // Balance history
        if let data = defaults.data(forKey: Keys.balanceHistory),
           let history = try? JSONDecoder().decode([BalanceSnapshot].self, from: data) {
            balanceHistory = history
        }
        // Launch at login
        launchAtLogin = LaunchService.isEnabled
    }

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

    /// Cached recurring detection — invalidated via transactions.didSet
    private var _cachedRecurringTransactions: [RecurringTransaction]?

    var recurringTransactions: [RecurringTransaction] {
        if let cached = _cachedRecurringTransactions { return cached }
        let result = RecurringDetector.detect(from: transactions)
        _cachedRecurringTransactions = result
        return result
    }

    /// Monthly equivalent of all recurring charges (normalizes weekly/annual to monthly)
    var estimatedMonthlyRecurring: Double {
        recurringTransactions.reduce(0) { $0 + $1.averageAmount * $1.frequency.monthlyMultiplier }
    }

    func transactionsForAccount(_ accountId: String) -> [TransactionDTO] {
        transactions.filter { $0.accountId == accountId }
            .sorted { $0.date > $1.date }
    }

    func transactionsForMerchant(_ merchantName: String, excluding transactionId: String) -> [TransactionDTO] {
        transactions.filter { $0.merchantName == merchantName && $0.id != transactionId }
            .sorted { $0.date > $1.date }
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
            recordBalanceSnapshot()
        } catch {
            self.error = error.localizedDescription
        }
        isLoading = false
    }

    func syncTransactions() async {
        do {
            var hasMore = true
            while hasMore {
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
                let removedIds = Set(response.removed)
                transactions.removeAll { removedIds.contains($0.id) }
                hasMore = response.hasMore
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
                await evaluateNotifications()
                try? await Task.sleep(for: .seconds(refreshInterval))
            }
        }
    }

    private func evaluateNotifications() async {
        guard notificationsEnabled else { return }
        let config = NotificationTriggers(
            largeTransaction: notifyLargeTransaction,
            lowBalance: notifyLowBalance,
            highUtilization: notifyHighUtilization,
            largeTransactionThreshold: largeTransactionThreshold,
            lowBalanceThreshold: lowBalanceThreshold,
            creditUtilizationThreshold: creditUtilizationThreshold
        )
        await notificationService.evaluateTriggers(
            transactions: transactions,
            accounts: accounts,
            config: config
        )
    }

    func requestNotificationPermission() async -> Bool {
        await notificationService.requestPermission()
    }

    func stopBackgroundRefresh() {
        refreshTask?.cancel()
        refreshTask = nil
    }

    func loadInitialData() async {
        // Recheck notification permission at startup (user may have revoked in System Settings)
        if notificationsEnabled {
            let status = await notificationService.checkPermissionStatus()
            if status == .denied || status == .notDetermined {
                notificationsEnabled = false
            }
        }

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

    // MARK: - Balance History

    private func recordBalanceSnapshot() {
        let snapshot = BalanceSnapshot(date: Date(), balance: netBalance)
        balanceHistory.append(snapshot)
        // Keep last 90 days
        let cutoff = Calendar.current.date(byAdding: .day, value: -90, to: Date()) ?? Date()
        balanceHistory.removeAll { $0.date < cutoff }
        // Persist
        if let data = try? JSONEncoder().encode(balanceHistory) {
            UserDefaults.standard.set(data, forKey: Keys.balanceHistory)
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

        let oneWeekAgo = Self.dateString(daysAgo: 8)
        let twoWeeksAgo = Self.dateString(daysAgo: 15)
        let threeWeeksAgo = Self.dateString(daysAgo: 22)
        let oneMonthAgo = Self.dateString(daysAgo: 30)
        let fiveWeeksAgo = Self.dateString(daysAgo: 35)
        let sixWeeksAgo = Self.dateString(daysAgo: 42)
        let twoMonthsAgo = Self.dateString(daysAgo: 60)

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
            TransactionDTO(id: "tx12", accountId: "demo_amex", amount: 650.00, date: twoDaysAgo, name: "FURNITURE STORE", merchantName: "West Elm", category: .shopping, pending: true),
            // 3 days ago
            TransactionDTO(id: "tx13", accountId: "demo_visa", amount: 75.00, date: threeDaysAgo, name: "PLANET FITNESS", merchantName: "Planet Fitness", category: .healthAndFitness),
            TransactionDTO(id: "tx14", accountId: "demo_checking", amount: -1_500.00, date: threeDaysAgo, name: "VENMO PAYMENT", merchantName: "Venmo", category: .income),
            TransactionDTO(id: "tx15", accountId: "demo_amex", amount: 55.00, date: threeDaysAgo, name: "TARGET 0392", merchantName: "Target", category: .shopping),
            TransactionDTO(id: "tx16", accountId: "demo_checking", amount: 1_850.00, date: threeDaysAgo, name: "RENT PAYMENT", merchantName: "Rent Payment", category: .billsAndUtilities),
            // ~1 week ago
            TransactionDTO(id: "tx17", accountId: "demo_checking", amount: 85.00, date: oneWeekAgo, name: "COSTCO WHOLESALE", merchantName: "Costco", category: .shopping),
            TransactionDTO(id: "tx18", accountId: "demo_amex", amount: 220.00, date: oneWeekAgo, name: "AIRBNB", merchantName: "Airbnb", category: .travel),
            TransactionDTO(id: "tx19", accountId: "demo_checking", amount: -2_800.00, date: oneWeekAgo, name: "DIRECT DEPOSIT", merchantName: "Employer", category: .income),
            TransactionDTO(id: "tx20", accountId: "demo_visa", amount: 42.00, date: oneWeekAgo, name: "DOORDASH", merchantName: "DoorDash", category: .foodAndDrink),
            // ~2 weeks ago
            TransactionDTO(id: "tx21", accountId: "demo_checking", amount: 130.00, date: twoWeeksAgo, name: "CON EDISON", merchantName: "Con Edison", category: .billsAndUtilities),
            TransactionDTO(id: "tx22", accountId: "demo_amex", amount: 64.99, date: twoWeeksAgo, name: "ADOBE CREATIVE", merchantName: "Adobe", category: .entertainment),
            TransactionDTO(id: "tx23", accountId: "demo_checking", amount: 95.00, date: twoWeeksAgo, name: "CVS PHARMACY", merchantName: "CVS", category: .healthAndFitness),
            // ~3 weeks ago
            TransactionDTO(id: "tx24", accountId: "demo_visa", amount: 175.00, date: threeWeeksAgo, name: "NORDSTROM", merchantName: "Nordstrom", category: .shopping),
            TransactionDTO(id: "tx25", accountId: "demo_checking", amount: 48.00, date: threeWeeksAgo, name: "LYFT RIDE", merchantName: "Lyft", category: .transportation),
            TransactionDTO(id: "tx26", accountId: "demo_amex", amount: 35.00, date: threeWeeksAgo, name: "HULU", merchantName: "Hulu", category: .entertainment),

            // === ~1 month ago — recurring merchants (2nd occurrence) ===
            TransactionDTO(id: "tx27", accountId: "demo_checking", amount: 15.99, date: oneMonthAgo, name: "NETFLIX.COM", merchantName: "Netflix", category: .entertainment),
            TransactionDTO(id: "tx28", accountId: "demo_visa", amount: 34.50, date: oneMonthAgo, name: "SPOTIFY", merchantName: "Spotify", category: .entertainment),
            TransactionDTO(id: "tx29", accountId: "demo_visa", amount: 75.00, date: oneMonthAgo, name: "PLANET FITNESS", merchantName: "Planet Fitness", category: .healthAndFitness),
            TransactionDTO(id: "tx30", accountId: "demo_checking", amount: 1_850.00, date: oneMonthAgo, name: "RENT PAYMENT", merchantName: "Rent Payment", category: .billsAndUtilities),
            TransactionDTO(id: "tx31", accountId: "demo_checking", amount: -2_800.00, date: oneMonthAgo, name: "DIRECT DEPOSIT", merchantName: "Employer", category: .income),
            TransactionDTO(id: "tx32", accountId: "demo_checking", amount: 72.00, date: fiveWeeksAgo, name: "WHOLEFDS MKT 10234", merchantName: "Whole Foods", category: .foodAndDrink),
            TransactionDTO(id: "tx33", accountId: "demo_amex", amount: 38.00, date: fiveWeeksAgo, name: "HULU", merchantName: "Hulu", category: .entertainment),
            TransactionDTO(id: "tx34", accountId: "demo_amex", amount: 64.99, date: sixWeeksAgo, name: "ADOBE CREATIVE", merchantName: "Adobe", category: .entertainment),

            // === ~2 months ago — recurring merchants (3rd occurrence) ===
            TransactionDTO(id: "tx35", accountId: "demo_checking", amount: 15.99, date: twoMonthsAgo, name: "NETFLIX.COM", merchantName: "Netflix", category: .entertainment),
            TransactionDTO(id: "tx36", accountId: "demo_visa", amount: 34.50, date: twoMonthsAgo, name: "SPOTIFY", merchantName: "Spotify", category: .entertainment),
            TransactionDTO(id: "tx37", accountId: "demo_visa", amount: 75.00, date: twoMonthsAgo, name: "PLANET FITNESS", merchantName: "Planet Fitness", category: .healthAndFitness),
            TransactionDTO(id: "tx38", accountId: "demo_checking", amount: 1_850.00, date: twoMonthsAgo, name: "RENT PAYMENT", merchantName: "Rent Payment", category: .billsAndUtilities),
            TransactionDTO(id: "tx39", accountId: "demo_checking", amount: -2_800.00, date: twoMonthsAgo, name: "DIRECT DEPOSIT", merchantName: "Employer", category: .income),
            TransactionDTO(id: "tx40", accountId: "demo_amex", amount: 64.99, date: twoMonthsAgo, name: "ADOBE CREATIVE", merchantName: "Adobe", category: .entertainment),
            TransactionDTO(id: "tx41", accountId: "demo_amex", amount: 36.00, date: twoMonthsAgo, name: "HULU", merchantName: "Hulu", category: .entertainment),
        ]

        // Generate demo balance history (60 days for richer sparkline)
        balanceHistory = (0..<60).reversed().map { daysAgo in
            let date = Calendar.current.date(byAdding: .day, value: -daysAgo, to: Date())!
            let jitter = Double.random(in: -800...800)
            return BalanceSnapshot(date: date, balance: 17_604.24 + jitter)
        }

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
