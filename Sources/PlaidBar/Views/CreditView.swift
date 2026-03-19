import SwiftUI
import PlaidBarCore

struct CreditView: View {
    @Environment(AppState.self) private var appState

    private var totalUtilization: Double {
        let totalBalance = appState.creditAccounts.reduce(0.0) {
            $0 + abs($1.balances.current ?? 0)
        }
        let totalLimit = appState.creditAccounts.reduce(0.0) {
            $0 + ($1.balances.limit ?? 0)
        }
        guard totalLimit > 0 else { return 0 }
        return (totalBalance / totalLimit) * 100
    }

    var body: some View {
        VStack(alignment: .leading, spacing: Spacing.md) {
            if appState.creditAccounts.isEmpty {
                ContentUnavailableView {
                    Label("No Credit Cards", systemImage: "creditcard")
                } description: {
                    Text("Link a credit card to track utilization and available credit.")
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
                    .tint(SemanticColors.utilization(for: totalUtilization))
                    .scaleEffect(0.7)
                    .frame(width: 36, height: 36)

                    VStack(alignment: .leading, spacing: 2) {
                        Text("Total Utilization")
                            .fontWeight(.semibold)
                        Text(Formatters.percent(totalUtilization))
                            .fontWeight(.semibold)
                            .foregroundStyle(SemanticColors.utilization(for: totalUtilization))
                    }
                    Spacer()
                    Image(systemName: SemanticColors.utilizationIcon(for: totalUtilization))
                        .foregroundStyle(SemanticColors.utilization(for: totalUtilization))
                }
                .padding(.horizontal, Spacing.lg)
                .padding(.bottom, Spacing.sm)
                .accessibilityElement(children: .combine)
                .accessibilityLabel("Total credit utilization \(Formatters.percent(totalUtilization))")
            }
        }
    }
}

struct CreditCardRow: View {
    let account: AccountDTO
    let threshold: Double

    private var balance: Double {
        abs(account.balances.current ?? 0)
    }

    private var limit: Double {
        account.balances.limit ?? 0
    }

    private var utilization: Double {
        guard limit > 0 else { return 0 }
        return (balance / limit) * 100
    }

    private var available: Double {
        max(0, limit - balance)
    }

    private var barColor: Color {
        SemanticColors.utilization(for: utilization)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text(account.name)
                    .font(.body)
                Spacer()
                // Issue #4: threshold-specific icons
                Image(systemName: SemanticColors.utilizationIcon(for: utilization))
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
                    .fontWeight(utilization >= 30 ? .semibold : .medium)
                    .foregroundStyle(barColor)
            }
        }
        .padding(.horizontal, Spacing.lg)
        .padding(.vertical, 6)
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(account.name), \(Formatters.percent(utilization)) utilization, \(Formatters.currency(available, format: .compact)) available")
    }
}
