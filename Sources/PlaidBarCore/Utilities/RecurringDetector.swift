import Foundation

public enum RecurringDetector {
    /// Detect recurring transactions from a list of transactions.
    /// Groups by merchantName, computes date intervals, classifies frequency.
    public static func detect(from transactions: [TransactionDTO]) -> [RecurringTransaction] {
        detect(from: TransactionDerivedIndex(transactions: transactions))
    }

    public static func detect(from index: TransactionDerivedIndex) -> [RecurringTransaction] {
        // Group by merchantName (non-nil only), excluding income
        let grouped = index.merchantBuckets.mapValues { entries in
            entries.filter { !$0.isIncome }
        }

        var results: [RecurringTransaction] = []

        for (merchant, entries) in grouped {
            guard entries.count >= 2 else { continue }

            // Sort by date ascending
            let sorted = entries.sorted { $0.rawDate < $1.rawDate }

            // Compute intervals in days between consecutive transactions
            let intervals = computeIntervals(sorted)
            guard !intervals.isEmpty else { continue }

            let medianInterval = median(intervals)

            // Classify frequency by median interval
            guard let frequency = classifyFrequency(medianInterval: medianInterval) else { continue }

            // Require minimum occurrences
            let minOccurrences = (frequency == .weekly || frequency == .biweekly) ? 3 : 2
            guard sorted.count >= minOccurrences else { continue }

            // Compute confidence from interval consistency
            let confidence = computeConfidence(intervals: intervals, medianInterval: medianInterval)
            guard confidence >= 0.3 else { continue }

            let averageAmount = sorted.reduce(0.0) { $0 + $1.displayAmount } / Double(sorted.count)
            let previousTransactions = sorted.dropLast()
            let trailingAverageAmount = previousTransactions.isEmpty
                ? nil
                : previousTransactions.reduce(0.0) { $0 + $1.displayAmount } / Double(previousTransactions.count)
            let latestAmount = sorted.last!.displayAmount
            let lastDate = sorted.last!.rawDate
            let nextExpected = computeNextDate(from: lastDate, frequency: frequency)
            let category = sorted.last!.category

            results.append(RecurringTransaction(
                merchantName: merchant,
                frequency: frequency,
                averageAmount: averageAmount,
                latestAmount: latestAmount,
                trailingAverageAmount: trailingAverageAmount,
                lastDate: lastDate,
                nextExpectedDate: nextExpected,
                category: category,
                transactionCount: sorted.count,
                confidence: confidence
            ))
        }

        return results.sorted { $0.averageAmount > $1.averageAmount }
    }

    // MARK: - Private Helpers

    static func computeIntervals(_ sorted: [TransactionDTO]) -> [Double] {
        computeIntervals(
            sorted.map {
                TransactionDerivedIndex.EntryForRecurring(
                    rawDate: $0.date,
                    parsedDate: Formatters.parseTransactionDate($0.date)
                )
            }
        )
    }

    static func computeIntervals(_ sorted: [TransactionDerivedIndex.Entry]) -> [Double] {
        computeIntervals(
            sorted.map {
                TransactionDerivedIndex.EntryForRecurring(rawDate: $0.rawDate, parsedDate: $0.parsedDate)
            }
        )
    }

    private static func computeIntervals(_ sorted: [TransactionDerivedIndex.EntryForRecurring]) -> [Double] {
        guard sorted.count >= 2 else { return [] }
        var intervals: [Double] = []
        for i in 1..<sorted.count {
            guard let d1 = sorted[i - 1].parsedDate,
                  let d2 = sorted[i].parsedDate else { continue }
            let days = d2.timeIntervalSince(d1) / 86400.0
            if days > 0 { intervals.append(days) }
        }
        return intervals
    }

    static func median(_ values: [Double]) -> Double {
        let sorted = values.sorted()
        let count = sorted.count
        if count == 0 { return 0 }
        if count % 2 == 0 {
            return (sorted[count / 2 - 1] + sorted[count / 2]) / 2.0
        }
        return sorted[count / 2]
    }

    static func classifyFrequency(medianInterval: Double) -> RecurringFrequency? {
        switch medianInterval {
        case 5...9: return .weekly
        case 12...16: return .biweekly
        case 26...35: return .monthly
        case 80...100: return .quarterly
        case 350...380: return .annual
        default: return nil
        }
    }

    static func computeConfidence(intervals: [Double], medianInterval: Double) -> Double {
        guard medianInterval > 0, !intervals.isEmpty else { return 0 }
        let variance = intervals.reduce(0.0) { $0 + pow($1 - medianInterval, 2) } / Double(intervals.count)
        let stddev = sqrt(variance)
        let coefficient = stddev / medianInterval
        return max(0, 1.0 - coefficient)
    }

    static func computeNextDate(from lastDate: String, frequency: RecurringFrequency) -> String {
        guard let date = Formatters.parseTransactionDate(lastDate) else { return lastDate }
        let calendar = Calendar.current
        let next: Date?
        switch frequency {
        case .weekly:
            next = calendar.date(byAdding: .day, value: 7, to: date)
        case .biweekly:
            next = calendar.date(byAdding: .day, value: 14, to: date)
        case .monthly:
            next = calendar.date(byAdding: .month, value: 1, to: date)
        case .quarterly:
            next = calendar.date(byAdding: .month, value: 3, to: date)
        case .annual:
            next = calendar.date(byAdding: .year, value: 1, to: date)
        }
        return Formatters.transactionDateString(next ?? date)
    }
}

private extension TransactionDerivedIndex {
    struct EntryForRecurring {
        let rawDate: String
        let parsedDate: Date?
    }
}
