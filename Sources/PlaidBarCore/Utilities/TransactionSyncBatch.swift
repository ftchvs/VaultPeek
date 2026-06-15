import Foundation

public struct TransactionSyncBatch: Sendable {
    public private(set) var transactions: [TransactionDTO]
    public private(set) var pendingCursors: [String: String]
    public private(set) var hasChanges: Bool

    public init(
        transactions: [TransactionDTO],
        pendingCursors: [String: String] = [:],
        hasChanges: Bool = false
    ) {
        self.transactions = transactions
        self.pendingCursors = pendingCursors
        self.hasChanges = hasChanges
    }

    public mutating func apply(_ response: SyncResponse) {
        if !response.added.isEmpty || !response.modified.isEmpty || !response.removed.isEmpty {
            let updatedTransactions = TransactionSyncReducer.applying(response, to: transactions)
            if updatedTransactions != transactions {
                transactions = updatedTransactions
                hasChanges = true
            }
        }
        pendingCursors.merge(response.pendingCursors) { _, latest in latest }
    }
}
