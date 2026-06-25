import Foundation
@testable import PlaidBarCore
import Testing

@Suite("Review Auto-Review Metadata + Inbox Integration (AND-553)")
struct ReviewAutoReviewMetadataTests {
    @Test("autoReviewed defaults to false and round-trips through Codable")
    func autoReviewedRoundTrips() throws {
        var metadata = TransactionReviewMetadata(id: "tx", status: .reviewed)
        #expect(metadata.autoReviewed == false)

        metadata.autoReviewed = true
        let data = try JSONEncoder().encode(metadata)
        let decoded = try JSONDecoder().decode(TransactionReviewMetadata.self, from: data)
        #expect(decoded.autoReviewed == true)
    }

    @Test("A record written before AND-553 (no autoReviewed key) decodes as false")
    func legacyRecordDecodesFalse() throws {
        // Simulate a pre-AND-553 on-disk record: a metadata JSON object with no
        // `autoReviewed` key. The forward-compatible decode must default it to
        // false so the row is treated as a manual review, not an auto-review.
        let legacyJSON = """
        {"id":"tx-legacy","status":"reviewed","excludedFromBudgets":false,"reviewReasonCodes":[]}
        """
        let data = Data(legacyJSON.utf8)
        let decoded = try JSONDecoder().decode(TransactionReviewMetadata.self, from: data)
        #expect(decoded.autoReviewed == false)
        #expect(decoded.status == .reviewed)
    }

    @Test("evaluate threads autoReviewed metadata onto the item's wasAutoReviewed flag")
    func evaluateSurfacesAutoReviewedFlag() {
        // A charge auto-reviewed while pending that reopens after settling
        // differently must carry `wasAutoReviewed` so the UI can flag it.
        let pendingTx = TransactionDTO(
            id: "tx-1",
            accountId: "acct",
            amount: 10,
            date: "2026-06-01",
            name: "COFFEE",
            merchantName: "Coffee",
            category: .foodAndDrink,
            pending: true
        )
        let postedTx = TransactionDTO(
            id: "tx-1",
            accountId: "acct",
            amount: 25, // settled at a different amount → reopens
            date: "2026-06-01",
            name: "COFFEE",
            merchantName: "Coffee",
            category: .foodAndDrink,
            pending: false
        )
        let metadata = TransactionReviewMetadata(
            id: "tx-1",
            status: .reviewed,
            reviewedAt: Date(),
            lastSeenAmount: 10,
            lastSeenName: "COFFEE",
            lastSeenPending: true,
            autoReviewed: true
        )
        _ = pendingTx

        let snapshot = TransactionReviewInbox.evaluate(
            transactions: [postedTx],
            metadata: [metadata],
            rules: [],
            recurring: [],
            now: Date()
        )

        let item = snapshot.items.first { $0.id == "tx-1" }
        #expect(item != nil)
        #expect(item?.wasAutoReviewed == true)
    }

    @Test("evaluate default sort order is unchanged (byte-identical priority order)")
    func evaluateDefaultSortUnchanged() {
        let transactions = [
            transaction(id: "low", amount: 12, lowConfidence: true),
            transaction(id: "high", amount: 12, lowConfidence: false),
        ]
        // Same data, default vs explicit `.priority` → identical ordering, proving
        // the new parameter's default is the historical behavior.
        let implicitDefault = TransactionReviewInbox.evaluate(
            transactions: transactions, metadata: [], rules: [], recurring: [], now: Date()
        )
        let explicitPriority = TransactionReviewInbox.evaluate(
            transactions: transactions, metadata: [], rules: [], recurring: [], now: Date(), sortOrder: .priority
        )
        #expect(implicitDefault.items.map(\.id) == explicitPriority.items.map(\.id))
    }

    @Test("evaluate with confidenceLowFirst floats the low-confidence row up")
    func evaluateConfidenceSort() {
        // Two otherwise-equivalent uncategorized rows; only confidence differs.
        let transactions = [
            transaction(id: "high", amount: 12, lowConfidence: false),
            transaction(id: "low", amount: 12, lowConfidence: true),
        ]

        let priority = TransactionReviewInbox.evaluate(
            transactions: transactions, metadata: [], rules: [], recurring: [], now: Date(), sortOrder: .priority
        )
        let confidence = TransactionReviewInbox.evaluate(
            transactions: transactions, metadata: [], rules: [], recurring: [], now: Date(), sortOrder: .confidenceLowFirst
        )

        // Confidence-first must lead with the low-confidence row.
        #expect(confidence.items.first?.id == "low")
        // The two orders genuinely differ here (priority leads with id "high" by
        // the id tiebreaker), proving the sort param has an effect.
        #expect(priority.items.map(\.id) != confidence.items.map(\.id))
    }

    // MARK: - Helpers

    /// A transaction with no merchant name and a unique merchant, so it trips the
    /// `.uncategorized` (low-confidence) / `.newMerchant` reasons and surfaces in
    /// the inbox.
    private func transaction(id: String, amount: Double, lowConfidence: Bool) -> TransactionDTO {
        TransactionDTO(
            id: id,
            accountId: "acct",
            amount: amount,
            date: "2026-06-01",
            name: "Merchant \(id)",
            merchantName: "Merchant \(id)",
            category: .other,
            pending: false,
            isLowConfidenceCategory: lowConfidence
        )
    }
}
