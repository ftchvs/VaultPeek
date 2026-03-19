import SwiftUI
import PlaidBarCore

struct RecurringView: View {
    @Environment(AppState.self) private var appState

    var body: some View {
        let recurring = appState.recurringTransactions
        let monthlyEstimate = appState.estimatedMonthlyRecurring

        VStack(alignment: .leading, spacing: 0) {
            if recurring.isEmpty {
                ContentUnavailableView {
                    Label("No Recurring Transactions", systemImage: "arrow.clockwise")
                } description: {
                    Text("Recurring charges will be detected automatically after syncing 2+ months of transactions.")
                }
                .padding()
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

                Text("Last: \(Formatters.displayTransactionDate(item.lastDate))")
                    .detailText()
            }

            Spacer()
        }
        .padding(.horizontal, Spacing.lg)
        .padding(.vertical, Spacing.sm)
        .hoverHighlight()
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(item.merchantName), \(item.frequency.displayName), \(Formatters.currency(item.averageAmount, format: .full))")
    }
}
