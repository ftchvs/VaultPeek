import Foundation
@testable import PlaidBarCore
import Testing

/// End-to-end **demo continuity** for the review / budget / category-dashboard
/// surfaces (AND-544). Where `DemoReviewBudgetFixturesTests` (AND-543) locks the
/// *shape* of the demo providers, this suite drives the real fixtures through the
/// real Core engines — the override-aware `CategoryBudgetPlanner` and the
/// `CategoryDashboardBuilder` — and asserts the numbers a `--demo` user would see:
///
/// - a category override actually *moves* demo spend (recategorize / approve in
///   the inbox changes a downstream total),
/// - a confirmed transfer / excluded row drops out of spend math,
/// - the seeded budgets produce a real under / nearing / over status mix that
///   survives every month boundary (the dashboard, not just the budget cards),
/// - and the demo review metadata covers every documented review state
///   (`reviewed` / `ignored` / `userCategory` override / `excludedFromBudgets`).
///
/// Mirrors how `AppState.loadDemoData` seeds the surfaces and how
/// `AppState.categoryBudgetPresentation` scores them, so a regression in the
/// fixtures *or* the engines that would leave `--demo` showing empty or stale
/// numbers fails here rather than only on screen. Every id / amount referenced is
/// synthetic demo data.
@Suite("Demo review / budget continuity (AND-544)")
struct DemoReviewBudgetContinuityTests {
    /// Fixed midday reference inside a 31-day month so the relative-dated demo
    /// transactions (`today`/`yesterday`/...) land deterministically and the
    /// current-month window is unambiguous.
    private let referenceDate: Date = {
        var components = DateComponents()
        components.year = 2025
        components.month = 1
        components.day = 15
        components.hour = 12
        return Calendar.current.date(from: components)!
    }()

    private let calendar = Calendar.current

    private func demoBudgetMap() -> [SpendingCategory: Double] {
        Dictionary(
            DemoFixtures.demoBudgets().map { ($0.category, $0.monthlyLimit) },
            uniquingKeysWith: { first, _ in first }
        )
    }

    // MARK: - Dashboard builds over the real demo fixtures

    /// Demo mode must populate the goals surfaces, not just the Plaid-derived
    /// dashboard fixtures. The fixtures stay Core-local and synthetic, then
    /// `AppState.loadDemoData` loads them into the app-local `GoalsStore` without
    /// persisting over real user goals.
    @Test("Demo fixtures provide savings goals for dashboard and Goals workspace")
    func demoFixturesProvideGoals() {
        let goals = DemoFixtures.demoGoals(now: referenceDate, calendar: calendar)
        let preview = DashboardGoalsPreview.make(from: goals, asOf: referenceDate)

        #expect(goals.count >= 3, "demo goals should populate the full goals surface")
        #expect(!preview.isEmpty, "demo dashboard goals preview should not be empty")
        #expect(preview.goals.count == min(goals.count, DashboardGoalsPreview.defaultLimit))
        #expect(Set(goals.map(\.id)).count == goals.count, "demo goal ids must be stable and unique")
        #expect(goals.allSatisfy { $0.targetAmount > 0 && $0.contributedAmount > 0 })
    }

    /// The Category Dashboard card / window builds its rollup from the main demo
    /// transactions (where the seeded overrides live) plus the seeded budgets,
    /// metadata, and rules. It must be non-empty and internally consistent so the
    /// `--demo` dashboard is never a blank surface.
    @Test("Dashboard builder over the demo fixtures yields a non-empty, consistent rollup")
    func dashboardBuildsFromDemoFixtures() {
        let dashboard = CategoryDashboardBuilder.build(
            transactions: DemoFixtures.transactions(now: referenceDate, calendar: calendar),
            budgets: demoBudgetMap(),
            asOf: referenceDate,
            calendar: calendar,
            metadata: DemoFixtures.demoReviewMetadata(now: referenceDate, calendar: calendar),
            rules: DemoFixtures.demoTransactionRules(now: referenceDate, calendar: calendar)
        )

        #expect(!dashboard.isEmpty, "demo dashboard rolled up empty")
        #expect(dashboard.totalSpent > 0, "demo dashboard has no spend")

        // Every group's spend is the sum of its leaves, and the overall total is
        // the sum of every group — the builder's core invariant, exercised on real
        // demo data rather than a hand-built set.
        for group in dashboard.groups {
            let leafSum = group.leaves.reduce(0) { $0 + $1.spent }
            #expect(abs(group.spent - leafSum) < 0.005, "\(group.group) spend != leaf sum")
        }
        let groupSum = dashboard.groups.reduce(0) { $0 + $1.spent }
        #expect(abs(dashboard.totalSpent - groupSum) < 0.005, "overall total != group sum")

        // No leaf ever reads negative (refunds are floored to 0 per leaf).
        #expect(dashboard.leaves.allSatisfy { $0.spent >= 0 })
    }

    /// Transfers and income never reach the rollup: the demo set has a paycheck
    /// (`tx3` Stripe / `tx19` direct deposit, category `.income`) and a Venmo
    /// outflow the user confirmed as a transfer (`tx14`). None may appear as a
    /// spendable leaf in the demo dashboard.
    @Test("Income and confirmed transfers never surface as spend in the demo rollup")
    func incomeAndTransfersAbsentFromDemoRollup() {
        let dashboard = CategoryDashboardBuilder.build(
            transactions: DemoFixtures.transactions(now: referenceDate, calendar: calendar),
            budgets: demoBudgetMap(),
            asOf: referenceDate,
            calendar: calendar,
            metadata: DemoFixtures.demoReviewMetadata(now: referenceDate, calendar: calendar),
            rules: DemoFixtures.demoTransactionRules(now: referenceDate, calendar: calendar)
        )

        let nonSpending: Set<SpendingCategory> = [.income, .transfer, .transferOut]
        for leaf in dashboard.leaves {
            #expect(!nonSpending.contains(leaf.category), "\(leaf.category) leaked into the rollup")
        }
    }

    // MARK: - An override actually moves demo spend

    /// The headline continuity contract: recategorizing in the demo inbox moves a
    /// real number. `tx52` (Blue Bottle Coffee) arrives with **no Plaid category**
    /// and is seeded `reviewed` with a `userCategory: .foodAndDrink` override. Run
    /// over the demo transactions, the override must add its $6.75 to Food & Drink
    /// — and that money must be absent when the same set is bucketed by raw Plaid
    /// category (no metadata).
    @Test("A demo userCategory override moves Blue Bottle spend into Food & Drink")
    func demoOverrideMovesSpend() {
        let transactions = DemoFixtures.transactions(now: referenceDate, calendar: calendar)
        let metadata = DemoFixtures.demoReviewMetadata(now: referenceDate, calendar: calendar)
        let rules = DemoFixtures.demoTransactionRules(now: referenceDate, calendar: calendar)

        // Guard the fixture precondition: the override exists and the transaction
        // has no raw Plaid category (so the move is attributable to the override).
        let blueBottleOverride = metadata.first { $0.id == "tx52" }
        #expect(blueBottleOverride?.userCategory == .foodAndDrink)
        let blueBottle = transactions.first { $0.id == "tx52" }
        #expect(blueBottle?.category == nil, "tx52 should arrive uncategorized")
        let amount = blueBottle?.amount ?? 0
        #expect(amount > 0)

        let monthStart = CategoryBudgetPlanner.monthStartDate(asOf: referenceDate, calendar: calendar)!
        let nextMonthStart = calendar.date(byAdding: .month, value: 1, to: monthStart)!
        let startKey = Formatters.transactionDateString(monthStart)
        let endKey = Formatters.transactionDateString(nextMonthStart)

        // Raw bucketing (no override): the uncategorized row falls back to `.other`,
        // so its amount is NOT in Food & Drink.
        let rawByCategory = CategoryBudgetPlanner.netSpendByCategory(
            from: transactions,
            startKey: startKey,
            endKey: endKey
        )
        // Override-aware bucketing: the row now counts under Food & Drink.
        let resolvedByCategory = CategoryBudgetPlanner.netSpendByCategory(
            from: transactions,
            startKey: startKey,
            endKey: endKey,
            metadata: metadata,
            rules: rules
        )

        let rawFood = rawByCategory[.foodAndDrink] ?? 0
        let resolvedFood = resolvedByCategory[.foodAndDrink] ?? 0
        #expect(
            resolvedFood >= rawFood + amount - 0.005,
            "override did not add \(amount) to Food & Drink (raw \(rawFood) → resolved \(resolvedFood))"
        )

        // And the same money is no longer attributed to `.other` once resolved.
        let rawOther = rawByCategory[.other] ?? 0
        let resolvedOther = resolvedByCategory[.other] ?? 0
        #expect(
            resolvedOther <= rawOther - amount + 0.005,
            "override did not remove \(amount) from .other (raw \(rawOther) → resolved \(resolvedOther))"
        )
    }

    /// The confirmed-transfer demo override (`tx14` Venmo, also covered by the
    /// Venmo rule) must drop the row from spend math entirely. The row is a
    /// negative-amount (inflow) charge mis-labeled `.income` by Plaid; once the
    /// user marks it a transfer + excluded, it must not net into any category.
    @Test("A demo transfer / excluded override drops the Venmo row from spend math")
    func demoTransferOverrideDropsRow() {
        let transactions = DemoFixtures.transactions(now: referenceDate, calendar: calendar)
        let metadata = DemoFixtures.demoReviewMetadata(now: referenceDate, calendar: calendar)
        let rules = DemoFixtures.demoTransactionRules(now: referenceDate, calendar: calendar)

        let venmo = metadata.first { $0.id == "tx14" }
        #expect(venmo?.isTransferOverride == true)
        #expect(venmo?.excludedFromBudgets == true)

        let resolution = EffectiveCategoryResolver.resolve(
            transaction: transactions.first { $0.id == "tx14" }!,
            metadata: venmo,
            rules: rules
        )
        #expect(resolution.isTransfer || resolution.excludedFromBudgets, "Venmo row not excluded")

        // The Venmo amount must never appear as category spend in the dashboard.
        let dashboard = CategoryDashboardBuilder.build(
            transactions: transactions,
            budgets: demoBudgetMap(),
            asOf: referenceDate,
            calendar: calendar,
            metadata: metadata,
            rules: rules
        )
        // -1,500 would net Bills/Income heavily negative if it leaked; assert no
        // group carries a suspiciously low (refund-like) total from it by checking
        // the transfers group never appears as a spendable leaf.
        #expect(dashboard.group(.transfers) == nil, "transfer leaked into the rollup")
    }

    /// A rule recategorization is part of the same continuity story: the seeded
    /// Starbucks → Food & Drink rule must resolve a matching demo charge to Food &
    /// Drink even if we strip its raw category, proving the rule path moves spend
    /// in `--demo` and not just user overrides.
    @Test("A demo rule recategorizes a matching transaction before aggregation")
    func demoRuleRecategorizes() {
        let rules = DemoFixtures.demoTransactionRules(now: referenceDate, calendar: calendar)
        let starbucksRule = rules.first { $0.matchMerchantContains == "Starbucks" }
        #expect(starbucksRule?.category == .foodAndDrink)

        // Strip the raw category so the resolved category is attributable to the
        // rule, not to Plaid. A real Starbucks demo charge (tx11) carries the
        // Starbucks merchant name the rule matches on.
        let stripped = TransactionDTO(
            id: "tx11",
            accountId: "demo_checking",
            amount: 12.50,
            date: Formatters.transactionDateString(referenceDate),
            name: "STARBUCKS 8823",
            merchantName: "Starbucks",
            category: nil
        )
        #expect(starbucksRule?.matches(stripped) == true, "Starbucks rule did not match the demo charge")

        let resolution = EffectiveCategoryResolver.resolve(
            transaction: stripped,
            metadata: nil,
            rules: rules
        )
        #expect(resolution.category == .foodAndDrink, "rule did not recategorize the demo charge")
    }

    // MARK: - Status-band continuity

    /// The seeded `demoBudgets` scored against `demoBudgetScoringTransactions`
    /// through the **dashboard builder** must surface at least one over- and one
    /// nearing-budget leaf, so every status band is demoable on the Category
    /// Dashboard — complementing the AND-543 test that asserts the same via the
    /// budget-card `presentation`.
    @Test("Demo budgets band at least one over and one nearing leaf in the dashboard")
    func demoBudgetsProduceOverAndNearing() {
        let dashboard = CategoryDashboardBuilder.build(
            transactions: DemoFixtures.demoBudgetScoringTransactions(now: referenceDate, calendar: calendar),
            budgets: demoBudgetMap(),
            asOf: referenceDate,
            calendar: calendar
        )

        #expect(dashboard.overBudgetCount >= 1, "no demo leaf is over budget")
        #expect(dashboard.nearingCount >= 1, "no demo leaf is nearing its budget")

        // Shopping is hand-tuned to blow its $500 limit; lock that specific
        // attention signal so a fixture edit that quietly flattens it is caught.
        let shopping = dashboard.leaf(.shopping)
        #expect(shopping?.status == .over, "demo Shopping should be over budget")
    }

    /// The dashboard's status mix must survive every day of the month: the
    /// scoring rows are anchored to the start of the current month so opening
    /// `--demo` on the 1st never collapses the spread to all-under. This is the
    /// dashboard analogue of the AND-543 budget-card month-boundary test.
    @Test("Demo dashboard status mix is stable across every day of the month")
    func demoDashboardStatusMixSurvivesMonthBoundaries() {
        let budgets = demoBudgetMap()
        var components = DateComponents()
        components.year = 2025
        components.month = 1
        components.hour = 12

        var observed: Set<String> = []
        for day in 1...31 {
            components.day = day
            let asOf = calendar.date(from: components)!
            let dashboard = CategoryDashboardBuilder.build(
                transactions: DemoFixtures.demoBudgetScoringTransactions(now: asOf, calendar: calendar),
                budgets: budgets,
                asOf: asOf,
                calendar: calendar
            )
            // Every day must keep at least one over and one nearing leaf.
            #expect(dashboard.overBudgetCount >= 1, "day \(day): nothing over budget")
            #expect(dashboard.nearingCount >= 1, "day \(day): nothing nearing budget")

            let fingerprint = "over=\(dashboard.overBudgetCount) near=\(dashboard.nearingCount)"
                + " spent=\(Int(dashboard.totalSpent.rounded()))"
            observed.insert(fingerprint)
        }
        // The anchored rows are identical month-relative every day, so the rollup
        // fingerprint never drifts.
        #expect(observed.count == 1, "demo dashboard drifted across the month: \(observed)")
    }

    // MARK: - Review-state coverage

    /// The demo review metadata must exercise every documented review state so the
    /// `--demo` Review Inbox and the override-aware spend math are both fully
    /// demoable: a still-open item, an ignored item, a `userCategory` override, and
    /// an `excludedFromBudgets` transfer.
    @Test("Demo review metadata covers reviewed, ignored, override, and excluded states")
    func demoMetadataCoversAllReviewStates() {
        let metadata = DemoFixtures.demoReviewMetadata(now: referenceDate, calendar: calendar)

        #expect(metadata.contains { $0.status == .needsReview }, "no open review item")
        #expect(metadata.contains { $0.status == .reviewed }, "no reviewed item")
        #expect(metadata.contains { $0.status == .ignored }, "no ignored item")
        #expect(metadata.contains { $0.userCategory != nil }, "no userCategory override")
        #expect(metadata.contains { $0.excludedFromBudgets }, "no excluded-from-budgets item")
        #expect(metadata.contains { $0.isTransferOverride == true }, "no transfer override")
    }

    /// Every demo metadata / rule id resolves against a real demo transaction, and
    /// the seeded fixtures together produce a non-empty review inbox — the basic
    /// "nothing dangles, the inbox isn't empty" continuity guard, asserted through
    /// the real `TransactionReviewInbox.evaluate` over the full demo set.
    @Test("Demo fixtures drive a non-empty inbox with no dangling references")
    func demoFixturesDriveNonEmptyInbox() {
        let transactions = DemoFixtures.transactions(now: referenceDate, calendar: calendar)
        let transactionIds = Set(transactions.map(\.id))
        let metadata = DemoFixtures.demoReviewMetadata(now: referenceDate, calendar: calendar)
        let rules = DemoFixtures.demoTransactionRules(now: referenceDate, calendar: calendar)

        for record in metadata {
            #expect(transactionIds.contains(record.id), "metadata id \(record.id) dangles")
        }
        for rule in rules {
            #expect(transactions.contains { rule.matches($0) }, "rule \(rule.id) matches nothing")
        }

        let snapshot = TransactionReviewInbox.evaluate(
            transactions: transactions,
            metadata: metadata,
            rules: rules,
            recurring: [],
            now: referenceDate
        )
        #expect(snapshot.totalCount > 0, "demo review inbox was empty")
    }
}
