import Foundation

public enum AccountTransactionFeed {
    public static func transactions(
        forAccountId accountId: String,
        in transactions: [TransactionDTO]
    ) -> [TransactionDTO] {
        sortedForFeed(transactions.filter { $0.accountId == accountId })
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
