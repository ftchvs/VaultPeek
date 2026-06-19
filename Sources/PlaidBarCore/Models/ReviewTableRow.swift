import Foundation

/// One row of the detached **review Table** (AND-532) — the power-review surface
/// that pulls the popover's Review Inbox off into a resizable, multi-select
/// `Table` (spec §3/§5, Option A). A row is the flat, `Sendable`, testable
/// projection of a ``TransactionReviewItem``: the columns the table shows
/// (merchant, amount, date, category, reason) plus the provenance flags the
/// renderer needs (transfer, on-device NL suggestion).
///
/// All money/merchant text is exposed both raw (so the `Table` can sort) and as a
/// privacy-mask-aware string (so the view stays a thin renderer and the window
/// withholds figures under Privacy Mask / App Lock). The category is carried as a
/// ``CategoryPillModel`` so the table's category pill matches the inbox's exactly
/// — same title, glyph, and accent — and never conveys the category by color alone
/// (ACCESSIBILITY.md). The reason summary is plain text, so "why is this here"
/// always reads, never as an unlabeled color.
public struct ReviewTableRow: Sendable, Hashable, Identifiable {
    /// Stable identity — the transaction id, also the `Table` row id and the id the
    /// existing AppState review actions key off.
    public let id: String
    /// Effective (user-renamed → Plaid → raw) merchant name.
    public let merchantName: String
    /// Absolute display amount (always positive), so the `Table` sorts numerically.
    public let amount: Double
    /// Raw transaction date string (`YYYY-MM-DD`), for the formatted date column.
    public let dateString: String
    /// The effective category, or `nil` for an uncategorized row.
    public let category: SpendingCategory?
    /// The category pill contract — title + glyph + accent hex, shared with the
    /// inbox pill so the two never drift.
    public let categoryPill: CategoryPillModel
    /// Reason codes (e.g. "Needs category", "New merchant"), display order.
    public let reasonCodes: [TransactionReviewReason]
    /// True when the row is a transfer (override or transfer category) — drives a
    /// text+glyph transfer badge, never color alone.
    public let isTransfer: Bool
    /// True when `category` was filled by the on-device NL tier (AND-507) rather
    /// than the user or Plaid — drives a text+glyph "Suggested" badge.
    public let isNLSuggested: Bool

    public init(item: TransactionReviewItem) {
        self.id = item.id
        self.merchantName = item.effectiveMerchantName
        self.amount = item.transaction.displayAmount
        self.dateString = item.transaction.date
        self.category = item.effectiveCategory
        self.categoryPill = CategoryPillModel.make(category: item.effectiveCategory)
        self.reasonCodes = item.reasonCodes
        self.isTransfer = item.isTransfer
        self.isNLSuggested = item.isNLSuggestedCategory
    }

    /// Category label — the pill title (the neutral "Uncategorized" when nil), the
    /// text layer that always carries the category meaning.
    public var categoryTitle: String { categoryPill.title }

    /// Category glyph — the pill glyph (the neutral tag when uncategorized).
    public var categoryGlyph: String { categoryPill.glyph }

    /// Comma-joined reason display names — the plain-text "why this row is here"
    /// (never an unlabeled color). Empty string when a row carries no reasons.
    public var reasonSummary: String {
        reasonCodes.map(\.displayName).joined(separator: ", ")
    }

    /// Formatted, privacy-mask-aware amount string for the Amount column.
    public func amountText(isMasked: Bool) -> String {
        PrivacyMaskPresentation.currency(amount, format: .full, isEnabled: isMasked, style: .compact)
    }

    /// Privacy-mask-aware merchant string — withheld under mask, since a merchant
    /// name can identify spend just as an amount can.
    public func merchantText(isMasked: Bool) -> String {
        PrivacyMaskPresentation.value(merchantName, isEnabled: isMasked, style: .compact)
    }

    /// Formatted date string for the Date column (delegates to the shared formatter).
    public var dateText: String {
        Formatters.displayTransactionDate(dateString)
    }

    /// Builds rows from inbox items, preserving list order (the order the table and
    /// the priority-sorted snapshot agree on).
    public static func rows(from items: [TransactionReviewItem]) -> [ReviewTableRow] {
        items.map(ReviewTableRow.init(item:))
    }
}

/// The review Table's user-selectable sort (AND-532). A small `Sendable` enum so
/// it can live in SwiftUI `@State` under strict concurrency — a `[KeyPathComparator]`
/// cannot. Sorting runs through the pure ``sorted(_:)`` comparator (no `KeyPath`,
/// so nothing non-`Sendable` leaks), keeping the order deterministic and testable.
public enum ReviewTableSort: String, Sendable, CaseIterable, Hashable {
    case amountDescending
    case amountAscending
    case dateDescending
    case merchant
    case category

    /// The Picker label for this sort.
    public var label: String {
        switch self {
        case .amountDescending: "Amount (high to low)"
        case .amountAscending: "Amount (low to high)"
        case .dateDescending: "Date (newest first)"
        case .merchant: "Merchant (A–Z)"
        case .category: "Category (A–Z)"
        }
    }

    /// Sorts rows by this order. Ties break on the stable row id so the order is
    /// fully deterministic (no incidental reordering between renders).
    public func sorted(_ rows: [ReviewTableRow]) -> [ReviewTableRow] {
        rows.sorted { lhs, rhs in
            switch self {
            case .amountDescending:
                if lhs.amount != rhs.amount { return lhs.amount > rhs.amount }
            case .amountAscending:
                if lhs.amount != rhs.amount { return lhs.amount < rhs.amount }
            case .dateDescending:
                if lhs.dateString != rhs.dateString { return lhs.dateString > rhs.dateString }
            case .merchant:
                let cmp = lhs.merchantName.localizedCaseInsensitiveCompare(rhs.merchantName)
                if cmp != .orderedSame { return cmp == .orderedAscending }
            case .category:
                let cmp = lhs.categoryTitle.localizedCaseInsensitiveCompare(rhs.categoryTitle)
                if cmp != .orderedSame { return cmp == .orderedAscending }
            }
            return lhs.id < rhs.id
        }
    }
}

/// Pure description of the *blast radius* of a bulk **recategorize** across a
/// multi-select review `Table` selection (AND-532, sub 556).
///
/// Bulk recategorize applies one chosen ``SpendingCategory`` to every selected row.
/// Like ``ReviewBulkActionPlan`` (the bulk *mark-reviewed* counterpart), it makes
/// the scope explicit *before* applying — how many rows, which merchants, and which
/// category — so a single action never silently moves more than the user selected,
/// and the announced "which" matches the visible list. It has no SwiftUI / AppState
/// dependency, so the "which rows + which category" decision is unit-testable.
///
/// Scope rule: the radius is the intersection of the explicit selection with the
/// currently-listed rows, in **list order** (selection order never leaks), so a
/// stale id (a row that already left the table) can never recategorize a
/// transaction that is no longer shown. The application itself reuses the existing
/// per-row `updateReviewCategory` AppState path for each affected id (state blast
/// radius), so bulk and single recategorize can never diverge in meaning.
public struct ReviewBulkRecategorizePlan: Sendable, Equatable {
    /// Transaction ids that will be recategorized, in table-list order.
    public let affectedIDs: [String]
    /// Merchant names of the affected rows, list order, for the "which" preview.
    public let affectedMerchantNames: [String]
    /// The category to apply to every affected row.
    public let category: SpendingCategory

    public var count: Int { affectedIDs.count }
    public var isEmpty: Bool { affectedIDs.isEmpty }

    public init(affectedIDs: [String], affectedMerchantNames: [String], category: SpendingCategory) {
        self.affectedIDs = affectedIDs
        self.affectedMerchantNames = affectedMerchantNames
        self.category = category
    }

    /// Computes the recategorize blast radius for a `Table` selection.
    ///
    /// - Parameters:
    ///   - rows: the rows currently listed in the table (already the visible set).
    ///   - selection: the user's multi-select set of row ids.
    ///   - category: the category to apply.
    public static func make(
        rows: [ReviewTableRow],
        selection: Set<String>,
        category: SpendingCategory
    ) -> ReviewBulkRecategorizePlan {
        let scoped = rows.filter { selection.contains($0.id) }
        return ReviewBulkRecategorizePlan(
            affectedIDs: scoped.map(\.id),
            affectedMerchantNames: scoped.map(\.merchantName),
            category: category
        )
    }

    /// Plain-language description of which rows resolve and to which category —
    /// count first, then the category, then a bounded list of merchant names — for a
    /// confirmation prompt and a VoiceOver announcement, so meaning never rides on a
    /// bare number or color alone.
    ///
    /// - Parameter previewLimit: how many merchant names to spell out before
    ///   collapsing the rest into "and N more".
    public func blastRadiusDescription(previewLimit: Int = 3) -> String {
        guard count > 0 else { return "No transactions to recategorize" }
        let noun = count == 1 ? "transaction" : "transactions"
        let names = affectedMerchantNames.prefix(max(previewLimit, 0))
        let remainder = count - names.count
        let head = "Set \(count) \(noun) to \(category.displayName)"
        guard !names.isEmpty else { return head }
        var preview = names.joined(separator: ", ")
        if remainder > 0 {
            preview += ", and \(remainder) more"
        }
        return "\(head): \(preview)"
    }
}
