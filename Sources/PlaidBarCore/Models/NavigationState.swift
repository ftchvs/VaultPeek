import Foundation

/// Pure, value-type navigation state for one window of the window-first shell
/// (ADR-001). Holds the current destination plus the per-destination selection
/// and filter state that used to live as scattered view-level
/// `@AppStorage` keys in `MainPopover` (`dashboard.accountFilter`,
/// `dashboard.selectedAccountId`, `dashboard.heatmapMode`).
///
/// This is a **value type**, so two windows that each own their own copy hold
/// *independent* selection — the R-10 contract (a per-window model, never a
/// singleton). The `@Observable @MainActor` `NavigationModel` wrapper in the app
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

    public init(
        destination: RouteDestination = .dashboard,
        dashboardFilter: DashboardAccountFilterKind = .all,
        selectedAccountID: String = "",
        heatmapMode: SpendingHeatmapMode = .spending
    ) {
        self.destination = destination
        self.dashboardFilter = dashboardFilter
        self.selectedAccountID = selectedAccountID
        self.heatmapMode = heatmapMode
    }

    // MARK: - Pure transitions

    /// Navigate to a bare destination, preserving the per-destination selection
    /// already held. (Selection within a destination is preserved across
    /// destination switches — the IA's selection-restoration contract.)
    public mutating func go(to destination: RouteDestination) {
        self.destination = destination
    }

    /// Apply a typed ``Route``: select its destination and fold any carried
    /// selection into the matching state slot. Only the selection slots this PR
    /// owns (dashboard account selection) are written here; richer per-destination
    /// selection (transaction id, category, goal id) is added as those
    /// destinations land in later Epic 2 subs.
    public mutating func apply(_ route: Route) {
        destination = route.destination
        switch route {
        case .accounts(let itemID):
            // An account deep-link selects that account on the dashboard surface
            // too, so the existing inspector follows the link.
            if let itemID { selectedAccountID = itemID }
        case .dashboard,
             .review,
             .transactions,
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
}
