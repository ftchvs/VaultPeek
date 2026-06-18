import Foundation

/// Full recurring payments/subscriptions surface model.
///
/// This wraps `RecurringObligationsPresentation` with display-ready row text so
/// the macOS view can stay thin and tests can cover the user-facing wording
/// without rendering SwiftUI.
public struct RecurringPaymentsSurfacePresentation: Sendable, Hashable {
    public struct Row: Sendable, Hashable, Identifiable {
        public let id: String
        public let merchantName: String
        public let amountText: String
        public let frequencyText: String
        public let lastChargeText: String
        public let nextExpectedText: String
        public let confidenceText: String
        public let monthlyEquivalentText: String
        public let flagExplanations: [String]
        public let accessibilityLabel: String
        public let needsAttention: Bool
        public let isLowConfidence: Bool
        /// True for low-cost, long-running subscriptions the user likely forgot
        /// about (AND-497). Drives the "You may have forgotten this" callout.
        public let isForgotten: Bool
        /// Link text for the cancel-help action, e.g. "How to cancel".
        public let cancelLinkText: String
        /// Destination for the cancel-help action: the merchant's own page when
        /// known, otherwise a generic "how to cancel <merchant>" search.
        public let cancelURL: URL
        /// True when `cancelURL` points at the merchant's own cancel page rather
        /// than a generic web search.
        public let cancelIsSpecific: Bool

        public init(item: RecurringObligationsPresentation.Item) {
            id = item.id
            merchantName = item.merchantName
            amountText = Formatters.currency(item.expectedAmount, format: .compact)
            frequencyText = item.frequency.displayName
            lastChargeText = Formatters.displayTransactionDate(item.lastDate)
            nextExpectedText = item.nextExpectedDate.isEmpty
                ? "Not enough history"
                : Formatters.displayTransactionDate(item.nextExpectedDate)
            confidenceText = item.confidenceLevel.label
            monthlyEquivalentText = "\(Formatters.currency(item.monthlyEquivalent, format: .compact))/mo"
            flagExplanations = Self.flagExplanations(for: item)
            needsAttention = item.needsAttention
            isLowConfidence = item.confidenceLevel == .low
            isForgotten = item.isForgotten

            let guidance = SubscriptionCancelGuidance.guidance(for: item.merchantName)
            cancelLinkText = guidance.linkText
            cancelURL = guidance.url
            cancelIsSpecific = guidance.isSpecific

            var parts = [
                merchantName,
                amountText,
                frequencyText,
                "last charged \(lastChargeText)",
                "next expected \(nextExpectedText)",
                confidenceText,
                "\(monthlyEquivalentText) monthly equivalent",
            ]
            parts.append(contentsOf: flagExplanations)
            accessibilityLabel = parts.joined(separator: ", ")
        }

        private static func flagExplanations(for item: RecurringObligationsPresentation.Item) -> [String] {
            var explanations: [String] = []
            // Forgotten first so it leads the row, matching the surface ordering.
            if item.isForgotten {
                explanations.append("You may have forgotten this subscription — it's small and has charged for a while.")
            }
            if item.hasPriceIncrease {
                explanations.append("Latest charge is higher than the prior pattern.")
            }
            if item.isStale {
                explanations.append("Expected charge has not appeared recently.")
            }
            if item.confidenceLevel == .low {
                explanations.append("Pattern is still low confidence.")
            }
            return explanations
        }
    }

    public let rows: [Row]
    public let estimatedMonthlyTotalText: String
    public let summaryText: String
    public let emptyTitle: String
    public let emptyDetail: String
    public let attentionCount: Int
    public let lowConfidenceCount: Int
    /// Number of rows flagged as likely-forgotten subscriptions (AND-497).
    public let forgottenCount: Int
    /// Header callout shown when at least one subscription looks forgotten, or
    /// nil when none do. Paired with an SF Symbol in the view so it never reads
    /// via color alone.
    public let forgottenCalloutText: String?

    public init(
        rows: [Row],
        estimatedMonthlyTotalText: String,
        summaryText: String,
        emptyTitle: String,
        emptyDetail: String,
        attentionCount: Int,
        lowConfidenceCount: Int,
        forgottenCount: Int = 0,
        forgottenCalloutText: String? = nil
    ) {
        self.rows = rows
        self.estimatedMonthlyTotalText = estimatedMonthlyTotalText
        self.summaryText = summaryText
        self.emptyTitle = emptyTitle
        self.emptyDetail = emptyDetail
        self.attentionCount = attentionCount
        self.lowConfidenceCount = lowConfidenceCount
        self.forgottenCount = forgottenCount
        self.forgottenCalloutText = forgottenCalloutText
    }

    public var isEmpty: Bool { rows.isEmpty }

    public static func make(
        from recurring: [RecurringTransaction],
        asOf date: Date,
        calendar: Calendar = .current
    ) -> RecurringPaymentsSurfacePresentation {
        let obligations = RecurringObligationsPresentation.make(
            from: recurring,
            asOf: date,
            calendar: calendar
        )
        let rows = obligations.items.map(Row.init(item:))
        let lowConfidenceCount = rows.count(where: \.isLowConfidence)
        let forgottenCount = obligations.forgottenCount

        return RecurringPaymentsSurfacePresentation(
            rows: rows,
            estimatedMonthlyTotalText: Formatters.currency(obligations.estimatedMonthlyTotal, format: .compact),
            summaryText: Self.summaryText(
                rowCount: rows.count,
                attentionCount: obligations.attentionCount,
                lowConfidenceCount: lowConfidenceCount,
                forgottenCount: forgottenCount
            ),
            emptyTitle: "No recurring payments detected",
            emptyDetail: "VaultPeek will list subscriptions here after it sees a repeated merchant pattern in synced local transactions.",
            attentionCount: obligations.attentionCount,
            lowConfidenceCount: lowConfidenceCount,
            forgottenCount: forgottenCount,
            forgottenCalloutText: Self.forgottenCalloutText(count: forgottenCount)
        )
    }

    private static func forgottenCalloutText(count: Int) -> String? {
        guard count > 0 else { return nil }
        let noun = count == 1 ? "subscription" : "subscriptions"
        return "You may have forgotten \(count) \(noun) — small charges that have run for a while."
    }

    private static func summaryText(
        rowCount: Int,
        attentionCount: Int,
        lowConfidenceCount: Int,
        forgottenCount: Int
    ) -> String {
        guard rowCount > 0 else {
            return "No recurring payments detected yet."
        }

        var parts = [
            "\(rowCount) detected \(rowCount == 1 ? "stream" : "streams")",
        ]
        if forgottenCount > 0 {
            parts.append("\(forgottenCount) maybe forgotten")
        }
        if attentionCount > 0 {
            parts.append("\(attentionCount) flagged")
        }
        if lowConfidenceCount > 0 {
            parts.append("\(lowConfidenceCount) low confidence")
        }
        return parts.joined(separator: " · ")
    }
}
