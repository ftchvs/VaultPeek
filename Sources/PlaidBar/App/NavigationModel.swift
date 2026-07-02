import PlaidBarCore
import SwiftUI

/// Per-window navigation model for the window-first shell (AND-594).
///
/// Wraps the pure ``NavigationState`` (PlaidBarCore) with the `@Observable`
/// `@MainActor` machinery SwiftUI needs and the UserDefaults persistence the
/// migrated `@AppStorage` keys used to own. It is **per-window scene state, not a
/// singleton**: the menu-bar popover gets one instance (via `AppState`),
/// and any additional window-first `Window` scene constructs its own — so two
/// windows hold independent selection. The state-transition logic stays in the
/// pure value type; this is a thin, testable shell over it.
///
/// Persistence preserves the *exact* prior keys
/// (`dashboard.accountFilter`, `dashboard.selectedAccountId`,
/// `dashboard.heatmapMode`) and raw values, so a user who upgrades keeps their
/// last filter / selection / heatmap metric. Reading/writing through these keys
/// (rather than scattered view-level `@AppStorage`) is the façade move: one
/// routable state, same on-disk footprint.
@Observable
@MainActor
final class NavigationModel {
    /// UserDefaults keys — identical to the retired view-level `@AppStorage`
    /// keys so persisted selections decode exactly as before.
    enum Keys {
        static let dashboardFilter = "dashboard.accountFilter"
        static let selectedAccountID = "dashboard.selectedAccountId"
        static let heatmapMode = "dashboard.heatmapMode"
        /// The last selected destination's `RouteDestination.rawValue`. New in
        /// AND-597: the popover only ever showed Dashboard, so this key did not
        /// exist before; restoring it lets the window-first shell reopen on the
        /// destination the user left off (selection persistence). Absent ⇒
        /// Dashboard, so an upgrading user (and the flag-OFF popover) is unchanged.
        static let destination = "navigation.destination"
        /// The Transaction Workspace filter/search, JSON-encoded (AND-582). New in
        /// Epic 4: the popover never had this surface, so the key is absent for an
        /// upgrading user (and the flag-OFF popover) ⇒ the default empty filter.
        static let transactionFilter = "navigation.transactionFilter"
        /// The Transaction Workspace sort order's raw value (AND-582). Absent ⇒
        /// the default newest-first sort.
        static let transactionSort = "navigation.transactionSort"
        /// The detached-dashboard intent (AND-600), migrated off the retired
        /// `AppState.isDashboardDetached` flag. Kept identical to the key the
        /// Settings toggle and the `DetachedDashboardWindowController`
        /// `frameAutosaveName` neighborhood used — `DetachedDashboardPreferences`
        /// owns it — so an upgrading user's persisted "floating window" preference
        /// decodes exactly as before.
        static let dashboardDetached = DetachedDashboardPreferences.detachedStorageKey
    }

    /// The pure state. Mutations route through the typed accessors below (which
    /// also persist), so direct assignment is avoided outside hydration.
    private(set) var state: NavigationState

    private let defaults: UserDefaults
    /// While hydrating from UserDefaults, suppress write-back so loading a value
    /// does not immediately persist it again.
    private var isHydrating = false
    /// When true, the persisted detached-dashboard intent is ignored at hydration
    /// (resolved to `false`). A headless snapshot render must never spawn the
    /// floating window — it would intercept the renderer's popover open — so this
    /// carries the deterministic override that previously lived in
    /// `AppState.loadSettings` via `DetachedDashboardPreferences.resolvedDetachedIntent`
    /// (AND-600).
    private let isRenderingSnapshot: Bool

    /// Creates a window's navigation model.
    ///
    /// - Parameters:
    ///   - defaults: the store to persist to. Tests inject an isolated suite so
    ///     two models can prove independent selection without sharing global
    ///     defaults; production uses `.standard`.
    ///   - persistRestore: when `true` (default), the last filter / selection /
    ///     heatmap metric (and the detached-dashboard intent) are restored from
    ///     `defaults`. A fresh second window can opt out to start from defaults.
    ///   - isRenderingSnapshot: when `true`, the persisted detached intent is
    ///     ignored (resolved to `false`) so a headless snapshot render never spawns
    ///     the floating window. Defaults to `false`; production resolves it from
    ///     `CommandLineOptions` at the `AppState` construction site.
    init(
        defaults: UserDefaults = .standard,
        persistRestore: Bool = true,
        isRenderingSnapshot: Bool = false
    ) {
        self.defaults = defaults
        self.state = NavigationState()
        self.isRenderingSnapshot = isRenderingSnapshot
        if persistRestore {
            hydrate()
        }
    }

    // MARK: - Façade surface (read identically to the old @AppStorage)

    var destination: RouteDestination { state.destination }

    var dashboardFilter: DashboardAccountFilterKind {
        get { state.dashboardFilter }
        set {
            state.setDashboardFilter(newValue)
            persistDashboardFilter()
            // setDashboardFilter clears the selection on a real change; mirror
            // that to disk so the cleared selection survives a relaunch.
            persistSelectedAccountID()
        }
    }

    var selectedAccountID: String {
        get { state.selectedAccountID }
        set {
            state.selectAccount(id: newValue)
            persistSelectedAccountID()
        }
    }

    var heatmapMode: SpendingHeatmapMode {
        get { state.heatmapMode }
        set {
            state.heatmapMode = newValue
            persistHeatmapMode()
        }
    }

    // MARK: - Surface presentation façade (AND-600)

    /// Whether this window's menu-bar popover is presented. Migrated off the
    /// retired single `AppState.isPopoverPresented` flag; ephemeral per-window
    /// session state, **not** persisted (a relaunch never auto-opens the popover).
    /// Bound by `menuBarExtraAccess(isPresented:)` so it stays the popover's
    /// presentation source of truth, now scoped to the window's model.
    var isPopoverPresented: Bool {
        get { state.isPopoverPresented }
        set { state.setPopoverPresented(newValue) }
    }

    /// Whether this window's dashboard lives in the detached floating window
    /// (AND-384/600). Migrated off the retired single `AppState.isDashboardDetached`
    /// flag. This is the durable intent — set/cleared it persists to
    /// `DetachedDashboardPreferences.detachedStorageKey`, so the floating window
    /// reopens on the next launch exactly as before. The
    /// `DetachedDashboardCoordinator` reads/writes it to bridge to the AppKit panel.
    var isDashboardDetached: Bool {
        get { state.isDashboardDetached }
        set {
            guard state.isDashboardDetached != newValue else { return }
            state.isDashboardDetached = newValue
            persistDashboardDetached()
        }
    }

    /// Detach the dashboard into the floating window: set the intent AND dismiss
    /// the popover in one transition (only one surface up at a time), persisting
    /// the intent. The pure `NavigationState.detachDashboard()` owns the rule; this
    /// mirrors the detach to disk so the floating window reopens next launch.
    func detachDashboard() {
        let wasDetached = state.isDashboardDetached
        state.detachDashboard()
        if state.isDashboardDetached != wasDetached { persistDashboardDetached() }
    }

    /// Re-dock the dashboard back into the menu-bar popover, persisting the cleared
    /// intent so a relaunch lands in the popover.
    func redockDashboard() {
        let wasDetached = state.isDashboardDetached
        state.redockDashboard()
        if state.isDashboardDetached != wasDetached { persistDashboardDetached() }
    }

    // MARK: - Transaction Workspace façade (AND-582)

    var transactionFilter: TransactionWorkspace.Filter {
        get { state.transactionFilter }
        set {
            state.setTransactionFilter(newValue)
            persistTransactionFilter()
            // setTransactionFilter clears the row selection on a real change; this
            // selection is window-only (not persisted), so nothing else to mirror.
        }
    }

    var transactionSort: TransactionWorkspace.Sort {
        get { state.transactionSort }
        set {
            state.setTransactionSort(newValue)
            persistTransactionSort()
        }
    }

    /// The selected transaction row id, or empty when none. Deliberately **not**
    /// persisted: a row selection is ephemeral per-session window state (unlike the
    /// dashboard account selection, which restored a drill-in), so a relaunch lands
    /// on the unselected inspector prompt.
    var selectedTransactionID: String {
        get { state.selectedTransactionID }
        set { state.selectTransaction(id: newValue) }
    }

    func deselectTransaction() {
        state.deselectTransaction()
    }

    // MARK: - Budgets / Alerts selection façade (AND-621)

    /// The selected Budgets category, or `nil` when none. Deliberately **not**
    /// persisted: like the transaction row selection it is ephemeral per-session
    /// per-window UI state (it replaces the in-memory `BudgetsSelectionModel`
    /// singleton, which never persisted), so a relaunch lands on the unselected
    /// inspector prompt.
    var budgetCategorySelection: SpendingCategory? {
        get { state.budgetCategorySelection }
        set { state.selectBudgetCategory(newValue) }
    }

    /// The selected alert id, or empty when none. Deliberately **not** persisted
    /// for the same reason as `budgetCategorySelection` (it replaces the in-memory
    /// `AlertsSelectionModel.selectedAlertID`, which never persisted).
    var alertSelection: String {
        get { state.alertSelection }
        set { state.selectAlert(id: newValue) }
    }

    /// The Review destination's Triage ↔ Table presentation. Deliberately **not**
    /// persisted: like the transaction row / budget category selections it is
    /// ephemeral per-session per-window UI state, so a fresh window opens on
    /// `.triage`. The "Open review table" affordance sets `.table` before
    /// navigating to Review.
    var reviewWorkspaceMode: ReviewWorkspaceMode {
        get { state.reviewWorkspaceMode }
        set { state.setReviewWorkspaceMode(newValue) }
    }

    func deselectBudgetCategory() {
        state.deselectBudgetCategory()
    }

    func deselectAlert() {
        state.deselectAlert()
    }

    /// Alert ids acknowledged this session. Not persisted (session-scoped
    /// per-window state, like the retired `AlertsSelectionModel`).
    var acknowledgedAlertIDs: Set<String> { state.acknowledgedAlertIDs }

    func acknowledgeAlert(_ id: String) {
        state.acknowledgeAlert(id)
    }

    func unacknowledgeAlert(_ id: String) {
        state.unacknowledgeAlert(id)
    }

    func acknowledgeAllAlerts(in inbox: AlertsInbox) {
        state.acknowledgeAllAlerts(in: inbox)
    }

    /// Self-heal: prune acknowledged ids + a stale selection to the live rows.
    func pruneAlerts(toRowsIn rows: [AttentionQueueRow]) {
        state.pruneAlerts(toRowsIn: rows)
    }

    /// Self-heal: drop a selected transaction id no longer in the filtered rows.
    @discardableResult
    func reconcileTransactionSelection(visibleTransactionIDs: [String]) -> Bool {
        state.reconcileTransactionSelection(visibleTransactionIDs: visibleTransactionIDs)
    }

    // MARK: - Goals façade (AND-606)

    /// The selected goal id (a `Goal.id` UUID string), or empty when none.
    /// Deliberately **not** persisted: like the transaction row selection, a goal
    /// selection is ephemeral per-session window state, so a relaunch lands on the
    /// unselected inspector prompt.
    var goalSelection: String {
        get { state.goalSelection }
        set { state.selectGoal(id: newValue) }
    }

    func deselectGoal() {
        state.deselectGoal()
    }

    /// Self-heal: drop a selected goal id that no longer maps to a visible goal
    /// (e.g. it was just deleted).
    @discardableResult
    func reconcileGoalSelection(visibleGoalIDs: [String]) -> Bool {
        state.reconcileGoalSelection(visibleGoalIDs: visibleGoalIDs)
    }

    // MARK: - Navigation

    func go(to destination: RouteDestination) {
        state.go(to: destination)
        persistDestination()
    }

    /// Applies a typed ``Route`` — the single in-window navigation entry point
    /// (the ⌘K palette, the ⌘1–8 keymap, a glance-chip hand-off, and — Epic 8 —
    /// App Intents all funnel here via `AppState.route(to:)`). Sets the
    /// destination and folds in any carried selection, then persists both so a
    /// relaunch restores exactly where the deep-link landed.
    func apply(_ route: Route) {
        state.apply(route)
        // A route may carry an account selection and always carries a
        // destination; persist both so the deep-link landing point survives a
        // relaunch like a manual selection / destination switch did.
        persistDestination()
        persistSelectedAccountID()
        // A `.transactions(filter:)` deep-link (e.g. the Dashboard spend-donut →
        // category-group filter, AND-730) folds its criteria into the workspace
        // filter inside `state.apply`; mirror that to disk so the pre-applied filter
        // survives a relaunch like a manual filter change did.
        persistTransactionFilter()
    }

    func deselectAccount() {
        state.deselectAccount()
        persistSelectedAccountID()
    }

    /// Self-heal: drop a persisted selection that is no longer visible (the
    /// `MainPopover` filter-populate edge). Persists the cleared value.
    @discardableResult
    func reconcileSelection(visibleAccountIDs: [String]) -> Bool {
        let didClear = state.reconcileSelection(visibleAccountIDs: visibleAccountIDs)
        if didClear { persistSelectedAccountID() }
        return didClear
    }

    /// The selected id resolved against the visible accounts (or `nil`).
    func resolvedSelectedID(visibleAccountIDs: [String]) -> String? {
        state.resolvedSelectedID(visibleAccountIDs: visibleAccountIDs)
    }

    // MARK: - Persistence

    private func hydrate() {
        isHydrating = true
        defer { isHydrating = false }

        var restored = NavigationState()
        // Restore the last destination (AND-597). Absent ⇒ the default Dashboard,
        // so an upgrading user — and the flag-OFF popover, which only ever shows
        // Dashboard — is unchanged. A persisted destination that has since been
        // deprecated-in-place (Gate-0, AND-979 — e.g. `.planning`) redirects to
        // its live target, so an upgrading user's old selection still decodes to
        // somewhere real instead of a destination nothing renders.
        if let rawDestination = defaults.string(forKey: Keys.destination),
           let destination = RouteDestination(rawValue: rawDestination) {
            restored.destination = destination.canonicalRedirect ?? destination
        }
        if let raw = defaults.string(forKey: Keys.dashboardFilter),
           let filter = DashboardAccountFilterKind(rawValue: raw) {
            restored.dashboardFilter = filter
        }
        if let id = defaults.string(forKey: Keys.selectedAccountID) {
            restored.selectedAccountID = id
        }
        if let rawMode = defaults.string(forKey: Keys.heatmapMode),
           let mode = SpendingHeatmapMode(rawValue: rawMode) {
            restored.heatmapMode = mode
        }
        // Transaction Workspace filter/sort (AND-582). Absent ⇒ defaults, so the
        // flag-OFF popover (which never reads these) is unchanged. A filter that
        // fails to decode (e.g. a removed category) falls back to the default
        // rather than throwing.
        if let data = defaults.data(forKey: Keys.transactionFilter),
           let filter = try? JSONDecoder().decode(TransactionWorkspace.Filter.self, from: data) {
            restored.transactionFilter = filter
        }
        if let rawSort = defaults.string(forKey: Keys.transactionSort),
           let sort = TransactionWorkspace.Sort(rawValue: rawSort) {
            restored.transactionSort = sort
        }
        // Detached-dashboard intent (AND-384/600). A headless snapshot render
        // ignores the persisted intent so the popover-capture path stays
        // deterministic regardless of host/CI defaults — otherwise a stale
        // `dashboard.detached = true` would spawn the floating window and intercept
        // the renderer's popover open. The stored value is left untouched (no
        // write-back during hydration) so the real user preference survives.
        let storedDetached = defaults.object(forKey: Keys.dashboardDetached) != nil
            ? defaults.bool(forKey: Keys.dashboardDetached)
            : nil
        restored.isDashboardDetached = DetachedDashboardPreferences.resolvedDetachedIntent(
            storedValue: storedDetached,
            isRenderingSnapshot: isRenderingSnapshot
        )
        // `isPopoverPresented` is deliberately not hydrated: a relaunch never
        // auto-opens the popover. It stays at its `NavigationState()` default.
        state = restored
    }

    private func persistDestination() {
        guard !isHydrating else { return }
        defaults.set(state.destination.rawValue, forKey: Keys.destination)
    }

    private func persistDashboardFilter() {
        guard !isHydrating else { return }
        defaults.set(state.dashboardFilter.rawValue, forKey: Keys.dashboardFilter)
    }

    private func persistSelectedAccountID() {
        guard !isHydrating else { return }
        defaults.set(state.selectedAccountID, forKey: Keys.selectedAccountID)
    }

    private func persistHeatmapMode() {
        guard !isHydrating else { return }
        defaults.set(state.heatmapMode.rawValue, forKey: Keys.heatmapMode)
    }

    private func persistTransactionFilter() {
        guard !isHydrating else { return }
        if let data = try? JSONEncoder().encode(state.transactionFilter) {
            defaults.set(data, forKey: Keys.transactionFilter)
        }
    }

    private func persistTransactionSort() {
        guard !isHydrating else { return }
        defaults.set(state.transactionSort.rawValue, forKey: Keys.transactionSort)
    }

    private func persistDashboardDetached() {
        guard !isHydrating else { return }
        defaults.set(state.isDashboardDetached, forKey: Keys.dashboardDetached)
    }
}
