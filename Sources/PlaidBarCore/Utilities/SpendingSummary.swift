import Foundation

public struct SpendingPeriodSummary: Sendable {
    public let currentTotal: Double
    public let previousTotal: Double
    public let delta: Double
    public let deltaPercent: Double
    public let categories: [(SpendingCategory, Double)]

    public init(
        currentTotal: Double,
        previousTotal: Double,
        categories: [(SpendingCategory, Double)]
    ) {
        self.currentTotal = currentTotal
        self.previousTotal = previousTotal
        self.delta = currentTotal - previousTotal
        self.deltaPercent = previousTotal > 0 ? (delta / previousTotal) * 100 : 0
        self.categories = categories
    }
}

public enum SpendingSummary {
    public static func periodSummary(
        from transactions: [TransactionDTO],
        currentStart: String,
        previousStart: String
    ) -> SpendingPeriodSummary {
        let currentExpenses = expenseTransactions(
            from: transactions,
            startingAt: currentStart
        )
        let previousExpenses = expenseTransactions(
            from: transactions,
            startingAt: previousStart,
            endingBefore: currentStart
        )

        let categories = spendingByCategory(from: currentExpenses)
        let currentTotal = categories.reduce(0) { $0 + $1.1 }
        let previousTotal = previousExpenses.reduce(0) { $0 + $1.displayAmount }

        return SpendingPeriodSummary(
            currentTotal: currentTotal,
            previousTotal: previousTotal,
            categories: categories
        )
    }

    public static func spendingByCategory(
        from transactions: [TransactionDTO]
    ) -> [(SpendingCategory, Double)] {
        let grouped = Dictionary(grouping: expenseTransactions(from: transactions)) {
            $0.category ?? .other
        }
        return grouped.map { category, transactions in
            (category, transactions.reduce(0) { $0 + $1.displayAmount })
        }.sorted { $0.1 > $1.1 }
    }

    public static func expenseTransactions(
        from transactions: [TransactionDTO],
        startingAt startDate: String? = nil,
        endingBefore endDate: String? = nil
    ) -> [TransactionDTO] {
        transactions.filter { transaction in
            if let startDate, transaction.date < startDate { return false }
            if let endDate, transaction.date >= endDate { return false }
            return !transaction.isIncome
                && transaction.category != .transfer
                && transaction.category != .transferOut
        }
    }
}
