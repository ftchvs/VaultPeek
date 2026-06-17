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

        let incoming = response.added + response.modified
        for transaction in incoming {
            if transactionsById[transaction.id] == nil {
                orderedIds.append(transaction.id)
            }
            transactionsById[transaction.id] = transaction
        }

        var removedIds = Set(response.removed)

        // Reconcile pending -> posted: when a posted transaction carries the id of the
        // pending transaction it supersedes, drop that pending row even if Plaid omits
        // the explicit `removed` entry. Otherwise the pending and posted rows double-count.
        for transaction in incoming where !transaction.pending {
            if let pendingId = transaction.pendingTransactionId, pendingId != transaction.id {
                removedIds.insert(pendingId)
            }
        }

        if !removedIds.isEmpty {
            orderedIds.removeAll { removedIds.contains($0) }
            for id in removedIds {
                transactionsById.removeValue(forKey: id)
            }
        }

        return orderedIds.compactMap { transactionsById[$0] }
    }
}
