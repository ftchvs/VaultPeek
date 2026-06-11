import Foundation

public enum AccountTransactionFeed {
    public struct AccountActivitySnapshot: Sendable, Equatable {
        public let transactions: [TransactionDTO]
        public let transactionCount: Int
        public let pendingTransactionCount: Int
        public let latestTransactionDate: String?
        public let recentSummary: AccountActivitySummary

        public var pendingTransactions: [TransactionDTO] {
            transactions.filter(\.pending)
        }

        public init(transactions: [TransactionDTO]) {
            self.transactions = AccountTransactionFeed.sortedForFeed(transactions)
            self.transactionCount = transactions.count
            self.pendingTransactionCount = transactions.count(where: \.pending)
            self.latestTransactionDate = transactions.latestTransactionDate
            self.recentSummary = AccountActivitySummary.recent(from: self.transactions)
        }
    }

    public static func activitySnapshot(
        forAccountId accountId: String,
        in transactions: [TransactionDTO]
    ) -> AccountActivitySnapshot {
        AccountActivitySnapshot(transactions: transactions.filter { $0.accountId == accountId })
    }

    public static func transactions(
        forAccountId accountId: String,
        in transactions: [TransactionDTO]
    ) -> [TransactionDTO] {
        activitySnapshot(forAccountId: accountId, in: transactions).transactions
    }

    public static func relatedMerchantTransactions(
        merchantName: String,
        excluding transactionId: String,
        in transactions: [TransactionDTO]
    ) -> [TransactionDTO] {
        sortedForFeed(
            transactions.filter {
                $0.merchantName == merchantName && $0.id != transactionId
            }
        )
    }

    public static func sortedForFeed(_ transactions: [TransactionDTO]) -> [TransactionDTO] {
        transactions.sorted(by: isPreferredInFeed)
    }

    private static func isPreferredInFeed(_ lhs: TransactionDTO, _ rhs: TransactionDTO) -> Bool {
        let lhsDate = Formatters.parseTransactionDate(lhs.date) ?? .distantPast
        let rhsDate = Formatters.parseTransactionDate(rhs.date) ?? .distantPast
        if lhsDate != rhsDate {
            return lhsDate > rhsDate
        }

        if lhs.pending != rhs.pending {
            return lhs.pending
        }

        if lhs.displayAmount != rhs.displayAmount {
            return lhs.displayAmount > rhs.displayAmount
        }

        let nameComparison = lhs.displayName.localizedStandardCompare(rhs.displayName)
        if nameComparison != .orderedSame {
            return nameComparison == .orderedAscending
        }

        return lhs.id < rhs.id
    }
}

private extension Array where Element == TransactionDTO {
    var latestTransactionDate: String? {
        compactMap { transaction -> (raw: String, parsed: Date)? in
            guard let parsed = Formatters.parseTransactionDate(transaction.date) else { return nil }
            return (transaction.date, parsed)
        }
        .max { $0.parsed < $1.parsed }?
        .raw
    }
}
