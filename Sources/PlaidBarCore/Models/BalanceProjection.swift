import Foundation

/// On-device forward cash-flow forecast (AND-498).
///
/// A dated forward `[BalanceSnapshot]` series stepping the anchor balance down
/// (and up, where recurring income exists) across the horizon as detected
/// recurring obligations come due, plus the projected-low point and a confidence
/// matching `SafeToSpendConfidence` semantics. Pure value type — produced by
/// `BalanceProjector`, rendered by `ProjectedBalanceChart`.
public struct BalanceProjection: Sendable, Equatable {
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

    public init(
        series: [BalanceSnapshot],
        projectedLow: BalanceSnapshot,
        confidence: SafeToSpendConfidence,
        accessibilitySummary: String
    ) {
        self.series = series
        self.projectedLow = projectedLow
        self.confidence = confidence
        self.accessibilitySummary = accessibilitySummary
    }

    /// The anchor (today) balance the projection starts from.
    public var anchorBalance: Double { series.first?.balance ?? projectedLow.balance }
    /// The projected balance at the end of the horizon.
    public var endBalance: Double { series.last?.balance ?? projectedLow.balance }
}
