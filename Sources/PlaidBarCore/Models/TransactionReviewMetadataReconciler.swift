import Foundation

public enum TransactionReviewMetadataReconciler {
    public static func reconcilePostedPendingTransactions(
        transactions: [TransactionDTO],
        metadata: [TransactionReviewMetadata]
    ) -> [TransactionReviewMetadata] {
        var byId = Dictionary(uniqueKeysWithValues: metadata.map { ($0.id, $0) })
        var changed = false

        for transaction in transactions where transaction.pending == false {
            guard let pendingId = transaction.pendingTransactionId,
                  pendingId != transaction.id,
                  let pendingMetadata = byId[pendingId]
            else { continue }

            var postedMetadata = byId[transaction.id] ?? TransactionReviewMetadata(id: transaction.id)
            let hadPostedResolution = postedMetadata.status == .reviewed || postedMetadata.status == .ignored
            guard !hadPostedResolution else { continue }

            let didSettleDifferently = pendingSettledDifferently(transaction, baseline: pendingMetadata)
            postedMetadata.status = didSettleDifferently ? .needsReview : pendingMetadata.status
            postedMetadata.userCategory = pendingMetadata.userCategory
            postedMetadata.userMerchantName = pendingMetadata.userMerchantName
            postedMetadata.isTransferOverride = pendingMetadata.isTransferOverride
            postedMetadata.excludedFromBudgets = pendingMetadata.excludedFromBudgets
            postedMetadata.reviewedAt = didSettleDifferently ? nil : pendingMetadata.reviewedAt
            postedMetadata.reviewReasonCodes = didSettleDifferently ? [.pendingChanged] : pendingMetadata.reviewReasonCodes
            postedMetadata.lastSeenAmount = transaction.amount
            postedMetadata.lastSeenName = transaction.name
            postedMetadata.lastSeenPending = transaction.pending

            byId[transaction.id] = postedMetadata
            byId.removeValue(forKey: pendingId)
            changed = true
        }

        guard changed else { return metadata.sorted { $0.id < $1.id } }
        return byId.values.sorted { $0.id < $1.id }
    }

    private static func pendingSettledDifferently(
        _ transaction: TransactionDTO,
        baseline: TransactionReviewMetadata
    ) -> Bool {
        guard baseline.lastSeenPending == true else { return false }
        let amountChanged = baseline.lastSeenAmount.map { abs($0 - transaction.amount) >= 0.01 } ?? false
        let nameChanged = baseline.lastSeenName.map { $0 != transaction.name } ?? false
        return amountChanged || nameChanged
    }
}
