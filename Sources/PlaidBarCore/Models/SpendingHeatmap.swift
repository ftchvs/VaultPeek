import Foundation

public enum SpendingHeatmapMode: String, Codable, CaseIterable, Sendable {
    case spending
    case netCashflow
}

public struct SpendingHeatmapDay: Identifiable, Sendable, Hashable {
    public let date: String
    public let value: Double
    public let transactionCount: Int

    public var id: String { date }

    public init(date: String, value: Double, transactionCount: Int) {
        self.date = date
        self.value = value
        self.transactionCount = transactionCount
    }
}

public enum SpendingHeatmap {
    public static func days(
        from transactions: [TransactionDTO],
        startDate: Date,
        endDate: Date,
        mode: SpendingHeatmapMode,
        calendar: Calendar = .current
    ) -> [SpendingHeatmapDay] {
        let start = calendar.startOfDay(for: startDate)
        let end = calendar.startOfDay(for: endDate)
        guard start <= end else { return [] }

        let relevant = transactions.compactMap { transaction -> (String, Double)? in
            guard let date = Formatters.parseTransactionDate(transaction.date) else { return nil }
            let day = calendar.startOfDay(for: date)
            guard day >= start && day <= end else { return nil }
            guard !isTransfer(transaction) else { return nil }

            switch mode {
            case .spending:
                guard !transaction.isIncome else { return nil }
                return (transaction.date, transaction.displayAmount)
            case .netCashflow:
                return (transaction.date, transaction.amount)
            }
        }

        let grouped = Dictionary(grouping: relevant) { $0.0 }
        let dayCount = calendar.dateComponents([.day], from: start, to: end).day ?? 0

        return (0...dayCount).compactMap { offset in
            guard let day = calendar.date(byAdding: .day, value: offset, to: start) else { return nil }
            let dateString = Formatters.transactionDateString(day)
            let entries = grouped[dateString] ?? []
            return SpendingHeatmapDay(
                date: dateString,
                value: entries.reduce(0) { $0 + $1.1 },
                transactionCount: entries.count
            )
        }
    }

    private static func isTransfer(_ transaction: TransactionDTO) -> Bool {
        transaction.category == .transfer || transaction.category == .transferOut
    }
}
