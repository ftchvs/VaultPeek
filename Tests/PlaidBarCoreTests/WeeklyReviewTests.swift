import Testing
@testable import PlaidBarCore

@Suite("Weekly review")
struct WeeklyReviewTests {
    private let calendar = Calendar(identifier: .gregorian)
    private let now = Date(timeIntervalSince1970: 1_781_510_400) // 2026-06-14

    @Test("Review waits for transaction review state instead of raw transactions")
    func waitsForTransactionReviewState() {
        let presentation = WeeklyReviewBuilder.evaluate(
            state: .empty,
            transactionState: nil,
            transactions: [transaction(id: "realistic-raw-id", date: "2026-06-14")],
            recurringTransactions: [],
            safeToSpend: safeToSpend(amount: 500),
            asOf: now,
            calendar: calendar
        )

        #expect(presentation.outcome == .waitingForTransactionReview)
        #expect(presentation.isBlockedByTransactionReviewDependency)
        #expect(presentation.items.isEmpty)
        #expect(presentation.menuBarPrompt == nil)
    }

    @Test("Derived items summarize review inbox, budgets, recurring, safe-to-spend, and connection health")
    func derivesWeeklyChecklistItems() {
        let presentation = WeeklyReviewBuilder.evaluate(
            state: WeeklyReviewState(lastCompletedAt: daysAgo(8)),
            transactionState: WeeklyReviewTransactionState(
                trustedTransactionIds: ["tx-trusted"],
                unreviewedTransactionIds: ["tx-unreviewed"]
            ),
            transactions: [transaction(id: "tx-trusted", date: "2026-06-13")],
            recurringTransactions: [
                RecurringTransaction(
                    merchantName: "Synthetic Streaming",
                    frequency: .monthly,
                    averageAmount: 20,
                    latestAmount: 24,
                    trailingAverageAmount: 20,
                    lastDate: "2026-06-10",
                    nextExpectedDate: "2026-06-17",
                    category: .entertainment,
                    transactionCount: 4,
                    confidence: 0.9
                ),
            ],
            safeToSpend: safeToSpend(amount: -25),
            categoryBudgets: CategoryBudgetPresentation(
                items: [
                    CategoryBudgetPresentation.Item(
                        category: .foodAndDrink,
                        monthlyLimit: 100,
                        spent: 125,
                        isSuggested: false
                    ),
                ],
                totalLimit: 100,
                totalSpent: 125,
                overBudgetCount: 1,
                nearingCount: 0
            ),
            itemStatuses: [ItemStatus(id: "item-synthetic", status: .error)],
            isSyncStale: true,
            asOf: now,
            calendar: calendar
        )

        #expect(presentation.outcome == .payAttention)
        #expect(presentation.isDue)
        #expect(presentation.reviewedTransactionCount == 1)
        #expect(presentation.items.map(\.kind) == [
            .transactionReview,
            .categoryDrift,
            .upcomingBills,
            .safeToSpendChange,
            .subscriptionChange,
            .connectionHealth,
        ])
        #expect(presentation.menuBarPrompt == "6 items to review")
    }

    @Test("Completing all derived items yields positive empty state")
    func completedItemsYieldLooksGood() {
        let state = WeeklyReviewState(
            lastCompletedAt: daysAgo(8),
            completedItemIds: ["weekly-review.transactions"]
        )

        let presentation = WeeklyReviewBuilder.evaluate(
            state: state,
            transactionState: WeeklyReviewTransactionState(
                trustedTransactionIds: [],
                unreviewedTransactionIds: ["tx-unreviewed"]
            ),
            transactions: [],
            recurringTransactions: [],
            safeToSpend: safeToSpend(amount: 500),
            asOf: now,
            calendar: calendar
        )

        #expect(presentation.outcome == .looksGood)
        #expect(presentation.completedCount == 1)
        #expect(presentation.totalCount == 1)
        #expect(presentation.remainingCount == 0)
        #expect(presentation.menuBarPrompt == "Weekly review due")
    }

    @Test("Notification copy is privacy preserving by default")
    func notificationCopyIsPrivate() {
        let presentation = WeeklyReviewBuilder.evaluate(
            state: .empty,
            transactionState: WeeklyReviewTransactionState(
                trustedTransactionIds: [],
                unreviewedTransactionIds: ["tx_private_123"]
            ),
            transactions: [
                TransactionDTO(
                    id: "tx_private_123",
                    accountId: "acct_private_456",
                    amount: 9_999.99,
                    date: "2026-06-14",
                    name: "Raw Private Merchant",
                    merchantName: "Private Merchant"
                ),
            ],
            recurringTransactions: [],
            safeToSpend: safeToSpend(amount: 500),
            asOf: now,
            calendar: calendar
        )

        let copy = [presentation.notificationTitle, presentation.notificationBody, presentation.menuBarPrompt ?? ""]
            .joined(separator: " ")

        for privateText in [
            "tx_private_123",
            "acct_private_456",
            "9999.99",
            "Raw Private Merchant",
            "Private Merchant",
        ] {
            #expect(copy.contains(privateText) == false)
        }
        #expect(copy.contains("$") == false)
    }

    private func transaction(id: String, date: String) -> TransactionDTO {
        TransactionDTO(
            id: id,
            accountId: "acct-\(id)",
            amount: 10,
            date: date,
            name: "Synthetic"
        )
    }

    private func safeToSpend(amount: Double) -> SafeToSpendResult {
        SafeToSpendResult(
            amount: amount,
            components: [
                SafeToSpendComponent(kind: .startingCash, label: "Starting cash", amount: amount),
            ],
            confidence: .ok,
            horizonEnd: now
        )
    }

    private func daysAgo(_ days: Int) -> Date {
        calendar.date(byAdding: .day, value: -days, to: now) ?? now
    }
}
