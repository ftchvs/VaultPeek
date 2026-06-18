import SwiftUI
import PlaidBarCore
import Combine
import OSLog
import WidgetKit
@preconcurrency import UserNotifications

@Observable
@MainActor
final class AppState {
    /// Used off the main actor inside the glance-snapshot write task; a
    /// `Logger` is `Sendable`, so it is safe to reference there.
    nonisolated static let glanceSnapshotLogger = Logger(
        subsystem: "com.ftchvs.PlaidBar",
        category: "GlanceSnapshot"
    )

    // MARK: - UserDefaults Keys
    private enum Keys {
        static let showBalanceInMenuBar = "showBalanceInMenuBar"
        static let menuBarSummaryMode = "menuBarSummaryMode"
        static let menuBarIconStyle = "menuBarIconStyle"
        static let summonHotkeyEnabled = "summonHotkeyEnabled"
        static let menuBarShowSignalMeter = "menuBarShowSignalMeter"
        static let balanceFormat = "balanceFormat"
        static let creditUtilizationThreshold = "creditUtilizationThreshold"
        static let refreshInterval = "refreshInterval"
        static let automaticRefreshPolicy = AutomaticRefreshPolicy.storageKey
        static let balanceHistory = "balanceHistory"
        static let accountBalanceLedger = "accountBalanceLedger"
        static let notificationsEnabled = "notificationsEnabled"
        static let largeTransactionThreshold = "largeTransactionThreshold"
        static let lowBalanceThreshold = "lowBalanceThreshold"
        static let notifyLargeTransaction = "notifyLargeTransaction"
        static let notifyLowBalance = "notifyLowBalance"
        static let notifyHighUtilization = "notifyHighUtilization"
        static let weeklyReviewState = "weeklyReview.state"
        static let weeklyReviewPreviousSafeToSpend = "weeklyReview.previousSafeToSpend"
        static let notifyRecurringChargeDetected = "notifyRecurringChargeDetected"
        static let notifyRecurringChargeChanged = "notifyRecurringChargeChanged"
        static let notifyRecurringChargeDueSoon = "notifyRecurringChargeDueSoon"
        static let notifyBrokenConnection = "notifyBrokenConnection"
        static let notifyWatchlist = "notifyWatchlist"
        static let watchlistTargets = "watchlistTargets"
        static let privacyMaskEnabled = "privacyMaskEnabled"
        static let appLockEnabled = UserDefaultsAppLockSettingsStore.defaultStorageKey
        static let appLockNotificationPrivacyMode = "appLock.notificationPrivacyMode"
        static let appLockPauseRefreshWhileLocked = "appLock.pauseRefreshWhileLocked"
        static let appLockLockOnLaunch = "appLock.lockOnLaunch"
        static let appLockLockWhenBackgrounded = "appLock.lockWhenBackgrounded"
        static let localAIEnabled = "localAIEnabled"
        static let localAIModelName = "localAIModelName"
        static let setupCompletedOnce = "setup.completedOnce"
        static let setupCompletedContextPrefix = "setup.completedOnce.context"
        static let firstRunSnapshotDismissedContextPrefix = "firstRunSnapshot.dismissed.context"
        static let lastTransactionCacheContext = "cache.lastTransactionCacheContext"
        static let categoryBudgetCache = "cache.categoryBudgets"
        static let dashboardDetached = DetachedDashboardPreferences.detachedStorageKey
    }

    // MARK: - State
    var accounts: [AccountDTO] = [] {
        didSet { invalidateLocalAIActivitySummaries() }
    }
    /// Latest per-account credit-card liabilities (APR, statement, due date)
    /// from Plaid Liabilities, refreshed alongside accounts. Empty for items
    /// linked without the `liabilities` scope. Latest-only — no history.
    var liabilities: [LiabilityDTO] = []
    var transactions: [TransactionDTO] = [] {
        didSet {
            _cachedTransactionDerivedIndex = nil
            _cachedRecurringTransactions = nil
            _cachedCategoryBudgetPresentation = nil
            _cachedTransactionReviewInboxSnapshot = nil
            invalidateLocalAIActivitySummaries()
        }
    }
    var transactionReviewMetadata: [TransactionReviewMetadata] = [] {
        didSet { _cachedTransactionReviewInboxSnapshot = nil }
    }
    var transactionRules: [TransactionRule] = [] {
        didSet { _cachedTransactionReviewInboxSnapshot = nil }
    }
    var hasLoadedTransactionReviewStorage = false
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
    var isFirstRunSnapshotDismissed = false {
        didSet {
            guard oldValue != isFirstRunSnapshotDismissed else { return }
            persistFirstRunSnapshotDismissal(isFirstRunSnapshotDismissed)
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
    var billingSubscription: BillingSubscription?
    var itemStatuses: [ItemStatus] = []
    /// User-set category budget limits hydrated from `/api/budgets`.
    /// Suggestions remain a local fallback/complement, but this cache wins for
    /// categories the user explicitly saved on the server.
    var categoryBudgets: [SpendingCategory: Double] = [:] {
        didSet { _cachedCategoryBudgetPresentation = nil }
    }
    var isDemoMode = false
    var isDemoStatusRecoveryScenario = false
    var lastSyncDate: Date?
    var balanceHistory: [BalanceSnapshot] = []
    /// Per-account "what the bank said" ledger (AND-490). Each refresh appends one
    /// dated row per account; the Time Machine surface reads from it.
    var accountBalanceLedger = AccountBalanceLedger()
    /// Display-safe rows describing prior-day balances Plaid restated on the most
    /// recent sync (AND-490). Empty when no history was rewritten.
    var syncHistoryDiffRows: [SyncHistoryDiff.Row] = []
    var notificationPermissionState: NotificationPermissionState = .notDetermined
    var weeklyReviewState: WeeklyReviewState = .empty {
        didSet {
            guard weeklyReviewState != oldValue else { return }
            persistWeeklyReviewState()
        }
    }
    @ObservationIgnored private var performanceTrace = PerformanceTrace()

    private struct CategoryBudgetCache: Codable {
        let context: TransactionCacheContext
        let budgets: [String: Double]
    }

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
    /// Whether the healthy menu-bar glyph is replaced by the live signal meter
    /// (AND-485). Only the healthy state is affected; the degraded glyph ladder
    /// (error/login/offline/warning) always wins so a problem is never hidden
    /// behind a meter. Persisted only; the render branch lives in MenuBarLabel.
    var menuBarShowSignalMeter: Bool = false {
        didSet {
            guard menuBarShowSignalMeter != oldValue else { return }
            UserDefaults.standard.set(menuBarShowSignalMeter, forKey: Keys.menuBarShowSignalMeter)
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
    /// How often financial data is refreshed from Plaid AUTOMATICALLY (on
    /// popover open and via the background loop). Manual refreshes always run.
    /// `refreshInterval` above stays the internal self-heal tick (connectivity
    /// re-probe + notifications); this throttles the actual Plaid data fetch.
    var automaticRefreshPolicy: AutomaticRefreshPolicy = .twiceDaily {
        didSet {
            guard automaticRefreshPolicy != oldValue else { return }
            UserDefaults.standard.set(automaticRefreshPolicy.rawValue, forKey: Keys.automaticRefreshPolicy)
        }
    }

    /// Whether an automatic (non-user-triggered) refresh is due now, per the
    /// refresh policy and the last successful sync. Manual refreshes bypass this.
    var shouldAutoRefreshNow: Bool {
        automaticRefreshPolicy.shouldAutoRefresh(
            lastSync: lastSyncDate,
            now: Date(),
            hasImmediateNeed: needsImmediateRefresh
        )
    }

    /// Refresh-now conditions the time-based throttle must not suppress. These
    /// bypass the twice-daily floor, but AutomaticRefreshPolicy still honors
    /// Manual only before any automatic Plaid-backed fetch is allowed.
    private var needsImmediateRefresh: Bool {
        if statusItemCount > 0, accounts.isEmpty { return true }
        if itemStatuses.contains(where: \.needsSync) { return true }
        // A healthy (connected) item that hasn't synced yet — e.g. just linked.
        // Count only CONNECTED items against the synced count so an item stuck in
        // login-required / permission-revoked / error (which can't sync until the
        // user repairs it) can't hold the gap open and defeat the throttle on
        // every tick (Codex P2). Once the new item syncs, the counts converge.
        if let synced = serverSyncedItemCount {
            let connectedCount = itemStatuses.filter { $0.status == .connected }.count
            if connectedCount > synced { return true }
        }
        return false
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
    var notifyRecurringChargeDetected: Bool = true {
        didSet {
            guard notifyRecurringChargeDetected != oldValue else { return }
            UserDefaults.standard.set(notifyRecurringChargeDetected, forKey: Keys.notifyRecurringChargeDetected)
        }
    }
    var notifyRecurringChargeChanged: Bool = true {
        didSet {
            guard notifyRecurringChargeChanged != oldValue else { return }
            UserDefaults.standard.set(notifyRecurringChargeChanged, forKey: Keys.notifyRecurringChargeChanged)
        }
    }
    var notifyRecurringChargeDueSoon: Bool = true {
        didSet {
            guard notifyRecurringChargeDueSoon != oldValue else { return }
            UserDefaults.standard.set(notifyRecurringChargeDueSoon, forKey: Keys.notifyRecurringChargeDueSoon)
        }
    }
    var notifyBrokenConnection: Bool = true {
        didSet {
            guard notifyBrokenConnection != oldValue else { return }
            UserDefaults.standard.set(notifyBrokenConnection, forKey: Keys.notifyBrokenConnection)
        }
    }
    /// Master gate for watchlist spend nudges (AND-501).
    var notifyWatchlist: Bool = true {
        didSet {
            guard notifyWatchlist != oldValue else { return }
            UserDefaults.standard.set(notifyWatchlist, forKey: Keys.notifyWatchlist)
        }
    }
    /// User-defined per-merchant / per-category spend watches (AND-501).
    /// Persisted app-side as Codable JSON in UserDefaults — a lightweight nudge
    /// list, deliberately not server-side envelope budgeting.
    var watchlistTargets: [WatchlistTarget] = [] {
        didSet {
            guard watchlistTargets != oldValue, !isLoadingDemoWatchlist else { return }
            persistWatchlistTargets()
        }
    }

    /// Guards `watchlistTargets.didSet` while demo fixtures are loaded so the
    /// demo nudges are shown in-memory only and never overwrite the user's real,
    /// persisted watchlist (demo exit clears accounts/transactions but does not
    /// restore preferences, so a persisted demo list would survive — Codex P2).
    private var isLoadingDemoWatchlist = false

    func addWatchlistTarget(_ target: WatchlistTarget) {
        watchlistTargets.append(target)
    }

    func removeWatchlistTarget(id: WatchlistTarget.ID) {
        watchlistTargets.removeAll { $0.id == id }
    }

    private func persistWatchlistTargets() {
        guard let data = try? JSONEncoder().encode(watchlistTargets) else { return }
        UserDefaults.standard.set(data, forKey: Keys.watchlistTargets)
    }

    /// Restores the persisted real watchlist, or empties it when none was saved.
    /// Called on launch and on demo exit; the in-memory demo nudges (loaded with
    /// `isLoadingDemoWatchlist` set, so never persisted) must not linger once the
    /// user leaves demo mode, so the no-data branch clears rather than no-ops.
    private func loadWatchlistTargets(defaults: UserDefaults) {
        guard let data = defaults.data(forKey: Keys.watchlistTargets),
              let decoded = try? JSONDecoder().decode([WatchlistTarget].self, from: data)
        else {
            isLoadingDemoWatchlist = true
            watchlistTargets = []
            isLoadingDemoWatchlist = false
            return
        }
        watchlistTargets = decoded
    }

    var appLockPreferences = AppLockPreferences() {
        didSet {
            guard appLockPreferences != oldValue, !isLoadingAppLockPreferences else { return }
            persistAppLockPreferences()
        }
    }

    var isAppLocked = false

    /// The message shown on the locked gate, updated from the most recent unlock
    /// attempt (`nil` once unlocked). Drives `lockedSurfaceCopy` so a cancelled /
    /// failed / unavailable attempt explains itself instead of leaving the plain
    /// idle prompt.
    private var lastUnlockMessage: AppLockAuthenticationMessage?

    var financialPrivacyDisplayMode: PrivacyDisplayMode {
        appLockPreferences.effectiveDisplayMode(isAppLocked: isAppLocked)
    }

    var shouldMaskFinancialValues: Bool {
        financialPrivacyDisplayMode != .normal
    }

    /// Flips the lighter Privacy Mask (dots balances/amounts without requiring
    /// authentication). Backs the quick toggles — the popover eye button, the
    /// ⌘⇧P shortcut, and ⌥-click on the menu-bar icon — so privacy can be engaged
    /// without opening Settings. Persisted via the `appLockPreferences` didSet.
    /// No-op while fully locked: App Lock already masks everything and owns reveal.
    func togglePrivacyMask() {
        guard !isContentLocked else { return }
        appLockPreferences.privacyMaskEnabled.toggle()
    }

    /// True only in full App Lock (`.locked`) — distinct from
    /// `shouldMaskFinancialValues`, which is also true for the lighter Privacy
    /// Mask (`.masked`). When this is true the dashboard must be gated behind the
    /// locked surface, not merely have its currency dotted: account and
    /// institution names must not leak (AND-462).
    var isContentLocked: Bool {
        financialPrivacyDisplayMode == .locked
    }

    /// Copy for the locked gate: the most recent unlock-attempt message when one
    /// exists, otherwise the neutral idle prompt.
    var lockedSurfaceCopy: String {
        lastUnlockMessage?.lockedSurfaceCopy ?? AppLockAuthenticationMessage.idleSurfaceCopy
    }

    var localAIEnabled: Bool = false {
        didSet {
            guard localAIEnabled != oldValue, !isLoadingLocalAISettings else { return }
            localAIEnabledPreference = localAIEnabled
            UserDefaults.standard.set(localAIEnabled, forKey: Keys.localAIEnabled)
            rebuildLocalAIInsightsService()
            invalidateLocalAIActivitySummaries()
        }
    }

    var localAIModelName: String = "llama3.2" {
        didSet {
            let normalized = Self.normalizedLocalAIModelName(localAIModelName) ?? "llama3.2"
            if normalized != localAIModelName {
                localAIModelName = normalized
            }
            guard normalized != oldValue, !isLoadingLocalAISettings else { return }
            localAIModelNamePreference = normalized
            UserDefaults.standard.set(normalized, forKey: Keys.localAIModelName)
            rebuildLocalAIInsightsService()
            invalidateLocalAIActivitySummaries()
        }
    }
    var isCheckingLocalAIAvailability = false

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

    /// Whether the global summon hotkey (⇧⌘V) is registered (AND-487). The
    /// register/unregister side effect is owned by the always-mounted label
    /// scene in `PlaidBarApp`, which observes this flag; here we only persist it.
    /// Opt-in (defaults `false`): ⇧⌘V is "Paste and Match Style" in many apps, so
    /// claiming it globally on a fresh install would hijack that editing shortcut
    /// before the user ever asked for the summon hotkey.
    var summonHotkeyEnabled: Bool = false {
        didSet {
            guard summonHotkeyEnabled != oldValue else { return }
            UserDefaults.standard.set(summonHotkeyEnabled, forKey: Keys.summonHotkeyEnabled)
        }
    }

    // MARK: - Services
    private let serverClient = ServerClient()
    /// Fetches + caches merchant logos via the local server's authed proxy.
    let merchantLogoStore = MerchantLogoStore()
    private let localDataCache = LocalDataCacheService()
    private let appLockService = AppLockService()
    private let reviewStorageWriter = ReviewStorageWriter()
    private var localAIInsightsService = LocalAIInsightsService()
    private let notificationService: any NotificationServiceProtocol
    private var refreshTask: Task<Void, Never>?
    private var localAISummaryRefreshTask: Task<Void, Never>?
    private let glanceSnapshotWriteDebouncer = GlanceSnapshotWriteDebouncer()
    private var glanceSnapshotWriteGeneration = 0
    private var reviewUndoStack: [(metadata: [TransactionReviewMetadata], rules: [TransactionRule])] = []
    private var localAIEnabledPreference: Bool?
    private var localAIModelNamePreference: String?
    private var localAIProbeAvailability: LocalAIAvailability?
    private var localAIProbeGeneration = 0
    private var isLoadingLocalAISettings = false
    private var isLoadingAppLockPreferences = false
    private var isUpgradingManagedServer = false
    private var isStartingBundledServer = false
    private var lastAttemptedCredentialUpgradeConfig: String?

    // MARK: - Init

    init(notificationService: (any NotificationServiceProtocol)? = nil) {
        _ = try? LocalDataStore.migrateLegacyDefaultStorageIfNeeded()
        self.notificationService = notificationService ?? NotificationService.shared
        loadSettings()
        // Engage launch App Lock synchronously before the first SwiftUI body is
        // ever evaluated. Deferring this to `loadInitialData()` leaks one frame
        // of cached/demo account names and activity because `.task` runs after
        // the initial render; the lock-on-launch privacy contract needs to be
        // true as soon as AppState enters the environment.
        lockOnLaunchIfNeeded()
        isSetupComplete = storedSetupCompletion()
        isFirstRunSnapshotDismissed = storedFirstRunSnapshotDismissal()
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
        if defaults.object(forKey: Keys.summonHotkeyEnabled) != nil {
            summonHotkeyEnabled = defaults.bool(forKey: Keys.summonHotkeyEnabled)
        }
        if defaults.object(forKey: Keys.menuBarShowSignalMeter) != nil {
            menuBarShowSignalMeter = defaults.bool(forKey: Keys.menuBarShowSignalMeter)
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
        if let rawPolicy = defaults.string(forKey: Keys.automaticRefreshPolicy),
           let policy = AutomaticRefreshPolicy(rawValue: rawPolicy) {
            automaticRefreshPolicy = policy
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
        if defaults.object(forKey: Keys.notifyRecurringChargeDetected) != nil {
            notifyRecurringChargeDetected = defaults.bool(forKey: Keys.notifyRecurringChargeDetected)
        }
        if defaults.object(forKey: Keys.notifyRecurringChargeChanged) != nil {
            notifyRecurringChargeChanged = defaults.bool(forKey: Keys.notifyRecurringChargeChanged)
        }
        if defaults.object(forKey: Keys.notifyRecurringChargeDueSoon) != nil {
            notifyRecurringChargeDueSoon = defaults.bool(forKey: Keys.notifyRecurringChargeDueSoon)
        }
        if defaults.object(forKey: Keys.notifyBrokenConnection) != nil {
            notifyBrokenConnection = defaults.bool(forKey: Keys.notifyBrokenConnection)
        }
        if defaults.object(forKey: Keys.notifyWatchlist) != nil {
            notifyWatchlist = defaults.bool(forKey: Keys.notifyWatchlist)
        }
        loadWatchlistTargets(defaults: defaults)
        loadAppLockPreferences(defaults: defaults)
        loadLocalAISettings(defaults: defaults)
        // Balance history
        loadPersistedBalanceHistory()
        loadPersistedWeeklyReviewState()
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

    private func loadAppLockPreferences(defaults: UserDefaults) {
        // `appLockService` is the single source of truth for the enabled flag —
        // it owns `Keys.appLockEnabled` via its settings store. Deriving the
        // preference from the service (rather than reading the key again here)
        // keeps the in-memory service state and the persisted flag coherent and
        // avoids the dual-write desync on the shared UserDefaults key.
        isLoadingAppLockPreferences = true
        appLockPreferences = AppLockPreferences(
            privacyMaskEnabled: defaults.object(forKey: Keys.privacyMaskEnabled) != nil
                ? defaults.bool(forKey: Keys.privacyMaskEnabled)
                : appLockPreferences.privacyMaskEnabled,
            appLockEnabled: appLockService.isLockEnabled,
            lockOnLaunch: defaults.object(forKey: Keys.appLockLockOnLaunch) != nil
                ? defaults.bool(forKey: Keys.appLockLockOnLaunch)
                : appLockPreferences.lockOnLaunch,
            lockWhenBackgrounded: defaults.object(forKey: Keys.appLockLockWhenBackgrounded) != nil
                ? defaults.bool(forKey: Keys.appLockLockWhenBackgrounded)
                : appLockPreferences.lockWhenBackgrounded,
            notificationPrivacyMode: defaults.string(forKey: Keys.appLockNotificationPrivacyMode)
                .flatMap(NotificationPrivacyMode.init(rawValue:))
                ?? appLockPreferences.notificationPrivacyMode,
            pauseRefreshWhileLocked: defaults.object(forKey: Keys.appLockPauseRefreshWhileLocked) != nil
                ? defaults.bool(forKey: Keys.appLockPauseRefreshWhileLocked)
                : appLockPreferences.pauseRefreshWhileLocked
        )
        isLoadingAppLockPreferences = false
        isAppLocked = appLockService.isLocked
    }

    private func persistAppLockPreferences() {
        // `appLockEnabled` is intentionally NOT written here — `appLockService`
        // owns `Keys.appLockEnabled` and is the single writer for it (via
        // `setAppLockEnabled`). Writing it from both paths is what previously
        // desynced the in-memory service from the persisted flag.
        UserDefaults.standard.set(appLockPreferences.privacyMaskEnabled, forKey: Keys.privacyMaskEnabled)
        UserDefaults.standard.set(appLockPreferences.lockOnLaunch, forKey: Keys.appLockLockOnLaunch)
        UserDefaults.standard.set(appLockPreferences.lockWhenBackgrounded, forKey: Keys.appLockLockWhenBackgrounded)
        UserDefaults.standard.set(appLockPreferences.notificationPrivacyMode.rawValue, forKey: Keys.appLockNotificationPrivacyMode)
        UserDefaults.standard.set(appLockPreferences.pauseRefreshWhileLocked, forKey: Keys.appLockPauseRefreshWhileLocked)
    }

    // MARK: - App Lock

    /// The current biometric / device-authentication capability, surfaced to the
    /// settings UI so the App Lock toggle can disable and explain itself when no
    /// authentication is available.
    func appLockAuthenticationCapability() -> AppLockCapability {
        appLockService.authenticationCapability()
    }

    /// Single entry point for enabling/disabling App Lock. Routes through
    /// `AppLockService` (the source of truth for the enabled flag) so the
    /// service's `isLockEnabled`, the persisted UserDefaults key, and the
    /// mirrored `appLockPreferences.appLockEnabled` stay coherent.
    ///
    /// Returns the resolved capability so callers can surface why enabling was
    /// refused (e.g. biometrics unavailable).
    @discardableResult
    func setAppLockEnabled(_ isEnabled: Bool) -> AppLockCapability {
        let capability = appLockService.setLockEnabled(isEnabled)
        // Mirror the service's authoritative state back onto the observable
        // preference and lock flag. The setter below persists the non-enabled
        // keys only; the service already persisted the enabled flag.
        appLockPreferences.appLockEnabled = appLockService.isLockEnabled
        isAppLocked = appLockService.isLocked
        return capability
    }

    /// Locks VaultPeek immediately when App Lock is enabled (no-op otherwise).
    /// Used by launch and resign-active lifecycle triggers.
    func lockApp() {
        appLockService.lock()
        isAppLocked = appLockService.isLocked
        // A fresh lock starts the gate at the neutral idle prompt — clear any
        // stale message from a prior cancelled/failed unlock attempt.
        if isAppLocked {
            lastUnlockMessage = nil
        }
    }

    /// Locks on launch when both App Lock and the lock-on-launch preference are
    /// enabled. Called synchronously during init before first render, and again
    /// idempotently during the initial data task for legacy call sites.
    func lockOnLaunchIfNeeded() {
        guard appLockPreferences.shouldLockOnLaunch else { return }
        lockApp()
    }

    /// Locks when VaultPeek loses focus (resign active / popover close), when
    /// the lock-when-backgrounded preference is enabled. MainActor-safe and
    /// cheap when App Lock is off.
    func lockOnResignActiveIfNeeded() {
        guard appLockPreferences.shouldLockWhenBackgrounded else { return }
        lockApp()
    }

    /// Prompts for biometric / device authentication to unlock VaultPeek. A
    /// no-op that resolves to `.success` when App Lock is disabled or already
    /// unlocked. Mirrors the resulting lock state back onto `isAppLocked`.
    @discardableResult
    func unlockApp() async -> AppLockAuthenticationResult {
        guard appLockService.isLockEnabled, appLockService.isLocked else {
            isAppLocked = appLockService.isLocked
            return .success
        }
        let result = await appLockService.authenticate(
            reason: "Unlock VaultPeek to view your balances."
        )
        isAppLocked = appLockService.isLocked
        // Surface the outcome on the locked gate: `nil` on success (the gate is
        // about to be dismissed), otherwise the cancelled / failed / unavailable
        // message so the user sees why it stayed locked.
        lastUnlockMessage = AppLockAuthenticationMessage(unlockResult: result)
        return result
    }

    private func loadLocalAISettings(defaults: UserDefaults) {
        isLoadingLocalAISettings = true
        defer {
            isLoadingLocalAISettings = false
            rebuildLocalAIInsightsService()
        }

        let environment = ProcessInfo.processInfo.environment
        if defaults.object(forKey: Keys.localAIEnabled) != nil {
            let enabled = defaults.bool(forKey: Keys.localAIEnabled)
            localAIEnabledPreference = enabled
            localAIEnabled = enabled
        } else {
            localAIEnabledPreference = nil
            localAIEnabled = LocalAIRuntimeResolution.isOptedIn(
                rawValue: environment[LocalAIRuntimeResolution.optInEnvironmentKey]
            )
        }

        if let storedModelName = Self.normalizedLocalAIModelName(defaults.string(forKey: Keys.localAIModelName)) {
            localAIModelNamePreference = storedModelName
            localAIModelName = storedModelName
        } else {
            localAIModelNamePreference = nil
            localAIModelName = Self.normalizedLocalAIModelName(environment["PLAIDBAR_LOCAL_AI_MODEL"]) ?? "llama3.2"
        }
    }

    private func rebuildLocalAIInsightsService() {
        localAIProbeGeneration += 1
        localAIProbeAvailability = nil
        localAIInsightsService = LocalAIInsightsService(
            enabledPreference: localAIEnabledPreference,
            modelNamePreference: localAIModelNamePreference
        )
    }

    private static func normalizedLocalAIModelName(_ value: String?) -> String? {
        let trimmed = value?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        return trimmed.isEmpty ? nil : trimmed
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
        // Safe-to-spend needs recurring + cashflow inputs that the pure Core
        // text() does not take, so compute it here (only for that mode, to keep
        // the common render path cheap) and feed the amount in.
        let safeToSpend: Double? = menuBarSummaryMode == .safeToSpend
            ? currentSafeToSpendAmount()
            : nil
        let rawText = MenuBarSummary.text(
            mode: menuBarSummaryMode,
            accounts: accounts,
            transactions: transactions,
            currencyFormat: balanceFormat,
            isInitialLoad: isBootLoadInFlight,
            privacyMaskEnabled: shouldMaskFinancialValues,
            precomputedSafeToSpend: safeToSpend
        )
        return appLockPreferences.menuBarText(
            currentText: rawText,
            isAppLocked: isAppLocked,
            isIconOnly: menuBarSummaryMode == .iconOnly
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
            financialAttentionText: shouldMaskFinancialValues ? nil : firstMenuBarAttentionText,
            iconStyle: menuBarIconStyle
        )
    }

    /// The live signal-meter glyph model (AND-485), or `nil` when the meter must
    /// not draw. The degraded glyph ladder in `menuBarStatusPresentation` always
    /// wins: the meter renders only when the status is showing the healthy glyph
    /// (no error/login/offline/warning), so a problem is never hidden behind a
    /// meter. Also suppressed under the privacy mask and when there is no signal.
    var menuBarSignalGlyph: SignalGlyphMeter.SignalGlyphRenderModel? {
        guard menuBarShowSignalMeter else { return nil }
        guard !shouldMaskFinancialValues else { return nil }
        // Only override the healthy glyph; defer to the degraded ladder otherwise.
        let presentation = menuBarStatusPresentation
        guard presentation.symbolName == menuBarIconStyle.healthySymbolName else { return nil }
        let model = SignalGlyphMeter.utilization(
            from: accounts,
            thresholdPercent: creditUtilizationThreshold,
            isStale: isSyncStale
        )
        return model.isEmpty ? nil : model
    }

    /// First attention row that actually carries menu-bar text. A higher-priority
    /// row without menu-bar text (e.g. an advisory recent-error) must not
    /// suppress a lower Cash/Credit/Spend badge.
    private var firstMenuBarAttentionText: String? {
        attentionQueue.rows.compactMap(\.menuBarAttentionText).first
    }

    var menuBarAttentionText: String? {
        menuBarStatusPresentation.attentionText ?? weeklyReviewPresentation.menuBarPrompt
    }

    var menuBarReviewText: String? {
        guard transactionReviewCount > 0 else { return nil }
        return "\(transactionReviewCount) review"
    }

    var menuBarHelpText: String {
        let reviewText = transactionReviewCount > 0
            ? " \(transactionReviewCount) transaction\(transactionReviewCount == 1 ? "" : "s") need review."
            : ""
        let status = "Status: \(diagnosticsSummary)"
        let review = weeklyReviewPresentation.menuBarPrompt.map { " Weekly review: \($0)." } ?? ""
        switch menuBarSummaryMode {
        case .netWorth:
            return "VaultPeek - Net worth: \(menuBarText).\(reviewText) \(status)\(review)"
        case .netCash:
            return "VaultPeek - Net cash: \(menuBarText).\(reviewText) \(status)\(review)"
        case .totalCash:
            return "VaultPeek - Total cash: \(menuBarText).\(reviewText) \(status)\(review)"
        case .creditUtilization:
            return "VaultPeek - Credit utilization: \(menuBarText).\(reviewText) \(status)\(review)"
        case .highestUtilization:
            return "VaultPeek - Highest card utilization: \(menuBarText).\(reviewText) \(status)\(review)"
        case .recentSpend:
            return "VaultPeek - Recent spend: \(menuBarText).\(reviewText) \(status)\(review)"
        case .todaySpend:
            return "VaultPeek - Today's spend: \(menuBarText).\(reviewText) \(status)\(review)"
        case .safeToSpend:
            return "VaultPeek - Safe to spend: \(menuBarText).\(reviewText) \(status)\(review)"
        case .iconOnly:
            return "VaultPeek.\(reviewText) \(status)\(review)"
        }
    }

    var menuBarAccessibilityLabel: String {
        let reviewText = transactionReviewCount > 0
            ? "\(transactionReviewCount) transaction\(transactionReviewCount == 1 ? "" : "s") need review. "
            : ""
        // diagnosticsSummary stays "healthy" for finance warnings, so fold the
        // visible finance badge (Cash/Credit/Spend) into the spoken status to
        // keep VoiceOver in sync with the badge sighted users see.
        let attention = menuBarAttentionText.map { ". Attention \($0)" } ?? ""
        let status = "Status \(diagnosticsSummary)\(attention)"
        let review = weeklyReviewPresentation.menuBarPrompt.map { " Weekly review \($0)." } ?? ""
        switch menuBarSummaryMode {
        case .netWorth:
            return "VaultPeek net worth \(menuBarText). \(reviewText)\(status)\(review)"
        case .netCash:
            return "VaultPeek net cash \(menuBarText). \(reviewText)\(status)\(review)"
        case .totalCash:
            return "VaultPeek total cash \(menuBarText). \(reviewText)\(status)\(review)"
        case .creditUtilization:
            return "VaultPeek credit utilization \(menuBarText). \(reviewText)\(status)\(review)"
        case .highestUtilization:
            return "VaultPeek highest card utilization \(menuBarText). \(reviewText)\(status)\(review)"
        case .recentSpend:
            return "VaultPeek recent spend \(menuBarText). \(reviewText)\(status)\(review)"
        case .todaySpend:
            return "VaultPeek today's spend \(menuBarText). \(reviewText)\(status)\(review)"
        case .safeToSpend:
            return "VaultPeek safe to spend \(menuBarText). \(reviewText)\(status)\(review)"
        case .iconOnly:
            return "VaultPeek. \(reviewText)\(status)\(review)"
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
        itemStatuses.filter { !$0.status.isDegraded }.count
    }

    var needsLoginItemCount: Int {
        itemStatuses.filter { $0.status.needsUpdateMode }.count
    }

    var erroredItemCount: Int {
        itemStatuses.filter { $0.status == .error }.count
    }

    /// Per-number completeness badge (AND-489): nil when data is complete and
    /// fresh, otherwise a `.stale` or `.partial` verdict mounted under derived
    /// numbers (net worth, utilization, cashflow, safe-to-spend).
    var dataIntegrityBadge: DataIntegrityBadge.Result? {
        DataIntegrityBadge.evaluate(
            isSyncStale: isSyncStale,
            isBootLoadInFlight: isBootLoadInFlight,
            itemCount: statusItemCount,
            syncedItemCount: serverSyncedItemCount ?? statusItemCount,
            degradedItemCount: itemStatuses.filter { $0.status.isDegraded }.count,
            needsSyncItemCount: itemStatuses.filter(\.needsSync).count,
            lastSync: lastSyncDate,
            lastSyncRelative: lastSyncRelative
        )
    }

    var degradedItemIds: Set<String> {
        Set(
            itemStatuses
                .filter { $0.status.isDegraded }
                .map(\.id)
        )
    }

    var diagnosticsSummary: String {
        if isDemoStatusRecoveryScenario {
            if erroredItemCount > 0 { return "\(erroredItemCount) demo item\(erroredItemCount == 1 ? "" : "s") need attention" }
            if needsLoginItemCount > 0 { return "\(needsLoginItemCount) demo item\(needsLoginItemCount == 1 ? "" : "s") need update" }
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
        if needsLoginItemCount > 0 { return "\(needsLoginItemCount) item\(needsLoginItemCount == 1 ? "" : "s") need update" }
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

    var firstRunSnapshotPresentation: FirstRunSnapshotPresentation? {
        FirstRunSnapshotPresentation.evaluate(
            accounts: accounts,
            transactions: transactions,
            completionState: firstRunCompletionState,
            isDismissed: isFirstRunSnapshotDismissed,
            isInitialLoad: isBootLoadInFlight,
            isDemoMode: isDemoMode,
            largeTransactionThreshold: largeTransactionThreshold
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

    var weeklyReviewPresentation: WeeklyReviewPresentation {
        let safeToSpend = SafeToSpendCalculator.compute(
            accounts: accounts,
            recurringTransactions: recurringTransactions,
            cashflow: WealthSummaryPresentation.evaluate(
                accounts: accounts,
                transactions: transactions,
                isDemoMode: usesDemoConnectionPresentation,
                serverConnected: serverConnected,
                credentialsConfigured: serverCredentialsConfigured,
                linkedItemCount: statusItemCount,
                syncedItemCount: serverSyncedItemCount ?? 0,
                itemStatuses: itemStatuses,
                isSyncStale: isSyncStale,
                lastSyncRelative: lastSyncRelative,
                statusSyncText: statusSyncText,
                errorMessage: error,
                creditUtilizationThreshold: creditUtilizationThreshold,
                balanceHistory: balanceHistory
            ).cashflow,
            asOf: Date()
        )

        return WeeklyReviewBuilder.evaluate(
            state: weeklyReviewState,
            transactionState: weeklyReviewTransactionState,
            transactions: transactions,
            recurringTransactions: recurringTransactions,
            safeToSpend: safeToSpend,
            previousSafeToSpendAmount: persistedPreviousSafeToSpendAmount,
            categoryBudgets: categoryBudgetPresentation,
            itemStatuses: itemStatuses,
            isSyncStale: isSyncStale
        )
    }

    /// Cached category budget presentation — invalidated via transactions.didSet
    /// and categoryBudgets.didSet. Recomputed full-scan on every read otherwise,
    /// which `MenuBarLabel.body` triggers repeatedly through the weekly-review
    /// and menu-bar accessors.
    private var _cachedCategoryBudgetPresentation: CategoryBudgetPresentation?

    var categoryBudgetPresentation: CategoryBudgetPresentation {
        if let cached = _cachedCategoryBudgetPresentation { return cached }
        let presentation = computeCategoryBudgetPresentation()
        _cachedCategoryBudgetPresentation = presentation
        return presentation
    }

    private func computeCategoryBudgetPresentation() -> CategoryBudgetPresentation {
        let now = Date()
        let suggestedBudgets = CategoryBudgetPlanner.suggestedBudgets(
            from: transactions,
            asOf: now
        )
        let suggestedPresentation = CategoryBudgetPlanner.presentation(
            budgets: suggestedBudgets.filter { categoryBudgets[$0.key] == nil },
            transactions: transactions,
            asOf: now,
            areSuggested: true
        )

        guard !categoryBudgets.isEmpty else { return suggestedPresentation }

        let serverPresentation = CategoryBudgetPlanner.presentation(
            budgets: categoryBudgets,
            transactions: transactions,
            asOf: now
        )
        return Self.mergeCategoryBudgetPresentations(
            serverPresentation,
            suggestedPresentation
        )
    }

    private static func mergeCategoryBudgetPresentations(
        _ explicit: CategoryBudgetPresentation,
        _ suggested: CategoryBudgetPresentation
    ) -> CategoryBudgetPresentation {
        let explicitCategoryIds = Set(explicit.items.map(\.id))
        let items = (explicit.items + suggested.items.filter { !explicitCategoryIds.contains($0.id) })
            .sorted { lhs, rhs in
                if lhs.status != rhs.status {
                    return categoryBudgetStatusRank(lhs.status) < categoryBudgetStatusRank(rhs.status)
                }
                if lhs.fractionUsed != rhs.fractionUsed {
                    return lhs.fractionUsed > rhs.fractionUsed
                }
                if lhs.isSuggested != rhs.isSuggested {
                    return !lhs.isSuggested
                }
                return lhs.category.displayName < rhs.category.displayName
            }

        return CategoryBudgetPresentation(
            items: items,
            totalLimit: items.reduce(0) { $0 + $1.monthlyLimit },
            totalSpent: items.reduce(0) { $0 + $1.spent },
            overBudgetCount: items.reduce(0) { $0 + ($1.status == .over ? 1 : 0) },
            nearingCount: items.reduce(0) { $0 + ($1.status == .nearing ? 1 : 0) }
        )
    }

    private static func categoryBudgetStatusRank(_ status: CategoryBudgetStatus) -> Int {
        switch status {
        case .over: 0
        case .nearing: 1
        case .under: 2
        }
    }

    private var weeklyReviewTransactionState: WeeklyReviewTransactionState? {
        // Production weekly reviews require loaded transaction-review metadata.
        // Raw Plaid transactions alone are not treated as reviewed; demo mode
        // keeps using pending flags so the checklist surface remains locally
        // exercisable.
        guard !isDemoMode else {
            let unreviewed = Set(transactions.filter(\.pending).map(\.id))
            let trusted = Set(transactions.map(\.id)).subtracting(unreviewed)
            return WeeklyReviewTransactionState(
                trustedTransactionIds: trusted,
                unreviewedTransactionIds: unreviewed
            )
        }

        guard hasLoadedTransactionReviewStorage,
              !transactions.isEmpty
        else { return nil }

        // Classify by the tested trust contract (metadata status), not by the
        // Review Inbox snapshot. `TransactionReviewInbox.evaluate` only emits an
        // item when a transaction trips a heuristic reason, so a transaction the
        // user never reviewed (status `.needsReview`, or no metadata yet) that
        // happens to trip no heuristic would otherwise be miscounted as trusted,
        // under-reporting the "needs review" count.
        return WeeklyReviewTransactionState.derived(
            from: transactions,
            metadata: transactionReviewMetadata
        )
    }

    private var persistedPreviousSafeToSpendAmount: Double? {
        let defaults = UserDefaults.standard
        guard defaults.object(forKey: Keys.weeklyReviewPreviousSafeToSpend) != nil else { return nil }
        return defaults.double(forKey: Keys.weeklyReviewPreviousSafeToSpend)
    }

    /// Cached review inbox snapshot — invalidated via transactions.didSet,
    /// transactionReviewMetadata.didSet, and transactionRules.didSet. The
    /// underlying scan is O(n) (peer aggregates are precomputed once in
    /// `TransactionReviewInbox.evaluate`), but `MenuBarLabel.body` reads
    /// `transactionReviewCount` from several accessors per render, so memoizing
    /// avoids re-running the whole scan multiple times for one frame.
    private var _cachedTransactionReviewInboxSnapshot: TransactionReviewInboxSnapshot?

    var transactionReviewInboxSnapshot: TransactionReviewInboxSnapshot {
        if let cached = _cachedTransactionReviewInboxSnapshot { return cached }
        let snapshot = TransactionReviewInbox.evaluate(
            transactions: transactions,
            metadata: transactionReviewMetadata,
            rules: transactionRules,
            recurring: recurringTransactions,
            now: Date()
        )
        _cachedTransactionReviewInboxSnapshot = snapshot
        return snapshot
    }

    var transactionReviewCount: Int {
        transactionReviewInboxSnapshot.totalCount
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
        // Align the stale threshold with the automatic-refresh floor so a normally
        // behaving install (now refreshing at most ~twice a day) doesn't flag
        // "stale"/broken-connection between refreshes. Manual-only has no floor,
        // so allow a full day before nagging.
        let policyFloor = automaticRefreshPolicy.minimumInterval ?? (24 * 60 * 60)
        let staleAfter = max(
            refreshInterval * 2,
            PlaidBarConstants.transactionSyncInterval * 2,
            policyFloor + 60 * 60
        )
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
        transactionDerivedIndex.recentFeedEntries.map(\.transaction)
    }

    /// Cached transaction index — invalidated via transactions.didSet.
    private var _cachedTransactionDerivedIndex: TransactionDerivedIndex?

    var transactionDerivedIndex: TransactionDerivedIndex {
        if let cached = _cachedTransactionDerivedIndex { return cached }
        let index = TransactionDerivedIndex(transactions: transactions)
        _cachedTransactionDerivedIndex = index
        return index
    }

    /// Cached recurring detection — invalidated via transactions.didSet
    private var _cachedRecurringTransactions: [RecurringTransaction]?

    var recurringTransactions: [RecurringTransaction] {
        if let cached = _cachedRecurringTransactions { return cached }
        let start = performanceStart()
        let result = RecurringDetector.detect(from: transactionDerivedIndex)
        _cachedRecurringTransactions = result
        recordPerformance(
            .derivedSummaryRecompute,
            startedAt: start,
            counts: [
                .transactionTotalCount: transactions.count,
                .recurringCount: result.count,
            ],
            outcome: .success
        )
        return result
    }

    /// Monthly equivalent of all recurring charges (normalizes weekly/annual to monthly)
    var estimatedMonthlyRecurring: Double {
        RecurringSummary.estimatedMonthlyTotal(from: recurringTransactions, asOf: Date())
    }

    var localAIAvailability: LocalAIAvailability {
        if let probeAvailability = localAIProbeAvailability {
            return probeAvailability
        }
        if let generatedAvailability = _cachedLocalAIActivitySummaries?
            .first(where: { $0.window == .lastMonth })?
            .availability,
            generatedAvailability.state == .available
        {
            return generatedAvailability
        }
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
        let start = performanceStart()
        let result = localAIInsightsService.activitySummaries(
            accounts: accounts,
            transactions: transactions,
            recurringTransactions: recurringTransactions
        )
        _cachedLocalAIActivitySummaries = result
        recordLocalAIActivitySummaryPerformance(
            startedAt: start,
            summaries: result,
            accountCount: accounts.count,
            transactionCount: transactions.count
        )
        return result
    }

    private func invalidateLocalAIActivitySummaries() {
        localAIProbeGeneration += 1
        localAIProbeAvailability = nil
        _cachedLocalAIActivitySummaries = nil
        scheduleLocalAIActivitySummaryRefresh()
    }

    func checkLocalAIAvailability() async {
        guard !isCheckingLocalAIAvailability else { return }
        let generation = localAIProbeGeneration
        let service = localAIInsightsService
        isCheckingLocalAIAvailability = true
        defer { isCheckingLocalAIAvailability = false }
        let availability = await service.probeAvailability()
        guard generation == localAIProbeGeneration else { return }
        localAIProbeAvailability = availability
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

            let start = performanceStart()
            let generated = await service.generatedActivitySummaries(
                accounts: accountSnapshot,
                transactions: transactionSnapshot,
                recurringTransactions: recurringSnapshot
            )
            guard !Task.isCancelled else { return }
            _cachedLocalAIActivitySummaries = generated
            recordLocalAIActivitySummaryPerformance(
                startedAt: start,
                summaries: generated,
                accountCount: accountSnapshot.count,
                transactionCount: transactionSnapshot.count
            )
        }
    }

    func transactionsForAccount(_ accountId: String) -> [TransactionDTO] {
        accountActivitySnapshot(for: accountId).transactions
    }

    func accountActivitySnapshot(for accountId: String) -> AccountTransactionFeed.AccountActivitySnapshot {
        AccountTransactionFeed.activitySnapshot(forAccountId: accountId, in: transactionDerivedIndex)
    }

    func transactionsForMerchant(_ merchantName: String, excluding transactionId: String) -> [TransactionDTO] {
        AccountTransactionFeed.relatedMerchantTransactions(
            merchantName: merchantName,
            excluding: transactionId,
            in: transactionDerivedIndex
        )
    }

    // MARK: - Actions

    func checkServerConnection() async {
        let statusStart = performanceStart()
        do {
            let status = try await serverClient.getStatusIncludingItems()
            recordPerformance(
                .statusFetch,
                startedAt: statusStart,
                counts: [.itemCount: status.itemCount],
                outcome: .success
            )
            serverConnected = true
            error = nil
            applyServerStatus(status)
            persistTransactionCacheContext()
            refreshSetupCompletionForActiveContext()
            refreshFirstRunSnapshotDismissalForActiveContext()
            if let itemStatuses = status.itemStatuses {
                applyItemStatuses(itemStatuses, itemCount: status.itemCount, syncReady: status.syncReady)
            } else if !(await refreshItemStatuses()) {
                itemStatuses = []
                updateSetupCompletion()
            }
            await upgradeManagedServerIfCredentialsArrived()
        } catch {
            recordPerformance(.statusFetch, startedAt: statusStart, outcome: .failure)
            serverConnected = false
            serverEnvironment = nil
            serverVersion = nil
            serverItemCount = nil
            serverCredentialsConfigured = nil
            serverStoragePath = nil
            serverSyncReady = nil
            serverSyncedItemCount = nil
            billingSubscription = nil
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

    /// Minimum interval between billable live `/accounts/balance/get` refreshes,
    /// so rapid clicks of the refresh button/control can't run up per-call Plaid
    /// balance fees.
    private static let liveBalanceRefreshCooldown: TimeInterval = 30
    private var lastLiveBalanceRefreshAt: Date?

    /// True when a live balance refresh is allowed (first time, or past the
    /// cooldown window since the last live call).
    private func liveBalanceRefreshAllowed() -> Bool {
        guard let last = lastLiveBalanceRefreshAt else { return true }
        return Date().timeIntervalSince(last) >= Self.liveBalanceRefreshCooldown
    }

    /// `/accounts/balance/get` can return `current: nil` (with only `available`
    /// set) for some institutions. The UI derives debt and utilization from
    /// `current ?? 0`, so backfill nil `current`/`limit` from the cached balance
    /// — a live refresh must never zero those out.
    private func balancesPreservingCachedCurrent(_ refreshed: [AccountDTO]) -> [AccountDTO] {
        guard !accounts.isEmpty else { return refreshed }
        let cachedById = Dictionary(accounts.map { ($0.id, $0) }, uniquingKeysWith: { _, latest in latest })
        return refreshed.map { account in
            let balances = account.balances
            guard balances.current == nil || balances.limit == nil,
                  let cached = cachedById[account.id]
            else { return account }
            return AccountDTO(
                id: account.id,
                itemId: account.itemId,
                name: account.name,
                officialName: account.officialName,
                type: account.type,
                subtype: account.subtype,
                mask: account.mask,
                balances: BalanceDTO(
                    available: balances.available,
                    current: balances.current ?? cached.balances.current,
                    limit: balances.limit ?? cached.balances.limit,
                    isoCurrencyCode: balances.isoCurrencyCode ?? cached.balances.isoCurrencyCode
                ),
                institutionName: account.institutionName
            )
        }
    }

    /// - Parameter live: when `true`, pull genuinely live balances via
    ///   `/accounts/balance/get` (a fresh request at the institution) instead of
    ///   the cached `/accounts/get`. Reserved for user-initiated ("force")
    ///   refreshes so automatic ticks never add a billable live call.
    func refreshAccounts(live: Bool = false) async {
        if refreshDemoDataIfNeeded() { return }

        let refreshStart = performanceStart()
        isLoading = true
        error = nil
        do {
            let fetchedAccounts = try await (live ? serverClient.getBalances() : serverClient.getAccounts())
            let refreshedAccounts = live ? balancesPreservingCachedCurrent(fetchedAccounts) : fetchedAccounts
            let itemStatusesAvailable = await refreshItemStatuses()
            accounts = itemStatusesAvailable
                ? accountsPreservingUnavailableItems(refreshedAccounts)
                : accountsPreservingCachedAccountsMissingFromRefresh(refreshedAccounts)
            let cacheAccounts = accounts
            let cacheDirectory = activeStorageDirectoryURL
            let cacheContext = transactionCacheContext
            try await saveAccountsToCacheWithPerformance(cacheAccounts, to: cacheDirectory, context: cacheContext)
            serverItemCount = Set(accounts.map(\.itemId)).count
            serverSyncReady = (serverItemCount ?? 0) > 0
            recordBalanceSnapshot()
            updateSetupCompletion()
            recordPerformance(
                live ? .balancesRefresh : .accountsRefresh,
                startedAt: refreshStart,
                counts: [.accountCount: accounts.count],
                outcome: .success
            )
        } catch {
            await refreshItemStatuses()
            self.error = error.localizedDescription
            recordPerformance(live ? .balancesRefresh : .accountsRefresh, startedAt: refreshStart, outcome: .failure)
        }
        isLoading = false
    }

    func refreshBalances() async {
        if refreshDemoDataIfNeeded() { return }

        let refreshStart = performanceStart()
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
            try await saveAccountsToCacheWithPerformance(cacheAccounts, to: cacheDirectory, context: cacheContext)
            lastSyncDate = Date()
            recordBalanceSnapshot()
            recordPerformance(
                .balancesRefresh,
                startedAt: refreshStart,
                counts: [.accountCount: accounts.count],
                outcome: .success
            )
        } catch {
            await refreshItemStatuses()
            self.error = error.localizedDescription
            recordPerformance(.balancesRefresh, startedAt: refreshStart, outcome: .failure)
        }
        isLoading = false
    }

    /// Fetches the latest per-card liabilities. Best-effort and supplementary:
    /// a failure (e.g. items linked without the `liabilities` scope) leaves the
    /// previous set in place and never disturbs the dashboard.
    func refreshLiabilities() async {
        if isDemoMode {
            liabilities = DemoFixtures.liabilities()
            return
        }
        guard serverConnected, serverCredentialsConfigured != false else { return }
        if let fetched = try? await serverClient.getLiabilities() {
            liabilities = fetched
        }
    }

    func syncTransactions() async {
        if refreshDemoDataIfNeeded() { return }

        let syncStart = performanceStart()
        var pageCount = 0
        var addedCount = 0
        var modifiedCount = 0
        var removedCount = 0
        do {
            var hasMore = true
            var batch = TransactionSyncBatch(transactions: transactions)
            while hasMore {
                pageCount += 1
                guard pageCount <= PlaidBarConstants.maxTransactionSyncPages else {
                    throw AppStateError.transactionSyncPageLimitExceeded(
                        maxPages: PlaidBarConstants.maxTransactionSyncPages
                    )
                }
                let response = try await serverClient.syncTransactions()
                addedCount += response.added.count
                modifiedCount += response.modified.count
                removedCount += response.removed.count
                batch.apply(response)
                hasMore = response.hasMore
            }
            if batch.hasChanges {
                // Assign once for the logical sync so downstream SwiftUI
                // caches recompute only after all pages have been reduced.
                transactions = batch.transactions
                seedReviewMetadataForNewTransactions(batch.transactions)
                let cacheDirectory = activeStorageDirectoryURL
                let cacheContext = transactionCacheContext
                try await saveTransactionsToCacheWithPerformance(
                    batch.transactions,
                    to: cacheDirectory,
                    context: cacheContext
                )
            }
            try await serverClient.commitSyncCursors(batch.pendingCursors)
            lastSyncDate = Date()
            serverSyncedItemCount = statusItemCount
            await refreshItemStatuses()
            updateSetupCompletion()
            recordPerformance(
                .transactionSync,
                startedAt: syncStart,
                counts: [
                    .pageCount: pageCount,
                    .transactionAddedCount: addedCount,
                    .transactionModifiedCount: modifiedCount,
                    .transactionRemovedCount: removedCount,
                    .transactionTotalCount: batch.transactions.count,
                ],
                outcome: .success
            )
        } catch {
            await refreshItemStatuses()
            self.error = error.localizedDescription
            recordPerformance(
                .transactionSync,
                startedAt: syncStart,
                counts: [
                    .pageCount: pageCount,
                    .transactionAddedCount: addedCount,
                    .transactionModifiedCount: modifiedCount,
                    .transactionRemovedCount: removedCount,
                ],
                outcome: .failure
            )
        }
    }

    func refreshCategoryBudgets() async {
        guard !isDemoMode else { return }
        do {
            let budgets = try await serverClient.listCategoryBudgets()
            categoryBudgets = Dictionary(
                budgets.map { ($0.category, $0.monthlyLimit) }
            ) { first, _ in first }
            persistCategoryBudgetCache()
        } catch {
            // Keep the last-known in-memory budgets (or local suggestions) visible
            // when the companion server is offline or the endpoint errors; never
            // replace a valid UI state with an empty cache on refresh failure.
            self.error = error.localizedDescription
        }
    }

    func setCategoryBudget(_ category: SpendingCategory, amount: Double) async {
        guard !CategoryBudgetPlanner.excludedCategories.contains(category) else {
            error = "Income and transfer categories cannot be budgeted."
            return
        }
        guard amount > 0 else {
            await removeCategoryBudget(category)
            return
        }

        let previousValue = categoryBudgets[category]
        categoryBudgets[category] = amount
        error = nil
        do {
            let saved = try await serverClient.saveCategoryBudget(
                categoryId: category.rawValue,
                amount: amount
            )
            categoryBudgets[saved.category] = saved.monthlyLimit
            persistCategoryBudgetCache()
        } catch {
            if let previousValue {
                categoryBudgets[category] = previousValue
            } else {
                categoryBudgets.removeValue(forKey: category)
            }
            self.error = error.localizedDescription
        }
    }

    func removeCategoryBudget(_ category: SpendingCategory) async {
        let previousValue = categoryBudgets[category]
        categoryBudgets.removeValue(forKey: category)
        error = nil
        do {
            try await serverClient.deleteCategoryBudget(categoryId: category.rawValue)
            categoryBudgets.removeValue(forKey: category)
            persistCategoryBudgetCache()
        } catch {
            if let previousValue {
                categoryBudgets[category] = previousValue
            }
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
            transactionReviewMetadata = []
            transactionRules = []
            itemStatuses = []
            categoryBudgets = [:]
            // loadDemoData() replaced the in-memory balance history with a
            // synthetic 60-day series. Restore persisted real history when it
            // exists so the first real snapshot cannot persist a demo trend.
            loadPersistedBalanceHistory()
            // Same for the watchlist: loadDemoData() seeded demo nudges in memory
            // only; restore the user's real saved watchlist (or empty) so demo
            // Starbucks/Shopping targets never fire against real data.
            loadWatchlistTargets(defaults: .standard)
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

    /// Refreshes the dashboard. `force` distinguishes a user-triggered refresh
    /// (the refresh button / recovery actions — always fetches) from an
    /// automatic one (the background loop — fetches only when due per
    /// `automaticRefreshPolicy`). Connectivity is re-probed either way so the
    /// loop keeps self-healing and notifications stay current.
    func refreshDashboard(force: Bool = true) async {
        if refreshDemoDataIfNeeded() { return }

        if await consumePendingGlanceCommand() { return }
        let dashboardStart = performanceStart()
        await checkServerConnection()
        // Setup state (credentials missing) cannot refresh anything from
        // Plaid; the status surfaces guide the user instead of surfacing a
        // 503 banner on every cycle.
        if serverConnected, serverCredentialsConfigured != false, force || shouldAutoRefreshNow {
            // A user-initiated (force) refresh pulls live balances via
            // /accounts/balance/get, but at most once per cooldown window so
            // rapid clicks can't run up per-call Plaid balance fees. Automatic
            // ticks always stay on cached /accounts/get.
            let useLive = force && liveBalanceRefreshAllowed()
            if useLive { lastLiveBalanceRefreshAt = Date() }
            await refreshAccounts(live: useLive)
            await syncTransactions()
            await refreshLiabilities()
        }
        if serverConnected {
            await refreshCategoryBudgets()
        }
        recordPerformance(
            .dashboardRefresh,
            startedAt: dashboardStart,
            counts: [
                .accountCount: accounts.count,
                .transactionTotalCount: transactions.count,
                .itemCount: statusItemCount,
            ],
            outcome: error == nil ? .success : .failure
        )
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
        await refreshCategoryBudgets()
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
            transactionReviewMetadata.removeAll { metadata in
                !transactions.contains { $0.id == metadata.id }
            }
            do {
                let cacheAccounts = accounts
                let cacheTransactions = transactions
                let cacheDirectory = activeStorageDirectoryURL
                let cacheContext = transactionCacheContext
                try await saveAccountsToCacheWithPerformance(cacheAccounts, to: cacheDirectory, context: cacheContext)
                try await saveTransactionsToCacheWithPerformance(
                    cacheTransactions,
                    to: cacheDirectory,
                    context: cacheContext
                )
                persistReviewStorage()
            } catch {
                self.error = "Local cache failed to save: \(error.localizedDescription)"
            }
            // Refresh (or clear, when the last institution is gone) the widget
            // snapshot so it never shows balances for just-removed accounts.
            writeGlanceSnapshot()
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
        transactionReviewMetadata = []
        transactionRules = []
        // Drop undo history too: a post-reset Undo must not restore pre-reset
        // review metadata/rules (old transaction ids, merchants, amounts).
        reviewUndoStack = []
        itemStatuses = []
        serverItemCount = 0
        serverCredentialsConfigured = nil
        serverSyncReady = nil
        serverSyncedItemCount = nil
        lastSyncDate = nil
        clearCategoryBudgetCache()
        UserDefaults.standard.set(false, forKey: resetSetupCompletionDefaultsKey)
        UserDefaults.standard.removeObject(forKey: firstRunSnapshotDismissalDefaultsKey)
        isSetupComplete = false
        isFirstRunSnapshotDismissed = false
        serverStoragePath = nil
        isDemoMode = false
        isDemoStatusRecoveryScenario = false
        error = nil

        balanceHistory = []
        UserDefaults.standard.removeObject(forKey: Keys.balanceHistory)
        // The per-account ledger holds bank IDs and balances and feeds the Time
        // Machine surface; the reset contract must wipe it (in memory and on
        // disk) so old data can't reappear after relaunch/reconnect (Codex P1).
        // Clear both the active namespaced key and the legacy global key.
        accountBalanceLedger = AccountBalanceLedger()
        syncHistoryDiffRows = []
        UserDefaults.standard.removeObject(forKey: accountBalanceLedgerDefaultsKey)
        UserDefaults.standard.removeObject(forKey: Keys.accountBalanceLedger)
        await clearGlanceSnapshot()
        UserDefaults.standard.removeObject(forKey: Keys.lastTransactionCacheContext)
        UserDefaults.standard.removeObject(forKey: Keys.weeklyReviewState)
        UserDefaults.standard.removeObject(forKey: Keys.weeklyReviewPreviousSafeToSpend)
        weeklyReviewState = .empty
        notificationService.resetDeduplicationState()

        return result
    }

    /// Starts the background refresh loop only if one is not already running.
    /// Used by the boot bootstrap so both the online and offline `loadInitialData()`
    /// paths leave the self-healing loop running without restarting an existing one.
    func startBackgroundRefreshIfNeeded() {
        guard refreshTask == nil else { return }
        startBackgroundRefresh()
    }

    func startBackgroundRefresh() {
        refreshTask?.cancel()
        refreshTask = Task {
            while !Task.isCancelled {
                if appLockPreferences.shouldRefreshFinancialData(isAppLocked: isAppLocked) {
                    // Automatic tick: only fetches Plaid data when due per the
                    // refresh policy; connectivity re-probe still runs each tick.
                    await refreshDashboard(force: false)
                }
                if appLockPreferences.shouldEvaluateFinancialNotifications(isAppLocked: isAppLocked) {
                    await evaluateNotifications()
                }
                try? await Task.sleep(for: .seconds(refreshInterval))
            }
        }
    }

    private func evaluateNotifications() async {
        guard notificationsEnabled else { return }
        guard appLockPreferences.shouldEvaluateFinancialNotifications(isAppLocked: isAppLocked) else { return }
        let config = NotificationTriggers(
            largeTransaction: notifyLargeTransaction,
            lowBalance: notifyLowBalance,
            highUtilization: notifyHighUtilization,
            recurringChargeDetected: notifyRecurringChargeDetected,
            recurringChargeChanged: notifyRecurringChargeChanged,
            recurringChargeDueSoon: notifyRecurringChargeDueSoon,
            staleSync: notifyBrokenConnection,
            loginRequired: notifyBrokenConnection,
            itemError: notifyBrokenConnection,
            watchlist: notifyWatchlist,
            largeTransactionThreshold: largeTransactionThreshold,
            lowBalanceThreshold: lowBalanceThreshold,
            creditUtilizationThreshold: creditUtilizationThreshold
        )
        await notificationService.evaluateTriggers(
            transactions: transactions,
            accounts: accounts,
            recurringTransactions: recurringTransactions,
            itemStatuses: itemStatuses,
            watchlistTargets: watchlistTargets,
            isSyncStale: isSyncStale,
            config: config
        )
    }

    func requestNotificationPermission() async -> Bool {
        let granted = await notificationService.requestPermission()
        notificationPermissionState = await notificationService.checkPermissionStatus()
        return granted
    }

    func toggleWeeklyReviewItem(_ item: WeeklyReviewItem) {
        if weeklyReviewState.completedItemIds.contains(item.id) {
            weeklyReviewState.completedItemIds.remove(item.id)
        } else {
            weeklyReviewState.completedItemIds.insert(item.id)
        }
    }

    func completeWeeklyReview() {
        let presentation = weeklyReviewPresentation
        weeklyReviewState.completedItemIds.formUnion(presentation.items.map(\.id))
        weeklyReviewState.dismissedItemIds = []
        weeklyReviewState.lastCompletedAt = Date()
        UserDefaults.standard.set(currentSafeToSpendAmount(), forKey: Keys.weeklyReviewPreviousSafeToSpend)
    }

    /// Set when a weekly-review action targets a surface that opens elsewhere
    /// (e.g. the review inbox or recurring inspector in MainPopover). The view
    /// observes this and performs the navigation, then clears it.
    var weeklyReviewNavigation: WeeklyReviewNavigationTarget?

    func performWeeklyReviewAction(_ item: WeeklyReviewItem) {
        switch item.action {
        case .openReviewInbox:
            // The transaction review inbox is available now, so route the user
            // to it rather than reporting it as missing.
            weeklyReviewNavigation = .reviewInbox
        case .inspectCategory:
            // No category-budget surface exists to navigate to yet. The drift
            // item is an informational flag, not a recoverable failure, so this
            // is a deliberate no-op rather than the error-banner path — surfacing
            // a red failure banner here read as a broken action (AND-466).
            break
        case .reviewRecurring:
            weeklyReviewNavigation = .recurring
        case .inspectSafeToSpend:
            weeklyReviewNavigation = .safeToSpend
        case .reconnectAccount:
            guard let itemId = ItemRecoveryTarget.itemId(from: itemStatuses) else {
                Task { await refreshDashboard() }
                return
            }
            Task { await reconnectItem(itemId: itemId) }
        case .refreshData:
            Task { await refreshDashboard() }
        }
    }

    func dismissFirstRunSnapshot() {
        isFirstRunSnapshotDismissed = true
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

        // Re-assert the launch lock before data work as a defensive/idempotent
        // guard. The first-render privacy guarantee is established in init;
        // keeping this call protects any test or future construction path that
        // invokes loadInitialData after mutating App Lock preferences.
        lockOnLaunchIfNeeded()

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
        _ = await consumePendingGlanceCommand()
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
                // Don't hit Plaid on every open: show cached data and only
                // auto-refresh when it's actually due (twice a day by default,
                // or never under "manual only"). `lastSyncDate` was just set
                // from the server's persisted last sync by checkServerConnection,
                // so this survives app restarts. The manual refresh button still
                // updates on demand.
                if shouldAutoRefreshNow {
                    await refreshAccounts()
                    await syncTransactions()
                    await refreshLiabilities()
                }
            }
            await refreshCategoryBudgets()
        } else {
            // Offline cold start: evaluate once immediately so a stale-sync /
            // broken-connection alert can still fire for cached or never-synced
            // state booted without a reachable local server, before the loop's
            // first sleep elapses.
            await evaluateNotifications()
        }
        // Start the self-healing background refresh loop on every boot path
        // (online and offline). The loop re-probes connectivity via
        // `refreshDashboard` and is gated by the app-lock predicates, so an
        // offline-at-boot launch recovers automatically once the server comes
        // up instead of staying frozen. Idempotent: never starts a second task.
        startBackgroundRefreshIfNeeded()
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

        if let cachedAccounts = try? await loadAccountsFromCacheWithPerformance(
            from: cacheDirectory,
            context: context
        ), !cachedAccounts.isEmpty {
            accounts = cachedAccounts
        }
        if let cachedTransactions = try? await loadTransactionsFromCacheWithPerformance(
            from: cacheDirectory,
            context: context
        ), !cachedTransactions.isEmpty {
            transactions = cachedTransactions
        }
        if let cachedMetadata = try? await localDataCache.loadTransactionReviewMetadata(
            from: cacheDirectory,
            context: context
        ) {
            transactionReviewMetadata = cachedMetadata
            hasLoadedTransactionReviewStorage = true
        }
        if let cachedRules = try? await localDataCache.loadTransactionRules(
            from: cacheDirectory,
            context: context
        ) {
            transactionRules = cachedRules
        }
        loadCategoryBudgetCache(for: context)
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

    private func persistCategoryBudgetCache() {
        guard let transactionCacheContext else { return }
        let rawBudgets = Dictionary(
            categoryBudgets.map { ($0.key.rawValue, $0.value) },
            uniquingKeysWith: { first, _ in first }
        )
        guard let data = try? JSONEncoder().encode(
            CategoryBudgetCache(context: normalizedCacheContext(transactionCacheContext), budgets: rawBudgets)
        ) else { return }
        UserDefaults.standard.set(data, forKey: Keys.categoryBudgetCache)
    }

    private func loadCategoryBudgetCacheForActiveContext() {
        guard let transactionCacheContext else { return }
        loadCategoryBudgetCache(for: transactionCacheContext)
    }

    private func loadCategoryBudgetCache(for context: TransactionCacheContext) {
        guard let data = UserDefaults.standard.data(forKey: Keys.categoryBudgetCache),
              let cache = try? JSONDecoder().decode(CategoryBudgetCache.self, from: data),
              cache.context == normalizedCacheContext(context)
        else { return }

        categoryBudgets = Dictionary(
            cache.budgets.compactMap { rawCategory, monthlyLimit in
                guard let category = SpendingCategory(rawValue: rawCategory) else { return nil }
                return (category, monthlyLimit)
            },
            uniquingKeysWith: { first, _ in first }
        )
    }

    private func clearCategoryBudgetCache() {
        categoryBudgets = [:]
        UserDefaults.standard.removeObject(forKey: Keys.categoryBudgetCache)
    }

    // MARK: - Local Caches

    private func loadCachedAccounts() async {
        do {
            accounts = try await loadAccountsFromCacheWithPerformance(
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
            try await saveAccountsToCacheWithPerformance(
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
            transactions = try await loadTransactionsFromCacheWithPerformance(
                from: activeStorageDirectoryURL,
                context: transactionCacheContext
            )
            await loadTransactionReviewStorage()
        } catch {
            self.error = "Transaction cache failed to load: \(error.localizedDescription)"
        }
    }

    private func clearCachedTransactions() async {
        transactions = []
        do {
            try await saveTransactionsToCacheWithPerformance(
                transactions,
                to: activeStorageDirectoryURL,
                context: transactionCacheContext
            )
            transactionReviewMetadata = []
            transactionRules = []
            try await localDataCache.saveTransactionReviewMetadata(
                [],
                to: activeStorageDirectoryURL,
                context: transactionCacheContext
            )
            try await localDataCache.saveTransactionRules(
                [],
                to: activeStorageDirectoryURL,
                context: transactionCacheContext
            )
        } catch {
            self.error = "Transaction cache failed to clear: \(error.localizedDescription)"
        }
    }

    private func loadTransactionReviewStorage() async {
        hasLoadedTransactionReviewStorage = false
        do {
            transactionReviewMetadata = try await localDataCache.loadTransactionReviewMetadata(
                from: activeStorageDirectoryURL,
                context: transactionCacheContext
            )
            transactionRules = try await localDataCache.loadTransactionRules(
                from: activeStorageDirectoryURL,
                context: transactionCacheContext
            )
            seedReviewMetadataForNewTransactions(transactions)
            hasLoadedTransactionReviewStorage = true
        } catch {
            hasLoadedTransactionReviewStorage = false
            self.error = "Review inbox storage failed to load: \(error.localizedDescription)"
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
        let itemsStart = performanceStart()
        do {
            let statuses = try await serverClient.getItems()
            applyItemStatuses(statuses)
            recordPerformance(
                .itemsFetch,
                startedAt: itemsStart,
                counts: [.itemCount: statuses.count],
                outcome: .success
            )
            return true
        } catch {
            recordPerformance(.itemsFetch, startedAt: itemsStart, outcome: .failure)
            return false
        }
    }

    private func applyServerStatus(_ status: ServerStatus) {
        serverEnvironment = status.environment
        serverVersion = status.version
        serverItemCount = status.itemCount
        serverCredentialsConfigured = status.credentialsConfigured
        serverStoragePath = status.storagePath
        serverSyncReady = status.syncReady
        serverSyncedItemCount = status.syncedItemCount
        billingSubscription = status.billingSubscription
        lastSyncDate = status.lastSync
        updateSetupCompletion()
    }

    private func loadAccountsFromCacheWithPerformance(
        from directory: URL,
        context: TransactionCacheContext?
    ) async throws -> [AccountDTO] {
        let start = performanceStart()
        do {
            let cachedAccounts = try await localDataCache.loadAccounts(from: directory, context: context)
            recordPerformance(
                .localCacheLoad,
                startedAt: start,
                counts: [.cacheRecordCount: cachedAccounts.count, .accountCount: cachedAccounts.count],
                outcome: .success
            )
            return cachedAccounts
        } catch {
            recordPerformance(.localCacheLoad, startedAt: start, outcome: .failure)
            throw error
        }
    }

    private func saveAccountsToCacheWithPerformance(
        _ accounts: [AccountDTO],
        to directory: URL,
        context: TransactionCacheContext?
    ) async throws {
        let start = performanceStart()
        do {
            try await localDataCache.saveAccounts(accounts, to: directory, context: context)
            recordPerformance(
                .localCacheSave,
                startedAt: start,
                counts: [.cacheRecordCount: accounts.count, .accountCount: accounts.count],
                outcome: .success
            )
        } catch {
            recordPerformance(.localCacheSave, startedAt: start, outcome: .failure)
            throw error
        }
    }

    private func loadTransactionsFromCacheWithPerformance(
        from directory: URL,
        context: TransactionCacheContext?
    ) async throws -> [TransactionDTO] {
        let start = performanceStart()
        do {
            let cachedTransactions = try await localDataCache.loadTransactions(from: directory, context: context)
            recordPerformance(
                .localCacheLoad,
                startedAt: start,
                counts: [
                    .cacheRecordCount: cachedTransactions.count,
                    .transactionTotalCount: cachedTransactions.count,
                ],
                outcome: .success
            )
            return cachedTransactions
        } catch {
            recordPerformance(.localCacheLoad, startedAt: start, outcome: .failure)
            throw error
        }
    }

    private func saveTransactionsToCacheWithPerformance(
        _ transactions: [TransactionDTO],
        to directory: URL,
        context: TransactionCacheContext?
    ) async throws {
        let start = performanceStart()
        do {
            try await localDataCache.saveTransactions(transactions, to: directory, context: context)
            recordPerformance(
                .localCacheSave,
                startedAt: start,
                counts: [
                    .cacheRecordCount: transactions.count,
                    .transactionTotalCount: transactions.count,
                ],
                outcome: .success
            )
        } catch {
            recordPerformance(.localCacheSave, startedAt: start, outcome: .failure)
            throw error
        }
    }

    var performanceSnapshot: PerformanceSnapshot {
        performanceTrace.snapshot()
    }

    func clearPerformanceTrace() {
        performanceTrace.clear()
    }

    private func performanceStart() -> UInt64 {
        DispatchTime.now().uptimeNanoseconds
    }

    private func recordPerformance(
        _ operation: PerformanceOperation,
        startedAt start: UInt64,
        counts: [PerformanceCountKey: Int] = [:],
        outcome: PerformanceOutcome
    ) {
        let end = DispatchTime.now().uptimeNanoseconds
        performanceTrace.record(
            operation,
            durationNanoseconds: end >= start ? end - start : 0,
            counts: counts,
            outcome: outcome
        )
        emitPerformanceTraceIfRequested()
    }

    private func recordLocalAIActivitySummaryPerformance(
        startedAt start: UInt64,
        summaries: [LocalAIActivitySummary],
        accountCount: Int,
        transactionCount: Int
    ) {
        recordPerformance(
            .derivedSummaryRecompute,
            startedAt: start,
            counts: [
                .accountCount: accountCount,
                .transactionTotalCount: transactionCount,
                .activitySummaryCount: summaries.count,
            ],
            outcome: .success
        )
    }

    /// Local-only performance capture: run the app with `PLAIDBAR_PERF_TRACE=1`
    /// or `--perf-trace` to print the in-memory trace snapshot to stdout. The
    /// snapshot schema only contains operation names, coarse durations, counts,
    /// and outcomes; it has no fields for Plaid IDs, tokens, balances, payloads,
    /// merchant names, or storage paths.
    private func emitPerformanceTraceIfRequested() {
        let environmentFlag = ProcessInfo.processInfo.environment["PLAIDBAR_PERF_TRACE"] == "1"
        guard environmentFlag || CommandLine.arguments.contains("--perf-trace"),
              let data = try? JSONEncoder().encode(performanceTrace.snapshot()),
              let json = String(data: data, encoding: .utf8)
        else { return }

        print("PlaidBar performance trace: \(json)")
    }

    private func applyItemStatuses(
        _ statuses: [ItemStatus],
        itemCount: Int? = nil,
        syncReady: Bool? = nil
    ) {
        itemStatuses = statuses
        serverItemCount = itemCount ?? statuses.count
        serverSyncReady = syncReady ?? !statuses.isEmpty
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

    private func refreshFirstRunSnapshotDismissalForActiveContext() {
        let storedValue = storedFirstRunSnapshotDismissal()
        if isFirstRunSnapshotDismissed != storedValue {
            isFirstRunSnapshotDismissed = storedValue
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

    private func storedFirstRunSnapshotDismissal() -> Bool {
        UserDefaults.standard.bool(forKey: firstRunSnapshotDismissalDefaultsKey)
    }

    private func persistFirstRunSnapshotDismissal(_ isDismissed: Bool) {
        if isDismissed {
            UserDefaults.standard.set(true, forKey: firstRunSnapshotDismissalDefaultsKey)
        } else {
            UserDefaults.standard.removeObject(forKey: firstRunSnapshotDismissalDefaultsKey)
        }
    }

    private var setupCompletionDefaultsKey: String {
        let environment = setupCompletionEnvironment.rawValue
        let path = activeStorageDirectoryURL.standardizedFileURL.path
        let encodedPath = path.addingPercentEncoding(withAllowedCharacters: .alphanumerics) ?? path
        return "\(Keys.setupCompletedContextPrefix).\(environment).\(encodedPath)"
    }

    private var firstRunSnapshotDismissalDefaultsKey: String {
        let environment = setupCompletionEnvironment.rawValue
        let path = activeStorageDirectoryURL.standardizedFileURL.path
        let encodedPath = path.addingPercentEncoding(withAllowedCharacters: .alphanumerics) ?? path
        return "\(Keys.firstRunSnapshotDismissedContextPrefix).\(environment).\(encodedPath)"
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

        if let data = UserDefaults.standard.data(forKey: accountBalanceLedgerDefaultsKey),
           let ledger = try? JSONDecoder().decode(AccountBalanceLedger.self, from: data) {
            accountBalanceLedger = ledger
        } else {
            accountBalanceLedger = AccountBalanceLedger()
        }
    }

    /// Per-account ledger key, namespaced by the active Plaid environment and
    /// storage directory exactly like `setupCompletionDefaultsKey`. The ledger
    /// holds per-account IDs and balances, so a global key would let Time Machine
    /// surface the previous context's data after switching production/sandbox or
    /// changing `PLAIDBAR_DATA_DIR` (Codex P1). The legacy global
    /// `Keys.accountBalanceLedger` is only ever cleared, never read, so stale
    /// pre-namespacing data cannot leak across contexts.
    private var accountBalanceLedgerDefaultsKey: String {
        let environment = setupCompletionEnvironment.rawValue
        let path = activeStorageDirectoryURL.standardizedFileURL.path
        let encodedPath = path.addingPercentEncoding(withAllowedCharacters: .alphanumerics) ?? path
        return "\(Keys.accountBalanceLedger).context.\(environment).\(encodedPath)"
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
        recordAccountBalanceLedger()
        writeGlanceSnapshot()
    }

    /// Appends today's per-account bank-reported balances to the ledger and
    /// recomputes the sync-history diff against the prior ledger (AND-490).
    private func recordAccountBalanceLedger() {
        // Only ledger accounts the bank actually reported on THIS refresh. When a
        // partial refresh omits a degraded item (login-required / provider
        // outage), `accountsPreservingUnavailableItems` keeps that item's cached
        // accounts in `accounts`; stamping them with today's date would make Time
        // Machine show a stale cached balance as "what the bank said" today and
        // undermine the ledger's data-integrity purpose (Codex P2).
        let reportedAccounts = bankReportedAccountsForLedger()
        guard !reportedAccounts.isEmpty else { return }
        let previous = accountBalanceLedger
        let next = previous.appending(accounts: reportedAccounts)
        let nameByAccountId = Dictionary(
            reportedAccounts.map { ($0.id, $0.name) },
            uniquingKeysWith: { first, _ in first }
        )
        syncHistoryDiffRows = SyncHistoryDiff.evaluate(
            previousLedger: previous,
            nextLedger: next,
            displayName: { nameByAccountId[$0] }
        )
        accountBalanceLedger = next
        if let data = try? JSONEncoder().encode(next) {
            UserDefaults.standard.set(data, forKey: accountBalanceLedgerDefaultsKey)
        }
    }

    /// Accounts whose balances were genuinely reported by the bank on the current
    /// refresh — i.e. accounts that do NOT belong to a degraded item preserved
    /// from cache. When item statuses are unknown (empty), every account is
    /// treated as reported, matching the pre-AND-490 behavior.
    private func bankReportedAccountsForLedger() -> [AccountDTO] {
        guard !itemStatuses.isEmpty else { return accounts }
        let degradedItemIds = Set(
            itemStatuses.filter { $0.status.isDegraded }.map(\.id)
        )
        guard !degradedItemIds.isEmpty else { return accounts }
        return accounts.filter { !degradedItemIds.contains($0.itemId) }
    }

    private func writeGlanceSnapshot(updatedAt: Date = Date()) {
        // With no accounts (e.g. the user just disconnected their last
        // institution), clear the app-group snapshot instead of leaving the
        // previous balances on disk — otherwise the widget would keep showing
        // removed-account net worth until a later reset or successful write.
        guard !accounts.isEmpty else {
            Task {
                await clearGlanceSnapshot()
                await MainActor.run {
                    WidgetCenter.shared.reloadTimelines(ofKind: "PlaidBarGlanceWidget")
                }
            }
            return
        }
        glanceSnapshotWriteGeneration += 1
        let generation = glanceSnapshotWriteGeneration
        let snapshot = GlanceSnapshot.make(
            netWorth: netBalance,
            balanceHistory: balanceHistory,
            updatedAt: updatedAt,
            isDemo: isDemoMode
        )
        let debouncer = glanceSnapshotWriteDebouncer
        Task { [snapshot, debouncer, generation] in
            guard self.glanceSnapshotWriteGeneration == generation else { return }
            await debouncer.schedule(snapshot) { snapshot in
                let changed: Bool
                do {
                    changed = try GlanceSnapshotStore.saveIfChanged(snapshot)
                } catch {
                    // A genuine write failure was previously indistinguishable
                    // from the "no change" skip below. Surface it (no balance
                    // material is logged) so a stuck widget snapshot is
                    // diagnosable; otherwise behave as before and skip.
                    AppState.glanceSnapshotLogger.error(
                        "Failed to write glance snapshot: \(String(describing: error), privacy: .public)"
                    )
                    return
                }
                guard changed else { return }
                await MainActor.run {
                    WidgetCenter.shared.reloadTimelines(ofKind: "PlaidBarGlanceWidget")
                }
            }
        }
    }

    private func clearGlanceSnapshot() async {
        glanceSnapshotWriteGeneration += 1
        await glanceSnapshotWriteDebouncer.cancel()
        try? GlanceSnapshotStore.clear()
        // Tell WidgetKit to drop the already-issued timeline entry so the widget
        // surface stops showing pre-clear balances immediately. This covers
        // every clear path — the explicit reset/data-wipe (`resetLocalData`) and
        // removing the last institution — not just the empty-accounts write
        // branch, which previously reloaded on its own (AND-385 Codex review).
        WidgetCenter.shared.reloadTimelines(ofKind: "PlaidBarGlanceWidget")
    }

    /// Consume a pending widget/control command (e.g. the "Refresh balances"
    /// control) and run it. Reached from `loadInitialData()` and
    /// `refreshDashboard()`, and — because the control opens the app via its
    /// `openAppWhenRun` intent while the dashboard popover may be closed, so
    /// neither of those runs — also from the app's activation hook
    /// (`PlaidBarApp`). A no-op when no command file is pending, so calling it
    /// on every app activation is cheap (AND-385).
    @discardableResult
    func consumePendingGlanceCommand() async -> Bool {
        guard let request = try? GlanceSnapshotStore.consumeCommand() else { return false }
        switch request.command {
        case .refreshBalances:
            await refreshDashboardFromGlanceCommand(requestedAt: request.requestedAt)
        }
        return true
    }

    private func refreshDashboardFromGlanceCommand(requestedAt: Date) async {
        guard !isDemoMode else {
            loadDemoData()
            return
        }

        await checkServerConnection()
        if !serverConnected {
            // The control can cold-launch the app with the popover closed, so
            // `loadInitialData()` — which normally starts the bundled server —
            // never ran. Start it (and wait for it to come up) here so the
            // requested refresh actually reaches Plaid instead of being dropped
            // by the not-connected guard below.
            await startBundledServerIfAvailable()
        }
        guard serverConnected, serverCredentialsConfigured != false else {
            // The refresh could not reach the server, so no balances were
            // fetched. Do not stamp the snapshot as freshly updated at the click
            // time — that would present stale data as current. Leave the
            // last-success snapshot (and its real timestamp) in place.
            return
        }
        // The macOS "Refresh balances" control should reflect live balances too,
        // still gated by the cooldown so it can't run up paid Plaid calls.
        let useLive = liveBalanceRefreshAllowed()
        if useLive { lastLiveBalanceRefreshAt = Date() }
        await refreshAccounts(live: useLive)
        await syncTransactions()
    }

    private func loadPersistedWeeklyReviewState() {
        guard let data = UserDefaults.standard.data(forKey: Keys.weeklyReviewState),
              let state = try? JSONDecoder().decode(WeeklyReviewState.self, from: data)
        else {
            weeklyReviewState = .empty
            return
        }
        weeklyReviewState = state
    }

    private func persistWeeklyReviewState() {
        guard let data = try? JSONEncoder().encode(weeklyReviewState) else { return }
        UserDefaults.standard.set(data, forKey: Keys.weeklyReviewState)
    }

    private func currentSafeToSpendAmount() -> Double {
        let presentation = WealthSummaryPresentation.evaluate(
            accounts: accounts,
            transactions: transactions,
            isDemoMode: usesDemoConnectionPresentation,
            serverConnected: serverConnected,
            credentialsConfigured: serverCredentialsConfigured,
            linkedItemCount: statusItemCount,
            syncedItemCount: serverSyncedItemCount ?? 0,
            itemStatuses: itemStatuses,
            isSyncStale: isSyncStale,
            lastSyncRelative: lastSyncRelative,
            statusSyncText: statusSyncText,
            errorMessage: error,
            creditUtilizationThreshold: creditUtilizationThreshold,
            balanceHistory: balanceHistory
        )
        return SafeToSpendCalculator.compute(
            accounts: accounts,
            recurringTransactions: recurringTransactions,
            cashflow: presentation.cashflow,
            asOf: Date()
        ).amount
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
        liabilities = DemoFixtures.liabilities()
        transactions = DemoFixtures.transactions()
        transactionReviewMetadata = []
        transactionRules = []
        categoryBudgets = [:]
        balanceHistory = DemoFixtures.balanceHistory()
        // Seed demo watchlist nudges (AND-501) so the Settings Watchlists section
        // is populated and the evaluator fires against the demo transactions.
        // Loaded in-memory only — the guard suppresses `didSet` persistence so a
        // demo session never overwrites the user's real, saved watchlist.
        isLoadingDemoWatchlist = true
        watchlistTargets = DemoFixtures.watchlistTargets()
        isLoadingDemoWatchlist = false

        // Balance Time Machine (AND-490): seed a multi-day per-account ledger and
        // a post-sync diff so the Time Machine list and the "history changed"
        // badge are both visible without Plaid.
        let demoLedger = DemoFixtures.accountBalanceLedger()
        let demoPostSyncLedger = DemoFixtures.postSyncAccountBalanceLedger()
        accountBalanceLedger = demoPostSyncLedger
        let demoNameByAccountId = Dictionary(
            DemoFixtures.accounts.map { ($0.id, $0.name) },
            uniquingKeysWith: { first, _ in first }
        )
        syncHistoryDiffRows = SyncHistoryDiff.evaluate(
            previousLedger: demoLedger,
            nextLedger: demoPostSyncLedger,
            displayName: { demoNameByAccountId[$0] }
        )

        isSetupComplete = true
        serverConnected = true
        serverEnvironment = .sandbox
        serverVersion = PlaidBarConstants.appVersion
        serverItemCount = Set(accounts.map(\.itemId)).count
        serverCredentialsConfigured = true
        serverStoragePath = LocalDataStore.displayPath
        serverSyncReady = true
        serverSyncedItemCount = isDemoStatusRecoveryScenario ? 1 : serverItemCount
        // Partial-sync statuses (one connected + one degraded) come from
        // DemoFixtures so the AND-489 data-integrity badge renders `.partial`
        // in the recovery scenario; the happy path stays all-connected.
        let recoveryStatuses = DemoFixtures.partialSyncItemStatuses()
        itemStatuses = isDemoStatusRecoveryScenario ? recoveryStatuses : [
            ItemStatus(id: "demo_chase", institutionName: "Chase", status: .connected, lastSync: Date()),
            ItemStatus(id: "demo_amex_item", institutionName: "American Express", status: .connected, lastSync: Date()),
        ]
        lastSyncDate = isDemoStatusRecoveryScenario ? recoveryStatuses.first?.lastSync ?? Date() : Date()
        writeGlanceSnapshot(updatedAt: lastSyncDate ?? Date())
    }

    // MARK: - Transaction Review

    func approveReviewItem(_ id: String) {
        updateReviewMetadata(id: id) { metadata, transaction in
            metadata.status = .reviewed
            metadata.reviewedAt = Date()
            metadata.reviewReasonCodes = []
            metadata.lastSeenAmount = transaction.amount
            metadata.lastSeenName = transaction.name
            metadata.lastSeenPending = transaction.pending
        }
    }

    func ignoreReviewItem(_ id: String) {
        updateReviewMetadata(id: id) { metadata, transaction in
            metadata.status = .ignored
            metadata.reviewedAt = Date()
            metadata.lastSeenAmount = transaction.amount
            metadata.lastSeenName = transaction.name
            metadata.lastSeenPending = transaction.pending
        }
    }

    func updateReviewCategory(_ id: String, category: SpendingCategory) {
        updateReviewMetadata(id: id) { metadata, transaction in
            metadata.status = .reviewed
            metadata.userCategory = category
            metadata.reviewedAt = Date()
            metadata.reviewReasonCodes = []
            metadata.lastSeenAmount = transaction.amount
            metadata.lastSeenName = transaction.name
            metadata.lastSeenPending = transaction.pending
        }
    }

    func renameReviewMerchant(_ id: String, merchantName: String) {
        let trimmed = merchantName.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        updateReviewMetadata(id: id) { metadata, transaction in
            metadata.status = .reviewed
            metadata.userMerchantName = trimmed
            metadata.reviewedAt = Date()
            metadata.reviewReasonCodes = []
            metadata.lastSeenAmount = transaction.amount
            metadata.lastSeenName = transaction.name
            metadata.lastSeenPending = transaction.pending
        }
    }

    func markReviewItemTransfer(_ id: String, isTransfer: Bool = true) {
        updateReviewMetadata(id: id) { metadata, transaction in
            metadata.status = .reviewed
            metadata.isTransferOverride = isTransfer
            metadata.excludedFromBudgets = isTransfer
            metadata.reviewedAt = Date()
            metadata.reviewReasonCodes = []
            metadata.lastSeenAmount = transaction.amount
            metadata.lastSeenName = transaction.name
            metadata.lastSeenPending = transaction.pending
        }
    }

    func createRule(
        from item: TransactionReviewItem,
        category: SpendingCategory? = nil,
        markTransfer: Bool? = nil
    ) {
        let matcher = item.effectiveMerchantName.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !matcher.isEmpty else { return }
        let resolvedTransfer = markTransfer ?? (item.reasonCodes.contains(.possibleTransfer) ? true : item.isTransfer)
        pushReviewUndoState()
        transactionRules.append(TransactionRule(
            matchMerchantContains: matcher,
            matchOriginalNameContains: nil,
            category: category ?? item.effectiveCategory,
            merchantName: item.effectiveMerchantName,
            isTransfer: resolvedTransfer ? true : nil,
            excludedFromBudgets: (resolvedTransfer || item.excludedFromBudgets) ? true : nil
        ))
        approveReviewItemWithoutUndo(item.id)
        persistReviewStorage()
    }

    func undoLastReviewAction() {
        guard let previous = reviewUndoStack.popLast() else { return }
        transactionReviewMetadata = previous.metadata
        transactionRules = previous.rules
        persistReviewStorage()
    }

    private func updateReviewMetadata(
        id: String,
        mutate: (inout TransactionReviewMetadata, TransactionDTO) -> Void
    ) {
        guard let transaction = transactions.first(where: { $0.id == id }) else { return }
        pushReviewUndoState()
        var byId = Dictionary(uniqueKeysWithValues: transactionReviewMetadata.map { ($0.id, $0) })
        var metadata = byId[id] ?? TransactionReviewMetadata(id: id)
        mutate(&metadata, transaction)
        byId[id] = metadata
        transactionReviewMetadata = byId.values.sorted { $0.id < $1.id }
        persistReviewStorage()
    }

    private func approveReviewItemWithoutUndo(_ id: String) {
        guard let transaction = transactions.first(where: { $0.id == id }) else { return }
        var byId = Dictionary(uniqueKeysWithValues: transactionReviewMetadata.map { ($0.id, $0) })
        var metadata = byId[id] ?? TransactionReviewMetadata(id: id)
        metadata.status = .reviewed
        metadata.reviewedAt = Date()
        metadata.reviewReasonCodes = []
        metadata.lastSeenAmount = transaction.amount
        metadata.lastSeenName = transaction.name
        metadata.lastSeenPending = transaction.pending
        byId[id] = metadata
        transactionReviewMetadata = byId.values.sorted { $0.id < $1.id }
    }

    private func seedReviewMetadataForNewTransactions(_ transactions: [TransactionDTO]) {
        var byId = Dictionary(uniqueKeysWithValues: transactionReviewMetadata.map { ($0.id, $0) })
        var changed = false
        for transaction in transactions where byId[transaction.id] == nil {
            byId[transaction.id] = TransactionReviewMetadata(
                id: transaction.id,
                lastSeenAmount: transaction.amount,
                lastSeenName: transaction.name,
                lastSeenPending: transaction.pending
            )
            changed = true
        }
        guard changed else { return }
        transactionReviewMetadata = byId.values.sorted { $0.id < $1.id }
        persistReviewStorage()
    }

    private func pushReviewUndoState() {
        reviewUndoStack.append((transactionReviewMetadata, transactionRules))
        if reviewUndoStack.count > 20 {
            reviewUndoStack.removeFirst(reviewUndoStack.count - 20)
        }
    }

    private func persistReviewStorage() {
        let metadata = transactionReviewMetadata
        let rules = transactionRules
        let cacheDirectory = activeStorageDirectoryURL
        let cacheContext = transactionCacheContext
        let cache = localDataCache
        // Hand the full snapshot to the serial writer instead of spawning an
        // independent Task. Independent tasks could complete out of order, letting
        // a stale write overwrite a newer one; the writer applies snapshots in
        // enqueue order so the last logical state always wins on disk.
        reviewStorageWriter.enqueue { [weak self] in
            do {
                try await cache.saveTransactionReviewMetadata(metadata, to: cacheDirectory, context: cacheContext)
                try await cache.saveTransactionRules(rules, to: cacheDirectory, context: cacheContext)
            } catch {
                await self?.reportReviewStorageFailure(error.localizedDescription)
            }
        }
    }

    private func reportReviewStorageFailure(_ description: String) {
        error = "Review inbox storage failed to save: \(description)"
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
