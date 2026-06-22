import PlaidBarCore
import SwiftUI

/// The content-column router for the window-first shell (AND-580/581).
///
/// Maps the window's selected `RouteDestination` to its per-destination content
/// view. Each destination owns its own `…DestinationView` file under
/// `Views/Destinations/`, so the parallel Epics 4–7 each fill their own file
/// without ever colliding in `AppShellView` — this `switch` is the single point
/// the shell touches.
///
/// **Settings is never routed here**: its sidebar row opens the native macOS
/// `Settings` scene, so the shell maps a Settings tap to
/// `openSettings()` and the split-view selection never parks on `.settings`. The
/// `.settings` arm falls back to the shared placeholder defensively, but it is
/// unreachable in practice.
///
/// Window-first surface only: built solely behind `WindowFirstFeatureFlag`
/// (default OFF), so with the flag off none of this is instantiated.
struct DestinationContentView: View {
    let destination: RouteDestination

    var body: some View {
        switch destination {
        case .dashboard: DashboardDestinationView()
        case .review: ReviewDestinationView()
        case .transactions: TransactionsDestinationView()
        case .budgets: BudgetsDestinationView()
        case .planning: PlanningDestinationView()
        case .goals: GoalsDestinationView()
        case .insights: InsightsDestinationView()
        case .alerts: AlertsDestinationView()
        case .accounts: AccountsDestinationView()
        case .settings:
            // Unreachable — Settings opens the native scene, not an in-split pane.
            DestinationPlaceholder(destination: .settings)
        }
    }
}

/// The detail-column (inspector) router for the window-first shell.
///
/// Only the **3-column** destinations (`RouteDestination.prefersThreeColumnLayout`
/// — Review, Transactions, Budgets, Goals, Alerts, Accounts) have an inspector;
/// for them this maps to the destination's `Inspector` pane. The 2-column
/// destinations and Settings have no detail column and `AppShellView` never
/// mounts this for them, so their arms fall back to the content-gated empty
/// prompt defensively.
///
/// The third column is **content-gated, not existence-gated**: each
/// `Inspector` shows its "Select a …" prompt when nothing is selected rather than
/// collapsing.
struct DestinationInspectorView: View {
    let destination: RouteDestination

    var body: some View {
        switch destination {
        case .review: ReviewDestinationView.Inspector()
        case .transactions: TransactionsDestinationView.Inspector()
        case .budgets: BudgetsDestinationView.Inspector()
        case .goals: GoalsDestinationView.Inspector()
        case .alerts: AlertsDestinationView.Inspector()
        case .accounts: AccountsDestinationView.Inspector()
        case .dashboard, .planning, .insights, .settings:
            // 2-column / native-Settings destinations have no inspector; not
            // mounted by the shell, shown defensively only.
            DestinationInspectorPlaceholder(destination: destination)
        }
    }
}
