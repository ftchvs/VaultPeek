import SwiftUI
import PlaidBarCore
import Combine
@preconcurrency import UserNotifications

@Observable
@MainActor
final class AppState {
    // MARK: - UserDefaults Keys
    private enum Keys {
        static let showBalanceInMenuBar = "showBalanceInMenuBar"
        static let menuBarSummaryMode = "menuBarSummaryMode"
        static let menuBarIconStyle = "menuBarIconStyle"
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
        static let setupCompletedOnce = "setup.completedOnce"
        static let setupCompletedContextPrefix = "setup.completedOnce.context"
        static let lastTransactionCacheContext = "cache.lastTransactionCacheContext"
        static let dashboardDetached = DetachedDashboardPreferences.detachedStorageKey
    }

    // MARK: - State
    var accounts: [AccountDTO] = [] {
        didSet { invalidateLocalAIActivitySummaries() }
    }
    var transactions: [TransactionDTO] = [] {
        didSet {
            _cachedRecurringTransactions = nil
            invalidateLocalAIActivitySummaries()
        }
    }
    var isLoading = false
    /// True from launch until the first `loadInitialData()` pass completes.
    /// While booting, data surfaces render loading/skeleton states instead
    /// of offline or empty verdicts — the first connectivity check has not
    /// delivered a verdict yet.
    var isBooting = true
    var error: String? {
        didSet {
            guard let error else { return }
            let sanitized = UserFacingError.sanitizedDetail(from: error)
            guard sanitized != error else { return }
            self.error = sanitized
        }
    }
    var isPopoverPresented = false

    /// When true, the dashboard lives in a floating desktop window instead of
    /// the menu-bar popover (AND-384). Persisted so the window reopens on the
    /// next launch. While detached, a click on the menu-bar item raises the
    /// floating window rather than opening the popover; re-docking flips this
    /// back to false and the popover resumes. Mirrors the `dashboard.detached`
    /// `@AppStorage` key the Settings toggle writes, so the toggle and the
    /// in-dashboard pin/re-dock controls stay in sync.
    var isDashboardDetached = false {
        didSet {
            guard isDashboardDetached != oldValue else { return }
            UserDefaults.standard.set(isDashboardDetached, forKey: Keys.dashboardDetached)
        }
    }

    /// Persisted across launches so configured installs boot straight into
    /// the dashboard instead of flashing first-run onboarding until the
    /// initial server handshake completes. Demo sessions never persist
    /// completion; explicit resets clear it.
    var isSetupComplete = false {
        didSet {
            guard oldValue != isSetupComplete else { return }
            persistSetupCompletion(isSetupComplete)
        }
    }
    var serverConnected = false
    var serverEnvironment: PlaidEnvironment?
    var serverVersion: String?
    var serverItemCount: Int?
    var serverCredentialsConfigured: Bool?
    var serverStoragePath: String?
    var serverSyncReady: Bool?
    var serverSyncedItemCount: Int?
    var itemStatuses: [ItemStatus] = []
    var isDemoMode = false
    var isDemoStatusRecoveryScenario = false
    var lastSyncDate: Date?
    var balanceHistory: [BalanceSnapshot] = []
    var notificationPermissionState: NotificationPermissionState = .notDetermined

    // MARK: - Settings (persisted to UserDefaults)
    var menuBarSummaryMode: MenuBarSummaryMode = .netWorth {
        didSet {
            guard menuBarSummaryMode != oldValue else { return }
            UserDefaults.standard.set(menuBarSummaryMode.rawValue, forKey: Keys.menuBarSummaryMode)
        }
    }
    var menuBarIconStyle: MenuBarIconStyle = .classic {
        didSet {
            guard menuBarIconStyle != oldValue else { return }
            UserDefaults.standard.set(menuBarIconStyle.rawValue, forKey: Keys.menuBarIconStyle)
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
            let normalizedInterval = PlaidBarConstants.normalizedBackgroundRefreshInterval(refreshInterval)
            guard normalizedInterval == refreshInterval else {
                refreshInterval = normalizedInterval
                return
            }
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
    private let localDataCache = LocalDataCacheService()
    private let localAIInsightsService = LocalAIInsightsService()
    private let notificationService: any NotificationServiceProtocol
    private var refreshTask: Task<Void, Never>?
    private var localAISummaryRefreshTask: Task<Void, Never>?
    private var isUpgradingManagedServer = false
    private var isStartingBundledServer = false
    private var lastAttemptedCredentialUpgradeConfig: String?

    // MARK: - Init

    init(notificationService: (any NotificationServiceProtocol)? = nil) {
        _ = try? LocalDataStore.migrateLegacyDefaultStorageIfNeeded()
        self.notificationService = notificationService ?? NotificationService.shared
        loadSettings()
        isSetupComplete = storedSetupCompletion()
        if isSetupComplete {
            persistSetupCompletion(true)
        }
        // Demo loads its fixtures synchronously HERE — before `MainPopover`'s
        // first paint — so the popover opens directly in the populated dashboard
        // at its settled width. Demo never persists setup completion
        // (`persistSetupCompletion` no-ops in demo), so deferring this to
        // `loadInitialData()` (a post-paint `.task`) made frame 1 render the
        // 480pt setup screen and then resize to the 801pt dashboard, which read
        // as a flicker/redraw on open. Production stays deferred to `.task`.
        if CommandLine.arguments.contains("--demo") {
            loadDemoData()
        }
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
        if let style = defaults.string(forKey: Keys.menuBarIconStyle),
           let iconStyle = MenuBarIconStyle(rawValue: style) {
            menuBarIconStyle = iconStyle
        }
        if let format = defaults.string(forKey: Keys.balanceFormat),
           let f = CurrencyFormat(rawValue: format) {
            balanceFormat = f
        }
        if defaults.object(forKey: Keys.creditUtilizationThreshold) != nil {
            creditUtilizationThreshold = defaults.double(forKey: Keys.creditUtilizationThreshold)
        }
        if defaults.object(forKey: Keys.refreshInterval) != nil {
            refreshInterval = PlaidBarConstants.normalizedBackgroundRefreshInterval(
                defaults.double(forKey: Keys.refreshInterval)
            )
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
        loadPersistedBalanceHistory()
        // Launch at login
        launchAtLogin = LaunchService.isEnabled
        // Detached-dashboard intent (AND-384). A headless snapshot render
        // ignores the persisted intent so the popover-capture path stays
        // deterministic regardless of host/CI defaults — otherwise a stale
        // `dashboard.detached = true` would spawn the floating window and
        // intercept the renderer's popover open. The stored value is left
        // untouched (no write-back) so the real user preference survives.
        let storedDetached = defaults.object(forKey: Keys.dashboardDetached) != nil
            ? defaults.bool(forKey: Keys.dashboardDetached)
            : nil
        isDashboardDetached = DetachedDashboardPreferences.resolvedDetachedIntent(
            storedValue: storedDetached,
            isRenderingSnapshot: CommandLineOptions.isRenderingSnapshot()
        )
    }

    // MARK: - Computed

    /// True while the launch handshake is still running for a real (non-demo)
    /// session. Demo data loads synchronously and never boots into skeletons.
    var isBootLoadInFlight: Bool {
        isBooting && !isDemoMode
    }

    /// Load-phase presenter per data surface. Surfaces with content keep
    /// rendering it; surfaces without content show a skeleton while the
    /// first fetch is in flight instead of offline/empty copy.
    func loadState(for surface: DashboardLoadSurface) -> DashboardLoadState {
        DashboardLoadState.evaluate(
            surface: surface,
            isDemoMode: isDemoMode,
            isBooting: isBooting,
            isLoading: isLoading,
            serverConnected: serverConnected,
            hasContent: hasContent(for: surface),
            errorMessage: error
        )
    }

    private func hasContent(for surface: DashboardLoadSurface) -> Bool {
        switch surface {
        case .menuBarSummary, .summaryCards, .accounts, .credit:
            accountCount > 0
        case .transactions, .spending, .recurring, .activityHeatmap:
            transactionCount > 0
        }
    }

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
            currencyFormat: balanceFormat,
            isInitialLoad: isBootLoadInFlight
        )
    }

    var menuBarStatusPresentation: MenuBarStatusPresentation {
        MenuBarStatusPresentation.evaluate(
            isDemoMode: isDemoMode,
            isInitialLoad: isBootLoadInFlight,
            isLoading: isLoading,
            serverConnected: serverConnected,
            errorMessage: error,
            erroredItemCount: erroredItemCount,
            needsLoginItemCount: needsLoginItemCount,
            isSyncStale: isSyncStale,
            hasEverSynced: lastSyncDate != nil,
            financialAttentionText: attentionQueue.rows.first?.menuBarAttentionText,
            iconStyle: menuBarIconStyle
        )
    }

    var menuBarAttentionText: String? {
        menuBarStatusPresentation.attentionText
    }

    var menuBarHelpText: String {
        let status = "Status: \(diagnosticsSummary)"
        switch menuBarSummaryMode {
        case .netWorth:
            return "VaultPeek - Net worth: \(menuBarText). \(status)"
        case .netCash:
            return "VaultPeek - Net cash: \(menuBarText). \(status)"
        case .totalCash:
            return "VaultPeek - Total cash: \(menuBarText). \(status)"
        case .creditUtilization:
            return "VaultPeek - Credit utilization: \(menuBarText). \(status)"
        case .recentSpend:
            return "VaultPeek - Recent spend: \(menuBarText). \(status)"
        case .iconOnly:
            return "VaultPeek. \(status)"
        }
    }

    var menuBarAccessibilityLabel: String {
        let status = "Status \(diagnosticsSummary)"
        switch menuBarSummaryMode {
        case .netWorth:
            return "VaultPeek net worth \(menuBarText). \(status)"
        case .netCash:
            return "VaultPeek net cash \(menuBarText). \(status)"
        case .totalCash:
            return "VaultPeek total cash \(menuBarText). \(status)"
        case .creditUtilization:
            return "VaultPeek credit utilization \(menuBarText). \(status)"
        case .recentSpend:
            return "VaultPeek recent spend \(menuBarText). \(status)"
        case .iconOnly:
            return "VaultPeek. \(status)"
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
        serverConnectionPresentation.statusText
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

    var localStorageResolvedDisplayPathText: String {
        LocalDataStore.displayPath(for: localStorageDirectoryURL)
    }

    var serverStoragePathText: String {
        serverStoragePath ?? localStoragePathText
    }

    var serverStorageDisplayText: String {
        guard let serverStoragePath else { return localStoragePathText }
        return LocalDataStore.displayPath(for: URL(fileURLWithPath: NSString(string: serverStoragePath).expandingTildeInPath))
    }

    var activeStorageDirectoryURL: URL {
        LocalDataStore.storageDirectoryURL(
            forServerStoragePath: serverStoragePath,
            fallback: localStorageDirectoryURL
        )
    }

    var activeStorageDirectoryDisplayText: String {
        LocalDataStore.displayPath(for: activeStorageDirectoryURL)
    }

    var serverCredentialsText: String {
        if isDemoMode { return "Not required" }
        guard serverConnected else { return "Unknown" }
        return serverCredentialsConfigured == true ? "Ready" : "Missing"
    }

    var serverSyncReadinessText: String {
        if isDemoMode { return "Demo data" }
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

    var degradedItemIds: Set<String> {
        Set(
            itemStatuses
                .filter { $0.status == .loginRequired || $0.status == .error }
                .map(\.id)
        )
    }

    var diagnosticsSummary: String {
        if isDemoStatusRecoveryScenario {
            if erroredItemCount > 0 { return "\(erroredItemCount) demo item\(erroredItemCount == 1 ? "" : "s") need attention" }
            if needsLoginItemCount > 0 { return "\(needsLoginItemCount) demo item\(needsLoginItemCount == 1 ? "" : "s") need login" }
        }
        let serverPresentation = serverConnectionPresentation
        if isDemoMode { return serverPresentation.diagnosticsSummary }
        switch serverPresentation.issue {
        case .offline, .localAuthMissing, .localAuthRejected, .serverModeMismatch:
            return serverPresentation.diagnosticsSummary
        case .demo, .syncing, .connected, .error:
            break
        }
        if statusItemCount == 0 { return "No Plaid items connected" }
        if erroredItemCount > 0 { return "\(erroredItemCount) item\(erroredItemCount == 1 ? "" : "s") need attention" }
        if needsLoginItemCount > 0 { return "\(needsLoginItemCount) item\(needsLoginItemCount == 1 ? "" : "s") need login" }
        if serverPresentation.issue == .error { return serverPresentation.diagnosticsSummary }
        return "Plaid connection healthy"
    }

    private var serverConnectionPresentation: ServerConnectionPresentation {
        ServerConnectionPresentation.evaluate(
            isDemoMode: isDemoMode,
            isInitialLoad: isBootLoadInFlight,
            isLoading: isLoading,
            serverConnected: serverConnected,
            errorMessage: error
        )
    }

    func onboardingPreflight(for environment: PlaidEnvironment) -> OnboardingPreflight {
        OnboardingPreflight.evaluate(
            expectedEnvironment: environment,
            serverConnected: serverConnected,
            serverEnvironment: serverEnvironment,
            credentialsConfigured: serverCredentialsConfigured,
            modeText: statusModeText,
            credentialsText: serverCredentialsText,
            storageText: activeStorageDirectoryDisplayText,
            linkedItemCount: statusItemCount
        )
    }

    var firstRunCompletionState: FirstRunCompletionState {
        FirstRunCompletionState.evaluate(
            isDemoMode: isDemoMode,
            serverConnected: serverConnected,
            linkedItemCount: statusItemCount,
            accountCount: accountCount,
            transactionCount: transactionCount,
            syncedItemCount: serverSyncedItemCount ?? 0,
            errorMessage: error
        )
    }

    var dashboardStatusReadiness: DashboardStatusReadiness {
        DashboardStatusReadiness.evaluate(
            isDemoMode: isDemoMode && !isDemoStatusRecoveryScenario,
            isInitialLoad: isBootLoadInFlight,
            serverConnected: serverConnected,
            credentialsConfigured: serverCredentialsConfigured,
            linkedItemCount: statusItemCount,
            accountCount: accountCount,
            syncedItemCount: serverSyncedItemCount ?? 0,
            needsLoginItemCount: needsLoginItemCount,
            erroredItemCount: erroredItemCount,
            isSyncStale: isSyncStale,
            lastSyncRelative: lastSyncRelative,
            errorMessage: error,
            notificationsEnabled: notificationsEnabled,
            notificationPermission: notificationPermissionPresentation
        )
    }

    var attentionQueue: AttentionQueue {
        AttentionQueue.evaluate(
            isDemoMode: isDemoMode && !isDemoStatusRecoveryScenario,
            serverConnected: serverConnected,
            credentialsConfigured: serverCredentialsConfigured,
            linkedItemCount: statusItemCount,
            accountCount: accountCount,
            syncedItemCount: serverSyncedItemCount ?? 0,
            itemStatuses: itemStatuses,
            isSyncStale: isSyncStale,
            lastSyncRelative: lastSyncRelative,
            errorMessage: error,
            accounts: accounts,
            transactions: transactions,
            lowCashThreshold: lowBalanceThreshold,
            largeTransactionThreshold: largeTransactionThreshold,
            creditUtilizationThreshold: creditUtilizationThreshold
        )
    }

    var notificationPermissionPresentation: NotificationPermissionPresentation {
        NotificationPermissionPresentation.evaluate(kind: notificationPermissionState.presentationKind)
    }

    var usesDemoConnectionPresentation: Bool {
        isDemoMode && !isDemoStatusRecoveryScenario
    }

    var isSyncStale: Bool {
        // Staleness is a verdict about completed syncs. During the boot
        // handshake the first sync is still in flight, so stale warnings
        // (menu bar badge, row tints, status strip) stay reserved for real
        // staleness measured after the check completes.
        if isBootLoadInFlight { return false }
        guard let lastSyncDate else { return true }
        let staleAfter = max(refreshInterval * 2, PlaidBarConstants.transactionSyncInterval * 2)
        return Date().timeIntervalSince(lastSyncDate) > staleAfter
    }

    var statusSyncText: String {
        if isBootLoadInFlight { return "Syncing" }
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
        SpendingSummary.spendingByCategory(from: transactions)
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
        RecurringSummary.estimatedMonthlyTotal(from: recurringTransactions, asOf: Date())
    }

    var localAIAvailability: LocalAIAvailability {
        if let generatedAvailability = _cachedLocalAIActivitySummaries?
            .first(where: { $0.window == .lastMonth })?
            .availability
        {
            return generatedAvailability
        }
        return localAIInsightsService.availability
    }

    /// Cached local summaries — invalidated via accounts.didSet and transactions.didSet.
    private var _cachedLocalAIActivitySummaries: [LocalAIActivitySummary]?

    var localAIActivitySummaries: [LocalAIActivitySummary] {
        if let cached = _cachedLocalAIActivitySummaries { return cached }
        let result = localAIInsightsService.activitySummaries(
            accounts: accounts,
            transactions: transactions,
            recurringTransactions: recurringTransactions
        )
        _cachedLocalAIActivitySummaries = result
        return result
    }

    private func invalidateLocalAIActivitySummaries() {
        _cachedLocalAIActivitySummaries = nil
        scheduleLocalAIActivitySummaryRefresh()
    }

    private func scheduleLocalAIActivitySummaryRefresh() {
        localAISummaryRefreshTask?.cancel()

        let accountSnapshot = accounts
        let transactionSnapshot = transactions
        guard !accountSnapshot.isEmpty || !transactionSnapshot.isEmpty else { return }

        let recurringSnapshot = recurringTransactions
        let service = localAIInsightsService
        localAISummaryRefreshTask = Task { [accountSnapshot, transactionSnapshot, recurringSnapshot, service] in
            // Debounce: a multi-page transaction sync reassigns `transactions`
            // once per page, and each assignment cancels and reschedules this
            // task. Waiting briefly first collapses that burst into a single
            // generation after the final page lands, instead of starting (and
            // abandoning) a local model call per page.
            do {
                try await Task.sleep(for: .milliseconds(400))
            } catch {
                return // cancelled during the debounce window — superseded
            }
            guard !Task.isCancelled else { return }

            let generated = await service.generatedActivitySummaries(
                accounts: accountSnapshot,
                transactions: transactionSnapshot,
                recurringTransactions: recurringSnapshot
            )
            guard !Task.isCancelled else { return }
            _cachedLocalAIActivitySummaries = generated
        }
    }

    func transactionsForAccount(_ accountId: String) -> [TransactionDTO] {
        accountActivitySnapshot(for: accountId).transactions
    }

    func accountActivitySnapshot(for accountId: String) -> AccountTransactionFeed.AccountActivitySnapshot {
        AccountTransactionFeed.activitySnapshot(forAccountId: accountId, in: transactions)
    }

    func transactionsForMerchant(_ merchantName: String, excluding transactionId: String) -> [TransactionDTO] {
        AccountTransactionFeed.relatedMerchantTransactions(
            merchantName: merchantName,
            excluding: transactionId,
            in: transactions
        )
    }

    // MARK: - Actions

    func checkServerConnection() async {
        do {
            let status = try await serverClient.getStatus()
            serverConnected = true
            error = nil
            serverEnvironment = status.environment
            serverVersion = status.version
            serverItemCount = status.itemCount
            serverCredentialsConfigured = status.credentialsConfigured
            serverStoragePath = status.storagePath
            serverSyncReady = status.syncReady
            serverSyncedItemCount = status.syncedItemCount
            lastSyncDate = status.lastSync
            persistTransactionCacheContext()
            refreshSetupCompletionForActiveContext()
            updateSetupCompletion()
            if !(await refreshItemStatuses()) {
                itemStatuses = []
                updateSetupCompletion()
            }
            await upgradeManagedServerIfCredentialsArrived()
        } catch {
            serverConnected = false
            serverEnvironment = nil
            serverVersion = nil
            serverItemCount = nil
            serverCredentialsConfigured = nil
            serverStoragePath = nil
            serverSyncReady = nil
            serverSyncedItemCount = nil
            itemStatuses = []
            switch error {
            case ServerClientError.serverNotRunning:
                // Expected pre-setup state, not an actionable error.
                self.error = nil
            case ServerClientError.authTokenUnavailable:
                // Demo mode has no server, so a missing token is expected
                // there — but when a real server is reachable a missing
                // token is actionable (e.g. PLAIDBAR_DATA_DIR mismatch)
                // and must stay visible.
                self.error = isDemoMode ? nil : error.localizedDescription
            default:
                // Demo mode has no server; never paint the demo dashboard
                // red over a connection probe.
                self.error = isDemoMode ? nil : error.localizedDescription
            }
            updateSetupCompletion()
            await recoverBundledServerIfNeeded()
        }
    }

    /// A managed server can exit right after launch when `server.conf` is
    /// broken in a way the pre-checks cannot see (for example an invalid
    /// `PLAID_ENV` that passed `configProvidesCredentials`). Re-attempt the
    /// launch plan on every failed connection check so "check again" and the
    /// background refresh recover once the user fixes the file, instead of
    /// requiring an app relaunch. Safe to run unconditionally: the plan
    /// declines outside an app bundle, in demo mode, and when any server is
    /// already reachable, and nothing is spawned while a managed process is
    /// still alive.
    private func recoverBundledServerIfNeeded() async {
        guard !isDemoMode, !isUpgradingManagedServer else { return }
        await startBundledServerIfAvailable()
    }

    func refreshAccounts() async {
        if refreshDemoDataIfNeeded() { return }

        isLoading = true
        error = nil
        do {
            let refreshedAccounts = try await serverClient.getAccounts()
            let itemStatusesAvailable = await refreshItemStatuses()
            accounts = itemStatusesAvailable
                ? accountsPreservingUnavailableItems(refreshedAccounts)
                : accountsPreservingCachedAccountsMissingFromRefresh(refreshedAccounts)
            let cacheAccounts = accounts
            let cacheDirectory = activeStorageDirectoryURL
            let cacheContext = transactionCacheContext
            try await localDataCache.saveAccounts(cacheAccounts, to: cacheDirectory, context: cacheContext)
            serverItemCount = Set(accounts.map(\.itemId)).count
            serverSyncReady = (serverItemCount ?? 0) > 0
            recordBalanceSnapshot()
            updateSetupCompletion()
        } catch {
            await refreshItemStatuses()
            self.error = error.localizedDescription
        }
        isLoading = false
    }

    func refreshBalances() async {
        if refreshDemoDataIfNeeded() { return }

        isLoading = true
        error = nil
        do {
            let refreshedAccounts = try await serverClient.getBalances()
            let itemStatusesAvailable = await refreshItemStatuses()
            accounts = itemStatusesAvailable
                ? accountsPreservingUnavailableItems(refreshedAccounts)
                : accountsPreservingCachedAccountsMissingFromRefresh(refreshedAccounts)
            let cacheAccounts = accounts
            let cacheDirectory = activeStorageDirectoryURL
            let cacheContext = transactionCacheContext
            try await localDataCache.saveAccounts(cacheAccounts, to: cacheDirectory, context: cacheContext)
            lastSyncDate = Date()
            recordBalanceSnapshot()
        } catch {
            await refreshItemStatuses()
            self.error = error.localizedDescription
        }
        isLoading = false
    }

    func syncTransactions() async {
        if refreshDemoDataIfNeeded() { return }

        do {
            var hasMore = true
            var pageCount = 0
            while hasMore {
                pageCount += 1
                guard pageCount <= PlaidBarConstants.maxTransactionSyncPages else {
                    throw AppStateError.transactionSyncPageLimitExceeded(
                        maxPages: PlaidBarConstants.maxTransactionSyncPages
                    )
                }
                let response = try await serverClient.syncTransactions()
                let updatedTransactions = TransactionSyncReducer.applying(response, to: transactions)
                // Assign before awaiting the cache write so a concurrent
                // reentrant mutation (e.g. removeAccount filtering
                // `transactions`) cannot be clobbered by the resumed sync
                // overwriting it with a value reduced from the pre-suspension
                // array. The cursor is still committed only after the cache
                // write succeeds, preserving local-first durability.
                transactions = updatedTransactions
                let cacheDirectory = activeStorageDirectoryURL
                let cacheContext = transactionCacheContext
                try await localDataCache.saveTransactions(
                    updatedTransactions,
                    to: cacheDirectory,
                    context: cacheContext
                )
                try await serverClient.commitSyncCursors(response.pendingCursors)
                hasMore = response.hasMore
            }
            lastSyncDate = Date()
            serverSyncedItemCount = statusItemCount
            await refreshItemStatuses()
            updateSetupCompletion()
        } catch {
            await refreshItemStatuses()
            self.error = error.localizedDescription
        }
    }

    func addAccount() async {
        error = nil

        if isDemoMode {
            isDemoMode = false
            isDemoStatusRecoveryScenario = false
            isSetupComplete = false
            serverConnected = false
            serverEnvironment = nil
            serverVersion = nil
            serverItemCount = nil
            serverCredentialsConfigured = nil
            serverStoragePath = nil
            serverSyncReady = nil
            serverSyncedItemCount = nil
            lastSyncDate = nil
            // Demo fixtures must not survive into real mode: a later refresh
            // preserves cached accounts missing from the server response, and
            // statusItemCount prefers serverItemCount, so stale demo rows and
            // counts would otherwise linger on the real dashboard.
            accounts = []
            transactions = []
            itemStatuses = []
            // loadDemoData() replaced the in-memory balance history with a
            // synthetic 60-day series. Restore persisted real history when it
            // exists so the first real snapshot cannot persist a demo trend.
            loadPersistedBalanceHistory()
            // Fall through into the real add-account flow: the demo readiness
            // card advertises "Connect Bank", so the first click must continue
            // into the server check + Plaid Link handoff (or surface the precise
            // server/credential blocker) instead of stranding the user in setup
            // and requiring a second click.
        }

        isLoading = true
        defer { isLoading = false }

        if !serverConnected {
            await checkServerConnection()
        }

        guard serverConnected else {
            error = "Start the VaultPeek companion server before adding an account."
            return
        }

        guard serverCredentialsConfigured != false else {
            error = "Plaid credentials are not configured on the VaultPeek companion server."
            return
        }

        do {
            let linkResponse = try await serverClient.createLinkToken()
            guard let url = URL(string: linkResponse.linkUrl) else {
                error = "The VaultPeek companion server returned an invalid Plaid Link URL."
                return
            }

            if !NSWorkspace.shared.open(url) {
                error = "Could not open Plaid Link in the browser."
            }
        } catch {
            self.error = error.localizedDescription
        }
    }

    func reconnectItem(itemId: String) async {
        guard !isDemoMode else {
            error = "Demo data is local. Connect a bank before reconnecting an institution."
            return
        }

        let institutionName = itemStatuses.first { $0.id == itemId }?.institutionName

        do {
            let linkResponse = try await serverClient.createUpdateLinkToken(itemId: itemId)
            guard let url = URL(string: linkResponse.linkUrl) else {
                error = ReconnectRecoveryMessage.invalidUpdateLinkURL(institutionName: institutionName)
                return
            }

            if !NSWorkspace.shared.open(url) {
                error = ReconnectRecoveryMessage.browserOpenFailed(institutionName: institutionName)
            }
        } catch {
            self.error = ReconnectRecoveryMessage.createFailed(
                errorMessage: error.localizedDescription,
                institutionName: institutionName
            )
        }
    }

    func startDemoMode() {
        isDemoMode = true
        loadDemoData()
    }

    func refreshDashboard() async {
        if refreshDemoDataIfNeeded() { return }

        await checkServerConnection()
        // Setup state (credentials missing) cannot refresh anything from
        // Plaid; the status surfaces guide the user instead of surfacing a
        // 503 banner on every cycle.
        if serverConnected, serverCredentialsConfigured != false {
            await refreshAccounts()
            await syncTransactions()
        }
    }

    func connectForOnboarding(expectedEnvironment: PlaidEnvironment) async -> Bool {
        error = nil
        await checkServerConnection()

        guard serverConnected else {
            switch expectedEnvironment {
            case .sandbox:
                error = "Start the VaultPeek companion server with --sandbox and sandbox credentials before connecting."
            case .production:
                error = "Start the VaultPeek companion server with production credentials before connecting real accounts."
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

        guard serverCredentialsConfigured == true else {
            switch expectedEnvironment {
            case .sandbox:
                error = "Sandbox Plaid credentials are missing on the VaultPeek companion server. Add PLAID_CLIENT_ID and PLAID_SECRET, then check again."
            case .production:
                error = "Production Plaid credentials are missing on the VaultPeek companion server. Add approved production credentials, then check again."
            }
            return false
        }

        await addAccount()
        return error == nil
    }

    @discardableResult
    func completeFirstRunCheck() async -> Bool {
        error = nil
        await checkServerConnection()

        guard serverConnected, statusItemCount > 0 else {
            updateSetupCompletion()
            return false
        }

        await refreshAccounts()

        guard !accounts.isEmpty else {
            updateSetupCompletion()
            return false
        }

        await syncTransactions()
        updateSetupCompletion()
        return firstRunCompletionState.isReady
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
            if !(await refreshItemStatuses()) {
                itemStatuses.removeAll { $0.id == removedItemId }
                serverItemCount = max(itemStatuses.count, fallbackItemCount)
                serverSyncReady = (serverItemCount ?? 0) > 0
                updateSetupCompletion()
            }
            let remainingItemCount = serverItemCount ?? 0
            if remainingItemCount == 0 {
                lastSyncDate = nil
                serverSyncedItemCount = 0
            }
            transactions.removeAll { transaction in
                transaction.itemId == removedItemId ||
                    (transaction.itemId == nil && removedAccountIds.contains(transaction.accountId))
            }
            do {
                let cacheAccounts = accounts
                let cacheTransactions = transactions
                let cacheDirectory = activeStorageDirectoryURL
                let cacheContext = transactionCacheContext
                try await localDataCache.saveAccounts(cacheAccounts, to: cacheDirectory, context: cacheContext)
                try await localDataCache.saveTransactions(
                    cacheTransactions,
                    to: cacheDirectory,
                    context: cacheContext
                )
            } catch {
                self.error = "Local cache failed to save: \(error.localizedDescription)"
            }
        } catch {
            self.error = error.localizedDescription
        }
    }

    @discardableResult
    func resetLocalData() async throws -> LocalDataResetResult {
        stopBackgroundRefresh()

        let resetSetupCompletionDefaultsKey = setupCompletionDefaultsKey
        let resetDirectory = activeStorageDirectoryURL
        let result = try await localDataCache.resetLocalData(at: resetDirectory)

        accounts = []
        transactions = []
        itemStatuses = []
        serverItemCount = 0
        serverCredentialsConfigured = nil
        serverSyncReady = nil
        serverSyncedItemCount = nil
        lastSyncDate = nil
        UserDefaults.standard.set(false, forKey: resetSetupCompletionDefaultsKey)
        isSetupComplete = false
        serverStoragePath = nil
        isDemoMode = false
        isDemoStatusRecoveryScenario = false
        error = nil

        balanceHistory = []
        UserDefaults.standard.removeObject(forKey: Keys.balanceHistory)
        UserDefaults.standard.removeObject(forKey: Keys.lastTransactionCacheContext)
        notificationService.resetDeduplicationState()

        return result
    }

    func startBackgroundRefresh() {
        refreshTask?.cancel()
        refreshTask = Task {
            while !Task.isCancelled {
                await refreshDashboard()
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
        let granted = await notificationService.requestPermission()
        notificationPermissionState = await notificationService.checkPermissionStatus()
        return granted
    }

    func notificationPermissionStatus() async -> NotificationPermissionState {
        notificationPermissionState = await notificationService.checkPermissionStatus()
        return notificationPermissionState
    }

    func stopBackgroundRefresh() {
        refreshTask?.cancel()
        refreshTask = nil
    }

    func loadInitialData() async {
        // The boot window ends when this pass returns, on every path: from
        // then on, offline/empty verdicts are real and may render.
        defer { isBooting = false }

        // Recheck notification permission at startup (user may have revoked in System Settings)
        if notificationsEnabled {
            _ = await notificationPermissionStatus()
        }

        if CommandLine.arguments.contains("--demo") {
            isDemoMode = true
            // `init` already loaded the demo fixtures synchronously so the
            // popover opens settled (no setup→dashboard width jump). Reload only
            // if something bypassed init — e.g. a test constructing this state
            // and calling `loadInitialData()` directly — so we never re-assign
            // identical fixtures (which would churn derived caches) on open.
            if accounts.isEmpty { loadDemoData() }
            return
        }
        // Returning users see cached last-known data immediately: the cache
        // loads before the connectivity check (which can take seconds while
        // a bundled server boots) instead of after it.
        await preloadCachedDataBeforeFirstConnect()
        await checkServerConnection()
        if !serverConnected {
            await startBundledServerIfAvailable()
        }
        if serverConnected {
            // In setup state (credentials missing) there is nothing to fetch
            // from Plaid yet, but the background refresh still runs: its
            // status checks notice when server.conf gains credentials and
            // restart the managed server.
            if serverCredentialsConfigured != false {
                if statusItemCount > 0 {
                    await loadCachedAccounts()
                    await loadCachedTransactions()
                } else {
                    await clearCachedAccounts()
                    await clearCachedTransactions()
                }
                await refreshAccounts()
                await syncTransactions()
            }
            startBackgroundRefresh()
        }
    }

    /// When installed as a standalone `.app` (DMG drag-install), the server
    /// ships inside the bundle. Starts it at app launch so it is usually
    /// ready before the popover first opens.
    func prewarmBundledServer() async {
        guard !CommandLine.arguments.contains("--demo") else {
            isBooting = false
            return
        }
        // The menu bar can be used without ever opening the popover. Once the
        // launch/server probe settles, stop treating offline/stale states as
        // placeholder skeletons even if `loadInitialData()` has not run yet.
        defer { isBooting = false }

        await checkServerConnection()
        guard !serverConnected else { return }
        // The authenticated status check fails for an externally managed
        // server when the local auth token is missing or stale. Probe the
        // unauthenticated /health endpoint so that case never spawns a
        // second server onto an occupied port.
        guard !(await serverClient.isLocalServerResponding()) else { return }
        _ = ServerProcessService.shared.launchBundledServerIfNeeded(
            isDemoMode: isDemoMode,
            serverAlreadyReachable: false
        )
    }

    /// A managed server launched before `server.conf` existed runs in a
    /// credential-less setup state. The server cannot hot-reload credentials,
    /// so once the user writes a config that provides them, restart it
    /// through a freshly evaluated launch plan. Runs after every successful
    /// status check, which covers the background refresh cadence and every
    /// "check again" action in the UI.
    private func upgradeManagedServerIfCredentialsArrived() async {
        guard !isDemoMode,
              !isUpgradingManagedServer,
              serverConnected,
              serverCredentialsConfigured == false,
              ServerProcessService.shared.isManagingServer
        else { return }

        let configFileURL = LocalDataStore.storageDirectoryURL()
            .appendingPathComponent(LocalDataStore.serverConfigFilename)
        guard let configFileContents = try? String(contentsOf: configFileURL, encoding: .utf8),
              configFileContents != lastAttemptedCredentialUpgradeConfig,
              ServerAutoLaunchPlan.configProvidesCredentials(in: configFileContents),
              !ServerAutoLaunchPlan.containsBlockedManagedConfigKey(in: configFileContents)
        else { return }

        isUpgradingManagedServer = true
        defer { isUpgradingManagedServer = false }

        guard await ServerProcessService.shared.restartManagedServer(isDemoMode: isDemoMode) else {
            return
        }
        // Remember the attempted config so a server that still reports
        // missing credentials (e.g. values Plaid rejects) is not restarted
        // every refresh; editing the file again retries.
        lastAttemptedCredentialUpgradeConfig = configFileContents

        for _ in 0 ..< 12 {
            try? await Task.sleep(for: .milliseconds(400))
            await checkServerConnection()
            if serverConnected { break }
        }
    }

    /// Popover-open path: start the bundled server if nothing did yet, then
    /// wait briefly for readiness (also covers a still-booting prewarm).
    /// Reentrancy-guarded because the readiness wait runs
    /// `checkServerConnection`, whose failure path calls back into
    /// `recoverBundledServerIfNeeded`; without the guard a server that
    /// crashes at boot would respawn once per wait iteration.
    private func startBundledServerIfAvailable() async {
        guard !isStartingBundledServer else { return }
        isStartingBundledServer = true
        defer { isStartingBundledServer = false }

        var launched = false
        if !ServerProcessService.shared.isManagingServer,
           !(await serverClient.isLocalServerResponding()) {
            launched = ServerProcessService.shared.launchBundledServerIfNeeded(
                isDemoMode: isDemoMode,
                serverAlreadyReachable: false
            )
        }
        guard launched || ServerProcessService.shared.isManagingServer else { return }

        for _ in 0 ..< 12 {
            try? await Task.sleep(for: .milliseconds(400))
            await checkServerConnection()
            if serverConnected { break }
        }
    }

    /// Warm start for returning users: hydrate accounts/transactions from the
    /// local cache saved under the last-known server context before the first
    /// connectivity check runs. Opportunistic — failures and context
    /// mismatches fall through to the normal post-connect cache path without
    /// surfacing an error during boot.
    private func preloadCachedDataBeforeFirstConnect() async {
        guard accounts.isEmpty, transactions.isEmpty,
              let context = persistedTransactionCacheContext(),
              let cacheDirectory = preconnectCacheDirectory(for: context)
        else { return }

        if let cachedAccounts = try? await localDataCache.loadAccounts(
            from: cacheDirectory,
            context: context
        ), !cachedAccounts.isEmpty {
            accounts = cachedAccounts
        }
        if let cachedTransactions = try? await localDataCache.loadTransactions(
            from: cacheDirectory,
            context: context
        ), !cachedTransactions.isEmpty {
            transactions = cachedTransactions
        }
    }

    private func preconnectCacheDirectory(for context: TransactionCacheContext) -> URL? {
        let normalizedContext = normalizedCacheContext(context)
        guard let currentHint = currentPreconnectCacheContextHint(),
              normalizedCacheContext(currentHint) == normalizedContext
        else { return nil }

        return URL(fileURLWithPath: normalizedContext.storagePath, isDirectory: true)
    }

    private func currentPreconnectCacheContextHint() -> TransactionCacheContext? {
        var environment = ProcessInfo.processInfo.environment
        let configURL = LocalDataStore.storageDirectoryURL()
            .appendingPathComponent(LocalDataStore.serverConfigFilename)
        if let configContents = try? String(contentsOf: configURL, encoding: .utf8) {
            for rawLine in configContents.components(separatedBy: .newlines) {
                guard let entry = parseServerConfigLine(rawLine) else { continue }
                environment[entry.key] = entry.value
            }
        }

        let rawEnvironment = trimmedNonEmpty(environment["PLAID_ENV"]) ?? PlaidEnvironment.production.rawValue
        guard let plaidEnvironment = PlaidEnvironment(rawValue: unquoteConfigValue(rawEnvironment)) else {
            return nil
        }

        return TransactionCacheContext(
            environment: plaidEnvironment,
            storagePath: LocalDataStore.storageDirectoryURL(environment: environment).standardizedFileURL.path
        )
    }

    private func normalizedCacheContext(_ context: TransactionCacheContext) -> TransactionCacheContext {
        TransactionCacheContext(
            environment: context.environment,
            storagePath: URL(
                fileURLWithPath: NSString(string: context.storagePath).expandingTildeInPath,
                isDirectory: true
            ).standardizedFileURL.path
        )
    }

    private func parseServerConfigLine(_ rawLine: String) -> (key: String, value: String)? {
        var line = rawLine.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !line.isEmpty, !line.hasPrefix("#") else { return nil }
        if line.hasPrefix("export ") {
            line.removeFirst("export ".count)
            line = line.trimmingCharacters(in: .whitespacesAndNewlines)
        }
        guard let separator = line.firstIndex(of: "=") else { return nil }
        let key = String(line[..<separator]).trimmingCharacters(in: .whitespacesAndNewlines)
        guard !key.isEmpty else { return nil }
        let value = String(line[line.index(after: separator)...])
            .trimmingCharacters(in: .whitespacesAndNewlines)
        return (key, unquoteConfigValue(value))
    }

    private func trimmedNonEmpty(_ value: String?) -> String? {
        guard let value else { return nil }
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }

    private func unquoteConfigValue(_ value: String) -> String {
        guard value.count >= 2,
              let first = value.first,
              let last = value.last,
              (first == "\"" && last == "\"") || (first == "'" && last == "'")
        else {
            return value
        }
        return String(value.dropFirst().dropLast())
    }

    private func persistedTransactionCacheContext() -> TransactionCacheContext? {
        guard let data = UserDefaults.standard.data(forKey: Keys.lastTransactionCacheContext) else {
            return nil
        }
        return try? JSONDecoder().decode(TransactionCacheContext.self, from: data)
    }

    private func persistTransactionCacheContext() {
        guard let transactionCacheContext,
              let data = try? JSONEncoder().encode(transactionCacheContext)
        else { return }
        UserDefaults.standard.set(data, forKey: Keys.lastTransactionCacheContext)
    }

    // MARK: - Balance History

    private func loadCachedAccounts() async {
        do {
            accounts = try await localDataCache.loadAccounts(
                from: activeStorageDirectoryURL,
                context: transactionCacheContext
            )
        } catch {
            self.error = "Account cache failed to load: \(error.localizedDescription)"
        }
    }

    private func clearCachedAccounts() async {
        accounts = []
        do {
            try await localDataCache.saveAccounts(
                accounts,
                to: activeStorageDirectoryURL,
                context: transactionCacheContext
            )
        } catch {
            self.error = "Account cache failed to clear: \(error.localizedDescription)"
        }
    }

    private func loadCachedTransactions() async {
        do {
            transactions = try await localDataCache.loadTransactions(
                from: activeStorageDirectoryURL,
                context: transactionCacheContext
            )
        } catch {
            self.error = "Transaction cache failed to load: \(error.localizedDescription)"
        }
    }

    private func clearCachedTransactions() async {
        transactions = []
        do {
            try await localDataCache.saveTransactions(
                transactions,
                to: activeStorageDirectoryURL,
                context: transactionCacheContext
            )
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

    @discardableResult
    private func refreshItemStatuses() async -> Bool {
        do {
            applyItemStatuses(try await serverClient.getItems())
            return true
        } catch {
            return false
        }
    }

    private func applyItemStatuses(_ statuses: [ItemStatus]) {
        itemStatuses = statuses
        serverItemCount = statuses.count
        serverSyncReady = !statuses.isEmpty
        updateSetupCompletion()
    }

    private func accountsPreservingUnavailableItems(_ refreshedAccounts: [AccountDTO]) -> [AccountDTO] {
        guard !accounts.isEmpty, !itemStatuses.isEmpty else { return refreshedAccounts }

        let refreshedAccountIds = Set(refreshedAccounts.map(\.id))
        let refreshedItemIds = Set(refreshedAccounts.map(\.itemId))
        let unavailableItemIds = Set(itemStatuses.compactMap { item -> String? in
            guard item.status != .connected, !refreshedItemIds.contains(item.id) else { return nil }
            return item.id
        })
        guard !unavailableItemIds.isEmpty else { return refreshedAccounts }

        let preservedAccounts = accounts.filter { account in
            unavailableItemIds.contains(account.itemId) && !refreshedAccountIds.contains(account.id)
        }
        return refreshedAccounts + preservedAccounts
    }

    private func accountsPreservingCachedAccountsMissingFromRefresh(_ refreshedAccounts: [AccountDTO]) -> [AccountDTO] {
        guard !accounts.isEmpty else { return refreshedAccounts }

        let refreshedAccountIds = Set(refreshedAccounts.map(\.id))
        let preservedAccounts = accounts.filter { account in
            !refreshedAccountIds.contains(account.id)
        }
        return refreshedAccounts + preservedAccounts
    }

    private func updateSetupCompletion() {
        // Promote-only: transient startup probes (prewarmBundledServer /
        // loadInitialData before the server is reachable) report not-ready
        // and must not erase the persisted completion bit. Explicit resets
        // (resetLocalData, demo exit) set isSetupComplete = false directly.
        if firstRunCompletionState.isReady {
            isSetupComplete = true
        }
    }

    private func refreshSetupCompletionForActiveContext() {
        let storedValue = storedSetupCompletion()
        if isSetupComplete != storedValue {
            isSetupComplete = storedValue
        }
    }

    private func storedSetupCompletion() -> Bool {
        let defaults = UserDefaults.standard
        if let scopedValue = defaults.object(forKey: setupCompletionDefaultsKey) as? Bool {
            return scopedValue
        }

        // One-time compatibility path for users who completed setup before
        // completion became scoped by data directory and Plaid environment.
        return defaults.bool(forKey: Keys.setupCompletedOnce)
            && activeStorageDirectoryURL == localStorageDirectoryURL
            && setupCompletionEnvironment == .production
    }

    private func persistSetupCompletion(_ isComplete: Bool) {
        guard !isComplete || !isDemoMode else { return }
        UserDefaults.standard.set(isComplete, forKey: setupCompletionDefaultsKey)
    }

    private var setupCompletionDefaultsKey: String {
        let environment = setupCompletionEnvironment.rawValue
        let path = activeStorageDirectoryURL.standardizedFileURL.path
        let encodedPath = path.addingPercentEncoding(withAllowedCharacters: .alphanumerics) ?? path
        return "\(Keys.setupCompletedContextPrefix).\(environment).\(encodedPath)"
    }

    private var setupCompletionEnvironment: PlaidEnvironment {
        serverEnvironment ?? configuredPlaidEnvironment() ?? .production
    }

    private func configuredPlaidEnvironment() -> PlaidEnvironment? {
        var values = ProcessInfo.processInfo.environment
        let configURL = localStorageDirectoryURL.appendingPathComponent(LocalDataStore.serverConfigFilename)
        if let contents = try? String(contentsOf: configURL, encoding: .utf8) {
            for line in contents.components(separatedBy: .newlines) {
                guard let entry = Self.parseConfigLine(line) else { continue }
                values[entry.key] = Self.unquotedConfigValue(entry.value)
            }
        }

        guard let rawValue = values["PLAID_ENV"]?
            .trimmingCharacters(in: .whitespacesAndNewlines),
            !rawValue.isEmpty
        else {
            return nil
        }
        return PlaidEnvironment(rawValue: rawValue)
    }

    private static func parseConfigLine(_ rawLine: String) -> (key: String, value: String)? {
        var line = rawLine.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !line.isEmpty, !line.hasPrefix("#") else { return nil }

        if line.hasPrefix("export ") {
            line.removeFirst("export ".count)
            line = line.trimmingCharacters(in: .whitespacesAndNewlines)
        }

        guard let separator = line.firstIndex(of: "=") else { return nil }
        let key = String(line[..<separator]).trimmingCharacters(in: .whitespacesAndNewlines)
        guard !key.isEmpty else { return nil }
        let value = String(line[line.index(after: separator)...])
            .trimmingCharacters(in: .whitespacesAndNewlines)
        return (key, value)
    }

    private static func unquotedConfigValue(_ value: String) -> String {
        guard value.count >= 2,
              let first = value.first,
              let last = value.last,
              (first == "\"" && last == "\"") || (first == "'" && last == "'")
        else {
            return value
        }
        return String(value.dropFirst().dropLast())
    }

    @discardableResult
    private func refreshDemoDataIfNeeded() -> Bool {
        guard isDemoMode else { return false }
        error = nil
        isLoading = false
        loadDemoData()
        return true
    }

    private func loadPersistedBalanceHistory() {
        if let data = UserDefaults.standard.data(forKey: Keys.balanceHistory),
           let history = try? JSONDecoder().decode([BalanceSnapshot].self, from: data) {
            balanceHistory = history
        } else {
            balanceHistory = []
        }
    }

    private func recordBalanceSnapshot() {
        guard !accounts.isEmpty else { return }
        balanceHistory = BalanceHistoryReducer.appending(
            BalanceSnapshot(date: Date(), balance: netBalance),
            to: balanceHistory
        )
        if let data = try? JSONEncoder().encode(balanceHistory) {
            UserDefaults.standard.set(data, forKey: Keys.balanceHistory)
        }
    }

    // MARK: - Demo Data

    func loadDemoData() {
        isDemoMode = true
        // Demo fixtures load synchronously: there is no boot handshake to wait for.
        isBooting = false
        isDemoStatusRecoveryScenario = CommandLine.arguments.contains("--screenshot-status-recovery")

        // Fixture content lives in PlaidBarCore so its continuity guarantees
        // (no heatmap dead zone, year-round income, active savings account)
        // stay testable. See DemoFixtures and DemoFixturesTests.
        accounts = DemoFixtures.accounts
        transactions = DemoFixtures.transactions()
        balanceHistory = DemoFixtures.balanceHistory()

        isSetupComplete = true
        serverConnected = true
        serverEnvironment = .sandbox
        serverVersion = PlaidBarConstants.appVersion
        serverItemCount = Set(accounts.map(\.itemId)).count
        serverCredentialsConfigured = true
        serverStoragePath = LocalDataStore.displayPath
        serverSyncReady = true
        serverSyncedItemCount = isDemoStatusRecoveryScenario ? 1 : serverItemCount
        let recoveredSync = Calendar.current.date(byAdding: .minute, value: -18, to: Date()) ?? Date()
        let needsLoginSync = Calendar.current.date(byAdding: .day, value: -3, to: Date()) ?? Date()
        itemStatuses = isDemoStatusRecoveryScenario ? [
            ItemStatus(id: "demo_chase", institutionName: "Chase", status: .connected, lastSync: recoveredSync),
            ItemStatus(id: "demo_amex_item", institutionName: "American Express", status: .loginRequired, lastSync: needsLoginSync),
        ] : [
            ItemStatus(id: "demo_chase", institutionName: "Chase", status: .connected, lastSync: Date()),
            ItemStatus(id: "demo_amex_item", institutionName: "American Express", status: .connected, lastSync: Date()),
        ]
        lastSyncDate = isDemoStatusRecoveryScenario ? recoveredSync : Date()
    }

}

private enum AppStateError: LocalizedError {
    case transactionSyncPageLimitExceeded(maxPages: Int)

    var errorDescription: String? {
        switch self {
        case .transactionSyncPageLimitExceeded(let maxPages):
            "Transaction sync did not finish after \(maxPages) pages. Try again later."
        }
    }
}
