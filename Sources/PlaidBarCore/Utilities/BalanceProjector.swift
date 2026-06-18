import Foundation

/// Builds an on-device forward cash-flow forecast (AND-498).
///
/// Anchors on the latest net-balance snapshot ("today") and walks each detected
/// recurring stream forward across the horizon, applying its `averageAmount` on
/// every occurrence day. Outflow obligations subtract; recurring income (when
/// any `.income` stream is present) adds — reusing the exact classification gate
/// proven in `SafeToSpendCalculator` (confidence >= `minimumObligationConfidence`,
/// `isOutflowObligation`, skip transfers).
///
/// Unlike safe-to-spend — which counts only the single next occurrence in one
/// window — the projector steps each stream by `RecurringFrequency.estimatedDays`
/// across the whole horizon, building a running daily balance. Pure, Sendable,
/// deterministic with an injected `asOf` + `Calendar`.
public enum BalanceProjector {
    /// Recurring streams below this confidence are ignored, matching
    /// `SafeToSpendCalculator.minimumObligationConfidence`.
    public static let minimumConfidence = SafeToSpendCalculator.minimumObligationConfidence

    /// Project the forward balance series.
    ///
    /// - Parameters:
    ///   - anchor: latest net-balance snapshot (today). Its `balance` seeds the line.
    ///   - recurring: detected recurring streams.
    ///   - asOf: reference "today". Occurrences are walked from here forward.
    ///   - horizonDays: forward window length (clamped to >= 1).
    ///   - calendar: calendar used to step days.
    /// - Returns: a `BalanceProjection`, or nil when there is no anchor.
    public static func project(
        anchor: BalanceSnapshot?,
        recurring: [RecurringTransaction],
        asOf date: Date,
        horizonDays: Int = PlaidBarConstants.projectedBalanceDefaultHorizonDays,
        calendar: Calendar = .current
    ) -> BalanceProjection? {
        guard let anchor else { return nil }
        let horizon = max(horizonDays, 1)
        let startDay = calendar.startOfDay(for: date)
        guard let horizonEnd = calendar.date(byAdding: .day, value: horizon, to: startDay) else {
            return nil
        }

        // Per-day net delta across the horizon, keyed by day index 1...horizon.
        var deltasByDayIndex: [Int: Double] = [:]
        var hasSignal = false

        for stream in recurring {
            guard stream.confidence >= minimumConfidence else { continue }
            guard let kind = classify(stream) else { continue }
            hasSignal = true

            let signed: Double
            switch kind {
            case .outflow: signed = -max(stream.averageAmount, 0)
            case .income: signed = max(stream.averageAmount, 0)
            }
            guard signed != 0 else { continue }

            // Walk occurrences from nextExpectedDate forward by estimatedDays.
            guard var occurrence = Formatters.parseTransactionDate(stream.nextExpectedDate)
                .map({ calendar.startOfDay(for: $0) })
            else { continue }
            let step = stream.frequency.estimatedDays

            // Skip any occurrence already in the past relative to the anchor.
            while occurrence < startDay {
                guard let next = calendar.date(byAdding: .day, value: step, to: occurrence) else { break }
                occurrence = next
            }

            while occurrence <= horizonEnd {
                if let dayIndex = calendar.dateComponents([.day], from: startDay, to: occurrence).day,
                   dayIndex >= 1, dayIndex <= horizon {
                    deltasByDayIndex[dayIndex, default: 0] += signed
                }
                guard let next = calendar.date(byAdding: .day, value: step, to: occurrence) else { break }
                occurrence = next
            }
        }

        // Build the running daily series: index 0 = anchor, 1...horizon forward.
        var series: [BalanceSnapshot] = []
        series.reserveCapacity(horizon + 1)
        var running = anchor.balance
        series.append(BalanceSnapshot(date: startDay, balance: running))
        for dayIndex in 1...horizon {
            running += deltasByDayIndex[dayIndex] ?? 0
            let day = calendar.date(byAdding: .day, value: dayIndex, to: startDay) ?? startDay
            series.append(BalanceSnapshot(date: day, balance: running))
        }

        // Projected low = the minimum across the whole series (earliest wins on ties).
        let projectedLow = series.min { lhs, rhs in
            if lhs.balance != rhs.balance { return lhs.balance < rhs.balance }
            return lhs.date < rhs.date
        } ?? series[0]

        let confidence: SafeToSpendConfidence = hasSignal ? .lowConfidence : .insufficientData
        let summary = accessibilitySummary(
            anchor: anchor.balance,
            end: running,
            low: projectedLow,
            horizon: horizon,
            confidence: confidence,
            calendar: calendar
        )

        return BalanceProjection(
            series: series,
            projectedLow: projectedLow,
            confidence: confidence,
            accessibilitySummary: summary
        )
    }

    // MARK: - Classification

    private enum StreamKind { case outflow, income }

    private static func classify(_ stream: RecurringTransaction) -> StreamKind? {
        switch stream.category {
        case .income:
            return .income
        case .transfer, .transferOut:
            // Own-account transfers net out; skip them.
            return nil
        default:
            return .outflow
        }
    }

    private static func accessibilitySummary(
        anchor: Double,
        end: Double,
        low: BalanceSnapshot,
        horizon: Int,
        confidence: SafeToSpendConfidence,
        calendar: Calendar
    ) -> String {
        let direction = end < anchor ? "down" : (end > anchor ? "up" : "flat")
        let lowText = Formatters.currency(low.balance, format: .compact)
        let lowDate = Formatters.displayTransactionDate(Formatters.transactionDateString(low.date))
        let confidenceText: String
        switch confidence {
        case .insufficientData: confidenceText = "No recurring signal yet, so this is indicative only."
        case .lowConfidence: confidenceText = "Estimated from recurring patterns."
        case .ok: confidenceText = ""
        }
        let base = "Projected balance over \(horizon) days trends \(direction), reaching a low of \(lowText) on \(lowDate)."
        return confidenceText.isEmpty ? base : "\(base) \(confidenceText)"
    }
}
