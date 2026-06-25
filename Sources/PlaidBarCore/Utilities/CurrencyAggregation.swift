import Foundation

/// Supplies an FX rate to convert one currency into another, for cross-currency
/// aggregates (net worth, safe-to-spend).
///
/// **No-cloud posture (SECURITY.md):** VaultPeek must not phone a remote FX API,
/// so a conversion source is *pluggable* and the only one shipped today is the
/// offline ``StaticCurrencyConversionRates`` stub. A source returns `nil` for any
/// pair it cannot price, in which case ``CurrencyAggregation`` falls back to
/// per-currency subtotals rather than inventing a number.
public protocol CurrencyConversionSource: Sendable {
    /// Multiplier such that `amount(in: from) * rate == amount(in: to)`.
    /// Returns `nil` when this source cannot price the pair (then callers must
    /// show per-currency subtotals, never a fabricated conversion).
    func rate(from: CurrencyCode, to: CurrencyCode) -> Double?
}

public extension CurrencyConversionSource {
    /// Converts `amount` from one currency to another, or `nil` if unpriceable.
    func convert(_ amount: Double, from: CurrencyCode, to: CurrencyCode) -> Double? {
        guard let rate = rate(from: from, to: to) else { return nil }
        return amount * rate
    }
}

/// A conversion source that prices nothing — the default. With it, every
/// cross-currency aggregate degrades to per-currency subtotals, which is the
/// safe behavior when no offline rate table is configured.
public struct NoConversionSource: CurrencyConversionSource {
    public init() {}
    public func rate(from: CurrencyCode, to: CurrencyCode) -> Double? {
        // Identity only: a currency always converts 1:1 to itself.
        from == to ? 1 : nil
    }
}

/// An **offline, static** rate table expressed relative to a base currency
/// (USD by default). These rates are *stub* values bundled with the app and are
/// intentionally NOT live — they preserve the no-cloud posture and exist so the
/// cross-currency path is exercisable/testable. The UI must always disclose that
/// converted figures are approximate and rate-dated (see ``CurrencyAggregation``'s
/// `rateProvenance`).
public struct StaticCurrencyConversionRates: CurrencyConversionSource {
    /// Units of `base` per 1 unit of the keyed currency. e.g. with base USD,
    /// `["EUR": 1.08]` means 1 EUR = 1.08 USD.
    public let base: CurrencyCode
    private let unitsOfBasePerCurrency: [CurrencyCode: Double]

    public init(base: CurrencyCode = .usd, unitsOfBasePerCurrency: [CurrencyCode: Double]) {
        self.base = base
        var table = unitsOfBasePerCurrency
        table[base] = 1 // base always prices itself at 1
        self.unitsOfBasePerCurrency = table
    }

    /// A small bundled sample table (USD base) so the conversion path is usable
    /// out of the box for demo/sandbox data. Rates are illustrative stubs, not
    /// market data, and deliberately omit most currencies so the per-currency
    /// fallback stays exercised.
    public static let sampleOffline = StaticCurrencyConversionRates(
        base: .usd,
        unitsOfBasePerCurrency: [
            CurrencyCode("EUR"): 1.08,
            CurrencyCode("GBP"): 1.27,
            CurrencyCode("CAD"): 0.74,
            CurrencyCode("JPY"): 0.0067,
            CurrencyCode("AUD"): 0.66,
        ]
    )

    public func rate(from: CurrencyCode, to: CurrencyCode) -> Double? {
        if from == to { return 1 }
        guard let fromInBase = unitsOfBasePerCurrency[from],
              let toInBase = unitsOfBasePerCurrency[to],
              toInBase != 0
        else {
            return nil
        }
        // (units of base per `from`) / (units of base per `to`) = `to` per `from`.
        return fromInBase / toInBase
    }
}

/// Per-currency grouping and (best-effort) cross-currency totaling for a set of
/// signed amounts. The core invariant: **native currency is never lost.** Even
/// when a converted grand total is available, the per-currency subtotals that
/// produced it remain attached, so the UI can always show both — or fall back to
/// subtotals-only when conversion is unavailable.
public struct CurrencyAggregation: Sendable, Equatable {
    /// A signed subtotal for one currency (assets positive, debts negative — the
    /// caller decides the sign convention before aggregating).
    public struct Subtotal: Sendable, Equatable, Identifiable {
        public let currency: CurrencyCode
        public let amount: Double
        public var id: String { currency.rawValue }

        public init(currency: CurrencyCode, amount: Double) {
            self.currency = currency
            self.amount = amount
        }
    }

    /// Provenance of the optional ``convertedTotal``, so the UI can label it
    /// honestly (and never present a stub-rate conversion as authoritative).
    public enum ConvertedTotal: Sendable, Equatable {
        /// All currencies are the same; the total is exact, not converted.
        case exact(amount: Double, currency: CurrencyCode)
        /// A cross-currency total produced by an offline/stub rate source. The
        /// `unpricedCurrencies` (if any) were left OUT of the converted figure and
        /// must still be surfaced via subtotals.
        case converted(amount: Double, currency: CurrencyCode, unpricedCurrencies: [CurrencyCode])
        /// No conversion was possible at all (mixed currencies, no rates). The UI
        /// must show subtotals only — there is no single headline number.
        case unavailable
    }

    /// One signed subtotal per distinct currency, sorted (resolved first, then
    /// alphabetical, unknown last). Always present and complete.
    public let subtotals: [Subtotal]

    /// Best-effort single figure. ``ConvertedTotal/unavailable`` whenever the
    /// currencies are mixed and not fully priceable.
    public let convertedTotal: ConvertedTotal

    public init(subtotals: [Subtotal], convertedTotal: ConvertedTotal) {
        self.subtotals = subtotals
        self.convertedTotal = convertedTotal
    }

    /// True when more than one distinct currency is present — the UI cue for
    /// "show per-currency breakdown / approximate-conversion disclosure".
    public var isMultiCurrency: Bool {
        subtotals.count > 1
    }

    /// Convenience: the single currency when there is exactly one, else `nil`.
    public var singleCurrency: CurrencyCode? {
        subtotals.count == 1 ? subtotals.first?.currency : nil
    }

    // MARK: - Building

    /// Aggregates `(amount, currency)` pairs into per-currency subtotals and a
    /// best-effort converted total in `reportingCurrency`.
    ///
    /// - When every amount shares one currency → `.exact` total, no conversion.
    /// - When mixed and `conversionSource` can price *every* foreign currency →
    ///   `.converted` total (with `unpricedCurrencies` empty).
    /// - When mixed and some currencies are unpriceable → `.converted` over the
    ///   priceable subset with the rest listed in `unpricedCurrencies`, OR
    ///   `.unavailable` if *nothing* can be priced beyond identity. Either way the
    ///   full per-currency subtotals are returned.
    public static func aggregate(
        _ entries: [(amount: Double, currency: CurrencyCode)],
        reportingCurrency: CurrencyCode = .usd,
        conversionSource: any CurrencyConversionSource = NoConversionSource()
    ) -> CurrencyAggregation {
        // 1. Sum by currency.
        var byCurrency: [CurrencyCode: Double] = [:]
        for entry in entries {
            byCurrency[entry.currency, default: 0] += entry.amount
        }

        let subtotals = byCurrency
            .map { Subtotal(currency: $0.key, amount: $0.value) }
            .sorted { $0.currency < $1.currency }

        // 2. Single-currency fast path → exact, no conversion needed.
        if subtotals.count <= 1 {
            if let only = subtotals.first {
                return CurrencyAggregation(
                    subtotals: subtotals,
                    convertedTotal: .exact(amount: only.amount, currency: only.currency)
                )
            }
            // Empty input: an exact zero in the reporting currency.
            return CurrencyAggregation(
                subtotals: [],
                convertedTotal: .exact(amount: 0, currency: reportingCurrency)
            )
        }

        // 3. Mixed currencies → attempt conversion of each subtotal.
        var convertedSum = 0.0
        var pricedForeign = false // a real cross-currency conversion happened
        var unpriced: [CurrencyCode] = []
        for subtotal in subtotals {
            if let converted = conversionSource.convert(
                subtotal.amount,
                from: subtotal.currency,
                to: reportingCurrency
            ) {
                convertedSum += converted
                if subtotal.currency != reportingCurrency { pricedForeign = true }
            } else {
                unpriced.append(subtotal.currency)
            }
        }

        // A converted headline is only meaningful if at least one *foreign*
        // currency was actually priced. If the source could only match the
        // reporting currency to itself (identity) while real foreign balances
        // remain unpriced, presenting a "converted total" would silently drop
        // those balances — so degrade to subtotals-only instead.
        guard pricedForeign else {
            return CurrencyAggregation(subtotals: subtotals, convertedTotal: .unavailable)
        }

        return CurrencyAggregation(
            subtotals: subtotals,
            convertedTotal: .converted(
                amount: convertedSum,
                currency: reportingCurrency,
                unpricedCurrencies: unpriced.sorted()
            )
        )
    }
}
