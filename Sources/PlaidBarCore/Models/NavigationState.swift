import Foundation

/// Pure, value-type navigation state for one window of the window-first shell.
/// Holds the current destination plus the per-destination selection
/// and filter state that used to live as scattered view-level
/// `@AppStorage` keys in `MainPopover` (`dashboard.accountFilter`,
/// `dashboard.selectedAccountId`, `dashboard.heatmapMode`).
///
/// This is a **value type**, so two windows that each own their own copy hold
/// *independent* selection — a per-window model, never a
/// singleton. The `@Observable @MainActor` `NavigationModel` wrapper in the app
/// target wraps one of these per window; the pure transitions all live here so
/// they are testable without SwiftUI (CLAUDE.md: shared logic in `PlaidBarCore`).
///
/// All transitions are pure functions returning a new value (or mutating `self`),
/// which makes the "two windows, independent selection" property trivially
/// testable at the Core layer.
public struct NavigationState: Sendable, Equatable, Codable {
    /// The currently selected destination (sidebar selection / window content).
    public var destination: RouteDestination

    // MARK: Dashboard / shared selection state (migrated from MainPopover)

    /// The dashboard's account filter (Cash / Credit / Savings / Debt / Status /
    /// Investments / All). Previously `@AppStorage("dashboard.accountFilter")`.
    public var dashboardFilter: DashboardAccountFilterKind

    /// The selected account id, or empty when none. Previously
    /// `@AppStorage("dashboard.selectedAccountId")`. Empty string (not `nil`)
    /// preserves the popover's existing "" sentinel so the persistence value and
    /// the deselect/resolve rules behave byte-identically.
    public var selectedAccountID: String

    /// The 365-day heatmap's metric (Spend / Net cashflow). Previously
    /// `@AppStorage("dashboard.heatmapMode")` on the heatmap subview.
    public var heatmapMode: SpendingHeatmapMode

    // MARK: Transaction Workspace state (AND-582, Epic 4)

    /// The Transaction Workspace ledger's composed filter + search. Held here (not
    /// view-level) so the window restores its last query and the table + inspector
    /// share one source of truth (the prompt's "filter/search state lives in
    /// NavigationModel"). All facets compose; the default passes everything.
    public var transactionFilter: TransactionWorkspace.Filter

    /// The Transaction Workspace table sort order.
    public var transactionSort: TransactionWorkspace.Sort

    /// The selected transaction id in the workspace, or empty when none. Empty
    /// string (not `nil`) mirrors the `selectedAccountID` "" sentinel so the
    /// content-gated inspector shows its "Select a transaction" prompt.
    public var selectedTransactionID: String

    // MARK: Goals state (AND-606, Epic 5 net-new)

    /// The selected goal id (a `Goal.id` UUID string) in the Goals workspace, or
    /// empty when none. Empty string (not `nil`) mirrors the `selectedAccountID`
    /// "" sentinel so the content-gated Goals inspector shows its "Select a goal"
    /// prompt. Per-window scene state, **not** a selection singleton (the
    /// AND-621 anti-pattern). Ephemeral like the transaction selection: not
    /// persisted, so a relaunch lands on the unselected prompt.
    public var goalSelection: String
    // MARK: Budgets / Alerts selection state (AND-621)

    /// The selected category on the **Budgets** destination, or `nil` when none —
    /// shared between the category tree (content column) and the category
    /// detail/editor (inspector column). Previously the singleton
    /// `BudgetsSelectionModel.shared`; holding it here makes two windows hold
    /// independent Budgets selection. `nil` (an enum has no "" sentinel)
    /// content-gates the inspector to its "Select a category" prompt.
    public var budgetCategorySelection: SpendingCategory?

    /// The selected alert id on the **Alerts** destination, or empty when none —
    /// shared between the alert list (content column) and the alert detail
    /// (inspector column). Previously the singleton `AlertsSelectionModel.shared`;
    /// holding it here makes two windows hold independent Alerts selection.
    /// Empty string (not `nil`) mirrors the `selectedTransactionID` "" sentinel so
    /// the content-gated inspector shows its "Select an alert" prompt.
    public var alertSelection: String

    /// Alert ids the user has acknowledged this session, shared between the list
    /// (writes) and the inspector (reflects the bit). Previously held on the
    /// singleton `AlertsSelectionModel`; per-window here so two windows acknowledge
    /// independently. Ephemeral session state — acknowledging mutes an alert
    /// from the unacknowledged count without resolving the underlying condition.
    public var acknowledgedAlertIDs: Set<String>

    // MARK: Review workspace mode (AND-616)

    /// The Review destination's Triage ↔ Table presentation. Held per-window so the
    /// "Open review table" affordance can land the multi-select table while a fresh
    /// window still opens on triage. Ephemeral per-window UI state (not persisted) —
    /// a fresh window defaults to `.triage`, and the glance weekly-review deep-link
    /// (`Route.from(weeklyReview:)`) still lands triage.
    public var reviewWorkspaceMode: ReviewWorkspaceMode

    // MARK: Surface presentation state (AND-600 — retired single-surface AppState flags)

    /// Whether this window's menu-bar popover surface is presented. Previously the
    /// single `AppState.isPopoverPresented` flag — a global property of the whole
    /// app, so it could only describe one surface. Held per-window here so each
    /// window's presentation is independent. Ephemeral session state, **not**
    /// persisted (a relaunch never auto-opens the popover).
    public var isPopoverPresented: Bool

    /// Whether this window's dashboard lives in the detached floating desktop
    /// window instead of the menu-bar popover (AND-384). Previously the single
    /// `AppState.isDashboardDetached` flag. Held per-window here so two windows
    /// hold independent detach intent. This is the durable intent; the
    /// `NavigationModel` wrapper persists it to `DetachedDashboardPreferences`'
    /// key so the floating window reopens on the next launch, exactly as before.
    public var isDashboardDetached: Bool

    public init(
        destination: RouteDestination = .dashboard,
        dashboardFilter: DashboardAccountFilterKind = .all,
        selectedAccountID: String = "",
        heatmapMode: SpendingHeatmapMode = .spending,
        transactionFilter: TransactionWorkspace.Filter = TransactionWorkspace.Filter(),
        transactionSort: TransactionWorkspace.Sort = .dateDescending,
        selectedTransactionID: String = "",
        goalSelection: String = "",
        budgetCategorySelection: SpendingCategory? = nil,
        alertSelection: String = "",
        acknowledgedAlertIDs: Set<String> = [],
        reviewWorkspaceMode: ReviewWorkspaceMode = .triage,
        isPopoverPresented: Bool = false,
        isDashboardDetached: Bool = false
    ) {
        self.destination = destination
        self.dashboardFilter = dashboardFilter
        self.selectedAccountID = selectedAccountID
        self.heatmapMode = heatmapMode
        self.transactionFilter = transactionFilter
        self.transactionSort = transactionSort
        self.selectedTransactionID = selectedTransactionID
        self.goalSelection = goalSelection
        self.budgetCategorySelection = budgetCategorySelection
        self.alertSelection = alertSelection
        self.acknowledgedAlertIDs = acknowledgedAlertIDs
        self.reviewWorkspaceMode = reviewWorkspaceMode
        self.isPopoverPresented = isPopoverPresented
        self.isDashboardDetached = isDashboardDetached
    }

    // MARK: - Pure transitions

    /// Navigate to a bare destination, preserving the per-destination selection
    /// already held. (Selection within a destination is preserved across
    /// destination switches — the selection-restoration contract.) A deprecated
    /// destination (``RouteDestination/canonicalRedirect``) redirects to its live
    /// target instead — the deprecate-in-place mechanism (Gate-0, AND-979).
    public mutating func go(to destination: RouteDestination) {
        self.destination = destination.canonicalRedirect ?? destination
    }

    /// Apply a typed ``Route``: select its destination and fold any carried
    /// selection into the matching state slot. Only the selection slots this PR
    /// owns (dashboard account selection) are written here; richer per-destination
    /// selection (transaction id, category, goal id) is added as those
    /// destinations land in later Epic 2 subs.
    ///
    /// A route targeting a deprecated destination lands on its redirect instead
    /// (``RouteDestination/canonicalRedirect``) — the deprecate-in-place mechanism
    /// (Gate-0, AND-979) — so an old `.planning(section:)` construction still
    /// resolves somewhere live rather than a destination nothing renders.
    public mutating func apply(_ route: Route) {
        destination = route.destination.canonicalRedirect ?? route.destination
        switch route {
        case .accounts(let itemID):
            // An account deep-link selects that account on the dashboard surface
            // too, so the existing inspector follows the link.
            if let itemID { selectedAccountID = itemID }
        case .transactions(let criteria, _):
            // A Transactions deep-link that carries filter criteria (e.g. the
            // Dashboard spend-donut → "show this group's transactions", AND-730)
            // pre-applies them as the active ledger filter. `setTransactionFilter`
            // clears any stale row selection on a real change, so the inspector
            // returns to its prompt rather than pointing at a now-hidden row. A
            // `nil`/empty criteria leaves the workspace filter untouched, so a bare
            // `.transactions()` navigation does not wipe the user's current filter.
            if let criteria {
                setTransactionFilter(criteria.workspaceFilter)
            }
        case .dashboard,
             .review,
             .budgets,
             .planning,
             .goals,
             .insights,
             .alerts,
             .settings:
            break
        }
    }

    /// Change the dashboard filter. Changing the filter clears the account
    /// selection — the rule `MainPopover` enforced via
    /// `.onChange(of: selectedFilterRawValue) { selectedAccountId = "" }`
    /// (AND-373/375). No-op (and no deselect) when the filter is unchanged, so a
    /// redundant set does not surprise-deselect.
    public mutating func setDashboardFilter(_ filter: DashboardAccountFilterKind) {
        guard filter != dashboardFilter else { return }
        dashboardFilter = filter
        selectedAccountID = ""
    }

    /// Select an account on the dashboard.
    public mutating func selectAccount(id: String) {
        selectedAccountID = id
    }

    /// Clear the dashboard account selection.
    public mutating func deselectAccount() {
        selectedAccountID = ""
    }

    /// Drop a persisted selection that no longer maps to a visible account — the
    /// self-heal `MainPopover` performed in `.onChange(of: filteredAccounts)`
    /// when accounts first populate. Returns `true` when a stale selection was
    /// cleared so a caller can react (e.g. animate the column collapse).
    @discardableResult
    public mutating func reconcileSelection(visibleAccountIDs: [String]) -> Bool {
        guard !selectedAccountID.isEmpty,
              !visibleAccountIDs.contains(selectedAccountID) else {
            return false
        }
        selectedAccountID = ""
        return true
    }

    /// The selected id resolved against the currently visible accounts — `nil`
    /// when nothing is selected or the selection is no longer visible. Mirrors
    /// `DashboardAccountSelection.resolvedSelectedId`, exposed here so the
    /// migrated `selectedAccount` computed property reads identically.
    public func resolvedSelectedID(visibleAccountIDs: [String]) -> String? {
        DashboardAccountSelection.resolvedSelectedId(
            selectedAccountID,
            visibleAccountIds: visibleAccountIDs
        )
    }

    // MARK: - Transaction Workspace transitions (AND-582)

    /// Replace the workspace filter/search. Changing the filter clears the row
    /// selection (the selected row may no longer be listed), mirroring the
    /// dashboard filter→deselect rule. No-op (and no deselect) when unchanged.
    public mutating func setTransactionFilter(_ filter: TransactionWorkspace.Filter) {
        guard filter != transactionFilter else { return }
        transactionFilter = filter
        selectedTransactionID = ""
    }

    /// Change the workspace sort order (does not affect the selection).
    public mutating func setTransactionSort(_ sort: TransactionWorkspace.Sort) {
        transactionSort = sort
    }

    /// Select a transaction row in the workspace.
    public mutating func selectTransaction(id: String) {
        selectedTransactionID = id
    }

    /// Clear the workspace row selection.
    public mutating func deselectTransaction() {
        selectedTransactionID = ""
    }

    /// Drop a selected transaction id that is no longer among the visible (filtered)
    /// rows — the same self-heal the dashboard does for accounts. Returns `true`
    /// when a stale selection was cleared.
    @discardableResult
    public mutating func reconcileTransactionSelection(visibleTransactionIDs: [String]) -> Bool {
        guard !selectedTransactionID.isEmpty,
              !visibleTransactionIDs.contains(selectedTransactionID) else {
            return false
        }
        selectedTransactionID = ""
        return true
    }

    // MARK: - Goals transitions (AND-606)

    /// Select a goal in the Goals workspace (drives the inspector).
    public mutating func selectGoal(id: String) {
        goalSelection = id
    }

    /// Clear the Goals workspace selection.
    public mutating func deselectGoal() {
        goalSelection = ""
    }

    /// Drop a selected goal id that is no longer among the visible goals — the same
    /// self-heal the dashboard does for accounts (e.g. the selected goal was just
    /// deleted). Returns `true` when a stale selection was cleared.
    @discardableResult
    public mutating func reconcileGoalSelection(visibleGoalIDs: [String]) -> Bool {
        guard !goalSelection.isEmpty,
              !visibleGoalIDs.contains(goalSelection) else {
            return false
        }
        goalSelection = ""
        return true
    }

    // MARK: - Budgets selection transitions (AND-621)

    /// Select a category on the Budgets destination (drives the inspector).
    public mutating func selectBudgetCategory(_ category: SpendingCategory?) {
        budgetCategorySelection = category
    }

    /// Clear the Budgets category selection.
    public mutating func deselectBudgetCategory() {
        budgetCategorySelection = nil
    }

    // MARK: - Alerts selection transitions (AND-621)

    /// Select an alert row on the Alerts destination (drives the inspector).
    public mutating func selectAlert(id: String) {
        alertSelection = id
    }

    /// Clear the Alerts selection.
    public mutating func deselectAlert() {
        alertSelection = ""
    }

    /// Acknowledge a single alert (mute it from the unacknowledged count).
    public mutating func acknowledgeAlert(_ id: String) {
        acknowledgedAlertIDs.insert(id)
    }

    /// Un-acknowledge a single alert (re-surface it in the count).
    public mutating func unacknowledgeAlert(_ id: String) {
        acknowledgedAlertIDs.remove(id)
    }

    /// Acknowledge every currently-listed alert ("acknowledge all").
    public mutating func acknowledgeAllAlerts(in inbox: AlertsInbox) {
        for entry in inbox.entries {
            acknowledgedAlertIDs.insert(entry.id)
        }
    }

    /// Prune acknowledged ids + a stale selection to the live rows, so neither
    /// lingers for a condition that has since resolved. Mirrors the self-heal the
    /// retired `AlertsSelectionModel.prune(toRowsIn:)` performed.
    public mutating func pruneAlerts(toRowsIn rows: [AttentionQueueRow]) {
        let pruned = AlertsInbox.pruneAcknowledgedIDs(acknowledgedAlertIDs, toRowsIn: rows)
        if pruned != acknowledgedAlertIDs {
            acknowledgedAlertIDs = pruned
        }
        if !alertSelection.isEmpty, !rows.contains(where: { $0.id == alertSelection }) {
            alertSelection = ""
        }
    }

    // MARK: - Review workspace mode transitions (AND-616)

    /// Set the Review destination's Triage ↔ Table presentation. Used by the
    /// "Open review table" affordance to land the table before navigating to Review.
    public mutating func setReviewWorkspaceMode(_ mode: ReviewWorkspaceMode) {
        reviewWorkspaceMode = mode
    }

    // MARK: - Surface presentation transitions (AND-600)

    /// Present or dismiss this window's menu-bar popover surface.
    public mutating func setPopoverPresented(_ isPresented: Bool) {
        isPopoverPresented = isPresented
    }

    /// Mark the dashboard detached into the floating window. Dismisses the popover —
    /// only one surface is up at a time (the rule the
    /// `DetachedDashboardCoordinator.detach` path enforced when these flags lived on
    /// `AppState`).
    public mutating func detachDashboard() {
        isDashboardDetached = true
        isPopoverPresented = false
    }

    /// Re-dock the dashboard back into the menu-bar popover.
    public mutating func redockDashboard() {
        isDashboardDetached = false
    }
}
