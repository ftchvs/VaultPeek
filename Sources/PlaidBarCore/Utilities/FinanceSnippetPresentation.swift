import Foundation

/// Pure presentation models for the *focused* finance `SnippetIntent` views
/// (AND-637): safe-to-spend, next recurring bills, and credit utilization. Each
/// is a small, rich snippet the system can render inline in Spotlight / Siri /
/// Shortcuts results without launching the app.
///
/// These complement ``SnippetDashboardPresentation`` (the combined mini-dashboard)
/// by giving each headline metric its own interactive snippet. As with that type,
/// every row-selection / formatting / masking decision lives here in
/// ``PlaidBarCore`` so it is `Sendable` and unit-tested without the SwiftUI view —
/// the app-target snippet views are thin renderers over these models.
///
/// Privacy mirrors ``FinanceIntentQueries`` and ``SnippetDashboardPresentation``:
/// when the snapshot is masked, missing, or empty every figure is withheld
/// (replaced with the shared dot placeholder) and the view shows a locked / setup
/// affordance — a real value is never leaked past App Lock / Privacy Mask.
///
/// `SnippetIntent.perform()` may be invoked multiple times by the system, so the
/// intent must re-load the snapshot on each call and rebuild the model through one
/// of these `model(from:)` entry points — never cache a value-bearing model.
public enum FinanceSnippetPresentation {
    // MARK: - Shared state

    /// Why a snippet is showing the withheld affordance instead of figures.
    public enum WithholdReason: Sendable, Equatable {
        /// App Lock / Privacy Mask is active — figures exist but must stay hidden.
        case masked
        /// No usable snapshot yet (first run / post-reset) — prompt setup.
        case unavailable

        /// Headline shown in the withheld affordance.
        public var headline: String {
            switch self {
            case .masked: "Figures hidden"
            case .unavailable: "Open VaultPeek"
            }
        }

        /// SF Symbol whose SHAPE carries the state (never colour alone).
        public var systemImage: String {
            switch self {
            case .masked: "eye.slash"
            case .unavailable: "arrow.down.circle"
            }
        }
    }

    // MARK: - Safe to spend

    /// A rendered safe-to-spend snippet: the headline amount plus the confidence
    /// cue and the look-ahead horizon line.
    public struct SafeToSpendModel: Sendable, Equatable {
        /// Formatted amount, or the dot placeholder when withheld.
        public let amount: String
        /// True when the underlying amount is negative (over budget). Drives an
        /// icon/text cue — never colour alone. Always `false` while withheld.
        public let isOverBudget: Bool
        /// Short confidence cue ("Estimate only" / "Lower confidence" / "On
        /// track"), or `nil` when unknown / withheld.
        public let confidenceLabel: String?
        /// SF Symbol paired with `confidenceLabel`, or `nil` when there is no cue.
        public let confidenceSystemImage: String?
        /// "through <date>" horizon line, or `nil` when unknown / withheld.
        public let horizonLabel: String?
        /// Withheld reason, or `nil` when real figures are shown.
        public let withholdReason: WithholdReason?
        /// When the snapshot was produced (chrome, never sensitive).
        public let updatedAt: Date
        /// Self-contained VoiceOver sentence for the whole snippet.
        public let accessibilityLabel: String

        public var isWithheld: Bool { withholdReason != nil }

        public init(
            amount: String,
            isOverBudget: Bool,
            confidenceLabel: String?,
            confidenceSystemImage: String?,
            horizonLabel: String?,
            withholdReason: WithholdReason?,
            updatedAt: Date,
            accessibilityLabel: String
        ) {
            self.amount = amount
            self.isOverBudget = isOverBudget
            self.confidenceLabel = confidenceLabel
            self.confidenceSystemImage = confidenceSystemImage
            self.horizonLabel = horizonLabel
            self.withholdReason = withholdReason
            self.updatedAt = updatedAt
            self.accessibilityLabel = accessibilityLabel
        }
    }

    public static func safeToSpend(from snapshot: FinanceSnapshot?) -> SafeToSpendModel {
        guard let reason = withholdReason(for: snapshot) else {
            // Safe: gate() guarantees a non-nil, non-masked, non-empty snapshot.
            let snapshot = snapshot!
            let amount = snapshot.safeToSpend
            let formatted = Formatters.currency(amount, format: .full, currencyCode: snapshot.isoCurrencyCode)
            let confidenceLabel = snapshot.safeToSpendConfidence?.label
            let confidenceImage = snapshot.safeToSpendConfidence?.iconName
            let horizon = snapshot.safeToSpendHorizonEnd.map { "through \(Formatters.displayDate($0))" }

            var a11y = amount < 0
                ? "Over budget by \(Formatters.currency(abs(amount), format: .full, currencyCode: snapshot.isoCurrencyCode))."
                : "\(formatted) safe to spend."
            if let confidenceLabel { a11y += " \(confidenceLabel)." }
            if let horizon { a11y += " \(horizon.capitalizedFirst)." }

            return SafeToSpendModel(
                amount: formatted,
                isOverBudget: amount < 0,
                confidenceLabel: confidenceLabel,
                confidenceSystemImage: confidenceImage,
                horizonLabel: horizon,
                withholdReason: nil,
                updatedAt: snapshot.generatedAt,
                accessibilityLabel: a11y
            )
        }

        return SafeToSpendModel(
            amount: PrivacyMaskPresentation.compactValue,
            isOverBudget: false,
            confidenceLabel: nil,
            confidenceSystemImage: nil,
            horizonLabel: nil,
            withholdReason: reason,
            updatedAt: snapshot?.generatedAt ?? Date(),
            accessibilityLabel: withheldAccessibility(reason, metric: "Safe to spend")
        )
    }

    // MARK: - Next recurring bills

    /// One bill row in the next-bills snippet.
    public struct BillRow: Sendable, Equatable, Identifiable {
        public let id: String
        public let merchantName: String
        /// Formatted amount.
        public let amount: String
        /// Short due-date label (e.g. "Jul 2").
        public let dueLabel: String

        public init(id: String, merchantName: String, amount: String, dueLabel: String) {
            self.id = id
            self.merchantName = merchantName
            self.amount = amount
            self.dueLabel = dueLabel
        }
    }

    /// A rendered next-bills snippet: up to ``maxBills`` rows plus an optional
    /// "+N more" remainder, or a withheld / empty affordance.
    public struct NextBillsModel: Sendable, Equatable {
        public let headline: String
        public let rows: [BillRow]
        /// Count of bills beyond the displayed rows, or 0.
        public let remainderCount: Int
        public let withholdReason: WithholdReason?
        public let updatedAt: Date
        public let accessibilityLabel: String

        public var isWithheld: Bool { withholdReason != nil }

        public init(
            headline: String,
            rows: [BillRow],
            remainderCount: Int,
            withholdReason: WithholdReason?,
            updatedAt: Date,
            accessibilityLabel: String
        ) {
            self.headline = headline
            self.rows = rows
            self.remainderCount = remainderCount
            self.withholdReason = withholdReason
            self.updatedAt = updatedAt
            self.accessibilityLabel = accessibilityLabel
        }
    }

    /// How many bills the snippet lists before summarizing the remainder.
    public static let maxBills = 3

    public static func nextBills(from snapshot: FinanceSnapshot?) -> NextBillsModel {
        if let reason = withholdReason(for: snapshot) {
            return NextBillsModel(
                headline: reason.headline,
                rows: [],
                remainderCount: 0,
                withholdReason: reason,
                updatedAt: snapshot?.generatedAt ?? Date(),
                accessibilityLabel: withheldAccessibility(reason, metric: "Upcoming bills")
            )
        }

        let snapshot = snapshot!
        let bills = snapshot.nextRecurringBills
        guard !bills.isEmpty else {
            return NextBillsModel(
                headline: "No upcoming bills",
                rows: [],
                remainderCount: 0,
                withholdReason: nil,
                updatedAt: snapshot.generatedAt,
                accessibilityLabel: "No upcoming bills in your tracked window."
            )
        }

        let rows = bills.prefix(maxBills).map { bill in
            BillRow(
                id: bill.id,
                merchantName: bill.merchantName,
                amount: Formatters.currency(bill.amount, format: .full, currencyCode: snapshot.isoCurrencyCode),
                dueLabel: Formatters.displayTransactionDate(bill.nextExpectedDate)
            )
        }
        let remainder = bills.count - rows.count

        let spoken = rows.map { "\($0.merchantName) \($0.amount) on \($0.dueLabel)" }
            .joined(separator: ", ")
        var a11y = "Upcoming bills: \(spoken)."
        if remainder > 0 { a11y += " Plus \(remainder) more." }

        return NextBillsModel(
            headline: "Next bills",
            rows: Array(rows),
            remainderCount: remainder,
            withholdReason: nil,
            updatedAt: snapshot.generatedAt,
            accessibilityLabel: a11y
        )
    }

    // MARK: - Credit utilization gauge

    /// A rendered credit-utilization snippet driving a gauge.
    public struct CreditUtilizationModel: Sendable, Equatable {
        /// Formatted percent (e.g. "42.0%"), or the dot placeholder when withheld.
        public let percentText: String
        /// Gauge fill fraction in `0...1`, or `nil` when withheld / unknown so the
        /// view can show an empty/indeterminate gauge.
        public let fraction: Double?
        /// True when utilization is at or above the warning threshold. Paired with
        /// an icon + text so the warning is never colour-only. `false` while
        /// withheld.
        public let isHigh: Bool
        /// Set when no credit card with a known limit is linked (a real "no data"
        /// answer, distinct from masked/setup).
        public let noLimitMessage: String?
        public let withholdReason: WithholdReason?
        public let updatedAt: Date
        public let accessibilityLabel: String

        public var isWithheld: Bool { withholdReason != nil }

        public init(
            percentText: String,
            fraction: Double?,
            isHigh: Bool,
            noLimitMessage: String?,
            withholdReason: WithholdReason?,
            updatedAt: Date,
            accessibilityLabel: String
        ) {
            self.percentText = percentText
            self.fraction = fraction
            self.isHigh = isHigh
            self.noLimitMessage = noLimitMessage
            self.withholdReason = withholdReason
            self.updatedAt = updatedAt
            self.accessibilityLabel = accessibilityLabel
        }
    }

    public static func creditUtilization(
        from snapshot: FinanceSnapshot?,
        warningThreshold: Double = PlaidBarConstants.creditUtilizationWarningThreshold
    ) -> CreditUtilizationModel {
        if let reason = withholdReason(for: snapshot) {
            return CreditUtilizationModel(
                percentText: PrivacyMaskPresentation.compactValue,
                fraction: nil,
                isHigh: false,
                noLimitMessage: nil,
                withholdReason: reason,
                updatedAt: snapshot?.generatedAt ?? Date(),
                accessibilityLabel: withheldAccessibility(reason, metric: "Credit utilization")
            )
        }

        let snapshot = snapshot!
        guard let percent = snapshot.creditUtilization else {
            let message = "No credit cards with a known limit are linked."
            return CreditUtilizationModel(
                percentText: "—",
                fraction: nil,
                isHigh: false,
                noLimitMessage: message,
                withholdReason: nil,
                updatedAt: snapshot.generatedAt,
                accessibilityLabel: message
            )
        }

        let clamped = min(max(percent, 0), 100)
        let isHigh = percent >= warningThreshold
        let formatted = Formatters.percent(percent)
        var a11y = snapshot.creditUtilizationScopeLabel.map {
            "Credit utilization \(formatted). Highest in the \($0)."
        } ?? "Credit utilization \(formatted)."
        if isHigh {
            a11y += " High — above your \(Formatters.percent(warningThreshold)) warning level."
        }

        return CreditUtilizationModel(
            percentText: formatted,
            fraction: clamped / 100,
            isHigh: isHigh,
            noLimitMessage: nil,
            withholdReason: nil,
            updatedAt: snapshot.generatedAt,
            accessibilityLabel: a11y
        )
    }

    // MARK: - Shared gating

    /// Returns the withhold reason for a snapshot, or `nil` to proceed with real
    /// figures. Mirrors ``FinanceIntentQueries`` and ``SnippetDashboardPresentation``
    /// so every snippet surface withholds identically.
    private static func withholdReason(for snapshot: FinanceSnapshot?) -> WithholdReason? {
        guard let snapshot else { return .unavailable }
        if snapshot.isMasked { return .masked }
        if snapshot.isEmpty { return .unavailable }
        return nil
    }

    private static func withheldAccessibility(_ reason: WithholdReason, metric: String) -> String {
        switch reason {
        case .masked:
            return "\(metric) is hidden while Privacy Mask is on."
        case .unavailable:
            return "VaultPeek hasn't synced yet. Open VaultPeek to connect an account."
        }
    }
}

private extension String {
    /// Capitalizes only the first character, leaving the rest unchanged (so
    /// "through Jul 2" reads as a sentence start without lower-casing "Jul").
    var capitalizedFirst: String {
        guard let first else { return self }
        return first.uppercased() + dropFirst()
    }
}
