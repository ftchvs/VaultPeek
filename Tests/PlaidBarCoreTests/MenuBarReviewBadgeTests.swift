import Testing
@testable import PlaidBarCore

@Suite("MenuBarReviewBadge")
struct MenuBarReviewBadgeTests {
    // MARK: count → badge string

    @Test("A positive unmasked count renders that number as the badge string")
    func positiveCountRendersNumber() {
        #expect(MenuBarReviewBadge.text(unreviewedCount: 1, isMasked: false) == "1")
        #expect(MenuBarReviewBadge.text(unreviewedCount: 7, isMasked: false) == "7")
        #expect(MenuBarReviewBadge.text(unreviewedCount: 42, isMasked: false) == "42")
        #expect(MenuBarReviewBadge.text(unreviewedCount: 99, isMasked: false) == "99")
    }

    @Test("Counts above the cap render as the capped overflow string")
    func largeCountIsCapped() {
        #expect(MenuBarReviewBadge.text(unreviewedCount: 100, isMasked: false) == "99+")
        #expect(MenuBarReviewBadge.text(unreviewedCount: 1234, isMasked: false) == "99+")
    }

    // MARK: zero → hidden

    @Test("A zero count hides the badge")
    func zeroHidesBadge() {
        #expect(MenuBarReviewBadge.text(unreviewedCount: 0, isMasked: false) == nil)
        #expect(MenuBarReviewBadge.isVisible(unreviewedCount: 0, isMasked: false) == false)
    }

    @Test("A negative count (defensive) hides the badge")
    func negativeHidesBadge() {
        #expect(MenuBarReviewBadge.text(unreviewedCount: -3, isMasked: false) == nil)
        #expect(MenuBarReviewBadge.isVisible(unreviewedCount: -3, isMasked: false) == false)
    }

    // MARK: masked → hidden (withheld under Privacy Mask)

    @Test("Privacy Mask withholds the badge even with a positive count")
    func maskedHidesBadge() {
        #expect(MenuBarReviewBadge.text(unreviewedCount: 5, isMasked: true) == nil)
        #expect(MenuBarReviewBadge.text(unreviewedCount: 100, isMasked: true) == nil)
        #expect(MenuBarReviewBadge.isVisible(unreviewedCount: 5, isMasked: true) == false)
    }

    @Test("Masked-and-zero is still hidden")
    func maskedZeroHidesBadge() {
        #expect(MenuBarReviewBadge.text(unreviewedCount: 0, isMasked: true) == nil)
    }

    // MARK: isVisible mirrors text presence

    @Test("isVisible is true exactly when text is non-nil")
    func visibilityMirrorsText() {
        #expect(MenuBarReviewBadge.isVisible(unreviewedCount: 3, isMasked: false) == true)
        #expect(MenuBarReviewBadge.isVisible(unreviewedCount: 99, isMasked: false) == true)
        #expect(MenuBarReviewBadge.isVisible(unreviewedCount: 100, isMasked: false) == true)
    }

    // MARK: accessibility label

    @Test("Accessibility label pluralizes and reads the real count, not the capped string")
    func accessibilityLabelReadsRealCount() {
        #expect(MenuBarReviewBadge.accessibilityLabel(unreviewedCount: 1, isMasked: false)
            == "1 transaction to review")
        #expect(MenuBarReviewBadge.accessibilityLabel(unreviewedCount: 4, isMasked: false)
            == "4 transactions to review")
        // Even when the visible badge caps at "99+", the spoken label uses the true count.
        #expect(MenuBarReviewBadge.accessibilityLabel(unreviewedCount: 250, isMasked: false)
            == "250 transactions to review")
    }

    @Test("Accessibility label is nil when the badge is hidden")
    func accessibilityLabelNilWhenHidden() {
        #expect(MenuBarReviewBadge.accessibilityLabel(unreviewedCount: 0, isMasked: false) == nil)
        #expect(MenuBarReviewBadge.accessibilityLabel(unreviewedCount: 9, isMasked: true) == nil)
    }
}
