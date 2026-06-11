import Foundation

/// Display-safe summary of the recorded net-worth history for the dashboard
/// header sparkline: trend direction, signed delta, and the honest day span
/// the data actually covers (which can be shorter than the requested window
/// while history is still accumulating).
public struct BalanceTrend: Sendable {
    public enum Direction: Sendable {
        case up
        case down
        case flat
    }

    public let direction: Direction
    public let delta: Double
    public let spanDays: Int
    public let points: [BalanceSnapshot]

    /// Signed compact delta, e.g. "+$1.2K", "-$420".
    public var deltaText: String {
        let magnitude = Formatters.currency(abs(delta), format: .abbreviated)
        switch direction {
        case .up:
            return "+\(magnitude)"
        case .down:
            return "-\(magnitude)"
        case .flat:
            return magnitude
        }
    }

    public var spanText: String {
        "\(spanDays)D"
    }

    public var accessibilitySummary: String {
        let change: String
        switch direction {
        case .up:
            change = "up \(Formatters.currency(abs(delta), format: .full))"
        case .down:
            change = "down \(Formatters.currency(abs(delta), format: .full))"
        case .flat:
            change = "unchanged"
        }
        return "Net worth \(change) over the last \(spanDays) day\(spanDays == 1 ? "" : "s")."
    }

    public static func evaluate(
        history: [BalanceSnapshot],
        now: Date = Date(),
        windowDays: Int = 90,
        calendar: Calendar = .current
    ) -> BalanceTrend? {
        guard windowDays > 0 else { return nil }
        let windowStart = calendar.date(byAdding: .day, value: -(windowDays - 1), to: calendar.startOfDay(for: now))
            ?? calendar.startOfDay(for: now)

        let points = history
            .filter { $0.date >= windowStart && $0.date <= now }
            .sorted { $0.date < $1.date }

        guard let first = points.first, let last = points.last, points.count >= 2 else {
            return nil
        }

        let delta = last.balance - first.balance
        let direction: Direction = if abs(delta) < 0.005 {
            .flat
        } else if delta > 0 {
            .up
        } else {
            .down
        }

        let spanDays = max(calendar.dateComponents([.day], from: first.date, to: last.date).day ?? 1, 1)

        return BalanceTrend(
            direction: direction,
            delta: delta,
            spanDays: spanDays,
            points: points
        )
    }
}
