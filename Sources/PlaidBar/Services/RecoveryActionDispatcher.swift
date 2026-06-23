import AppKit
import PlaidBarCore
import SwiftUI

/// The single place that maps a converged ``RecoveryAction`` onto the `AppState`
/// entry point that performs it (post-1.0 priority #3: converged recovery
/// actions).
///
/// Before convergence, the dashboard readiness panel, the menu-bar popover, the
/// attention queue, the Alerts inspector, and the menu-bar glance each carried a
/// near-identical `perform(_:)` switch — the same `checkServer → refresh →
/// reconnect → openSettings → notification` mapping copied five times, drifting
/// slightly each time (one fell back to `refreshAccounts`, another to
/// `refreshDashboard`; one ran `addAccount()` directly, another took an
/// `onAddAccount` closure). Every surface now dispatches through this one type, so
/// a verb means exactly the same thing — and runs exactly the same `AppState`
/// method — everywhere.
///
/// `@MainActor` because it touches `AppState` (itself `@MainActor`) and opens
/// windows. The per-surface differences (how to open Settings, whether to deep
/// link a route, what "add account" does on this surface) are injected as
/// closures so the mapping body stays identical.
@MainActor
struct RecoveryActionDispatcher {
    let appState: AppState
    /// Opens VaultPeek Settings. Surfaces inside the SwiftUI window pass the
    /// `\.openSettings` environment action; others pass a bespoke opener.
    var openSettings: () -> Void
    /// Window-first deep link. No-op by default so flag-OFF surfaces keep their
    /// in-place behavior; installed with a real handler only when window-first is
    /// ON. When provided, route-mapped actions open the window instead of running
    /// the in-place action.
    var openRoute: ((Route) -> Void)?
    /// What "add an account" means on this surface — some surfaces run a setup
    /// flow (`onAddAccount`), others call `appState.addAccount()` directly. When
    /// `nil`, falls back to `appState.addAccount()`.
    var onAddAccount: (() -> Void)?

    init(
        appState: AppState,
        openSettings: @escaping () -> Void,
        openRoute: ((Route) -> Void)? = nil,
        onAddAccount: (() -> Void)? = nil
    ) {
        self.appState = appState
        self.openSettings = openSettings
        self.openRoute = openRoute
        self.onAddAccount = onAddAccount
    }

    /// Dispatch a converged recovery button — the preferred entry point, since the
    /// button folds the `targetItemId` an item-scoped `.reconnect` needs.
    func dispatch(_ button: RecoveryActionButton) {
        perform(button.action, targetItemId: button.targetItemId)
    }

    /// Dispatch the recovery action carried by an attention queue row, honoring the
    /// window-first deep link when one is available.
    func dispatch(_ row: AttentionQueueRow) {
        if let route = routedDestination(for: row.action, targetItemId: row.targetItemId) {
            openRoute?(route)
            return
        }
        guard let action = row.action else { return }
        perform(action, targetItemId: row.targetItemId)
    }

    /// Dispatch a bare verb, resolving an item target from the row/button when one
    /// was carried, else from the live item statuses (so a dashboard `.reconnect`
    /// with no carried target still finds the degraded item).
    func perform(_ action: RecoveryAction, targetItemId: String? = nil) {
        switch action {
        case .checkServer:
            Task { await appState.checkServerConnection() }
        case .addAccount:
            if let onAddAccount {
                onAddAccount()
            } else {
                Task { await appState.addAccount() }
            }
        case .refresh:
            Task { await appState.refreshDashboard() }
        case .refreshAccounts:
            Task { await appState.refreshAccounts() }
        case .syncTransactions:
            Task { await appState.syncTransactions() }
        case .reconnect:
            guard let itemId = targetItemId ?? ItemRecoveryTarget.itemId(from: appState.itemStatuses) else {
                // No resolvable item — refresh so the status re-evaluates rather
                // than opening Link with no target.
                Task { await appState.refreshDashboard() }
                return
            }
            Task { await appState.reconnectItem(itemId: itemId) }
        case .openSettings:
            openSettings()
        case .requestNotificationPermission:
            Task { _ = await appState.requestNotificationPermission() }
        case .openNotificationSettings:
            openNotificationSettings()
        case .clearFilters, .showWiderPeriod:
            // Surface-local view-state verbs (search/filter, period window). The
            // dispatcher owns no view state, so these are handled by the calling
            // surface; reaching here is a no-op by design.
            break
        }
    }

    /// The window-first destination a verb should open, or `nil` to run the
    /// in-place action. Only resolves when a route handler is installed
    /// (window-first ON), so flag-OFF surfaces never deep link.
    private func routedDestination(for action: RecoveryAction?, targetItemId: String?) -> Route? {
        guard openRoute != nil, let action else { return nil }
        guard let route = Route.from(recoveryAction: action, targetItemId: targetItemId) else { return nil }
        return route.resolvingAccountSelection(in: appState.accounts)
    }

    /// Open the macOS System Settings notifications pane, falling back to VaultPeek
    /// Settings if the deep-link URL cannot be built.
    private func openNotificationSettings() {
        guard let url = URL(string: "x-apple.systempreferences:com.apple.Notifications-Settings.extension") else {
            openSettings()
            return
        }
        NSWorkspace.shared.open(url)
    }
}
