import Foundation

/// Account-detail insight block derived from a raw transaction feed: current-window
/// spend/income totals with previous-window comparison, the top spending categories,
/// and a short "needs review" list (pending and unusually large transactions).
///
/// All computation is pure and deterministic. The reference date comes from `now` when
/// provided, otherwise from the latest parseable transaction date, so fixtures and tests
/// never depend on the wall clock. Windowing follows `AccountActivitySummary.recent`:
/// the current window spans `[startOfDay(reference - (windowDays - 1)), reference]` and
/// the previous window covers the `windowDays` immediately before it.
public struct AccountDetailInsights: Sendable, Equatable {
    /// One spending category's contribution to the current window.
    public struct CategorySlice: Sendable, Equatable, Identifiable {
        public let category: SpendingCategory
        public let total: Double
        /// Fraction (0...1) of the full current-window spend total — computed against
        /// all window spend, not just the capped top slices. 0 when window spend is 0.
        public let share: Double
        public let transactionCount: Int

        public var id: String {
            category.rawValue
        }

        public init(category: SpendingCategory, total: Double, share: Double, transactionCount: Int) {
            self.category = category
            self.total = total
            self.share = share
            self.transactionCount = transactionCount
        }
    }

    /// A current-window transaction surfaced for user attention.
    public struct ReviewItem: Sendable, Equatable, Identifiable {
        public enum Reason: Sendable, Equatable {
            case pending
            case largeAmount
        }

        public let transaction: TransactionDTO
        public let reason: Reason

        public var id: String {
            transaction.id
        }

        public init(transaction: TransactionDTO, reason: Reason) {
            self.transaction = transaction
            self.reason = reason
        }
    }

    public let windowDays: Int
    /// Current-window expense total (absolute amounts, transfers excluded).
    public let spendTotal: Double
    /// Current-window income total (absolute amounts, transfers excluded).
    public let incomeTotal: Double
    /// Expense total for the `windowDays` immediately before the current window.
    public let previousSpendTotal: Double
    /// Income total for the `windowDays` immediately before the current window.
    public let previousIncomeTotal: Double
    public let topCategories: [CategorySlice]
    public let reviewItems: [ReviewItem]

    public var spendDelta: Double {
        spendTotal - previousSpendTotal
    }

    public var incomeDelta: Double {
        incomeTotal - previousIncomeTotal
    }

    public init(
        windowDays: Int,
        spendTotal: Double,
        incomeTotal: Double,
        previousSpendTotal: Double,
        previousIncomeTotal: Double,
        topCategories: [CategorySlice],
        reviewItems: [ReviewItem]
    ) {
        self.windowDays = windowDays
        self.spendTotal = spendTotal
        self.incomeTotal = incomeTotal
        self.previousSpendTotal = previousSpendTotal
        self.previousIncomeTotal = previousIncomeTotal
        self.topCategories = topCategories
        self.reviewItems = reviewItems
    }

    /// Computes insights for the account detail surface.
    ///
    /// - Transfers (`.transfer` / `.transferOut`) never count toward spend/income totals
    ///   or `topCategories`.
    /// - Income (`isIncome`, amount < 0 in Plaid convention) is excluded from
    ///   `topCategories` — category slices describe spending only.
    /// - Pending transactions count toward totals and categories (they are real spending
    ///   signals) and lead `reviewItems`, followed by posted, non-transfer expenses at or above
    ///   `largeAmountThreshold`. The default threshold mirrors
    ///   `NotificationTriggers.largeTransactionThreshold`'s default of 500.
    public static func compute(
        transactions: [TransactionDTO],
        windowDays: Int = 30,
        largeAmountThreshold: Double = 500,
        maxCategories: Int = 5,
        maxReviewItems: Int = 6,
        now: Date? = nil,
        calendar: Calendar = .current
    ) -> AccountDetailInsights {
        let referenceDate = now ?? latestTransactionDate(in: transactions) ?? Date()
        let currentStart = calendar.startOfDay(
            for: calendar.date(byAdding: .day, value: -(windowDays - 1), to: referenceDate) ?? referenceDate
        )
        let previousStart = calendar.startOfDay(
            for: calendar.date(byAdding: .day, value: -windowDays, to: currentStart) ?? currentStart
        )

        var currentWindow: [TransactionDTO] = []
        var previousWindow: [TransactionDTO] = []
        for transaction in transactions {
            guard let date = Formatters.parseTransactionDate(transaction.date) else { continue }
            if date >= currentStart, date <= referenceDate {
                currentWindow.append(transaction)
            } else if date >= previousStart, date < currentStart {
                previousWindow.append(transaction)
            }
        }

        let currentTotals = totals(of: currentWindow)
        let previousTotals = totals(of: previousWindow)

        return AccountDetailInsights(
            windowDays: windowDays,
            spendTotal: currentTotals.spend,
            incomeTotal: currentTotals.income,
            previousSpendTotal: previousTotals.spend,
            previousIncomeTotal: previousTotals.income,
            topCategories: topCategories(
                in: currentWindow,
                spendTotal: currentTotals.spend,
                maxCategories: maxCategories
            ),
            reviewItems: reviewItems(
                in: currentWindow,
                largeAmountThreshold: largeAmountThreshold,
                maxReviewItems: maxReviewItems
            )
        )
    }

    // MARK: - Private helpers

    private static func totals(of transactions: [TransactionDTO]) -> (spend: Double, income: Double) {
        var spend = 0.0
        var income = 0.0
        for transaction in transactions where !transaction.isTransfer {
            if transaction.isIncome {
                income += transaction.displayAmount
            } else {
                spend += transaction.displayAmount
            }
        }
        return (spend, income)
    }

    private static func topCategories(
        in transactions: [TransactionDTO],
        spendTotal: Double,
        maxCategories: Int
    ) -> [CategorySlice] {
        var buckets: [SpendingCategory: (total: Double, count: Int)] = [:]
        for transaction in transactions where !transaction.isTransfer && !transaction.isIncome {
            let category = transaction.category ?? .other
            let bucket = buckets[category] ?? (0, 0)
            buckets[category] = (bucket.total + transaction.displayAmount, bucket.count + 1)
        }

        let slices = buckets
            .map { category, bucket in
                CategorySlice(
                    category: category,
                    total: bucket.total,
                    share: spendTotal > 0 ? bucket.total / spendTotal : 0,
                    transactionCount: bucket.count
                )
            }
            .sorted { lhs, rhs in
                if lhs.total != rhs.total {
                    return lhs.total > rhs.total
                }
                return lhs.category.displayName < rhs.category.displayName
            }

        return Array(slices.prefix(max(0, maxCategories)))
    }

    private static func reviewItems(
        in transactions: [TransactionDTO],
        largeAmountThreshold: Double,
        maxReviewItems: Int
    ) -> [ReviewItem] {
        let pending = transactions
            .filter(\.pending)
            .sorted(by: isPreferredForReview)
            .map { ReviewItem(transaction: $0, reason: .pending) }

        let pendingIds = Set(pending.map(\.id))
        let large = transactions
            .filter { transaction in
                !transaction.pending &&
                    !transaction.isIncome &&
                    !transaction.isTransfer &&
                    transaction.displayAmount >= largeAmountThreshold &&
                    !pendingIds.contains(transaction.id)
            }
            .sorted(by: isPreferredForReview)
            .map { ReviewItem(transaction: $0, reason: .largeAmount) }

        return Array((pending + large).prefix(max(0, maxReviewItems)))
    }

    /// Stable review ordering: date descending, then displayAmount descending, then id ascending.
    private static func isPreferredForReview(_ lhs: TransactionDTO, _ rhs: TransactionDTO) -> Bool {
        let lhsDate = Formatters.parseTransactionDate(lhs.date) ?? .distantPast
        let rhsDate = Formatters.parseTransactionDate(rhs.date) ?? .distantPast
        if lhsDate != rhsDate {
            return lhsDate > rhsDate
        }
        if lhs.displayAmount != rhs.displayAmount {
            return lhs.displayAmount > rhs.displayAmount
        }
        return lhs.id < rhs.id
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
