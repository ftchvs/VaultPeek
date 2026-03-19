import SwiftUI
import PlaidBarCore

struct TransactionsView: View {
    @Environment(AppState.self) private var appState
    @State private var searchText = ""

    private var filteredTransactions: [(String, [TransactionDTO])] {
        if searchText.isEmpty {
            return appState.transactionsByDate
        }
        let query = searchText.lowercased()
        return appState.transactionsByDate.compactMap { (date, txns) in
            let filtered = txns.filter {
                $0.displayName.lowercased().contains(query) ||
                ($0.category?.displayName.lowercased().contains(query) ?? false)
            }
            return filtered.isEmpty ? nil : (date, filtered)
        }
    }

    var body: some View {
        VStack(spacing: 0) {
            // Search bar
            HStack(spacing: Spacing.sm) {
                Image(systemName: "magnifyingglass")
                    .foregroundStyle(.secondary)
                    .font(.caption)
                TextField("Search transactions...", text: $searchText)
                    .textFieldStyle(.plain)
                    .font(.body)
                if !searchText.isEmpty {
                    Button {
                        searchText = ""
                    } label: {
                        Image(systemName: "xmark.circle.fill")
                            .foregroundStyle(.secondary)
                    }
                    .buttonStyle(.borderless)
                }
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 7)
            .background(.quaternary.opacity(0.5), in: RoundedRectangle(cornerRadius: 8))
            .padding(.horizontal, Spacing.lg)
            .padding(.vertical, Spacing.sm)

            Divider()

            if filteredTransactions.isEmpty {
                ContentUnavailableView {
                    Label(
                        searchText.isEmpty ? "No Transactions" : "No Results",
                        systemImage: searchText.isEmpty ? "tray" : "magnifyingglass"
                    )
                } description: {
                    Text(searchText.isEmpty
                        ? "Transactions will appear after syncing with your bank."
                        : "No transactions match \"\(searchText)\".")
                }
                .padding()
            } else {
                ForEach(filteredTransactions, id: \.0) { date, transactions in
                    // Date header
                    Text(Self.formatDateHeader(date))
                        .sectionTitle()
                        .foregroundStyle(.secondary)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(.horizontal, Spacing.lg)
                        .padding(.top, 10)
                        .padding(.bottom, Spacing.xs)
                        .background(.quaternary.opacity(0.3))

                    ForEach(transactions) { transaction in
                        TransactionRow(transaction: transaction)
                    }
                }
            }
        }
    }

    private static func formatDateHeader(_ dateString: String) -> String {
        guard let date = Formatters.parseTransactionDate(dateString) else {
            return dateString
        }
        return Formatters.displayDate(date)
    }
}

struct TransactionRow: View {
    let transaction: TransactionDTO

    var body: some View {
        HStack(spacing: 10) {
            // Category icon
            Image(systemName: (transaction.category ?? .other).iconName)
                .font(.body)
                .foregroundStyle(.secondary)
                .frame(width: 24)

            // Name and category
            VStack(alignment: .leading, spacing: 2) {
                Text(transaction.displayName)
                    .font(.body)
                    .lineLimit(1)
                if let category = transaction.category {
                    Text(category.displayName)
                        .detailText()
                }
            }

            Spacer()

            // Amount
            VStack(alignment: .trailing) {
                Text(amountText)
                    .foregroundStyle(amountColor)
                    .monospacedDigit()

                if transaction.pending {
                    Text("Pending")
                        .microText()
                        .foregroundStyle(SemanticColors.pending)
                }
            }
        }
        .padding(.horizontal, Spacing.lg)
        .padding(.vertical, Spacing.sm)
        .hoverHighlight()
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(transaction.displayName), \(amountText)\(transaction.pending ? ", pending" : "")")
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
}
