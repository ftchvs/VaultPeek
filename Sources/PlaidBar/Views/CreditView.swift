import SwiftUI
import PlaidBarCore

struct CreditView: View {
    @Environment(AppState.self) private var appState

    private var totalUtilization: Double {
        appState.totalCreditUtilization ?? 0
    }

    private var hasCreditUtilizationData: Bool {
        appState.creditAccounts.contains { $0.balances.utilizationPercent != nil }
    }

    private var emptyPresentation: SecondaryContentUnavailableState {
        SecondaryContentUnavailableState.credit(
            isDemoMode: appState.isDemoMode,
            isInitialLoad: appState.loadState(for: .credit).isInitialLoad,
            serverConnected: appState.serverConnected,
            linkedItemCount: appState.statusItemCount,
            accountCount: appState.accounts.count
        )
    }

    var body: some View {
        VStack(alignment: .leading, spacing: Spacing.md) {
            if appState.creditAccounts.isEmpty {
                emptyState
            } else {
                Text("Credit Utilization")
                    .sectionTitle()
                    .foregroundStyle(.secondary)
                    .padding(.horizontal, Spacing.lg)
                    .padding(.top, Spacing.sm)

                ForEach(appState.creditAccounts) { card in
                    CreditCardRow(
                        account: card,
                        threshold: appState.creditUtilizationThreshold
                    )
                }

                Divider()
                    .padding(.horizontal, Spacing.lg)

                if hasCreditUtilizationData {
                    totalUtilizationSummary
                } else {
                    creditDataUnavailableCallout
                }
            }
        }
    }

    private var totalUtilizationStatus: String {
        AccountPresentation.utilizationStatusLabel(
            for: totalUtilization,
            threshold: appState.creditUtilizationThreshold
        )
    }

    private var totalUtilizationSummary: some View {
        HStack(spacing: Spacing.md) {
            Gauge(value: min(totalUtilization, 100), in: 0...100) {
                EmptyView()
            }
            .gaugeStyle(.accessoryCircular)
            .tint(SemanticColors.utilization(for: totalUtilization, threshold: appState.creditUtilizationThreshold))
            .scaleEffect(0.7)
            .frame(width: 36, height: 36)

            VStack(alignment: .leading, spacing: Spacing.xxs) {
                Text("Total Utilization")
                    .fontWeight(.semibold)
                Text(Formatters.percent(totalUtilization))
                    .fontWeight(.semibold)
                    .foregroundStyle(SemanticColors.utilization(for: totalUtilization, threshold: appState.creditUtilizationThreshold))
                Text(totalUtilizationStatus)
                    .microText()
                    .foregroundStyle(.secondary)
            }
            Spacer()
            Image(systemName: SemanticColors.utilizationIcon(
                for: totalUtilization,
                threshold: appState.creditUtilizationThreshold
            ))
                .foregroundStyle(SemanticColors.utilization(for: totalUtilization, threshold: appState.creditUtilizationThreshold))
        }
        .padding(.horizontal, Spacing.lg)
        .padding(.bottom, Spacing.sm)
        .accessibilityElement(children: .combine)
        .accessibilityLabel("Total credit utilization \(Formatters.percent(totalUtilization)), \(totalUtilizationStatus)")
    }

    private var creditDataUnavailableCallout: some View {
        HStack(alignment: .top, spacing: Spacing.md) {
            Image(systemName: "exclamationmark.triangle.fill")
                .foregroundStyle(SemanticColors.warning)
                .frame(width: 24)

            VStack(alignment: .leading, spacing: Spacing.xs) {
                Text("Credit Limits Unavailable")
                    .fontWeight(.semibold)
                Text("Credit cards are linked, but Plaid has not returned limits needed to calculate utilization.")
                    .detailText()
                    .fixedSize(horizontal: false, vertical: true)

                Button {
                    Task { await appState.refreshAccounts() }
                } label: {
                    Label("Refresh Accounts", systemImage: "arrow.clockwise")
                }
                .buttonStyle(.bordered)
                .controlSize(.small)
            }
        }
        .padding(.horizontal, Spacing.lg)
        .padding(.bottom, Spacing.sm)
        .accessibilityElement(children: .combine)
        .accessibilityLabel("Credit limits unavailable. Refresh accounts to check for updated credit data.")
    }

    @ViewBuilder
    private var emptyState: some View {
        SecondaryUnavailableView(presentation: emptyPresentation) {
            performEmptyAction(emptyPresentation.action)
        }
    }

    private func performEmptyAction(_ action: SecondaryContentUnavailableAction) {
        switch action {
        case .checkServer:
            Task { await appState.checkServerConnection() }
        case .addAccount:
            Task { await appState.addAccount() }
        case .refreshAccounts:
            Task { await appState.refreshAccounts() }
        case .syncTransactions:
            Task { await appState.syncTransactions() }
        case .refresh:
            Task { await appState.refreshDashboard() }
        case .clearFilters, .showWiderPeriod:
            break
        }
    }
}

struct CreditCardRow: View {
    let account: AccountDTO
    let threshold: Double

    private var balance: Double {
        AccountPresentation.displayBalance(for: account)
    }

    private var limit: Double {
        account.balances.limit ?? 0
    }

    private var utilization: Double {
        account.balances.utilizationPercent ?? 0
    }

    private var hasUtilizationData: Bool {
        account.balances.utilizationPercent != nil
    }

    private var available: Double {
        AccountPresentation.availableBalance(for: account)
    }

    private var barColor: Color {
        hasUtilizationData ? SemanticColors.utilization(for: utilization, threshold: threshold) : .secondary
    }

    private var utilizationStatus: String {
        guard hasUtilizationData else { return "Limit unavailable" }
        return AccountPresentation.utilizationStatusLabel(for: utilization, threshold: threshold)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: Spacing.rowVertical) {
            HStack {
                Text(account.name)
                    .font(.body)
                Spacer()
                // Issue #4: threshold-specific icons
                Image(systemName: SemanticColors.utilizationIcon(for: utilization, threshold: threshold))
                    .foregroundStyle(barColor)
                    .font(.caption)
            }

            // Progress bar — thicker with rounded ends
            GeometryReader { geometry in
                ZStack(alignment: .leading) {
                    RoundedRectangle(cornerRadius: 6)
                        .fill(.quaternary)

                    RoundedRectangle(cornerRadius: 6)
                        .fill(barColor)
                        .frame(
                            width: max(
                                0,
                                geometry.size.width * min(hasUtilizationData ? utilization / 100 : 0, 1.0)
                            )
                        )
                }
            }
            .frame(height: 12)

            HStack {
                Text(balanceLimitText)
                    .detailText()
                Spacer()
                if hasUtilizationData {
                    Text("Avail: \(Formatters.currency(available, format: .compact))")
                        .font(.caption)
                        .foregroundStyle(SemanticColors.available)
                    Text("\u{00B7}")
                        .font(.caption)
                        .foregroundStyle(.quaternary)
                }
                Text(utilizationText)
                    .font(.caption)
                    // Issue #4: bold percentage at warning thresholds
                    .fontWeight(hasUtilizationData && utilization >= threshold ? .semibold : .medium)
                    .foregroundStyle(barColor)
            }
        }
        .padding(.horizontal, Spacing.lg)
        .padding(.vertical, Spacing.rowVertical)
        .accessibilityElement(children: .combine)
        .accessibilityLabel(accessibilityLabel)
    }

    private var balanceLimitText: String {
        guard hasUtilizationData else {
            return "\(Formatters.currency(balance, format: .compact)) owed - limit unavailable"
        }
        return "\(Formatters.currency(balance, format: .compact)) / \(Formatters.currency(limit, format: .compact))"
    }

    private var utilizationText: String {
        hasUtilizationData ? Formatters.percent(utilization) : "Utilization unavailable"
    }

    private var accessibilityLabel: String {
        guard hasUtilizationData else {
            return "\(account.name), \(Formatters.currency(balance, format: .compact)) owed, credit limit unavailable"
        }
        return "\(account.name), \(Formatters.percent(utilization)) utilization, \(utilizationStatus), \(Formatters.currency(available, format: .compact)) available"
    }
}
