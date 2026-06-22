import SwiftUI
import PlaidBarCore
import PlaidBarCache
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
        static let selectedInsightWindow = "localAI.selectedInsightWindow"
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
            _cachedCategoryDashboardPresentation = nil
            _cachedTransactionReviewInboxSnapshot = nil
            invalidateLocalAIActivitySummaries()
        }
    }
    var transactionReviewMetadata: [TransactionReviewMetadata] = [] {
        didSet {
            _cachedTransactionReviewInboxSnapshot = nil
            // Spend math is now override-aware (AND-526/554): an approve /
            // recategorize / exclude edits this metadata, so the budget
            // presentation must recompute too — not only the inbox. The category
            // dashboard rollup shares the same override-aware aggregation
            // (AND-539), so it is invalidated on the same edits.
            _cachedCategoryBudgetPresentation = nil
            _cachedCategoryDashboardPresentation = nil
        }
    }
    var transactionRules: [TransactionRule] = [] {
        didSet {
            _cachedTransactionReviewInboxSnapshot = nil
            // A new/changed rule recategorizes or excludes spend, so invalidate
            // the budget presentation and the category dashboard rollup alongside
            // the inbox (AND-526/554, AND-539).
            _cachedCategoryBudgetPresentation = nil
            _cachedCategoryDashboardPresentation = nil
        }
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

    /// Per-window navigation model (AND-594). Owns the destination plus
    /// the dashboard filter / account selection / heatmap metric that previously
    /// lived as scattered view-level `@AppStorage` keys in `MainPopover`. This is
    /// the menu-bar popover's window's model; a window-first `Window` scene
    /// constructs its own, so two windows hold independent selection.
    ///
    /// `AppState` exposes this as a façade: the popover reads
    /// `appState.dashboardFilter` / `dashboardSelectedAccountID` /
    /// `dashboardHeatmapMode`, which delegate here and persist to the original
    /// UserDefaults keys — so popover behavior and on-disk persistence are
    /// unchanged.
    let navigationModel: NavigationModel

    /// Pending deep-link route awaiting the primary window (AND-597).
    ///
    /// The window-first primary scene is a declarative `Window`, not a
    /// `WindowGroup` with a presented value, so a deep-link cannot be passed *into*
    /// the open call. Instead the opener sets this slot, then calls
    /// `openWindow(id: "main")`; `AppShellView` consumes it on appear / change and
    /// applies it through its window's `NavigationModel`. It is set only by
    /// ``route(to:)`` and cleared by ``consumePendingRoute()``, so the round-trip
    /// is single-shot. Inert with the flag OFF: nothing opens the window then, so
    /// the slot is never read — flag-OFF behavior is unchanged.
    var pendingRoute: Route?

    /// The dashboard's account filter, persisted under `dashboard.accountFilter`.
    /// Setting a *new* filter clears the account selection, exactly as the
    /// popover's `.onChange(of:)` did (AND-373/375).
    var dashboardFilter: DashboardAccountFilterKind {
        get { navigationModel.dashboardFilter }
        set { navigationModel.dashboardFilter = newValue }
    }

    /// The selected account id ("" when none), persisted under
    /// `dashboard.selectedAccountId`.
    var dashboardSelectedAccountID: String {
        get { navigationModel.selectedAccountID }
        set { navigationModel.selectedAccountID = newValue }
    }

    /// The 365-day heatmap metric, persisted under `dashboard.heatmapMode`.
    var dashboardHeatmapMode: SpendingHeatmapMode {
        get { navigationModel.heatmapMode }
        set { navigationModel.heatmapMode = newValue }
    }

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
        didSet {
            _cachedCategoryBudgetPresentation = nil
            _cachedCategoryDashboardPresentation = nil
        }
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
        // Re-emit both App Group snapshots so the masked/unmasked state takes
        // effect on disk immediately: enabling the mask overwrites any prior real
        // figures with value-free snapshots; disabling restores the real values.
        // `writeGlanceSnapshot` also rewrites the App Intents `FinanceSnapshot`
        // (via `writeFinanceSnapshot`), so the widget glance snapshot and the
        // intents snapshot are redacted together — no stale real glance file is
        // left on disk while the app is masked (AND-517).
        writeGlanceSnapshot()
    }

    /// Applies a pending Control Center / Focus-filter privacy-mask command, if
    /// any. Drives the same `appLockPreferences.privacyMaskEnabled` path as the
    /// in-app eye toggle so persistence, the masked snapshot rewrite, and control
    /// reload all happen through the existing flow. A no-op (returns `false`) when
    /// no command is pending. Skipped while fully locked — App Lock already masks
    /// everything and owns reveal (mirrors `togglePrivacyMask`).
    ///
    /// Lives here (not in `PrivacyMaskControlCommandReader`) so it can re-emit both
    /// App Group snapshots via the file-private `writeGlanceSnapshot()`, exactly
    /// like `togglePrivacyMask` / `lockApp` / `unlockApp`. The extension that drops
    /// the command (Control Center toggle) already re-redacts the on-disk snapshot
    /// when enabling the mask; this makes the *activation* path deterministic too,
    /// so the snapshot is re-redacted the moment the app applies the command rather
    /// than at a later refresh (bug-hunt R2).
    @discardableResult
    func applyPendingPrivacyMaskControlCommand() -> Bool {
        guard let command = try? PrivacyMaskControlCommandReader.consume() else { return false }
        guard !isContentLocked else { return true }
        if appLockPreferences.privacyMaskEnabled != command.maskEnabled {
            appLockPreferences.privacyMaskEnabled = command.maskEnabled
        }
        // Re-emit both App Group snapshots after every consumed command, even when
        // the in-app preference already matches. A background Control Center/Focus
        // ON→OFF sequence can leave the persisted files masked while the app still
        // has `privacyMaskEnabled == false`; the queued OFF command must restore the
        // real App Group snapshots instead of being skipped as a state no-op.
        writeGlanceSnapshot()
        return true
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
    /// The insight time-window the user last chose in the Insights surface
    /// (AND-585 follow-up). All three windows — 7-day, 30-day, year-over-year — are
    /// already computed on-device every refresh; this only selects which one the
    /// surfaces read. Persisted like the other local-AI preferences; defaults to
    /// `.lastMonth` (the historical hardcoded window) so behavior is unchanged for
    /// anyone who never touches the selector. UI-only — no model run is triggered.
    var selectedInsightWindow: LocalAIInsightWindow = .lastMonth {
        didSet {
            guard selectedInsightWindow != oldValue, !isLoadingLocalAISettings else { return }
            UserDefaults.standard.set(selectedInsightWindow.rawValue, forKey: Keys.selectedInsightWindow)
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

    /// App-local savings-goals store (AND-606). Constructing it is cheap and does
    /// **no I/O** — goals are read lazily inside the store (`loadIfNeeded()` on the
    /// Goals destination's first appearance). Only the window-first Goals
    /// destination ever reads it, so with `WindowFirstFeatureFlag` OFF nothing
    /// touches goals storage and the popover boot path is byte-identical.
    let goalsStore = GoalsStore()
    /// Disposable SwiftData read-model cache for instant cold render (AND-566).
    /// Opened lazily and behind `try?`; `nil` whenever SwiftData is unavailable
    /// or the store fails to open, in which case the app behaves exactly as it
    /// did before this cache existed (the JSON/UserDefaults cold path). Opened
    /// against the directory it was created for so a server-directory change
    /// re-opens a fresh store. Never the source of truth. `internal` (not
    /// `private`) so the AND-566 wiring extension in
    /// `AppState+ReadModelCache.swift` can read/mutate it; still module-scoped.
    var readModelCacheStore: ReadModelCacheStore?
    var readModelCacheStoreDirectoryPath: String?
    /// Disposable per-transaction SwiftData cache for large-history paging
    /// (AND-567). Like ``readModelCacheStore`` it is lazily opened, scoped to the
    /// active data directory, never the source of truth, and gated by
    /// ``readModelCacheEnabled``. The AND-567 wiring extension in
    /// `AppState+TransactionCache.swift` reads/mutates it.
    var transactionCacheStore: TransactionCacheStore?
    var transactionCacheStoreDirectoryPath: String?
    /// Set false to disable the disposable read-model cache entirely; the app
    /// then renders exactly as it did before AND-566 (no hydrate, no persist).
    /// Plumbed for kill-switch/test parity, not surfaced in Settings.
    let readModelCacheEnabled: Bool
    private let appLockService = AppLockService()
    private let reviewStorageWriter = ReviewStorageWriter()
    private var localAIInsightsService = LocalAIInsightsService()
    private let notificationService: any NotificationServiceProtocol
    private var refreshTask: Task<Void, Never>?
    private var localAISummaryRefreshTask: Task<Void, Never>?
    /// Observer tokens for the OS power-state / thermal-state change
    /// notifications that drive energy-aware background refresh (AND-568).
    /// Retained so they can be removed in `deinit`.
    private var energyStateObservers: [NSObjectProtocol] = []
    /// The last energy-constrained verdict the power/thermal observers acted on.
    /// Cached so a power/thermal notification only restarts the refresh loop (and
    /// issues its connectivity probe) when the constrained verdict actually flips
    /// — not on every transition that stays on the same side of the boundary
    /// (e.g. `.nominal` → `.fair`, both unconstrained). `nil` until the first
    /// notification establishes a baseline.
    private var lastEnergyConstrainedVerdict: Bool?
    /// Observer token for `NSApplication.didBecomeActiveNotification`, used to
    /// re-probe Apple Foundation Models availability when the app reactivates so a
    /// transient FM state (model still downloading, Apple Intelligence just turned
    /// on in System Settings) recovers within the session instead of requiring a
    /// relaunch (AND-563/564). Retained so it can be removed in `deinit`.
    private var appActivationObserver: NSObjectProtocol?
    private let glanceSnapshotWriteDebouncer = GlanceSnapshotWriteDebouncer()
    private var glanceSnapshotWriteGeneration = 0
    private var reviewUndoStack: [(metadata: [TransactionReviewMetadata], rules: [TransactionRule])] = []
    /// While true, the per-row review mutators skip pushing their own undo snapshot
    /// because a single combined snapshot was already captured for the whole batch
    /// (see `withBatchedReviewUndo`). Lets bulk / multi-row actions collapse into one
    /// ⌘Z, matching the AND-528 bulk "Mark N reviewed" contract.
    private var isBatchingReviewUndo = false
    private var localAIEnabledPreference: Bool?
    private var localAIModelNamePreference: String?
    private var localAIProbeAvailability: LocalAIAvailability?
    private var localAIProbeGeneration = 0
    /// Detection-only Foundation Models (Apple Intelligence) tier state (AND-563).
    /// Probed cheaply via `FoundationModelsAvailabilityProbe`; `.unsupported` on
    /// any OS/build without Foundation Models, so the tier order is unchanged
    /// there. No insight generation is routed through Foundation Models yet.
    private let foundationModelsProbe = FoundationModelsAvailabilityProbe()
    private var foundationModelsTierState: LocalAIFoundationModelsTierState = .unsupported
    private var isLoadingLocalAISettings = false
    private var isLoadingAppLockPreferences = false
    private var isUpgradingManagedServer = false
    private var isStartingBundledServer = false
    private var lastAttemptedCredentialUpgradeConfig: String?

    // MARK: - Init

    init(
        notificationService: (any NotificationServiceProtocol)? = nil,
        readModelCacheEnabled: Bool = true,
        navigationModel: NavigationModel? = nil
    ) {
        _ = try? LocalDataStore.migrateLegacyDefaultStorageIfNeeded()
        self.notificationService = notificationService ?? NotificationService.shared
        self.readModelCacheEnabled = readModelCacheEnabled
        // The popover-window navigation model. Hydrates the last
        // filter/selection/heatmap from the original UserDefaults keys, so
        // persistence is preserved across the migration (façade).
        self.navigationModel = navigationModel ?? NavigationModel()
        loadSettings()
        // Record whether Apple Foundation Models is available so the tier resolver
        // can prefer it (AND-563) and, when available, the insight service routes
        // generation through it (AND-564). Cheap + synchronous. `loadSettings()`
        // already built the service with `.unsupported`; rebuild now that the probe
        // ran so the FM engine is wired on launch when Apple Intelligence is ready.
        foundationModelsTierState = foundationModelsProbe.currentState()
        rebuildLocalAIInsightsService()
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
        // Begin watching OS power/thermal transitions so the background refresh
        // cadence re-evaluates the moment Low Power Mode or thermal pressure
        // changes (AND-568). The observers only restart an already-running loop,
        // so registering here (before the loop starts in `loadInitialData`) is
        // safe and idempotent.
        startEnergyStateObservers()
    }

    // `isolated deinit` (SE-0371) so teardown runs on the main actor and can read
    // the actor-isolated observer tokens. Block-based NotificationCenter observers
    // must be explicitly removed; doing it here avoids leaking the two energy
    // observers if an AppState is ever torn down (e.g. in tests).
    isolated deinit {
        stopEnergyStateObservers()
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
            // Both headless renderers must run deterministically: a stale
            // `dashboard.detached = true` would spawn the floating window and
            // intercept either harness. The window-first harness builds its own
            // off-screen windows, so it likewise wants no detached popover.
            isRenderingSnapshot: CommandLineOptions.isRenderingSnapshot()
                || CommandLineOptions.isRenderingWindowFirst()
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
            // Locking masks financial values, so immediately overwrite both App
            // Group snapshots with value-free ones — no figures leak past the lock
            // via the widget / Control Center (glance snapshot) or Spotlight / Siri
            // / Shortcuts (App Intents snapshot). `writeGlanceSnapshot` redacts the
            // glance file and also re-emits the redacted `FinanceSnapshot` through
            // `writeFinanceSnapshot` (AND-517).
            writeGlanceSnapshot()
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
        // A successful unlock that fully clears the masked state must restore the
        // real figures on disk immediately, rather than leaving the value-free
        // snapshots written at lock time until the next data refresh. Mirrors the
        // disable path in `togglePrivacyMask`; guarded on `shouldMaskFinancialValues`
        // so a still-active Privacy Mask keeps the snapshots redacted (AND-517).
        if !shouldMaskFinancialValues {
            writeGlanceSnapshot()
        }
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

        if let storedWindow = defaults.string(forKey: Keys.selectedInsightWindow),
           let window = LocalAIInsightWindow(rawValue: storedWindow)
        {
            selectedInsightWindow = window
        } else {
            selectedInsightWindow = .lastMonth
        }
    }

    private func rebuildLocalAIInsightsService() {
        localAIProbeGeneration += 1
        localAIProbeAvailability = nil
        // AND-564: wire the Foundation Models insight engine ONLY when Apple
        // Intelligence is available, so the service's pure routing decision can
        // prefer it. On any OS/build without an available FM tier the model stays
        // nil and the state stays `.unsupported`, leaving the existing generation
        // path byte-identical to before AND-564.
        let foundationModelsModel: (any LocalInsightModel)? = foundationModelsTierState.isAvailable
            ? FoundationModelsInsightModel()
            : nil
        localAIInsightsService = LocalAIInsightsService(
            enabledPreference: localAIEnabledPreference,
            modelNamePreference: localAIModelNamePreference,
            foundationModelsModel: foundationModelsModel,
            foundationModelsState: foundationModelsTierState
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
        MenuBarAnnouncement.helpText(
            mode: menuBarSummaryMode,
            valueText: menuBarText,
            reviewCount: transactionReviewCount,
            diagnosticsSummary: diagnosticsSummary,
            weeklyReviewPrompt: weeklyReviewPresentation.menuBarPrompt
        )
    }

    var menuBarAccessibilityLabel: String {
        // diagnosticsSummary stays "healthy" for finance warnings, so the spoken
        // label folds the visible finance badge (Cash/Credit/Spend) into the
        // status to keep VoiceOver in sync with the badge sighted users see.
        MenuBarAnnouncement.accessibilityLabel(
            mode: menuBarSummaryMode,
            valueText: menuBarText,
            reviewCount: transactionReviewCount,
            diagnosticsSummary: diagnosticsSummary,
            attentionText: menuBarAttentionText,
            weeklyReviewPrompt: weeklyReviewPresentation.menuBarPrompt
        )
    }

    var lastSyncRelative: String? {
        guard let lastSyncDate else { return nil }
        return Formatters.relativeDate(lastSyncDate)
    }

    var statusModeText: String {
        StatusPanelText.mode(isDemoMode: isDemoMode, environment: serverEnvironment)
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
        StatusPanelText.serverCredentials(
            isDemoMode: isDemoMode,
            serverConnected: serverConnected,
            credentialsConfigured: serverCredentialsConfigured
        )
    }

    var serverSyncReadinessText: String {
        StatusPanelText.serverSyncReadiness(
            isDemoMode: isDemoMode,
            serverConnected: serverConnected,
            syncReady: serverSyncReady
        )
    }

    var refreshCadenceText: String {
        StatusPanelText.refreshCadence(interval: refreshInterval)
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

    /// Linked items in a transient, non-actionable provider outage. Degraded but
    /// self-healing — surfaced as a warning so the status cluster shows, never as
    /// a blocking reconnect prompt.
    var providerOutageItemCount: Int {
        itemStatuses.filter { $0.status.isProviderOutage }.count
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
        StatusPanelText.diagnosticsSummary(
            isDemoStatusRecoveryScenario: isDemoStatusRecoveryScenario,
            isDemoMode: isDemoMode,
            serverConnection: serverConnectionPresentation,
            statusItemCount: statusItemCount,
            erroredItemCount: erroredItemCount,
            needsLoginItemCount: needsLoginItemCount
        )
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
            providerOutageItemCount: providerOutageItemCount,
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
        // The budget scorer counts only current-calendar-month transactions. The
        // demo set anchors dates relative to `now`, so on the 1st/2nd of a month
        // the high-spend rows roll into the previous month and the dashboard
        // collapses to all-under. Score demo budgets against the dedicated
        // current-month-anchored rows so the under/near/over spread is stable
        // regardless of launch day (AND-543 review). Suggestions are suppressed in
        // demo mode (empty `transactions`) so only the seeded budgets show.
        let scoringTransactions = isDemoMode
            ? DemoFixtures.demoBudgetScoringTransactions()
            : transactions
        // Pass the live review metadata + rules so recategorizing / excluding a
        // transaction in the inbox actually moves the budget totals (AND-526/554).
        // The cache is invalidated whenever transactions, categoryBudgets,
        // transactionReviewMetadata, or transactionRules change.
        let presentation = CategoryBudgetPlanner.mergedPresentation(
            explicitBudgets: categoryBudgets,
            transactions: scoringTransactions,
            asOf: Date(),
            metadata: transactionReviewMetadata,
            rules: transactionRules
        )
        _cachedCategoryBudgetPresentation = presentation
        return presentation
    }

    /// Cached category dashboard rollup (AND-539) — the override-aware, 2-level
    /// group/leaf presentation the donut, status-bar tree, and flat table all
    /// render. Invalidated via the same `didSet`s as
    /// `categoryBudgetPresentation` (`transactions`, `categoryBudgets`,
    /// `transactionReviewMetadata`, `transactionRules`), so recategorizing /
    /// excluding / re-budgeting moves the dashboard immediately — never stale
    /// until an unrelated refresh.
    private var _cachedCategoryDashboardPresentation: CategoryDashboardPresentation?

    /// Override-aware current-month category rollup for the Category Dashboard card
    /// and detached window (AND-539). Built by ``CategoryDashboardBuilder`` from the
    /// same live inputs the budget presentation uses, so the two surfaces can never
    /// disagree on a category's spend.
    var categoryDashboardPresentation: CategoryDashboardPresentation {
        if let cached = _cachedCategoryDashboardPresentation { return cached }
        // Mirror `categoryBudgetPresentation`: in demo mode score against the
        // dedicated current-month-anchored rows so the under/near/over spread is
        // stable regardless of launch day (AND-543); otherwise use live transactions.
        let scoringTransactions = isDemoMode
            ? DemoFixtures.demoBudgetScoringTransactions()
            : transactions
        let presentation = CategoryDashboardBuilder.build(
            transactions: scoringTransactions,
            budgets: categoryBudgets,
            asOf: Date(),
            metadata: transactionReviewMetadata,
            rules: transactionRules,
            recurring: recurringTransactions
        )
        _cachedCategoryDashboardPresentation = presentation
        return presentation
    }

    private var weeklyReviewTransactionState: WeeklyReviewTransactionState? {
        // Production weekly reviews require loaded transaction-review metadata.
        // Raw Plaid transactions alone are not treated as reviewed; demo mode
        // keeps trusting non-pending rows so the checklist surface remains
        // locally exercisable without seeding metadata for every fixture, while
        // still honoring explicitly seeded `.needsReview` rows so the Review
        // Inbox and the Weekly Review agree. See `demoDerived` for the contract.
        guard !isDemoMode else {
            return WeeklyReviewTransactionState.demoDerived(
                from: transactions,
                metadata: transactionReviewMetadata
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

    // MARK: - Menu-bar glance (AND-616)

    /// The reduced menu-bar **glance** contract: the sync line, the
    /// high-signal glance metrics (net worth · safe-to-spend · to-review), and the
    /// ≤3 attention chips that deep-link into window destinations. Once
    /// window-first is the default (AND-616) this — not the full dashboard — is the
    /// menu-bar surface; the dashboard lives only in the window's Dashboard
    /// destination.
    ///
    /// Assembly lives in the pure `MenuBarGlanceModel.make` (PlaidBarCore) so the
    /// contract (≤4 metrics, ≤3 chips, each chip's route) is unit-tested without
    /// the app; this feeds it the live finance signals — the same
    /// `WealthSummaryPresentation` / `SafeToSpendCalculator` math the dashboard and
    /// the App Intents snapshot use, so no surface can disagree on the figures.
    /// Currency metrics honor Privacy Mask / App Lock via `shouldMaskFinancialValues`.
    var menuBarGlanceModel: MenuBarGlanceModel {
        let wealth = WealthSummaryPresentation.evaluate(
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
        let safeToSpend = SafeToSpendCalculator.compute(
            accounts: accounts,
            recurringTransactions: recurringTransactions,
            cashflow: wealth.cashflow,
            asOf: Date()
        ).amount

        return MenuBarGlanceModel.make(
            netWorth: wealth.netWorth,
            safeToSpend: safeToSpend,
            unreviewedCount: transactionReviewCount,
            syncStatusText: statusSyncText,
            syncSeverity: wealth.syncHealth.severity,
            attention: attentionQueue,
            isMasked: shouldMaskFinancialValues
        )
    }

    // MARK: - Window-first sidebar (AND-595)

    /// Items needing reconnect — the actionable degraded items the connection
    /// health strip surfaces in its reconnect-needed bucket. Drives the
    /// Accounts sidebar badge; excludes provider-outage items, which are
    /// non-actionable (VaultPeek retries them automatically).
    var sidebarReconnectNeededCount: Int {
        ConnectionHealthStrip.evaluate(itemStatuses)
            .buckets
            .first { $0.state == .reconnectNeeded }?
            .count ?? 0
    }

    /// Unacknowledged "alerts" backing the Alerts sidebar badge. The dedicated
    /// Alerts feed lands in Epic 6; until then this is the
    /// count of non-healthy `AttentionQueue` rows — the same "do I need to act?"
    /// rollup the menu-bar glance and Dashboard already key off, so the
    /// badge stays truthful and consistent across all three surfaces.
    var sidebarUnacknowledgedAlertCount: Int {
        attentionQueue.rows.filter { $0.severity != .healthy }.count
    }

    /// The per-destination textual count badges for the window-first sidebar.
    /// Pure assembly lives in `SidebarBadgeModel.make`
    /// (PlaidBarCore) so the view stays thin and the hide-when-zero / a11y-phrase
    /// policy is unit-tested; this just feeds it the live counts. Window-first
    /// surface only — the menu-bar popover never reads it.
    var sidebarBadgeModel: SidebarBadgeModel {
        SidebarBadgeModel.make(
            unreviewedCount: transactionReviewCount,
            overBudgetCount: categoryBudgetPresentation.overBudgetCount,
            unacknowledgedAlertCount: sidebarUnacknowledgedAlertCount,
            reconnectNeededCount: sidebarReconnectNeededCount,
            isMasked: shouldMaskFinancialValues
        )
    }

    // MARK: - Deep-link routing (AND-597)

    /// **The reusable deep-link entry point for the window-first shell.** Any
    /// surface — a menu-bar glance attention chip today, an App Intent in Epic 8
    /// tomorrow — routes a typed ``Route`` into the primary window by calling this.
    ///
    /// Because the primary scene is a declarative `Window` (not a `WindowGroup`
    /// with a presented value), the route cannot be threaded through the open
    /// call. So this performs a **pending-route handoff**: it stages the route in
    /// ``pendingRoute`` and asks the caller-supplied `openWindow` to bring the
    /// `Window` forward. ``AppShellView`` then consumes the pending route on
    /// appear / change and applies it to *its* window's `NavigationModel`
    /// (destination + selection), so the window lands exactly on the deep-link
    /// target.
    ///
    /// The `openWindow` closure is injected (the scene owns SwiftUI's
    /// `openWindow(id:)` environment action) rather than reached through
    /// `AppState`, mirroring how the command palette injects `openSettings` /
    /// `summon`. App Intents (Epic 8) will call this same method, passing the
    /// intent's `openWindow`, so the deep-link path has one definition.
    ///
    /// - Parameters:
    ///   - route: the destination + selection to land on.
    ///   - openWindow: brings the primary `Window` forward (the scene's
    ///     `openWindow(id: "main")`). A no-op default keeps headless callers /
    ///     previews safe; in that case the staged route is still applied by an
    ///     already-open `AppShellView`.
    func route(to route: Route, openWindow: @MainActor () -> Void = {}) {
        pendingRoute = route
        openWindow()
    }

    /// Consumes the staged ``pendingRoute`` (if any), applying it to the supplied
    /// window's `NavigationModel` and clearing the slot so it fires once.
    /// Called by ``AppShellView`` on appear and whenever `pendingRoute` changes —
    /// covering both "window already open" (change fires) and "window opened by
    /// this route" (appear fires) hand-offs.
    ///
    /// - Parameter navigationModel: the consuming window's per-window model. Each
    ///   `AppShellView` passes its own, so a route only ever lands in the
    ///   window that processed the hand-off.
    func consumePendingRoute(into navigationModel: NavigationModel) {
        guard let route = pendingRoute else { return }
        pendingRoute = nil
        navigationModel.apply(route.resolvingAccountSelection(in: accounts))
    }

    var notificationPermissionPresentation: NotificationPermissionPresentation {
        NotificationPermissionPresentation.evaluate(kind: notificationPermissionState.presentationKind)
    }

    var usesDemoConnectionPresentation: Bool {
        isDemoMode && !isDemoStatusRecoveryScenario
    }

    var isSyncStale: Bool {
        SyncStaleness.isStale(
            isBootLoadInFlight: isBootLoadInFlight,
            lastSyncDate: lastSyncDate,
            refreshInterval: refreshInterval,
            refreshPolicy: automaticRefreshPolicy,
            asOf: Date()
        )
    }

    var statusSyncText: String {
        SyncStaleness.statusText(
            isBootLoadInFlight: isBootLoadInFlight,
            lastSyncRelative: lastSyncRelative,
            isStale: isSyncStale
        )
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

    /// The shared, contextual recurring **empty/unavailable** state — the single
    /// source the window-first Dashboard and Planning recurring cards both render
    /// when nothing is detected, so the two surfaces stay identical. The Core
    /// engine (``SecondaryContentUnavailableState/recurring(isDemoMode:isInitialLoad:serverConnected:linkedItemCount:accountCount:syncedItemCount:transactionCount:errorMessage:)``)
    /// decides the contextual copy + next-step action from the live load signals;
    /// the views never branch on the inputs themselves.
    var recurringUnavailableState: SecondaryContentUnavailableState {
        SecondaryContentUnavailableState.recurring(
            isDemoMode: usesDemoConnectionPresentation,
            isInitialLoad: loadState(for: .recurring).isInitialLoad,
            serverConnected: serverConnected,
            linkedItemCount: statusItemCount,
            accountCount: accounts.count,
            syncedItemCount: serverSyncedItemCount ?? 0,
            transactionCount: transactions.count,
            errorMessage: error
        )
    }

    /// Dispatches the recovery action carried by ``recurringUnavailableState`` to
    /// the matching `AppState` method, mirroring the established mapping used by the
    /// accounts empty state in Settings so behavior stays consistent. Keeps the
    /// Dashboard and Planning recurring cards' action wiring identical.
    func performRecurringUnavailableAction(_ action: SecondaryContentUnavailableAction) {
        switch action {
        case .checkServer:
            Task { await checkServerConnection() }
        case .refreshAccounts:
            Task { await refreshAccounts() }
        case .syncTransactions:
            Task { await syncTransactions() }
        case .refresh:
            Task { await refreshDashboard() }
        case .addAccount:
            navigationModel.go(to: .accounts)
        case .clearFilters, .showWiderPeriod:
            break
        }
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

    /// Detection-only Foundation Models tier state for Settings surfacing
    /// (AND-563). `.unsupported` whenever Apple Intelligence can't be probed on
    /// this OS/build.
    var foundationModelsAvailability: LocalAIFoundationModelsTierState {
        foundationModelsTierState
    }

    /// The on-device AI tier VaultPeek would currently prefer, highest first.
    /// Apple Foundation Models sits on top WHEN available; otherwise this is
    /// exactly the tier order that existed before AND-563. Detection/ordering
    /// only — insight generation still runs on the existing path.
    var localAIPreferredTier: LocalAIRuntimeTier {
        LocalAITierResolver.resolvePreferredTier(
            facts: LocalAITierFacts(
                foundationModels: foundationModelsTierState,
                ollamaEngaged: LocalAIRuntimeResolution.usesModel(for: localAIAvailability.state),
                naturalLanguageReady: Self.naturalLanguageTierReady
            )
        )
    }

    /// The always-on NaturalLanguage categorizer (AND-507) ships whenever the
    /// framework is importable, which on macOS is always.
    private static var naturalLanguageTierReady: Bool {
        #if canImport(NaturalLanguage)
        true
        #else
        false
        #endif
    }

    /// The merchant categorizer for the current device, with the Foundation
    /// Models guided-generation tier (AND-565) slotted ABOVE NaturalLanguage when
    /// Apple Intelligence is available, and falling back to NaturalLanguage
    /// otherwise.
    ///
    /// Additive and reversible: the FM seam is wired ONLY when the probe reports
    /// `.available`; in every other state this returns a categorizer whose
    /// behavior is byte-identical to the always-on NaturalLanguage path, so the
    /// no-FM device is unchanged. The categorizer produces *suggestions* with
    /// provenance — it never auto-applies a category or bypasses the review /
    /// override flow (`EffectiveCategoryResolver` stays the source of truth for
    /// persisted categories).
    var merchantCategorizer: FMMerchantCategorizer {
        FMMerchantCategorizer(
            foundationModelsState: foundationModelsTierState,
            nlCategorizer: NLMerchantCategorizer(),
            fmCategorizer: foundationModelsTierState.isAvailable
                ? FoundationModelsMerchantCategorizer()
                : nil
        )
    }

    /// Re-probe Apple Foundation Models availability (e.g. after the user enables
    /// Apple Intelligence in System Settings) and rebuild the insight service so a
    /// now-available FM tier starts generating insights (AND-564) — or a
    /// now-unavailable one disengages and the existing engine resumes unchanged.
    ///
    /// Wired to `NSApplication.didBecomeActiveNotification` (see
    /// `startEnergyStateObservers`) so a transient FM state — the model still
    /// downloading (`.modelNotReady`), or Apple Intelligence only just enabled in
    /// System Settings (`.appleIntelligenceNotEnabled`) — recovers the next time
    /// the app reactivates, instead of being stuck until the user relaunches. The
    /// `previous == current` guard makes the common no-change reactivation a cheap
    /// no-op.
    func refreshFoundationModelsAvailability() {
        let previous = foundationModelsTierState
        foundationModelsTierState = foundationModelsProbe.currentState()
        guard foundationModelsTierState != previous else { return }
        rebuildLocalAIInsightsService()
        invalidateLocalAIActivitySummaries()
        // The FM categorization tier just flipped availability; any cached FM
        // category suggestions were computed against the prior state, so drop them
        // and let the Review Inbox recompute on its next appearance.
        _foundationModelsCategorySuggestions = [:]
        // Income subtype suggestions may have been FM-refined against the prior
        // state too; drop them so they recompute (the heuristic floor still
        // backfills on the next refresh regardless of FM availability).
        _incomeCategorySuggestions = [:]
    }

    /// Display-only Foundation Models category *suggestions*, keyed by transaction
    /// id (AND-565). Populated by `refreshFoundationModelsCategorySuggestions()`
    /// only on an `.available` FM device; empty everywhere else, so the no-FM path
    /// is unchanged. These are SUGGESTIONS, never persisted categories: they never
    /// touch `transactionReviewMetadata.userCategory`, never feed budget/export
    /// totals, and never bypass the review/override flow — exactly the contract the
    /// NL "Suggested" badge already follows.
    private var _foundationModelsCategorySuggestions: [String: MerchantCategorySuggestion] = [:]

    /// The on-device Foundation Models category suggestion for a transaction, if
    /// one has been computed this session. `nil` on every non-`.available` device
    /// (the dictionary stays empty there), so callers degrade to the existing NL
    /// path with no change.
    func foundationModelsCategorySuggestion(for transactionID: String) -> MerchantCategorySuggestion? {
        _foundationModelsCategorySuggestions[transactionID]
    }

    /// Drive the live Foundation Models categorization tier (AND-565): for the
    /// current Review Inbox items that still need a category, ask the wired
    /// categorizer for an on-device suggestion and cache the `.foundationModels`
    /// results for display. A no-op unless the FM probe reports `.available`, so
    /// the no-FM device never makes a model call and behaves exactly as before.
    ///
    /// Only the redaction-safe merchant string crosses into the model (the
    /// categorizer enforces this); no identifiers, amounts, or Plaid payloads.
    /// Results are display-only suggestions — they are never auto-applied and never
    /// bypass the review/override flow (`EffectiveCategoryResolver` stays the
    /// source of truth for persisted categories).
    func refreshFoundationModelsCategorySuggestions() async {
        guard foundationModelsTierState.isAvailable else { return }
        let categorizer = merchantCategorizer
        // Evict cache entries whose transactions have left the Review Inbox
        // (categorized/approved/ignored/dropped). The cache is otherwise
        // insert-only, so without this prune it grows with session-cumulative
        // throughput rather than live inbox size (unbounded memory creep).
        // `foundationModelsCategorySuggestion(for:)` only reads ids currently
        // in the inbox, so dropping absent ids removes nothing on display.
        let liveIDs = Set(transactionReviewInboxSnapshot.items.map(\.id))
        _foundationModelsCategorySuggestions = _foundationModelsCategorySuggestions.filter { liveIDs.contains($0.key) }
        // Only items still flagged as needing a category benefit from a
        // suggestion; a row the user already categorized must not be second-
        // guessed. Skip ones already suggested this session to avoid redundant
        // model calls on every inbox reopen.
        let pending = transactionReviewInboxSnapshot.items.filter { item in
            item.reasonCodes.contains(.uncategorized)
                && _foundationModelsCategorySuggestions[item.id] == nil
        }
        guard !pending.isEmpty else { return }

        var produced: [String: MerchantCategorySuggestion] = [:]
        for item in pending {
            // Priority #5: feed the richer, injection-safe context (Plaid hint +
            // recurring flag + inflow/outflow) so the on-device model disambiguates
            // better than from the merchant string alone. Identifier-free.
            let context = CategorySuggestionContext.make(
                for: item.transaction,
                isRecurring: isRecurringTransaction(item.transaction)
            )
            guard let suggestion = await categorizer.suggest(for: item.transaction, context: context),
                  suggestion.tier == .foundationModels else { continue }
            produced[item.id] = suggestion
        }
        guard !produced.isEmpty else { return }
        // Merge rather than replace: concurrent passes (e.g. a refresh landing
        // mid-iteration) must not clobber suggestions another pass already wrote.
        for (id, suggestion) in produced {
            _foundationModelsCategorySuggestions[id] = suggestion
        }
    }

    /// Display-only income-subtype *suggestions*, keyed by transaction id (priority
    /// #5). The income analogue of `_foundationModelsCategorySuggestions`: the
    /// deterministic `IncomeMerchantClassifier` always produces a heuristic floor,
    /// and on an `.available` FM device the on-device income categorizer can refine
    /// it. SUGGESTIONS only — they never persist, never mutate Plaid's raw category,
    /// and never become budget spend (income is not spend).
    private var _incomeCategorySuggestions: [String: IncomeCategorySuggestion] = [:]

    /// The on-device income-subtype suggestion for a transaction, if one has been
    /// computed this session. `nil` for spend transactions and for income the
    /// classifier could not place.
    func incomeCategorySuggestion(for transactionID: String) -> IncomeCategorySuggestion? {
        _incomeCategorySuggestions[transactionID]
    }

    /// Whether the on-device Foundation Models (Apple Intelligence) categorization
    /// tier is currently available. Read-only view onto the private probe state so
    /// SwiftUI surfaces can key suggestion-refresh tasks on FM availability without
    /// reaching into AppState internals.
    var isFoundationModelsCategorizationAvailable: Bool {
        foundationModelsTierState.isAvailable
    }

    /// Whether a transaction belongs to a detected recurring stream (matched by
    /// normalized merchant), so the income/expense suggestion context can carry the
    /// recurring signal. Pure read over the cached recurring streams.
    private func isRecurringTransaction(_ transaction: TransactionDTO) -> Bool {
        let key = (transaction.merchantName ?? transaction.name)
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .lowercased()
        guard !key.isEmpty else { return false }
        return recurringTransactions.contains { recurring in
            recurring.merchantName
                .trimmingCharacters(in: .whitespacesAndNewlines)
                .lowercased() == key
        }
    }

    /// Drive the income-subtype suggestion tier (priority #5) for a *specific* set of
    /// income transactions, computing a subtype suggestion (FM-refined when Apple
    /// Intelligence is available, else the deterministic heuristic floor) and caching
    /// it for display. Always runs the heuristic — it is on-device, deterministic,
    /// and needs no model — so income subtypes appear even without Apple
    /// Intelligence. Results are display-only and never bypass the review flow.
    ///
    /// Scoped on purpose: an on-device FM generation can take seconds, so the
    /// inspector (which shows ONE row) must not FM-categorize the entire income
    /// history on every detail render. Callers pass the id(s) actually on screen via
    /// `refreshIncomeCategorySuggestion(for:)`; the cache prune still covers the full
    /// live set so it never leaks past departed transactions.
    ///
    /// Only the redaction-safe `CategorySuggestionContext` crosses into any model;
    /// no identifiers, amounts, or Plaid payloads.
    func refreshIncomeCategorySuggestions(ids: Set<String>) async {
        // Prune entries for transactions no longer present (cache stays bounded by
        // live transactions, not session-cumulative throughput).
        let liveIncomeIDs = Set(transactions.filter(\.isIncome).map(\.id))
        _incomeCategorySuggestions = _incomeCategorySuggestions.filter { liveIncomeIDs.contains($0.key) }

        // Only the requested, still-live income rows that aren't already cached —
        // bounds the (potentially slow) model work to what the caller needs now.
        let pending = transactions.filter {
            $0.isIncome
                && ids.contains($0.id)
                && _incomeCategorySuggestions[$0.id] == nil
        }
        guard !pending.isEmpty else { return }

        let categorizer = merchantCategorizer
        let incomeSeam: (any FMIncomeCategorizing)? = foundationModelsTierState.isAvailable
            ? FoundationModelsIncomeCategorizer()
            : nil

        var produced: [String: IncomeCategorySuggestion] = [:]
        for transaction in pending {
            let context = CategorySuggestionContext.make(
                for: transaction,
                isRecurring: isRecurringTransaction(transaction)
            )
            guard let suggestion = await categorizer.suggestIncome(
                for: transaction,
                context: context,
                incomeCategorizer: incomeSeam
            ) else { continue }
            produced[transaction.id] = suggestion
        }
        guard !produced.isEmpty else { return }
        // Merge rather than replace: a concurrent scoped pass for another row must
        // not clobber a suggestion this pass did not compute.
        for (id, suggestion) in produced {
            _incomeCategorySuggestions[id] = suggestion
        }
    }

    /// Compute the income-subtype suggestion for a single transaction (the inspector
    /// shows one row). A thin scope over `refreshIncomeCategorySuggestions(ids:)` so a
    /// detail render never kicks off whole-history FM work. No-op for a non-income id
    /// (filtered inside) or one already cached.
    func refreshIncomeCategorySuggestion(for transactionID: String) async {
        guard !transactionID.isEmpty else { return }
        await refreshIncomeCategorySuggestions(ids: [transactionID])
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

    /// The on-device summary for a specific window, or the closest available
    /// fallback (the requested window, then `.lastMonth`, then the first summary).
    /// All three windows are computed every refresh, so selecting one never starts
    /// a new model run.
    func summary(for window: LocalAIInsightWindow) -> LocalAIActivitySummary? {
        let summaries = localAIActivitySummaries
        return summaries.first { $0.window == window }
            ?? summaries.first { $0.window == .lastMonth }
            ?? summaries.first
    }

    /// The summary for the window the Insights surface should actually present —
    /// driven off `localAIWindowSelection.resolvedSelection`, NOT the raw
    /// `selectedInsightWindow`. When the requested window is no longer usable (e.g.
    /// year-over-year after a refresh with no prior-year rows), the selector resolves
    /// to a usable fallback; using the raw window here would show a disabled /
    /// misleading receipt for a window the chip itself has fallen back from. Sourcing
    /// both the summary and the selected chip from `resolvedSelection` keeps them in
    /// lockstep.
    var selectedInsightSummary: LocalAIActivitySummary? {
        summary(for: localAIWindowSelection.resolvedSelection)
    }

    /// The selector presentation (ordered options + which are usable + the resolved
    /// selection) for the chosen window. Pure logic lives in Core; this binds it to
    /// the live summaries and persisted selection.
    var localAIWindowSelection: LocalAIInsightWindowSelection {
        LocalAIInsightWindowSelection.make(
            summaries: localAIActivitySummaries,
            requestedSelection: selectedInsightWindow
        )
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
            accounts = AccountReconciliation.accountsAfterRefresh(
                refreshedAccounts: refreshedAccounts,
                currentAccounts: accounts,
                itemStatusesAvailable: itemStatusesAvailable,
                itemStatuses: itemStatuses
            )
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
            accounts = AccountReconciliation.accountsAfterRefresh(
                refreshedAccounts: refreshedAccounts,
                currentAccounts: accounts,
                itemStatusesAvailable: itemStatusesAvailable,
                itemStatuses: itemStatuses
            )
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
            // A serverless --demo launch needs no server to stay populated, but
            // the demo readiness card advertises "Connect Bank". Probe for a real
            // server FIRST and bail without mutating anything when none is
            // reachable: the destructive demo→real teardown below (clearing
            // accounts/transactions/etc.) must never run in a serverless demo, or
            // a single "Connect Bank" tap would wipe the demo dashboard and paint
            // a server-required banner the demo does not need. Mirrors the
            // already-correct demo guards in `reconnectItem` and
            // `refreshLiabilities`. Only once a server is actually present do we
            // fall through into the real add-account flow (teardown + Plaid Link).
            // The probe's failure path (checkServerConnection's catch) clears
            // itemStatuses + all server metadata. In a serverless demo (incl. the
            // recovery-scenario screenshot mode) that would erase the demo
            // sync-health rows even though accounts/transactions survive — so
            // snapshot the demo status fields and restore them if no real server
            // turns up (AQ-1, codex review).
            let demoItemStatuses = itemStatuses
            let demoServerConnected = serverConnected
            let demoServerEnvironment = serverEnvironment
            let demoServerVersion = serverVersion
            let demoServerItemCount = serverItemCount
            let demoServerCredentialsConfigured = serverCredentialsConfigured
            let demoServerStoragePath = serverStoragePath
            let demoServerSyncReady = serverSyncReady
            let demoServerSyncedItemCount = serverSyncedItemCount
            let demoBillingSubscription = billingSubscription
            await checkServerConnection()
            guard serverConnected else {
                // No real server: restore the demo status fields the probe cleared
                // and bail without tearing down demo data or painting a banner.
                itemStatuses = demoItemStatuses
                serverConnected = demoServerConnected
                serverEnvironment = demoServerEnvironment
                serverVersion = demoServerVersion
                serverItemCount = demoServerItemCount
                serverCredentialsConfigured = demoServerCredentialsConfigured
                serverStoragePath = demoServerStoragePath
                serverSyncReady = demoServerSyncReady
                serverSyncedItemCount = demoServerSyncedItemCount
                billingSubscription = demoBillingSubscription
                error = nil
                return
            }

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
            // Demo fixtures may have been published to the shared App Group before
            // the demo guards landed, or by an older build; wipe both the glance and
            // finance snapshots (and the Spotlight account index) on demo exit so a
            // prior demo's unlabeled figures never linger on the widget / Control
            // Center / Siri / Spotlight surfaces (bug-hunt R2). `clearGlanceSnapshot`
            // clears both stores + the index and reloads the widget timeline.
            await clearGlanceSnapshot()
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
            // Never paint a server-required banner over a demo dashboard
            // (existing `error = isDemoMode ? nil : …` convention). The demo
            // path already returned above before any teardown, so reaching here
            // in demo mode is not expected — but suppress defensively in case a
            // future caller re-enters this guard while demo is still active.
            error = isDemoMode ? nil : "Start the VaultPeek companion server before adding an account."
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
        // Energy-aware gate (AND-568): a `force` refresh is user-initiated and
        // always pulls Plaid data; an automatic tick additionally backs off the
        // network-and-CPU-heavy Plaid fetch while the device is in Low Power Mode
        // or under serious/critical thermal pressure. The connectivity re-probe
        // above and the category-budget recompute below still run every tick, so
        // only the Plaid round-trip is deferred — never the cheap local work.
        let plaidFetchAllowed = EnergyAwareRefreshPolicy.shouldRunAutomaticRefresh(
            conditions: currentEnergyConditions,
            automaticRefreshIsDue: shouldAutoRefreshNow,
            isManual: force
        )
        // Setup state (credentials missing) cannot refresh anything from
        // Plaid; the status surfaces guide the user instead of surfacing a
        // 503 banner on every cycle.
        if serverConnected, serverCredentialsConfigured != false, plaidFetchAllowed {
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
                // The account cache write is load-bearing: if the post-delete save
                // is lost, the next launch reloads stale JSON and the removed
                // account reappears (GH #508). Retry once before giving up.
                try await persistAccountCacheWithRetry(
                    cacheAccounts,
                    to: cacheDirectory,
                    context: cacheContext
                )
                try await saveTransactionsToCacheWithPerformance(
                    cacheTransactions,
                    to: cacheDirectory,
                    context: cacheContext
                )
                persistReviewStorage()
            } catch {
                // Server delete already succeeded and in-memory state is correct, so
                // the account is gone for this session. The on-disk cache is stale,
                // but boot-time reconciliation against the server item list drops it
                // on the next launch, so it cannot resurrect (GH #508).
                self.error = "Removed the account, but couldn't update the local cache: "
                    + "\(error.localizedDescription)"
            }
            // Refresh (or clear, when the last institution is gone) the widget
            // snapshot so it never shows balances for just-removed accounts.
            // `writeGlanceSnapshot` also refreshes/clears the App Intents snapshot.
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
        // Wipe the disposable read-model cache alongside the JSON/SQLite caches
        // so a post-reset cold start never paints pre-reset balances (AND-566).
        await clearReadModelCache()
        // Wipe the disposable per-transaction cache too so the paged list never
        // surfaces pre-reset transactions (AND-567).
        await clearTransactionCache()
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
                    // `refreshDashboard(force: false)` additionally defers the
                    // Plaid round-trip while the device is energy-constrained
                    // (AND-568).
                    await refreshDashboard(force: false)
                }
                if appLockPreferences.shouldEvaluateFinancialNotifications(isAppLocked: isAppLocked) {
                    await evaluateNotifications()
                }
                // Energy-aware cadence (AND-568): lengthen the sleep while the
                // device is in Low Power Mode or under serious/critical thermal
                // pressure so a throttled / battery-saving machine wakes the app
                // less often. A power/thermal change posts a notification that
                // restarts this loop, so the longer sleep is re-evaluated as soon
                // as conditions return to normal — it never strands the app on a
                // stale long delay.
                let delay = EnergyAwareRefreshPolicy.nextTickDelay(
                    baseInterval: refreshInterval,
                    conditions: currentEnergyConditions
                )
                try? await Task.sleep(for: .seconds(delay))
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

    // MARK: - Energy-aware refresh (AND-568)

    /// Live device energy/thermal snapshot read from `ProcessInfo`, mapped onto
    /// the framework-light `EnergyAwareRefreshPolicy` inputs. Read at the top of
    /// each automatic refresh decision and when sizing the next loop sleep, so
    /// the policy always sees the current Low Power Mode / thermal state.
    var currentEnergyConditions: EnergyAwareRefreshPolicy.EnergyConditions {
        let info = ProcessInfo.processInfo
        return EnergyAwareRefreshPolicy.EnergyConditions(
            lowPowerMode: info.isLowPowerModeEnabled,
            thermalState: Self.energyThermalState(from: info.thermalState)
        )
    }

    /// Maps the live `ProcessInfo.ThermalState` onto the pure Core mirror enum so
    /// the decision logic stays testable without a real device.
    nonisolated static func energyThermalState(
        from state: ProcessInfo.ThermalState
    ) -> EnergyAwareRefreshPolicy.EnergyThermalState {
        switch state {
        case .nominal: .nominal
        case .fair: .fair
        case .serious: .serious
        case .critical: .critical
        @unknown default: .nominal
        }
    }

    /// Subscribes to the OS Low Power Mode and thermal-state change
    /// notifications. When either changes we restart the background loop so the
    /// next-tick delay and the automatic-refresh gate are re-evaluated against
    /// the new conditions immediately — e.g. when the user plugs in and Low Power
    /// Mode turns off, the loop drops back from the constrained cadence to the
    /// normal interval without waiting out a stale long sleep. Idempotent: a
    /// second call removes the prior observers first.
    func startEnergyStateObservers() {
        stopEnergyStateObservers()
        let center = NotificationCenter.default
        let powerObserver = center.addObserver(
            forName: .NSProcessInfoPowerStateDidChange,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            MainActor.assumeIsolated {
                self?.handleEnergyStateChange()
            }
        }
        let thermalObserver = center.addObserver(
            forName: ProcessInfo.thermalStateDidChangeNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            MainActor.assumeIsolated {
                self?.handleEnergyStateChange()
            }
        }
        energyStateObservers = [powerObserver, thermalObserver]
        // Re-probe Apple Foundation Models availability on app reactivation so a
        // transient FM state recovers within the session (AND-563/564). The probe
        // is cheap and the refresh self-guards against no-change reactivations.
        appActivationObserver = center.addObserver(
            forName: NSApplication.didBecomeActiveNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            MainActor.assumeIsolated {
                self?.refreshFoundationModelsAvailability()
            }
        }
    }

    private func stopEnergyStateObservers() {
        let center = NotificationCenter.default
        for observer in energyStateObservers {
            center.removeObserver(observer)
        }
        energyStateObservers = []
        if let appActivationObserver {
            center.removeObserver(appActivationObserver)
            self.appActivationObserver = nil
        }
    }

    /// Re-evaluates the background cadence after a power/thermal transition by
    /// restarting the loop (only when one is already running, so we never spin a
    /// loop up before boot). The restart re-reads `currentEnergyConditions` for
    /// both the gate and the sleep length.
    ///
    /// Restarting the loop also tears down the current sleep and immediately runs
    /// a refresh tick, which issues a server connectivity probe (HTTP). The energy
    /// cadence only changes when the *constrained* verdict crosses its boundary
    /// (Low Power Mode on/off, or thermal entering/leaving `.serious`/`.critical`),
    /// so a transition that stays on the same side — e.g. `.nominal` → `.fair`, or
    /// `.serious` → `.critical`, both already constrained — would have produced the
    /// same next-tick delay. Restart (and probe) ONLY when the verdict actually
    /// flips; otherwise this is a cheap no-op (AND-568 perf).
    private func handleEnergyStateChange() {
        guard refreshTask != nil else { return }
        let constrained = currentEnergyConditions.isConstrained
        guard constrained != lastEnergyConstrainedVerdict else { return }
        lastEnergyConstrainedVerdict = constrained
        startBackgroundRefresh()
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
        // Fast path: paint frame 1 from the disposable SwiftData read-model cache
        // before the (slower) JSON warm path and well before the HTTP refresh
        // (AND-566). Best-effort; on any failure or miss it leaves `accounts` /
        // `transactions` empty so the JSON path below runs exactly as before.
        await hydrateFromReadModelCache()

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
                guard let entry = ServerConfigLine.parse(rawLine) else { continue }
                environment[entry.key] = ServerConfigLine.unquote(entry.value)
            }
        }

        let rawEnvironment = trimmedNonEmpty(environment["PLAID_ENV"]) ?? PlaidEnvironment.production.rawValue
        // Unquoted a second time on purpose: file-sourced values were unquoted in
        // the loop above, but a PLAID_ENV inherited from the process environment
        // bypasses it, so this normalizes a quoted value from either source.
        guard let plaidEnvironment = PlaidEnvironment(rawValue: ServerConfigLine.unquote(rawEnvironment)) else {
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

    private func trimmedNonEmpty(_ value: String?) -> String? {
        guard let value else { return nil }
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
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
            let cachedAccounts = try await loadAccountsFromCacheWithPerformance(
                from: activeStorageDirectoryURL,
                context: transactionCacheContext
            )
            accounts = reconcileCachedAccountsAgainstServer(cachedAccounts)
            // If a prior removal's cache write failed (GH #508), the stale account
            // was just dropped from `accounts` above. Heal the on-disk cache so it
            // no longer lists a deleted account on the next launch.
            if accounts.count != cachedAccounts.count {
                let healedAccounts = accounts
                let cacheDirectory = activeStorageDirectoryURL
                let cacheContext = transactionCacheContext
                try? await saveAccountsToCacheWithPerformance(
                    healedAccounts,
                    to: cacheDirectory,
                    context: cacheContext
                )
            }
        } catch {
            self.error = "Account cache failed to load: \(error.localizedDescription)"
        }
    }

    /// Drops cached accounts whose item the server no longer reports, using the
    /// authoritative item list already fetched by `checkServerConnection` before
    /// boot loads the cache. Guarded so a transient empty item-status list (e.g. a
    /// failed `/api/items` fetch) never blanks the dashboard — only a known,
    /// non-empty server item list prunes the cache (GH #508).
    private func reconcileCachedAccountsAgainstServer(_ cachedAccounts: [AccountDTO]) -> [AccountDTO] {
        guard !itemStatuses.isEmpty else { return cachedAccounts }
        return AccountReconciliation.cachedAccountsReconciledAgainstServerItems(
            cachedAccounts: cachedAccounts,
            serverItemIds: itemStatuses.map(\.id)
        )
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

    /// Internal accessors so the read-model cache wiring (AND-566, in a separate
    /// file) can reuse the same context resolution the JSON cache uses without
    /// duplicating it. The live context is the server-derived one; the preconnect
    /// hint is the file/env-derived fallback for a cold start before the first
    /// status check.
    var liveTransactionCacheContext: TransactionCacheContext? {
        transactionCacheContext
    }

    func preconnectReadModelCacheContextHint() -> TransactionCacheContext? {
        currentPreconnectCacheContextHint()
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

    /// Persists the account cache, retrying once on failure. Used after a
    /// server-side account removal where a lost write would otherwise let the
    /// deleted account resurrect from stale JSON on the next launch (GH #508).
    private func persistAccountCacheWithRetry(
        _ accounts: [AccountDTO],
        to directory: URL,
        context: TransactionCacheContext?
    ) async throws {
        do {
            try await saveAccountsToCacheWithPerformance(accounts, to: directory, context: context)
        } catch {
            try await saveAccountsToCacheWithPerformance(accounts, to: directory, context: context)
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
                guard let entry = ServerConfigLine.parse(line) else { continue }
                values[entry.key] = ServerConfigLine.unquote(entry.value)
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
        // outage), `AccountReconciliation.accountsPreservingDegradedItems` keeps
        // that item's cached accounts in `accounts`; stamping them with today's
        // date would make Time
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
        // Demo-mode fixtures must never reach the shared App Group container: a
        // glance/finance snapshot there is shown UNLABELED on Control Center / Siri
        // / Spotlight / the widget and would PERSIST after demo exit. Skip the
        // publish entirely while in demo. The tradeoff: demo mode loses widget /
        // Control Center coverage — acceptable for a screenshot/preview mode, and it
        // removes the leak. The demo-exit teardown clears any lingering snapshot
        // (see `addAccount`'s `isDemoMode = false` path and `resetLocalData`).
        guard !isDemoMode else { return }
        // With no accounts (e.g. the user just disconnected their last
        // institution), clear the app-group snapshot instead of leaving the
        // previous balances on disk — otherwise the widget would keep showing
        // removed-account net worth until a later reset or successful write.
        guard !accounts.isEmpty else {
            // App Intents read a parallel App Group snapshot. Clear it on the same
            // empty path so Spotlight/Siri/Shortcuts stop reporting removed-account
            // figures (AND-512).
            try? AppGroupSnapshotStore.clear()
            // No accounts left to surface in search — drop the display-only
            // Spotlight account index too so removed-account names don't linger
            // (AND-513). `writeFinanceSnapshot` is skipped on this empty path, so
            // the index clear must happen here explicitly.
            AccountSpotlightIndexer.clear()
            // Drop the disposable read-model cache on the same empty path so a
            // cold start after the last institution was removed does not paint
            // stale balances from the cache (AND-566).
            Task { await clearReadModelCache() }
            // Drop the disposable per-transaction cache on the same empty path so
            // the paged list never surfaces transactions for a removed institution
            // (AND-567).
            Task { await clearTransactionCache() }
            Task {
                await clearGlanceSnapshot()
                await MainActor.run {
                    WidgetCenter.shared.reloadTimelines(ofKind: "PlaidBarGlanceWidget")
                }
            }
            return
        }
        // Keep the App Intents snapshot fresh on the same path that already
        // recomputes summaries for the widget (AND-512).
        writeFinanceSnapshot(updatedAt: updatedAt)
        // Trail the authoritative in-memory data into the disposable read-model
        // cache so the next cold start renders instantly (AND-566). This is the
        // single post-refresh/mutation seam, so the cache always reflects the
        // latest accounts/transactions. Best-effort, detached, never blocks.
        persistReadModelCache()
        // Mirror the live transactions into the disposable per-transaction cache so
        // the virtualized large-history list can page on the next open (AND-567).
        // Same seam, same best-effort/detached contract; fallback-safe.
        persistTransactionCache()
        glanceSnapshotWriteGeneration += 1
        let generation = glanceSnapshotWriteGeneration
        // When Privacy Mask / App Lock is active, build a value-free snapshot so
        // the on-disk glance-snapshot.json carries no balances, today's change, or
        // sparkline for a widget / Control Center surface to leak (AND-517). The
        // widget view already dots figures at read time via the FinanceSnapshot
        // mask flag; this is defense in depth at the file level.
        let snapshot = GlanceSnapshot.make(
            netWorth: netBalance,
            balanceHistory: balanceHistory,
            updatedAt: updatedAt,
            isDemo: isDemoMode,
            isMasked: shouldMaskFinancialValues
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

    /// Writes the display-safe ``FinanceSnapshot`` consumed by the Finance App
    /// Intents (Spotlight / Siri / Shortcuts) into the shared App Group — the
    /// "Tahoe spine" writer half (AND-512). Runs on the same path that already
    /// recomputes summaries for the glance widget so the intents stay fresh.
    ///
    /// Reuses the existing core inputs — `accounts`, `recurringTransactions`, and
    /// the cashflow from ``WealthSummaryPresentation`` — and lets
    /// ``FinanceSnapshotBuilder`` do the math, so the figures match the popover
    /// with no duplicated calculation here. Values only; never tokens or ids.
    /// When App Lock / Privacy Mask is active the snapshot is written with
    /// `isMasked == true` so the intents withhold the figures past the lock.
    private func writeFinanceSnapshot(updatedAt: Date = Date()) {
        // Defense in depth alongside `writeGlanceSnapshot`'s guard: never publish
        // demo fixtures to the shared App Group `FinanceSnapshot` that backs the
        // unlabeled Control Center value controls / Siri / Spotlight / Shortcuts.
        guard !isDemoMode else { return }
        let cashflow = WealthSummaryPresentation.evaluate(
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
        ).cashflow

        let snapshot = FinanceSnapshotBuilder.make(
            accounts: accounts,
            recurringTransactions: recurringTransactions,
            cashflow: cashflow,
            isMasked: shouldMaskFinancialValues,
            transactions: transactions,
            reviewMetadata: transactionReviewMetadata,
            transactionRules: transactionRules,
            creditUtilizationThreshold: creditUtilizationThreshold,
            generatedAt: updatedAt
        )
        // File IO off the main actor; the snapshot is `Sendable` and the store is
        // a stateless enum, so a detached task is safe under strict concurrency.
        Task.detached(priority: .utility) {
            do {
                try AppGroupSnapshotStore.save(snapshot)
            } catch {
                AppState.glanceSnapshotLogger.error(
                    "Failed to write finance snapshot: \(String(describing: error), privacy: .public)"
                )
            }
        }
        // Keep the display-only Spotlight account index in lockstep with the
        // finance snapshot: this is the shared seam for account load/refresh
        // (via `writeGlanceSnapshot`), demo data, and the Privacy Mask / App Lock
        // transitions (`togglePrivacyMask` / `lockApp`). `refresh` clears the
        // index when masked, so masking removes account names from system search
        // immediately; the empty-accounts clear lives in `writeGlanceSnapshot` /
        // `clearGlanceSnapshot` (AND-513).
        AccountSpotlightIndexer.refresh(accounts: accounts, isMasked: shouldMaskFinancialValues)
    }

    private func clearGlanceSnapshot() async {
        glanceSnapshotWriteGeneration += 1
        await glanceSnapshotWriteDebouncer.cancel()
        try? GlanceSnapshotStore.clear()
        // The App Intents snapshot lives in a sibling file in the same container;
        // wipe it on every glance clear (reset / last-institution removal) so it
        // can't keep answering with pre-clear figures (AND-512).
        try? AppGroupSnapshotStore.clear()
        // Drop the display-only Spotlight account index on the same reset /
        // data-wipe path so removed-account names don't linger in search (AND-513).
        AccountSpotlightIndexer.clear()
        // Tell WidgetKit to drop the already-issued timeline entry so the widget
        // surface stops showing pre-clear balances immediately. This covers
        // every clear path — the explicit reset/data-wipe (`resetLocalData`) and
        // removing the last institution — not just the empty-accounts write
        // branch, which previously reloaded on its own (AND-385 Codex review).
        WidgetCenter.shared.reloadTimelines(ofKind: "PlaidBarGlanceWidget")
    }

    private func clearPublishedSystemSnapshotsForDemoEntry() {
        glanceSnapshotWriteGeneration += 1
        let debouncer = glanceSnapshotWriteDebouncer
        Task { await debouncer.cancel() }
        try? GlanceSnapshotStore.clear()
        try? AppGroupSnapshotStore.clear()
        AccountSpotlightIndexer.clear()
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
        let wasDemoMode = isDemoMode
        isDemoMode = true
        if !wasDemoMode {
            clearPublishedSystemSnapshotsForDemoEntry()
        }
        // Demo fixtures load synchronously: there is no boot handshake to wait for.
        isBooting = false
        isDemoStatusRecoveryScenario = CommandLine.arguments.contains("--screenshot-status-recovery")

        // Fixture content lives in PlaidBarCore so its continuity guarantees
        // (no heatmap dead zone, year-round income, active savings account)
        // stay testable. See DemoFixtures and DemoFixturesTests.
        accounts = DemoFixtures.accounts
        liabilities = DemoFixtures.liabilities()
        transactions = DemoFixtures.transactions()
        // Seed review metadata, categorization rules, and category budgets so
        // --demo actually surfaces the Review Inbox + budget/category state
        // (AND-543) instead of empty placeholders. Held in-memory only: these
        // assignments invalidate the inbox/budget caches via `didSet` but never
        // persist, so a demo session never overwrites the user's real saved data.
        transactionReviewMetadata = DemoFixtures.demoReviewMetadata()
        transactionRules = DemoFixtures.demoTransactionRules()
        categoryBudgets = Dictionary(
            DemoFixtures.demoBudgets().map { ($0.category, $0.monthlyLimit) },
            uniquingKeysWith: { first, _ in first }
        )
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

    /// Clear the user's category override on a transaction, restoring the
    /// auditable Plaid (or uncategorized) fallback as the effective category
    /// (priority #5). This nils `userCategory` — Plaid's raw `transaction.category`
    /// is never mutated, so the `EffectiveCategoryResolver` precedence chain
    /// (override → rule → confident Plaid → uncategorized) transparently falls back
    /// to Plaid's own answer.
    ///
    /// It also REOPENS the row to needs-review (clears `status`/`reviewedAt` back to
    /// `.needsReview`): the row was likely marked `.reviewed` when the category was
    /// first set, and `TransactionReviewInbox.evaluate` drops a `.reviewed` row, so
    /// merely nilling the category would make the now-uncategorized transaction
    /// vanish from the review queue instead of returning for re-confirmation. The
    /// reason codes are cleared so `evaluate` re-derives them from the restored
    /// baseline. Routed through the same undoable `updateReviewMetadata` path as
    /// every other override, so the whole restore (override + reopen) is one
    /// ⌘Z-reversible step and reflected everywhere.
    func clearReviewCategory(_ id: String) {
        updateReviewMetadata(id: id) { metadata, _ in
            metadata.userCategory = nil
            metadata.status = .needsReview
            metadata.reviewedAt = nil
            metadata.reviewReasonCodes = []
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

    /// Attach (or clear) a free-text note on a transaction from the Transaction
    /// Workspace inspector (AND-582). Routes through the SAME undoable
    /// `updateReviewMetadata` path as every other override, so the note persists on
    /// the existing review-metadata storage and is covered by ⌘Z. A note is a
    /// display-only annotation — it does NOT mark the row reviewed and never feeds
    /// budget/category/export totals. An empty/whitespace note clears it.
    func updateReviewNote(_ id: String, note: String) {
        let trimmed = note.trimmingCharacters(in: .whitespacesAndNewlines)
        updateReviewMetadata(id: id) { metadata, _ in
            metadata.userNote = trimmed.isEmpty ? nil : trimmed
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
        // Re-categorization replaces, not stacks: drop any existing rule that
        // matches the SAME merchant so the user's newer choice wins. Without this
        // the resolver would keep applying an older same-merchant rule (it resolves
        // by most-recent `createdAt`, but a stale duplicate is still wasted state
        // and surfaces as a phantom second rule).
        transactionRules.removeAll {
            $0.matchMerchantContains?.compare(matcher, options: .caseInsensitive) == .orderedSame
        }
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

    /// Marks a batch of inbox rows reviewed in a single, undoable step (AND-528).
    ///
    /// The blast radius — exactly which transaction ids resolve — is decided by the
    /// pure `ReviewBulkActionPlan` (computed in the view and surfaced to the user
    /// before this is called), so this method just applies the already-vetted ids.
    /// Each id flows through the SAME per-item approve logic as the single-row
    /// Approve button (`approveReviewItemWithoutUndo`) so the two paths can never
    /// diverge in what "reviewed" means. The whole batch shares one undo snapshot
    /// (a single ⌘Z restores the entire bulk action) and one persistence write.
    @discardableResult
    func bulkMarkReviewed(ids: [String]) -> Int {
        // Resolve against current transactions so a stale id (a row already gone
        // from the snapshot) is skipped rather than seeding orphan metadata.
        let resolvableIDs = ids.filter { id in transactions.contains(where: { $0.id == id }) }
        guard !resolvableIDs.isEmpty else { return 0 }
        pushReviewUndoState()
        for id in resolvableIDs {
            approveReviewItemWithoutUndo(id)
        }
        persistReviewStorage()
        return resolvableIDs.count
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
        // Inside a batch, the combined snapshot was already captured up front; the
        // per-row mutators must not each push their own or one ⌘Z would only revert
        // the last row of a bulk action.
        guard !isBatchingReviewUndo else { return }
        reviewUndoStack.append((transactionReviewMetadata, transactionRules))
        if reviewUndoStack.count > 20 {
            reviewUndoStack.removeFirst(reviewUndoStack.count - 20)
        }
    }

    /// Runs `body` as a single undoable review batch: captures one combined undo
    /// snapshot up front, suppresses the per-row snapshots the inner mutators would
    /// otherwise push, and persists once. A single ⌘Z then reverts the whole batch.
    ///
    /// Reuses the exact per-row review paths (`updateReviewCategory`,
    /// `markReviewItemTransfer`, `createRule`, …) so bulk and single-row actions can
    /// never diverge in meaning — only their undo granularity differs. Re-entrancy is
    /// a no-op for the inner call: the outermost batch owns the one snapshot.
    func withBatchedReviewUndo(_ body: () -> Void) {
        guard !isBatchingReviewUndo else {
            body()
            return
        }
        pushReviewUndoState()
        isBatchingReviewUndo = true
        defer { isBatchingReviewUndo = false }
        body()
    }

    private func persistReviewStorage() {
        // Demo mode seeds synthetic review metadata and rules into the real
        // AppState (see `loadDemoData`). Acting on a demo inbox item must never
        // write those fixtures to disk: `activeStorageDirectoryURL` is the
        // sandbox-scoped real cache, and a later real connection on the same
        // storage path would reload the synthetic `tx*`/Starbucks/Venmo records.
        // The decision is a pure, tested predicate in PlaidBarCore.
        guard ReviewStoragePersistencePolicy.shouldPersist(isDemoMode: isDemoMode) else { return }
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
