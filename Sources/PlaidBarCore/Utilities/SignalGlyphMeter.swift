import Foundation

/// Pure value→geometry mapping for the menu-bar "signal glyph" — a code-drawn
/// monochrome template meter that shows a live signal (v1: highest credit-card
/// utilization) as a fill height, with severity carried by SHAPE (an
/// over-threshold cap), not color, since template images cannot tint (AND-485).
///
/// All clamping, empty-history, and divide-by-zero guards live here so the
/// drawing layer (`SignalGlyphImage`, app target) is a dumb renderer. The bar
/// form reads `MenuBarSummary.highestUtilization` (the worst single card, which
/// is what the menu-bar meter promises) and the sparkline form reuses
/// `AccountSparkline.normalize`.
public enum SignalGlyphMeter {

    /// Severity band, expressed as a discrete shape cue (NOT color). The drawing
    /// layer renders `.overThreshold` with a distinct cap so an over-limit
    /// signal is legible in a monochrome menu bar.
    public enum SeverityBand: String, Sendable, Equatable {
        /// Below the threshold: a plain capless bar.
        case calm
        /// At or above the threshold: a capped/notched bar.
        case overThreshold
    }

    /// How the model wants the glyph drawn for staleness, again as shape, not
    /// color: a dashed/half-height treatment reads as "stale" in monochrome.
    public enum StalenessHint: String, Sendable, Equatable {
        case fresh
        case stale
    }

    /// A render-ready description of the meter geometry. The renderer maps
    /// `fillFraction` (0...1) onto the glyph height and applies the severity and
    /// staleness shape cues. `polyline` is populated for the sparkline form.
    public struct SignalGlyphRenderModel: Sendable, Equatable {
        /// Bar fill height as a fraction of the glyph height, clamped to 0...1.
        public let fillFraction: Double
        /// Severity band (shape cue, not color).
        public let severity: SeverityBand
        /// Staleness rendering hint (shape cue, not color).
        public let staleness: StalenessHint
        /// `true` when there is no signal to draw (e.g. no credit limit). The
        /// renderer should fall back to the plain icon rather than an empty bar.
        public let isEmpty: Bool
        /// Optional downsampled, normalized polyline (0...1) for the sparkline
        /// form. Empty for the bar form.
        public let polyline: [Double]

        public init(
            fillFraction: Double,
            severity: SeverityBand,
            staleness: StalenessHint,
            isEmpty: Bool,
            polyline: [Double] = []
        ) {
            self.fillFraction = fillFraction
            self.severity = severity
            self.staleness = staleness
            self.isEmpty = isEmpty
            self.polyline = polyline
        }

        /// The model the renderer uses when there is no signal: a no-meter
        /// sentinel that degrades to the plain icon (mirrors `.iconOnly`).
        public static let empty = SignalGlyphRenderModel(
            fillFraction: 0,
            severity: .calm,
            staleness: .fresh,
            isEmpty: true
        )

        /// A VoiceOver phrase for the meter, conveying value, over-threshold,
        /// and staleness in WORDS (never color). The menu-bar parent view sets
        /// one `.accessibilityLabel`, which overrides the child glyph image, so
        /// the meter's signal would otherwise be silent for non-utilization
        /// title modes; the view folds this phrase into that label. Returns nil
        /// for the empty model (nothing to announce). The fill is read back as a
        /// rounded percent of the meter — the v1 bar's fill is the highest
        /// credit-card utilization, so it doubles as the spoken value.
        public var accessibilityDescription: String? {
            guard !isEmpty else { return nil }
            let percent = Int((fillFraction * 100).rounded())
            var phrase = "Signal meter \(percent) percent"
            if severity == .overThreshold {
                phrase += ", over threshold"
            }
            if staleness == .stale {
                phrase += ", stale"
            }
            return phrase
        }
    }

    /// Maps a normalized magnitude onto a bar-fill model.
    ///
    /// - Parameters:
    ///   - magnitude: signal magnitude; clamped to 0...1 (values above 1, e.g.
    ///     an over-limit card, cap at full fill).
    ///   - threshold: optional 0...1 boundary above which the band is
    ///     `.overThreshold`. `nil` keeps the band `.calm`.
    ///   - isStale: when `true`, the staleness hint flips regardless of magnitude.
    public static func bar(
        magnitude: Double,
        threshold: Double? = nil,
        isStale: Bool = false
    ) -> SignalGlyphRenderModel {
        let clamped = clamp01(magnitude)
        let band: SeverityBand
        if let threshold, clamped >= clamp01(threshold) {
            band = .overThreshold
        } else {
            band = .calm
        }
        return SignalGlyphRenderModel(
            fillFraction: clamped,
            severity: band,
            staleness: isStale ? .stale : .fresh,
            isEmpty: false
        )
    }

    /// Builds the v1 utilization bar model from accounts, reusing
    /// `MenuBarSummary.highestUtilization` so the meter shows the worst single
    /// card — the signal Settings promises ("your highest credit-card
    /// utilization"). The pooled `creditUtilization` aggregate can read calm
    /// while one card is near-maxed, so the meter must not use it. Returns the
    /// `.empty` model when no credit card reports a positive limit.
    ///
    /// - Parameters:
    ///   - accounts: all accounts (credit cards are filtered internally).
    ///   - thresholdPercent: the user's credit-utilization warning threshold,
    ///     e.g. 30 (percent). Mapped onto 0...1.
    ///   - isStale: sync-staleness flag from the menu-bar status.
    public static func utilization(
        from accounts: [AccountDTO],
        thresholdPercent: Double,
        isStale: Bool = false
    ) -> SignalGlyphRenderModel {
        guard let utilizationPercent = MenuBarSummary.highestUtilization(from: accounts) else {
            return .empty
        }
        return bar(
            magnitude: utilizationPercent / 100,
            threshold: thresholdPercent / 100,
            isStale: isStale
        )
    }

    /// Builds a sparkline model from a balance history, reusing
    /// `AccountSparkline.normalize`. A flat/empty series collapses to a defined
    /// mid-line (0.5), never NaN, mirroring the row sparkline's flat guard.
    ///
    /// - Parameters:
    ///   - balances: balance points, oldest first.
    ///   - maxPoints: downsample cap so the menu-bar glyph stays a few px wide.
    ///   - isStale: sync-staleness flag.
    public static func sparkline(
        balances: [Double],
        maxPoints: Int = 12,
        isStale: Bool = false
    ) -> SignalGlyphRenderModel {
        guard !balances.isEmpty else { return .empty }
        let normalized = AccountSparkline.normalize(balances)
        guard !normalized.isEmpty else {
            return SignalGlyphRenderModel(
                fillFraction: 0.5,
                severity: .calm,
                staleness: isStale ? .stale : .fresh,
                isEmpty: false,
                polyline: [0.5]
            )
        }
        let points = downsample(normalized, to: max(2, maxPoints))
        // The trailing point doubles as the bar fill so a renderer that only
        // draws a bar still shows the latest value.
        return SignalGlyphRenderModel(
            fillFraction: clamp01(points.last ?? 0.5),
            severity: .calm,
            staleness: isStale ? .stale : .fresh,
            isEmpty: false,
            polyline: points
        )
    }

    // MARK: - Helpers

    private static func clamp01(_ value: Double) -> Double {
        guard value.isFinite else { return 0 }
        return min(max(value, 0), 1)
    }

    /// Evenly downsamples a series to at most `count` points, always keeping the
    /// first and last so the trend endpoints survive.
    private static func downsample(_ values: [Double], to count: Int) -> [Double] {
        guard values.count > count, count >= 2 else { return values }
        let step = Double(values.count - 1) / Double(count - 1)
        return (0 ..< count).map { index in
            let position = Int((Double(index) * step).rounded())
            return values[min(position, values.count - 1)]
        }
    }
}
