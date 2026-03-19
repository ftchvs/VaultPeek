import Foundation

public struct RecurringTransaction: Sendable, Identifiable, Hashable {
    public let id: String
    public let merchantName: String
    public let frequency: RecurringFrequency
    public let averageAmount: Double
    public let lastDate: String
    public let nextExpectedDate: String
    public let category: SpendingCategory?
    public let transactionCount: Int
    public let confidence: Double

    public init(
        merchantName: String,
        frequency: RecurringFrequency,
        averageAmount: Double,
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
        self.lastDate = lastDate
        self.nextExpectedDate = nextExpectedDate
        self.category = category
        self.transactionCount = transactionCount
        self.confidence = confidence
    }
}

public enum RecurringFrequency: String, Sendable, CaseIterable, Hashable {
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
