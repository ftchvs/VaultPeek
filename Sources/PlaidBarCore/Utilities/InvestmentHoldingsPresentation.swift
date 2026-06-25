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
        public let totalMarketValue: Double
        public let totalCostBasis: Double?
        public let totalGain: Double?
        public let gainDirection: Direction
        public let totalMarketValueText: String
        public let totalGainText: String?
        public let accessibilityLabel: String

        public init(
            holdingsCount: Int,
            totalMarketValue: Double,
            totalCostBasis: Double?,
            totalGain: Double?,
            gainDirection: Direction,
            totalMarketValueText: String,
            totalGainText: String?,
            accessibilityLabel: String
        ) {
            self.holdingsCount = holdingsCount
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

        let marketValueText = PrivacyMaskPresentation.currency(
            holding.marketValue,
            isEnabled: privacyMaskEnabled
        )

        let gain = holding.unrealizedGain
        let gainDirection = gain.map(Direction.of)
        let gainText: String? = gain.map { signedCurrency($0, masked: privacyMaskEnabled) }

        let accessibilityLabel = holdingAccessibilityLabel(
            name: name,
            ticker: ticker,
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

        let totalMarketValue = scoped.reduce(0) { $0 + $1.marketValue }

        // Cost basis is summable only over the holdings that actually report it.
        // If *none* report it, leave the total nil so the view omits the gain
        // cue rather than implying a $0 cost basis (and a misleading "all gain").
        let basisHoldings = scoped.filter { $0.costBasis != nil }
        let totalCostBasis: Double? = basisHoldings.isEmpty
            ? nil
            : basisHoldings.reduce(0) { $0 + ($1.costBasis ?? 0) }

        // Gain aggregates over the same basis-reporting holdings so value and
        // basis stay comparable.
        let totalGain: Double? = totalCostBasis.map { basis in
            basisHoldings.reduce(0) { $0 + $1.marketValue } - basis
        }
        let direction = totalGain.map(Direction.of) ?? .flat

        return Summary(
            holdingsCount: scoped.count,
            totalMarketValue: totalMarketValue,
            totalCostBasis: totalCostBasis,
            totalGain: totalGain,
            gainDirection: direction,
            totalMarketValueText: PrivacyMaskPresentation.currency(
                totalMarketValue,
                isEnabled: privacyMaskEnabled
            ),
            totalGainText: totalGain.map { signedCurrency($0, masked: privacyMaskEnabled) },
            accessibilityLabel: summaryAccessibilityLabel(
                holdingsCount: scoped.count,
                totalMarketValue: totalMarketValue,
                totalGain: totalGain,
                direction: direction,
                privacyMaskEnabled: privacyMaskEnabled
            )
        )
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
    /// Mask.
    static func signedCurrency(_ amount: Double, masked: Bool) -> String {
        guard !masked else { return PrivacyMaskPresentation.compactValue }
        let magnitude = Formatters.currency(abs(amount))
        if amount > 0 { return "+\(magnitude)" }
        if amount < 0 { return "−\(magnitude)" }
        return magnitude
    }

    private static func holdingAccessibilityLabel(
        name: String,
        ticker: String?,
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
        parts.append("worth \(Formatters.currency(marketValue))")
        if let gain, let gainDirection {
            parts.append("\(gainDirection.spokenWord) \(Formatters.currency(abs(gain)))")
        }
        return parts.joined(separator: ", ")
    }

    private static func summaryAccessibilityLabel(
        holdingsCount: Int,
        totalMarketValue: Double,
        totalGain: Double?,
        direction: Direction,
        privacyMaskEnabled: Bool
    ) -> String {
        let positions = "\(holdingsCount) holding\(holdingsCount == 1 ? "" : "s")"
        if privacyMaskEnabled {
            return "\(positions), value hidden while Privacy Mask is on"
        }
        var label = "\(positions), total value \(Formatters.currency(totalMarketValue))"
        if let totalGain {
            label += ", \(direction.spokenWord) \(Formatters.currency(abs(totalGain)))"
        }
        return label
    }
}
