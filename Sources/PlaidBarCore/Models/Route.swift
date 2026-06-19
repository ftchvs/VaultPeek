import Foundation

// MARK: - Route destinations

/// The 11 primary destinations of the window-first navigation shell (ADR-001,
/// `docs/strategy/macos26-migration/05-information-architecture.md`).
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

    /// The IA sidebar band a destination lives in (Overview / Workflows /
    /// Insights / Money / System). Grouping the verbs together is the IA's
    /// "list of jobs to do" model (§2 of the IA doc).
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

    /// The `⌘N` shortcut number for the destination, matching the IA keymap's
    /// explicit `[⌘1]…[⌘8]` assignments (§3.4 and the destination tree):
    /// Dashboard 1 · Review 2 · Budgets 3 · Planning 4 · Goals 5 · Insights 6 ·
    /// Alerts 7 · Accounts 8. `Transactions` is reachable via the sidebar / ⌘K /
    /// deep-links but has no number (the IA tree assigns none), and `Settings`
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
    /// IA's column-policy table (§3.1). 2-column destinations are composed
    /// canvases with no master→detail relationship.
    public var prefersThreeColumnLayout: Bool {
        switch self {
        case .review, .transactions, .budgets, .goals, .alerts, .accounts:
            true
        case .dashboard, .planning, .insights, .settings:
            false
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

/// Planning's segmented sub-sections (§5.5 of the IA doc) — Planning is a
/// composed 2-column canvas, so these select a section rather than a list item.
public enum PlanningSection: String, CaseIterable, Sendable, Hashable, Codable {
    case forecast
    case recurring
    case incomeFlow
}

/// Insights' feed sub-sections (§5.7 of the IA doc).
public enum InsightSection: String, CaseIterable, Sendable, Hashable, Codable {
    case receipts
    case weeklyReview
    case trends
}

// MARK: - Route

/// A typed deep-link target. Any surface can navigate anywhere by constructing a
/// `Route`; the associated values carry the per-destination selection so a link
/// can land on a specific transaction, category, account, or sub-section.
///
/// Mirrors the IA doc's `Route` sketch (§2.1). `Equatable`/`Hashable`/`Sendable`
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
    /// `WeeklyReviewNavigationTarget` deep-links land on the new destinations
    /// (§2.1 of the IA doc). `.safeToSpend` lives on the Dashboard canvas.
    public static func from(weeklyReview target: WeeklyReviewNavigationTarget) -> Route {
        switch target {
        case .reviewInbox: .review()
        case .recurring: .planning(section: .recurring)
        case .safeToSpend: .dashboard
        }
    }
}
