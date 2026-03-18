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
            HStack {
                Image(systemName: "magnifyingglass")
                    .foregroundStyle(.secondary)
                TextField("Search transactions...", text: $searchText)
                    .textFieldStyle(.plain)
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
            .padding(.horizontal)
            .padding(.vertical, 8)

            Divider()

            if filteredTransactions.isEmpty {
                ContentUnavailableView {
                    Label("No Transactions", systemImage: "creditcard")
                } description: {
                    Text(searchText.isEmpty
                        ? "Transactions will appear after syncing."
                        : "No matches found.")
                }
                .padding()
            } else {
                ForEach(filteredTransactions, id: \.0) { date, transactions in
                    // Date header
                    Text(Self.formatDateHeader(date))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(.horizontal)
                        .padding(.top, 10)
                        .padding(.bottom, 4)

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
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }

            Spacer()

            // Amount
            VStack(alignment: .trailing) {
                Text(amountText)
                    .foregroundStyle(transaction.isIncome ? .green : .primary)
                    .monospacedDigit()

                if transaction.pending {
                    Text("Pending")
                        .font(.caption2)
                        .foregroundStyle(.orange)
                }
            }
        }
        .padding(.horizontal)
        .padding(.vertical, 5)
    }

    private var amountText: String {
        let prefix = transaction.isIncome ? "+" : "-"
        return "\(prefix)\(Formatters.currency(transaction.displayAmount, format: .full))"
    }
}
