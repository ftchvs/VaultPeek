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

    // MARK: - Quick toggle affordance (popover eye button, ⌥-click, shortcut)

    /// SF Symbol for the quick Privacy Mask toggle. State is carried by the glyph
    /// SHAPE (struck-through eye when hidden, plain eye when visible), never by
    /// color alone.
    public static func toggleSymbolName(isMasked: Bool) -> String {
        isMasked ? "eye.slash" : "eye"
    }

    /// Verb-first action label for the toggle control — describes what a tap
    /// DOES next, so it doubles as the tooltip and the accessibility label.
    public static func toggleActionLabel(isMasked: Bool) -> String {
        isMasked ? "Show amounts" : "Hide amounts"
    }
}