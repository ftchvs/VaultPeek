import Foundation

// MARK: - Route destinations

/// The 11 primary destinations of the window-first navigation shell.
///
/// This is the *bare destination identity* — the sidebar selection token and the
/// thing `⌘1…⌘8` jump to. The richer ``Route`` carries the per-destination
/// selection (e.g. which transaction, which category) on top of one of these.
///
/// Pure and `Sendable`, so the navigation state and its transitions are testable
/// without the SwiftUI app target (CLAUDE.md: shared logic lives in
/// `PlaidBarCore`). The order of `allCases` is the sidebar order; the `⌘`
/// shortcut ordinal is derived from it (Dashboard…Accounts = ⌘1…⌘8; Settings is
/// the native `⌘,` scene and has no numeric shortcut).
public enum RouteDestination: String, CaseIterable, Sendable, Hashable, Codable {
    case dashboard
    case review
    case transactions
    case budgets
    case planning
    case goals
    case insights
    case alerts
    case accounts
    case settings

    /// The sidebar band a destination lives in (Overview / Workflows /
    /// Insights / Money / System). Grouping the verbs together is the
    /// "list of jobs to do" model.
    public enum Band: String, CaseIterable, Sendable, Hashable, Codable {
        case overview
        case workflows
        case insights
        case money
        case system

        public var title: String {
            switch self {
            case .overview: "Overview"
            case .workflows: "Workflows"
            case .insights: "Insights"
            case .money: "Money"
            case .system: "System"
            }
        }
    }

    public var band: Band {
        switch self {
        case .dashboard: .overview
        case .review, .transactions, .budgets, .planning, .goals: .workflows
        case .insights, .alerts: .insights
        case .accounts: .money
        case .settings: .system
        }
    }

    /// Sidebar / window-title label.
    public var title: String {
        switch self {
        case .dashboard: "Dashboard"
        case .review: "Review"
        case .transactions: "Transactions"
        case .budgets: "Budgets"
        case .planning: "Planning"
        case .goals: "Goals"
        case .insights: "Insights"
        case .alerts: "Alerts"
        case .accounts: "Accounts"
        case .settings: "Settings"
        }
    }

    /// SF Symbol for the sidebar row (chrome only — never the sole carrier of
    /// meaning; the label always accompanies it).
    public var systemImage: String {
        switch self {
        case .dashboard: "rectangle.3.group"
        case .review: "tray.full"
        case .transactions: "list.bullet.rectangle"
        case .budgets: "chart.pie"
        case .planning: "calendar.badge.clock"
        case .goals: "target"
        case .insights: "lightbulb"
        case .alerts: "bell"
        case .accounts: "building.columns"
        case .settings: "gearshape"
        }
    }

    /// The `⌘N` shortcut number for the destination, matching the keymap's
    /// explicit `[⌘1]…[⌘8]` assignments:
    /// Dashboard 1 · Review 2 · Budgets 3 · Planning 4 · Goals 5 · Insights 6 ·
    /// Alerts 7 · Accounts 8. `Transactions` is reachable via the sidebar / ⌘K /
    /// deep-links but has no number, and `Settings`
    /// uses the native `⌘,` scene — both return `nil`.
    public var commandShortcutNumber: Int? {
        switch self {
        case .dashboard: 1
        case .review: 2
        case .budgets: 3
        case .planning: 4
        case .goals: 5
        case .insights: 6
        case .alerts: 7
        case .accounts: 8
        case .transactions, .settings: nil
        }
    }

    /// Whether the destination renders a 3-column (list → detail) layout, per the
    /// column-policy table. 2-column destinations are composed
    /// canvases with no master→detail relationship.
    public var prefersThreeColumnLayout: Bool {
        switch self {
        case .review, .transactions, .budgets, .goals, .alerts, .accounts:
            true
        case .dashboard, .planning, .insights, .settings:
            false
        }
    }

    /// The inspector (detail-column) empty-state prompt a 3-column destination
    /// shows when nothing is selected. The third column is **content-gated, not
    /// existence-gated**: it always exists and shows a "Select a …"
    /// `ContentUnavailableView` rather than collapsing. `nil` for 2-column
    /// destinations and the native Settings scene, which have no inspector column.
    ///
    /// Pure copy in `PlaidBarCore` so the per-destination prompt — and the
    /// "3-column ⇔ non-nil prompt" invariant — is unit-testable without the app
    /// target (CLAUDE.md). The real per-row inspector content lands with each
    /// destination's workspace in Epics 4–7.
    public var detailColumnEmptyPrompt: String? {
        switch self {
        case .review: "Select an item to review"
        case .transactions: "Select a transaction"
        case .budgets: "Select a category"
        case .goals: "Select a goal"
        case .alerts: "Select an alert"
        case .accounts: "Select an account"
        case .dashboard, .planning, .insights, .settings: nil
        }
    }
}

// MARK: - Sub-section enums

/// The native Settings scene's tabs, expressed in `PlaidBarCore` so a ``Route``
/// can target one without coupling Core to the app target's private
/// `SettingsTab`. Raw values match the app's `@AppStorage("settings.selectedTab")`
/// values so a routed tab decodes against the same persisted key.
public enum SettingsRouteTab: String, CaseIterable, Sendable, Hashable, Codable {
    case general
    case accounts
    case appearance
    case notifications
    case privacy
    case about
}

/// Planning's segmented sub-sections — Planning is a
/// composed 2-column canvas, so these select a section rather than a list item.
public enum PlanningSection: String, CaseIterable, Sendable, Hashable, Codable {
    case forecast
    case recurring
    case incomeFlow
}

/// Insights' feed sub-sections.
public enum InsightSection: String, CaseIterable, Sendable, Hashable, Codable {
    case receipts
    case weeklyReview
    case trends
}

/// The Review workspace's Triage ↔ Table presentation (Epic 6, AND-616). Lives in
/// `PlaidBarCore` (rather than as a private view-level enum) so the in-window
/// route hooks can set the mode before navigating and the mode→navigation
/// behavior is unit-testable without the app target (CLAUDE.md). A small,
/// `Sendable`, `RawRepresentable` enum so it can drive a `Picker`/persisted store.
public enum ReviewWorkspaceMode: String, Sendable, Codable, CaseIterable {
    /// Single-item triage: the embedded `ReviewInboxView` with date sections,
    /// single-key actions, inline rule prompt, and undo.
    case triage
    /// Multi-select power review: the embedded `ReviewTableWindow` bulk engine with
    /// blast-radius confirmation.
    case table

    public var label: String {
        switch self {
        case .triage: "Triage"
        case .table: "Table"
        }
    }

    public var systemImage: String {
        switch self {
        case .triage: "checklist"
        case .table: "tablecells"
        }
    }
}

// MARK: - Route

/// A typed deep-link target. Any surface can navigate anywhere by constructing a
/// `Route`; the associated values carry the per-destination selection so a link
/// can land on a specific transaction, category, account, or sub-section.
///
/// `Equatable`/`Hashable`/`Sendable`
/// + `Codable` so it can be persisted (selection restoration across launches)
/// and compared in tests. The actual sidebar / ⌘K / deep-link *UI* is later in
/// Epic 2 (AND-595/596/597); this PR introduces the model and migrates state.
public enum Route: Sendable, Hashable, Codable {
    case dashboard
    case review(itemID: String? = nil)
    case transactions(filter: TransactionFilterCriteria? = nil, focus: String? = nil)
    case budgets(category: SpendingCategory? = nil)
    case planning(section: PlanningSection = .forecast)
    case goals(id: UUID? = nil)
    case insights(section: InsightSection = .receipts)
    case alerts(id: String? = nil)
    case accounts(itemID: String? = nil)
    case settings(tab: SettingsRouteTab = .general)

    /// The bare destination this route resolves to — what the sidebar selects and
    /// what a `⌘N` shortcut jumps to.
    public var destination: RouteDestination {
        switch self {
        case .dashboard: .dashboard
        case .review: .review
        case .transactions: .transactions
        case .budgets: .budgets
        case .planning: .planning
        case .goals: .goals
        case .insights: .insights
        case .alerts: .alerts
        case .accounts: .accounts
        case .settings: .settings
        }
    }

    /// The canonical route for a bare destination, using each case's default
    /// selection. Lets the sidebar (which selects a `RouteDestination`) produce a
    /// full `Route` without inventing selection.
    public static func canonical(for destination: RouteDestination) -> Route {
        switch destination {
        case .dashboard: .dashboard
        case .review: .review()
        case .transactions: .transactions()
        case .budgets: .budgets()
        case .planning: .planning()
        case .goals: .goals()
        case .insights: .insights()
        case .alerts: .alerts()
        case .accounts: .accounts()
        case .settings: .settings()
        }
    }

    /// Maps a weekly-review navigation target onto a route, so the existing
    /// `WeeklyReviewNavigationTarget` deep-links land on the new destinations.
    /// `.safeToSpend` lives on the Dashboard canvas.
    public static func from(weeklyReview target: WeeklyReviewNavigationTarget) -> Route {
        switch target {
        case .reviewInbox: .review()
        case .recurring: .planning(section: .recurring)
        case .safeToSpend: .dashboard
        }
    }

    /// Maps a menu-bar **glance attention chip** onto the destination it should
    /// open the window at (the menu-bar glance → window hand-off). A glance chip
    /// is a launcher: tapping "Card over 75%" opens
    /// **Accounts** at that card, "3 to review" opens **Review**, a stale-spend
    /// chip opens **Transactions** — *not* just the Dashboard.
    ///
    /// Returns `nil` for chips that carry no meaningful in-window destination —
    /// the local-infrastructure rows (server offline, missing/rejected auth,
    /// missing credentials, mode mismatch, the generic recent-error / sync /
    /// notification rows). Those keep their existing in-place *action* (check the
    /// server, open Settings, refresh) rather than routing somewhere unhelpful;
    /// the caller falls back to the row's `action` when this is `nil`.
    ///
    /// Pure (keyed off the row's stable `id` + carried `targetItemId`) so the
    /// glance → route decision is unit-testable at the Core layer without the app
    /// target (CLAUDE.md). The window-first flag gating and the actual
    /// `openWindow` live in the app target; this only decides *where* a chip
    /// points.
    public static func from(attentionRow row: AttentionQueueRow) -> Route? {
        // Degraded-institution rows (reconnect / fresh-login / outage) point at
        // Accounts, selecting the affected item so the inspector follows the link.
        if row.id.hasPrefix("item-error-")
            || row.id.hasPrefix("item-repair-")
            || row.id.hasPrefix("item-outage-") {
            return .accounts(itemID: row.targetItemId)
        }

        switch row.id {
        // Financial cockpit chips route to where the user reviews that signal.
        case "financial-low-cash":
            // Low cash → review cash accounts.
            return .accounts()
        case "financial-high-utilization":
            // "Card over 75%" → the credit card inspector in Accounts.
            return .accounts()
        case "financial-unusual-spending":
            // "Recent spending changed" → recent activity in Transactions.
            return .transactions()
        default:
            // Local-infrastructure + generic rows have no in-window destination;
            // the caller keeps their existing action.
            return nil
        }
    }

    /// Resolves an `.accounts(itemID:)` deep-link whose `itemID` is actually a
    /// Plaid *item_id* into one keyed by the matching `AccountDTO.id`, so the
    /// Accounts destination (which selects by `AccountDTO.id`) lands on the right
    /// row.
    ///
    /// Degraded-institution attention chips carry the affected Plaid `item_id`
    /// (`AttentionQueueRow.targetItemId`), but the Accounts list selects accounts
    /// by `AccountDTO.id`; `AccountDTO.itemId` provides the item→account hop. For a
    /// multi-account item the **first matching account is selected by design** —
    /// the chip points at the institution, and the inspector then surfaces the
    /// item's other accounts.
    ///
    /// Any non-`.accounts` route, an `.accounts(itemID: nil)` route, or an item id
    /// with no matching account returns `self` unchanged, so the caller can apply
    /// the result unconditionally. Pure + `accounts`-driven so the resolution is
    /// unit-testable at the Core layer (CLAUDE.md); the `AppState` wiring that calls
    /// this with the live account list lives in the app target.
    public func resolvingAccountSelection(in accounts: [AccountDTO]) -> Route {
        if case .accounts(let itemID?) = self,
           let accountID = accounts.first(where: { $0.itemId == itemID })?.id {
            return .accounts(itemID: accountID)
        }
        return self
    }
}
