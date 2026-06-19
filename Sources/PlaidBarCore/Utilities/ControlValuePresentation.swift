import Foundation

/// Pure presentation logic for the macOS 26 Control Center *value* controls
/// (AND-503): Safe-to-Spend and Credit Utilization. A Control Widget runs in the
/// widget extension, never the app, and cannot be unit-tested headlessly — so the
/// masked-vs-real value-string decision lives here, in ``PlaidBarCore``, where it
/// is `Sendable` and fully testable.
///
/// Each control reads the shared ``FinanceSnapshot`` from the App Group and asks
/// for a ``ControlValueDisplay``: the figure rendered to a short string, plus an
/// accessibility label and the SF Symbol the control should show. The figure is
/// **withheld** (replaced with ``PrivacyMaskPresentation/compactValue``) whenever
/// the snapshot is masked (App Lock / Privacy Mask), missing, or carries no usable
/// value — mirroring ``FinanceIntentQueries`` so the control never leaks a figure
/// the intents would refuse to speak.
///
/// State is never conveyed by color alone: the symbol SHAPE changes between the
/// data, masked, and unavailable states, and the value/label text is explicit.
public enum ControlValuePresentation {
    /// The short string a control shows when the value is withheld because the
    /// snapshot is masked, missing, or has no usable figure. Reuses the shared
    /// Privacy-Mask dot placeholder so masked controls match masked popover/widget
    /// surfaces exactly.
    public static let withheldValue = PrivacyMaskPresentation.compactValue

    /// One rendered Control Center value, ready to drop into a `Label`.
    public struct ControlValueDisplay: Sendable, Equatable {
        /// The figure rendered to a short display string, or ``withheldValue``
        /// when withheld.
        public let value: String
        /// A self-contained accessibility sentence (state conveyed in words, never
        /// color alone).
        public let accessibilityLabel: String
        /// SF Symbol name whose SHAPE conveys the state (value / masked / setup).
        public let systemImage: String
        /// True when no real figure is shown — the control is masked, the snapshot
        /// is missing, or there is no usable value.
        public let isWithheld: Bool

        public init(
            value: String,
            accessibilityLabel: String,
            systemImage: String,
            isWithheld: Bool
        ) {
            self.value = value
            self.accessibilityLabel = accessibilityLabel
            self.systemImage = systemImage
            self.isWithheld = isWithheld
        }
    }

    // MARK: - Reasons a value is withheld

    /// Why a value is not shown, so the control can pick the right symbol + copy.
    private enum WithheldReason {
        /// App Lock / Privacy Mask is on.
        case masked
        /// No snapshot yet (first run / post-reset) or snapshot has no usable data.
        case unavailable
    }

    /// Shared gate: returns the reason a value must be withheld, or `nil` to show
    /// the real figure. Mirrors ``FinanceIntentQueries`` (missing → unavailable,
    /// masked → masked, empty → unavailable).
    private static func withheldReason(for snapshot: FinanceSnapshot?) -> WithheldReason? {
        guard let snapshot else { return .unavailable }
        if snapshot.isMasked { return .masked }
        if snapshot.isEmpty { return .unavailable }
        return nil
    }

    // MARK: - Safe to spend

    /// Display for the Safe-to-Spend control. Shows the conservative discretionary
    /// balance as a compact currency string; withholds it when masked/unavailable.
    public static func safeToSpend(from snapshot: FinanceSnapshot?) -> ControlValueDisplay {
        if let reason = withheldReason(for: snapshot) {
            return withheld(reason, metric: "Safe to spend")
        }
        // `withheldReason` already proved the snapshot is present, unmasked, and
        // non-empty; bind it for the figure.
        guard let snapshot else {
            return withheld(.unavailable, metric: "Safe to spend")
        }
        let amount = snapshot.safeToSpend
        let formatted = Formatters.currency(
            amount,
            format: .compact,
            currencyCode: snapshot.isoCurrencyCode
        )
        let descriptor = amount < 0 ? "over budget" : "safe to spend"
        return ControlValueDisplay(
            value: formatted,
            accessibilityLabel: "Safe to spend \(formatted), \(descriptor)",
            systemImage: "dollarsign.circle",
            isWithheld: false
        )
    }

    // MARK: - Credit utilization

    /// Display for the Credit-Utilization control. Shows the aggregate utilization
    /// percent; withholds it when masked/unavailable. A snapshot with no known
    /// credit limit (`creditUtilization == nil`) is reported as "no credit" rather
    /// than a misleading 0%.
    public static func creditUtilization(from snapshot: FinanceSnapshot?) -> ControlValueDisplay {
        if let reason = withheldReason(for: snapshot) {
            return withheld(reason, metric: "Credit utilization")
        }
        guard let snapshot else {
            return withheld(.unavailable, metric: "Credit utilization")
        }
        guard let percent = snapshot.creditUtilization else {
            // Non-withheld, but no figure to show — a credit-limit-free user.
            return ControlValueDisplay(
                value: "—",
                accessibilityLabel: "Credit utilization unavailable, no credit card with a known limit is linked",
                systemImage: "creditcard",
                isWithheld: false
            )
        }
        let formatted = Formatters.percent(percent, decimals: 0)
        return ControlValueDisplay(
            value: formatted,
            accessibilityLabel: "Credit utilization \(formatted)",
            systemImage: "creditcard",
            isWithheld: false
        )
    }

    // MARK: - Withheld rendering

    private static func withheld(_ reason: WithheldReason, metric: String) -> ControlValueDisplay {
        switch reason {
        case .masked:
            return ControlValueDisplay(
                value: withheldValue,
                accessibilityLabel: "\(metric) hidden while Privacy Mask is on",
                systemImage: "eye.slash",
                isWithheld: true
            )
        case .unavailable:
            return ControlValueDisplay(
                value: withheldValue,
                accessibilityLabel: "\(metric) unavailable, open VaultPeek to get started",
                systemImage: "lock.shield",
                isWithheld: true
            )
        }
    }
}
