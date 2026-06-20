import PlaidBarCore
import SwiftUI

/// The Transaction Workspace's filter + search + sort bar (AND-582).
///
/// Every control writes the shared ``TransactionWorkspace/Filter`` /
/// ``TransactionWorkspace/Sort`` held in ``NavigationModel``, so the query
/// persists per window and the table re-resolves through the pure Core pipeline.
/// Facets compose (AND); the search field also composes with them. A result count
/// and a "Clear" affordance round out the bar.
struct TransactionsFilterBar: View {
    @Binding var filter: TransactionWorkspace.Filter
    @Binding var sort: TransactionWorkspace.Sort
    let accounts: [AccountDTO]
    let resultCount: Int
    var isSearchFocused: FocusState<Bool>.Binding

    var body: some View {
        VStack(alignment: .leading, spacing: Spacing.sm) {
            searchRow
            facetRow
        }
        .accessibilityElement(children: .contain)
    }

    // MARK: - Search row

    private var searchRow: some View {
        HStack(spacing: Spacing.sm) {
            HStack(spacing: Spacing.xs) {
                Image(systemName: "magnifyingglass")
                    .foregroundStyle(.secondary)
                TextField("Search merchant or note", text: $filter.searchText)
                    .textFieldStyle(.plain)
                    .focused(isSearchFocused)
                if !filter.searchText.isEmpty {
                    Button {
                        filter.searchText = ""
                    } label: {
                        Image(systemName: "xmark.circle.fill")
                            .foregroundStyle(.secondary)
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("Clear search")
                }
            }
            .padding(.horizontal, Spacing.sm)
            .padding(.vertical, Spacing.xs)
            .background(.quaternary, in: RoundedRectangle(cornerRadius: Radius.control))
            .frame(maxWidth: 360)

            Spacer(minLength: Spacing.sm)

            Text(resultCountText)
                .font(.caption)
                .foregroundStyle(.secondary)
                .monospacedDigit()
                .accessibilityLabel(resultCountText)

            if filter.isActive {
                Button {
                    filter = filter.cleared()
                } label: {
                    Label("Clear filters", systemImage: "xmark.circle")
                }
                .controlSize(.small)
                .help("Reset every filter and the search")
            }
        }
    }

    private var resultCountText: String {
        resultCount == 1 ? "1 transaction" : "\(resultCount) transactions"
    }

    // MARK: - Facet row

    private var facetRow: some View {
        HStack(spacing: Spacing.sm) {
            accountPicker
            categoryPicker
            dateRangePicker
            amountPicker
            statusPicker

            Spacer(minLength: Spacing.sm)

            sortPicker
        }
        .controlSize(.small)
    }

    private var accountPicker: some View {
        Picker("Account", selection: $filter.accountID) {
            Text("All accounts").tag("")
            ForEach(accounts) { account in
                Text(accountLabel(account)).tag(account.id)
            }
        }
        .pickerStyle(.menu)
        .fixedSize()
        .accessibilityLabel("Filter by account")
    }

    private var categoryPicker: some View {
        Picker("Category", selection: $filter.category) {
            Text("All categories").tag(SpendingCategory?.none)
            ForEach(SpendingCategory.allCases, id: \.self) { category in
                Label(category.displayName, systemImage: category.iconName)
                    .tag(SpendingCategory?.some(category))
            }
        }
        .pickerStyle(.menu)
        .fixedSize()
        .accessibilityLabel("Filter by category")
    }

    private var dateRangePicker: some View {
        Picker("Date", selection: $filter.dateRange) {
            ForEach(TransactionWorkspace.DateRange.allCases, id: \.self) { range in
                Text(range.label).tag(range)
            }
        }
        .pickerStyle(.menu)
        .fixedSize()
        .accessibilityLabel("Filter by date range")
    }

    private var amountPicker: some View {
        Picker("Amount", selection: $filter.amountBand) {
            ForEach(TransactionWorkspace.AmountBand.allCases, id: \.self) { band in
                Text(band.label).tag(band)
            }
        }
        .pickerStyle(.menu)
        .fixedSize()
        .accessibilityLabel("Filter by amount")
    }

    private var statusPicker: some View {
        Picker("Status", selection: $filter.status) {
            ForEach(TransactionWorkspace.StatusFilter.allCases, id: \.self) { status in
                Text(status.label).tag(status)
            }
        }
        .pickerStyle(.menu)
        .fixedSize()
        .accessibilityLabel("Filter by review status")
    }

    private var sortPicker: some View {
        Picker("Sort", selection: $sort) {
            ForEach(TransactionWorkspace.Sort.allCases, id: \.self) { option in
                Text(option.label).tag(option)
            }
        }
        .pickerStyle(.menu)
        .fixedSize()
        .accessibilityLabel("Sort transactions")
    }

    private func accountLabel(_ account: AccountDTO) -> String {
        if let mask = account.mask, !mask.isEmpty {
            return "\(account.name) ••\(mask)"
        }
        return account.name
    }
}
