import PlaidBarCore
import SwiftUI

/// **Planning** destination (2-column — IA §3.1/§5.5, `[⌘4]`).
///
/// Epic 5 / AND-583 (ADR-001 window-first workspace). A composed analytical
/// canvas — no master list, so the shell renders only this content column (no
/// inspector). It stacks the forward-looking planning surfaces, every one driven
/// by an existing engine (no new aggregation here):
///
/// - **Safe to spend** — `SafeToSpendCard` over `SafeToSpendCalculator.compute`,
///   the exact Core computation the popover uses, so the two surfaces can never
///   disagree. It recomputes from live `transactions` / `recurringTransactions` /
///   cashflow, so it updates whenever a transaction is edited.
/// - **Cashflow projection** — `ProjectedBalanceChart` over
///   `ProjectedBalancePresentation.evaluate`; self-hides until there is enough
///   recorded balance history to anchor a line.
/// - **Upcoming recurring** — `RecurringObligationsSection` over
///   `RecurringObligationsPresentation.make`, the same read-only recurring
///   presentation the flyout shows; self-hides when nothing is detected.
/// - **Goals** — a read-only contribution overview (AND-606) over ``GoalsSummary``
///   of the live ``GoalsStore`` goals, so it can never disagree with the Goals
///   destination's numbers. Self-shows its empty state when no goals exist.
///
/// Confidence / pressure cues ride on text + SF Symbol, never color alone
/// (ACCESSIBILITY.md — the reused cards already enforce this). Window-first surface
/// only: reached solely when `AppShellView` mounts (behind `WindowFirstFeatureFlag`,
/// default OFF), so the flag-off popover is byte-identical.
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
        let presentation = wealthPresentation
        let privacyMaskEnabled = isMasked

        ScrollView {
            VStack(alignment: .leading, spacing: Spacing.lg) {
                header

                // Safe to spend — must match the Core computation (AND-401).
                SafeToSpendCard(
                    result: SafeToSpendCalculator.compute(
                        accounts: appState.accounts,
                        recurringTransactions: appState.recurringTransactions,
                        cashflow: presentation.cashflow,
                        asOf: Date()
                    ),
                    lastUpdatedRelative: appState.lastSyncRelative,
                    privacyMaskEnabled: privacyMaskEnabled
                )
                .loadingRedaction(appState.loadState(for: .summaryCards))

                // Forward cashflow projection (AND-498). Self-hides until there is
                // enough recorded balance history to anchor a line.
                cashflowProjectionSection(privacyMaskEnabled: privacyMaskEnabled)

                // Upcoming recurring obligations (AND-400), read-only. Self-hides
                // when no recurring series are detected.
                RecurringObligationsSection(
                    presentation: RecurringObligationsPresentation.make(
                        from: appState.recurringTransactions,
                        asOf: Date()
                    ),
                    privacyMaskEnabled: privacyMaskEnabled
                )
                .loadingRedaction(appState.loadState(for: .recurring))

                // Goals contributions — read-only overview over the live goals
                // (AND-606). Wired to `GoalsSummary` so it matches the Goals
                // destination; self-shows an empty state when no goals exist.
                goalsSummarySection(privacyMaskEnabled: privacyMaskEnabled)
            }
            .padding(Spacing.lg)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .scrollContentBackground(.hidden)
        .navigationTitle(RouteDestination.planning.title)
        .task { await appState.goalsStore.loadIfNeeded() }
        .accessibilityElement(children: .contain)
    }

    // MARK: - Header

    private var header: some View {
        VStack(alignment: .leading, spacing: Spacing.xxs) {
            Text("Planning")
                .font(.title2.weight(.bold))
            Text("Look ahead: what's safe to spend, where the balance is heading, and what's already committed.")
                .font(.subheadline)
                .foregroundStyle(.secondary)
        }
        .accessibilityElement(children: .combine)
    }

    // MARK: - Cashflow projection

    @ViewBuilder
    private func cashflowProjectionSection(privacyMaskEnabled: Bool) -> some View {
        let projection = ProjectedBalancePresentation.evaluate(
            history: appState.balanceHistory,
            recurring: appState.recurringTransactions,
            now: Date()
        )
        switch projection {
        case let .available(balanceProjection):
            VStack(alignment: .leading, spacing: Spacing.sm) {
                Label("Projected balance", systemImage: "chart.xyaxis.line")
                    .sectionTitle()
                    .foregroundStyle(.secondary)

                if privacyMaskEnabled {
                    Label("Forecast hidden while VaultPeek is private", systemImage: "eye.slash")
                        .detailText()
                        .foregroundStyle(.secondary)
                        .frame(maxWidth: .infinity, minHeight: 88, alignment: .leading)
                } else {
                    ProjectedBalanceChart(projection: balanceProjection)
                }
            }
            .padding(Spacing.md)
            .glassSurface(.raised)
            .loadingRedaction(appState.loadState(for: .summaryCards))
            .accessibilityElement(children: .contain)
        case .insufficientHistory:
            // Stay quiet until there is enough history — no empty placeholder.
            EmptyView()
        }
    }

    // MARK: - Goals contribution overview (AND-606)

    @ViewBuilder
    private func goalsSummarySection(privacyMaskEnabled: Bool) -> some View {
        let summary = GoalsSummary.make(from: appState.goalsStore.goals)
        VStack(alignment: .leading, spacing: Spacing.sm) {
            HStack(alignment: .firstTextBaseline) {
                Label("Goals", systemImage: RouteDestination.goals.systemImage)
                    .sectionTitle()
                    .foregroundStyle(.secondary)
                Spacer()
                Button("Open Goals") {
                    appState.navigationModel.go(to: .goals)
                }
                .buttonStyle(.link)
                .font(.caption)
                .accessibilityHint("Switches to the Goals workspace.")
            }

            if summary.isEmpty {
                ContentUnavailableView {
                    Label("No goals yet", systemImage: "flag.checkered")
                } description: {
                    Text("Set targets and track contributions in the Goals workspace.")
                }
                .frame(maxWidth: .infinity, minHeight: 140)
            } else {
                goalsOverview(summary, privacyMaskEnabled: privacyMaskEnabled)
            }
        }
        .padding(Spacing.md)
        .glassSurface(.raised)
        .accessibilityElement(children: .contain)
        .accessibilityLabel(goalsAccessibilityLabel(summary, privacyMaskEnabled: privacyMaskEnabled))
    }

    private func goalsOverview(_ summary: GoalsSummary, privacyMaskEnabled: Bool) -> some View {
        VStack(alignment: .leading, spacing: Spacing.sm) {
            ProgressView(value: summary.overallFraction)
                .progressViewStyle(.linear)
                .tint(SemanticColors.brand)
                .accessibilityHidden(true)

            HStack(alignment: .firstTextBaseline) {
                Text("\(summary.overallPercent)% of total")
                    .font(.callout.weight(.semibold))
                    .monospacedDigit()
                Spacer()
                Text("\(goalsCurrency(summary.totalSaved, masked: privacyMaskEnabled)) of \(goalsCurrency(summary.totalTarget, masked: privacyMaskEnabled))")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .monospacedDigit()
            }

            HStack(spacing: Spacing.md) {
                Label("\(summary.goalCount) goal\(summary.goalCount == 1 ? "" : "s")", systemImage: "flag")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                if summary.fundedCount > 0 {
                    Label("\(summary.fundedCount) funded", systemImage: "checkmark.seal")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                if summary.behindCount > 0 {
                    Label("\(summary.behindCount) behind", systemImage: "exclamationmark.triangle")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
        }
    }

    private func goalsAccessibilityLabel(_ summary: GoalsSummary, privacyMaskEnabled: Bool) -> String {
        guard !summary.isEmpty else { return "Goals: no goals yet." }
        var parts = ["Goals: \(summary.overallPercent) percent of total saved across \(summary.goalCount) goal\(summary.goalCount == 1 ? "" : "s")"]
        if summary.fundedCount > 0 { parts.append("\(summary.fundedCount) funded") }
        if summary.behindCount > 0 { parts.append("\(summary.behindCount) behind") }
        return parts.joined(separator: ". ")
    }

    private func goalsCurrency(_ amount: Double, masked: Bool) -> String {
        PrivacyMaskPresentation.currency(amount, format: .full, isEnabled: masked, style: .compact)
    }
}

#Preview {
    PlanningDestinationView()
        .environment(AppState())
}
