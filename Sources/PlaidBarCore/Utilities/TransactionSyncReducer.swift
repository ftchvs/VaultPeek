import Foundation

public enum TransactionSyncReducer {
    public static func applying(
        _ response: SyncResponse,
        to transactions: [TransactionDTO]
    ) -> [TransactionDTO] {
        var transactionsById: [String: TransactionDTO] = [:]
        var orderedIds: [String] = []

        for transaction in transactions {
            if transactionsById[transaction.id] == nil {
                orderedIds.append(transaction.id)
            }
            transactionsById[transaction.id] = transaction
        }

        for transaction in response.added + response.modified {
            if transactionsById[transaction.id] == nil {
                orderedIds.append(transaction.id)
            }
            transactionsById[transaction.id] = transaction
        }

        let removedIds = Set(response.removed)
        if !removedIds.isEmpty {
            orderedIds.removeAll { removedIds.contains($0) }
            for id in removedIds {
                transactionsById.removeValue(forKey: id)
            }
        }

        return orderedIds.compactMap { transactionsById[$0] }
    }
}
