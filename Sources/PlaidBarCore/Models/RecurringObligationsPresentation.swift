import Foundation

/// Display-ready view of detected recurring obligations (AND-400).
///
/// Pure presentation logic: takes the `[RecurringTransaction]` already produced
/// by `RecurringDetector` and turns it into a sorted, annotated list plus the
/// aggregates a glance surface needs (estimated monthly total, attention count).
/// All formatting stays in the view; this type owns ordering, flagging, and
/// derived numbers so they are testable and identical across surfaces.
///
/// This is the *read-only* half of AND-400. User mutation (confirm / rename /
/// ignore / correct a detected series) and the local persistence it requires
/// are deliberately out of scope here — that half shares the budgeting-suite
/// persistence decision tracked across AND-399/400/402/403.
public struct RecurringObligationsPresentation: Sendable, Hashable {
    public struct Item: Sendable, Hashable, Identifiable {
        public let id: String
        public let merchantName: String
        public let frequency: RecurringFrequency
        /// Typical charge amount for one occurrence (the detector's average).
        public let expectedAmount: Double
        /// `expectedAmount` normalized to a monthly-equivalent cost.
        public let monthlyEquivalent: Double
        public let nextExpectedDate: String
        public let lastDate: String
        public let confidence: Double
        public let confidenceLevel: RecurringConfidenceLevel
        public let flags: Set<RecurringStreamFlag>
        public let category: SpendingCategory?

        public init(
            id: String,
            merchantName: String,
            frequency: RecurringFrequency,
            expectedAmount: Double,
            monthlyEquivalent: Double,
            nextExpectedDate: String,
            lastDate: String,
            confidence: Double,
            confidenceLevel: RecurringConfidenceLevel,
            flags: Set<RecurringStreamFlag>,
            category: SpendingCategory?
        ) {
            self.id = id
            self.merchantName = merchantName
            self.frequency = frequency
            self.expectedAmount = expectedAmount
            self.monthlyEquivalent = monthlyEquivalent
            self.nextExpectedDate = nextExpectedDate
            self.lastDate = lastDate
            self.confidence = confidence
            self.confidenceLevel = confidenceLevel
            self.flags = flags
            self.category = category
        }

        /// True when the series carries any flag the user should look at.
        public var needsAttention: Bool { !flags.isEmpty }
        public var hasPriceIncrease: Bool { flags.contains(.priceIncrease) }
        public var isStale: Bool { flags.contains(.stale) }
    }

    /// Detected obligations, attention-first then soonest-due (see `make`).
    public let items: [Item]
    /// Monthly-equivalent cost of the *active* (non-stale) obligations — matches
    /// `RecurringSummary.estimatedMonthlyTotal(asOf:)` so the section header and
    /// any safe-to-spend math agree.
    public let estimatedMonthlyTotal: Double
    /// Count of obligations carrying at least one flag.
    public let attentionCount: Int

    public init(items: [Item], estimatedMonthlyTotal: Double, attentionCount: Int) {
        self.items = items
        self.estimatedMonthlyTotal = estimatedMonthlyTotal
        self.attentionCount = attentionCount
    }

    public var isEmpty: Bool { items.isEmpty }
    public var count: Int { items.count }

    /// Build the presentation from detected recurring series.
    ///
    /// Ordering: items needing attention first (so price increases / missing
    /// charges surface at the top), then soonest `nextExpectedDate`, then
    /// merchant name for a stable tiebreak. ISO `yyyy-MM-dd` strings sort
    /// lexicographically, so a plain string compare is the date order.
    public static func make(
        from recurring: [RecurringTransaction],
        asOf date: Date,
        calendar: Calendar = .current
    ) -> RecurringObligationsPresentation {
        let items = recurring.map { stream -> Item in
            Item(
                id: stream.id,
                merchantName: stream.merchantName,
                frequency: stream.frequency,
                expectedAmount: stream.averageAmount,
                monthlyEquivalent: stream.averageAmount * stream.frequency.monthlyMultiplier,
                nextExpectedDate: stream.nextExpectedDate,
                lastDate: stream.lastDate,
                confidence: stream.confidence,
                confidenceLevel: RecurringConfidenceLevel(confidence: stream.confidence),
                flags: stream.flags(asOf: date, calendar: calendar),
                category: stream.category
            )
        }
        .sorted { lhs, rhs in
            if lhs.needsAttention != rhs.needsAttention {
                return lhs.needsAttention && !rhs.needsAttention
            }
            if lhs.nextExpectedDate != rhs.nextExpectedDate {
                return lhs.nextExpectedDate < rhs.nextExpectedDate
            }
            return lhs.merchantName < rhs.merchantName
        }

        return RecurringObligationsPresentation(
            items: items,
            estimatedMonthlyTotal: RecurringSummary.estimatedMonthlyTotal(
                from: recurring,
                asOf: date,
                calendar: calendar
            ),
            attentionCount: items.reduce(0) { $0 + ($1.needsAttention ? 1 : 0) }
        )
    }
}

/// Discrete confidence band for display — text + symbol, never color alone
/// (ACCESSIBILITY.md).
public enum RecurringConfidenceLevel: String, Sendable, Hashable, CaseIterable {
    case high
    case medium
    case low

    /// `medium`/`low` boundary. A standalone constant (not reusing
    /// `RecurringTransaction.priceIncreaseConfidenceThreshold`, which governs an
    /// unrelated decision) so display banding can move without dragging the
    /// price-increase gate with it.
    static let mediumConfidenceThreshold = 0.6
    static let highConfidenceThreshold = 0.8

    public init(confidence: Double) {
        if confidence >= Self.highConfidenceThreshold {
            self = .high
        } else if confidence >= Self.mediumConfidenceThreshold {
            self = .medium
        } else {
            self = .low
        }
    }

    public var label: String {
        switch self {
        case .high: "Confident"
        case .medium: "Likely"
        case .low: "Low confidence"
        }
    }

    public var iconName: String {
        switch self {
        case .high: "checkmark.seal"
        case .medium: "questionmark.circle"
        case .low: "exclamationmark.circle"
        }
    }
}
