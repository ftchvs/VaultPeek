import Foundation

public enum RecurringSummary {
    public static func estimatedMonthlyTotal(
        from recurringTransactions: [RecurringTransaction]
    ) -> Double {
        recurringTransactions.reduce(0) {
            $0 + $1.averageAmount * $1.frequency.monthlyMultiplier
        }
    }
}
