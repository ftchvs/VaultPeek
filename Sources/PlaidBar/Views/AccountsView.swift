import SwiftUI
import PlaidBarCore

struct AccountsView: View {
    @Environment(AppState.self) private var appState

    private var emptyPresentation: SecondaryContentUnavailableState {
        SecondaryContentUnavailableState.accounts(
            isDemoMode: appState.isDemoMode,
            serverConnected: appState.serverConnected,
            linkedItemCount: appState.statusItemCount
        )
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            if appState.accounts.isEmpty {
                emptyState
            } else {
                // Depository accounts
                if !appState.depositoryAccounts.isEmpty {
                    sectionHeader("Bank Accounts")
                    ForEach(appState.depositoryAccounts) { account in
                        AccountRow(
                            account: account,
                            utilizationThreshold: appState.creditUtilizationThreshold
                        )
                    }
                }

                // Credit accounts
                if !appState.creditAccounts.isEmpty {
                    sectionHeader("Credit Cards")
                    ForEach(appState.creditAccounts) { account in
                        AccountRow(
                            account: account,
                            utilizationThreshold: appState.creditUtilizationThreshold
                        )
                    }
                }

                if !appState.loanAccounts.isEmpty {
                    sectionHeader("Loans")
                    ForEach(appState.loanAccounts) { account in
                        AccountRow(
                            account: account,
                            utilizationThreshold: appState.creditUtilizationThreshold
                        )
                    }
                }

                // Other accounts
                let otherAccounts = appState.accounts.filter {
                    $0.type != .depository && $0.type != .credit && $0.type != .loan
                }
                if !otherAccounts.isEmpty {
                    sectionHeader("Other")
                    ForEach(otherAccounts) { account in
                        AccountRow(
                            account: account,
                            utilizationThreshold: appState.creditUtilizationThreshold
                        )
                    }
                }

                // Net balance footer (inside scroll)
                Divider()
                    .padding(.top, Spacing.xs)
                HStack {
                    Text("Net Balance")
                        .fontWeight(.semibold)
                    Spacer()
                    Text(Formatters.currency(appState.netBalance, format: .full))
                        .fontWeight(.semibold)
                        .monospacedDigit()
                        .contentTransition(.numericText())
                        .animation(.default, value: appState.netBalance)
                }
                .padding(.horizontal, Spacing.lg)
                .padding(.vertical, Spacing.sm)
            }
        }
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

    private func sectionHeader(_ title: String) -> some View {
        Text(title)
            .sectionTitle()
            .foregroundStyle(.secondary)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, Spacing.lg)
            .padding(.top, Spacing.md)
            .padding(.bottom, Spacing.xs)
            .background(.quaternary.opacity(0.3))
    }
}

// MARK: - Institution Avatar

private struct InstitutionAvatar: View {
    let name: String

    private var initial: String {
        String(name.prefix(1)).uppercased()
    }

    private static let avatarColors: [Color] = [.blue, .green, .orange, .purple, .pink, .teal, .indigo, .mint]

    private var color: Color {
        // DJB2 hash for deterministic color across launches (hashValue is randomized per process)
        let hash = name.utf8.reduce(5381) { ($0 &<< 5) &+ $0 &+ Int($1) }
        return Self.avatarColors[abs(hash) % Self.avatarColors.count]
    }

    var body: some View {
        Text(initial)
            .font(.caption.bold())
            .foregroundStyle(.white)
            .frame(width: 28, height: 28)
            .background(color, in: Circle())
    }
}

struct AccountRow: View {
    let account: AccountDTO
    let utilizationThreshold: Double

    var body: some View {
        HStack(spacing: Spacing.md) {
            InstitutionAvatar(name: account.institutionName ?? account.name)

            VStack(alignment: .leading, spacing: Spacing.xxs) {
                Text(account.name)
                    .font(.body)
                if let mask = account.mask {
                    Text("\u{2022}\u{2022}\u{2022}\u{2022} \(mask)")
                        .detailText()
                }
            }
            Spacer()
            VStack(alignment: .trailing, spacing: Spacing.xxs) {
                HStack(spacing: Spacing.xs) {
                    // Issue #3: secondary cue for debt amounts (not color-only)
                    if AccountPresentation.isDebt(account) {
                        Image(systemName: AccountPresentation.iconName(for: account))
                            .font(.caption2)
                            .foregroundStyle(SemanticColors.creditDebt)
                    }
                    Text(formattedAmount)
                        .monospacedDigit()
                        .foregroundStyle(amountColor)
                }

                if let utilization = account.balances.utilizationPercent {
                    Text(Formatters.percent(utilization))
                        .microText()
                        .foregroundStyle(
                            utilization >= utilizationThreshold
                                ? SemanticColors.utilization(for: utilization, threshold: utilizationThreshold)
                                : .secondary
                        )
                }
            }
        }
        .padding(.horizontal, Spacing.lg)
        .padding(.vertical, Spacing.rowVertical)
        .hoverHighlight()
        .accessibilityElement(children: .combine)
        .accessibilityLabel(accessibilityLabel)
    }

    private var formattedAmount: String {
        AccountPresentation.rowAmountText(for: account)
    }

    private var amountColor: Color {
        AccountPresentation.isDebt(account) ? SemanticColors.creditDebt : .primary
    }

    private var accessibilityLabel: String {
        AccountPresentation.rowAccessibilityLabel(
            for: account,
            amountText: formattedAmount,
            utilizationThreshold: utilizationThreshold
        )
    }
}
