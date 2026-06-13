import Foundation

public enum RecurringSummary {
    public static func estimatedMonthlyTotal(
        from recurringTransactions: [RecurringTransaction],
        asOf date: Date? = nil,
        calendar: Calendar = .current
    ) -> Double {
        recurringTransactions
            .filter { recurring in
                guard let date else { return true }
                return !recurring.isStale(asOf: date, calendar: calendar)
            }
            .reduce(0) {
            $0 + $1.averageAmount * $1.frequency.monthlyMultiplier
        }
    }
}
