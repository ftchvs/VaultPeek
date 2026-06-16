import Foundation

/// Deterministic strong masking helpers for screen-share/privacy presentation.
///
/// These helpers intentionally return fixed mask strings instead of preserving
/// input length, prefixes, suffixes, last-four digits, dates, or exact numeric
/// magnitude. Missing values pass through as unavailable placeholders so the UI
/// does not imply hidden private data exists when the source value is nil/empty.
public enum StrongMaskFormatter {
    public enum TextSlot: Sendable {
        case primaryLabel
        case secondaryLabel
        case metadata
        case longDescription
        case identifier

        public var mask: String {
            switch self {
            case .primaryLabel:
                return "••••••"
            case .secondaryLabel:
                return "•••• ••••"
            case .metadata:
                return "••••"
            case .longDescription:
                return "•••••• ••••••"
            case .identifier:
                return "••••••••"
            }
        }
    }

    public enum AccessibilityHiddenValue: Sendable {
        case accountName
        case institution
        case merchant
        case description
        case amount
        case date
        case identifier
        case accountMask
        case percentage
        case count

        fileprivate var label: String {
            switch self {
            case .accountName:
                return "Account name hidden"
            case .institution:
                return "Institution hidden"
            case .merchant:
                return "Merchant hidden"
            case .description:
                return "Transaction description hidden"
            case .amount:
                return "Amount hidden"
            case .date:
                return "Date hidden"
            case .identifier:
                return "Identifier hidden"
            case .accountMask:
                return "Account number hidden"
            case .percentage:
                return "Percentage hidden"
            case .count:
                return "Count hidden"
            }
        }
    }

    public static let unavailable = "—"
    public static let maskedMoney = "$••••"
    public static let maskedPercent = "••%"
    public static let maskedDate = "••/••/••"
    public static let maskedDateRange = "••• •• – ••• ••"

    /// Masks a present sensitive string with the fixed placeholder for its UI slot.
    /// Nil, empty, and whitespace-only values return `unavailable` instead of bullets.
    public static func text(_ value: String?, slot: TextSlot, unavailable: String = Self.unavailable) -> String {
        guard hasVisibleContent(value) else { return unavailable }
        return slot.mask
    }

    public static func accountName(_ value: String?, unavailable: String = Self.unavailable) -> String {
        text(value, slot: .primaryLabel, unavailable: unavailable)
    }

    public static func officialAccountName(_ value: String?, unavailable: String = Self.unavailable) -> String {
        text(value, slot: .secondaryLabel, unavailable: unavailable)
    }

    public static func institutionName(_ value: String?, unavailable: String = Self.unavailable) -> String {
        text(value, slot: .primaryLabel, unavailable: unavailable)
    }

    public static func merchantName(_ value: String?, unavailable: String = Self.unavailable) -> String {
        text(value, slot: .primaryLabel, unavailable: unavailable)
    }

    public static func transactionDescription(_ value: String?, unavailable: String = Self.unavailable) -> String {
        text(value, slot: .longDescription, unavailable: unavailable)
    }

    /// Masks the displayed transaction label using merchant copy when present,
    /// otherwise falling back to the raw transaction name/description slot.
    public static func transactionDisplayName(
        merchantName: String?,
        name: String?,
        unavailable: String = Self.unavailable
    ) -> String {
        if hasVisibleContent(merchantName) {
            return self.merchantName(merchantName, unavailable: unavailable)
        }
        return transactionDescription(name, unavailable: unavailable)
    }

    public static func identifier(_ value: String?, unavailable: String = Self.unavailable) -> String {
        text(value, slot: .identifier, unavailable: unavailable)
    }

    public static func accountLastFour(_ value: String?, unavailable: String = Self.unavailable) -> String {
        text(value, slot: .metadata, unavailable: unavailable)
    }

    public static func money(
        _ value: Double?,
        preservesSign: Bool = false,
        unavailable: String = Self.unavailable
    ) -> String {
        guard let value, value.isFinite else { return unavailable }
        guard preservesSign else { return maskedMoney }
        if value < 0 { return "-\(maskedMoney)" }
        if value > 0 { return "+\(maskedMoney)" }
        return maskedMoney
    }

    /// Masks a decimal money value without preserving magnitude, cents, or width.
    public static func money(
        _ value: Decimal?,
        preservesSign: Bool = false,
        unavailable: String = Self.unavailable
    ) -> String {
        guard let value else { return unavailable }
        guard preservesSign else { return maskedMoney }
        if value < 0 { return "-\(maskedMoney)" }
        if value > 0 { return "+\(maskedMoney)" }
        return maskedMoney
    }

    public static func percent(_ value: Double?, unavailable: String = Self.unavailable) -> String {
        guard let value, value.isFinite else { return unavailable }
        return maskedPercent
    }

    public static func count(_ value: Int?, label: String, unavailable: String = Self.unavailable) -> String {
        guard value != nil else { return unavailable }
        let suffix = label.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !suffix.isEmpty else { return "••" }
        return "•• \(suffix)"
    }

    public static func date(_ value: String?, unavailable: String = Self.unavailable) -> String {
        guard hasVisibleContent(value) else { return unavailable }
        return maskedDate
    }

    public static func date(_ value: Date?, unavailable: String = Self.unavailable) -> String {
        guard value != nil else { return unavailable }
        return maskedDate
    }

    public static func dateRange(_ start: String?, _ end: String?, unavailable: String = Self.unavailable) -> String {
        guard hasVisibleContent(start) || hasVisibleContent(end) else { return unavailable }
        return maskedDateRange
    }

    public static func freshness(prefix: String, value: String?, unavailable: String = Self.unavailable) -> String {
        guard hasVisibleContent(value) else { return unavailable }
        let safePrefix = prefix.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !safePrefix.isEmpty else { return "•••" }
        return "\(safePrefix) •••"
    }

    /// Pass-through for lower-sensitivity labels such as account type, category,
    /// pending/posted status, or generic recovery copy.
    public static func generic(_ value: String?, unavailable: String = Self.unavailable) -> String {
        guard let value, hasVisibleContent(value) else { return unavailable }
        return value
    }

    public static func accessibilityLabel(for hiddenValue: AccessibilityHiddenValue) -> String {
        hiddenValue.label
    }

    private static func hasVisibleContent(_ value: String?) -> Bool {
        guard let value else { return false }
        return !value.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }
}
