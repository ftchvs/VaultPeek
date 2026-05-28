import SwiftUI
import PlaidBarCore
import Combine

@Observable
@MainActor
final class AppState {
    // MARK: - UserDefaults Keys
    private enum Keys {
        static let showBalanceInMenuBar = "showBalanceInMenuBar"
        static let menuBarSummaryMode = "menuBarSummaryMode"
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
    var serverEnvironment: PlaidEnvironment?
    var serverVersion: String?
    var serverItemCount: Int?
    var serverCredentialsConfigured: Bool?
    var serverStoragePath: String?
    var serverSyncReady: Bool?
    var itemStatuses: [ItemStatus] = []
    var isDemoMode = false
    var lastSyncDate: Date?
    var balanceHistory: [BalanceSnapshot] = []

    // MARK: - Settings (persisted to UserDefaults)
    var menuBarSummaryMode: MenuBarSummaryMode = .netCash {
        didSet {
            guard menuBarSummaryMode != oldValue else { return }
            UserDefaults.standard.set(menuBarSummaryMode.rawValue, forKey: Keys.menuBarSummaryMode)
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

    init(notificationService: (any NotificationServiceProtocol)? = nil) {
        self.notificationService = notificationService ?? NotificationService.shared
        loadSettings()
    }

    private func loadSettings() {
        let defaults = UserDefaults.standard
        if let mode = defaults.string(forKey: Keys.menuBarSummaryMode),
           let summaryMode = MenuBarSummaryMode(rawValue: mode) {
            menuBarSummaryMode = summaryMode
        } else if defaults.object(forKey: Keys.showBalanceInMenuBar) != nil,
                  !defaults.bool(forKey: Keys.showBalanceInMenuBar) {
            menuBarSummaryMode = .iconOnly
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
        MenuBarSummary.netCash(from: accounts)
    }

    var totalCash: Double {
        MenuBarSummary.totalCash(from: accounts)
    }

    var totalDebt: Double {
        MenuBarSummary.totalDebt(from: accounts)
    }

    var totalCreditUtilization: Double? {
        MenuBarSummary.creditUtilization(from: accounts)
    }

    var recentSpend: Double {
        MenuBarSummary.recentSpend(from: transactions)
    }

    var runwayMonthlySpend: Double {
        MenuBarSummary.runwayMonthlySpend(from: transactions)
    }

    var runwayMonths: Double? {
        MenuBarSummary.runwayMonths(cash: totalCash, monthlySpend: runwayMonthlySpend)
    }

    var runwayText: String {
        MenuBarSummary.runwayText(months: runwayMonths)
    }

    var runwayBasisText: String {
        MenuBarSummary.runwayBasisText(cash: totalCash, monthlySpend: runwayMonthlySpend)
    }

    var menuBarText: String {
        MenuBarSummary.text(
            mode: menuBarSummaryMode,
            accounts: accounts,
            transactions: transactions,
            currencyFormat: balanceFormat
        )
    }

    var menuBarAttentionText: String? {
        if isDemoMode { return nil }
        if error != nil || erroredItemCount > 0 { return "Error" }
        if !serverConnected { return "Offline" }
        if needsLoginItemCount > 0 { return "Login" }
        if isSyncStale { return lastSyncDate == nil ? "Never" : "Stale" }
        return nil
    }

    var menuBarHelpText: String {
        let status = "Status: \(diagnosticsSummary)"
        switch menuBarSummaryMode {
        case .netCash:
            return "PlaidBar - Net cash: \(menuBarText). \(status)"
        case .totalCash:
            return "PlaidBar - Total cash: \(menuBarText). \(status)"
        case .creditUtilization:
            return "PlaidBar - Credit utilization: \(menuBarText). \(status)"
        case .recentSpend:
            return "PlaidBar - Recent spend: \(menuBarText). \(status)"
        case .iconOnly:
            return "PlaidBar. \(status)"
        }
    }

    var menuBarAccessibilityLabel: String {
        let status = "Status \(diagnosticsSummary)"
        switch menuBarSummaryMode {
        case .netCash:
            return "PlaidBar net cash \(menuBarText). \(status)"
        case .totalCash:
            return "PlaidBar total cash \(menuBarText). \(status)"
        case .creditUtilization:
            return "PlaidBar credit utilization \(menuBarText). \(status)"
        case .recentSpend:
            return "PlaidBar recent spend \(menuBarText). \(status)"
        case .iconOnly:
            return "PlaidBar. \(status)"
        }
    }

    var lastSyncRelative: String? {
        guard let lastSyncDate else { return nil }
        return Formatters.relativeDate(lastSyncDate)
    }

    var statusModeText: String {
        if isDemoMode { return "Demo" }
        switch serverEnvironment {
        case .sandbox: return "Sandbox"
        case .production: return "Production"
        case nil: return "Unknown"
        }
    }

    var statusServerText: String {
        if isLoading { return "Syncing" }
        if error != nil { return "Error" }
        return serverConnected ? "Connected" : "Offline"
    }

    var statusItemCount: Int {
        if let serverItemCount { return serverItemCount }
        return Set(accounts.map(\.itemId)).count
    }

    var accountCount: Int {
        accounts.count
    }

    var transactionCount: Int {
        transactions.count
    }

    var localServerURLText: String {
        PlaidBarConstants.serverBaseURL
    }

    var localStoragePathText: String {
        LocalDataStore.displayPath
    }

    var localStorageDirectoryURL: URL {
        LocalDataStore.storageDirectoryURL()
    }

    var localStorageResolvedPathText: String {
        localStorageDirectoryURL.path
    }

    var serverStoragePathText: String {
        serverStoragePath ?? localStoragePathText
    }

    var serverStorageDisplayText: String {
        guard let serverStoragePath else { return localStoragePathText }
        return serverStoragePath.replacingOccurrences(of: NSHomeDirectory(), with: "~")
    }

    var serverCredentialsText: String {
        guard serverConnected else { return "Unknown" }
        return serverCredentialsConfigured == true ? "Ready" : "Missing"
    }

    var serverSyncReadinessText: String {
        guard serverConnected else { return "Unknown" }
        return serverSyncReady == true ? "Ready" : "No items"
    }

    var refreshCadenceText: String {
        "\(Int(refreshInterval / 60)) min"
    }

    var connectedItemCount: Int {
        itemStatuses.filter { $0.status == .connected }.count
    }

    var needsLoginItemCount: Int {
        itemStatuses.filter { $0.status == .loginRequired }.count
    }

    var erroredItemCount: Int {
        itemStatuses.filter { $0.status == .error }.count
    }

    var diagnosticsSummary: String {
        if isDemoMode { return "Demo data loaded" }
        if !serverConnected { return "Server offline" }
        if statusItemCount == 0 { return "No Plaid items connected" }
        if erroredItemCount > 0 { return "\(erroredItemCount) item\(erroredItemCount == 1 ? "" : "s") need attention" }
        if needsLoginItemCount > 0 { return "\(needsLoginItemCount) item\(needsLoginItemCount == 1 ? "" : "s") need login" }
        return "Plaid connection healthy"
    }

    var isSyncStale: Bool {
        guard let lastSyncDate else { return true }
        let staleAfter = max(refreshInterval * 2, PlaidBarConstants.transactionSyncInterval * 2)
        return Date().timeIntervalSince(lastSyncDate) > staleAfter
    }

    var statusSyncText: String {
        guard let lastSyncRelative else { return "Never synced" }
        return isSyncStale ? "Stale \(lastSyncRelative)" : "Synced \(lastSyncRelative)"
    }

    var creditAccounts: [AccountDTO] {
        accounts.filter { $0.type == .credit }
    }

    var loanAccounts: [AccountDTO] {
        accounts.filter { $0.type == .loan }
    }

    var debtAccounts: [AccountDTO] {
        accounts.filter(AccountPresentation.isDebt)
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
            serverEnvironment = status.environment
            serverVersion = status.version
            serverItemCount = status.itemCount
            serverCredentialsConfigured = status.credentialsConfigured
            serverStoragePath = status.storagePath
            serverSyncReady = status.syncReady
            lastSyncDate = status.lastSync
            isSetupComplete = status.itemCount > 0
            itemStatuses = (try? await serverClient.getItems()) ?? []
        } catch {
            serverConnected = false
            serverEnvironment = nil
            serverVersion = nil
            serverItemCount = nil
            serverCredentialsConfigured = nil
            serverStoragePath = nil
            serverSyncReady = nil
            itemStatuses = []
            isSetupComplete = false
        }
    }

    func refreshAccounts() async {
        isLoading = true
        error = nil
        do {
            accounts = try await serverClient.getAccounts()
            serverItemCount = Set(accounts.map(\.itemId)).count
            serverSyncReady = (serverItemCount ?? 0) > 0
            isSetupComplete = !accounts.isEmpty
            itemStatuses = (try? await serverClient.getItems()) ?? itemStatuses
        } catch {
            itemStatuses = (try? await serverClient.getItems()) ?? itemStatuses
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
            itemStatuses = (try? await serverClient.getItems()) ?? itemStatuses
            self.error = error.localizedDescription
        }
        isLoading = false
    }

    func syncTransactions() async {
        do {
            var hasMore = true
            var cachePersistenceError: Error?
            while hasMore {
                let response = try await serverClient.syncTransactions()
                transactions = TransactionSyncReducer.applying(response, to: transactions)
                do {
                    try LocalDataStore.saveTransactions(transactions, context: transactionCacheContext)
                } catch {
                    cachePersistenceError = error
                }
                hasMore = response.hasMore
            }
            lastSyncDate = Date()
            itemStatuses = (try? await serverClient.getItems()) ?? itemStatuses
            if let cachePersistenceError {
                self.error = "Transaction cache failed to save: \(cachePersistenceError.localizedDescription)"
            }
        } catch {
            itemStatuses = (try? await serverClient.getItems()) ?? itemStatuses
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

    func reconnectItem(itemId: String) async {
        do {
            let linkResponse = try await serverClient.createUpdateLinkToken(itemId: itemId)
            if let url = URL(string: linkResponse.linkUrl) {
                NSWorkspace.shared.open(url)
            }
        } catch {
            self.error = error.localizedDescription
        }
    }

    func startDemoMode() {
        isDemoMode = true
        loadDemoData()
    }

    func connectForOnboarding(expectedEnvironment: PlaidEnvironment) async -> Bool {
        error = nil
        await checkServerConnection()

        guard serverConnected else {
            switch expectedEnvironment {
            case .sandbox:
                error = "Start PlaidBarServer with --sandbox and sandbox credentials before connecting."
            case .production:
                error = "Start PlaidBarServer with production credentials before connecting real accounts."
            }
            return false
        }

        guard serverEnvironment == expectedEnvironment else {
            let currentMode = statusModeText.lowercased()
            switch expectedEnvironment {
            case .sandbox:
                error = "Server is running in \(currentMode), not sandbox. Restart with ./Scripts/run.sh --sandbox."
            case .production:
                error = "Server is running in \(currentMode), not production. Restart with ./Scripts/run.sh after Plaid production approval."
            }
            return false
        }

        await addAccount()
        return error == nil
    }

    func removeAccount(itemId: String) async {
        do {
            try await serverClient.removeItem(itemId: itemId)
            let removedItemId = itemId
            let removedAccountIds = Set(
                accounts.filter { $0.itemId == removedItemId }.map(\.id)
            )
            accounts.removeAll { $0.itemId == removedItemId }
            let fallbackItemCount = Set(accounts.map(\.itemId)).count
            if let refreshedItemStatuses = try? await serverClient.getItems() {
                itemStatuses = refreshedItemStatuses
                serverItemCount = refreshedItemStatuses.count
            } else {
                itemStatuses.removeAll { $0.id == removedItemId }
                serverItemCount = max(itemStatuses.count, fallbackItemCount)
            }
            let remainingItemCount = serverItemCount ?? 0
            serverSyncReady = remainingItemCount > 0
            isSetupComplete = remainingItemCount > 0
            if remainingItemCount == 0 {
                lastSyncDate = nil
            }
            transactions.removeAll { transaction in
                transaction.itemId == removedItemId ||
                    (transaction.itemId == nil && removedAccountIds.contains(transaction.accountId))
            }
            do {
                try LocalDataStore.saveTransactions(transactions, context: transactionCacheContext)
            } catch {
                self.error = "Transaction cache failed to save: \(error.localizedDescription)"
            }
        } catch {
            self.error = error.localizedDescription
        }
    }

    @discardableResult
    func resetLocalData() throws -> LocalDataResetResult {
        stopBackgroundRefresh()

        let result = try LocalDataStore.resetLocalData(at: localStorageDirectoryURL)

        accounts = []
        transactions = []
        itemStatuses = []
        serverItemCount = 0
        serverCredentialsConfigured = nil
        serverStoragePath = nil
        serverSyncReady = nil
        lastSyncDate = nil
        isSetupComplete = false
        isDemoMode = false
        error = nil

        balanceHistory = []
        UserDefaults.standard.removeObject(forKey: Keys.balanceHistory)
        notificationService.resetDeduplicationState()

        return result
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
            isDemoMode = true
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
            if statusItemCount > 0 {
                loadCachedTransactions()
            } else {
                clearCachedTransactions()
            }
            await refreshAccounts()
            await syncTransactions()
            startBackgroundRefresh()
        }
    }

    // MARK: - Balance History

    private func loadCachedTransactions() {
        do {
            transactions = try LocalDataStore.loadTransactions(context: transactionCacheContext)
        } catch {
            self.error = "Transaction cache failed to load: \(error.localizedDescription)"
        }
    }

    private func clearCachedTransactions() {
        transactions = []
        do {
            try LocalDataStore.saveTransactions(transactions, context: transactionCacheContext)
        } catch {
            self.error = "Transaction cache failed to clear: \(error.localizedDescription)"
        }
    }

    private var transactionCacheContext: TransactionCacheContext? {
        guard let serverEnvironment, let serverStoragePath else { return nil }
        return TransactionCacheContext(
            environment: serverEnvironment,
            storagePath: serverStoragePath
        )
    }

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
        transactions.append(contentsOf: Self.historicalDemoTransactions())

        // Generate demo balance history (60 days for richer sparkline)
        balanceHistory = (0..<60).reversed().map { daysAgo in
            let date = Calendar.current.date(byAdding: .day, value: -daysAgo, to: Date())!
            let jitter = Double.random(in: -800...800)
            return BalanceSnapshot(date: date, balance: 17_604.24 + jitter)
        }

        isSetupComplete = true
        isDemoMode = true
        serverConnected = true
        serverEnvironment = .sandbox
        serverVersion = PlaidBarConstants.appVersion
        serverItemCount = Set(accounts.map(\.itemId)).count
        serverCredentialsConfigured = true
        serverStoragePath = LocalDataStore.displayPath
        serverSyncReady = true
        itemStatuses = [
            ItemStatus(id: "demo_chase", institutionName: "Chase", status: .connected, lastSync: Date()),
            ItemStatus(id: "demo_amex_item", institutionName: "American Express", status: .connected, lastSync: Date()),
        ]
        lastSyncDate = Date()
    }

    private static func dateString(daysAgo: Int) -> String {
        let date = Calendar.current.date(byAdding: .day, value: -daysAgo, to: Date())!
        return Formatters.transactionDateString(date)
    }

    private static func historicalDemoTransactions() -> [TransactionDTO] {
        struct DemoMerchant {
            let interval: Int
            let offset: Int
            let accountId: String
            let amount: Double
            let name: String
            let merchantName: String
            let category: SpendingCategory
        }

        let merchants = [
            DemoMerchant(interval: 7, offset: 4, accountId: "demo_checking", amount: 78.40, name: "WHOLEFDS MKT 10234", merchantName: "Whole Foods", category: .foodAndDrink),
            DemoMerchant(interval: 10, offset: 6, accountId: "demo_amex", amount: 42.25, name: "SWEETGREEN", merchantName: "Sweetgreen", category: .foodAndDrink),
            DemoMerchant(interval: 14, offset: 9, accountId: "demo_checking", amount: 28.60, name: "UBER TRIP", merchantName: "Uber", category: .transportation),
            DemoMerchant(interval: 16, offset: 12, accountId: "demo_visa", amount: 63.15, name: "TARGET 0392", merchantName: "Target", category: .shopping),
            DemoMerchant(interval: 21, offset: 17, accountId: "demo_amex", amount: 118.90, name: "COSTCO WHOLESALE", merchantName: "Costco", category: .shopping),
            DemoMerchant(interval: 30, offset: 24, accountId: "demo_checking", amount: 132.00, name: "CON EDISON", merchantName: "Con Edison", category: .billsAndUtilities),
            DemoMerchant(interval: 31, offset: 30, accountId: "demo_checking", amount: 1_850.00, name: "RENT PAYMENT", merchantName: "Rent Payment", category: .billsAndUtilities),
            DemoMerchant(interval: 45, offset: 38, accountId: "demo_amex", amount: 310.00, name: "DELTA AIR LINES", merchantName: "Delta Airlines", category: .travel),
        ]

        return merchants.flatMap { merchant in
            stride(from: merchant.offset + 70, through: 364, by: merchant.interval).map { daysAgo in
                let merchantSlug = merchant.merchantName
                    .lowercased()
                    .replacingOccurrences(of: " ", with: "_")
                return TransactionDTO(
                    id: "demo_hist_\(merchantSlug)_\(daysAgo)",
                    accountId: merchant.accountId,
                    amount: merchant.amount + seasonalAdjustment(daysAgo: daysAgo, interval: merchant.interval),
                    date: dateString(daysAgo: daysAgo),
                    name: merchant.name,
                    merchantName: merchant.merchantName,
                    category: merchant.category
                )
            }
        }
    }

    private static func seasonalAdjustment(daysAgo: Int, interval: Int) -> Double {
        let cycle = Double((daysAgo / max(interval, 1)) % 5)
        return cycle * 8.75
    }
}

enum PopoverTab: String, CaseIterable, Sendable {
    case accounts = "Accounts"
    case transactions = "Transactions"
    case spending = "Spending"
    case credit = "Credit"
    case status = "Status"
}
