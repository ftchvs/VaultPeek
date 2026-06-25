import Foundation
@testable import PlaidBarCore
import Testing

@Suite("Review Inbox Sorting Tests (AND-553)")
struct ReviewInboxSortingTests {
    @Test("Default sort order is the historical priority order")
    func defaultIsPriority() {
        #expect(ReviewInboxSortOrder.defaultValue == .priority)
    }

    @Test("Priority order keeps the historical comparator: urgency, then newest, then id")
    func priorityOrder() {
        // Two `.uncategorized` (priority 2) rows and one `.possibleTransfer`
        // (priority 0). The high-priority one must float to the top regardless of
        // its date; within the same priority, newer date wins, then id.
        let items = [
            item(id: "old-low", date: "2026-06-01", reasons: [.uncategorized]),
            item(id: "transfer", date: "2026-05-01", reasons: [.possibleTransfer]),
            item(id: "new-low", date: "2026-06-10", reasons: [.uncategorized]),
        ]

        let sorted = ReviewInboxSorting.sorted(items, order: .priority)

        #expect(sorted.map(\.id) == ["transfer", "new-low", "old-low"])
    }

    @Test("Confidence-first floats low-confidence rows to the top")
    func confidenceFirstFloatsLowConfidence() {
        let items = [
            item(id: "high-1", reasons: [.uncategorized], lowConfidence: false),
            item(id: "low-1", reasons: [.uncategorized], lowConfidence: true),
            item(id: "high-2", reasons: [.uncategorized], lowConfidence: false),
            item(id: "low-2", reasons: [.uncategorized], lowConfidence: true),
        ]

        let sorted = ReviewInboxSorting.sorted(items, order: .confidenceLowFirst)

        // Both low-confidence rows precede both high-confidence rows.
        let lowFirst = sorted.prefix(2).map(\.id)
        #expect(Set(lowFirst) == ["low-1", "low-2"])
        #expect(Set(sorted.suffix(2).map(\.id)) == ["high-1", "high-2"])
    }

    @Test("Within a confidence band, confidence-first falls back to the historical order")
    func confidenceFirstInBandTiebreaker() {
        // All low-confidence; the in-band order must match the priority comparator
        // (urgency → newest → id), so the secondary ordering never changes.
        let items = [
            item(id: "low-old-uncat", date: "2026-06-01", reasons: [.uncategorized], lowConfidence: true),
            item(id: "low-transfer", date: "2026-05-01", reasons: [.possibleTransfer], lowConfidence: true),
            item(id: "low-new-uncat", date: "2026-06-10", reasons: [.uncategorized], lowConfidence: true),
        ]

        let confidence = ReviewInboxSorting.sorted(items, order: .confidenceLowFirst)
        let priority = ReviewInboxSorting.sorted(items, order: .priority)

        // Same band for all → identical to the historical order.
        #expect(confidence.map(\.id) == priority.map(\.id))
        #expect(confidence.map(\.id) == ["low-transfer", "low-new-uncat", "low-old-uncat"])
    }

    @Test("Confidence-first prefers a low-confidence row even over a higher-priority high-confidence row")
    func confidenceBeatsPriorityAcrossBands() {
        // A high-confidence high-priority transfer vs a low-confidence ordinary
        // uncategorized: confidence-first puts the low-confidence row first, since
        // confidence is the primary key across bands.
        let items = [
            item(id: "high-transfer", reasons: [.possibleTransfer], lowConfidence: false),
            item(id: "low-uncat", reasons: [.uncategorized], lowConfidence: true),
        ]

        let sorted = ReviewInboxSorting.sorted(items, order: .confidenceLowFirst)
        #expect(sorted.map(\.id) == ["low-uncat", "high-transfer"])
    }

    @Test("Sorting is stable and deterministic across repeated calls")
    func deterministic() {
        let items = (1 ... 6).map { item(id: "id-\($0)", reasons: [.uncategorized], lowConfidence: $0.isMultiple(of: 2)) }
        let a = ReviewInboxSorting.sorted(items, order: .confidenceLowFirst).map(\.id)
        let b = ReviewInboxSorting.sorted(items, order: .confidenceLowFirst).map(\.id)
        #expect(a == b)
    }

    // MARK: - Helpers

    private func item(
        id: String,
        date: String = "2026-06-01",
        reasons: [TransactionReviewReason],
        lowConfidence: Bool = false
    ) -> TransactionReviewItem {
        TransactionReviewItem(
            transaction: TransactionDTO(
                id: id,
                accountId: "acct",
                amount: 12,
                date: date,
                name: id.uppercased(),
                merchantName: id,
                category: .foodAndDrink,
                pending: false,
                isLowConfidenceCategory: lowConfidence
            ),
            status: .needsReview,
            reasonCodes: reasons,
            effectiveCategory: .foodAndDrink,
            effectiveMerchantName: id,
            isTransfer: false,
            excludedFromBudgets: false,
            matchedRuleIds: []
        )
    }
}
