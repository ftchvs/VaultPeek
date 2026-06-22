import Foundation

/// The single, converged vocabulary of recovery verbs every attention surface
/// can offer the user (post-1.0 priority #3: converged recovery actions).
///
/// VaultPeek presents five recoverable attention states — (1) local server
/// unreachable, (2) a Plaid item that needs login/repair, (3) empty-data /
/// first-run, (4) stale sync, (5) notification-permission. Before convergence each
/// surface (dashboard readiness panel, attention queue, secondary content
/// `ContentUnavailableView`s, the notification settings row, the account
/// connection chip) carried its *own* action enum and its *own* labels, so the
/// same state could read "Refresh Now" on one surface and "Refresh" on another,
/// or "Reconnect <Inst>" here and "Update <Inst>" there.
///
/// `RecoveryAction` unifies those verbs into one `Sendable`/`Codable` enum. It is
/// the superset of the legacy `DashboardStatusReadinessAction` and
/// `SecondaryContentUnavailableAction` (both now deprecated typealiases), keeping
/// every legacy raw value so existing `Codable` snapshots and `== .reconnect`
/// equality tests stay byte-stable. The item-scoped target for `.reconnectItem`
/// is **not** an associated value (which would break the `String` raw
/// representation the persisted `Route`/`AttentionQueueRow` snapshots rely on) —
/// it is carried alongside the verb by ``RecoveryActionButton``.
///
/// Pure + `Sendable` so it lives in `PlaidBarCore` and is unit-testable without
/// the app target (CLAUDE.md). The app-layer `RecoveryActionDispatcher` maps each
/// verb onto the matching `AppState` entry point.
public enum RecoveryAction: String, Codable, Sendable, CaseIterable, Hashable {
    /// STATE-1: re-check the local VaultPeek companion server connection.
    case checkServer
    /// STATE-3: start Plaid Link to connect a new institution.
    case addAccount
    /// STATE-4 / generic: refresh the dashboard (balances + transactions).
    case refresh
    /// STATE-3: refresh just account balances.
    case refreshAccounts
    /// STATE-3: run / re-run the transaction sync.
    case syncTransactions
    /// STATE-2: reconnect or update a degraded Plaid item through Link update mode.
    /// The affected item is carried by ``RecoveryActionButton/targetItemId``. The
    /// case name stays `reconnect` (and the raw value with it) so the converged
    /// enum is a byte-stable drop-in for the legacy `DashboardStatusReadinessAction`
    /// — every `== .reconnect` snapshot and persisted value keeps working.
    case reconnect
    /// Open VaultPeek Settings.
    case openSettings
    /// STATE-5: request macOS notification permission.
    case requestNotificationPermission
    /// STATE-5: open the macOS System Settings notification pane.
    case openNotificationSettings
    /// Empty-search recovery: clear the active search text / filters.
    case clearFilters
    /// Empty-period recovery: widen the spending period window.
    case showWiderPeriod

    /// The one canonical button title for this verb. Item-scoped reconnect and
    /// the few context-specific job titles ("Load Balances", "Run First Sync")
    /// are layered on top by the caller via
    /// ``RecoveryActionButton`` / `primaryActionTitle`, but this is the single
    /// source of truth that kills the cross-surface label drift.
    public var canonicalTitle: String {
        switch self {
        case .checkServer: "Check Server"
        case .addAccount: "Add Account"
        case .refresh: "Refresh"
        case .refreshAccounts: "Refresh Accounts"
        case .syncTransactions: "Sync Transactions"
        case .reconnect: "Reconnect"
        case .openSettings: "Settings"
        case .requestNotificationPermission: "Request Permission"
        case .openNotificationSettings: "Open System Settings"
        case .clearFilters: "Clear Filters"
        case .showWiderPeriod: "Show Wider Period"
        }
    }

    /// The one canonical SF Symbol for this verb. Chrome only — meaning is always
    /// carried by the accompanying label too, never the glyph alone
    /// (ACCESSIBILITY.md).
    public var canonicalIconName: String {
        switch self {
        case .checkServer: "server.rack"
        case .addAccount: "plus.circle"
        case .refresh: "arrow.clockwise"
        case .refreshAccounts: "arrow.clockwise"
        case .syncTransactions: "arrow.triangle.2.circlepath"
        case .reconnect: "link.badge.plus"
        case .openSettings: "gearshape"
        case .requestNotificationPermission: "bell.badge"
        case .openNotificationSettings: "gearshape"
        case .clearFilters: "xmark.circle"
        case .showWiderPeriod: "calendar"
        }
    }
}

/// The canonical, surface-agnostic description of a recovery button: which
/// converged ``RecoveryAction`` it runs, the resolved title + icon, an optional
/// VoiceOver hint, whether the control is interactive (some recovery copy is
/// advisory-only, e.g. "Run App Bundle"), and the item it targets.
///
/// This folds what used to be spread across `ItemRecoveryTarget` (the
/// item-scoped reconnect target + institution-qualified title) and each surface's
/// bespoke `(action, title, icon)` triple into ONE value, so every surface emits
/// the same button shape and an item reconnect carries its `targetItemId` in the
/// same place everywhere. `Equatable`/`Sendable`/`Codable` so it is testable and
/// persistable; the app layer hands the button's `action` + `targetItemId` to the
/// dispatcher.
public struct RecoveryActionButton: Equatable, Sendable, Codable, Hashable {
    public let action: RecoveryAction
    public let title: String
    public let iconName: String
    public let accessibilityHint: String?
    /// `false` for advisory recovery copy whose "action" is informational only
    /// (the button is shown disabled), e.g. notification identity unavailable.
    public let isInteractive: Bool
    /// The Plaid `item_id` an item-scoped `.reconnectItem` targets; `nil` for
    /// non-item actions. Folds the role `ItemRecoveryTarget` used to play.
    public let targetItemId: String?

    public init(
        action: RecoveryAction,
        title: String? = nil,
        iconName: String? = nil,
        accessibilityHint: String? = nil,
        isInteractive: Bool = true,
        targetItemId: String? = nil
    ) {
        self.action = action
        self.title = title ?? action.canonicalTitle
        self.iconName = iconName ?? action.canonicalIconName
        self.accessibilityHint = accessibilityHint
        self.isInteractive = isInteractive
        self.targetItemId = targetItemId
    }

    /// Builds the item-scoped reconnect button for the highest-priority degraded
    /// item in `statuses` (errored items first, then update-mode items), folding
    /// `ItemRecoveryTarget` so the institution-qualified title ("Reconnect Chase"
    /// / "Update Chase") and the `targetItemId` are produced in one place.
    /// Returns `nil` when no item needs recovery.
    public static func reconnect(from statuses: [ItemStatus]) -> RecoveryActionButton? {
        guard let itemId = ItemRecoveryTarget.itemId(from: statuses) else { return nil }
        return RecoveryActionButton(
            action: .reconnect,
            title: ItemRecoveryTarget.actionTitle(from: statuses),
            accessibilityHint: "Reconnects this institution through Plaid Link.",
            targetItemId: itemId
        )
    }
}
