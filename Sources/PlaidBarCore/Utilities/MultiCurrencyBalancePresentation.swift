import Foundation

/// Bridges account/transaction currency grouping into display-ready text, with
/// non-color accessibility cues baked in (ACCESSIBILITY.md): every figure carries
/// its currency by *symbol + spoken name*, never by color, and the converted vs.
/// per-currency state is conveyed in words.
public enum MultiCurrencyBalancePresentation {
    /// A formatted per-currency subtotal row for the breakdown UI.
    public struct SubtotalRow: Sendable, Equatable, Identifiable {
        public let currency: CurrencyCode
        public let amount: Double
        /// Native-currency formatted figure, e.g. `"€1,200.00"` or `"$8,000.00"`.
        public let formattedAmount: String
        /// VoiceOver label, e.g. `"Euro: €1,200.00"` — currency named in text.
        public let accessibilityLabel: String
        public var id: String { currency.rawValue }

        public init(
            currency: CurrencyCode,
            amount: Double,
            formattedAmount: String,
            accessibilityLabel: String
        ) {
            self.currency = currency
            self.amount = amount
            self.formattedAmount = formattedAmount
            self.accessibilityLabel = accessibilityLabel
        }
    }

    /// Net worth across accounts, grouped per currency (assets positive, debt
    /// negative) with a best-effort converted grand total. Debt accounts
    /// (credit/loan) contribute a negative subtotal in their own currency, matching
    /// ``WealthSummaryPresentation`` net-worth math but never collapsing currencies.
    public static func netWorth(
        accounts: [AccountDTO],
        reportingCurrency: CurrencyCode = .usd,
        conversionSource: any CurrencyConversionSource = NoConversionSource()
    ) -> CurrencyAggregation {
        let entries: [(amount: Double, currency: CurrencyCode)] = accounts.map { account in
            let balance = AccountPresentation.displayBalance(for: account)
            let signed = AccountPresentation.isDebt(account) ? -balance : balance
            return (amount: signed, currency: account.balances.currency)
        }
        return CurrencyAggregation.aggregate(
            entries,
            reportingCurrency: reportingCurrency,
            conversionSource: conversionSource
        )
    }

    /// Net worth whose **displayed** figure reconciles with the displayed assets
    /// and debt at the same `format` (AND-731).
    ///
    /// Plain ``netWorth(accounts:…)`` sums signed balances at full precision, so its
    /// rounded display (e.g. `$60,104`) can differ by a cent's worth of rounding
    /// from `displayedAssets − displayedDebt` (e.g. `$66,162 − $6,057 = $60,105`) —
    /// three independent rounding passes that don't add up on screen. This variant
    /// rounds each per-currency asset and debt subtotal to the format's display
    /// precision *first*, then forms net = roundedAssets − roundedDebt per currency,
    /// so the three on-screen numbers always reconcile. The cross-currency converted
    /// total (if any) is likewise rebuilt from these rounded subtotals.
    ///
    /// Use this for the Accounts/Dashboard hero trio where all three are shown
    /// together; the unrounded ``netWorth`` remains correct for menu-bar glances and
    /// any single-figure surface that does not also display its parts.
    public static func reconciledNetWorth(
        accounts: [AccountDTO],
        format: CurrencyFormat,
        reportingCurrency: CurrencyCode = .usd,
        conversionSource: any CurrencyConversionSource = NoConversionSource()
    ) -> CurrencyAggregation {
        let assets = totalAssets(
            accounts: accounts,
            reportingCurrency: reportingCurrency,
            conversionSource: conversionSource
        )
        let debt = totalDebt(
            accounts: accounts,
            reportingCurrency: reportingCurrency,
            conversionSource: conversionSource
        )

        var roundedByCurrency: [CurrencyCode: Double] = [:]
        for subtotal in assets.subtotals {
            roundedByCurrency[subtotal.currency, default: 0]
                += Formatters.displayRounded(subtotal.amount, format: format)
        }
        for subtotal in debt.subtotals {
            // Debt subtotals are positive magnitudes; net worth subtracts them.
            roundedByCurrency[subtotal.currency, default: 0]
                -= Formatters.displayRounded(subtotal.amount, format: format)
        }

        let entries = roundedByCurrency.map { (amount: $0.value, currency: $0.key) }
        return CurrencyAggregation.aggregate(
            entries,
            reportingCurrency: reportingCurrency,
            conversionSource: conversionSource
        )
    }

    public static func totalCash(
        accounts: [AccountDTO],
        reportingCurrency: CurrencyCode = .usd,
        conversionSource: any CurrencyConversionSource = NoConversionSource()
    ) -> CurrencyAggregation {
        CurrencyAggregation.aggregate(
            accounts
                .filter { $0.type == .depository }
                .map { (amount: $0.balances.effectiveBalance, currency: $0.balances.currency) },
            reportingCurrency: reportingCurrency,
            conversionSource: conversionSource
        )
    }

    public static func totalAssets(
        accounts: [AccountDTO],
        reportingCurrency: CurrencyCode = .usd,
        conversionSource: any CurrencyConversionSource = NoConversionSource()
    ) -> CurrencyAggregation {
        CurrencyAggregation.aggregate(
            accounts
                .filter { !AccountPresentation.isDebt($0) }
                .map { (amount: max($0.balances.effectiveBalance, 0), currency: $0.balances.currency) },
            reportingCurrency: reportingCurrency,
            conversionSource: conversionSource
        )
    }

    public static func totalDebt(
        accounts: [AccountDTO],
        reportingCurrency: CurrencyCode = .usd,
        conversionSource: any CurrencyConversionSource = NoConversionSource()
    ) -> CurrencyAggregation {
        CurrencyAggregation.aggregate(
            accounts
                .filter(AccountPresentation.isDebt)
                .map { (amount: AccountPresentation.displayBalance(for: $0), currency: $0.balances.currency) },
            reportingCurrency: reportingCurrency,
            conversionSource: conversionSource
        )
    }

    public static func displayText(
        from aggregation: CurrencyAggregation,
        format: CurrencyFormat = .full,
        privacyMaskEnabled: Bool = false
    ) -> String {
        let headline = headline(
            from: aggregation,
            format: format,
            privacyMaskEnabled: privacyMaskEnabled
        )
        if let total = headline.formattedTotal { return total }
        if privacyMaskEnabled { return PrivacyMaskPresentation.compactValue }

        let perCurrency = subtotalRows(
            from: aggregation,
            format: format,
            privacyMaskEnabled: privacyMaskEnabled
        )
        .map(\.formattedAmount)
        .joined(separator: " · ")
        return perCurrency.isEmpty ? "By currency" : perCurrency
    }

    /// Secondary detail copy for a hero metric backed by a currency aggregation.
    /// When the aggregation has no single converted total — mixed, unpriceable
    /// currencies — surface the honest per-currency ``Headline/disclosure``;
    /// otherwise defer to the caller's contextual `fallback` copy. Mirrors the
    /// inline detail logic the dashboard and accounts destinations each spelled
    /// out verbatim. The disclosure is format-independent, so this intentionally
    /// takes no `format`: the `.compact` headline matches the prior inline call.
    public static func metricDetail(
        from aggregation: CurrencyAggregation,
        fallback: String
    ) -> String {
        let headline = headline(from: aggregation, format: .compact)
        return headline.formattedTotal == nil ? headline.disclosure : fallback
    }

    /// Formats per-currency subtotals as display rows. `privacyMaskEnabled`
    /// suppresses the figure but keeps the currency identity visible (you can see
    /// you have EUR without seeing how much).
    public static func subtotalRows(
        from aggregation: CurrencyAggregation,
        format: CurrencyFormat = .full,
        privacyMaskEnabled: Bool = false
    ) -> [SubtotalRow] {
        aggregation.subtotals.map { subtotal in
            let formatted = privacyMaskEnabled
                ? PrivacyMaskPresentation.compactValue
                : Formatters.currency(subtotal.amount, in: subtotal.currency, format: format)
            return SubtotalRow(
                currency: subtotal.currency,
                amount: subtotal.amount,
                formattedAmount: formatted,
                accessibilityLabel: "\(subtotal.currency.accessibleName): \(formatted)"
            )
        }
    }

    /// Headline figure + an honest secondary disclosure line for the converted
    /// total. Returns `nil` headline when conversion is unavailable; callers then
    /// render the subtotal rows alone.
    public struct Headline: Sendable, Equatable {
        /// The single converted/exact figure, or `nil` when only subtotals exist.
        public let formattedTotal: String?
        /// Plain-language note: exact, approximate (with unpriced remainder), or a
        /// subtotals-only prompt. Never communicates state by color.
        public let disclosure: String
        public let accessibilityLabel: String

        public init(formattedTotal: String?, disclosure: String, accessibilityLabel: String) {
            self.formattedTotal = formattedTotal
            self.disclosure = disclosure
            self.accessibilityLabel = accessibilityLabel
        }
    }

    public static func headline(
        from aggregation: CurrencyAggregation,
        format: CurrencyFormat = .full,
        privacyMaskEnabled: Bool = false
    ) -> Headline {
        switch aggregation.convertedTotal {
        case let .exact(amount, currency):
            let formatted = privacyMaskEnabled
                ? PrivacyMaskPresentation.compactValue
                : Formatters.currency(amount, in: currency, format: format)
            return Headline(
                formattedTotal: formatted,
                disclosure: "All accounts in \(currency.accessibleName).",
                accessibilityLabel: "Total \(formatted), all in \(currency.accessibleName)."
            )

        case let .converted(amount, currency, unpriced):
            let formatted = privacyMaskEnabled
                ? PrivacyMaskPresentation.compactValue
                : Formatters.currency(amount, in: currency, format: format)
            let approxNote = "Approximate, converted to \(currency.accessibleName) using offline rates."
            let unpricedNote = unpriced.isEmpty
                ? ""
                : " Excludes \(listCurrencyNames(unpriced)); shown separately below."
            let disclosure = approxNote + unpricedNote
            return Headline(
                formattedTotal: formatted,
                disclosure: disclosure,
                accessibilityLabel: "Approximate total \(formatted) in \(currency.accessibleName). \(disclosure)"
            )

        case .unavailable:
            let disclosure = "Multiple currencies — no conversion rates available. Shown per currency below."
            return Headline(
                formattedTotal: nil,
                disclosure: disclosure,
                accessibilityLabel: disclosure
            )
        }
    }

    /// A single-line menu-bar **glance** figure plus its spoken label, sized for
    /// the constrained menu-bar surface where the multi-line ``headline``
    /// disclosure does not fit.
    ///
    /// Unlike the dashboard, the glance must show *a number*, not a "By currency"
    /// prompt. When the figure is exact (one currency) or a real cross-currency
    /// conversion is available, that single figure is used verbatim — so a
    /// single-currency user sees byte-identical text to before. When currencies
    /// are mixed and unpriceable, the glance shows the **dominant** currency's
    /// subtotal (largest by absolute value) in that currency's own symbol, with a
    /// trailing ``multiCurrencyMarker`` (a non-color "+" cue) signalling that other
    /// currencies exist but are not summed into this figure. It never fabricates a
    /// cross-currency `$` total.
    public struct Glance: Sendable, Equatable {
        /// The figure to render in the menu bar, e.g. `"$1,234"`, `"€1.200+"`.
        public let text: String
        /// VoiceOver label naming the figure (and, when mixed, the dominant
        /// currency + that other currencies exist) in words, never by color.
        public let accessibilityLabel: String

        public init(text: String, accessibilityLabel: String) {
            self.text = text
            self.accessibilityLabel = accessibilityLabel
        }
    }

    /// Non-color marker appended to a mixed-currency dominant-subtotal glance to
    /// signal "other currencies exist, not included in this figure". Kept ASCII so
    /// it renders in the menu bar across locales and is read by VoiceOver via the
    /// glance's spoken label rather than this glyph.
    public static let multiCurrencyMarker = "+"

    public static func glance(
        from aggregation: CurrencyAggregation,
        format: CurrencyFormat = .compact,
        privacyMaskEnabled: Bool = false
    ) -> Glance {
        let headline = headline(
            from: aggregation,
            format: format,
            privacyMaskEnabled: privacyMaskEnabled
        )

        // Exact (single currency) or a real cross-currency conversion → use the
        // single figure verbatim. Single-currency text is byte-identical to the
        // pre-multi-currency menu bar.
        if let total = headline.formattedTotal {
            return Glance(text: total, accessibilityLabel: headline.accessibilityLabel)
        }

        // Mixed + unpriceable → dominant currency's subtotal + non-color marker.
        // No conversion is invented; the omitted currencies are named in the
        // spoken label so VoiceOver users know the figure is one currency only.
        guard let dominant = dominantSubtotal(in: aggregation) else {
            // Defensive: no subtotals at all (empty input never reaches here via
            // aggregate, which yields .exact 0) — keep the prior subtotals prompt.
            return Glance(
                text: displayText(from: aggregation, format: format, privacyMaskEnabled: privacyMaskEnabled),
                accessibilityLabel: headline.accessibilityLabel
            )
        }

        let figure = privacyMaskEnabled
            ? PrivacyMaskPresentation.compactValue
            : Formatters.currency(dominant.amount, in: dominant.currency, format: format)
        let others = aggregation.subtotals
            .filter { $0.currency != dominant.currency }
            .map(\.currency)
        let othersNote = others.isEmpty
            ? ""
            : " Other currencies (\(listCurrencyNames(others))) shown separately, not included."

        return Glance(
            text: figure + multiCurrencyMarker,
            accessibilityLabel:
                "\(figure) \(dominant.currency.accessibleName) subtotal.\(othersNote)"
        )
    }

    /// The subtotal that dominates by absolute magnitude. Ties resolve to the
    /// first in ``CurrencyAggregation``'s deterministic order (resolved-first,
    /// alphabetical), so the chosen currency is stable across renders.
    static func dominantSubtotal(
        in aggregation: CurrencyAggregation
    ) -> CurrencyAggregation.Subtotal? {
        aggregation.subtotals.reduce(nil) { current, candidate in
            guard let current else { return candidate }
            return abs(candidate.amount) > abs(current.amount) ? candidate : current
        }
    }

    private static func listCurrencyNames(_ currencies: [CurrencyCode]) -> String {
        let names = currencies.map(\.accessibleName)
        switch names.count {
        case 0: return ""
        case 1: return names[0]
        case 2: return "\(names[0]) and \(names[1])"
        default:
            return names.dropLast().joined(separator: ", ") + ", and \(names[names.count - 1])"
        }
    }
}
