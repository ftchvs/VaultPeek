import SwiftUI
import PlaidBarCore

struct AccountsView: View {
    @Environment(AppState.self) private var appState

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            if appState.accounts.isEmpty {
                ContentUnavailableView {
                    Label("No Accounts", systemImage: "building.columns")
                } description: {
                    Text("Add a bank account to get started.")
                }
                .padding()
            } else {
                // Depository accounts
                if !appState.depositoryAccounts.isEmpty {
                    sectionHeader("Bank Accounts")
                    ForEach(appState.depositoryAccounts) { account in
                        AccountRow(account: account)
                    }
                }

                // Credit accounts
                if !appState.creditAccounts.isEmpty {
                    sectionHeader("Credit Cards")
                    ForEach(appState.creditAccounts) { account in
                        AccountRow(account: account)
                    }
                }

                // Other accounts
                let otherAccounts = appState.accounts.filter {
                    $0.type != .depository && $0.type != .credit
                }
                if !otherAccounts.isEmpty {
                    sectionHeader("Other")
                    ForEach(otherAccounts) { account in
                        AccountRow(account: account)
                    }
                }

                // Net balance footer
                Divider()
                    .padding(.top, 4)
                HStack {
                    Text("Net Balance")
                        .fontWeight(.semibold)
                    Spacer()
                    Text(Formatters.currency(appState.netBalance, format: .full))
                        .fontWeight(.semibold)
                        .monospacedDigit()
                }
                .padding(.horizontal)
                .padding(.vertical, 8)
            }
        }
    }

    private func sectionHeader(_ title: String) -> some View {
        Text(title)
            .font(.caption)
            .foregroundStyle(.secondary)
            .textCase(.uppercase)
            .padding(.horizontal)
            .padding(.top, 12)
            .padding(.bottom, 4)
    }
}

struct AccountRow: View {
    let account: AccountDTO

    var body: some View {
        HStack {
            VStack(alignment: .leading, spacing: 2) {
                Text(account.name)
                    .font(.body)
                if let mask = account.mask {
                    Text("\u{2022}\u{2022}\u{2022}\u{2022} \(mask)")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            Spacer()
            VStack(alignment: .trailing, spacing: 2) {
                let amount = account.balances.current ?? account.balances.effectiveBalance
                Text(Formatters.currency(
                    account.type == .credit ? -abs(amount) : amount,
                    format: .full
                ))
                .monospacedDigit()
                .foregroundStyle(account.type == .credit ? .red : .primary)

                if let utilization = account.balances.utilizationPercent {
                    Text(Formatters.percent(utilization))
                        .font(.caption)
                        .foregroundStyle(utilization > 30 ? .orange : .secondary)
                }
            }
        }
        .padding(.horizontal)
        .padding(.vertical, 6)
    }
}
