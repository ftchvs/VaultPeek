import SwiftUI
import PlaidBarCore

struct AccountsView: View {
    @Environment(AppState.self) private var appState
    @State private var selectedAccountID: String?

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
                            utilizationThreshold: appState.creditUtilizationThreshold,
                            isSelected: selectedAccountID == account.id,
                            onSelect: { toggleSelectedAccount(account.id) }
                        )
                    }
                }

                // Credit accounts
                if !appState.creditAccounts.isEmpty {
                    sectionHeader("Credit Cards")
                    ForEach(appState.creditAccounts) { account in
                        AccountRow(
                            account: account,
                            utilizationThreshold: appState.creditUtilizationThreshold,
                            isSelected: selectedAccountID == account.id,
                            onSelect: { toggleSelectedAccount(account.id) }
                        )
                    }
                }

                if !appState.loanAccounts.isEmpty {
                    sectionHeader("Loans")
                    ForEach(appState.loanAccounts) { account in
                        AccountRow(
                            account: account,
                            utilizationThreshold: appState.creditUtilizationThreshold,
                            isSelected: selectedAccountID == account.id,
                            onSelect: { toggleSelectedAccount(account.id) }
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
                            utilizationThreshold: appState.creditUtilizationThreshold,
                            isSelected: selectedAccountID == account.id,
                            onSelect: { toggleSelectedAccount(account.id) }
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

    private func toggleSelectedAccount(_ accountID: String) {
        selectedAccountID = selectedAccountID == accountID ? nil : accountID
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
    @Environment(AppState.self) private var appState
    let account: AccountDTO
    let utilizationThreshold: Double
    let isSelected: Bool
    let onSelect: () -> Void

    var body: some View {
        HStack(spacing: Spacing.md) {
            InstitutionAvatar(name: account.institutionName ?? account.name)
                .overlay(alignment: .bottomTrailing) {
                    Circle()
                        .fill(connectionTint)
                        .frame(width: 8, height: 8)
                        .overlay {
                            Circle()
                                .stroke(Color(nsColor: .windowBackgroundColor), lineWidth: 1.5)
                        }
                }

            VStack(alignment: .leading, spacing: Spacing.xxs) {
                Text(account.name)
                    .font(.body)
                Text(secondaryDetailText)
                    .detailText()
                    .lineLimit(1)
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
                Text(trailingDetailText)
                    .lineLimit(1)
                    .minimumScaleFactor(0.78)
                    .foregroundStyle(trailingDetailColor)
                    .font(trailingDetailFont)
            }
        }
        .padding(.horizontal, Spacing.lg)
        .padding(.vertical, Spacing.rowVertical)
        .background(selectionFill, in: RoundedRectangle(cornerRadius: SurfaceTokens.compactCornerRadius))
        .overlay(alignment: .leading) {
            if isSelected {
                Capsule()
                    .fill(Color.accentColor.opacity(0.65))
                    .frame(width: 3)
                    .padding(.vertical, Spacing.xs)
            }
        }
        .overlay {
            if isSelected {
                RoundedRectangle(cornerRadius: SurfaceTokens.compactCornerRadius)
                    .stroke(Color.primary.opacity(0.08), lineWidth: 1)
            }
        }
        .hoverHighlight()
        .onTapGesture(perform: onSelect)
        .accessibilityElement(children: .combine)
        .accessibilityLabel(accessibilityLabel)
        .accessibilityAddTraits(isSelected ? .isSelected : [])
    }

    private var selectionFill: Color {
        isSelected ? Color.accentColor.opacity(0.08) : .clear
    }

    private var connectionPresentation: AccountConnectionPresentation {
        AccountConnectionPresentation.evaluate(
            isDemoMode: appState.usesDemoConnectionPresentation,
            serverConnected: appState.serverConnected,
            isSyncStale: appState.isSyncStale,
            statusSyncText: appState.statusSyncText,
            itemStatus: itemStatus,
            institutionName: itemConnectionStatus?.institutionName,
            itemLastSyncRelative: itemConnectionStatus?.lastSync.map(Formatters.relativeDate)
        )
    }

    private var itemStatus: ItemConnectionStatus? {
        itemConnectionStatus?.status
    }

    private var itemConnectionStatus: ItemStatus? {
        appState.itemStatuses.first { $0.id == account.itemId }
    }

    private var pendingCount: Int {
        appState.transactionsForAccount(account.id).filter(\.pending).count
    }

    private var secondaryDetailText: String {
        AccountPresentation.dashboardRowSubtitle(
            for: account,
            connectionLabel: connectionPresentation.itemSyncLabel ?? connectionPresentation.rowLabel,
            pendingCount: pendingCount
        )
    }

    private var trailingDetailText: String {
        AccountPresentation.dashboardTrailingDetailText(
            for: account,
            connectionLabel: connectionPresentation.signalLabel
        )
    }

    private var trailingDetailColor: Color {
        if let utilization = account.balances.utilizationPercent {
            return utilization >= utilizationThreshold
                ? SemanticColors.utilization(for: utilization, threshold: utilizationThreshold)
                : .secondary
        }
        return connectionTint
    }

    private var trailingDetailFont: Font {
        if account.balances.utilizationPercent != nil {
            return .caption.weight(.bold)
        }
        return .caption2
    }

    private var connectionTint: Color {
        switch connectionPresentation.level {
        case .demo, .offline, .healthy, .unknown:
            return .secondary
        case .stale, .loginRequired:
            return SemanticColors.warning
        case .error:
            return SemanticColors.negative
        }
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
            connectionLabel: connectionPresentation.rowLabel,
            pendingCount: pendingCount,
            isSelected: isSelected,
            utilizationThreshold: utilizationThreshold
        )
    }
}
