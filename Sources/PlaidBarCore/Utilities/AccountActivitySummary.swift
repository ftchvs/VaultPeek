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
        let referenceDate = now ?? latestTransactionDate(in: transactions) ?? Date()
        let startDate = calendar.startOfDay(
            for: calendar.date(byAdding: .day, value: -(days - 1), to: referenceDate) ?? referenceDate
        )

        let recentTransactions = transactions.filter { transaction in
            guard let date = Formatters.parseTransactionDate(transaction.date) else { return false }
            return date >= startDate && date <= referenceDate
        }

        var inflowTotal = 0.0
        var outflowTotal = 0.0

        for transaction in recentTransactions where !transaction.isTransfer {
            if transaction.isIncome {
                inflowTotal += transaction.displayAmount
            } else {
                outflowTotal += transaction.displayAmount
            }
        }

        return AccountActivitySummary(
            transactionCount: recentTransactions.count,
            pendingCount: recentTransactions.filter(\.pending).count,
            inflowTotal: inflowTotal,
            outflowTotal: outflowTotal,
            days: days
        )
    }

    private static func latestTransactionDate(in transactions: [TransactionDTO]) -> Date? {
        transactions
            .compactMap { Formatters.parseTransactionDate($0.date) }
            .max()
    }
}

private extension TransactionDTO {
    var isTransfer: Bool {
        category == .transfer || category == .transferOut
    }
}
