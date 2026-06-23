import PlaidBarCore
import SwiftUI

/// **Planning** destination — window-first composed 2-column canvas (AND-624,
/// Epic 5 / AND-583; `[⌘4]`).
///
/// Redesigned to match the **Dashboard reference** desktop language
/// (``WindowMetrics`` / ``WindowTypography``): a **hero metrics row** of the
/// headline forward-looking figures, then a **two-column card grid** (≤3 cards per
/// column) under `title2` region banners — not the popover's tight single-column
/// stack. It re-*hosts* the data the popover already computes in a desk-distance
/// layout; **no new aggregation lives here** — every figure comes from an existing
/// Core engine, so this canvas can never disagree with the popover or the other
/// destinations:
///
/// - **Safe to spend** — the hero figure, plus an explainable breakdown via
///   `SafeToSpendCard` over `SafeToSpendCalculator.compute` (the exact Core
///   computation the popover uses). Recomputes from live `transactions` /
///   `recurringTransactions` / cashflow, so it updates on every edit.
/// - **Cashflow projection** — the prominent left-column hero card,
///   `ProjectedBalanceChart` over `ProjectedBalancePresentation.evaluate`;
///   self-hides until there is enough recorded balance history to anchor a line.
/// - **Upcoming recurring** — `RecurringObligationsSection` (re-hosting the same
///   read-only `RecurringObligationsPresentation` the flyout shows). The "open"
///   affordance is omitted here — this *is* the recurring surface.
/// - **Goals** — a read-only contribution overview (AND-606) over ``GoalsSummary``
///   of the live ``GoalsStore`` goals, so it can never disagree with the Goals
///   destination's numbers. Self-shows its empty state when no goals exist.
///
/// **Charts stay solid**: the projection chart and figures back
/// onto the quiet ``WindowSection`` surface, never a translucent wash. Confidence
/// / pressure cues ride on text + SF Symbol, never color alone (ACCESSIBILITY.md —
/// the reused cards already enforce this). Every value runs through
/// `PrivacyMaskPresentation`, so masked figures stay dotted and are never leaked.
///
/// **Flag-OFF inert:** reached only when `AppShellView` mounts (behind
/// `WindowFirstFeatureFlag`, default OFF), so the flag-off popover is
/// byte-identical and this view is never instantiated there.
struct PlanningDestinationView: View {
    @Environment(AppState.self) private var appState
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    /// The wealth summary supplies the cashflow window the safe-to-spend card needs;
    /// built from the same inputs the flyout uses so the number matches everywhere.
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

    private var isMasked: Bool { appState.shouldMaskFinancialValues }

    var body: some View {
        GeometryReader { proxy in
            let isWide = proxy.size.width >= WindowMetrics.twoColumnBreakpoint

            ScrollView {
                VStack(alignment: .leading, spacing: WindowMetrics.xl) {
                    heroMetricsRow

                    if isWide {
                        HStack(alignment: .top, spacing: WindowMetrics.columnGap) {
                            cashflowColumn
                                .frame(maxWidth: .infinity, alignment: .topLeading)
                            commitmentsColumn
                                .frame(maxWidth: .infinity, alignment: .topLeading)
                        }
                    } else {
                        VStack(alignment: .leading, spacing: WindowMetrics.xl) {
                            cashflowColumn
                            commitmentsColumn
                        }
                    }
                }
                .padding(WindowMetrics.canvasMargin)
                .frame(maxWidth: .infinity, alignment: .topLeading)
            }
            .scrollContentBackground(.hidden)
        }
        .navigationTitle(RouteDestination.planning.title)
        .accessibilityElement(children: .contain)
        .task {
            await appState.loadInitialData()
            await appState.goalsStore.loadIfNeeded()
        }
    }

    // MARK: - Hero metrics row

    /// The headline forward-looking figures across the top of the canvas — safe to
    /// spend, the projected month-end / low balance, and what's committed monthly —
    /// as large tabular figures. Reflows to wrap on a narrow window so each figure
    /// keeps its tabular legibility (``WindowMetrics`` `heroTileMinWidth`). Every
    /// value runs through `PrivacyMaskPresentation`; none rely on color for meaning
    /// (the label names the figure, a glyph reinforces it).
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
        .accessibilityLabel("Planning headline metrics")
    }

    // MARK: - Columns

    /// The left/primary **Cashflow** column — the forward look at the balance:
    /// 1. the **projected balance** chart, given the prominent hero card at the top
    ///    (the column's signature instrument); it self-hides until there is enough
    ///    recorded history, falling back to a quiet "building forecast" card so the
    ///    grid keeps a uniform card rather than a hole;
    /// 2. the **safe-to-spend breakdown** — the explainable, signed reconciliation
    ///    behind the hero figure.
    private var cashflowColumn: some View {
        VStack(alignment: .leading, spacing: WindowMetrics.lg) {
            columnHeader("Cashflow", systemImage: "chart.xyaxis.line")

            projectedBalanceCard

            safeToSpendBreakdownCard
        }
        .accessibilityElement(children: .contain)
    }

    /// The right/secondary **Commitments** column — what's already spoken for and
    /// what you're saving toward:
    /// 1. **upcoming recurring** obligations (re-hosted from the popover);
    /// 2. the **goals** contribution overview.
    private var commitmentsColumn: some View {
        VStack(alignment: .leading, spacing: WindowMetrics.lg) {
            columnHeader("Commitments", systemImage: "calendar.badge.clock")

            recurringCard

            goalsCard
        }
        .accessibilityElement(children: .contain)
    }

    /// A window-scale **column** region header (`title2` via ``WindowSectionTitle``)
    /// — one step up from a card's `title3` title, so the column reads as a region
    /// grouping its cards rather than nesting a card in a card.
    private func columnHeader(_ title: String, systemImage: String) -> some View {
        Label {
            Text(title).windowSectionTitle()
        } icon: {
            Image(systemName: systemImage).foregroundStyle(.secondary)
        }
        .labelStyle(.titleAndIcon)
        .accessibilityAddTraits(.isHeader)
    }

    // MARK: - Projected balance card

    /// The forward cashflow projection (AND-498), hosted as the column's prominent
    /// hero card. Charts stay solid: the chart backs onto the quiet
    /// ``WindowSection`` surface, never glass. While Privacy Mask is on the forecast
    /// is withheld (it would otherwise reveal the balance trajectory); while history
    /// is too thin it shows a quiet "building forecast" line so the grid keeps a
    /// uniform card rather than a hole.
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

    // MARK: - Safe-to-spend breakdown card

    /// The explainable, signed safe-to-spend reconciliation behind the hero figure
    /// — `SafeToSpendCard` re-hosted from the popover. It self-cards (its own glass
    /// chrome at popover scale), so like the Dashboard's re-hosted cards it is
    /// mounted directly under the column banner rather than re-wrapped (no
    /// card-in-card). The hero tile already carries the big figure; this card adds
    /// the "why".
    private var safeToSpendBreakdownCard: some View {
        SafeToSpendCard(
            result: safeToSpendResult,
            lastUpdatedRelative: appState.lastSyncRelative,
            privacyMaskEnabled: isMasked
        )
        .loadingRedaction(appState.loadState(for: .summaryCards))
    }

    // MARK: - Recurring obligations card

    /// Upcoming recurring obligations (AND-400), read-only. Re-hosts the popover's
    /// self-carding ``RecurringObligationsSection`` directly under the column banner
    /// (no card-in-card), exactly as the Dashboard does. The "open" affordance is
    /// dropped (`onOpenSubscriptions: nil`) because this *is* the recurring surface.
    /// When nothing is detected it shows the shared contextual, actionable empty
    /// state (the same ``SecondaryContentUnavailableState`` recurring engine +
    /// action dispatch the Dashboard uses, sourced from `AppState`) in a uniform
    /// ``WindowSection`` card rather than self-hiding, so the grid keeps an even
    /// rhythm and both surfaces match.
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
                privacyMaskEnabled: isMasked
            )
            .loadingRedaction(appState.loadState(for: .recurring))
        }
    }

    // MARK: - Goals contribution overview (AND-606)

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
            if summary.isEmpty {
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
                Label(summary.goalCountLabel, systemImage: "flag")
                    .windowSupportingText()
                if summary.fundedCount > 0 {
                    Label("\(summary.fundedCount) funded", systemImage: "checkmark.seal")
                        .windowSupportingText()
                }
                if summary.behindCount > 0 {
                    Label("\(summary.behindCount) behind", systemImage: "exclamationmark.triangle")
                        .windowSupportingText()
                }
            }
        }
    }

    private func goalsAccessibilityLabel(_ summary: GoalsSummary) -> String {
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

    // MARK: - Hero metric data (surface-only; reuses Core engines)

    /// One headline figure for the hero row. Pure presentation data derived from
    /// the same Core engines the rail / popover use — no new model logic.
    private struct PlanningHeroMetric: Identifiable {
        let id: String
        let label: String
        let value: String
        let systemImage: String
        let detail: String?
        let accent: Color
    }

    /// The safe-to-spend result — the exact Core computation behind both the hero
    /// figure and the breakdown card, computed once per body pass.
    private var safeToSpendResult: SafeToSpendResult {
        SafeToSpendCalculator.compute(
            accounts: appState.accounts,
            recurringTransactions: appState.recurringTransactions,
            cashflow: wealthPresentation.cashflow,
            asOf: Date()
        )
    }

    private var heroMetrics: [PlanningHeroMetric] {
        let masked = isMasked
        let safe = safeToSpendResult

        let safeTile = PlanningHeroMetric(
            id: "safeToSpend",
            label: "Safe to spend",
            value: PrivacyMaskPresentation.currency(safe.amount, format: .compact, isEnabled: masked),
            systemImage: safe.confidence.iconName,
            detail: "Through \(Formatters.displayDate(safe.horizonEnd)) · \(safe.confidence.label)",
            accent: safe.amount >= 0 ? SemanticColors.positive : SemanticColors.warning
        )

        var tiles = [safeTile]

        // Projected month-end balance — only when there is enough history.
        let projection = ProjectedBalancePresentation.evaluate(
            history: appState.balanceHistory,
            recurring: appState.recurringTransactions,
            now: Date()
        )
        if case let .available(balanceProjection) = projection {
            tiles.append(
                PlanningHeroMetric(
                    id: "projectedEnd",
                    label: "Projected balance",
                    value: PrivacyMaskPresentation.currency(balanceProjection.endBalance, format: .compact, isEnabled: masked),
                    systemImage: "calendar.badge.clock",
                    detail: "Low \(PrivacyMaskPresentation.currency(balanceProjection.projectedLow.balance, format: .compact, isEnabled: masked)) on \(Formatters.displayDate(balanceProjection.projectedLow.date))",
                    accent: SemanticColors.brand
                )
            )
        }

        // Committed monthly recurring.
        let recurring = RecurringObligationsPresentation.make(
            from: appState.recurringTransactions,
            asOf: Date()
        )
        if !recurring.isEmpty {
            tiles.append(
                PlanningHeroMetric(
                    id: "recurringMonthly",
                    label: "Committed monthly",
                    value: PrivacyMaskPresentation.currency(recurring.estimatedMonthlyTotal, format: .compact, isEnabled: masked),
                    systemImage: "repeat",
                    detail: recurringDetail(recurring, privacyMaskEnabled: masked),
                    accent: .secondary
                )
            )
        }

        return tiles
    }

    private func recurringDetail(
        _ recurring: RecurringObligationsPresentation,
        privacyMaskEnabled: Bool
    ) -> String {
        recurring.detailLine(privacyMaskEnabled: privacyMaskEnabled)
    }
}

#Preview {
    PlanningDestinationView()
        .environment(AppState())
}
