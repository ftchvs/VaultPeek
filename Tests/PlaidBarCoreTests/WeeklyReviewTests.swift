import Testing
@testable import PlaidBarCore

@Suite("Weekly review")
struct WeeklyReviewTests {
    private let calendar = Calendar(identifier: .gregorian)
    private let now = Date(timeIntervalSince1970: 1_781_510_400) // 2026-06-14

    @Test("Review degrades neutrally while transaction data is not ready")
    func waitsNeutrallyForTransactionData() {
        let presentation = WeeklyReviewBuilder.evaluate(
            state: .empty,
            transactionState: nil,
            transactions: [transaction(id: "realistic-raw-id", date: "2026-06-14")],
            recurringTransactions: [],
            safeToSpend: safeToSpend(amount: 500),
            asOf: now,
            calendar: calendar
        )

        #expect(presentation.outcome == .notReady)
        #expect(presentation.isBlockedByTransactionReviewDependency == false)
        #expect(presentation.items.isEmpty)
        #expect(presentation.menuBarPrompt == nil)
        #expect(presentation.notificationBody == "Weekly review will appear once transaction data is ready.")
    }

    @Test("Transaction review item still gives a clear user action")
    func transactionReviewItemGivesUserAction() {
        let presentation = WeeklyReviewBuilder.evaluate(
            state: .empty,
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

        #expect(presentation.outcome == .reviewItems)
        #expect(presentation.items.count == 1)
        #expect(presentation.items.first?.kind == .transactionReview)
        #expect(presentation.items.first?.title == "1 transaction needs review")
        #expect(presentation.items.first?.detail == "Approve or categorize the latest inbox items before closing the week.")
        #expect(presentation.items.first?.action == .openReviewInbox)
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

    @Test("Transaction review metadata derives trusted and unreviewed weekly state")
    func transactionReviewMetadataDerivesWeeklyTransactionState() {
        let state = WeeklyReviewTransactionState.derived(
            from: [
                transaction(id: "reviewed", date: "2026-06-14"),
                transaction(id: "ignored", date: "2026-06-14"),
                transaction(id: "needs-review", date: "2026-06-14"),
            ],
            metadata: [
                TransactionReviewMetadata(id: "reviewed", status: .reviewed),
                TransactionReviewMetadata(id: "ignored", status: .ignored),
                TransactionReviewMetadata(id: "needs-review", status: .needsReview),
                TransactionReviewMetadata(id: "stale-reviewed", status: .reviewed),
            ]
        )

        #expect(state.trustedTransactionIds == ["reviewed", "ignored"])
        #expect(state.unreviewedTransactionIds == ["needs-review"])
    }

    @Test("Transactions without metadata are not treated as trusted")
    func missingTransactionReviewMetadataRequiresReview() {
        let state = WeeklyReviewTransactionState.derived(
            from: [transaction(id: "missing-metadata", date: "2026-06-14")],
            metadata: []
        )

        #expect(state.trustedTransactionIds.isEmpty)
        #expect(state.unreviewedTransactionIds == ["missing-metadata"])
    }

    /// Regression for the Weekly Review under-count: a transaction whose metadata
    /// is `.needsReview` but which trips no Review Inbox heuristic must still be
    /// counted as unreviewed. The old production path derived the count from the
    /// inbox snapshot, which emits no item for such a transaction — silently
    /// counting a genuinely-unreviewed transaction as trusted. `derived(...)`
    /// (the contract production now uses) classifies strictly by metadata status.
    @Test("Needs-review transaction tripping no inbox heuristic is still unreviewed")
    func needsReviewWithoutHeuristicIsCountedUnreviewed() {
        // Three identical, well-categorized charges for one established merchant:
        // categorized (no `.uncategorized`), merchant count > 1 (no `.newMerchant`),
        // uniform amount (no `.unusualAmount`), not income/transfer/pending. This
        // trips none of the inbox heuristics.
        let transactions = (0..<3).map { index in
            TransactionDTO(
                id: "grocery-\(index)",
                accountId: "acct-grocery",
                amount: 42.50,
                date: "2026-06-1\(index)",
                name: "WHOLE FOODS",
                merchantName: "Whole Foods",
                category: .foodAndDrink
            )
        }
        // Two settled as reviewed; the third left needing review.
        let metadata = [
            TransactionReviewMetadata(id: "grocery-0", status: .reviewed),
            TransactionReviewMetadata(id: "grocery-1", status: .reviewed),
            TransactionReviewMetadata(id: "grocery-2", status: .needsReview),
        ]

        // The inbox emits no item for the needs-review transaction — this is the
        // exact gap that made the old production count miss it.
        let inbox = TransactionReviewInbox.evaluate(
            transactions: transactions,
            metadata: metadata,
            rules: [],
            recurring: [],
            now: now
        )
        #expect(inbox.items.contains { $0.id == "grocery-2" } == false)

        // The tested contract still counts it as unreviewed.
        let state = WeeklyReviewTransactionState.derived(from: transactions, metadata: metadata)
        #expect(state.unreviewedTransactionIds == ["grocery-2"])
        #expect(state.trustedTransactionIds == ["grocery-0", "grocery-1"])
    }

    @Test("Reviewed and ignored transaction metadata unblock weekly review")
    func reviewedAndIgnoredTransactionMetadataUnblocksWeeklyReview() {
        let transactions = [
            transaction(id: "reviewed", date: "2026-06-14"),
            transaction(id: "ignored", date: "2026-06-14"),
        ]
        let transactionState = WeeklyReviewTransactionState.derived(
            from: transactions,
            metadata: [
                TransactionReviewMetadata(id: "reviewed", status: .reviewed),
                TransactionReviewMetadata(id: "ignored", status: .ignored),
            ]
        )

        let presentation = WeeklyReviewBuilder.evaluate(
            state: .empty,
            transactionState: transactionState,
            transactions: transactions,
            recurringTransactions: [],
            safeToSpend: safeToSpend(amount: 500),
            asOf: now,
            calendar: calendar
        )

        #expect(!presentation.isBlockedByTransactionReviewDependency)
        #expect(!presentation.items.contains { $0.kind == .transactionReview })
        #expect(presentation.reviewedTransactionCount == 2)
    }

    @Test("Needs-review transaction metadata creates actionable weekly review item")
    func needsReviewTransactionMetadataCreatesActionableWeeklyReviewItem() {
        let transactions = [transaction(id: "needs-review", date: "2026-06-14")]
        let transactionState = WeeklyReviewTransactionState.derived(
            from: transactions,
            metadata: [TransactionReviewMetadata(id: "needs-review", status: .needsReview)]
        )

        let presentation = WeeklyReviewBuilder.evaluate(
            state: .empty,
            transactionState: transactionState,
            transactions: transactions,
            recurringTransactions: [],
            safeToSpend: safeToSpend(amount: 500),
            asOf: now,
            calendar: calendar
        )

        #expect(!presentation.isBlockedByTransactionReviewDependency)
        #expect(presentation.items.map(\.kind) == [.transactionReview])
        #expect(presentation.items.first?.action == .openReviewInbox)
    }

    @Test("Completing all derived items in the current cycle yields positive empty state")
    func completedItemsYieldLooksGood() {
        // Completed two days ago: still inside the current weekly cycle (not yet
        // due again), so the completion counts toward this cycle.
        let state = WeeklyReviewState(
            lastCompletedAt: daysAgo(2),
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
    }

    @Test("Completions from a prior cycle do not suppress a new cycle's items")
    func priorCycleCompletionsDoNotCarryOver() {
        // Completed 8 days ago: the weekly review is due again, so last cycle's
        // completion must not mark this cycle's fresh transaction item as done.
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

        #expect(presentation.outcome == .reviewItems)
        #expect(presentation.completedCount == 0)
        #expect(presentation.totalCount == 1)
        #expect(presentation.remainingCount == 1)
    }

    @Test("Category drift hint does not promise navigation that does not happen")
    func categoryDriftHintDoesNotPromiseNavigation() {
        // The category-drift item's `.inspectCategory` action has no budget
        // surface to open (AND-466). Its accessibility hint must therefore not
        // claim it opens one — that read as a live dead-end.
        let presentation = WeeklyReviewBuilder.evaluate(
            state: .empty,
            transactionState: WeeklyReviewTransactionState(
                trustedTransactionIds: [],
                unreviewedTransactionIds: []
            ),
            transactions: [],
            recurringTransactions: [],
            safeToSpend: safeToSpend(amount: 500),
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
            asOf: now,
            calendar: calendar
        )

        let driftItem = presentation.items.first { $0.kind == .categoryDrift }
        #expect(driftItem?.action == .inspectCategory)
        #expect(driftItem?.accessibilityHint == "Flags category budget pressure for this month.")
        #expect(driftItem?.accessibilityHint.contains("Opens") == false)
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
