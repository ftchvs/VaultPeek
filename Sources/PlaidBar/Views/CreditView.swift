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
        VStack(alignment: .leading, spacing: 12) {
            if appState.creditAccounts.isEmpty {
                ContentUnavailableView {
                    Label("No Credit Cards", systemImage: "creditcard")
                } description: {
                    Text("Link a credit card to see utilization.")
                }
                .padding()
            } else {
                Text("Credit Utilization")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .textCase(.uppercase)
                    .padding(.horizontal)
                    .padding(.top, 8)

                ForEach(appState.creditAccounts) { card in
                    CreditCardRow(
                        account: card,
                        threshold: appState.creditUtilizationThreshold
                    )
                }

                Divider()
                    .padding(.horizontal)

                // Total
                HStack {
                    Text("Total Utilization")
                        .fontWeight(.semibold)
                    Spacer()
                    Text(Formatters.percent(totalUtilization))
                        .fontWeight(.semibold)
                        .foregroundStyle(
                            totalUtilization > appState.creditUtilizationThreshold
                                ? .orange : .primary
                        )
                }
                .padding(.horizontal)
                .padding(.bottom, 8)
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

    private var isWarning: Bool {
        utilization > threshold
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text(account.name)
                    .font(.body)
                Spacer()
                if isWarning {
                    Image(systemName: "exclamationmark.triangle.fill")
                        .foregroundStyle(.orange)
                        .font(.caption)
                }
            }

            // Progress bar
            GeometryReader { geometry in
                ZStack(alignment: .leading) {
                    RoundedRectangle(cornerRadius: 4)
                        .fill(.quaternary)

                    RoundedRectangle(cornerRadius: 4)
                        .fill(isWarning ? .orange : .blue)
                        .frame(
                            width: max(
                                0,
                                geometry.size.width * min(utilization / 100, 1.0)
                            )
                        )
                }
            }
            .frame(height: 8)

            HStack {
                Text("\(Formatters.currency(balance, format: .compact)) / \(Formatters.currency(limit, format: .compact))")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Spacer()
                Text(Formatters.percent(utilization))
                    .font(.caption)
                    .fontWeight(.medium)
                    .foregroundStyle(isWarning ? .orange : .secondary)
            }
        }
        .padding(.horizontal)
        .padding(.vertical, 6)
    }
}
