import Foundation

/// On-device forward cash-flow forecast (AND-498).
///
/// A dated forward `[BalanceSnapshot]` series stepping the anchor balance down
/// (and up, where recurring income exists) across the horizon as detected
/// recurring obligations come due, plus the projected-low point and a confidence
/// matching `SafeToSpendConfidence` semantics. Pure value type — produced by
/// `BalanceProjector`, rendered by `ProjectedBalanceChart`.
public struct BalanceProjection: Sendable, Equatable {
    /// One day of the uncertainty band around the projected line:
    /// `low <= projected balance <= high` on `date`.
    public struct BandPoint: Sendable, Equatable {
        public let date: Date
        public let low: Double
        public let high: Double

        public init(date: Date, low: Double, high: Double) {
            self.date = date
            self.low = low
            self.high = high
        }
    }

    /// Forward daily balance series, oldest (the anchor, today) first. Length is
    /// `horizonDays + 1` — index 0 is the anchor day, the rest are future days.
    public let series: [BalanceSnapshot]
    /// The lowest projected balance over the horizon (the dip to watch).
    public let projectedLow: BalanceSnapshot
    /// How much to trust the forecast — same ladder as safe-to-spend.
    public let confidence: SafeToSpendConfidence
    /// Pre-rendered VoiceOver summary so meaning never relies on the line's
    /// dash/color alone (ACCESSIBILITY.md).
    public let accessibilitySummary: String
    /// Deterministic uncertainty band around `series`, one point per series
    /// day, widening ~sqrt(days out) and scaled by `confidence` (higher
    /// confidence → narrower). `nil` when there is no recurring signal to size
    /// the band honestly (and for callers that never computed one).
    public let band: [BandPoint]?

    public init(
        series: [BalanceSnapshot],
        projectedLow: BalanceSnapshot,
        confidence: SafeToSpendConfidence,
        accessibilitySummary: String,
        band: [BandPoint]? = nil
    ) {
        self.series = series
        self.projectedLow = projectedLow
        self.confidence = confidence
        self.accessibilitySummary = accessibilitySummary
        self.band = band
    }

    /// The anchor (today) balance the projection starts from.
    public var anchorBalance: Double { series.first?.balance ?? projectedLow.balance }
    /// The projected balance at the end of the horizon.
    public var endBalance: Double { series.last?.balance ?? projectedLow.balance }
}
