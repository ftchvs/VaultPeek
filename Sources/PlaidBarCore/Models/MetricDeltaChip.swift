import Foundation

/// Display-ready comparison chip: the glyph, text, sentiment, and VoiceOver
/// label a view needs to render a "so what?" delta next to a hero number —
/// with zero math left in the view layer.
public struct MetricDeltaChip: Sendable, Equatable {
    /// Which figures the chip text carries.
    public enum Style: Sendable, Equatable {
        /// Signed currency only: `+$420 vs last month`.
        case currency
        /// Signed percent only: `+14% vs last month`.
        case percent
        /// Both: `+$420 (+14%) vs last month`.
        case currencyAndPercent
    }

    /// Direction glyph (▲/▼/■), same convention as `GlanceSnapshot.ChangeDirection`.
    public let glyph: String
    /// Chip body, e.g. `+$420 vs last month`.
    public let text: String
    /// Resolved direction × polarity feel for tinting (never color alone —
    /// the glyph + signed text carry the meaning textually).
    public let sentiment: MetricDelta.Sentiment
    /// Fully spoken label with no glyphs or symbols, e.g.
    /// `Up 420 dollars versus last month`.
    public let accessibilityLabel: String

    public init(
        glyph: String,
        text: String,
        sentiment: MetricDelta.Sentiment,
        accessibilityLabel: String
    ) {
        self.glyph = glyph
        self.text = text
        self.sentiment = sentiment
        self.accessibilityLabel = accessibilityLabel
    }

    /// Build a chip from a delta, or `nil` when nothing should render.
    ///
    /// **Privacy Mask suppresses the chip entirely** (`isMasked` → `nil`).
    /// A delta is metadata *derived from* a private figure, so it is dropped
    /// under mask exactly like `DashboardGoalsCard` drops its pace label —
    /// never rendered as `▲ ••••`: even a bare arrow leaks which way a hidden
    /// number moved.
    ///
    /// A `.flat` delta also returns `nil` unless `showsFlat` is requested, so
    /// insignificant movement stays silent by default.
    ///
    /// - Parameters:
    ///   - delta: the classified comparison.
    ///   - comparisonLabel: trailing context, e.g. `"vs last month"` (see
    ///     `ComparisonPeriod.comparisonLabel`). A leading `"vs "` is spoken as
    ///     `"versus "` in the accessibility label.
    ///   - format: currency format for the signed amount.
    ///   - style: which figures the text carries. Percent styles fall back to
    ///     the signed currency amount when `percentChange` is `nil` (no honest
    ///     percentage exists) rather than inventing one.
    ///   - showsFlat: when `true`, a flat delta renders as `■` + "Unchanged".
    ///   - isMasked: Privacy Mask state; `true` suppresses the chip.
    public static func make(
        delta: MetricDelta,
        comparisonLabel: String,
        format: CurrencyFormat = .compact,
        style: Style = .currency,
        showsFlat: Bool = false,
        isMasked: Bool
    ) -> MetricDeltaChip? {
        guard !isMasked else { return nil }
        if delta.direction == .flat, !showsFlat { return nil }

        let text: String
        let spokenBody: String
        if delta.direction == .flat {
            text = "Unchanged \(comparisonLabel)"
            spokenBody = "Unchanged"
        } else {
            let amountText = delta.signedText(format: format)
            let percentText = delta.percentText()
            let figure: String
            switch style {
            case .currency:
                figure = amountText
            case .percent:
                figure = percentText ?? amountText
            case .currencyAndPercent:
                figure = percentText.map { "\(amountText) (\($0))" } ?? amountText
            }
            text = "\(figure) \(comparisonLabel)"
            spokenBody = "\(directionWord(delta.direction)) \(spokenFigure(delta: delta, style: style))"
        }

        return MetricDeltaChip(
            glyph: delta.glyph,
            text: text,
            sentiment: delta.sentiment,
            accessibilityLabel: "\(spokenBody) \(spokenComparison(comparisonLabel))"
        )
    }

    // MARK: - Spoken composition

    private static func directionWord(_ direction: GlanceSnapshot.ChangeDirection) -> String {
        switch direction {
        case .up: "Up"
        case .down: "Down"
        case .flat: "Unchanged"
        }
    }

    /// The chip's figure in words: `420 dollars`, `14 percent`, or
    /// `420 dollars, 14 percent` — no `$`/`%` symbols, no sign glyphs (the
    /// direction word already carries the sign).
    private static func spokenFigure(delta: MetricDelta, style: Style) -> String {
        let dollars = spokenDollars(abs(delta.delta))
        guard let percentChange = delta.percentChange else { return dollars }
        let percent = "\(Int(abs(percentChange).rounded())) percent"
        switch style {
        case .currency: return dollars
        case .percent: return percent
        case .currencyAndPercent: return "\(dollars), \(percent)"
        }
    }

    /// `420.5` → `"421 dollars"`, `1` → `"1 dollar"`. Whole-dollar precision
    /// matches the chip's compact visual style.
    private static func spokenDollars(_ magnitude: Double) -> String {
        let rounded = Int(magnitude.rounded())
        return rounded == 1 ? "1 dollar" : "\(rounded) dollars"
    }

    /// `"vs last month"` → `"versus last month"` so VoiceOver never reads a
    /// bare "vs".
    private static func spokenComparison(_ label: String) -> String {
        label.hasPrefix("vs ") ? "versus \(label.dropFirst(3))" : label
    }
}
