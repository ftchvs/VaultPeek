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
                        .foregroundStyle(utilizationColor(for: totalUtilization))
                }
                .padding(.horizontal)
                .padding(.bottom, 8)
            }
        }
    }
}

// MARK: - Utilization Color

private func utilizationColor(for percent: Double) -> Color {
    switch percent {
    case 0..<30: return .green
    case 30..<50: return .yellow
    case 50..<75: return .orange
    default: return .red
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
        utilizationColor(for: utilization)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text(account.name)
                    .font(.body)
                Spacer()
                if utilization > threshold {
                    Image(systemName: "exclamationmark.triangle.fill")
                        .foregroundStyle(.orange)
                        .font(.caption)
                }
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
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Spacer()
                Text("Avail: \(Formatters.currency(available, format: .compact))")
                    .font(.caption)
                    .foregroundStyle(.green)
                Text("·")
                    .font(.caption)
                    .foregroundStyle(.quaternary)
                Text(Formatters.percent(utilization))
                    .font(.caption)
                    .fontWeight(.medium)
                    .foregroundStyle(barColor)
            }
        }
        .padding(.horizontal)
        .padding(.vertical, 6)
    }
}
