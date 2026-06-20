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
/// - **Goals** — a read-only summary placeholder. The full Goals destination is a
///   separate net-new sub (AND-606) and is **deferred**; Planning only previews it.
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

                // Goals contributions — read-only summary placeholder. The full
                // Goals destination is the separate net-new AND-606 (deferred).
                goalsSummarySection
            }
            .padding(Spacing.lg)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .scrollContentBackground(.hidden)
        .navigationTitle(RouteDestination.planning.title)
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

    // MARK: - Goals summary (deferred destination — AND-606)

    private var goalsSummarySection: some View {
        VStack(alignment: .leading, spacing: Spacing.sm) {
            Label("Goals", systemImage: RouteDestination.goals.systemImage)
                .sectionTitle()
                .foregroundStyle(.secondary)

            ContentUnavailableView {
                Label("Savings goals are coming soon", systemImage: "flag.checkered")
            } description: {
                Text("Set targets and track contributions in the dedicated Goals workspace.")
            }
            .frame(maxWidth: .infinity, minHeight: 140)
        }
        .padding(Spacing.md)
        .glassSurface(.raised)
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Goals: savings goals are coming soon.")
    }
}

#Preview {
    PlanningDestinationView()
        .environment(AppState())
}
