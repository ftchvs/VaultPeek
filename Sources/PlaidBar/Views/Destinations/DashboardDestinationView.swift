import PlaidBarCore
import SwiftUI

/// **Dashboard** destination (2-column composed canvas — IA §3.1/§5.1, `[⌘1]`) —
/// AND-622 (ADR-001 window-first workspace).
///
/// The default / primary surface: a composed *overview* canvas with no
/// master→detail relationship, so the shell renders only this content column (no
/// inspector). It re-hosts the **same overview content the menu-bar popover and
/// its detached desktop window show** (``MainPopover``), surfaced from the same
/// reusable subviews + the same `PlaidBarCore` presentation engines — **no model
/// or chart logic lives here** (surface only). The two surfaces can never diverge
/// because they read the same `AppState` and the same Core.
///
/// Layout (IA §5.1): a two-column canvas — a **Summary** column (the existing
/// ``WealthSummaryFlyout``: net-worth hero, balance mix, 30-day cashflow) beside
/// an **Overview** column (the change receipt, balance time-machine, weekly
/// review, category dashboard, status readiness, the activity heatmap + account
/// rows, and the local-insight receipt). On a narrow window the two columns stack.
///
/// **Drill-ins deep-link, they don't open a third column** (IA §3.1, §5.1): the
/// 2-column dashboard has no inspector, so selecting an account routes to the
/// **Accounts** destination via `\.openRoute` rather than opening a local
/// inspector pane. With the window-first flag OFF the route handler is a no-op, so
/// this view is never instantiated and the popover is byte-identical.
///
/// **Privacy Mask / App Lock:** the shell already paints the full
/// ``AppLockedGateView`` over the whole window while content is *locked* (ADR-001
/// Epic 10 / AND-588), so this canvas never double-gates; it only honors Privacy
/// *Mask* the same way the re-hosted subviews already do (they read
/// `AppState.shouldMaskFinancialValues`), so masked values stay dotted and are
/// never leaked here.
///
/// **Empty / loading / error states** match the popover: the re-hosted cards each
/// carry their own loading redaction and empty copy, the overview block shows the
/// shared fallback banner before setup completes, and a sync error surfaces in the
/// inline ``DashboardErrorBanner`` at the top of the overview column — the same
/// signals the popover renders.
///
/// **Flag-OFF inert:** reached only when the window-first `Window` opens
/// (`WindowFirstFeatureFlag` ON). This file is never instantiated in the
/// flag-OFF popover build.
struct DashboardDestinationView: View {
    @Environment(AppState.self) private var appState
    @Environment(\.openSettings) private var openSettings
    @Environment(\.openRoute) private var openRoute

    /// Below this content width the two columns stack into one (a narrow window),
    /// matching the popover's behavior of dropping the side rail when space is
    /// tight. Tuned to the same ballpark as the popover's three-column floor.
    private let twoColumnBreakpoint: CGFloat = 760

    var body: some View {
        GeometryReader { proxy in
            let isWide = proxy.size.width >= twoColumnBreakpoint

            ScrollView {
                Group {
                    if isWide {
                        HStack(alignment: .top, spacing: Spacing.lg) {
                            summaryColumn
                                .frame(width: PopoverGeometry.railWidth, alignment: .topLeading)

                            overviewColumn
                                .frame(maxWidth: .infinity, alignment: .topLeading)
                        }
                    } else {
                        VStack(alignment: .leading, spacing: Spacing.lg) {
                            summaryColumn
                            overviewColumn
                        }
                    }
                }
                .padding(Spacing.lg)
                .frame(maxWidth: .infinity, alignment: .topLeading)
            }
            .scrollContentBackground(.hidden)
        }
        .navigationTitle(RouteDestination.dashboard.title)
        .accessibilityElement(children: .contain)
        .task { await appState.loadInitialData() }
    }

    // MARK: - Summary column

    /// The left **Summary** column: the existing ``WealthSummaryFlyout`` the
    /// popover mounts as its rail (net-worth hero, balance mix, 30-day cashflow),
    /// re-hosted unchanged. Its "Add account" / "Recurring" / "Income flow"
    /// affordances deep-link to the relevant destinations so the 2-column canvas
    /// never needs a local inspector.
    private var summaryColumn: some View {
        WealthSummaryFlyout(
            onAddAccount: { openRoute(.accounts()) },
            onOpenSubscriptions: { openRoute(.planning(section: .recurring)) },
            onOpenFlow: { openRoute(.planning(section: .incomeFlow)) }
        )
        .leftPanelSurface()
        .accessibilityElement(children: .contain)
    }

    // MARK: - Overview column

    /// The right **Overview** column: the same center-column stack the popover
    /// renders, top to bottom, each item an existing reusable subview driven by
    /// the same `AppState` + Core. Order and content mirror ``MainPopover``'s
    /// `dashboardColumn` so the two surfaces stay in lockstep.
    private var overviewColumn: some View {
        VStack(alignment: .leading, spacing: Spacing.lg) {
            if let error = appState.error {
                DashboardErrorBanner(error: error) { appState.error = nil }
            }

            BalanceTimeMachineView()

            WeeklyReviewCard()

            CategoryDashboardCard()

            if let presentation = appState.firstRunSnapshotPresentation {
                FirstRunSnapshotView(
                    presentation: presentation,
                    onDismiss: appState.dismissFirstRunSnapshot
                )
            }

            if shouldShowStatusReadiness {
                statusReadinessCluster
            }

            // The activity heatmap + filter bar + account rows — the overview's
            // core instrument. Account drill-ins deep-link to Accounts (no local
            // inspector on a 2-column canvas).
            DashboardOverviewColumn(onSelectAccount: { account in
                openRoute(.accounts(itemID: account.itemId))
            })

            DashboardLocalInsightCard()
        }
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Dashboard overview")
    }

    /// The status-readiness cluster (connection health + attention queue +
    /// readiness panel) is shown when setup is incomplete or the readiness verdict
    /// needs attention — the same gate the popover uses to elevate it. A healthy,
    /// fully-set-up dashboard keeps it quiet.
    private var shouldShowStatusReadiness: Bool {
        let level = appState.dashboardStatusReadiness.level
        return !appState.isSetupComplete || level == .warning || level == .blocked
    }

    private var statusReadinessCluster: some View {
        VStack(alignment: .leading, spacing: Spacing.sm) {
            ConnectionHealthStripView()

            AttentionQueueView(title: "Attention", onAddAccount: { openRoute(.accounts()) })

            DashboardReadinessPanel(
                openSettings: { openSettings() },
                onAddAccount: { openRoute(.accounts()) }
            )
        }
        .accessibilityElement(children: .contain)
    }
}

#Preview {
    DashboardDestinationView()
        .environment(AppState())
}
