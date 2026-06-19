import Foundation
import Testing
@testable import PlaidBarCore

/// Tests for the AND-536 pure rollup builder. The builder must:
/// - roll override-aware leaf spend into 2-level group totals,
/// - keep leaf + group totals summing to the overall total,
/// - move spend when a user override / rule recategorizes a row,
/// - skip excluded / transfer / income rows,
/// - band each leaf and group against its budget (under/nearing/over),
/// - never emit a false "over" on an empty / first-run dataset,
/// - and be deterministic for a fixed `asOf` month boundary (no `Date()`).
@Suite("Category dashboard builder (AND-536)")
struct CategoryDashboardBuilderTests {
    // June 13, 2026 — the current month is June; May/April/March are complete.
    private let now = Formatters.parseTransactionDate("2026-06-13")!
    private let calendar = Calendar(identifier: .gregorian)

    private func tx(
        _ amount: Double,
        _ date: String,
        _ category: SpendingCategory?,
        id: String? = nil,
        name: String = "Merchant",
        pending: Bool = false,
        pendingTransactionId: String? = nil,
        lowConfidence: Bool = false
    ) -> TransactionDTO {
        TransactionDTO(
            id: id ?? "\(name)-\(date)-\(amount)",
            accountId: "acct",
            amount: amount,
            date: date,
            name: name,
            merchantName: name,
            category: category,
            pending: pending,
            pendingTransactionId: pendingTransactionId,
            isLowConfidenceCategory: lowConfidence
        )
    }

    // MARK: - Rollup correctness

    @Test("Leaf totals roll up into their group and sum to the overall total")
    func leafAndGroupTotalsSumToOverall() {
        let transactions = [
            tx(100, "2026-06-02", .foodAndDrink),   // Food & Dining group
            tx(40, "2026-06-05", .foodAndDrink),    // Food & Dining group
            tx(60, "2026-06-07", .shopping),        // Shopping group
            tx(30, "2026-06-09", .transportation),  // Transportation group
        ]
        let result = CategoryDashboardBuilder.build(
            transactions: transactions,
            budgets: [:],
            asOf: now,
            calendar: calendar
        )

        // Overall total = sum of every leaf.
        #expect(result.totalSpent == 230)

        // Each leaf lands in the right group, and group spend = sum of its leaves.
        let food = result.group(.foodAndDining)
        #expect(food?.spent == 140)
        #expect(food?.leaves.first(where: { $0.category == .foodAndDrink })?.spent == 140)

        let shopping = result.group(.shopping)
        #expect(shopping?.spent == 60)

        let transport = result.group(.transportation)
        #expect(transport?.spent == 30)

        // The sum of group spend equals the overall total (the rollup invariant).
        let groupSum = result.groups.reduce(0) { $0 + $1.spent }
        #expect(groupSum == result.totalSpent)

        // The sum of every leaf across all groups also equals the overall total.
        let leafSum = result.groups.flatMap(\.leaves).reduce(0) { $0 + $1.spent }
        #expect(leafSum == result.totalSpent)
    }

    @Test("Groups are emitted in canonical display order")
    func groupsOrderedByDisplayOrder() {
        let transactions = [
            tx(50, "2026-06-02", .shopping),        // Shopping (index 4)
            tx(50, "2026-06-03", .foodAndDrink),    // Food & Dining (index 2)
            tx(50, "2026-06-04", .entertainment),   // Entertainment (index 7)
        ]
        let result = CategoryDashboardBuilder.build(
            transactions: transactions,
            budgets: [:],
            asOf: now,
            calendar: calendar
        )
        let order = result.groups.map(\.group)
        let expected = CategoryGroup.displayOrder.filter { order.contains($0) }
        #expect(order == expected)
    }

    // MARK: - Override awareness

    @Test("A user category override moves spend across leaves and groups")
    func userOverrideMovesSpend() {
        // Plaid says this $100 charge is Shopping; the user recategorizes it as
        // Food & Drink. Override-aware aggregation must move the spend.
        let transaction = tx(100, "2026-06-05", .shopping, id: "tx-override")
        let metadata = [
            TransactionReviewMetadata(id: "tx-override", userCategory: .foodAndDrink),
        ]

        let raw = CategoryDashboardBuilder.build(
            transactions: [transaction],
            budgets: [:],
            asOf: now,
            calendar: calendar
        )
        #expect(raw.group(.shopping)?.spent == 100)
        #expect(raw.group(.foodAndDining) == nil)

        let resolved = CategoryDashboardBuilder.build(
            transactions: [transaction],
            budgets: [:],
            asOf: now,
            calendar: calendar,
            metadata: metadata,
            rules: []
        )
        // Spend moved out of Shopping and into Food & Dining.
        #expect(resolved.group(.shopping) == nil)
        #expect(resolved.group(.foodAndDining)?.spent == 100)
        #expect(resolved.totalSpent == 100)
    }

    @Test("A rule recategorization moves spend in the rollup")
    func ruleOverrideMovesSpend() {
        let transaction = tx(80, "2026-06-06", .shopping, name: "SuperMart")
        let rule = TransactionRule(matchMerchantContains: "SuperMart", category: .foodAndDrink)

        let resolved = CategoryDashboardBuilder.build(
            transactions: [transaction],
            budgets: [:],
            asOf: now,
            calendar: calendar,
            metadata: [],
            rules: [rule]
        )
        #expect(resolved.group(.shopping) == nil)
        #expect(resolved.group(.foodAndDining)?.spent == 80)
    }

    @Test("Pending-phase override carries into the posted charge under a new id")
    func pendingOverrideCarriesForward() {
        // A charge reviewed while pending (id "pending-1") re-posts under a new
        // id ("posted-1") linking back via pendingTransactionId. The category
        // decision saved under the pending id must still move spend in the rollup.
        let posted = tx(
            45, "2026-06-08", .shopping,
            id: "posted-1", pendingTransactionId: "pending-1"
        )
        let metadata = [
            TransactionReviewMetadata(id: "pending-1", userCategory: .foodAndDrink),
        ]
        let result = CategoryDashboardBuilder.build(
            transactions: [posted],
            budgets: [:],
            asOf: now,
            calendar: calendar,
            metadata: metadata,
            rules: []
        )
        #expect(result.group(.shopping) == nil)
        #expect(result.group(.foodAndDining)?.spent == 45)
    }

    // MARK: - Excluded / transfer / income rows

    @Test("Transfers and income never count toward any group")
    func transfersAndIncomeSkipped() {
        let transactions = [
            tx(100, "2026-06-05", .foodAndDrink),
            tx(-2000, "2026-06-01", .income),     // paycheck — money in, income
            tx(500, "2026-06-02", .transferOut),  // own-account move out
            tx(-500, "2026-06-02", .transfer),    // own-account move in
        ]
        let result = CategoryDashboardBuilder.build(
            transactions: transactions,
            budgets: [:],
            asOf: now,
            calendar: calendar
        )
        #expect(result.totalSpent == 100)
        #expect(result.group(.income) == nil)
        #expect(result.group(.transfers) == nil)
        #expect(result.group(.foodAndDining)?.spent == 100)
    }

    @Test("A user-excluded row is dropped from the rollup")
    func userExcludedRowSkipped() {
        let transaction = tx(75, "2026-06-04", .shopping, id: "tx-excluded")
        let metadata = [
            TransactionReviewMetadata(id: "tx-excluded", excludedFromBudgets: true),
        ]
        let result = CategoryDashboardBuilder.build(
            transactions: [transaction],
            budgets: [:],
            asOf: now,
            calendar: calendar,
            metadata: metadata,
            rules: []
        )
        #expect(result.isEmpty)
        #expect(result.totalSpent == 0)
    }

    @Test("A transfer override excludes a row that Plaid mislabeled as spend")
    func transferOverrideSkipped() {
        // Plaid called this card payment Shopping; the user marks it a transfer.
        let transaction = tx(300, "2026-06-04", .shopping, id: "tx-transfer")
        let metadata = [
            TransactionReviewMetadata(id: "tx-transfer", isTransferOverride: true),
        ]
        let result = CategoryDashboardBuilder.build(
            transactions: [transaction],
            budgets: [:],
            asOf: now,
            calendar: calendar,
            metadata: metadata,
            rules: []
        )
        #expect(result.totalSpent == 0)
        #expect(result.group(.shopping) == nil)
    }

    // MARK: - Budget-status banding

    @Test("Leaf and group budget statuses band under / nearing / over")
    func budgetStatusBands() {
        let transactions = [
            tx(50, "2026-06-02", .foodAndDrink),    // under its 200 limit
            tx(170, "2026-06-03", .shopping),       // 85% of 200 → nearing
            tx(260, "2026-06-04", .transportation), // over its 200 limit
        ]
        let budgets: [SpendingCategory: Double] = [
            .foodAndDrink: 200,
            .shopping: 200,
            .transportation: 200,
        ]
        let result = CategoryDashboardBuilder.build(
            transactions: transactions,
            budgets: budgets,
            asOf: now,
            calendar: calendar
        )

        #expect(result.leaf(.foodAndDrink)?.status == .under)
        #expect(result.leaf(.shopping)?.status == .nearing)
        #expect(result.leaf(.transportation)?.status == .over)

        // The over/nearing aggregate counts reflect the leaves.
        #expect(result.overBudgetCount == 1)
        #expect(result.nearingCount == 1)

        // Group rollups carry the same banding for their single-leaf groups.
        #expect(result.group(.shopping)?.status == .nearing)
        #expect(result.group(.transportation)?.status == .over)
    }

    @Test("A group can be over even when each leaf is under, via summed limits")
    func groupOverWhileLeavesUnder() {
        // Two leaves in the Health & Wellness group, each under its own limit, but
        // the group's summed spend exceeds the group's summed limit.
        let transactions = [
            tx(90, "2026-06-02", .healthAndFitness), // 90 / 100 → nearing leaf
            tx(95, "2026-06-03", .personalCare),     // 95 / 100 → nearing leaf
        ]
        let budgets: [SpendingCategory: Double] = [
            .healthAndFitness: 100,
            .personalCare: 100,
        ]
        let result = CategoryDashboardBuilder.build(
            transactions: transactions,
            budgets: budgets,
            asOf: now,
            calendar: calendar
        )
        let group = result.group(.healthAndWellness)
        // Group spend 185 vs summed limit 200 → nearing at group level even though
        // neither leaf is over. (Independent group status — spec §7 edge case.)
        #expect(group?.spent == 185)
        #expect(group?.monthlyLimit == 200)
        #expect(group?.status == .nearing)
        // Each leaf is independently nearing, not over.
        #expect(result.leaf(.healthAndFitness)?.status == .nearing)
        #expect(result.leaf(.personalCare)?.status == .nearing)
    }

    @Test("A category with no budget has nil status but still contributes spend")
    func unbudgetedCategoryHasNilStatus() {
        let transactions = [
            tx(120, "2026-06-02", .shopping),    // budgeted
            tx(60, "2026-06-03", .entertainment), // not budgeted
        ]
        let result = CategoryDashboardBuilder.build(
            transactions: transactions,
            budgets: [.shopping: 300],
            asOf: now,
            calendar: calendar
        )
        #expect(result.leaf(.shopping)?.status == .under)
        #expect(result.leaf(.entertainment)?.status == nil)
        #expect(result.leaf(.entertainment)?.monthlyLimit == nil)
        // Unbudgeted spend still rolls into the overall total.
        #expect(result.totalSpent == 180)
    }

    // MARK: - Empty / first-run

    @Test("Empty input yields an empty dashboard with no false over")
    func emptyInputNoFalseOver() {
        let result = CategoryDashboardBuilder.build(
            transactions: [],
            budgets: [:],
            asOf: now,
            calendar: calendar
        )
        #expect(result.isEmpty)
        #expect(result.totalSpent == 0)
        #expect(result.totalLimit == 0)
        #expect(result.overBudgetCount == 0)
        #expect(result.nearingCount == 0)
        #expect(result.groups.isEmpty)
    }

    @Test("Budgets with zero spend are under, never falsely over (first run)")
    func budgetsWithNoSpendAreUnder() {
        // First-run: the user set budgets but has no current-month spend yet.
        let result = CategoryDashboardBuilder.build(
            transactions: [],
            budgets: [.foodAndDrink: 400, .shopping: 200],
            asOf: now,
            calendar: calendar
        )
        #expect(result.overBudgetCount == 0)
        #expect(result.nearingCount == 0)
        #expect(result.totalLimit == 600)
        #expect(result.totalSpent == 0)
        // Budgeted-but-unspent categories surface as on-track, not over.
        #expect(result.leaf(.foodAndDrink)?.status == .under)
        #expect(result.leaf(.shopping)?.status == .under)
    }

    // MARK: - asOf determinism / month boundary

    @Test("Only the current month counts — prior and next month roll off")
    func monthBoundaryDeterminism() {
        let transactions = [
            tx(400, "2026-05-31", .foodAndDrink), // previous month — excluded
            tx(100, "2026-06-01", .foodAndDrink), // first day of current month — counts
            tx(50, "2026-06-30", .foodAndDrink),  // last day of current month — counts
            tx(75, "2026-07-01", .foodAndDrink),  // next month — excluded
        ]
        let result = CategoryDashboardBuilder.build(
            transactions: transactions,
            budgets: [:],
            asOf: now,
            calendar: calendar
        )
        #expect(result.group(.foodAndDining)?.spent == 150)
        #expect(result.totalSpent == 150)
    }

    @Test("Two asOf dates in the same month produce identical rollups")
    func sameMonthDeterministic() {
        let transactions = [
            tx(100, "2026-06-05", .foodAndDrink),
            tx(60, "2026-06-20", .shopping),
        ]
        let early = CategoryDashboardBuilder.build(
            transactions: transactions,
            budgets: [:],
            asOf: Formatters.parseTransactionDate("2026-06-01")!,
            calendar: calendar
        )
        let late = CategoryDashboardBuilder.build(
            transactions: transactions,
            budgets: [:],
            asOf: Formatters.parseTransactionDate("2026-06-28")!,
            calendar: calendar
        )
        #expect(early == late)
        #expect(early.totalSpent == 160)
    }

    @Test("Refunds net against spend within a leaf before rollup")
    func refundsNetWithinLeaf() {
        let transactions = [
            tx(120, "2026-06-03", .shopping),  // purchase
            tx(-20, "2026-06-08", .shopping),  // refund (same category)
        ]
        let result = CategoryDashboardBuilder.build(
            transactions: transactions,
            budgets: [:],
            asOf: now,
            calendar: calendar
        )
        #expect(result.leaf(.shopping)?.spent == 100)
        #expect(result.group(.shopping)?.spent == 100)
        #expect(result.totalSpent == 100)
    }

    // MARK: - Committed recurring ghost segment (AND-559)

    private func monthlyStream(
        _ merchant: String,
        amount: Double,
        category: SpendingCategory
    ) -> RecurringTransaction {
        RecurringTransaction(
            merchantName: merchant,
            frequency: .monthly,
            averageAmount: amount,
            lastDate: "2026-06-01",
            nextExpectedDate: "2026-07-01",
            category: category,
            transactionCount: 6,
            confidence: 0.9
        )
    }

    @Test("Recurring streams thread committed spend onto the matching leaf and its group")
    func committedThreadedToLeafAndGroup() {
        let transactions = [tx(200, "2026-06-03", .subscriptions)]
        let result = CategoryDashboardBuilder.build(
            transactions: transactions,
            budgets: [.subscriptions: 100],
            asOf: now,
            calendar: calendar,
            recurring: [monthlyStream("Netflix", amount: 30, category: .subscriptions)]
        )

        let leaf = result.leaf(.subscriptions)
        #expect(leaf?.committed == 30)
        // 30 committed against a 100 budget = 0.3 of the bar.
        #expect(leaf?.committedFraction == 0.3)

        // The group rollup sums its leaves' commitments.
        let group = result.group(SpendingCategory.subscriptions.group)
        #expect(group?.committed == 30)
    }

    @Test("Committed is capped at the full bar even when recurring exceeds the budget")
    func committedClampedToFullBar() {
        let result = CategoryDashboardBuilder.build(
            transactions: [tx(50, "2026-06-03", .subscriptions)],
            budgets: [.subscriptions: 20],
            asOf: now,
            calendar: calendar,
            recurring: [monthlyStream("Bundle", amount: 40, category: .subscriptions)]
        )
        let leaf = result.leaf(.subscriptions)
        #expect(leaf?.committed == 40)            // raw amount preserved
        #expect(leaf?.committedFraction == 1.0)   // fraction clamped to the bar
    }

    @Test("An unbudgeted leaf has no committed fraction even with a recurring stream")
    func committedFractionNilWhenUnbudgeted() {
        let result = CategoryDashboardBuilder.build(
            transactions: [tx(80, "2026-06-03", .subscriptions)],
            budgets: [:],
            asOf: now,
            calendar: calendar,
            recurring: [monthlyStream("Netflix", amount: 30, category: .subscriptions)]
        )
        let leaf = result.leaf(.subscriptions)
        #expect(leaf?.committed == 30)
        #expect(leaf?.committedFraction == nil)
    }

    @Test("No recurring input leaves committed nil (backward compatible)")
    func committedNilWithoutRecurring() {
        let result = CategoryDashboardBuilder.build(
            transactions: [tx(200, "2026-06-03", .subscriptions)],
            budgets: [.subscriptions: 100],
            asOf: now,
            calendar: calendar
        )
        #expect(result.leaf(.subscriptions)?.committed == nil)
        #expect(result.leaf(.subscriptions)?.committedFraction == nil)
    }

    @Test("A category with no recurring stream keeps a nil ghost segment")
    func committedNilForUnmappedCategory() {
        let result = CategoryDashboardBuilder.build(
            transactions: [tx(120, "2026-06-03", .foodAndDrink)],
            budgets: [.foodAndDrink: 300],
            asOf: now,
            calendar: calendar,
            recurring: [monthlyStream("Netflix", amount: 30, category: .subscriptions)]
        )
        #expect(result.leaf(.foodAndDrink)?.committed == nil)
        #expect(result.leaf(.foodAndDrink)?.committedFraction == nil)
    }

    @Test("A rule moves the committed ghost to the recategorized leaf in the dashboard")
    func committedFollowsRuleRecategorization() {
        let result = CategoryDashboardBuilder.build(
            transactions: [tx(200, "2026-06-03", .healthAndFitness, name: "Gym")],
            budgets: [.healthAndFitness: 100],
            asOf: now,
            calendar: calendar,
            rules: [TransactionRule(matchMerchantContains: "Gym", category: .healthAndFitness)],
            recurring: [RecurringTransaction(
                merchantName: "Gym", frequency: .monthly, averageAmount: 30,
                lastDate: "2026-06-01", nextExpectedDate: "2026-07-01",
                category: .subscriptions, transactionCount: 6, confidence: 0.9
            )]
        )
        // Ghost follows the rule onto healthAndFitness, not the raw subscriptions leaf.
        #expect(result.leaf(.healthAndFitness)?.committed == 30)
        #expect(result.leaf(.subscriptions) == nil)
    }

    @Test("Stale recurring streams are dropped from dashboard commitments")
    func committedDropsStaleStreams() {
        let result = CategoryDashboardBuilder.build(
            transactions: [tx(80, "2026-06-03", .subscriptions)],
            budgets: [.subscriptions: 100],
            asOf: now,
            calendar: calendar,
            recurring: [RecurringTransaction(
                merchantName: "Cancelled", frequency: .monthly, averageAmount: 25,
                lastDate: "2026-01-01", nextExpectedDate: "2026-02-01",
                category: .subscriptions, transactionCount: 6, confidence: 0.9
            )]
        )
        #expect(result.leaf(.subscriptions)?.committed == nil)
    }

    @Test("Group committed counts only budgeted leaves, excludes unbudgeted ones")
    func groupCommittedExcludesUnbudgetedLeaves() {
        // Hand-built rollup: a budgeted leaf (limit 300, committed 50) plus an
        // unbudgeted leaf carrying its own commitment (30). The group denominator is
        // only the budgeted limit (300), so the group's committed must be 50 — the
        // unbudgeted leaf's 30 is excluded so it can't overstate group pressure.
        let budgeted = CategoryDashboardPresentation.Leaf(
            category: .foodAndDrink, spent: 100, monthlyLimit: 300, committed: 50
        )
        let unbudgeted = CategoryDashboardPresentation.Leaf(
            category: .shopping, spent: 40, monthlyLimit: nil, committed: 30
        )
        let group = CategoryDashboardPresentation.GroupRollup(
            group: .foodAndDining, leaves: [budgeted, unbudgeted]
        )
        #expect(group.monthlyLimit == 300)
        #expect(group.committed == 50)
        #expect(group.committedFraction == 50.0 / 300.0)
    }
}
