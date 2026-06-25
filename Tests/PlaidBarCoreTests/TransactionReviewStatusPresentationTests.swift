import Testing
@testable import PlaidBarCore

/// Pins the per-status presentation copy (`displayName`, `glyphName`) extracted
/// from the transactions table + transaction inspector views into
/// `TransactionReviewStatus`. Both surfaces previously carried byte-identical
/// private `statusTitle`/`statusGlyph` switches; these are now the single
/// source of truth. The strings drive what the user sees, so the golden values
/// are asserted verbatim — any change is intentional and must update the test.
@Suite struct TransactionReviewStatusPresentationTests {
    @Test func displayNamePinsEveryCase() {
        #expect(TransactionReviewStatus.needsReview.displayName == "Needs review")
        #expect(TransactionReviewStatus.reviewed.displayName == "Reviewed")
        #expect(TransactionReviewStatus.ignored.displayName == "Ignored")
    }

    @Test func glyphNamePinsEveryCase() {
        #expect(TransactionReviewStatus.needsReview.glyphName == "exclamationmark.circle")
        #expect(TransactionReviewStatus.reviewed.glyphName == "checkmark.circle")
        #expect(TransactionReviewStatus.ignored.glyphName == "minus.circle")
    }

    /// Every status must yield a non-empty display name + glyph — guards against
    /// a future case being added to the enum without presentation copy.
    @Test func everyStatusHasNonEmptyPresentation() {
        for status in TransactionReviewStatus.allCases {
            #expect(!status.displayName.isEmpty)
            #expect(!status.glyphName.isEmpty)
        }
    }
}
