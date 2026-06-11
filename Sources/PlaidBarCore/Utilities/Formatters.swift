import Foundation

public enum CurrencyFormat: String, Sendable {
    case full       // $12,450.32
    case abbreviated // $12.4K
    case compact    // $12,450
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

    private static func abbreviatedCurrency(_ amount: Double, currencyCode: String) -> String {
        let sign = amount < 0 ? "-" : ""
        let abs = abs(amount)
        let symbol = currencyCode == "USD" ? "$" : currencyCode

        switch abs {
        case 1_000_000...:
            return "\(sign)\(symbol)\(String(format: "%.1fM", abs / 1_000_000))"
        case 1_000...:
            return "\(sign)\(symbol)\(String(format: "%.1fK", abs / 1_000))"
        default:
            return "\(sign)\(symbol)\(String(format: "%.0f", abs))"
        }
    }

    // MARK: - Dates

    private static let transactionDateFormatter: DateFormatter = {
        let f = DateFormatter()
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
}
