import Foundation
import Testing
@testable import PlaidBarCore

@Suite("Category budget alert evaluator (AND-642)")
struct CategoryBudgetAlertEvaluatorTests {
    // 2025-06-15T13:46:40Z, UTC — a fixed mid-month reference so month keys are
    // stable across runs (the exact year is asserted in deterministicMonthKey).
    private let fixedNow = Date(timeIntervalSince1970: 1_750_000_000)
    private var utcCalendar: Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "UTC")!
        return calendar
    }

    private func item(
        _ category: SpendingCategory,
        limit: Double,
        spent: Double,
        isSuggested: Bool = false
    ) -> CategoryBudgetPresentation.Item {
        CategoryBudgetPresentation.Item(
            category: category, monthlyLimit: limit, spent: spent, isSuggested: isSuggested
        )
    }

    // MARK: - Crossing logic

    @Test("Only nearing and over categories alert; under and unbudgeted are silent")
    func emitsOnlyAttentionBands() {
        let presentation = CategoryBudgetPresentation(items: [
            item(.foodAndDrink, limit: 200, spent: 250),     // over (1.25)
            item(.shopping, limit: 100, spent: 85),          // nearing (0.85)
            item(.transportation, limit: 100, spent: 40),    // under (0.40)
            item(.entertainment, limit: 0, spent: 500),      // unbudgeted: no limit
        ])

        let alerts = CategoryBudgetAlertEvaluator.evaluate(
            presentation: presentation, now: fixedNow, calendar: utcCalendar
        )

        #expect(alerts.map(\.category) == [.foodAndDrink, .shopping])
        #expect(alerts.map(\.band) == [.over, .nearing])
        // Worst-first: over precedes nearing.
        #expect(alerts.first?.band == .over)
    }

    @Test("Alerts are ordered over-first then by category name")
    func ordersWorstFirstThenName() {
        let presentation = CategoryBudgetPresentation(items: [
            item(.shopping, limit: 100, spent: 90),          // nearing — "Shopping"
            item(.foodAndDrink, limit: 100, spent: 95),      // nearing — "Food & Drink"
            item(.transportation, limit: 100, spent: 130),   // over — "Transportation"
        ])

        let alerts = CategoryBudgetAlertEvaluator.evaluate(
            presentation: presentation, now: fixedNow, calendar: utcCalendar
        )

        // Over first; the two nearing alerts then sort by display name
        // ("Food & Drink" < "Shopping").
        #expect(alerts.map(\.category) == [.transportation, .foodAndDrink, .shopping])
    }

    @Test("Suggested budgets do not alert unless explicitly included")
    func suggestedExcludedByDefault() {
        let presentation = CategoryBudgetPresentation(items: [
            item(.foodAndDrink, limit: 200, spent: 260, isSuggested: true),  // over but suggested
            item(.shopping, limit: 100, spent: 95),                          // nearing, explicit
        ])

        let defaultAlerts = CategoryBudgetAlertEvaluator.evaluate(
            presentation: presentation, now: fixedNow, calendar: utcCalendar
        )
        #expect(defaultAlerts.map(\.category) == [.shopping])

        let inclusiveAlerts = CategoryBudgetAlertEvaluator.evaluate(
            presentation: presentation, includeSuggested: true, now: fixedNow, calendar: utcCalendar
        )
        #expect(inclusiveAlerts.map(\.category) == [.foodAndDrink, .shopping])
    }

    @Test("A stricter near-threshold widens the nearing band without recomputing spend")
    func nearThresholdOverride() {
        // 0.85 consumed: under the default 0.8 nearing band? No — it is nearing.
        // 0.72 consumed: under at 0.8, but nearing once the threshold drops to 0.7.
        let presentation = CategoryBudgetPresentation(items: [
            item(.shopping, limit: 100, spent: 72),
        ])

        let atDefault = CategoryBudgetAlertEvaluator.evaluate(
            presentation: presentation, now: fixedNow, calendar: utcCalendar
        )
        #expect(atDefault.isEmpty)

        let atSeventy = CategoryBudgetAlertEvaluator.evaluate(
            presentation: presentation, nearThreshold: 0.7, now: fixedNow, calendar: utcCalendar
        )
        #expect(atSeventy.map(\.band) == [.nearing])
    }

    @Test("Boundary at exactly the limit is nearing, just over is over")
    func bandBoundaries() {
        #expect(CategoryBudgetAlertEvaluator.band(forFraction: 0.79, nearThreshold: 0.8) == .under)
        #expect(CategoryBudgetAlertEvaluator.band(forFraction: 0.80, nearThreshold: 0.8) == .nearing)
        #expect(CategoryBudgetAlertEvaluator.band(forFraction: 1.00, nearThreshold: 0.8) == .nearing)
        #expect(CategoryBudgetAlertEvaluator.band(forFraction: 1.01, nearThreshold: 0.8) == .over)
    }

    @Test("Alert id and month key are deterministic for the reference month")
    func deterministicMonthKey() {
        let presentation = CategoryBudgetPresentation(items: [
            item(.foodAndDrink, limit: 100, spent: 120),
        ])
        let alert = CategoryBudgetAlertEvaluator.evaluate(
            presentation: presentation, now: fixedNow, calendar: utcCalendar
        ).first
        #expect(alert?.monthKey == "2025-06")
        #expect(alert?.id == "FOOD_AND_DRINK#2025-06#over")
    }

    // MARK: - Notification integration + de-dup

    @Test("Budget alert decisions surface through the trigger selection with correct severity")
    func decisionsThroughTriggerSelection() {
        let presentation = CategoryBudgetPresentation(items: [
            item(.foodAndDrink, limit: 100, spent: 130),  // over
            item(.shopping, limit: 100, spent: 90),        // nearing
        ])

        let evaluation = NotificationTriggerSelection.evaluate(
            budgetPresentation: presentation,
            now: fixedNow,
            calendar: utcCalendar
        )

        let budgetDecisions = evaluation.decisions.filter { $0.kind == .categoryBudgetAlert }
        #expect(budgetDecisions.count == 2)
        // Over is a warning; nearing is an advisory informational heads-up. Bodies
        // are intentionally generic (lock-screen safe) and dedup keys are hashed,
        // so the two decisions are distinguished by band severity/title, not by a
        // category name.
        let overDecision = budgetDecisions.first { $0.severity == .warning }
        #expect(overDecision?.title == "Over budget")
        #expect(overDecision?.body.contains("over") == true)
        let nearingDecision = budgetDecisions.first { $0.severity == .informational }
        #expect(nearingDecision?.title == "Budget warning")
        #expect(nearingDecision?.body.contains("nearing") == true)
    }

    @Test("A category fires once at nearing then again when it escalates to over, not every refresh")
    func dedupEscalation() {
        let nearingPresentation = CategoryBudgetPresentation(items: [
            item(.foodAndDrink, limit: 100, spent: 90),  // nearing
        ])

        let first = NotificationTriggerSelection.evaluate(
            budgetPresentation: nearingPresentation, now: fixedNow, calendar: utcCalendar
        )
        let nearingKey = first.decisions.first { $0.kind == .categoryBudgetAlert }?.dedupKey
        #expect(nearingKey != nil)

        // Same band on the next refresh, key already delivered: no new decision.
        let repeated = NotificationTriggerSelection.evaluate(
            budgetPresentation: nearingPresentation,
            now: fixedNow,
            calendar: utcCalendar,
            deliveredDedupKeys: [nearingKey!]
        )
        #expect(repeated.decisions.filter { $0.kind == .categoryBudgetAlert }.isEmpty)
        // A one-shot band crossing does not auto-resolve when it stays put.
        #expect(repeated.resolvedDedupKeys.isEmpty)

        // Now it crosses into over: a distinct band key fires even though the
        // nearing key was already delivered.
        let overPresentation = CategoryBudgetPresentation(items: [
            item(.foodAndDrink, limit: 100, spent: 130),  // over
        ])
        let escalated = NotificationTriggerSelection.evaluate(
            budgetPresentation: overPresentation,
            now: fixedNow,
            calendar: utcCalendar,
            deliveredDedupKeys: [nearingKey!]
        )
        let overDecisions = escalated.decisions.filter { $0.kind == .categoryBudgetAlert }
        #expect(overDecisions.count == 1)
        #expect(overDecisions.first?.dedupKey != nearingKey)
    }

    @Test("Disabling the budget-alert family suppresses its decisions")
    func disabledFamilySuppressed() {
        let presentation = CategoryBudgetPresentation(items: [
            item(.foodAndDrink, limit: 100, spent: 130),
        ])
        let evaluation = NotificationTriggerSelection.evaluate(
            budgetPresentation: presentation,
            now: fixedNow,
            calendar: utcCalendar,
            config: NotificationTriggers(categoryBudgetAlert: false)
        )
        #expect(evaluation.decisions.allSatisfy { $0.kind != .categoryBudgetAlert })
    }

    // MARK: - Privacy

    @Test("Unmasked body stays generic — never the category name or an amount (lock-screen safe)")
    func unmaskedBodyIsLockScreenSafe() {
        let presentation = CategoryBudgetPresentation(items: [
            item(.foodAndDrink, limit: 100, spent: 137.42),
        ])
        let evaluation = NotificationTriggerSelection.evaluate(
            budgetPresentation: presentation,
            privacyMaskActive: false,
            now: fixedNow,
            calendar: utcCalendar
        )
        let body = evaluation.decisions.first { $0.kind == .categoryBudgetAlert }?.body ?? ""
        // A delivered notification renders on the lock screen, which the in-app
        // Privacy Mask cannot guard — so the body must never name the category,
        // even when the in-app surface is unmasked (matches every other trigger).
        #expect(!body.contains("Food & Drink"))
        #expect(body.contains("over"))
        // No amount, no dollar sign, no raw figures.
        #expect(!body.contains("$"))
        #expect(!body.contains("137"))
        #expect(!body.contains("100"))
    }

    @Test("Masked body omits the category name and the amount")
    func maskedBodyOmitsCategoryAndAmount() {
        let presentation = CategoryBudgetPresentation(items: [
            item(.foodAndDrink, limit: 100, spent: 137.42),  // over
            item(.shopping, limit: 100, spent: 90),          // nearing
        ])
        let evaluation = NotificationTriggerSelection.evaluate(
            budgetPresentation: presentation,
            privacyMaskActive: true,
            now: fixedNow,
            calendar: utcCalendar
        )

        let bodies = evaluation.decisions
            .filter { $0.kind == .categoryBudgetAlert }
            .map(\.body)
        #expect(bodies.count == 2)
        for body in bodies {
            #expect(!body.contains("Food & Drink"))
            #expect(!body.contains("Shopping"))
            #expect(!body.contains("$"))
            #expect(!body.contains("137"))
        }
        // The status verb still distinguishes over from nearing without naming the
        // category, so the masked alert remains useful.
        #expect(bodies.contains { $0.contains("over") })
        #expect(bodies.contains { $0.contains("nearing") })
    }

    @Test("Dedup keys do not expose the category amount or limit")
    func dedupKeysHideAmounts() {
        let presentation = CategoryBudgetPresentation(items: [
            item(.foodAndDrink, limit: 137, spent: 999),
        ])
        let evaluation = NotificationTriggerSelection.evaluate(
            budgetPresentation: presentation, now: fixedNow, calendar: utcCalendar
        )
        let key = evaluation.decisions.first { $0.kind == .categoryBudgetAlert }?.dedupKey ?? ""
        // The dedup key is hashed (see NotificationTriggerSelection.dedupKey), so
        // neither the spend nor the limit leaks into it.
        #expect(!key.contains("999"))
        #expect(!key.contains("137"))
        #expect(key.hasPrefix("category-budget-alert:"))
    }
}
