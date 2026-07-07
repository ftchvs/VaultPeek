import PlaidBarCore
import SwiftUI

/// **Insights** destination — a window-first **composed 2-column canvas** (AND-624,
/// matching the Dashboard reference; `[⌘6]`), Epic 7 / AND-585.
///
/// This re-*hosts* the Insights data — the on-device Foundation Models summary, the
/// weekly review, the trend charts, and (since 2026-07-02, the Planning fold —
/// Gate-0, AND-979) the forward-looking cashflow/commitments cards — in a
/// desk-distance desktop layout rather than re-using the popover's compact stack.
/// It reads the *same* `AppState` + `PlaidBarCore` engines as the popover and the
/// menu-bar surfaces, so the two can never diverge; **no model or chart logic
/// lives here** (surface only).
///
/// Layout (desk-distance, ``WindowMetrics`` / ``WindowTypography`` — "comfortable
/// density", a calm canvas of a few generous cards):
/// 1. a **hero**: the streaming FM spending-insight headline + the on-device
///    ``LocalAIInsightReceipt`` (tier + provenance + consent), surfaced via
///    ``InsightsAIInsightView`` as a prominent full-width hero card. AI is **off by
///    default with a visible toggle** (AND-564); availability is detected with a
///    graceful NaturalLanguage / deterministic fallback (AND-563);
/// 2. a **two-column card grid** below it under a `title2` column banner each:
///    - left **Trends** column — the net-worth trend, the spend donut, and the
///      activity heatmap, each its own ``WindowSection`` chart card
///      (``InsightsTrendsView``). Every chart ships its ``ChartAudioGraph`` audio
///      graph (AND-569) + a `reduceTransparency` / Privacy Mask text alternative;
///      **Liquid Glass never touches a chart** and no meaning rides on color alone
///      (ACCESSIBILITY.md);
///    - right **Planning & Review** column — the forward look, folded in from the
///      retired Planning destination: the projected-balance forecast, the
///      explainable Safe-to-Spend breakdown, upcoming recurring obligations, and
///      the goals contribution overview — then the existing ``WeeklyReviewCard``
///      re-hosted unchanged, so this surface and the popover drive the same
///      review state. This column intentionally runs longer than the app's usual
///      "≤3 cards" convention (5 cards) rather than introducing an unprecedented
///      third content column — every card is still a self-contained
///      ``WindowSection``, so the cost is a longer scroll, not new structure.
///      Deliberately does **not** duplicate Dashboard's headline hero metrics
///      (Net Worth / Safe-to-Spend / 30-day spend) or its Recurring/Goals glance
///      cards — those already live there; this column's job is the *why* and the
///      *forecast* behind them, not repeating the same figures a third time
///      (the redundancy AND-727 flags).
///   On a narrow window the two columns stack.
///
/// **Privacy Mask / App Lock:** the shell paints the full lock gate over the whole
/// window while *locked* (Epic 10), so this canvas never double-gates; it
/// honors Privacy *Mask* the way the re-hosted subviews do (figures run through
/// `PrivacyMaskPresentation` / `shouldMaskFinancialValues`), so masked figures stay
/// hidden and are never leaked here.
///
/// **Flag-OFF inert:** reached only when the window-first `Window` opens
/// (`WindowFirstFeatureFlag` ON). With the flag off the popover is byte-identical —
/// this file is never instantiated.
struct InsightsDestinationView: View {
    @Environment(AppState.self) private var appState

    private var isMasked: Bool { appState.shouldMaskFinancialValues }

    var body: some View {
        GeometryReader { proxy in
            let isWide = proxy.size.width >= WindowMetrics.twoColumnBreakpoint

            ScrollView {
                VStack(alignment: .leading, spacing: WindowMetrics.xl) {
                    // Hero — the on-device spending insight + receipt, given the
                    // full canvas width so it reads as the destination's headline
                    // instrument (like the Dashboard's heatmap hero).
                    InsightsAIInsightView()

                    if isWide {
                        HStack(alignment: .top, spacing: WindowMetrics.columnGap) {
                            trendsColumn
                                .frame(maxWidth: .infinity, alignment: .topLeading)
                            planningAndReviewColumn
                                .frame(maxWidth: .infinity, alignment: .topLeading)
                        }
                    } else {
                        VStack(alignment: .leading, spacing: WindowMetrics.xl) {
                            trendsColumn
                            planningAndReviewColumn
                        }
                    }
                }
                .padding(WindowMetrics.canvasMargin)
                .frame(maxWidth: .infinity, alignment: .topLeading)
            }
            .scrollContentBackground(.hidden)
        }
        .navigationTitle(RouteDestination.insights.title)
        .accessibilityElement(children: .contain)
        .task {
            await appState.loadInitialData()
            await appState.goalsStore.loadIfNeeded()
        }
    }

    // MARK: - Columns

    /// The left/primary **Trends** column — the three trend chart cards (net-worth
    /// trend, spend donut, activity heatmap). Each self-cards as a ``WindowSection``
    /// inside ``InsightsTrendsView``; the column banner above them is a `title2`
    /// region header. Charts stay solid (never glass) and re-host the same Core
    /// engines as the popover.
    private var trendsColumn: some View {
        VStack(alignment: .leading, spacing: WindowMetrics.lg) {
            columnHeader("Trends", systemImage: "chart.xyaxis.line")
            InsightsTrendsView()
        }
        .accessibilityElement(children: .contain)
    }

    /// The right/secondary **Planning & Review** column — the forward look folded
    /// in from Planning (projected balance, safe-to-spend breakdown, recurring,
    /// goals), then the weekly review. See the type doc for why this column runs
    /// longer than the app's usual card-count convention.
    private var planningAndReviewColumn: some View {
        VStack(alignment: .leading, spacing: WindowMetrics.lg) {
            columnHeader("Planning & Review", systemImage: "calendar.badge.checkmark")
            projectedBalanceCard
            safeToSpendBreakdownCard
            recurringCard
            goalsCard
            WeeklyReviewCard()
        }
        .accessibilityElement(children: .contain)
    }

    /// A window-scale **column** region header (`title2` via ``WindowSectionTitle``)
    /// — one step up from a card's `title3` title, so the column reads as a region
    /// grouping its cards. A heading, not a card, so it sits cleanly above the
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

    // MARK: - Projected balance card (folded from Planning)

    /// The forward cashflow projection (AND-498), hosted as a card in the
    /// Planning & Review column. Charts stay solid: the chart backs onto the
    /// quiet ``WindowSection`` surface, never glass. While Privacy Mask is on the
    /// forecast is withheld (it would otherwise reveal the balance trajectory);
    /// while history is too thin it shows a quiet "building forecast" line so the
    /// column keeps a uniform card rather than a hole.
    @ViewBuilder
    private var projectedBalanceCard: some View {
        let projection = ProjectedBalancePresentation.evaluate(
            history: appState.balanceHistory,
            recurring: appState.recurringTransactions,
            now: Date()
        )
        WindowSection("Projected balance", systemImage: "chart.xyaxis.line") {
            if case let .available(balanceProjection) = projection, !isMasked {
                Text(projectedLowDetail(balanceProjection))
                    .windowSupportingText()
                    .monospacedDigit()
            }
        } content: {
            switch projection {
            case let .available(balanceProjection):
                if isMasked {
                    maskedForecastNotice
                } else {
                    ProjectedBalanceChart(projection: balanceProjection)
                        .frame(minHeight: WindowMetrics.heatmapHeroMinHeight)
                }
            case .insufficientHistory:
                Label(
                    "Building your forecast — a projected line appears once VaultPeek has recorded a little balance history.",
                    systemImage: "hourglass"
                )
                .windowBodyText()
                .foregroundStyle(.secondary)
                .frame(maxWidth: .infinity, minHeight: WindowMetrics.heatmapHeroMinHeight, alignment: .leading)
            }
        }
        .loadingRedaction(appState.loadState(for: .summaryCards))
    }

    private var maskedForecastNotice: some View {
        Label("Forecast hidden while VaultPeek is private", systemImage: "eye.slash")
            .windowBodyText()
            .foregroundStyle(.secondary)
            .frame(maxWidth: .infinity, minHeight: WindowMetrics.heatmapHeroMinHeight, alignment: .leading)
    }

    private func projectedLowDetail(_ projection: BalanceProjection) -> String {
        "Projected low \(Formatters.currency(projection.projectedLow.balance, format: .compact)) on \(Formatters.displayDate(projection.projectedLow.date))"
    }

    // MARK: - Safe-to-spend breakdown card (folded from Planning)

    /// The wealth summary supplies the cashflow window the safe-to-spend
    /// breakdown needs; built from the same inputs the popover/Dashboard use so
    /// the number matches everywhere.
    private var wealthPresentation: WealthSummaryPresentation {
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

    /// The safe-to-spend result — the exact Core computation behind Dashboard's
    /// hero figure, computed once per body pass for the breakdown card below.
    private var safeToSpendResult: SafeToSpendResult {
        SafeToSpendCalculator.compute(
            accounts: appState.accounts,
            recurringTransactions: appState.recurringTransactions,
            cashflow: wealthPresentation.cashflow,
            asOf: Date()
        )
    }

    /// The explainable, signed safe-to-spend reconciliation behind Dashboard's
    /// hero figure — `SafeToSpendCard` re-hosted from the popover. It self-cards
    /// (its own glass chrome at popover scale), so like the other re-hosted cards
    /// it is mounted directly under the column banner rather than re-wrapped (no
    /// card-in-card). Dashboard's hero tile carries the big figure; this card
    /// adds the "why".
    private var safeToSpendBreakdownCard: some View {
        SafeToSpendCard(
            result: safeToSpendResult,
            lastUpdatedRelative: appState.lastSyncRelative,
            privacyMaskEnabled: isMasked
        )
        .loadingRedaction(appState.loadState(for: .summaryCards))
    }

    // MARK: - Recurring obligations card (folded from Planning)

    /// Upcoming recurring obligations (AND-400), read-only. Re-hosts the
    /// popover's self-carding ``RecurringObligationsSection`` directly under the
    /// column banner (no card-in-card), exactly as Planning did. The "open"
    /// affordance is dropped (`onOpenSubscriptions: nil`) — this card, not a
    /// separate destination, is now the recurring detail surface Dashboard's
    /// "open" chevron lands on. When nothing is detected it shows the shared
    /// contextual, actionable empty state in a uniform ``WindowSection`` card
    /// rather than self-hiding, so the column keeps an even rhythm.
    @ViewBuilder
    private var recurringCard: some View {
        let presentation = RecurringObligationsPresentation.make(
            from: appState.recurringTransactions,
            asOf: Date()
        )
        if presentation.isEmpty {
            WindowSection("Recurring", systemImage: "repeat") {
                EmptyView()
            } content: {
                SecondaryUnavailableView(presentation: appState.recurringUnavailableState) {
                    appState.performRecurringUnavailableAction(appState.recurringUnavailableState.action)
                }
            }
            .accessibilityElement(children: .contain)
        } else {
            RecurringObligationsSection(
                presentation: presentation,
                onOpenSubscriptions: nil,
                privacyMaskEnabled: isMasked,
                scale: .window
            )
            .loadingRedaction(appState.loadState(for: .recurring))
        }
    }

    // MARK: - Goals contribution overview (folded from Planning, AND-606)

    /// The read-only goals contribution overview, hosted in a window-scale
    /// ``WindowSection`` with a `title3` header and an "Open Goals" accessory that
    /// switches to the Goals workspace. Figures are window `.body`+ and tabular;
    /// progress is carried by the percent text and counts, never color alone.
    private var goalsCard: some View {
        let summary = GoalsSummary.make(from: appState.goalsStore.goals)
        return WindowSection("Goals", systemImage: RouteDestination.goals.systemImage) {
            Button("Open Goals") {
                appState.navigationModel.go(to: .goals)
            }
            .buttonStyle(.link)
            .accessibilityHint("Switches to the Goals workspace.")
        } content: {
            if isMasked {
                ContentUnavailableView {
                    Label("Goal details hidden", systemImage: "lock.fill")
                } description: {
                    Text("VaultPeek is private. Open Goals after unlocking to review goal details.")
                }
                .frame(maxWidth: .infinity, minHeight: 140)
            } else if summary.isEmpty {
                ContentUnavailableView {
                    Label("No goals yet", systemImage: "flag.checkered")
                } description: {
                    Text("Set targets and track contributions in the Goals workspace.")
                }
                .frame(maxWidth: .infinity, minHeight: 140)
            } else {
                goalsOverview(summary)
            }
        }
        .accessibilityLabel(goalsAccessibilityLabel(summary))
    }

    private func goalsOverview(_ summary: GoalsSummary) -> some View {
        VStack(alignment: .leading, spacing: WindowMetrics.sm) {
            if isMasked {
                ProgressView()
                    .progressViewStyle(.linear)
                    .tint(.secondary)
                    .accessibilityHidden(true)
            } else {
                ProgressView(value: summary.overallFraction)
                    .progressViewStyle(.linear)
                    .tint(SemanticColors.brand)
                    .accessibilityHidden(true)
            }

            HStack(alignment: .firstTextBaseline) {
                Text("\(goalsPercent(summary.overallPercent)) of total")
                    .windowDataText()
                Spacer(minLength: WindowMetrics.sm)
                Text("\(goalsCurrency(summary.totalSaved)) of \(goalsCurrency(summary.totalTarget))")
                    .windowSupportingText()
                    .monospacedDigit()
            }

            HStack(spacing: WindowMetrics.md) {
                Label(goalsSecondaryLabel(summary), systemImage: "flag")
                    .windowSupportingText()
                if !isMasked, summary.fundedCount > 0 {
                    Label("\(summary.fundedCount) funded", systemImage: "checkmark.seal")
                        .windowSupportingText()
                }
                if !isMasked, summary.behindCount > 0 {
                    Label("\(summary.behindCount) behind", systemImage: "exclamationmark.triangle")
                        .windowSupportingText()
                }
            }
        }
    }

    private func goalsSecondaryLabel(_ summary: GoalsSummary) -> String {
        isMasked ? "Goal details hidden" : summary.goalCountLabel
    }

    private func goalsAccessibilityLabel(_ summary: GoalsSummary) -> String {
        if isMasked { return "Goals: details hidden while VaultPeek is private." }
        guard !summary.isEmpty else { return "Goals: no goals yet." }
        var parts = ["Goals: \(goalsPercent(summary.overallPercent)) of total saved across \(summary.goalCountLabel)"]
        if summary.fundedCount > 0 { parts.append("\(summary.fundedCount) funded") }
        if summary.behindCount > 0 { parts.append("\(summary.behindCount) behind") }
        return parts.joined(separator: ". ")
    }

    private func goalsCurrency(_ amount: Double) -> String {
        PrivacyMaskPresentation.currency(amount, format: .full, isEnabled: isMasked, style: .compact)
    }

    private func goalsPercent(_ value: Int) -> String {
        PrivacyMaskPresentation.percent(Double(value), decimals: 0, isEnabled: isMasked)
    }
}

#if canImport(PreviewsMacros)
#Preview {
    InsightsDestinationView()
        .environment(AppState())
}
#endif
