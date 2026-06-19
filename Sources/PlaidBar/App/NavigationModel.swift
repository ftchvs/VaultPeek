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

    // MARK: - Navigation

    func go(to destination: RouteDestination) {
        state.go(to: destination)
    }

    func apply(_ route: Route) {
        state.apply(route)
        // A route may carry an account selection; persist it so a deep-link
        // landing point survives like a manual selection did.
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
        state = restored
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
}
