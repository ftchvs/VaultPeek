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
            self.init(entries: TransactionDerivedIndex(transactions: transactions).entries)
        }

        public init(entries: [TransactionDerivedIndex.Entry]) {
            let sortedEntries = entries.sorted(by: TransactionDerivedIndex.isPreferredInFeed)
            self.transactions = sortedEntries.map(\.transaction)
            self.transactionCount = entries.count
            self.pendingTransactionCount = entries.count(where: { $0.transaction.pending })
            self.latestTransactionDate = entries.latestTransactionDate
            self.recentSummary = AccountActivitySummary.recent(from: sortedEntries)
        }
    }

    public static func activitySnapshot(
        forAccountId accountId: String,
        in transactions: [TransactionDTO]
    ) -> AccountActivitySnapshot {
        activitySnapshot(
            forAccountId: accountId,
            in: TransactionDerivedIndex(transactions: transactions)
        )
    }

    public static func activitySnapshot(
        forAccountId accountId: String,
        in index: TransactionDerivedIndex
    ) -> AccountActivitySnapshot {
        AccountActivitySnapshot(entries: index.entries(forAccountId: accountId))
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
        relatedMerchantTransactions(
            merchantName: merchantName,
            excluding: transactionId,
            in: TransactionDerivedIndex(transactions: transactions)
        )
    }

    public static func relatedMerchantTransactions(
        merchantName: String,
        excluding transactionId: String,
        in index: TransactionDerivedIndex
    ) -> [TransactionDTO] {
        index.sortedForFeed(
            index.entries(forMerchantName: merchantName).filter { $0.transaction.id != transactionId }
        )
        .map(\.transaction)
    }

    public static func sortedForFeed(_ transactions: [TransactionDTO]) -> [TransactionDTO] {
        let index = TransactionDerivedIndex(transactions: transactions)
        return index.sortedForFeed(index.entries).map(\.transaction)
    }
}

private extension Array where Element == TransactionDerivedIndex.Entry {
    var latestTransactionDate: String? {
        compactMap { entry -> (raw: String, parsed: Date)? in
            guard let parsed = entry.parsedDate else { return nil }
            return (entry.rawDate, parsed)
        }
        .max { $0.parsed < $1.parsed }?
        .raw
    }
}
