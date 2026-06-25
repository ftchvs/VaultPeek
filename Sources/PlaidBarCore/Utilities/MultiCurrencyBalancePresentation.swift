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
