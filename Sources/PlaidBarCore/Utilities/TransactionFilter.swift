import Foundation

// `Codable` is added so this can ride inside the typed `Route.transactions`
// deep-link (AND-594); all members are already Codable, so synthesis is free.
public struct TransactionFilterCriteria: Equatable, Sendable, Codable, Hashable {
    public let searchText: String
    public let category: SpendingCategory?
    /// A parent ``CategoryGroup`` to filter to — the group-level facet a Dashboard
    /// spend-donut slice / legend row deep-links into (AND-730). Purely additive
    /// (defaults to `nil`), so existing leaf-`category` deep-links are unchanged.
    public let categoryGroup: CategoryGroup?
    public let accountId: String?
    public let startDate: String?

    public init(
        searchText: String = "",
        category: SpendingCategory? = nil,
        categoryGroup: CategoryGroup? = nil,
        accountId: String? = nil,
        startDate: String? = nil
    ) {
        self.searchText = searchText
        self.category = category
        self.categoryGroup = categoryGroup
        self.accountId = accountId
        self.startDate = startDate
    }

    /// Translates these criteria into the window-first ledger's
    /// ``TransactionWorkspace/Filter`` (AND-730). Lets a typed
    /// ``Route/transactions(filter:focus:)`` deep-link pre-apply a category-group
    /// (donut) or leaf-category filter when the window's Transactions destination
    /// consumes the route. The `startDate` is intentionally dropped — the workspace
    /// models date as a relative ``TransactionWorkspace/DateRange`` rather than an
    /// absolute lower bound — so a donut/legend link carries only the facets the
    /// ledger represents.
    public var workspaceFilter: TransactionWorkspace.Filter {
        TransactionWorkspace.Filter(
            accountID: accountId ?? "",
            category: category,
            categoryGroup: categoryGroup,
            searchText: searchText
        )
    }
}

public enum TransactionFilter {
    public static func groupedRecent(
        from transactions: [TransactionDTO],
        criteria: TransactionFilterCriteria = TransactionFilterCriteria(),
        maxCount: Int = PlaidBarConstants.maxRecentTransactions
    ) -> [(String, [TransactionDTO])] {
        let matching = filtered(transactions, criteria: criteria)
        let recent = Array(
            matching
                .sorted { $0.date > $1.date }
                .prefix(maxCount)
        )
        return grouped(recent)
    }

    public static func filtered(
        _ transactions: [TransactionDTO],
        criteria: TransactionFilterCriteria
    ) -> [TransactionDTO] {
        let query = criteria.searchText
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .lowercased()

        return transactions.filter { transaction in
            if !query.isEmpty,
               !transaction.displayName.lowercased().contains(query),
               !(transaction.category?.displayName.lowercased().contains(query) ?? false) {
                return false
            }

            if let category = criteria.category,
               transaction.category != category {
                return false
            }

            if let accountId = criteria.accountId,
               transaction.accountId != accountId {
                return false
            }

            if let startDate = criteria.startDate,
               transaction.date < startDate {
                return false
            }

            return true
        }
    }

    private static func grouped(_ transactions: [TransactionDTO]) -> [(String, [TransactionDTO])] {
        let grouped = Dictionary(grouping: transactions) { $0.date }
        return grouped.sorted { $0.key > $1.key }
    }
}
