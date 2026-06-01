import SwiftUI
import PlaidBarCore

struct RecurringView: View {
    @Environment(AppState.self) private var appState

    var body: some View {
        let recurring = appState.recurringTransactions
        let monthlyEstimate = appState.estimatedMonthlyRecurring

        VStack(alignment: .leading, spacing: 0) {
            if recurring.isEmpty {
                emptyState
            } else {
                // Estimated monthly total header (normalizes weekly/annual to monthly equivalent)
                HStack {
                    Text("EST. MONTHLY COST")
                        .sectionTitle()
                        .foregroundStyle(.secondary)
                    Spacer()
                    Text(Formatters.currency(monthlyEstimate, format: .full))
                        .heroBalance()
                }
                .padding(.horizontal, Spacing.lg)
                .padding(.top, Spacing.md)
                .padding(.bottom, Spacing.sm)
                .accessibilityElement(children: .combine)
                .accessibilityLabel("Estimated monthly recurring cost: \(Formatters.currency(monthlyEstimate, format: .full))")

                Divider()

                ForEach(recurring) { item in
                    RecurringRow(item: item)
                }
            }
        }
    }

    @ViewBuilder
    private var emptyState: some View {
        if !appState.isDemoMode && !appState.serverConnected {
            ContentUnavailableView {
                Label("Server Offline", systemImage: "server.rack")
            } description: {
                Text("Start PlaidBarServer before detecting recurring charges.")
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
                Label("No Bank Linked", systemImage: "building.columns")
            } description: {
                Text("Connect a Plaid institution before recurring charges can be detected.")
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
        } else if appState.transactions.isEmpty {
            ContentUnavailableView {
                Label("No Synced Transactions", systemImage: "tray")
            } description: {
                Text("Sync transaction history so PlaidBar can look for repeated charges.")
            } actions: {
                Button {
                    Task { await appState.syncTransactions() }
                } label: {
                    Label("Sync Transactions", systemImage: "arrow.triangle.2.circlepath")
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.small)
            }
            .padding()
        } else {
            ContentUnavailableView {
                Label("No Recurring Charges Found", systemImage: "arrow.clockwise")
            } description: {
                Text("PlaidBar needs repeated merchant charges, usually 2+ months of history, before it marks a charge as recurring.")
            }
            .padding()
        }
    }
}

private struct RecurringRow: View {
    let item: RecurringTransaction

    var body: some View {
        HStack(spacing: Spacing.md) {
            // Category icon
            Image(systemName: (item.category ?? .other).iconName)
                .font(.body)
                .foregroundStyle(.secondary)
                .frame(width: 24)

            VStack(alignment: .leading, spacing: Spacing.xxs) {
                Text(item.merchantName)
                    .font(.body)
                    .lineLimit(1)

                HStack(spacing: Spacing.sm) {
                    // Frequency badge
                    Text(item.frequency.displayName)
                        .microText()
                        .padding(.horizontal, Spacing.sm)
                        .padding(.vertical, Spacing.xxs)
                        .background(SemanticColors.recurring.opacity(0.15), in: Capsule())
                        .foregroundStyle(SemanticColors.recurring)

                    Text(Formatters.currency(item.averageAmount, format: .full))
                        .detailText()
                        .monospacedDigit()
                }

                Text("Last: \(Formatters.displayTransactionDate(item.lastDate)) • Next: \(Formatters.displayTransactionDate(item.nextExpectedDate))")
                    .detailText()

                Text("\(item.transactionCount) matching charges • \(Formatters.percent(item.confidence * 100, decimals: 0)) confidence")
                    .detailText()
            }

            Spacer()
        }
        .padding(.horizontal, Spacing.lg)
        .padding(.vertical, Spacing.sm)
        .hoverHighlight()
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(item.merchantName), \(item.frequency.displayName), \(Formatters.currency(item.averageAmount, format: .full)), \(item.transactionCount) matching charges, \(Formatters.percent(item.confidence * 100, decimals: 0)) confidence, next expected \(Formatters.displayTransactionDate(item.nextExpectedDate))")
    }
}
