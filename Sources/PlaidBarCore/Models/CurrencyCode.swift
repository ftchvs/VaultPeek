import Foundation

/// A normalized currency identifier carried by an ``AccountDTO``/``TransactionDTO``.
///
/// Plaid reports balances and transaction amounts under either an ISO-4217
/// `iso_currency_code` (e.g. `"USD"`, `"EUR"`, `"GBP"`) or an
/// `unofficial_currency_code` for assets that have no ISO code (crypto,
/// rewards points, certain neobank balances). VaultPeek treats both as opaque
/// uppercase tokens for *display and grouping*: we never assume USD, and we
/// never silently coerce a non-USD balance into a dollar figure.
///
/// `nil`/empty Plaid codes collapse to ``unknown`` so downstream grouping is
/// total — a balance with no reported currency is its own bucket rather than
/// being folded into USD.
public struct CurrencyCode: Codable, Sendable, Hashable, Comparable, CustomStringConvertible {
    /// Uppercased token, e.g. `"USD"`. Never empty (empty input → ``unknown``).
    public let rawValue: String

    /// True when Plaid supplied a real (ISO or unofficial) code. ``unknown`` is
    /// the only instance for which this is `false`.
    public let isResolved: Bool

    private init(rawValue: String, isResolved: Bool) {
        self.rawValue = rawValue
        self.isResolved = isResolved
    }

    /// Fallback bucket for accounts/transactions Plaid returned with no currency
    /// code. Kept distinct from USD so totals never quietly absorb an unknown.
    public static let unknown = CurrencyCode(rawValue: "—", isResolved: false)

    /// The app's reporting/home currency. Aggregates convert *into* this when a
    /// conversion source can supply rates; otherwise per-currency subtotals are
    /// shown. Today this is USD; the type leaves room to make it user-selectable.
    public static let usd = CurrencyCode(rawValue: "USD", isResolved: true)

    /// Builds a code from a raw Plaid string. Whitespace-trimmed and uppercased;
    /// `nil`/empty → ``unknown``.
    public init(_ code: String?) {
        guard let trimmed = code?.trimmingCharacters(in: .whitespacesAndNewlines),
              !trimmed.isEmpty
        else {
            self = .unknown
            return
        }
        self = CurrencyCode(rawValue: trimmed.uppercased(), isResolved: true)
    }

    public init(from decoder: any Decoder) throws {
        let container = try decoder.singleValueContainer()
        self = CurrencyCode(try container.decode(String.self))
    }

    public func encode(to encoder: any Encoder) throws {
        var container = encoder.singleValueContainer()
        try container.encode(isResolved ? rawValue : "")
    }

    public var description: String { rawValue }

    public static func < (lhs: CurrencyCode, rhs: CurrencyCode) -> Bool {
        // Resolved codes sort before the unknown bucket; within each, alphabetical.
        if lhs.isResolved != rhs.isResolved { return lhs.isResolved }
        return lhs.rawValue < rhs.rawValue
    }

    /// Currency-symbol prefix usable as a *non-color* visual cue. For USD this
    /// is `"$"`; for any other resolved code it is the code itself (e.g. `"EUR"`)
    /// so the symbol never silently collapses two currencies into one glyph.
    /// For ``unknown`` it is empty.
    public var symbolHint: String {
        guard isResolved else { return "" }
        return rawValue == "USD" ? "$" : rawValue
    }

    /// VoiceOver-friendly spoken name. Uses the system's localized currency name
    /// when the code is a known ISO currency, else the raw code. Always carries
    /// the currency identity by *text*, never by color (ACCESSIBILITY.md).
    public var accessibleName: String {
        guard isResolved else { return "unknown currency" }
        if let localized = Locale.current.localizedString(forCurrencyCode: rawValue),
           !localized.isEmpty {
            return localized
        }
        return rawValue
    }
}
