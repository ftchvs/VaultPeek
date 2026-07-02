import Foundation

public enum CurrencyFormat: String, Sendable {
    case full       // $12,450.32
    case abbreviated // $12.4K
    case compact    // $12,450

    /// Number of fraction digits this format renders. The single source of truth
    /// for the rounding-consistency policy (AND-731): a figure shown twice on one
    /// screen, or an aggregate derived from displayed parts, must round to the same
    /// precision so the on-screen numbers reconcile. `abbreviated` collapses to a
    /// K/M magnitude with no meaningful cents, so it shares the whole-unit
    /// precision of `compact`.
    public var displayFractionDigits: Int {
        switch self {
        case .full: return 2
        case .compact, .abbreviated: return 0
        }
    }
}

public enum Formatters {
    // MARK: - Currency

    private static let fullFormatter: NumberFormatter = {
        let f = NumberFormatter()
        f.numberStyle = .currency
        f.currencyCode = "USD"
        f.minimumFractionDigits = 2
        f.maximumFractionDigits = 2
        return f
    }()

    private static let compactFormatter: NumberFormatter = {
        let f = NumberFormatter()
        f.numberStyle = .currency
        f.currencyCode = "USD"
        f.minimumFractionDigits = 0
        f.maximumFractionDigits = 0
        return f
    }()

    /// Rounds `amount` to the precision `format` will *display* (AND-731). Use this
    /// when an aggregate must reconcile with its displayed parts (e.g. net worth ==
    /// displayed assets − displayed debt): round each part with this first, derive
    /// the aggregate from the rounded parts, then format — so the on-screen figures
    /// add up even though the underlying doubles carry sub-cent precision.
    public static func displayRounded(_ amount: Double, format: CurrencyFormat) -> Double {
        let scale = pow(10.0, Double(format.displayFractionDigits))
        return (amount * scale).rounded() / scale
    }

    public static func currency(_ amount: Double, format: CurrencyFormat = .full, currencyCode: String = "USD") -> String {
        switch format {
        case .full:
            if currencyCode == "USD" {
                return fullFormatter.string(from: NSNumber(value: amount)) ?? "$\(amount)"
            }
            guard let formatter = fullFormatter.copy() as? NumberFormatter else { return "$\(amount)" }
            formatter.currencyCode = currencyCode
            return formatter.string(from: NSNumber(value: amount)) ?? "$\(amount)"
        case .abbreviated:
            return abbreviatedCurrency(amount, currencyCode: currencyCode)
        case .compact:
            if currencyCode == "USD" {
                return compactFormatter.string(from: NSNumber(value: amount)) ?? "$\(amount)"
            }
            guard let formatter = compactFormatter.copy() as? NumberFormatter else { return "$\(amount)" }
            formatter.currencyCode = currencyCode
            return formatter.string(from: NSNumber(value: amount)) ?? "$\(amount)"
        }
    }

    /// Formats an amount in a specific ``CurrencyCode``, so non-USD balances and
    /// transactions render in their native currency (e.g. `€1,200.00`, `GBP 80`).
    /// The ``CurrencyCode/unknown`` bucket renders the bare number with no symbol,
    /// since coercing it to `$` would imply a currency Plaid never reported.
    public static func currency(
        _ amount: Double,
        in currencyCode: CurrencyCode,
        format: CurrencyFormat = .full
    ) -> String {
        guard currencyCode.isResolved else {
            return unknownCurrency(amount, format: format)
        }
        return currency(amount, format: format, currencyCode: currencyCode.rawValue)
    }

    private static func unknownCurrency(_ amount: Double, format: CurrencyFormat) -> String {
        switch format {
        case .full:
            return String(format: "%.2f", amount)
        case .compact:
            return String(format: "%.0f", amount)
        case .abbreviated:
            return abbreviatedCurrency(amount, currencyCode: "")
        }
    }

    private static func abbreviatedCurrency(_ amount: Double, currencyCode: String) -> String {
        let sign = amount < 0 ? "-" : ""
        let magnitude = abs(amount)
        let symbol = currencyCode == "USD" ? "$" : currencyCode
        // A symbol that is the bare currency code (e.g. `EUR`) — rather than a
        // glyph like `$` — needs a separator so it does not run into the
        // magnitude as `EUR1.2K`. Use a non-breaking space so the figure never
        // wraps between the code and the number. `$` (and the unknown-currency
        // empty symbol) keep no separator, so USD output is byte-identical.
        let separator = (symbol.isEmpty || symbol == "$") ? "" : "\u{00A0}"

        switch magnitude {
        case 1_000_000...:
            return "\(sign)\(symbol)\(separator)\(String(format: "%.1fM", magnitude / 1_000_000))"
        case 1_000...:
            return "\(sign)\(symbol)\(separator)\(String(format: "%.1fK", magnitude / 1_000))"
        default:
            return "\(sign)\(symbol)\(separator)\(String(format: "%.0f", magnitude))"
        }
    }

    /// Sign-prefixed currency string so direction reads textually — never by color
    /// alone (ACCESSIBILITY.md) — and so VoiceOver/monochrome render it correctly.
    /// `+` for positive, the chosen `minusGlyph` for negative, and **no** prefix for
    /// zero; the magnitude is always `currency(abs(amount), format:)`.
    ///
    /// AND-664 #2 single-sources the half-dozen hand-rolled copies that all built
    /// `prefix + currency(abs(amount))`. The knobs preserve each prior call site's
    /// exact output: `format` (compact vs full), `minusGlyph` (the ASCII
    /// hyphen-minus `-` most sites use, or the typographic U+2212 `−` the
    /// investment row deliberately uses), and `masked` (the sites that replace the
    /// whole value with the Privacy-Mask placeholder when masking is on).
    ///
    /// - Parameter minusGlyph: the glyph used for a negative amount. Defaults to the
    ///   ASCII hyphen-minus `"-"`.
    /// - Parameter masked: when `true`, returns `PrivacyMaskPresentation.compactValue`
    ///   instead of any amount — for the sites that mask the value at this layer.
    public static func signedCurrency(
        _ amount: Double,
        format: CurrencyFormat = .full,
        minusGlyph: String = "-",
        masked: Bool = false
    ) -> String {
        if masked { return PrivacyMaskPresentation.compactValue }
        let magnitude = currency(abs(amount), format: format)
        if amount > 0 { return "+\(magnitude)" }
        if amount < 0 { return "\(minusGlyph)\(magnitude)" }
        return magnitude
    }

    // MARK: - Dates

    private static let transactionDateFormatter: DateFormatter = {
        let f = DateFormatter()
        // Plaid transaction dates are fixed-format Gregorian yyyy-MM-dd. Pin the
        // locale and calendar (Apple QA1480): an unpinned formatter inherits the
        // system calendar, so on a Buddhist- or Japanese-calendar system these
        // keys would parse and render with shifted years (e.g. 2569-06-10),
        // silently corrupting every date bucket and cache comparison.
        f.locale = Locale(identifier: "en_US_POSIX")
        f.calendar = Calendar(identifier: .gregorian)
        f.dateFormat = "yyyy-MM-dd"
        return f
    }()

    private static let displayDateFormatter: DateFormatter = {
        let f = DateFormatter()
        f.dateStyle = .medium
        f.timeStyle = .none
        return f
    }()

    // Computed property — creates a new formatter per call.
    // Called infrequently (once per sync label render), avoids nonisolated(unsafe).
    private static var relativeDateFormatter: RelativeDateTimeFormatter {
        let f = RelativeDateTimeFormatter()
        f.unitsStyle = .short
        return f
    }

    public static func parseTransactionDate(_ dateString: String) -> Date? {
        transactionDateFormatter.date(from: dateString)
    }

    /// Fast structural check that a string is a canonical `yyyy-MM-dd` transaction
    /// date key, as produced by Plaid and `transactionDateString(_:)`. Canonical
    /// keys sort lexicographically in date order, so aggregations can range-filter
    /// with string comparison instead of a `DateFormatter` parse per transaction.
    public static func isCanonicalTransactionDateKey(_ value: String) -> Bool {
        let bytes = Array(value.utf8)
        guard bytes.count == 10 else { return false }
        for (index, byte) in bytes.enumerated() {
            if index == 4 || index == 7 {
                if byte != UInt8(ascii: "-") { return false }
            } else if byte < UInt8(ascii: "0") || byte > UInt8(ascii: "9") {
                return false
            }
        }
        return true
    }

    public static func transactionDateString(_ date: Date) -> String {
        transactionDateFormatter.string(from: date)
    }

    public static func displayDate(_ date: Date) -> String {
        let calendar = Calendar.current
        if calendar.isDateInToday(date) {
            return "Today"
        } else if calendar.isDateInYesterday(date) {
            return "Yesterday"
        } else {
            return displayDateFormatter.string(from: date)
        }
    }

    public static func relativeDate(_ date: Date) -> String {
        relativeDateFormatter.localizedString(for: date, relativeTo: Date())
    }

    /// Parse a YYYY-MM-DD transaction date string and return a display string (Today/Yesterday/medium date).
    /// Returns the raw string if parsing fails.
    public static func displayTransactionDate(_ dateString: String) -> String {
        guard let date = parseTransactionDate(dateString) else { return dateString }
        return displayDate(date)
    }

    // MARK: - Percentages

    public static func percent(_ value: Double, decimals: Int = 1) -> String {
        String(format: "%.\(decimals)f%%", value)
    }

    /// Format a fractional share (`0...1`) as a whole-number percent string, e.g. `0.4267` → `"43%"`.
    /// Rounds to the nearest whole percent (half away from zero) with no decimal places — used for
    /// compact composition/segment share labels. Unlike ``percent(_:decimals:)``, the input is a
    /// fraction, not an already-scaled percentage value.
    public static func percentFromShare(_ share: Double) -> String {
        "\(Int((share * 100).rounded()))%"
    }
}
