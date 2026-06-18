import Foundation

/// Pure month-to-date spend evaluation for watchlist nudges (AND-501).
///
/// Given the current transactions and the user's [WatchlistTarget], computes
/// month-to-date expense spend per target and reports which targets have crossed
/// their threshold. Income and own-account transfers are excluded by reusing
/// `SpendingSummary.expenseTransactions`. Deterministic with an injected `now` +
/// `Calendar` — no hidden `Date()`.
public enum WatchlistEvaluator {
    /// A watchlist target that has crossed its month-to-date threshold.
    public struct Match: Sendable, Equatable, Identifiable {
        public let target: WatchlistTarget
        /// Month-to-date spend at this target (>= the threshold).
        public let currentSpend: Double
        /// `yyyy-MM` key for the month the spend is summed over. Feeds the
        /// dedup key so each month re-arms the nudge.
        public let monthKey: String

        public var id: String { "\(target.id.uuidString)#\(monthKey)" }

        public init(target: WatchlistTarget, currentSpend: Double, monthKey: String) {
            self.target = target
            self.currentSpend = currentSpend
            self.monthKey = monthKey
        }
    }

    /// Evaluate all targets against month-to-date spend.
    ///
    /// - Parameters:
    ///   - transactions: all known transactions (any window).
    ///   - targets: the user's configured watches.
    ///   - now: reference "today" defining the current calendar month.
    ///   - calendar: calendar used to bound the month.
    /// - Returns: one `Match` per target whose month-to-date spend is >= its
    ///   threshold (threshold > 0). Order follows `targets`.
    public static func evaluate(
        transactions: [TransactionDTO],
        targets: [WatchlistTarget],
        now: Date,
        calendar: Calendar = .current
    ) -> [Match] {
        guard !targets.isEmpty else { return [] }

        let monthKey = monthKey(for: now, calendar: calendar)
        let monthStart = monthStartString(for: now, calendar: calendar)

        // Restrict to current-month expense rows once, then sum per target.
        let monthExpenses = SpendingSummary.expenseTransactions(
            from: transactions,
            startingAt: monthStart
        )

        return targets.compactMap { target -> Match? in
            guard target.monthlyThreshold > 0 else { return nil }
            let spend = monthToDateSpend(for: target, in: monthExpenses)
            guard spend >= target.monthlyThreshold else { return nil }
            return Match(target: target, currentSpend: spend, monthKey: monthKey)
        }
    }

    /// Month-to-date spend for one target across already-filtered expense rows.
    static func monthToDateSpend(
        for target: WatchlistTarget,
        in monthExpenses: [TransactionDTO]
    ) -> Double {
        monthExpenses.reduce(0) { total, transaction in
            guard matches(target, transaction) else { return total }
            return total + transaction.displayAmount
        }
    }

    /// Whether a transaction belongs to a target.
    static func matches(_ target: WatchlistTarget, _ transaction: TransactionDTO) -> Bool {
        switch target.kind {
        case .merchant:
            return WatchlistTarget.normalizeMerchant(transaction.displayName) == target.key
        case .category:
            return transaction.category == target.category
        }
    }

    /// `yyyy-MM` key for the month containing `date`.
    static func monthKey(for date: Date, calendar: Calendar) -> String {
        let components = calendar.dateComponents([.year, .month], from: date)
        let year = components.year ?? 0
        let month = components.month ?? 0
        return String(format: "%04d-%02d", year, month)
    }

    /// First-of-month `yyyy-MM-dd` string used to bound month-to-date spend.
    static func monthStartString(for date: Date, calendar: Calendar) -> String {
        let components = calendar.dateComponents([.year, .month], from: date)
        let startOfMonth = calendar.date(from: components) ?? calendar.startOfDay(for: date)
        return Formatters.transactionDateString(startOfMonth)
    }
}
