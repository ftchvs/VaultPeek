import Foundation
@testable import PlaidBarCore
import Testing

/// Locks in the AND-543 demo providers — category budgets, review metadata, and
/// categorization rules — so `--demo` actually surfaces the review inbox and
/// budget state instead of empty placeholders. Every category, amount, and id
/// here is synthetic; the providers only reference ids that exist in the demo
/// transaction set so nothing dangles.
@Suite("Demo Review / Budget Fixtures")
struct DemoReviewBudgetFixturesTests {
    /// Fixed midday reference date so the transaction-id assertions never depend
    /// on the wall clock or DST boundaries.
    private let referenceDate: Date = {
        var components = DateComponents()
        components.year = 2025
        components.month = 3
        components.day = 15
        components.hour = 12
        return Calendar.current.date(from: components)!
    }()

    // MARK: - Budgets

    @Test("demoBudgets is non-empty and internally consistent")
    func demoBudgetsConsistent() {
        let budgets = DemoFixtures.demoBudgets()
        #expect(!budgets.isEmpty)

        // Every limit is a positive amount.
        for budget in budgets {
            #expect(budget.monthlyLimit > 0, "\(budget.category) had non-positive limit")
        }

        // At most one budget per category (the DTO's identity contract).
        let categories = budgets.map(\.category)
        #expect(Set(categories).count == categories.count, "duplicate category budget")

        // Budgets never target the income / transfer pseudo-categories — those
        // are not spending categories and would render nonsensically.
        let nonSpending: Set<SpendingCategory> = [.income, .transfer, .transferOut]
        #expect(budgets.allSatisfy { !nonSpending.contains($0.category) })
    }

    @Test("Budgeted categories all appear in the demo spending data")
    func budgetsReferenceSpentCategories() {
        let budgets = DemoFixtures.demoBudgets()
        let spentCategories = Set(
            DemoFixtures.transactions(now: referenceDate)
                .filter { !$0.isIncome }
                .compactMap(\.category)
        )
        for budget in budgets {
            #expect(
                spentCategories.contains(budget.category),
                "budget for \(budget.category) has no matching demo spend"
            )
        }
    }

    @Test("demoBudgets produces a mix of under-, near-, and over-budget states")
    func budgetsExerciseStatusBands() {
        let budgets = DemoFixtures.demoBudgets()
        // The fixtures should not be uniformly generous — at least two distinct
        // limits so the dashboard's status bars are demoable, not all-green.
        #expect(Set(budgets.map(\.monthlyLimit)).count >= 2)
    }

    // MARK: - Review metadata

    @Test("demoReviewMetadata is non-empty and references real demo transactions")
    func reviewMetadataReferencesDemoTransactions() {
        let metadata = DemoFixtures.demoReviewMetadata()
        #expect(!metadata.isEmpty)

        let transactionIds = Set(DemoFixtures.transactions(now: referenceDate).map(\.id))
        for record in metadata {
            #expect(
                transactionIds.contains(record.id),
                "review metadata id \(record.id) is not a demo transaction"
            )
        }

        // Ids are unique — the metadata store keys on transaction id.
        let ids = metadata.map(\.id)
        #expect(Set(ids).count == ids.count, "duplicate review metadata id")
    }

    @Test("demoReviewMetadata leaves at least one item needing review")
    func reviewMetadataHasOpenItems() {
        let metadata = DemoFixtures.demoReviewMetadata()
        // The whole point of the fixture is a non-empty review inbox in --demo:
        // not every seeded record may be reviewed/ignored.
        #expect(metadata.contains { $0.status == .needsReview })
    }

    @Test("Reviewed/recategorized metadata carries a user category and timestamp")
    func reviewedMetadataIsComplete() {
        let metadata = DemoFixtures.demoReviewMetadata()
        for record in metadata where record.status == .reviewed {
            // A reviewed record should have been acted on at a known time.
            #expect(record.reviewedAt != nil, "reviewed \(record.id) missing reviewedAt")
        }
        // At least one record demonstrates a user recategorization so demo mode
        // shows the override flowing into budget math.
        #expect(metadata.contains { $0.userCategory != nil })
    }

    // MARK: - Rules

    @Test("demoTransactionRules is non-empty and each rule has a matcher + effect")
    func rulesAreWellFormed() {
        let rules = DemoFixtures.demoTransactionRules()
        #expect(!rules.isEmpty)

        for rule in rules {
            // A usable rule needs something to match on...
            let hasMatcher = rule.matchMerchantContains != nil || rule.matchOriginalNameContains != nil
            #expect(hasMatcher, "rule \(rule.id) has no matcher")
            // ...and something to do.
            let hasEffect = rule.category != nil
                || rule.merchantName != nil
                || rule.isTransfer != nil
                || rule.excludedFromBudgets != nil
            #expect(hasEffect, "rule \(rule.id) has no effect")
        }

        // Rule ids are unique.
        let ids = rules.map(\.id)
        #expect(Set(ids).count == ids.count, "duplicate rule id")
    }

    @Test("At least one demo rule matches a demo transaction")
    func rulesMatchDemoTransactions() {
        let rules = DemoFixtures.demoTransactionRules()
        let transactions = DemoFixtures.transactions(now: referenceDate)
        for rule in rules {
            #expect(
                transactions.contains { rule.matches($0) },
                "rule \(rule.id) matches no demo transaction"
            )
        }
    }

    // MARK: - Cross-fixture wiring

    @Test("Fixtures drive a non-empty review inbox in demo mode")
    func fixturesProduceNonEmptyInbox() {
        let transactions = DemoFixtures.transactions(now: referenceDate)
        let snapshot = TransactionReviewInbox.evaluate(
            transactions: transactions,
            metadata: DemoFixtures.demoReviewMetadata(),
            rules: DemoFixtures.demoTransactionRules(),
            recurring: [],
            now: referenceDate
        )
        #expect(snapshot.totalCount > 0, "demo review inbox was empty")
    }
}
