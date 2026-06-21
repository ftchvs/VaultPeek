import PlaidBarCore
import SwiftUI

/// **Dashboard** destination — the window-first *reference* surface (AND-624,
/// building on AND-622; ADR-001 window-first workspace, IA §3.1/§5.1, `[⌘1]`).
///
/// This is the design exemplar that sets the bar for the propagation pass across
/// the other destinations: a **composed 2-column canvas that uses the window's
/// width** rather than a re-hosted popover rail. It reads from the *same*
/// `AppState` + `PlaidBarCore` presentation engines the menu-bar popover and the
/// detached desktop window use — **no model or chart logic lives here** (surface
/// only) — but it re-*hosts the data in a desktop layout*, it does not clone the
/// popover's compact arrangement. The data can never diverge from the popover
/// because both read the same Core; only the layout differs.
///
/// Layout (desk-distance, ``WindowMetrics`` / ``WindowTypography``) — tuned for
/// "comfortable density" (AND-624): a calm, spacious canvas of a few generous
/// cards per column rather than a tight stack of small ones.
/// 1. a **hero metrics row** — net worth, safe-to-spend, and last-30-day spend as
///    large tabular figures with labels (the dashboard's headline numbers,
///    surfaced from `WealthSummaryPresentation` + `SafeToSpendCalculator`, the
///    same engines the rail/weekly-review use);
/// 2. a **two-column card grid** below it, **at most three cards per column** under
///    a `title2` column banner:
///    - left **Activity** column — the year-scale activity **heatmap hero** (the
///      signature instrument, a prominent near-full-width card at the top), the
///      consolidated **Accounts** card (filter segments + account rows + the "what
///      the bank said" balances merged into one card), and either the
///      **status-readiness** group (while setup needs attention) or the **weekly
///      review** card;
///    - right **Money & insights** column — recurring obligations, the category
///      dashboard, and the local-insight teaser.
///    Each card self-cards (a ``WindowSection`` or its own chrome) with a `title3`
///    header. On a narrow window the two columns stack.
///
/// **Drill-ins deep-link, they don't open a third column** (IA §3.1, §5.1): the
/// 2-column dashboard has no inspector, so selecting an account routes to the
/// **Accounts** destination via `\.openRoute`. With the window-first flag OFF the
/// route handler is a no-op and this view is never instantiated, so the popover
/// stays byte-identical.
///
/// **Privacy Mask / App Lock:** the shell paints the full ``AppLockedGateView``
/// over the whole window while content is *locked* (ADR-001 Epic 10 / AND-588),
/// so this canvas never double-gates; it only honors Privacy *Mask* the way the
/// re-hosted subviews and the hero figures do (every value runs through
/// `PrivacyMaskPresentation` / `shouldMaskFinancialValues`), so masked figures
/// stay dotted and are never leaked here.
///
/// **Empty / loading / error states** match the popover: the re-hosted cards each
/// carry their own loading redaction and empty copy, the overview block shows the
/// shared fallback banner before setup completes, the hero tiles read as
/// dashes/“Private” before data lands, and a sync error surfaces in the inline
/// ``DashboardErrorBanner`` at the top of the canvas.
///
/// **Flag-OFF inert:** reached only when the window-first `Window` opens
/// (`WindowFirstFeatureFlag` ON). Never instantiated in the flag-OFF popover build.
struct DashboardDestinationView: View {
    @Environment(AppState.self) private var appState
    @Environment(\.openSettings) private var openSettings
    @Environment(\.openRoute) private var openRoute
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        GeometryReader { proxy in
            let isWide = proxy.size.width >= WindowMetrics.twoColumnBreakpoint

            ScrollView {
                VStack(alignment: .leading, spacing: WindowMetrics.xl) {
                    if let error = appState.error {
                        DashboardErrorBanner(error: error) { appState.error = nil }
                    }

                    heroMetricsRow

                    if isWide {
                        HStack(alignment: .top, spacing: WindowMetrics.columnGap) {
                            primaryColumn
                                .frame(maxWidth: .infinity, alignment: .topLeading)
                            secondaryColumn
                                .frame(maxWidth: .infinity, alignment: .topLeading)
                        }
                    } else {
                        VStack(alignment: .leading, spacing: WindowMetrics.xl) {
                            primaryColumn
                            secondaryColumn
                        }
                    }
                }
                .padding(WindowMetrics.canvasMargin)
                .frame(maxWidth: .infinity, alignment: .topLeading)
            }
            .scrollContentBackground(.hidden)
        }
        .navigationTitle(RouteDestination.dashboard.title)
        .accessibilityElement(children: .contain)
        .task { await appState.loadInitialData() }
    }

    // MARK: - Hero metrics row

    /// The headline figures across the top of the canvas. Reflows to wrap on a
    /// narrow window so each figure keeps its tabular legibility (``WindowMetrics``
    /// `heroTileMinWidth`). Every value runs through `PrivacyMaskPresentation`, so
    /// masked figures show the dotted placeholder; none rely on color for meaning
    /// (the label names the figure).
    private var heroMetricsRow: some View {
        let metrics = heroMetrics
        return LazyVGrid(
            columns: [GridItem(.adaptive(minimum: WindowMetrics.heroTileMinWidth), spacing: WindowMetrics.lg)],
            alignment: .leading,
            spacing: WindowMetrics.lg
        ) {
            ForEach(metrics) { metric in
                WindowHeroMetricTile(
                    label: metric.label,
                    value: metric.value,
                    systemImage: metric.systemImage,
                    detail: metric.detail,
                    accent: metric.accent,
                    reduceMotion: reduceMotion
                )
            }
        }
        .loadingRedaction(appState.loadState(for: .summaryCards))
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Headline metrics")
    }

    // MARK: - Columns

    /// The left/primary **Activity** column — at most three generous cards so the
    /// column reads as calm, comfortable density rather than a tight stack of small
    /// cards (AND-624):
    /// 1. the year-scale activity **heatmap hero** (the signature instrument), given
    ///    a prominent near-full-column-width card at the top;
    /// 2. the consolidated **Accounts** card (filter segments + account rows + the
    ///    "what the bank said" bank-reported balances, all merged into one card);
    /// 3. the **status-readiness** card *when setup needs attention*, otherwise the
    ///    **weekly review** card — never both, so the column stays at three cards.
    ///
    /// Each card self-cards (it is a ``WindowSection`` or carries its own chrome);
    /// the column banner above them is a `title2` region header. The data is
    /// identical to the popover — these re-host the same Core engines.
    private var primaryColumn: some View {
        VStack(alignment: .leading, spacing: WindowMetrics.lg) {
            columnHeader("Activity", systemImage: "square.grid.3x3.fill")

            DashboardActivityHeatmapCard()

            DashboardOverviewColumn(onSelectAccount: { account in
                openRoute(.accounts(itemID: account.itemId))
            })

            if shouldShowStatusReadiness {
                statusReadinessCard
            } else {
                WeeklyReviewCard()
            }
        }
        .accessibilityElement(children: .contain)
    }

    /// The right/secondary **Money & insights** column — three cards: recurring
    /// obligations, the category dashboard, and the local-insight teaser (plus the
    /// first-run snapshot when present, which is transient). Each re-hosted card
    /// self-cards, so they are mounted directly under the column banner.
    private var secondaryColumn: some View {
        VStack(alignment: .leading, spacing: WindowMetrics.lg) {
            columnHeader("Money & insights", systemImage: "chart.pie")

            DashboardRecurringCard(onOpen: { openRoute(.planning(section: .recurring)) })

            CategoryDashboardCard(inWindow: true)

            if let presentation = appState.firstRunSnapshotPresentation {
                FirstRunSnapshotView(
                    presentation: presentation,
                    onDismiss: appState.dismissFirstRunSnapshot
                )
            }

            DashboardLocalInsightCard()
        }
        .accessibilityElement(children: .contain)
    }

    /// A window-scale **column** region header (`title2` via ``WindowSectionTitle``)
    /// — one step up from a card's `title3` title, so the column reads as a region
    /// grouping its cards. It is a heading, not a card, so it sits cleanly above the
    /// self-carding cards below without nesting a card in a card.
    private func columnHeader(_ title: String, systemImage: String) -> some View {
        Label {
            Text(title).windowSectionTitle()
        } icon: {
            Image(systemName: systemImage).foregroundStyle(.secondary)
        }
        .labelStyle(.titleAndIcon)
        .accessibilityAddTraits(.isHeader)
    }

    // MARK: - Status readiness

    /// The status-readiness cluster (connection health + attention queue +
    /// readiness panel) is shown when setup is incomplete or the readiness verdict
    /// needs attention — the same gate the popover uses to elevate it. A healthy,
    /// fully-set-up dashboard keeps it quiet.
    private var shouldShowStatusReadiness: Bool {
        let level = appState.dashboardStatusReadiness.level
        return !appState.isSetupComplete || level == .warning || level == .blocked
    }

    /// The status-readiness group: connection health + attention queue + the
    /// readiness panel under a single `title3` "Status" header. The three pieces
    /// each carry their own glass chrome (they are shared popover views), so they
    /// are grouped by a header + tight spacing rather than re-wrapped in another
    /// card — that would card-in-a-card. They occupy the column's third slot in
    /// place of the weekly review while setup needs attention. Tighter
    /// intra-group spacing (`sm`) reads them as one cluster, distinct from the
    /// `lg` gaps between the column's top-level cards.
    private var statusReadinessCard: some View {
        VStack(alignment: .leading, spacing: WindowMetrics.sm) {
            Label {
                Text("Status").windowCardTitle()
            } icon: {
                Image(systemName: "checklist").foregroundStyle(.secondary)
            }
            .labelStyle(.titleAndIcon)
            .accessibilityAddTraits(.isHeader)

            ConnectionHealthStripView()
            AttentionQueueView(title: "Attention", onAddAccount: { openRoute(.accounts()) })
            DashboardReadinessPanel(
                openSettings: { openSettings() },
                onAddAccount: { openRoute(.accounts()) }
            )
        }
        .accessibilityElement(children: .contain)
    }

    // MARK: - Hero metric data (surface-only; reuses Core engines)

    /// One headline figure for the hero row. Pure presentation data, derived from
    /// the same Core engines the rail/weekly-review use — no new model logic.
    private struct HeroMetric: Identifiable {
        let id: String
        let label: String
        let value: String
        let systemImage: String
        let detail: String?
        let accent: Color
    }

    /// The wealth summary the rail also computes — the single source for net worth,
    /// account count, and the 30-day cashflow used by the hero figures and the
    /// safe-to-spend input.
    private var wealthSummary: WealthSummaryPresentation {
        WealthSummaryPresentation.evaluate(
            accounts: appState.accounts,
            transactions: appState.transactions,
            isDemoMode: appState.usesDemoConnectionPresentation,
            serverConnected: appState.serverConnected,
            credentialsConfigured: appState.serverCredentialsConfigured,
            linkedItemCount: appState.statusItemCount,
            syncedItemCount: appState.serverSyncedItemCount ?? 0,
            itemStatuses: appState.itemStatuses,
            isSyncStale: appState.isSyncStale,
            lastSyncRelative: appState.lastSyncRelative,
            statusSyncText: appState.statusSyncText,
            errorMessage: appState.error,
            creditUtilizationThreshold: appState.creditUtilizationThreshold,
            lowCashThreshold: appState.lowBalanceThreshold,
            largeTransactionThreshold: appState.largeTransactionThreshold,
            balanceHistory: appState.balanceHistory
        )
    }

    private var heroMetrics: [HeroMetric] {
        let masked = appState.shouldMaskFinancialValues
        let summary = wealthSummary
        let safeToSpend = SafeToSpendCalculator.compute(
            accounts: appState.accounts,
            recurringTransactions: appState.recurringTransactions,
            cashflow: summary.cashflow,
            asOf: Date()
        )

        let netWorth = HeroMetric(
            id: "netWorth",
            label: "Net worth",
            value: PrivacyMaskPresentation.currency(summary.netWorth, format: .compact, isEnabled: masked),
            systemImage: "chart.line.uptrend.xyaxis",
            detail: accountCountDetail(summary.accountCount),
            accent: SemanticColors.brand
        )

        let safe = HeroMetric(
            id: "safeToSpend",
            label: "Safe to spend",
            value: PrivacyMaskPresentation.currency(safeToSpend.amount, format: .compact, isEnabled: masked),
            systemImage: safeToSpend.confidence.iconName,
            detail: "Through end of month · \(safeToSpend.confidence.label) confidence",
            accent: safeToSpend.amount >= 0 ? SemanticColors.positive : SemanticColors.warning
        )

        let spend = HeroMetric(
            id: "spend30",
            label: "Last 30-day spend",
            value: PrivacyMaskPresentation.currency(summary.cashflow.spending, format: .compact, isEnabled: masked),
            systemImage: "creditcard",
            detail: "Across \(summary.cashflow.transactionCount) transactions",
            accent: .secondary
        )

        return [netWorth, safe, spend]
    }

    private func accountCountDetail(_ count: Int) -> String {
        count == 1 ? "Across 1 account" : "Across \(count) accounts"
    }
}

#Preview {
    DashboardDestinationView()
        .environment(AppState())
}
