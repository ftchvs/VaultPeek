import SwiftUI
import PlaidBarCore

struct CreditView: View {
    @Environment(AppState.self) private var appState

    private var totalUtilization: Double {
        appState.totalCreditUtilization ?? 0
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

                // Total with gauge
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
        }
    }

    private var totalUtilizationStatus: String {
        AccountPresentation.utilizationStatusLabel(
            for: totalUtilization,
            threshold: appState.creditUtilizationThreshold
        )
    }

    @ViewBuilder
    private var emptyState: some View {
        if !appState.isDemoMode && !appState.serverConnected {
            ContentUnavailableView {
                Label("Server Offline", systemImage: "server.rack")
            } description: {
                Text("Start PlaidBarServer before checking credit utilization.")
            } actions: {
                Button {
                    Task { await appState.checkServerConnection() }
                } label: {
                    Label("Check Server", systemImage: "arrow.clockwise")
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.small)
            }
            .padding()
        } else if appState.statusItemCount == 0 {
            ContentUnavailableView {
                Label("No Bank Linked", systemImage: "creditcard")
            } description: {
                Text("Connect a Plaid institution with a credit card to track utilization.")
            } actions: {
                Button {
                    Task { await appState.addAccount() }
                } label: {
                    Label("Add Account", systemImage: "plus.circle")
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.small)
            }
            .padding()
        } else if appState.accounts.isEmpty {
            ContentUnavailableView {
                Label("No Account Data", systemImage: "tray")
            } description: {
                Text("The linked item has not loaded account balances yet.")
            } actions: {
                Button {
                    Task { await appState.refreshAccounts() }
                } label: {
                    Label("Refresh Accounts", systemImage: "arrow.clockwise")
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.small)
            }
            .padding()
        } else {
            ContentUnavailableView {
                Label("No Credit Accounts", systemImage: "creditcard")
            } description: {
                Text("Your linked accounts do not include a credit card with utilization data.")
            } actions: {
                Button {
                    Task { await appState.addAccount() }
                } label: {
                    Label("Add Credit Card", systemImage: "plus.circle")
                }
                .buttonStyle(.bordered)
                .controlSize(.small)
            }
            .padding()
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

    private var available: Double {
        AccountPresentation.availableBalance(for: account)
    }

    private var barColor: Color {
        SemanticColors.utilization(for: utilization, threshold: threshold)
    }

    private var utilizationStatus: String {
        AccountPresentation.utilizationStatusLabel(for: utilization, threshold: threshold)
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
                                geometry.size.width * min(utilization / 100, 1.0)
                            )
                        )
                }
            }
            .frame(height: 12)

            HStack {
                Text("\(Formatters.currency(balance, format: .compact)) / \(Formatters.currency(limit, format: .compact))")
                    .detailText()
                Spacer()
                Text("Avail: \(Formatters.currency(available, format: .compact))")
                    .font(.caption)
                    .foregroundStyle(SemanticColors.available)
                Text("\u{00B7}")
                    .font(.caption)
                    .foregroundStyle(.quaternary)
                Text(Formatters.percent(utilization))
                    .font(.caption)
                    // Issue #4: bold percentage at warning thresholds
                    .fontWeight(utilization >= threshold ? .semibold : .medium)
                    .foregroundStyle(barColor)
            }
        }
        .padding(.horizontal, Spacing.lg)
        .padding(.vertical, Spacing.rowVertical)
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(account.name), \(Formatters.percent(utilization)) utilization, \(utilizationStatus), \(Formatters.currency(available, format: .compact)) available")
    }
}
