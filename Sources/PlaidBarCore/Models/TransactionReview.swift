import Foundation

public enum TransactionReviewStatus: String, Codable, Sendable, Equatable, Hashable {
    case needsReview
    case reviewed
    case ignored
}

public enum TransactionReviewReason: String, Codable, Sendable, CaseIterable, Equatable, Hashable {
    case uncategorized
    case newMerchant
    case unusualAmount
    case possibleTransfer
    case recurringChanged
    case pendingChanged
    case changedSinceReview

    public var displayName: String {
        switch self {
        case .uncategorized: "Needs category"
        case .newMerchant: "New merchant"
        case .unusualAmount: "Large / unusual"
        case .possibleTransfer: "Possible transfer"
        case .recurringChanged: "Recurring changed"
        case .pendingChanged: "Pending changed"
        case .changedSinceReview: "Changed since review"
        }
    }

    public var priority: Int {
        switch self {
        case .possibleTransfer, .pendingChanged, .recurringChanged, .changedSinceReview: 0
        case .unusualAmount: 1
        case .uncategorized, .newMerchant: 2
        }
    }

    public var isHighPriority: Bool {
        priority == 0 || self == .unusualAmount
    }

    /// SF Symbol name for this reason's leading glyph. Shared by the inbox row
    /// and the inspector legend so the two surfaces read consistently; the glyph
    /// is always a redundant layer alongside the `displayName` text, never the
    /// sole carrier of meaning (ACCESSIBILITY.md).
    public var glyphName: String {
        switch self {
        case .uncategorized: "tag"
        case .newMerchant: "person.crop.circle.badge.questionmark"
        case .unusualAmount: "chart.line.uptrend.xyaxis"
        case .possibleTransfer: "arrow.left.arrow.right"
        case .recurringChanged: "calendar.badge.exclamationmark"
        case .pendingChanged: "clock.badge.exclamationmark"
        case .changedSinceReview: "arrow.triangle.2.circlepath"
        }
    }

    /// Plain-language explanation of *why* a transaction surfaced for this
    /// reason, shown in the inspector legend.
    public var explanation: String {
        switch self {
        case .uncategorized:
            "No category yet. Recategorize so it counts toward the right budget."
        case .newMerchant:
            "First time you've seen this merchant. Confirm it's expected."
        case .unusualAmount:
            "Larger or more unusual than this merchant's usual charges."
        case .possibleTransfer:
            "Looks like a transfer or card payment. Mark transfer to exclude it from budgets."
        case .recurringChanged:
            "A recurring charge changed amount or timing."
        case .pendingChanged:
            "This pending charge changed before it posted."
        case .changedSinceReview:
            "Changed since you last reviewed it, so it reopened."
        }
    }
}

public struct TransactionReviewMetadata: Codable, Sendable, Identifiable, Equatable {
    public let id: String
    public var status: TransactionReviewStatus
    public var userCategory: SpendingCategory?
    public var userMerchantName: String?
    public var isTransferOverride: Bool?
    public var excludedFromBudgets: Bool
    public var reviewedAt: Date?
    public var reviewReasonCodes: [TransactionReviewReason]
    public var lastSeenAmount: Double?
    public var lastSeenName: String?
    public var lastSeenPending: Bool?
    /// A free-text note the user attached to this transaction from the
    /// Transaction Workspace inspector (AND-582). Display-only annotation: it is
    /// never fed to budget/category/export totals and never bypasses the
    /// review/override flow, so it cannot mis-attribute spend. Persisted on the
    /// same review-metadata storage path as every other override. `nil` (and
    /// decoded as `nil` when absent) so records written before AND-582 still
    /// decode and behave identically.
    public var userNote: String?

    public init(
        id: String,
        status: TransactionReviewStatus = .needsReview,
        userCategory: SpendingCategory? = nil,
        userMerchantName: String? = nil,
        isTransferOverride: Bool? = nil,
        excludedFromBudgets: Bool = false,
        reviewedAt: Date? = nil,
        reviewReasonCodes: [TransactionReviewReason] = [],
        lastSeenAmount: Double? = nil,
        lastSeenName: String? = nil,
        lastSeenPending: Bool? = nil,
        userNote: String? = nil
    ) {
        self.id = id
        self.status = status
        self.userCategory = userCategory
        self.userMerchantName = userMerchantName
        self.isTransferOverride = isTransferOverride
        self.excludedFromBudgets = excludedFromBudgets
        self.reviewedAt = reviewedAt
        self.reviewReasonCodes = reviewReasonCodes
        self.lastSeenAmount = lastSeenAmount
        self.lastSeenName = lastSeenName
        self.lastSeenPending = lastSeenPending
        self.userNote = userNote
    }

    public init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(String.self, forKey: .id)
        status = try container.decode(TransactionReviewStatus.self, forKey: .status)
        userCategory = try container.decodeIfPresent(SpendingCategory.self, forKey: .userCategory)
        userMerchantName = try container.decodeIfPresent(String.self, forKey: .userMerchantName)
        isTransferOverride = try container.decodeIfPresent(Bool.self, forKey: .isTransferOverride)
        excludedFromBudgets = try container.decodeIfPresent(Bool.self, forKey: .excludedFromBudgets) ?? false
        reviewedAt = try container.decodeIfPresent(Date.self, forKey: .reviewedAt)
        reviewReasonCodes = try container.decodeIfPresent([TransactionReviewReason].self, forKey: .reviewReasonCodes) ?? []
        lastSeenAmount = try container.decodeIfPresent(Double.self, forKey: .lastSeenAmount)
        lastSeenName = try container.decodeIfPresent(String.self, forKey: .lastSeenName)
        lastSeenPending = try container.decodeIfPresent(Bool.self, forKey: .lastSeenPending)
        // New field (AND-582) — absent in records written before it existed, so
        // default to nil. Matches the forward-compatible decode used for
        // `TransactionDTO.isLowConfidenceCategory`.
        userNote = try container.decodeIfPresent(String.self, forKey: .userNote)
    }
}

public struct TransactionRule: Codable, Sendable, Identifiable, Equatable {
    public let id: UUID
    public var matchMerchantContains: String?
    public var matchOriginalNameContains: String?
    public var category: SpendingCategory?
    public var merchantName: String?
    public var isTransfer: Bool?
    public var excludedFromBudgets: Bool?
    public var createdAt: Date

    public init(
        id: UUID = UUID(),
        matchMerchantContains: String? = nil,
        matchOriginalNameContains: String? = nil,
        category: SpendingCategory? = nil,
        merchantName: String? = nil,
        isTransfer: Bool? = nil,
        excludedFromBudgets: Bool? = nil,
        createdAt: Date = Date()
    ) {
        self.id = id
        self.matchMerchantContains = matchMerchantContains
        self.matchOriginalNameContains = matchOriginalNameContains
        self.category = category
        self.merchantName = merchantName
        self.isTransfer = isTransfer
        self.excludedFromBudgets = excludedFromBudgets
        self.createdAt = createdAt
    }

    public func matches(_ transaction: TransactionDTO) -> Bool {
        let merchant = transaction.merchantName ?? transaction.name
        let merchantMatched = matchMerchantContains.map {
            merchant.localizedCaseInsensitiveContains($0)
        } ?? false
        let originalMatched = matchOriginalNameContains.map {
            transaction.name.localizedCaseInsensitiveContains($0)
        } ?? false
        return merchantMatched || originalMatched
    }
}

public struct TransactionReviewItem: Sendable, Identifiable, Equatable {
    public let id: String
    public let transaction: TransactionDTO
    public let status: TransactionReviewStatus
    public let reasonCodes: [TransactionReviewReason]
    public let effectiveCategory: SpendingCategory?
    public let effectiveMerchantName: String
    public let isTransfer: Bool
    public let excludedFromBudgets: Bool
    public let matchedRuleIds: [UUID]
    /// Provenance of `effectiveCategory`. `.appleNaturalLanguage` means the
    /// zero-setup on-device NL tier (AND-507) backfilled the category because
    /// Plaid returned nothing usable and the user hasn't overridden — the UI
    /// pairs this with a text+icon "Suggested" badge (never color alone). Nil
    /// when the category came straight from the user override or Plaid.
    public let categorySource: LocalAICategoryResolutionSource?

    public init(
        transaction: TransactionDTO,
        status: TransactionReviewStatus,
        reasonCodes: [TransactionReviewReason],
        effectiveCategory: SpendingCategory?,
        effectiveMerchantName: String,
        isTransfer: Bool,
        excludedFromBudgets: Bool,
        matchedRuleIds: [UUID],
        categorySource: LocalAICategoryResolutionSource? = nil
    ) {
        self.id = transaction.id
        self.transaction = transaction
        self.status = status
        self.reasonCodes = reasonCodes
        self.effectiveCategory = effectiveCategory
        self.effectiveMerchantName = effectiveMerchantName
        self.isTransfer = isTransfer
        self.excludedFromBudgets = excludedFromBudgets
        self.matchedRuleIds = matchedRuleIds
        self.categorySource = categorySource
    }

    /// Whether `effectiveCategory` was filled by the on-device NL tier rather
    /// than the user or Plaid — drives the "Suggested" badge.
    public var isNLSuggestedCategory: Bool {
        categorySource == .appleNaturalLanguage
    }
}

public struct TransactionReviewInboxSnapshot: Sendable, Equatable {
    public let items: [TransactionReviewItem]
    public let totalCount: Int
    public let highPriorityCount: Int

    public init(items: [TransactionReviewItem]) {
        self.items = items
        self.totalCount = items.count
        self.highPriorityCount = items.filter { item in
            item.reasonCodes.contains(where: \.isHighPriority)
        }.count
    }
}

public enum TransactionReviewInbox {
    public static func evaluate(
        transactions: [TransactionDTO],
        metadata: [TransactionReviewMetadata],
        rules: [TransactionRule],
        recurring: [RecurringTransaction],
        now: Date,
        nlCategorizer: NLMerchantCategorizer = NLMerchantCategorizer()
    ) -> TransactionReviewInboxSnapshot {
        let metadataById = Dictionary(uniqueKeysWithValues: metadata.map { ($0.id, $0) })
        let merchantCounts = Dictionary(grouping: transactions, by: normalizedMerchantKey)
            .mapValues(\.count)
        let spendTransactions = transactions.filter { !$0.isIncome }
        let recurringByMerchant = Dictionary(grouping: recurring, by: { normalizedKey($0.merchantName) })

        // Precompute per-merchant and per-category spend aggregates once so the
        // unusual-amount check is O(1) per transaction instead of re-scanning
        // every spend transaction per row (which made the inbox O(n^2)).
        let unusualPeerIndex = UnusualSpendPeerIndex(spendTransactions: spendTransactions)

        let items = transactions.compactMap { transaction -> TransactionReviewItem? in
            let ownMetadata = metadataById[transaction.id]
            // When Plaid posts a previously-pending charge it arrives under a
            // brand-new transaction id that links back to the pending id via
            // pending_transaction_id. The pending-phase record (the user's
            // category/transfer choices and the last-seen amount/name) still lives
            // under that old id, so carry it forward to reconcile the two.
            let priorPendingMetadata = transaction.pendingTransactionId.flatMap { metadataById[$0] }
            // Production seeds a fresh `.needsReview` record under the posted id
            // before this runs, so `ownMetadata` almost always exists. Treat the
            // posted charge as resolved on its own only once the user has acted on
            // it directly (reviewed/ignored under the posted id). Until then the
            // own record is just the seeded baseline, so prefer the pending-phase
            // record — otherwise the seeded `.needsReview` would mask a charge the
            // user already reviewed while pending, dropping its status and overrides.
            let ownResolved = ownMetadata.map { $0.status == .reviewed || $0.status == .ignored } ?? false
            let metadata = ownResolved ? ownMetadata : (priorPendingMetadata ?? ownMetadata)
            let isAlreadyResolved = metadata?.status == .reviewed || metadata?.status == .ignored
            // The pending baseline only matters until the charge is resolved under
            // its posted id. After that, comparing the posted amount against the old
            // pending amount would re-flag `.pendingChanged` and reopen it on every
            // refresh, so stop falling back to the prior pending record.
            let pendingBaseline = ownResolved ? nil : pendingBaseline(own: ownMetadata, prior: priorPendingMetadata)
            let matchedRules = rules.filter { $0.matches(transaction) }

            // Category resolution precedence: user override → Plaid → on-device
            // NL inference (AND-507) → uncategorized. The NL tier only fills in
            // when the user hasn't overridden AND Plaid returned nothing usable
            // (nil/.other) or flagged its own category LOW/UNKNOWN — so the
            // Review Inbox keeps surfacing only genuinely low-confidence items.
            let resolvedCategory = EffectiveCategoryResolver.resolveCategory(
                transaction: transaction,
                userCategory: metadata?.userCategory,
                nlCategorizer: nlCategorizer
            )
            let effectiveCategory = resolvedCategory.category
            let categorySource = resolvedCategory.source
            let effectiveMerchant = trimmedNonEmpty(metadata?.userMerchantName)
                ?? trimmedNonEmpty(transaction.merchantName)
                ?? transaction.name
            let isTransfer = metadata?.isTransferOverride
                ?? effectiveCategory.map(EffectiveCategoryResolver.isTransferCategory)
                ?? false

            if transaction.isIncome, !looksLikeTransfer(transaction) {
                return nil
            }

            var reasons: Set<TransactionReviewReason> = []
            // Plaid PFCv2 categorizes most transactions confidently; surface a
            // category as "needs review" when it is missing/uncategorized, or
            // when Plaid itself reports LOW/UNKNOWN confidence — but never once
            // the user has set their own category.
            //
            // The on-device NL tier (AND-507) is a *suggestion*, not a persisted
            // category: it fills `effectiveCategory` for display (with the
            // "Suggested" badge) but downstream budget/category/export totals
            // still group by the raw `transaction.category`. So an NL-backfilled
            // item must STAY in the inbox flagged `.uncategorized` — otherwise a
            // recognizable charge with no other review reason silently drops out
            // while its spend keeps landing in "Other", and the user never gets
            // to approve the suggestion (which persists it as `userCategory`).
            // Only a user override clears this; NL never overrides the user.
            if metadata?.userCategory == nil,
                effectiveCategory == nil || effectiveCategory == .other ||
                categorySource == .appleNaturalLanguage ||
                transaction.isLowConfidenceCategory {
                reasons.insert(.uncategorized)
            }
            if merchantNeedsReview(transaction: transaction, effectiveMerchant: effectiveMerchant) ||
                merchantCounts[normalizedMerchantKey(transaction), default: 0] == 1 {
                reasons.insert(.newMerchant)
            }
            if isUnusual(transaction, peers: unusualPeerIndex, category: effectiveCategory) {
                reasons.insert(.unusualAmount)
            }
            if looksLikeTransfer(transaction), !isTransfer {
                reasons.insert(.possibleTransfer)
            }
            if recurringChanged(transaction, recurringByMerchant: recurringByMerchant, now: now) {
                reasons.insert(.recurringChanged)
            }
            let didSettleDifferently = pendingSettledDifferently(transaction, baseline: pendingBaseline)
            if didSettleDifferently {
                reasons.insert(.pendingChanged)
            }
            // A charge the user already resolved under its own id whose amount or
            // name drifted afterward must reopen even when the new value trips no
            // other heuristic (e.g. a known, categorized merchant going $50 -> $60,
            // below the unusual-amount threshold). Insert the reason BEFORE the
            // empty-reasons guard below — otherwise that guard drops the row and the
            // reopen logic never runs, silently swallowing the post-review change.
            let reviewedChargeChangedSinceReview = ownResolved && reviewedChargeChanged(transaction, ownMetadata)
            if reviewedChargeChangedSinceReview {
                reasons.insert(.changedSinceReview)
            }

            let orderedReasons = reasons.sorted {
                if $0.priority == $1.priority { return $0.rawValue < $1.rawValue }
                return $0.priority < $1.priority
            }
            guard !orderedReasons.isEmpty else { return nil }

            // A charge the user already reviewed/ignored is CLEARED from the
            // inbox once they act — even when it carries a high-priority reason.
            // (Previously a high-priority reason kept resolved items pinned, so
            // Approve/Ignore appeared to do nothing on exactly the large/unusual
            // rows users most want to clear.) It only returns if the charge
            // materially changed SINCE the review — a different posted amount/name
            // (`reviewedChargeChanged`) or a pending→posted settle difference —
            // in which case it reopens as needs-review (reportedStatus below).
            // Reopen a resolved charge only if it materially changed since review:
            // a pending→posted settle difference (`didSettleDifferently`), or — when
            // the user resolved the POSTED charge under its own id — a later
            // amount/name change vs that own baseline. The carried-forward pending
            // record is NOT used as a change baseline (its pending-phase name/amount
            // legitimately differ from the posted charge; that comparison is
            // `didSettleDifferently`'s job).
            let changedSinceReview = isAlreadyResolved
                && (didSettleDifferently || reviewedChargeChangedSinceReview)
            if isAlreadyResolved, !changedSinceReview {
                return nil
            }

            // A matched rule normalizes fields on an item the user has NOT
            // explicitly resolved; it should not hide a fresh high-priority
            // signal, but the rule handles the lower-priority ones.
            if !isAlreadyResolved, !matchedRules.isEmpty {
                guard orderedReasons.contains(where: \.isHighPriority) else { return nil }
            }

            // A reviewed charge that changed after the fact is effectively
            // reopened — present it as needing review rather than as resolved.
            let reportedStatus: TransactionReviewStatus =
                changedSinceReview ? .needsReview : (metadata?.status ?? .needsReview)

            return TransactionReviewItem(
                transaction: transaction,
                status: reportedStatus,
                reasonCodes: orderedReasons,
                effectiveCategory: effectiveCategory,
                effectiveMerchantName: effectiveMerchant,
                isTransfer: isTransfer,
                excludedFromBudgets: metadata?.excludedFromBudgets ?? isTransfer,
                matchedRuleIds: matchedRules.map(\.id),
                categorySource: categorySource
            )
        }
        .sorted { lhs, rhs in
            let lhsPriority = lhs.reasonCodes.map(\.priority).min() ?? Int.max
            let rhsPriority = rhs.reasonCodes.map(\.priority).min() ?? Int.max
            if lhsPriority != rhsPriority { return lhsPriority < rhsPriority }
            if lhs.transaction.date != rhs.transaction.date { return lhs.transaction.date > rhs.transaction.date }
            return lhs.id < rhs.id
        }

        return TransactionReviewInboxSnapshot(items: items)
    }

    private static func normalizedMerchantKey(_ transaction: TransactionDTO) -> String {
        normalizedKey(transaction.merchantName ?? transaction.name)
    }

    private static func normalizedKey(_ value: String) -> String {
        value
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .lowercased()
    }

    private static func merchantNeedsReview(transaction: TransactionDTO, effectiveMerchant: String) -> Bool {
        if trimmedNonEmpty(transaction.merchantName) == nil { return true }
        let raw = effectiveMerchant.trimmingCharacters(in: .whitespacesAndNewlines)
        guard raw.count >= 2 else { return true }
        let letters = raw.filter(\.isLetter)
        let uppercaseLetters = letters.filter(\.isUppercase)
        let hasDigits = raw.contains(where: \.isNumber)
        return letters.count >= 4 && uppercaseLetters.count == letters.count && hasDigits
    }

    private static func isUnusual(
        _ transaction: TransactionDTO,
        peers index: UnusualSpendPeerIndex,
        category: SpendingCategory?
    ) -> Bool {
        guard transaction.amount > 0 else { return false }
        let merchantKey = normalizedMerchantKey(transaction)
        var peers = index.merchantPeers(excluding: transaction, merchantKey: merchantKey)
        if peers.count < 3, let category {
            peers = index.categoryPeers(excluding: transaction, category: category)
        }
        guard peers.count >= 3 else { return false }
        let average = peers.sum / Double(peers.count)
        return transaction.displayAmount >= max(average * 1.75, average + 50)
    }

    /// Precomputed spend aggregates so `isUnusual` can resolve a transaction's
    /// peer set in O(1) instead of filtering every spend transaction per row.
    ///
    /// Aggregates are built over spend transactions with `abs(amount) > 0`,
    /// grouped by normalized merchant key and by raw category — matching the
    /// two filters the original per-row scan used. Because the current
    /// transaction is itself part of these aggregates when it qualifies, each
    /// lookup subtracts its own contribution, reproducing the `id != self`
    /// exclusion exactly.
    private struct UnusualSpendPeerIndex {
        struct Peers {
            let count: Int
            let sum: Double
        }

        private struct Aggregate {
            var count = 0
            var sum = 0.0

            mutating func add(_ magnitude: Double) {
                count += 1
                sum += magnitude
            }

            /// Peers seen by another transaction, excluding its own contribution
            /// when it is part of this aggregate.
            func excluding(magnitude: Double, present: Bool) -> Peers {
                guard present else { return Peers(count: count, sum: sum) }
                return Peers(count: count - 1, sum: sum - magnitude)
            }
        }

        private var byMerchantKey: [String: Aggregate] = [:]
        private var byCategory: [SpendingCategory: Aggregate] = [:]

        init(spendTransactions: [TransactionDTO]) {
            for transaction in spendTransactions where abs(transaction.amount) > 0 {
                let magnitude = abs(transaction.amount)
                let merchantKey = TransactionReviewInbox.normalizedMerchantKey(transaction)
                byMerchantKey[merchantKey, default: Aggregate()].add(magnitude)
                if let category = transaction.category {
                    byCategory[category, default: Aggregate()].add(magnitude)
                }
            }
        }

        func merchantPeers(excluding transaction: TransactionDTO, merchantKey: String) -> Peers {
            let aggregate = byMerchantKey[merchantKey] ?? Aggregate()
            // The current transaction is in this aggregate when it is a qualifying
            // spend (amount > 0 implies non-income and abs > 0), so remove itself.
            return aggregate.excluding(magnitude: abs(transaction.amount), present: transaction.amount > 0)
        }

        func categoryPeers(excluding transaction: TransactionDTO, category: SpendingCategory) -> Peers {
            let aggregate = byCategory[category] ?? Aggregate()
            // Aggregates key on the raw category, so the current transaction is in
            // this bucket only when its own category equals the lookup category.
            let isSelfInBucket = transaction.amount > 0 && transaction.category == category
            return aggregate.excluding(magnitude: abs(transaction.amount), present: isSelfInBucket)
        }
    }

    private static func looksLikeTransfer(_ transaction: TransactionDTO) -> Bool {
        let text = "\(transaction.name) \(transaction.merchantName ?? "")".lowercased()
        let keywords = [
            "credit card payment",
            "cc payment",
            "card payment",
            "payment thank you",
            "autopay",
            "ach transfer",
            "online transfer",
            "bank transfer",
            "external transfer",
            "venmo",
            "zelle",
            "cash app",
            "paypal transfer",
            "chase credit",
        ]
        return keywords.contains { text.contains($0) }
    }

    private static func recurringChanged(
        _ transaction: TransactionDTO,
        recurringByMerchant: [String: [RecurringTransaction]],
        now: Date
    ) -> Bool {
        let merchantKey = normalizedMerchantKey(transaction)
        guard let streams = recurringByMerchant[merchantKey] else { return false }
        return streams.contains { recurring in
            (recurring.lastDate == transaction.date && recurring.hasPriceIncrease) ||
                recurring.isStale(asOf: now)
        }
    }

    /// Whether a charge the user already reviewed has materially changed since,
    /// relative to the amount/name snapshot captured at review time (`lastSeen*`).
    /// A changed charge reopens in the inbox as needs-review; an unchanged one
    /// stays cleared. Missing baselines mean "no change". The pending→posted
    /// transition itself is NOT a material change — a charge that posts with the
    /// same amount/name should stay cleared (the pending-vs-posted settle
    /// difference is detected separately by `pendingSettledDifferently`).
    private static func reviewedChargeChanged(
        _ transaction: TransactionDTO,
        _ metadata: TransactionReviewMetadata?
    ) -> Bool {
        guard let metadata else { return false }
        if let seenAmount = metadata.lastSeenAmount, abs(seenAmount - transaction.amount) > 0.005 {
            return true
        }
        if let seenName = metadata.lastSeenName, seenName != transaction.name {
            return true
        }
        return false
    }

    /// The record that captured this charge while it was pending. Prefer the
    /// transaction's own history; fall back to the record carried over from a
    /// prior pending transaction id when Plaid posts the charge under a new id.
    private static func pendingBaseline(
        own: TransactionReviewMetadata?,
        prior: TransactionReviewMetadata?
    ) -> TransactionReviewMetadata? {
        if own?.lastSeenPending == true { return own }
        if prior?.lastSeenPending == true { return prior }
        return nil
    }

    private static func pendingSettledDifferently(
        _ transaction: TransactionDTO,
        baseline: TransactionReviewMetadata?
    ) -> Bool {
        guard transaction.pending == false, let baseline, baseline.lastSeenPending == true
        else { return false }
        let amountChanged = baseline.lastSeenAmount.map { abs($0 - transaction.amount) >= 0.01 } ?? false
        let nameChanged = baseline.lastSeenName.map { $0 != transaction.name } ?? false
        return amountChanged || nameChanged
    }

    private static func trimmedNonEmpty(_ value: String?) -> String? {
        guard let value else { return nil }
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }
}

/// Decides whether review-inbox metadata and categorization rules may be written
/// to the on-disk cache.
///
/// In `--demo`, synthetic fixtures are seeded into the live AppState, so a review
/// action there must NOT persist: `activeStorageDirectoryURL` is the
/// sandbox-scoped real cache, and a later real connection on the same storage
/// path would reload the synthetic `tx*`/Starbucks/Venmo records. This is a pure,
/// testable predicate so the security-relevant guard does not live only in the
/// (untestable, `@main`) app target.
public enum ReviewStoragePersistencePolicy {
    /// `true` only when the current review/rule state may be saved to disk.
    /// Demo mode is never persisted.
    public static func shouldPersist(isDemoMode: Bool) -> Bool {
        !isDemoMode
    }
}
