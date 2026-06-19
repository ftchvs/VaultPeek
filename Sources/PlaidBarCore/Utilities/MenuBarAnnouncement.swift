import Foundation

/// Pure derivation of the menu-bar item's hover tooltip ("help") text and its
/// VoiceOver accessibility label.
///
/// Extracted from `AppState` so the wording is `Sendable`, unit-tested, and the
/// per-mode noun comes from a single source of truth (`MenuBarSummaryMode`)
/// rather than two hand-maintained switch statements. The tooltip uses the
/// mode's `displayName` ("Net worth", "Today's spend"); the spoken label uses its
/// lowercased form ("net worth", "today's spend" — the apostrophe is preserved),
/// matching the previous inline behavior exactly.
public enum MenuBarAnnouncement {

    /// Tooltip shown when hovering the menu-bar item.
    ///
    /// - Parameters:
    ///   - mode: which summary the menu bar is currently showing.
    ///   - valueText: the rendered menu-bar value (e.g. `"$1,234"`).
    ///   - reviewCount: number of transactions awaiting review.
    ///   - diagnosticsSummary: short health string (e.g. `"All good"`).
    ///   - weeklyReviewPrompt: optional weekly-review nudge.
    public static func helpText(
        mode: MenuBarSummaryMode,
        valueText: String,
        reviewCount: Int,
        diagnosticsSummary: String,
        weeklyReviewPrompt: String?
    ) -> String {
        let review = reviewCount > 0 ? " \(reviewPhrase(reviewCount)) need review." : ""
        let status = "Status: \(diagnosticsSummary)"
        let weekly = weeklyReviewPrompt.map { " Weekly review: \($0)." } ?? ""
        switch mode {
        case .iconOnly:
            return "VaultPeek.\(review) \(status)\(weekly)"
        default:
            return "VaultPeek - \(mode.displayName): \(valueText).\(review) \(status)\(weekly)"
        }
    }

    /// VoiceOver label for the menu-bar item.
    ///
    /// Unlike the tooltip, the spoken label folds the visible finance attention
    /// badge into the status (`diagnosticsSummary` stays "healthy" for finance
    /// warnings, so the badge sighted users see must be spoken explicitly).
    ///
    /// - Parameters:
    ///   - mode: which summary the menu bar is currently showing.
    ///   - valueText: the rendered menu-bar value (e.g. `"$1,234"`).
    ///   - reviewCount: number of transactions awaiting review.
    ///   - diagnosticsSummary: short health string (e.g. `"All good"`).
    ///   - attentionText: optional finance attention badge to speak.
    ///   - weeklyReviewPrompt: optional weekly-review nudge.
    public static func accessibilityLabel(
        mode: MenuBarSummaryMode,
        valueText: String,
        reviewCount: Int,
        diagnosticsSummary: String,
        attentionText: String?,
        weeklyReviewPrompt: String?
    ) -> String {
        let review = reviewCount > 0 ? "\(reviewPhrase(reviewCount)) need review. " : ""
        let attention = attentionText.map { ". Attention \($0)" } ?? ""
        let status = "Status \(diagnosticsSummary)\(attention)"
        let weekly = weeklyReviewPrompt.map { " Weekly review \($0)." } ?? ""
        switch mode {
        case .iconOnly:
            return "VaultPeek. \(review)\(status)\(weekly)"
        default:
            return "VaultPeek \(mode.displayName.lowercased()) \(valueText). \(review)\(status)\(weekly)"
        }
    }

    /// `"1 transaction"` / `"3 transactions"` — the shared, pluralized count phrase.
    ///
    /// Only the count phrase is shared; the surrounding spacing is intentionally
    /// asymmetric and lives at each call site — the tooltip wraps it with a leading
    /// space (`" … need review."`) while the spoken label uses a trailing space
    /// (`"… need review. "`). Keep that split when editing.
    private static func reviewPhrase(_ count: Int) -> String {
        "\(count) transaction\(count == 1 ? "" : "s")"
    }
}
