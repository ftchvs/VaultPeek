import Foundation

public struct RecurringTransaction: Sendable, Identifiable, Hashable {
    public static let priceIncreaseConfidenceThreshold = 0.6
    public static let priceIncreaseRelativeThreshold = 0.10
    public static let priceIncreaseAbsoluteThreshold = 1.0

    public let id: String
    public let merchantName: String
    public let frequency: RecurringFrequency
    public let averageAmount: Double
    public let latestAmount: Double
    public let trailingAverageAmount: Double?
    public let lastDate: String
    public let nextExpectedDate: String
    public let category: SpendingCategory?
    public let transactionCount: Int
    public let confidence: Double

    public init(
        merchantName: String,
        frequency: RecurringFrequency,
        averageAmount: Double,
        latestAmount: Double? = nil,
        trailingAverageAmount: Double? = nil,
        lastDate: String,
        nextExpectedDate: String,
        category: SpendingCategory?,
        transactionCount: Int,
        confidence: Double
    ) {
        self.id = "\(merchantName)-\(frequency.rawValue)"
        self.merchantName = merchantName
        self.frequency = frequency
        self.averageAmount = averageAmount
        self.latestAmount = latestAmount ?? averageAmount
        self.trailingAverageAmount = trailingAverageAmount
        self.lastDate = lastDate
        self.nextExpectedDate = nextExpectedDate
        self.category = category
        self.transactionCount = transactionCount
        self.confidence = confidence
    }

    public var priceIncrease: RecurringPriceIncrease? {
        guard confidence >= Self.priceIncreaseConfidenceThreshold,
              let trailingAverageAmount,
              trailingAverageAmount > 0
        else { return nil }

        let absoluteIncrease = latestAmount - trailingAverageAmount
        let relativeIncrease = absoluteIncrease / trailingAverageAmount
        guard absoluteIncrease >= Self.priceIncreaseAbsoluteThreshold,
              relativeIncrease >= Self.priceIncreaseRelativeThreshold
        else { return nil }

        return RecurringPriceIncrease(
            latestAmount: latestAmount,
            trailingAverageAmount: trailingAverageAmount,
            absoluteIncrease: absoluteIncrease,
            relativeIncrease: relativeIncrease
        )
    }

    public var hasPriceIncrease: Bool {
        priceIncrease != nil
    }

    public func isStale(asOf date: Date, calendar: Calendar = .current) -> Bool {
        guard let lastChargeDate = Formatters.parseTransactionDate(lastDate) else { return false }
        let lastChargeStart = calendar.startOfDay(for: lastChargeDate)
        let asOfStart = calendar.startOfDay(for: date)
        guard let daysSinceLastCharge = calendar.dateComponents(
            [.day],
            from: lastChargeStart,
            to: asOfStart
        ).day else { return false }

        return daysSinceLastCharge > frequency.estimatedDays * 2
    }

    public func isStale(asOf dateString: String, calendar: Calendar = .current) -> Bool {
        guard let date = Formatters.parseTransactionDate(dateString) else { return false }
        return isStale(asOf: date, calendar: calendar)
    }

    /// True when the stream looks like a subscription the user probably forgot
    /// about: still charging, low-cost, monthly-or-rarer, and run for enough
    /// cycles to have slipped into the background (AND-497).
    ///
    /// This is the *opposite* of `isStale` — stale means the expected charge has
    /// stopped, while forgotten means it keeps charging unnoticed. A stale stream
    /// is never also forgotten, so `isStale` takes precedence here and in
    /// `flags(asOf:)`.
    public func isForgotten(asOf date: Date, calendar: Calendar = .current) -> Bool {
        // A stopped stream is reported as stale, not forgotten.
        if isStale(asOf: date, calendar: calendar) { return false }
        // Weekly/biweekly streams are too frequent to "forget" — keep this to
        // monthly-or-rarer cadences where a single small charge hides easily.
        switch frequency {
        case .weekly, .biweekly:
            return false
        case .monthly, .quarterly, .annual:
            break
        }
        guard transactionCount >= PlaidBarConstants.forgottenSubscriptionMinimumCycles else {
            return false
        }
        // Easy to forget means small: a large charge gets noticed every cycle.
        guard averageAmount > 0,
              averageAmount <= PlaidBarConstants.forgottenSubscriptionMaxAmount else {
            return false
        }
        // Only flag recognizable subscription/entertainment spend; uncategorized
        // or other-category recurrence is too noisy to call "forgotten".
        switch category {
        case .subscriptions, .entertainment:
            return true
        default:
            return false
        }
    }

    public func isForgotten(asOf dateString: String, calendar: Calendar = .current) -> Bool {
        guard let date = Formatters.parseTransactionDate(dateString) else { return false }
        return isForgotten(asOf: date, calendar: calendar)
    }

    public func flags(asOf date: Date, calendar: Calendar = .current) -> Set<RecurringStreamFlag> {
        var flags: Set<RecurringStreamFlag> = []
        if hasPriceIncrease {
            flags.insert(.priceIncrease)
        }
        if isStale(asOf: date, calendar: calendar) {
            flags.insert(.stale)
        }
        if isForgotten(asOf: date, calendar: calendar) {
            flags.insert(.forgotten)
        }
        return flags
    }

    public func flags(asOf dateString: String, calendar: Calendar = .current) -> Set<RecurringStreamFlag> {
        guard let date = Formatters.parseTransactionDate(dateString) else {
            return hasPriceIncrease ? [.priceIncrease] : []
        }
        return flags(asOf: date, calendar: calendar)
    }
}

public struct RecurringPriceIncrease: Sendable, Hashable {
    public let latestAmount: Double
    public let trailingAverageAmount: Double
    public let absoluteIncrease: Double
    public let relativeIncrease: Double
}

public enum RecurringStreamFlag: String, Sendable, Hashable, CaseIterable {
    case priceIncrease
    case stale
    case forgotten

    /// Short badge text. Paired with `iconName` so the flag never reads through
    /// color alone (ACCESSIBILITY.md).
    public var label: String {
        switch self {
        case .priceIncrease: "Price up"
        case .stale: "Missing"
        case .forgotten: "Forgotten?"
        }
    }

    public var iconName: String {
        switch self {
        case .priceIncrease: "arrow.up.right"
        case .stale: "calendar.badge.exclamationmark"
        case .forgotten: "questionmark.app.dashed"
        }
    }

    /// Longer phrasing for VoiceOver / accessibility labels.
    public var accessibilityDescription: String {
        switch self {
        case .priceIncrease: "price increased"
        case .stale: "expected charge missing"
        case .forgotten: "you may have forgotten this subscription"
        }
    }
}

public enum RecurringFrequency: String, Codable, Sendable, CaseIterable, Hashable {
    case weekly
    case biweekly
    case monthly
    case quarterly
    case annual

    public var displayName: String {
        switch self {
        case .weekly: "Weekly"
        case .biweekly: "Biweekly"
        case .monthly: "Monthly"
        case .quarterly: "Quarterly"
        case .annual: "Annual"
        }
    }

    public var iconName: String {
        switch self {
        case .weekly: "arrow.clockwise"
        case .biweekly: "arrow.2.squarepath"
        case .monthly: "calendar"
        case .quarterly: "calendar.badge.clock"
        case .annual: "calendar.circle"
        }
    }

    public var estimatedDays: Int {
        switch self {
        case .weekly: 7
        case .biweekly: 14
        case .monthly: 30
        case .quarterly: 90
        case .annual: 365
        }
    }

    /// Multiplier to normalize any frequency to a monthly equivalent cost
    public var monthlyMultiplier: Double {
        switch self {
        case .weekly: 52.0 / 12.0
        case .biweekly: 26.0 / 12.0
        case .monthly: 1.0
        case .quarterly: 1.0 / 3.0
        case .annual: 1.0 / 12.0
        }
    }
}
