import Foundation

/// How the Review Inbox orders its rows (AND-553, DEFERRED v2 / AND-524).
///
/// The default `.priority` order is the byte-identical historical ordering: most
/// urgent reason first (`reasonCodes.priority`), then newest, then id. The new
/// `.confidenceLowFirst` order is a cheap smart-sort that floats the rows the user
/// most needs to look at — Plaid's own LOW/UNKNOWN categorizations
/// (`TransactionDTO.isLowConfidenceCategory`) — to the top, falling back to the
/// existing priority order within each confidence band so the secondary ordering
/// never changes.
///
/// Pure and `Sendable`: the ordering decision lives here (not in the view) so it
/// is unit-tested without SwiftUI and shared by every surface that lists the
/// inbox. Additive — a user who never changes the control sees `.priority`, i.e.
/// today's order exactly.
public enum ReviewInboxSortOrder: String, CaseIterable, Sendable, Identifiable {
    /// Historical order: highest-priority reason first, then newest, then id.
    case priority
    /// Low-confidence categorizations first, then the historical order within
    /// each confidence band.
    case confidenceLowFirst

    /// The default — unchanged historical order. A not-opted-in user sees this.
    public static let defaultValue: ReviewInboxSortOrder = .priority

    /// Stable UserDefaults key for the sort control (app-side `@AppStorage`).
    public static let storageKey = "reviewInbox.sortOrder"

    public var id: String { rawValue }

    /// Menu/segment label. The meaning rides this text + the control's glyph,
    /// never color alone (ACCESSIBILITY.md).
    public var title: String {
        switch self {
        case .priority: "Most urgent"
        case .confidenceLowFirst: "Low confidence first"
        }
    }

    /// SF Symbol paired with `title` so the control is legible without color.
    public var glyphName: String {
        switch self {
        case .priority: "exclamationmark.triangle"
        case .confidenceLowFirst: "questionmark.circle"
        }
    }
}

/// Pure, deterministic ordering of inbox items by a chosen `ReviewInboxSortOrder`.
///
/// Kept separate from `TransactionReviewInbox.evaluate` so the *what surfaces*
/// (heuristic detection) and the *in what order* (presentation) concerns stay
/// independent and individually testable; `evaluate` calls this for its final
/// ordering.
public enum ReviewInboxSorting {
    /// Returns `items` ordered by `order`. The historical comparator (urgency →
    /// newest → id) is the tiebreaker in every order, so two items that share a
    /// confidence band keep today's relative order exactly.
    public static func sorted(
        _ items: [TransactionReviewItem],
        order: ReviewInboxSortOrder
    ) -> [TransactionReviewItem] {
        switch order {
        case .priority:
            items.sorted(by: priorityLess)
        case .confidenceLowFirst:
            items.sorted { lhs, rhs in
                let lhsLow = lhs.transaction.isLowConfidenceCategory
                let rhsLow = rhs.transaction.isLowConfidenceCategory
                // Low-confidence rows float up; within the same confidence band
                // fall back to the historical comparator so nothing else reorders.
                if lhsLow != rhsLow { return lhsLow && !rhsLow }
                return priorityLess(lhs, rhs)
            }
        }
    }

    /// The historical inbox comparator, extracted verbatim from
    /// `TransactionReviewInbox.evaluate` so the default order is bit-for-bit
    /// unchanged and the confidence order can reuse it as its in-band tiebreaker.
    static func priorityLess(_ lhs: TransactionReviewItem, _ rhs: TransactionReviewItem) -> Bool {
        let lhsPriority = lhs.reasonCodes.map(\.priority).min() ?? Int.max
        let rhsPriority = rhs.reasonCodes.map(\.priority).min() ?? Int.max
        if lhsPriority != rhsPriority { return lhsPriority < rhsPriority }
        if lhs.transaction.date != rhs.transaction.date { return lhs.transaction.date > rhs.transaction.date }
        return lhs.id < rhs.id
    }
}
