import Foundation

public struct TransactionFilterCriteria: Equatable, Sendable {
    public let searchText: String
    public let category: SpendingCategory?
    public let accountId: String?
    public let startDate: String?

    public init(
        searchText: String = "",
        category: SpendingCategory? = nil,
        accountId: String? = nil,
        startDate: String? = nil
    ) {
        self.searchText = searchText
        self.category = category
        self.accountId = accountId
        self.startDate = startDate
    }
}

public enum TransactionFilter {
    public static func groupedRecent(
        from transactions: [TransactionDTO],
        criteria: TransactionFilterCriteria = TransactionFilterCriteria(),
        maxCount: Int = PlaidBarConstants.maxRecentTransactions
    ) -> [(String, [TransactionDTO])] {
        let recent = Array(
            transactions
                .sorted { $0.date > $1.date }
                .prefix(maxCount)
        )
        return grouped(filtered(recent, criteria: criteria))
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
