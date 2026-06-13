public enum NetWorthTrendPresentation: Sendable, Equatable {
    case available(BalanceTrend)
    case insufficientHistory(pointCount: Int, requiredPointCount: Int)

    public static func evaluate(
        history: [BalanceSnapshot],
        now: Date = Date(),
        windowDays: Int = 90,
        calendar: Calendar = .current
    ) -> NetWorthTrendPresentation {
        if let trend = BalanceTrend.evaluate(
            history: history,
            now: now,
            windowDays: windowDays,
            calendar: calendar
        ) {
            return .available(trend)
        }

        let windowStart = calendar.date(
            byAdding: .day,
            value: -(windowDays - 1),
            to: calendar.startOfDay(for: now)
        ) ?? calendar.startOfDay(for: now)
        let pointCount = windowDays > 0
            ? history.filter { $0.date >= windowStart && $0.date <= now }.count
            : 0
        return .insufficientHistory(
            pointCount: pointCount,
            requiredPointCount: BalanceTrend.requiredPointCount
        )
    }

    public var accessibilitySummary: String {
        switch self {
        case let .available(trend):
            return trend.accessibilitySummary
        case let .insufficientHistory(pointCount, requiredPointCount):
            let needed = max(requiredPointCount - pointCount, 0)
            return "Net worth trend unavailable. Needs \(needed) more local balance snapshot\(needed == 1 ? "" : "s")."
        }
    }
}
