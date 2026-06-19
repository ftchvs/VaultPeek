import Foundation
@testable import PlaidBarCore
import Testing

@Suite("MenuBarAnnouncement Tests")
struct MenuBarAnnouncementTests {
    // MARK: - Help text (tooltip)

    @Test("Help text: value mode, no review, no weekly prompt")
    func helpTextBaseline() {
        let text = MenuBarAnnouncement.helpText(
            mode: .netWorth,
            valueText: "$1,234",
            reviewCount: 0,
            diagnosticsSummary: "All good",
            weeklyReviewPrompt: nil
        )
        #expect(text == "VaultPeek - Net worth: $1,234. Status: All good")
    }

    @Test("Help text: review count + weekly prompt are appended")
    func helpTextWithReviewAndWeekly() {
        let text = MenuBarAnnouncement.helpText(
            mode: .netCash,
            valueText: "$500",
            reviewCount: 3,
            diagnosticsSummary: "Sync stale",
            weeklyReviewPrompt: "ready"
        )
        #expect(text == "VaultPeek - Net cash: $500. 3 transactions need review. Status: Sync stale Weekly review: ready.")
    }

    @Test("Help text: icon-only mode omits the value noun")
    func helpTextIconOnly() {
        let text = MenuBarAnnouncement.helpText(
            mode: .iconOnly,
            valueText: "(ignored)",
            reviewCount: 1,
            diagnosticsSummary: "OK",
            weeklyReviewPrompt: nil
        )
        // Singular "transaction" for a count of 1.
        #expect(text == "VaultPeek. 1 transaction need review. Status: OK")
    }

    // MARK: - Accessibility label

    @Test("Accessibility label: value mode, no review, no attention, no weekly")
    func accessibilityBaseline() {
        let label = MenuBarAnnouncement.accessibilityLabel(
            mode: .netWorth,
            valueText: "$1,234",
            reviewCount: 0,
            diagnosticsSummary: "All good",
            attentionText: nil,
            weeklyReviewPrompt: nil
        )
        #expect(label == "VaultPeek net worth $1,234. Status All good")
    }

    @Test("Accessibility label: folds attention badge into spoken status")
    func accessibilityWithAttentionReviewWeekly() {
        let label = MenuBarAnnouncement.accessibilityLabel(
            mode: .safeToSpend,
            valueText: "$200",
            reviewCount: 2,
            diagnosticsSummary: "Healthy",
            attentionText: "Credit high",
            weeklyReviewPrompt: "due"
        )
        #expect(label == "VaultPeek safe to spend $200. 2 transactions need review. Status Healthy. Attention Credit high Weekly review due.")
    }

    @Test("Accessibility label: icon-only mode omits the value noun")
    func accessibilityIconOnly() {
        let label = MenuBarAnnouncement.accessibilityLabel(
            mode: .iconOnly,
            valueText: "(ignored)",
            reviewCount: 0,
            diagnosticsSummary: "OK",
            attentionText: nil,
            weeklyReviewPrompt: nil
        )
        #expect(label == "VaultPeek. Status OK")
    }

    // MARK: - Golden noun literals (catch copy drift, independent of displayName)

    /// Pins the EXACT tooltip/VoiceOver wording for every value mode. Because the
    /// nouns flow from `MenuBarSummaryMode.displayName` — which also drives the
    /// Settings picker — a re-word there for UI reasons would otherwise silently
    /// change accessibility copy. These literals fail loudly if that happens.
    @Test("Golden noun literals for every value mode")
    func goldenNounLiterals() {
        let cases: [(mode: MenuBarSummaryMode, help: String, spoken: String)] = [
            (.netWorth, "Net worth", "net worth"),
            (.netCash, "Net cash", "net cash"),
            (.totalCash, "Total cash", "total cash"),
            (.creditUtilization, "Credit utilization", "credit utilization"),
            (.highestUtilization, "Highest card utilization", "highest card utilization"),
            (.recentSpend, "Recent spend", "recent spend"),
            (.todaySpend, "Today's spend", "today's spend"),
            (.safeToSpend, "Safe to spend", "safe to spend"),
        ]
        for (mode, helpNoun, spokenNoun) in cases {
            #expect(MenuBarAnnouncement.helpText(
                mode: mode,
                valueText: "V",
                reviewCount: 0,
                diagnosticsSummary: "D",
                weeklyReviewPrompt: nil
            ) == "VaultPeek - \(helpNoun): V. Status: D")
            #expect(MenuBarAnnouncement.accessibilityLabel(
                mode: mode,
                valueText: "V",
                reviewCount: 0,
                diagnosticsSummary: "D",
                attentionText: nil,
                weeklyReviewPrompt: nil
            ) == "VaultPeek \(spokenNoun) V. Status D")
        }
    }
}
