import SwiftUI
import PlaidBarCore

struct TransactionDetailView: View {
    let transaction: TransactionDTO
    @Environment(AppState.self) private var appState
    @Environment(\.dismiss) private var dismiss

    private var accountName: String {
        appState.accounts.first { $0.id == transaction.accountId }?.name ?? "Unknown"
    }

    var body: some View {
        NavigationStack {
            Form {
                // Header: merchant + category
                Section {
                    HStack(spacing: Spacing.md) {
                        Image(systemName: (transaction.category ?? .other).iconName)
                            .font(.title2)
                            .foregroundStyle(.secondary)
                            .frame(width: 32)

                        VStack(alignment: .leading, spacing: Spacing.xxs) {
                            Text(transaction.displayName)
                                .font(.title3.bold())
                            if transaction.merchantName != nil && transaction.name != transaction.merchantName {
                                Text(transaction.name)
                                    .detailText()
                            }
                        }
                    }
                }

                // Details
                Section {
                    LabeledContent("Amount") {
                        Text(amountText)
                            .monospacedDigit()
                            .foregroundStyle(amountColor)
                    }

                    if let category = transaction.category {
                        LabeledContent("Category") {
                            Label(category.displayName, systemImage: category.iconName)
                        }
                    }

                    if let merchantName = transaction.merchantName {
                        LabeledContent("Merchant") {
                            Text(merchantName)
                        }
                    }

                    LabeledContent("Raw Name") {
                        Text(transaction.name)
                    }

                    LabeledContent("Date") {
                        Text(Formatters.displayTransactionDate(transaction.date))
                    }

                    LabeledContent("Account") {
                        Text(accountName)
                    }

                    LabeledContent("Status") {
                        HStack(spacing: Spacing.xs) {
                            Circle()
                                .fill(transaction.pending ? SemanticColors.pending : SemanticColors.positive)
                                .frame(width: 8, height: 8)
                            Text(transaction.pending ? "Pending" : "Posted")
                        }
                    }

                    LabeledContent("Source") {
                        Text(sourceText)
                    }
                }
            }
            .formStyle(.grouped)
            .navigationTitle("Transaction")
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                }
            }
        }
        .presentationSizing(.fitted)
        .accessibilityElement(children: .contain)
    }

    private var amountText: String {
        if transaction.isIncome {
            return "+\(Formatters.currency(transaction.displayAmount, format: .full))"
        }
        return Formatters.currency(transaction.displayAmount, format: .full)
    }

    private var amountColor: Color {
        transaction.isIncome ? SemanticColors.income : SemanticColors.expense
    }

    private var sourceText: String {
        if transaction.category != nil {
            return "Plaid category"
        }
        return "Uncategorized"
    }

}
