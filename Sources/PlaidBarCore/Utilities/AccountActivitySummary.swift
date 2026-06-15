import Foundation

public struct AccountActivitySummary: Sendable, Equatable {
    public let transactionCount: Int
    public let pendingCount: Int
    public let inflowTotal: Double
    public let outflowTotal: Double
    public let days: Int

    public init(
        transactionCount: Int,
        pendingCount: Int,
        inflowTotal: Double,
        outflowTotal: Double,
        days: Int
    ) {
        self.transactionCount = transactionCount
        self.pendingCount = pendingCount
        self.inflowTotal = inflowTotal
        self.outflowTotal = outflowTotal
        self.days = days
    }

    public static func recent(
        from transactions: [TransactionDTO],
        now: Date? = nil,
        calendar: Calendar = .current,
        days: Int = 30
    ) -> AccountActivitySummary {
        recent(
            from: TransactionDerivedIndex(transactions: transactions),
            now: now,
            calendar: calendar,
            days: days
        )
    }

    public static func recent(
        from index: TransactionDerivedIndex,
        now: Date? = nil,
        calendar: Calendar = .current,
        days: Int = 30
    ) -> AccountActivitySummary {
        recent(from: index.entries, now: now, calendar: calendar, days: days)
    }

    public static func recent(
        from entries: [TransactionDerivedIndex.Entry],
        now: Date? = nil,
        calendar: Calendar = .current,
        days: Int = 30
    ) -> AccountActivitySummary {
        let referenceDate = now ?? latestTransactionDate(in: entries) ?? Date()
        let startDate = calendar.startOfDay(
            for: calendar.date(byAdding: .day, value: -(days - 1), to: referenceDate) ?? referenceDate
        )

        let recentEntries = entries.filter { entry in
            guard let date = entry.parsedDate else { return false }
            return date >= startDate && date <= referenceDate
        }

        var inflowTotal = 0.0
        var outflowTotal = 0.0

        for entry in recentEntries where !entry.isTransfer {
            if entry.isIncome {
                inflowTotal += entry.displayAmount
            } else {
                outflowTotal += entry.displayAmount
            }
        }

        return AccountActivitySummary(
            transactionCount: recentEntries.count,
            pendingCount: recentEntries.count(where: { $0.transaction.pending }),
            inflowTotal: inflowTotal,
            outflowTotal: outflowTotal,
            days: days
        )
    }

    private static func latestTransactionDate(in entries: [TransactionDerivedIndex.Entry]) -> Date? {
        entries
            .compactMap(\.parsedDate)
            .max()
    }
}
