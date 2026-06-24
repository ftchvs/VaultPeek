import Testing
@testable import PlaidBarCore

/// Pins the per-reason presentation copy (`glyphName`, `explanation`) extracted
/// from the inbox row + inspector legend views into `TransactionReviewReason`.
/// These strings drive what the user sees, so the golden values are asserted
/// verbatim — any change is intentional and must update the test.
@Suite struct TransactionReviewReasonPresentationTests {
    @Test func glyphNamePinsEveryCase() {
        #expect(TransactionReviewReason.uncategorized.glyphName == "tag")
        #expect(TransactionReviewReason.newMerchant.glyphName == "person.crop.circle.badge.questionmark")
        #expect(TransactionReviewReason.unusualAmount.glyphName == "chart.line.uptrend.xyaxis")
        #expect(TransactionReviewReason.possibleTransfer.glyphName == "arrow.left.arrow.right")
        #expect(TransactionReviewReason.recurringChanged.glyphName == "calendar.badge.exclamationmark")
        #expect(TransactionReviewReason.pendingChanged.glyphName == "clock.badge.exclamationmark")
        #expect(TransactionReviewReason.changedSinceReview.glyphName == "arrow.triangle.2.circlepath")
    }

    @Test func explanationPinsEveryCase() {
        #expect(TransactionReviewReason.uncategorized.explanation
            == "No category yet. Recategorize so it counts toward the right budget.")
        #expect(TransactionReviewReason.newMerchant.explanation
            == "First time you've seen this merchant. Confirm it's expected.")
        #expect(TransactionReviewReason.unusualAmount.explanation
            == "Larger or more unusual than this merchant's usual charges.")
        #expect(TransactionReviewReason.possibleTransfer.explanation
            == "Looks like a transfer or card payment. Mark transfer to exclude it from budgets.")
        #expect(TransactionReviewReason.recurringChanged.explanation
            == "A recurring charge changed amount or timing.")
        #expect(TransactionReviewReason.pendingChanged.explanation
            == "This pending charge changed before it posted.")
        #expect(TransactionReviewReason.changedSinceReview.explanation
            == "Changed since you last reviewed it, so it reopened.")
    }

    /// Every case must yield a non-empty glyph + explanation — guards against a
    /// future case being added to the enum without presentation copy.
    @Test func everyReasonHasNonEmptyPresentation() {
        for reason in TransactionReviewReason.allCases {
            #expect(!reason.glyphName.isEmpty)
            #expect(!reason.explanation.isEmpty)
        }
    }
}
