import Foundation

/// Pure derivation of the NSStatusItem menu-bar badge for the unreviewed
/// review-inbox count (AND-534).
///
/// The badge is the small overlay drawn on the menu-bar status item's button
/// (a custom `NSStatusItem` per the documented `MenuBarExtra`-glass constraint —
/// see the delivery design §4/§7). Extracting the visibility/text rules here
/// keeps them `Sendable`, unit-tested, and out of the AppKit drawing code, which
/// then only renders whatever string this returns (or nothing when `nil`).
///
/// Rules (all enforced by tests):
/// - **Zero or negative count → hidden** (`nil`): a "0" badge is noise.
/// - **Privacy Mask on → withheld** (`nil`): the unreviewed count is a financial
///   signal, so it is suppressed under the mask exactly like balances/amounts.
/// - **Otherwise → the count**, capped at `"99+"` so the badge never grows wide
///   enough to crowd the menu bar.
///
/// Meaning is carried by the number itself (and the spoken accessibility label),
/// never by color alone (`ACCESSIBILITY.md`).
public enum MenuBarReviewBadge {

    /// Counts at or above this threshold render as the capped overflow string
    /// rather than their literal value, keeping the badge a stable width.
    public static let overflowThreshold = 100

    /// The capped overflow string shown for counts at/above `overflowThreshold`.
    public static let overflowText = "99+"

    /// The badge text to draw on the status item, or `nil` when the badge must
    /// be hidden (zero/negative count, or Privacy Mask engaged).
    ///
    /// - Parameters:
    ///   - unreviewedCount: number of transactions awaiting review.
    ///   - isMasked: whether Privacy Mask / App Lock is hiding financial values.
    public static func text(unreviewedCount: Int, isMasked: Bool) -> String? {
        guard isVisible(unreviewedCount: unreviewedCount, isMasked: isMasked) else { return nil }
        return unreviewedCount >= overflowThreshold ? overflowText : "\(unreviewedCount)"
    }

    /// Whether the badge should be drawn at all. `true` exactly when
    /// `text(unreviewedCount:isMasked:)` is non-nil.
    public static func isVisible(unreviewedCount: Int, isMasked: Bool) -> Bool {
        guard !isMasked else { return false }
        return unreviewedCount > 0
    }

    /// VoiceOver label spoken for the badge, or `nil` when the badge is hidden.
    ///
    /// Unlike the visible string this always reads the *true* count (never the
    /// capped `"99+"`) and pluralizes "transaction".
    public static func accessibilityLabel(unreviewedCount: Int, isMasked: Bool) -> String? {
        guard isVisible(unreviewedCount: unreviewedCount, isMasked: isMasked) else { return nil }
        let noun = unreviewedCount == 1 ? "transaction" : "transactions"
        return "\(unreviewedCount) \(noun) to review"
    }
}
