import Foundation

public enum PrivacyMaskPresentation {
    public enum Style: Sendable {
        case compact
        case hero
        case detail
    }

    public static let compactValue = "••••"
    public static let heroValue = "Private"
    public static let detailValue = "Hidden while Privacy Mask is on"

    public static func value(
        _ unmaskedValue: String,
        isEnabled: Bool,
        style: Style = .compact
    ) -> String {
        guard isEnabled else { return unmaskedValue }

        switch style {
        case .compact:
            return compactValue
        case .hero:
            return heroValue
        case .detail:
            return detailValue
        }
    }

    public static func currency(
        _ amount: Double,
        format: CurrencyFormat = .full,
        isEnabled: Bool,
        style: Style = .compact
    ) -> String {
        value(Formatters.currency(amount, format: format), isEnabled: isEnabled, style: style)
    }

    public static func percent(
        _ percent: Double,
        decimals: Int = 0,
        isEnabled: Bool,
        style: Style = .compact
    ) -> String {
        value(Formatters.percent(percent, decimals: decimals), isEnabled: isEnabled, style: style)
    }

    public static func maskedHelpText(isEnabled: Bool) -> String? {
        isEnabled ? detailValue : nil
    }
}