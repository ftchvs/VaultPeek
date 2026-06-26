import Foundation

/// Pure, `Sendable` presentation logic for the Plaid Investments surface
/// (AND-644). Joins ``HoldingDTO`` positions to their ``SecurityDTO`` reference
/// data and produces display rows + an account/portfolio summary, all
/// Privacy-Mask-aware.
///
/// Why this lives in Core: it is the most testable part of the Investments
/// feature — a deterministic reduction over DTOs with no I/O — and is reused by
/// the app's holdings detail view, the Accounts inspector, and net-worth
/// inclusion. The SwiftUI layer only renders these rows; it never recomputes
/// market values.
///
/// Accessibility (ACCESSIBILITY.md): gain/loss is *never* signaled by color
/// alone. Every row and the summary expose a ``Direction`` enum (`gain` /
/// `loss` / `flat`) with a non-color glyph name and a sign-prefixed text, plus a
/// spoken VoiceOver label. Color, if any, is additive on top of these cues.
public enum InvestmentHoldingsPresentation {
    /// The directional outcome of a gain/loss figure, carrying its own
    /// non-color cues so the view never has to derive meaning from a sign or a
    /// color swatch alone.
    public enum Direction: String, Sendable, Equatable {
        case gain
        case loss
        case flat

        /// An SF Symbol that encodes direction by *shape* (arrow up / down /
        /// dash), satisfying the no-meaning-by-color-alone rule.
        public var glyphName: String {
            switch self {
            case .gain: return "arrow.up.right"
            case .loss: return "arrow.down.right"
            case .flat: return "minus"
            }
        }

        /// A short, color-independent word for the direction, used in
        /// VoiceOver labels and as a redundant textual cue.
        public var spokenWord: String {
            switch self {
            case .gain: return "up"
            case .loss: return "down"
            case .flat: return "flat"
            }
        }

        public static func of(_ value: Double) -> Direction {
            if value > 0 { return .gain }
            if value < 0 { return .loss }
            return .flat
        }
    }

    /// One holding rendered for display: the resolved security identity plus
    /// preformatted, Privacy-Mask-aware value/quantity strings and a directional
    /// gain cue. Identifiable by the underlying holding id.
    public struct HoldingRow: Sendable, Equatable, Identifiable {
        public let id: String
        public let accountId: String
        public let securityName: String
        public let tickerSymbol: String?
        /// A human label for the security type (e.g. "ETF", "Equity"). Nil when
        /// Plaid omits the type.
        public let securityTypeLabel: String?
        public let quantityText: String
        public let marketValueText: String
        /// Preformatted unrealized gain/loss with an explicit sign, or nil when
        /// cost basis is unavailable (so the view omits the cue honestly).
        public let gainText: String?
        public let gainDirection: Direction?
        /// A full spoken description for VoiceOver, masked when Privacy Mask is on.
        public let accessibilityLabel: String

        public init(
            id: String,
            accountId: String,
            securityName: String,
            tickerSymbol: String?,
            securityTypeLabel: String?,
            quantityText: String,
            marketValueText: String,
            gainText: String?,
            gainDirection: Direction?,
            accessibilityLabel: String
        ) {
            self.id = id
            self.accountId = accountId
            self.securityName = securityName
            self.tickerSymbol = tickerSymbol
            self.securityTypeLabel = securityTypeLabel
            self.quantityText = quantityText
            self.marketValueText = marketValueText
            self.gainText = gainText
            self.gainDirection = gainDirection
            self.accessibilityLabel = accessibilityLabel
        }
    }

    /// A portfolio (or single-account) rollup: total market value, total cost
    /// basis, and the aggregate unrealized gain with a directional cue.
    public struct Summary: Sendable, Equatable {
        public let holdingsCount: Int
        /// Per-currency aggregation of the holdings' market values (AND-660). The
        /// source of truth for the displayed total: mixed currencies stay grouped
        /// here and never collapse into a single fabricated `$` figure.
        public let marketValueAggregation: CurrencyAggregation
        /// Scalar sum of every holding's market value, *regardless of currency*.
        /// Retained only as the net-worth inclusion input (callers fold investment
        /// value into a USD net worth today); it is **not** a display figure and
        /// must not be rendered with a `$` when ``marketValueAggregation`` is
        /// multi-currency. Prefer ``totalMarketValueText`` for display.
        public let totalMarketValue: Double
        public let totalCostBasis: Double?
        public let totalGain: Double?
        public let gainDirection: Direction
        public let totalMarketValueText: String
        public let totalGainText: String?
        public let accessibilityLabel: String

        /// True when the holdings span more than one currency, so the displayed
        /// total is a per-currency breakdown rather than a single headline figure.
        public var isMultiCurrency: Bool { marketValueAggregation.isMultiCurrency }

        public init(
            holdingsCount: Int,
            marketValueAggregation: CurrencyAggregation,
            totalMarketValue: Double,
            totalCostBasis: Double?,
            totalGain: Double?,
            gainDirection: Direction,
            totalMarketValueText: String,
            totalGainText: String?,
            accessibilityLabel: String
        ) {
            self.holdingsCount = holdingsCount
            self.marketValueAggregation = marketValueAggregation
            self.totalMarketValue = totalMarketValue
            self.totalCostBasis = totalCostBasis
            self.totalGain = totalGain
            self.gainDirection = gainDirection
            self.totalMarketValueText = totalMarketValueText
            self.totalGainText = totalGainText
            self.accessibilityLabel = accessibilityLabel
        }
    }

    // MARK: - Mapping

    /// Builds display rows for the holdings in `accountId`, joined to their
    /// securities and sorted by descending market value (largest position
    /// first) so the most material holdings lead. Holdings whose security is
    /// missing still render with a fallback name rather than disappearing.
    public static func rows(
        forAccount accountId: String,
        holdings: [HoldingDTO],
        securities: [SecurityDTO],
        privacyMaskEnabled: Bool
    ) -> [HoldingRow] {
        let securitiesById = Dictionary(
            securities.map { ($0.id, $0) },
            uniquingKeysWith: { first, _ in first }
        )
        return holdings
            .filter { $0.accountId == accountId }
            .sorted { $0.marketValue > $1.marketValue }
            .map { holding in
                row(for: holding, security: securitiesById[holding.securityId], privacyMaskEnabled: privacyMaskEnabled)
            }
    }

    /// All rows across every account, grouped contract aside — used when a
    /// single combined holdings list is desired.
    public static func allRows(
        holdings: [HoldingDTO],
        securities: [SecurityDTO],
        privacyMaskEnabled: Bool
    ) -> [HoldingRow] {
        let securitiesById = Dictionary(
            securities.map { ($0.id, $0) },
            uniquingKeysWith: { first, _ in first }
        )
        return holdings
            .sorted { $0.marketValue > $1.marketValue }
            .map { holding in
                row(for: holding, security: securitiesById[holding.securityId], privacyMaskEnabled: privacyMaskEnabled)
            }
    }

    private static func row(
        for holding: HoldingDTO,
        security: SecurityDTO?,
        privacyMaskEnabled: Bool
    ) -> HoldingRow {
        let name = privacyMaskEnabled
            ? "Investment holding"
            : securityName(security, fallbackId: holding.securityId)
        let ticker = privacyMaskEnabled ? nil : security?.tickerSymbol
        let typeLabel = privacyMaskEnabled ? nil : securityTypeLabel(security?.type)

        // Quantity is a count of shares, not a balance — but it can reveal
        // position size, so mask it alongside currency under Privacy Mask.
        let quantityText = privacyMaskEnabled
            ? PrivacyMaskPresentation.compactValue
            : "\(formatQuantity(holding.quantity)) shares"

        // Render the value/gain in the holding's *own* currency so a EUR
        // position never reads as `$` (AND-660). Masked figures still collapse to
        // the placeholder; only the unmasked path threads the currency.
        let currency = holding.currency
        let marketValueText = privacyMaskEnabled
            ? PrivacyMaskPresentation.compactValue
            : Formatters.currency(holding.marketValue, in: currency)

        let gain = holding.unrealizedGain
        let gainDirection = gain.map(Direction.of)
        let gainText: String? = gain.map { signedCurrency($0, in: currency, masked: privacyMaskEnabled) }

        let accessibilityLabel = holdingAccessibilityLabel(
            name: name,
            ticker: ticker,
            currency: currency,
            marketValue: holding.marketValue,
            quantity: holding.quantity,
            gain: gain,
            gainDirection: gainDirection,
            privacyMaskEnabled: privacyMaskEnabled
        )

        return HoldingRow(
            id: holding.id,
            accountId: holding.accountId,
            securityName: name,
            tickerSymbol: ticker,
            securityTypeLabel: typeLabel,
            quantityText: quantityText,
            marketValueText: marketValueText,
            gainText: gainText,
            gainDirection: gainDirection,
            accessibilityLabel: accessibilityLabel
        )
    }

    // MARK: - Summary

    /// Rolls up the supplied holdings into a portfolio summary. When `accountId`
    /// is provided, only that account's holdings are included.
    public static func summary(
        holdings: [HoldingDTO],
        accountId: String? = nil,
        privacyMaskEnabled: Bool
    ) -> Summary {
        let scoped = accountId.map { id in holdings.filter { $0.accountId == id } } ?? holdings

        // Group market value per currency so a mixed EUR/USD portfolio never
        // collapses into a single fabricated `$` scalar (AND-660). The scalar
        // `totalMarketValue` remains for net-worth inclusion only.
        let marketValueAggregation = CurrencyAggregation.aggregate(
            scoped.map { (amount: $0.marketValue, currency: $0.currency) }
        )
        let totalMarketValue = scoped.reduce(0) { $0 + $1.marketValue }

        // Cost basis is summable only over the holdings that actually report it.
        // If *none* report it, leave the total nil so the view omits the gain
        // cue rather than implying a $0 cost basis (and a misleading "all gain").
        let basisHoldings = scoped.filter { $0.costBasis != nil }
        let totalCostBasis: Double? = basisHoldings.isEmpty
            ? nil
            : basisHoldings.reduce(0) { $0 + ($1.costBasis ?? 0) }

        // Gain aggregates over the same basis-reporting holdings so value and
        // basis stay comparable. Grouped per currency so a EUR gain and a USD
        // gain are never summed into a meaningless cross-currency number.
        let gainAggregation: CurrencyAggregation? = basisHoldings.isEmpty
            ? nil
            : CurrencyAggregation.aggregate(
                basisHoldings.map { (amount: $0.marketValue - ($0.costBasis ?? 0), currency: $0.currency) }
            )
        let totalGain: Double? = totalCostBasis.map { basis in
            basisHoldings.reduce(0) { $0 + $1.marketValue } - basis
        }
        let direction = totalGain.map(Direction.of) ?? .flat

        return Summary(
            holdingsCount: scoped.count,
            marketValueAggregation: marketValueAggregation,
            totalMarketValue: totalMarketValue,
            totalCostBasis: totalCostBasis,
            totalGain: totalGain,
            gainDirection: direction,
            totalMarketValueText: marketValueText(
                from: marketValueAggregation,
                privacyMaskEnabled: privacyMaskEnabled
            ),
            totalGainText: gainAggregation.map {
                gainText(from: $0, privacyMaskEnabled: privacyMaskEnabled)
            },
            accessibilityLabel: summaryAccessibilityLabel(
                holdingsCount: scoped.count,
                marketValueAggregation: marketValueAggregation,
                gainAggregation: gainAggregation,
                direction: direction,
                privacyMaskEnabled: privacyMaskEnabled
            )
        )
    }

    /// Display text for the rolled-up market value. Single currency (or a
    /// priceable conversion) renders one figure; mixed unpriceable currencies
    /// render a per-currency breakdown, never a fabricated `$` total (AND-660).
    private static func marketValueText(
        from aggregation: CurrencyAggregation,
        privacyMaskEnabled: Bool
    ) -> String {
        let headline = MultiCurrencyBalancePresentation.headline(
            from: aggregation,
            format: .full,
            privacyMaskEnabled: privacyMaskEnabled
        )
        if let total = headline.formattedTotal { return total }
        return MultiCurrencyBalancePresentation.subtotalRows(
            from: aggregation,
            format: .full,
            privacyMaskEnabled: privacyMaskEnabled
        )
        .map(\.formattedAmount)
        .joined(separator: " · ")
    }

    /// Sign-prefixed display text for the rolled-up unrealized gain. Single
    /// currency renders one signed figure; mixed currencies render a per-currency
    /// list so EUR and USD gains are never summed (AND-660).
    private static func gainText(
        from aggregation: CurrencyAggregation,
        privacyMaskEnabled: Bool
    ) -> String {
        if privacyMaskEnabled { return PrivacyMaskPresentation.compactValue }
        if let single = aggregation.singleCurrency,
           let subtotal = aggregation.subtotals.first {
            return signedCurrency(subtotal.amount, in: single, masked: false)
        }
        return aggregation.subtotals
            .map { signedCurrency($0.amount, in: $0.currency, masked: false) }
            .joined(separator: " · ")
    }

    /// The total market value of all supplied holdings — the figure that should
    /// be folded into net worth for investment accounts. Long positions only
    /// contribute non-negative value to assets; callers clamp at the asset
    /// total, matching `WealthSummaryPresentation`.
    public static func totalMarketValue(holdings: [HoldingDTO]) -> Double {
        holdings.reduce(0) { $0 + $1.marketValue }
    }

    // MARK: - Formatting helpers

    static func securityName(_ security: SecurityDTO?, fallbackId: String) -> String {
        if let name = security?.name, !name.isEmpty { return name }
        if let ticker = security?.tickerSymbol, !ticker.isEmpty { return ticker }
        return fallbackId.isEmpty ? "Unknown security" : "Unidentified security"
    }

    /// Title-cases Plaid's lower-case security type, with a friendly override for
    /// the common acronym types so "etf" renders as "ETF" not "Etf".
    static func securityTypeLabel(_ type: String?) -> String? {
        guard let type, !type.isEmpty else { return nil }
        switch type.lowercased() {
        case "etf": return "ETF"
        case "equity": return "Equity"
        case "mutual fund": return "Mutual Fund"
        case "fixed income": return "Fixed Income"
        case "cash": return "Cash"
        case "derivative": return "Derivative"
        case "loan": return "Loan"
        default:
            return type
                .split(separator: " ")
                .map { $0.prefix(1).uppercased() + $0.dropFirst() }
                .joined(separator: " ")
        }
    }

    static func formatQuantity(_ quantity: Double) -> String {
        let formatter = NumberFormatter()
        formatter.numberStyle = .decimal
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.minimumFractionDigits = 0
        // Show up to 4 fractional digits for fractional-share brokerages, but
        // trim trailing zeros so whole-share counts read as "10" not "10.0000".
        formatter.maximumFractionDigits = 4
        return formatter.string(from: NSNumber(value: quantity)) ?? "\(quantity)"
    }

    /// A sign-prefixed currency string so the direction reads textually even in
    /// monochrome / for VoiceOver — never relying on color. Masked under Privacy
    /// Mask. Rendered in `currency`'s own native format (AND-660) so a EUR gain
    /// shows as EUR, not `$`.
    static func signedCurrency(_ amount: Double, in currency: CurrencyCode, masked: Bool) -> String {
        if masked { return PrivacyMaskPresentation.compactValue }
        // Uses the typographic U+2212 MINUS SIGN (not ASCII hyphen-minus) for a
        // negative gain, and the holding's native currency for the magnitude.
        let magnitude = Formatters.currency(abs(amount), in: currency, format: .full)
        if amount > 0 { return "+\(magnitude)" }
        if amount < 0 { return "\u{2212}\(magnitude)" }
        return magnitude
    }

    private static func holdingAccessibilityLabel(
        name: String,
        ticker: String?,
        currency: CurrencyCode,
        marketValue: Double,
        quantity: Double,
        gain: Double?,
        gainDirection: Direction?,
        privacyMaskEnabled: Bool
    ) -> String {
        var parts: [String] = [name]
        if let ticker, !ticker.isEmpty { parts.append(ticker) }

        if privacyMaskEnabled {
            parts.append("value hidden while Privacy Mask is on")
            return parts.joined(separator: ", ")
        }

        parts.append("\(formatQuantity(quantity)) shares")
        parts.append("worth \(Formatters.currency(marketValue, in: currency))")
        if let gain, let gainDirection {
            parts.append("\(gainDirection.spokenWord) \(Formatters.currency(abs(gain), in: currency))")
        }
        return parts.joined(separator: ", ")
    }

    private static func summaryAccessibilityLabel(
        holdingsCount: Int,
        marketValueAggregation: CurrencyAggregation,
        gainAggregation: CurrencyAggregation?,
        direction: Direction,
        privacyMaskEnabled: Bool
    ) -> String {
        let positions = "\(holdingsCount) holding\(holdingsCount == 1 ? "" : "s")"
        if privacyMaskEnabled {
            return "\(positions), value hidden while Privacy Mask is on"
        }
        // Name the total per currency so VoiceOver never speaks a fabricated `$`
        // figure for a mixed-currency portfolio (AND-660).
        let valueText = marketValueText(from: marketValueAggregation, privacyMaskEnabled: false)
        var label = "\(positions), total value \(valueText)"
        if let gainAggregation {
            // Single currency keeps the prior "<direction> <amount>" phrasing; a
            // mixed-currency gain reads as a per-currency list.
            if let single = gainAggregation.singleCurrency,
               let subtotal = gainAggregation.subtotals.first {
                label += ", \(Direction.of(subtotal.amount).spokenWord) \(Formatters.currency(abs(subtotal.amount), in: single))"
            } else {
                let perCurrency = gainAggregation.subtotals
                    .map { "\(Direction.of($0.amount).spokenWord) \(Formatters.currency(abs($0.amount), in: $0.currency))" }
                    .joined(separator: ", ")
                label += ", \(perCurrency)"
            }
        }
        return label
    }
}
