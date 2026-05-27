import SwiftUI
import PlaidBarCore

struct TransactionsView: View {
    @Environment(AppState.self) private var appState
    @State private var searchText = ""
    @State private var selectedTransaction: TransactionDTO?
    @State private var viewMode: TransactionViewMode = .recent
    @State private var selectedCategory: SpendingCategory?
    @State private var selectedAccountId: String?
    @State private var selectedDateRange: DateRangeFilter = .all

    enum TransactionViewMode: String, CaseIterable, Sendable {
        case recent = "Recent"
        case recurring = "Recurring"
    }

    private var availableCategories: [SpendingCategory] {
        let categories = Set(appState.transactions.compactMap(\.category))
        return SpendingCategory.allCases.filter { categories.contains($0) && $0 != .income && $0 != .transfer && $0 != .transferOut }
    }

    private var filteredTransactions: [(String, [TransactionDTO])] {
        var base = appState.transactionsByDate

        // Text search
        if !searchText.isEmpty {
            let query = searchText.lowercased()
            base = base.compactMap { (date, txns) in
                let filtered = txns.filter {
                    $0.displayName.lowercased().contains(query) ||
                    ($0.category?.displayName.lowercased().contains(query) ?? false)
                }
                return filtered.isEmpty ? nil : (date, filtered)
            }
        }

        // Category filter
        if let category = selectedCategory {
            base = base.compactMap { (date, txns) in
                let filtered = txns.filter { $0.category == category }
                return filtered.isEmpty ? nil : (date, filtered)
            }
        }

        // Account filter
        if let accountId = selectedAccountId {
            base = base.compactMap { (date, txns) in
                let filtered = txns.filter { $0.accountId == accountId }
                return filtered.isEmpty ? nil : (date, filtered)
            }
        }

        // Date range filter
        if let startDate = selectedDateRange.startDate() {
            base = base.compactMap { (date, txns) in
                let filtered = txns.filter { $0.date >= startDate }
                return filtered.isEmpty ? nil : (date, filtered)
            }
        }

        return base
    }

    private var hasActiveFilters: Bool {
        selectedCategory != nil || selectedAccountId != nil || selectedDateRange != .all
    }

    var body: some View {
        VStack(spacing: 0) {
            // Segmented toggle: Recent / Recurring
            Picker("View", selection: $viewMode) {
                ForEach(TransactionViewMode.allCases, id: \.self) { mode in
                    Text(mode.rawValue).tag(mode)
                }
            }
            .pickerStyle(.segmented)
            .labelsHidden()
            .padding(.horizontal, Spacing.lg)
            .padding(.top, Spacing.sm)
            .padding(.bottom, Spacing.sm)

            if viewMode == .recurring {
                RecurringView()
            } else {
                recentView
            }
        }
        .animation(.easeInOut(duration: 0.2), value: viewMode)
        .sheet(item: $selectedTransaction) { tx in
            TransactionDetailView(transaction: tx)
                .environment(appState)
        }
    }

    @ViewBuilder
    private var recentView: some View {
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
        .padding(.horizontal, Spacing.md)
        .padding(.vertical, Spacing.sm)
        .background(.quaternary.opacity(0.5), in: RoundedRectangle(cornerRadius: 8))
        .padding(.horizontal, Spacing.lg)
        .padding(.vertical, Spacing.sm)

        // Filter chips
        FilterChipsView(
            selectedCategory: $selectedCategory,
            selectedAccountId: $selectedAccountId,
            selectedDateRange: $selectedDateRange,
            accounts: appState.accounts,
            availableCategories: availableCategories
        )
        .animation(.easeInOut(duration: 0.15), value: selectedCategory)
        .animation(.easeInOut(duration: 0.15), value: selectedAccountId)
        .animation(.easeInOut(duration: 0.15), value: selectedDateRange)

        Divider()

        if filteredTransactions.isEmpty {
            emptyState
        } else {
            ForEach(filteredTransactions, id: \.0) { date, transactions in
                // Date header
                Text(Formatters.displayTransactionDate(date))
                    .sectionTitle()
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.horizontal, Spacing.lg)
                    .padding(.top, Spacing.md)
                    .padding(.bottom, Spacing.xs)
                    .background(.quaternary.opacity(0.3))

                ForEach(transactions) { transaction in
                    TransactionRow(transaction: transaction)
                        .onTapGesture {
                            selectedTransaction = transaction
                        }
                }
            }
        }
    }

    @ViewBuilder
    private var emptyState: some View {
        if !searchText.isEmpty || hasActiveFilters {
            ContentUnavailableView {
                Label("No Results", systemImage: "magnifyingglass")
            } description: {
                Text("No transactions match the current search or filters.")
            } actions: {
                Button {
                    clearSearchAndFilters()
                } label: {
                    Label("Clear Filters", systemImage: "xmark.circle")
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.small)
            }
            .padding()
        } else if !appState.isDemoMode && !appState.serverConnected {
            ContentUnavailableView {
                Label("Server Offline", systemImage: "server.rack")
            } description: {
                Text("Start PlaidBarServer before syncing transaction history.")
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
                Text("Connect a Plaid institution before transaction history can sync.")
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
            ContentUnavailableView {
                Label("No Synced Transactions", systemImage: "tray")
            } description: {
                Text("Run a transaction sync to load recent history for linked accounts.")
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
        }
    }

    private func clearSearchAndFilters() {
        searchText = ""
        selectedCategory = nil
        selectedAccountId = nil
        selectedDateRange = .all
    }

}

struct TransactionRow: View {
    let transaction: TransactionDTO

    var body: some View {
        HStack(spacing: Spacing.md) {
            // Category icon
            Image(systemName: (transaction.category ?? .other).iconName)
                .font(.body)
                .foregroundStyle(.secondary)
                .frame(width: 24)

            // Name and category
            VStack(alignment: .leading, spacing: Spacing.xxs) {
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
        .contentShape(Rectangle())
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
