import Foundation

/// Gates the projected-balance forecast on having enough history + an anchor
/// (AND-498), mirroring `NetWorthTrendPresentation.available/.insufficientHistory`.
public enum ProjectedBalancePresentation: Sendable, Equatable {
    case available(BalanceProjection)
    case insufficientHistory(pointCount: Int, requiredPointCount: Int)

    /// Build the presentation from balance history + detected recurring streams.
    ///
    /// Requires at least `requiredPointCount` snapshots so a forecast is not drawn
    /// off a single data point. Uses the most recent snapshot as the anchor.
    public static func evaluate(
        history: [BalanceSnapshot],
        recurring: [RecurringTransaction],
        now: Date = Date(),
        horizonDays: Int = PlaidBarConstants.projectedBalanceDefaultHorizonDays,
        requiredPointCount: Int = PlaidBarConstants.projectedBalanceMinimumHistoryPoints,
        calendar: Calendar = .current
    ) -> ProjectedBalancePresentation {
        guard history.count >= requiredPointCount else {
            return .insufficientHistory(
                pointCount: history.count,
                requiredPointCount: requiredPointCount
            )
        }
        // Anchor on the latest snapshot by date.
        let anchor = history.max { $0.date < $1.date }
        guard let projection = BalanceProjector.project(
            anchor: anchor,
            recurring: recurring,
            asOf: now,
            horizonDays: horizonDays,
            calendar: calendar
        ) else {
            return .insufficientHistory(
                pointCount: history.count,
                requiredPointCount: requiredPointCount
            )
        }
        return .available(projection)
    }

    public var accessibilitySummary: String {
        switch self {
        case let .available(projection):
            return projection.accessibilitySummary
        case let .insufficientHistory(pointCount, requiredPointCount):
            let needed = max(requiredPointCount - pointCount, 0)
            return "Balance forecast unavailable. Needs \(needed) more local balance snapshot\(needed == 1 ? "" : "s")."
        }
    }

    public var projection: BalanceProjection? {
        if case let .available(projection) = self { return projection }
        return nil
    }
}
