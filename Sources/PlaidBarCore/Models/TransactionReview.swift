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

    public var displayName: String {
        switch self {
        case .uncategorized: "Needs category"
        case .newMerchant: "New merchant"
        case .unusualAmount: "Large / unusual"
        case .possibleTransfer: "Possible transfer"
        case .recurringChanged: "Recurring changed"
        case .pendingChanged: "Pending changed"
        }
    }

    public var priority: Int {
        switch self {
        case .possibleTransfer, .pendingChanged, .recurringChanged: 0
        case .unusualAmount: 1
        case .uncategorized, .newMerchant: 2
        }
    }

    public var isHighPriority: Bool {
        priority == 0 || self == .unusualAmount
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
        lastSeenPending: Bool? = nil
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

    public init(
        transaction: TransactionDTO,
        status: TransactionReviewStatus,
        reasonCodes: [TransactionReviewReason],
        effectiveCategory: SpendingCategory?,
        effectiveMerchantName: String,
        isTransfer: Bool,
        excludedFromBudgets: Bool,
        matchedRuleIds: [UUID]
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
        now: Date
    ) -> TransactionReviewInboxSnapshot {
        let metadataById = Dictionary(uniqueKeysWithValues: metadata.map { ($0.id, $0) })
        let merchantCounts = Dictionary(grouping: transactions, by: normalizedMerchantKey)
            .mapValues(\.count)
        let spendTransactions = transactions.filter { !$0.isIncome }
        let recurringByMerchant = Dictionary(grouping: recurring, by: { normalizedKey($0.merchantName) })

        let items = transactions.compactMap { transaction -> TransactionReviewItem? in
            let metadata = metadataById[transaction.id]
            let isAlreadyResolved = metadata?.status == .reviewed || metadata?.status == .ignored
            let pendingBaseline = pendingBaseline(own: metadata)
            let matchedRules = rules.filter { $0.matches(transaction) }

            let effectiveCategory = metadata?.userCategory ?? transaction.category
            let effectiveMerchant = trimmedNonEmpty(metadata?.userMerchantName)
                ?? trimmedNonEmpty(transaction.merchantName)
                ?? transaction.name
            let isTransfer = metadata?.isTransferOverride
                ?? effectiveCategory.map(isTransferCategory)
                ?? false

            if transaction.isIncome, !looksLikeTransfer(transaction) {
                return nil
            }

            var reasons = Set(metadata?.reviewReasonCodes ?? [])
            if effectiveCategory == nil || effectiveCategory == .other {
                reasons.insert(.uncategorized)
            }
            if merchantNeedsReview(transaction: transaction, effectiveMerchant: effectiveMerchant) ||
                merchantCounts[normalizedMerchantKey(transaction), default: 0] == 1 {
                reasons.insert(.newMerchant)
            }
            if isUnusual(transaction, in: spendTransactions, category: effectiveCategory) {
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

            let orderedReasons = reasons.sorted {
                if $0.priority == $1.priority { return $0.rawValue < $1.rawValue }
                return $0.priority < $1.priority
            }
            guard !orderedReasons.isEmpty else { return nil }

            // A matched rule applies its normalized fields, and an already
            // reviewed/ignored item is settled — but neither should hide a
            // high-priority signal (large spike, recurring change, posted-pending
            // change, possible transfer). Surface those; suppress the rest.
            if isAlreadyResolved || !matchedRules.isEmpty {
                guard orderedReasons.contains(where: \.isHighPriority) else { return nil }
            }

            // A charge that settled with a different amount or name after its
            // pending phase was already approved/ignored is effectively reopened —
            // present it as needing review rather than as still resolved.
            let reportedStatus: TransactionReviewStatus =
                (didSettleDifferently && isAlreadyResolved) ? .needsReview : (metadata?.status ?? .needsReview)

            return TransactionReviewItem(
                transaction: transaction,
                status: reportedStatus,
                reasonCodes: orderedReasons,
                effectiveCategory: effectiveCategory,
                effectiveMerchantName: effectiveMerchant,
                isTransfer: isTransfer,
                excludedFromBudgets: metadata?.excludedFromBudgets ?? isTransfer,
                matchedRuleIds: matchedRules.map(\.id)
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

    private static func isTransferCategory(_ category: SpendingCategory) -> Bool {
        category == .transfer || category == .transferOut
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
        in transactions: [TransactionDTO],
        category: SpendingCategory?
    ) -> Bool {
        guard transaction.amount > 0 else { return false }
        let merchantKey = normalizedMerchantKey(transaction)
        var peers = transactions.filter {
            $0.id != transaction.id &&
                normalizedMerchantKey($0) == merchantKey &&
                abs($0.amount) > 0
        }
        if peers.count < 3, let category {
            peers = transactions.filter {
                $0.id != transaction.id && $0.category == category && abs($0.amount) > 0
            }
        }
        guard peers.count >= 3 else { return false }
        let average = peers.map { abs($0.amount) }.reduce(0, +) / Double(peers.count)
        return transaction.displayAmount >= max(average * 1.75, average + 50)
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

    /// The record that captured this charge while it was pending. Posted↔pending
    /// id migration happens before evaluation, so this only uses the transaction's
    /// own metadata and never requires persisting Plaid's raw pending id.
    private static func pendingBaseline(
        own: TransactionReviewMetadata?
    ) -> TransactionReviewMetadata? {
        if own?.lastSeenPending == true { return own }
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
