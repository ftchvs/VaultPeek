import PlaidBarCore
import SwiftUI

/// Per-window navigation model for the window-first shell (ADR-001, AND-594).
///
/// Wraps the pure ``NavigationState`` (PlaidBarCore) with the `@Observable`
/// `@MainActor` machinery SwiftUI needs and the UserDefaults persistence the
/// migrated `@AppStorage` keys used to own. It is **per-window scene state, not a
/// singleton** (R-10): the menu-bar popover gets one instance (via `AppState`),
/// and any additional window-first `Window` scene constructs its own — so two
/// windows hold independent selection. The state-transition logic stays in the
/// pure value type; this is a thin, testable shell over it.
///
/// Persistence preserves the *exact* prior keys
/// (`dashboard.accountFilter`, `dashboard.selectedAccountId`,
/// `dashboard.heatmapMode`) and raw values, so a user who upgrades keeps their
/// last filter / selection / heatmap metric. Reading/writing through these keys
/// (rather than scattered view-level `@AppStorage`) is the R-02 façade move: one
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
        /// destination the user left off (IA §2.1 selection persistence). Absent ⇒
        /// Dashboard, so an upgrading user (and the flag-OFF popover) is unchanged.
        static let destination = "navigation.destination"
        /// The Transaction Workspace filter/search, JSON-encoded (AND-582). New in
        /// Epic 4: the popover never had this surface, so the key is absent for an
        /// upgrading user (and the flag-OFF popover) ⇒ the default empty filter.
        static let transactionFilter = "navigation.transactionFilter"
        /// The Transaction Workspace sort order's raw value (AND-582). Absent ⇒
        /// the default newest-first sort.
        static let transactionSort = "navigation.transactionSort"
    }

    /// The pure state. Mutations route through the typed accessors below (which
    /// also persist), so direct assignment is avoided outside hydration.
    private(set) var state: NavigationState

    private let defaults: UserDefaults
    /// While hydrating from UserDefaults, suppress write-back so loading a value
    /// does not immediately persist it again.
    private var isHydrating = false

    /// Creates a window's navigation model.
    ///
    /// - Parameters:
    ///   - defaults: the store to persist to. Tests inject an isolated suite so
    ///     two models can prove independent selection without sharing global
    ///     defaults; production uses `.standard`.
    ///   - persistRestore: when `true` (default), the last filter / selection /
    ///     heatmap metric are restored from `defaults`. A fresh second window can
    ///     opt out to start from defaults.
    init(defaults: UserDefaults = .standard, persistRestore: Bool = true) {
        self.defaults = defaults
        self.state = NavigationState()
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

    // MARK: - Budgets / Alerts selection façade (AND-621, R-10)

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
    /// relaunch restores exactly where the deep-link landed (IA §2.1).
    func apply(_ route: Route) {
        state.apply(route)
        // A route may carry an account selection and always carries a
        // destination; persist both so the deep-link landing point survives a
        // relaunch like a manual selection / destination switch did.
        persistDestination()
        persistSelectedAccountID()
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
        // Dashboard — is unchanged.
        if let rawDestination = defaults.string(forKey: Keys.destination),
           let destination = RouteDestination(rawValue: rawDestination) {
            restored.destination = destination
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
}
