import Foundation

/// Opt-in preference for auto-marking high-confidence rows reviewed (AND-553,
/// DEFERRED v2 / AND-524).
///
/// **Off by default.** A user who never enables this sees the inbox behave exactly
/// as it does today: nothing is resolved on their behalf, every row waits for an
/// explicit action. Only when the user opts in does VaultPeek clear the safest,
/// most boring rows (high-confidence, already-categorized, ordinary-value, never a
/// transfer or unusual charge) so the queue holds the items that actually need a
/// human look.
public enum ReviewAutoReviewPreference: String, CaseIterable, Sendable, Identifiable {
    case off
    case on

    /// The default — auto-review disabled. A not-opted-in user gets today's
    /// behavior, byte-for-byte.
    public static let defaultValue: ReviewAutoReviewPreference = .off

    /// Stable UserDefaults key for the settings toggle (app-side `@AppStorage`).
    public static let storageKey = "reviewInbox.autoReviewHighConfidence"

    public var id: String { rawValue }

    public var isEnabled: Bool { self == .on }
}

/// Pure eligibility logic deciding which inbox rows are safe to auto-mark
/// reviewed (AND-553).
///
/// The whole value — and the whole risk — of auto-review is *what it is allowed to
/// touch*. This type encodes the conservative contract and nothing else; the app
/// applies the resulting ids through the SAME undoable batch path as a manual bulk
/// review, and flags each auto-resolved row so the user can see (and bulk-undo)
/// exactly what was cleared for them.
///
/// A row is auto-reviewable only when ALL hold:
/// 1. **High confidence** — Plaid did NOT flag the categorization LOW/UNKNOWN
///    (`!transaction.isLowConfidenceCategory`). Low-confidence rows are precisely
///    the ones a human should see, so they are never auto-cleared.
/// 2. **Categorized** — there is a real effective category that is not the
///    catch-all `.other`. An uncategorized / "Other" row needs a human.
/// 3. **Not a suggestion** — the category is a real Plaid/user category, not an
///    on-device NL/Foundation Models *suggestion* awaiting approval (a suggested
///    row carries `.uncategorized` and is not high-confidence per the inbox).
/// 4. **Ordinary value** — the row does not carry the `.unusualAmount` reason. A
///    larger-than-usual charge is exactly what the user wants to eyeball.
/// 5. **Never a transfer** — neither the resolved `isTransfer` flag nor a
///    `.possibleTransfer` reason. Transfers/card-payments are budget-affecting
///    edge cases that must stay a deliberate human decision.
///
/// Items already resolved (`status != .needsReview`) are excluded — auto-review
/// only ever clears rows that are still genuinely pending.
public enum ReviewAutoReviewPolicy {
    /// Whether a single inbox row is safe to auto-mark reviewed under the
    /// conservative contract above.
    public static func isAutoReviewable(_ item: TransactionReviewItem) -> Bool {
        // Only touch rows still genuinely needing review.
        guard item.status == .needsReview else { return false }

        // 1. High confidence — never clear what Plaid itself flagged uncertain.
        guard !item.transaction.isLowConfidenceCategory else { return false }

        // 2 + 3. A real, non-"Other" category that is NOT an on-device suggestion.
        guard let category = item.effectiveCategory,
              category != .other,
              !item.isNLSuggestedCategory
        else { return false }

        // 5. Never a transfer (resolved flag or a possible-transfer signal) and
        //    never one of the transfer categories.
        guard !item.isTransfer,
              !item.reasonCodes.contains(.possibleTransfer),
              !EffectiveCategoryResolver.isTransferCategory(category)
        else { return false }

        // 4. Ordinary value — leave larger/unusual charges for a human.
        guard !item.reasonCodes.contains(.unusualAmount) else { return false }

        // Defense in depth: a row carrying any high-priority reason (transfer,
        // pending/recurring change, changed-since-review, or unusual amount) is
        // never auto-cleared even if the specific guards above were relaxed.
        guard !item.reasonCodes.contains(where: \.isHighPriority) else { return false }

        return true
    }

    /// The transaction ids of every auto-reviewable row in `snapshot`, in the
    /// snapshot's listed order. The app marks exactly these reviewed (flagged as
    /// auto-reviewed) in a single undoable batch. Empty when nothing qualifies —
    /// so applying it is a no-op and the inbox is unchanged.
    public static func autoReviewableIDs(in snapshot: TransactionReviewInboxSnapshot) -> [String] {
        snapshot.items.filter(isAutoReviewable).map(\.id)
    }
}
