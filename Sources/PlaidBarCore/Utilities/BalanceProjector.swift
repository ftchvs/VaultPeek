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
        // Seed the line at the anchor snapshot's own date, not `asOf`. When the
        // latest balance point is stale (older than `asOf` after offline days),
        // relabeling it as "today" would both fake a fresh balance and skip any
        // recurring occurrences that fell between the snapshot and now. Anchoring
        // on the snapshot date keeps the seed honest and walks those occurrences;
        // when the anchor is current this is identical to starting at `asOf`.
        let asOfDay = calendar.startOfDay(for: date)
        let startDay = min(calendar.startOfDay(for: anchor.date), asOfDay)
        guard let horizonEnd = calendar.date(byAdding: .day, value: horizon, to: asOfDay) else {
            return nil
        }

        // Total day span the series covers: from the (possibly stale) anchor day
        // through the forward horizon end. Equals `horizon` when the anchor is
        // current; larger when it is stale (the extra days back-fill the gap).
        let totalDays = max(
            calendar.dateComponents([.day], from: startDay, to: horizonEnd).day ?? horizon,
            horizon
        )

        // Per-day net delta across the span, keyed by day index 0...totalDays.
        // Index 0 captures any obligation due exactly on the anchor day; it is
        // folded into the seed below so the anchor snapshot already reflects it.
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
                   dayIndex >= 0, dayIndex <= totalDays {
                    deltasByDayIndex[dayIndex, default: 0] += signed
                }
                guard let next = calendar.date(byAdding: .day, value: step, to: occurrence) else { break }
                occurrence = next
            }
        }

        // Build the running daily series: index 0 = anchor (its true snapshot
        // day), 1...totalDays forward through the horizon end.
        var series: [BalanceSnapshot] = []
        series.reserveCapacity(totalDays + 1)
        // Fold any day-0 obligation (due exactly on the anchor day) into the seed
        // so the projected line agrees with SafeToSpendCalculator's inclusive
        // (nextDay >= referenceDay) window. The 1...totalDays loop starts at 1,
        // so this does not double-count the day-0 delta.
        var running = anchor.balance + (deltasByDayIndex[0] ?? 0)
        series.append(BalanceSnapshot(date: startDay, balance: running))
        for dayIndex in 1...totalDays {
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
            horizon: totalDays,
            confidence: confidence,
            calendar: calendar
        )

        return BalanceProjection(
            series: series,
            projectedLow: projectedLow,
            confidence: confidence,
            accessibilitySummary: summary,
            band: uncertaintyBand(series: series, confidence: confidence)
        )
    }

    // MARK: - Uncertainty band

    /// Half-width multiplier per confidence tier: higher confidence → narrower
    /// band. Public so a chart legend can explain the band width honestly.
    public static func bandHalfWidthScale(for confidence: SafeToSpendConfidence) -> Double {
        switch confidence {
        case .ok: 0.5
        case .lowConfidence: 1.0
        case .insufficientData: 1.5
        }
    }

    /// Deterministic uncertainty band around a projected series.
    ///
    /// The band's unit is the series' own mean absolute day-over-day movement
    /// (no randomness, no external state), scaled by the confidence tier; the
    /// half-width then grows with the square root of days out — the standard
    /// "uncertainty compounds like a random walk" shape. Day 0 (the anchor,
    /// a real recorded balance) always has zero width. Returns `nil` when the
    /// series never moves (no recurring signal): a band sized from zero
    /// movement would be a fake-precision zero-width ribbon.
    ///
    /// Invariant: `low <= series balance <= high` on every day, and the width
    /// is non-decreasing across the horizon.
    static func uncertaintyBand(
        series: [BalanceSnapshot],
        confidence: SafeToSpendConfidence
    ) -> [BalanceProjection.BandPoint]? {
        guard series.count >= 2 else { return nil }
        var totalMovement = 0.0
        for index in 1..<series.count {
            totalMovement += abs(series[index].balance - series[index - 1].balance)
        }
        guard totalMovement > 0 else { return nil }

        let unit = bandHalfWidthScale(for: confidence) * (totalMovement / Double(series.count - 1))
        return series.enumerated().map { dayIndex, point in
            let halfWidth = unit * Double(dayIndex).squareRoot()
            return BalanceProjection.BandPoint(
                date: point.date,
                low: point.balance - halfWidth,
                high: point.balance + halfWidth
            )
        }
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
