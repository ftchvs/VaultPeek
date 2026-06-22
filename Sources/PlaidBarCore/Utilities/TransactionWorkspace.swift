import Foundation

/// Pure, value-type model for the **Transaction Workspace** (AND-582, Epic 4) —
/// the window-first ledger's filter/search/sort state and the row view-model its
/// `Table` renders.
///
/// All of this lives in PlaidBarCore (CLAUDE.md: shared logic out of views) so the
/// compose pipeline — filter, then search, then sort — is unit-testable without
/// SwiftUI and shared by both the table column rendering and the inspector. The
/// override-aware spend attributes (effective category, transfer, exclusion) come
/// from the existing ``EffectiveCategoryResolver``; nothing here re-derives spend
/// math. The note/category/transfer *edits* persist through the existing AppState
/// review path — this file only reads the resolved state.
public enum TransactionWorkspace {}

// MARK: - Filter

public extension TransactionWorkspace {
    /// A relative date window for the ledger. Resolved to a concrete lower-bound
    /// `yyyy-MM-dd` key against a supplied "today", so the comparison is a cheap
    /// string compare on the canonical transaction date (no `DateFormatter` per
    /// row). `allTime` imposes no lower bound.
    enum DateRange: String, CaseIterable, Sendable, Codable, Hashable {
        case allTime
        case last7Days
        case last30Days
        case last90Days
        case thisYear

        public var label: String {
            switch self {
            case .allTime: "All time"
            case .last7Days: "Last 7 days"
            case .last30Days: "Last 30 days"
            case .last90Days: "Last 90 days"
            case .thisYear: "This year"
            }
        }

        /// The inclusive lower-bound transaction-date key for this range relative to
        /// `now`, or `nil` for `allTime`. A transaction passes when its date key is
        /// `>=` this value.
        public func lowerBoundKey(now: Date, calendar: Calendar = .current) -> String? {
            switch self {
            case .allTime:
                return nil
            case .last7Days:
                return Self.key(daysAgo: 7, from: now, calendar: calendar)
            case .last30Days:
                return Self.key(daysAgo: 30, from: now, calendar: calendar)
            case .last90Days:
                return Self.key(daysAgo: 90, from: now, calendar: calendar)
            case .thisYear:
                let year = calendar.component(.year, from: now)
                return String(format: "%04d-01-01", year)
            }
        }

        private static func key(daysAgo days: Int, from now: Date, calendar: Calendar) -> String? {
            guard let date = calendar.date(byAdding: .day, value: -days, to: now) else { return nil }
            return Formatters.transactionDateString(date)
        }
    }

    /// The amount-magnitude band a row must fall in (absolute value, in dollars).
    /// All thresholds compare against `TransactionDTO.displayAmount`.
    enum AmountBand: String, CaseIterable, Sendable, Codable, Hashable {
        case any
        case under25
        case from25to100
        case from100to500
        case over500

        public var label: String {
            switch self {
            case .any: "Any amount"
            case .under25: "Under $25"
            case .from25to100: "$25 – $100"
            case .from100to500: "$100 – $500"
            case .over500: "Over $500"
            }
        }

        public func contains(_ displayAmount: Double) -> Bool {
            switch self {
            case .any: true
            case .under25: displayAmount < 25
            case .from25to100: displayAmount >= 25 && displayAmount < 100
            case .from100to500: displayAmount >= 100 && displayAmount < 500
            case .over500: displayAmount >= 500
            }
        }
    }

    /// The review-status facet a row must match. Mirrors the inbox's three states
    /// plus "any" and a derived "flagged" (still needs review) facet.
    enum StatusFilter: String, CaseIterable, Sendable, Codable, Hashable {
        case any
        case needsReview
        case reviewed
        case ignored

        public var label: String {
            switch self {
            case .any: "Any status"
            case .needsReview: "Needs review"
            case .reviewed: "Reviewed"
            case .ignored: "Ignored"
            }
        }

        public func matches(_ status: TransactionReviewStatus) -> Bool {
            switch self {
            case .any: true
            case .needsReview: status == .needsReview
            case .reviewed: status == .reviewed
            case .ignored: status == .ignored
            }
        }
    }

    /// The composable filter + search state for the ledger. Persisted in
    /// `NavigationState` so the window restores its last query. All facets compose
    /// (AND); empty/`any` facets are no-ops, so the default value passes everything.
    struct Filter: Sendable, Codable, Hashable {
        /// Empty string ⇒ all accounts (matches the dashboard "" sentinel).
        public var accountID: String
        /// `nil` ⇒ all categories. Matches the row's *effective* category.
        public var category: SpendingCategory?
        public var dateRange: DateRange
        public var amountBand: AmountBand
        public var status: StatusFilter
        /// Free-text search; matched case-insensitively against merchant + raw name.
        public var searchText: String

        public init(
            accountID: String = "",
            category: SpendingCategory? = nil,
            dateRange: DateRange = .allTime,
            amountBand: AmountBand = .any,
            status: StatusFilter = .any,
            searchText: String = ""
        ) {
            self.accountID = accountID
            self.category = category
            self.dateRange = dateRange
            self.amountBand = amountBand
            self.status = status
            self.searchText = searchText
        }

        /// Whether any facet narrows the result set (drives the "Clear filters"
        /// affordance and the filtered empty state).
        public var isActive: Bool {
            !accountID.isEmpty
                || category != nil
                || dateRange != .allTime
                || amountBand != .any
                || status != .any
                || !trimmedSearch.isEmpty
        }

        /// The trimmed search term (so leading/trailing whitespace never blanks the
        /// list or counts as an active filter).
        public var trimmedSearch: String {
            searchText.trimmingCharacters(in: .whitespacesAndNewlines)
        }

        public func cleared() -> Filter { Filter() }
    }
}

// MARK: - Sort

public extension TransactionWorkspace {
    /// The table sort order, stored as a small `Sendable` enum because
    /// `[KeyPathComparator]` is not `Sendable` and cannot live in `@State` under
    /// strict concurrency (the same constraint `ReviewTableWindow` documents). The
    /// table sorts via ``sorted(_:)`` rather than `Table`'s `sortOrder:` binding.
    enum Sort: String, CaseIterable, Sendable, Codable, Hashable {
        case dateDescending
        case dateAscending
        case amountDescending
        case amountAscending
        case merchantAscending

        public var label: String {
            switch self {
            case .dateDescending: "Newest first"
            case .dateAscending: "Oldest first"
            case .amountDescending: "Largest amount"
            case .amountAscending: "Smallest amount"
            case .merchantAscending: "Merchant A–Z"
            }
        }

        public func sorted(_ rows: [Row]) -> [Row] {
            switch self {
            case .dateDescending:
                rows.sorted { lhs, rhs in
                    if lhs.transaction.date != rhs.transaction.date {
                        return lhs.transaction.date > rhs.transaction.date
                    }
                    return lhs.id < rhs.id
                }
            case .dateAscending:
                rows.sorted { lhs, rhs in
                    if lhs.transaction.date != rhs.transaction.date {
                        return lhs.transaction.date < rhs.transaction.date
                    }
                    return lhs.id < rhs.id
                }
            case .amountDescending:
                rows.sorted { lhs, rhs in
                    if lhs.transaction.displayAmount != rhs.transaction.displayAmount {
                        return lhs.transaction.displayAmount > rhs.transaction.displayAmount
                    }
                    return lhs.id < rhs.id
                }
            case .amountAscending:
                rows.sorted { lhs, rhs in
                    if lhs.transaction.displayAmount != rhs.transaction.displayAmount {
                        return lhs.transaction.displayAmount < rhs.transaction.displayAmount
                    }
                    return lhs.id < rhs.id
                }
            case .merchantAscending:
                rows.sorted { lhs, rhs in
                    let lk = lhs.merchantName.localizedLowercase
                    let rk = rhs.merchantName.localizedLowercase
                    if lk != rk { return lk < rk }
                    return lhs.id < rhs.id
                }
            }
        }
    }
}

// MARK: - Row view-model

public extension TransactionWorkspace {
    /// One ledger row: the raw transaction plus its override-aware resolved spend
    /// attributes (from ``EffectiveCategoryResolver``) and review status. Pure and
    /// `Sendable` so the `Table` renders it directly and tests assert against it
    /// without SwiftUI.
    struct Row: Sendable, Identifiable, Hashable {
        public let transaction: TransactionDTO
        /// Effective merchant display name: user rename → cleaned → raw.
        public let merchantName: String
        /// The override-aware effective (budget) category — user override → rule →
        /// confident Plaid → uncategorized. May be `nil` (genuinely uncategorized).
        public let effectiveCategory: SpendingCategory?
        /// Display-only on-device NL suggestion (the "Suggested" badge), when the
        /// category came from neither the user nor a rule.
        public let suggestedCategory: SpendingCategory?
        /// Plaid's raw category exactly as Plaid classified it — the auditable,
        /// restorable fallback (priority #5). Pure passthrough; `nil` when Plaid
        /// returned no category.
        public let plaidCategory: SpendingCategory?
        /// Whether the effective (budget) category currently overrides a *restorable*
        /// Plaid category (an actual user/rule override that differs from a confident
        /// Plaid answer). Drives the "Restore Plaid category" affordance. `false` for
        /// a low-confidence / `.other` / nil Plaid row with no override, so the
        /// affordance is never offered for a value the resolver would re-reject.
        public let isOverridingPlaid: Bool
        /// The provenance of the override over Plaid (`user` vs `rule`), or `nil` when
        /// not overriding. The inspector offers a per-row "Restore Plaid category"
        /// only for a `.user` override — a `.rule` override is governed by a rule, so
        /// a per-row clear would not restore Plaid.
        public let overrideOrigin: EffectiveCategoryResolver.OverrideOrigin?
        public let isTransfer: Bool
        public let excludedFromBudgets: Bool
        public let status: TransactionReviewStatus
        /// The user's free-text note, if any (display-only).
        public let note: String?

        public var id: String { transaction.id }

        public init(
            transaction: TransactionDTO,
            merchantName: String,
            effectiveCategory: SpendingCategory?,
            suggestedCategory: SpendingCategory?,
            plaidCategory: SpendingCategory? = nil,
            isOverridingPlaid: Bool = false,
            overrideOrigin: EffectiveCategoryResolver.OverrideOrigin? = nil,
            isTransfer: Bool,
            excludedFromBudgets: Bool,
            status: TransactionReviewStatus,
            note: String?
        ) {
            self.transaction = transaction
            self.merchantName = merchantName
            self.effectiveCategory = effectiveCategory
            self.suggestedCategory = suggestedCategory
            self.plaidCategory = plaidCategory
            self.isOverridingPlaid = isOverridingPlaid
            self.overrideOrigin = overrideOrigin
            self.isTransfer = isTransfer
            self.excludedFromBudgets = excludedFromBudgets
            self.status = status
            self.note = note
        }

        /// Whether this row's effective category was filled by the on-device NL
        /// tier rather than the user / Plaid — drives the "Suggested" badge.
        public var isCategorySuggested: Bool {
            effectiveCategory == nil && suggestedCategory != nil
        }

        /// Whether a per-transaction "Restore Plaid category" affordance applies:
        /// the effective category overrides a restorable Plaid category AND that
        /// override is a per-row *user* override (clearable), not a rule. A
        /// rule-backed override is governed by the rule, so a per-row clear would not
        /// restore Plaid — the inspector surfaces the rule instead of a no-op restore.
        public var canRestorePlaidCategory: Bool {
            isOverridingPlaid && overrideOrigin == .user
        }

        /// Whether the override over Plaid comes from a matching rule (not a per-row
        /// user override). The inspector uses this to explain that a rule governs the
        /// category rather than offering a per-row restore that would silently no-op.
        public var isOverriddenByRule: Bool {
            isOverridingPlaid && overrideOrigin == .rule
        }

        /// Whether a free-text note is attached (drives a glyph in the table).
        public var hasNote: Bool {
            !(note?.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ?? true)
        }
    }
}

// MARK: - Pipeline (build → filter → search → sort)

public extension TransactionWorkspace {
    /// Builds the override-aware row view-models for every transaction, reusing the
    /// existing ``EffectiveCategoryResolver`` (no spend re-derivation) and the
    /// persisted review metadata. NL inference is intentionally **not** run here
    /// (it is async / expensive); the resolver's `suggestedCategory` is consulted
    /// only via the metadata path, so the table stays synchronous and cheap. The
    /// caller supplies the same `metadata`/`rules` AppState already holds.
    static func rows(
        transactions: [TransactionDTO],
        metadata: [TransactionReviewMetadata],
        rules: [TransactionRule]
    ) -> [Row] {
        let metadataByID = Dictionary(uniqueKeysWithValues: metadata.map { ($0.id, $0) })
        return transactions.map { transaction in
            let own = metadataByID[transaction.id]
            let resolution = EffectiveCategoryResolver.resolve(
                transaction: transaction,
                metadata: own,
                rules: rules
            )
            let merchant = trimmedNonEmpty(own?.userMerchantName)
                ?? trimmedNonEmpty(transaction.merchantName)
                ?? transaction.name
            return Row(
                transaction: transaction,
                merchantName: merchant,
                effectiveCategory: resolution.category,
                suggestedCategory: resolution.suggestedCategory,
                plaidCategory: resolution.plaidCategory,
                isOverridingPlaid: resolution.isOverridingPlaid,
                overrideOrigin: resolution.overrideOrigin,
                isTransfer: resolution.isTransfer,
                excludedFromBudgets: resolution.excludedFromBudgets,
                status: own?.status ?? .needsReview,
                note: trimmedNonEmpty(own?.userNote)
            )
        }
    }

    /// Applies the filter (AND of every facet) + search to the rows. `now` resolves
    /// any relative date range; injecting it keeps the date facet deterministic in
    /// tests.
    static func filtered(_ rows: [Row], by filter: Filter, now: Date) -> [Row] {
        let lowerBound = filter.dateRange.lowerBoundKey(now: now)
        let search = filter.trimmedSearch.localizedLowercase
        return rows.filter { row in
            if !filter.accountID.isEmpty, row.transaction.accountId != filter.accountID {
                return false
            }
            if let category = filter.category {
                // Match against the *effective* (override-aware) category so a
                // recategorized row filters where the user expects it.
                guard row.effectiveCategory == category else { return false }
            }
            if let lowerBound, row.transaction.date < lowerBound {
                return false
            }
            if !filter.amountBand.contains(row.transaction.displayAmount) {
                return false
            }
            if !filter.status.matches(row.status) {
                return false
            }
            if !search.isEmpty {
                let merchant = row.merchantName.localizedLowercase
                let raw = row.transaction.name.localizedLowercase
                let note = row.note?.localizedLowercase ?? ""
                guard merchant.contains(search) || raw.contains(search) || note.contains(search) else {
                    return false
                }
            }
            return true
        }
    }

    /// The full pipeline: build rows, filter + search, then sort. The single entry
    /// point the view calls.
    static func resolve(
        transactions: [TransactionDTO],
        metadata: [TransactionReviewMetadata],
        rules: [TransactionRule],
        filter: Filter,
        sort: Sort,
        now: Date
    ) -> [Row] {
        let built = rows(transactions: transactions, metadata: metadata, rules: rules)
        let narrowed = filtered(built, by: filter, now: now)
        return sort.sorted(narrowed)
    }

    private static func trimmedNonEmpty(_ value: String?) -> String? {
        guard let value else { return nil }
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }
}
