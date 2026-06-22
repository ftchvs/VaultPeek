import Foundation
@testable import PlaidBarCore
import Testing

/// Tests for `EffectiveCategoryResolver` (AND-525): the pure type lifted out of
/// `TransactionReviewInbox.resolveCategory` that resolves a transaction's
/// *effective* category / transfer-ness / budget-exclusion from its review
/// metadata and any matching rules — the override-aware foundation AND-526's
/// spend math builds on.
///
/// All inputs are synthetic; no real Plaid data.
@Suite("Effective Category Resolver Tests")
struct EffectiveCategoryResolverTests {
    // MARK: - Category precedence (behavior-preserving lift)

    @Test("No override returns the Plaid base category")
    func plaidCategoryIsBaseline() {
        let transaction = tx(id: "plaid", category: .shopping)

        let resolution = EffectiveCategoryResolver.resolve(transaction: transaction)

        #expect(resolution.category == .shopping)
        #expect(resolution.source == .plaidCategory)
        #expect(resolution.isTransfer == false)
        #expect(resolution.excludedFromBudgets == false)
    }

    @Test("A user category override wins over the Plaid category")
    func userCategoryOverrideWins() {
        let transaction = tx(id: "override", category: .shopping)
        let metadata = TransactionReviewMetadata(id: "override", userCategory: .foodAndDrink)

        let resolution = EffectiveCategoryResolver.resolve(
            transaction: transaction,
            metadata: metadata
        )

        // The user's choice stands; an override is not tagged as a suggestion.
        #expect(resolution.category == .foodAndDrink)
        #expect(resolution.source == nil)
    }

    @Test("Nil Plaid category with no resolvable name stays uncategorized")
    func unresolvableNilCategoryStaysNil() {
        let transaction = tx(id: "unknown", name: "SQ *KMNT LLC 9921", category: nil, merchantName: nil)

        let resolution = EffectiveCategoryResolver.resolve(transaction: transaction)

        #expect(resolution.category == nil)
        #expect(resolution.source == nil)
    }

    @Test("A nil-category transaction exposes the NL suggestion but does not budget it")
    func nlBackfillsResolvableMissingCategory() {
        let transaction = tx(id: "nl", name: "BLUE BOTTLE COFFEE", category: nil, merchantName: nil)

        let resolution = EffectiveCategoryResolver.resolve(transaction: transaction)

        // Budget surface: an unapproved NL suggestion is NOT the aggregation
        // category — the row stays uncategorized until the user approves it.
        #expect(resolution.category == nil)
        #expect(resolution.source == nil)
        // …but the suggestion is still exposed for display ("Suggested" badge).
        #expect(resolution.suggestedCategory == .foodAndDrink)
    }

    @Test("A low-confidence Plaid category surfaces an NL suggestion without budgeting it")
    func nlBackfillsLowConfidencePlaidCategory() {
        let transaction = tx(
            id: "nl-low",
            name: "NETFLIX.COM",
            category: .other,
            merchantName: nil,
            lowConfidence: true
        )

        let resolution = EffectiveCategoryResolver.resolve(transaction: transaction)

        // Low-confidence Plaid is not a confident category, and the NL tier is
        // display-only on the budget surface → uncategorized for aggregation.
        #expect(resolution.category == nil)
        #expect(resolution.source == nil)
        #expect(resolution.suggestedCategory == .entertainment)
    }

    @Test("A confident Plaid category is not overridden by the NL tier")
    func confidentPlaidCategoryWins() {
        let transaction = tx(id: "confident", name: "BLUE BOTTLE COFFEE", category: .shopping, merchantName: nil)

        let resolution = EffectiveCategoryResolver.resolve(transaction: transaction)

        #expect(resolution.category == .shopping)
        #expect(resolution.source == .plaidCategory)
    }

    @Test("NL never wins over a user category override")
    func userOverrideBeatsNLInference() {
        let transaction = tx(id: "nl-user", name: "BLUE BOTTLE COFFEE", category: nil, merchantName: nil)
        let metadata = TransactionReviewMetadata(id: "nl-user", userCategory: .shopping)

        let resolution = EffectiveCategoryResolver.resolve(transaction: transaction, metadata: metadata)

        #expect(resolution.category == .shopping)
        #expect(resolution.source == nil)
    }

    // MARK: - Rule-match resolution

    @Test("A matching rule's category resolves an otherwise-uncategorized transaction")
    func ruleCategoryResolvesUncategorized() {
        let transaction = tx(id: "rule", category: nil, merchantName: "Known Merchant")
        let rule = TransactionRule(
            matchMerchantContains: "Known Merchant",
            category: .shopping,
            merchantName: "Known Merchant"
        )

        let resolution = EffectiveCategoryResolver.resolve(
            transaction: transaction,
            rules: [rule]
        )

        #expect(resolution.category == .shopping)
    }

    @Test("A non-matching rule leaves the base category untouched")
    func nonMatchingRuleIsIgnored() {
        let transaction = tx(id: "no-rule", category: .foodAndDrink, merchantName: "Coffee Shop")
        let rule = TransactionRule(
            matchMerchantContains: "Some Other Place",
            category: .shopping
        )

        let resolution = EffectiveCategoryResolver.resolve(transaction: transaction, rules: [rule])

        #expect(resolution.category == .foodAndDrink)
    }

    @Test("The most recently created same-merchant rule wins over an older one")
    func newestSameMerchantRuleWins() {
        // Re-categorization: the user first filed Acme → shopping, then later
        // re-filed Acme → foodAndDrink. The newer rule (by createdAt) must win,
        // regardless of array order — the bug resolved by array index, so the
        // stale earliest rule kept applying and the newer choice looked dead.
        let transaction = tx(id: "recat", category: nil, merchantName: "Acme Corp")
        let older = TransactionRule(
            matchMerchantContains: "Acme",
            category: .shopping,
            createdAt: Date(timeIntervalSince1970: 1_000)
        )
        let newer = TransactionRule(
            matchMerchantContains: "Acme",
            category: .foodAndDrink,
            createdAt: Date(timeIntervalSince1970: 2_000)
        )

        // Older first in the array (the natural append order) — newer must still win.
        let resolution = EffectiveCategoryResolver.resolve(
            transaction: transaction,
            rules: [older, newer]
        )

        #expect(resolution.category == .foodAndDrink)
    }

    // MARK: - Override vs rule precedence

    @Test("A user category override wins over a matching rule's category")
    func overrideBeatsRule() {
        let transaction = tx(id: "both", category: .shopping, merchantName: "Known Merchant")
        let metadata = TransactionReviewMetadata(id: "both", userCategory: .travel)
        let rule = TransactionRule(
            matchMerchantContains: "Known Merchant",
            category: .foodAndDrink
        )

        let resolution = EffectiveCategoryResolver.resolve(
            transaction: transaction,
            metadata: metadata,
            rules: [rule]
        )

        #expect(resolution.category == .travel)
        #expect(resolution.source == nil)
    }

    @Test("A matching rule's category wins over the Plaid base category")
    func ruleBeatsPlaidCategory() {
        let transaction = tx(id: "rule-vs-plaid", category: .other, merchantName: "Known Merchant")
        let rule = TransactionRule(
            matchMerchantContains: "Known Merchant",
            category: .billsAndUtilities
        )

        let resolution = EffectiveCategoryResolver.resolve(transaction: transaction, rules: [rule])

        #expect(resolution.category == .billsAndUtilities)
    }

    // MARK: - Transfer resolution

    @Test("A transfer override marks the resolution as a transfer")
    func transferOverrideMarksTransfer() {
        let transaction = tx(id: "transfer", name: "CHASE CREDIT CARD PAYMENT", category: .other)
        let metadata = TransactionReviewMetadata(id: "transfer", isTransferOverride: true)

        let resolution = EffectiveCategoryResolver.resolve(transaction: transaction, metadata: metadata)

        #expect(resolution.isTransfer == true)
    }

    @Test("A transfer-category transaction resolves as a transfer without an override")
    func transferCategoryIsTransfer() {
        let transaction = tx(id: "xfer-in", category: .transfer)

        let resolution = EffectiveCategoryResolver.resolve(transaction: transaction)

        #expect(resolution.isTransfer == true)
    }

    @Test("A matching rule can mark a transaction as a transfer")
    func ruleMarksTransfer() {
        let transaction = tx(id: "rule-xfer", category: .other, merchantName: "My Brokerage")
        let rule = TransactionRule(matchMerchantContains: "My Brokerage", isTransfer: true)

        let resolution = EffectiveCategoryResolver.resolve(transaction: transaction, rules: [rule])

        #expect(resolution.isTransfer == true)
    }

    @Test("An explicit non-transfer override beats a transfer-looking category")
    func transferOverrideFalseWins() {
        let transaction = tx(id: "not-xfer", category: .transfer)
        let metadata = TransactionReviewMetadata(id: "not-xfer", isTransferOverride: false)

        let resolution = EffectiveCategoryResolver.resolve(transaction: transaction, metadata: metadata)

        #expect(resolution.isTransfer == false)
    }

    // MARK: - Excluded-from-budget handling

    @Test("Excluded-from-budgets metadata flows into the resolution")
    func excludedFromBudgetsMetadataWins() {
        let transaction = tx(id: "excluded", category: .shopping)
        let metadata = TransactionReviewMetadata(id: "excluded", excludedFromBudgets: true)

        let resolution = EffectiveCategoryResolver.resolve(transaction: transaction, metadata: metadata)

        #expect(resolution.excludedFromBudgets == true)
    }

    @Test("A transfer is excluded from budgets by default")
    func transferIsExcludedByDefault() {
        let transaction = tx(id: "xfer-excl", category: .transferOut)

        let resolution = EffectiveCategoryResolver.resolve(transaction: transaction)

        #expect(resolution.isTransfer == true)
        #expect(resolution.excludedFromBudgets == true)
    }

    @Test("A rule can exclude a transaction from budgets")
    func ruleExcludesFromBudgets() {
        let transaction = tx(id: "rule-excl", category: .shopping, merchantName: "Reimbursable")
        let rule = TransactionRule(matchMerchantContains: "Reimbursable", excludedFromBudgets: true)

        let resolution = EffectiveCategoryResolver.resolve(transaction: transaction, rules: [rule])

        #expect(resolution.excludedFromBudgets == true)
    }

    @Test("Un-transferring a transfer-category row keeps it in budgets")
    func untransferOverrideKeepsRowInBudgets() {
        // The honored "include this transfer in budgets" path in v1 is the explicit
        // un-transfer override (`isTransferOverride == false`): it clears both the
        // transfer flag and the transfer-default exclusion. (Updated from the old
        // `metadataNotExcludedBeatsTransferDefault`, which assumed a default-`false`
        // `excludedFromBudgets` could beat the transfer default — that semantics is
        // gone, since seeded metadata stores a non-optional `false` that must read
        // as "no opinion", not an explicit include.)
        let transaction = tx(id: "keep", category: .transfer)
        let metadata = TransactionReviewMetadata(
            id: "keep",
            isTransferOverride: false,
            excludedFromBudgets: false
        )

        let resolution = EffectiveCategoryResolver.resolve(transaction: transaction, metadata: metadata)

        #expect(resolution.isTransfer == false)
        #expect(resolution.excludedFromBudgets == false)
    }

    @Test("Seeded default-false metadata does not suppress the transfer-default exclusion")
    func seededMetadataExclusionTransferDefault() {
        // Production seeds EVERY new transaction with a metadata record whose
        // `excludedFromBudgets` defaults to a non-optional `false`. That default
        // must NOT short-circuit the transfer-default exclusion (the original bug).
        let transaction = tx(id: "seeded-xfer", category: .transfer)
        let metadata = TransactionReviewMetadata(id: "seeded-xfer") // defaults: excludedFromBudgets=false

        let resolution = EffectiveCategoryResolver.resolve(transaction: transaction, metadata: metadata)

        #expect(resolution.isTransfer == true)
        #expect(resolution.excludedFromBudgets == true)
    }

    @Test("Seeded default-false metadata does not suppress a rule's budget exclusion")
    func seededMetadataExclusionRuleStillExcludes() {
        // Same seeded default-`false` metadata on a NON-transfer row that a rule
        // marks excluded: the rule's exclusion must still win (original bug
        // suppressed it because the `??` chain stopped at the seeded `false`).
        let transaction = tx(id: "seeded-rule", category: .shopping, merchantName: "Reimbursable")
        let metadata = TransactionReviewMetadata(id: "seeded-rule") // defaults: excludedFromBudgets=false
        let rule = TransactionRule(matchMerchantContains: "Reimbursable", excludedFromBudgets: true)

        let resolution = EffectiveCategoryResolver.resolve(
            transaction: transaction,
            metadata: metadata,
            rules: [rule]
        )

        #expect(resolution.isTransfer == false)
        #expect(resolution.excludedFromBudgets == true)
    }

    // MARK: - NL kept out of the budget category

    @Test("An NL-only merchant is uncategorized for budgets but still suggested for display")
    func nlOnlyMerchantNotBudgetedButSuggested() {
        // Resolvable only via NL: no user category, nil Plaid, no rule. The budget
        // surface must NOT count it as the NL category, while the display surface
        // (`resolveCategory`) is unchanged and still returns the NL suggestion.
        let transaction = tx(id: "nl-only", name: "BLUE BOTTLE COFFEE", category: nil, merchantName: nil)

        let resolution = EffectiveCategoryResolver.resolve(transaction: transaction)
        let display = EffectiveCategoryResolver.resolveCategory(
            transaction: transaction,
            userCategory: nil
        )

        // Budget surface: uncategorized, never the NL category.
        #expect(resolution.category == nil)
        #expect(resolution.source != .appleNaturalLanguage)
        #expect(resolution.suggestedCategory == .foodAndDrink)
        // Display surface unchanged: still returns the NL "Suggested" category.
        #expect(display.category == .foodAndDrink)
        #expect(display.source == .appleNaturalLanguage)
    }

    // MARK: - Parity with TransactionReviewInbox

    @Test("Resolver tracks the inbox for settled categories; keeps unapproved NL out of budgets")
    func resolverMatchesInboxEffectiveCategory() {
        let transactions = [
            tx(id: "p-1", category: .shopping, merchantName: "Acme"),
            tx(id: "p-2", name: "BLUE BOTTLE COFFEE", category: nil, merchantName: nil),
            tx(id: "p-3", category: .other, merchantName: "Mystery"),
            tx(id: "p-4", name: "NETFLIX.COM", category: .other, merchantName: nil, lowConfidence: true),
        ]
        let metadata = [TransactionReviewMetadata(id: "p-1", userCategory: .travel)]

        let snapshot = TransactionReviewInbox.evaluate(
            transactions: transactions,
            metadata: metadata,
            rules: [],
            recurring: [],
            now: now
        )
        let metadataById = Dictionary(uniqueKeysWithValues: metadata.map { ($0.id, $0) })

        for item in snapshot.items {
            let resolution = EffectiveCategoryResolver.resolve(
                transaction: item.transaction,
                metadata: metadataById[item.id]
            )

            // The budget surface attributes spend only to a *settled* category:
            // a user override or a confident Plaid category. Anything the inbox
            // shows as a display-only NL "Suggested" hint, or as a non-confident
            // `.other`, is uncategorized for budgeting — so the budget category
            // diverges from the inbox's effective category for those rows.
            let inboxIsSettled = item.categorySource != .appleNaturalLanguage
                && item.effectiveCategory != nil
                && item.effectiveCategory != .other

            if inboxIsSettled {
                #expect(resolution.category == item.effectiveCategory)
                #expect(resolution.source == item.categorySource)
            } else {
                #expect(resolution.category == nil)
                #expect(resolution.source != .appleNaturalLanguage)
            }

            // The NL suggestion the inbox would surface is still exposed for
            // display, even when it is kept out of the budget category.
            if item.categorySource == .appleNaturalLanguage {
                #expect(resolution.suggestedCategory == item.effectiveCategory)
            }
        }
    }

    // MARK: - Helpers

    private let now = Date(timeIntervalSince1970: 1_800_000_000)

    // MARK: - Plaid passthrough fallback (priority #5)

    @Test("Plaid passthrough exposes the raw Plaid category verbatim")
    func plaidPassthroughExposesRawCategory() {
        let transaction = tx(id: "pt", category: .shopping)

        let resolution = EffectiveCategoryResolver.resolve(transaction: transaction)

        #expect(resolution.plaidCategory == .shopping)
        // Plaid is the source of the budget category here → not overriding Plaid.
        #expect(resolution.isOverridingPlaid == false)
    }

    @Test("isOverridingPlaid is true when a user override differs from Plaid")
    func overridingPlaidWhenUserDiffers() {
        let transaction = tx(id: "ov", category: .shopping)
        let metadata = TransactionReviewMetadata(id: "ov", userCategory: .foodAndDrink)

        let resolution = EffectiveCategoryResolver.resolve(transaction: transaction, metadata: metadata)

        #expect(resolution.category == .foodAndDrink)
        #expect(resolution.plaidCategory == .shopping)
        #expect(resolution.isOverridingPlaid == true)
        #expect(resolution.overrideOrigin == .user)
    }

    @Test("isOverridingPlaid is false when the user override matches Plaid")
    func notOverridingWhenUserMatchesPlaid() {
        let transaction = tx(id: "match", category: .shopping)
        let metadata = TransactionReviewMetadata(id: "match", userCategory: .shopping)

        let resolution = EffectiveCategoryResolver.resolve(transaction: transaction, metadata: metadata)

        #expect(resolution.plaidCategory == .shopping)
        #expect(resolution.isOverridingPlaid == false)
    }

    @Test("isOverridingPlaid is true when a rule differs from Plaid")
    func overridingPlaidWhenRuleDiffers() {
        let transaction = tx(id: "rule", name: "ACME STORE", category: .shopping, merchantName: "Acme")
        let rule = TransactionRule(matchMerchantContains: "Acme", category: .homeImprovement)

        let resolution = EffectiveCategoryResolver.resolve(transaction: transaction, rules: [rule])

        #expect(resolution.category == .homeImprovement)
        #expect(resolution.plaidCategory == .shopping)
        #expect(resolution.isOverridingPlaid == true)
        #expect(resolution.overrideOrigin == .rule)
    }

    @Test("Nil Plaid category never reads as overriding Plaid")
    func nilPlaidNeverOverriding() {
        let transaction = tx(id: "nilp", name: "BLUE BOTTLE COFFEE", category: nil, merchantName: nil)
        let metadata = TransactionReviewMetadata(id: "nilp", userCategory: .foodAndDrink)

        let resolution = EffectiveCategoryResolver.resolve(transaction: transaction, metadata: metadata)

        #expect(resolution.plaidCategory == nil)
        #expect(resolution.isOverridingPlaid == false)
    }

    // MARK: - isOverridingPlaid false-positive guard (codex #1)

    @Test("Low-confidence Plaid with no override does not read as overriding Plaid")
    func lowConfidencePlaidNoOverrideIsNotOverriding() {
        // A Plaid `.other` row flagged LOW/UNKNOWN with NO user/rule override: the
        // budget category falls through to nil (uncategorized). Previously
        // `isOverridingPlaid` was true (raw `.other` != nil budget) and "Restore
        // Plaid category" would have been a no-op — the resolver re-rejects `.other`.
        // It must now read false: there is no actual override and no restorable Plaid.
        let transaction = tx(id: "low-no-ov", name: "MYSTERY LLC", category: .other, merchantName: nil, lowConfidence: true)

        let resolution = EffectiveCategoryResolver.resolve(transaction: transaction)

        #expect(resolution.category == nil)
        #expect(resolution.isOverridingPlaid == false)
        #expect(resolution.overrideOrigin == nil)
    }

    @Test("Plaid .other with no override does not read as overriding Plaid")
    func plaidOtherNoOverrideIsNotOverriding() {
        // Same shape without the low-confidence flag: a bare `.other` Plaid category
        // with no override is not a restorable category, so no override is reported.
        let transaction = tx(id: "other-no-ov", category: .other, merchantName: nil)

        let resolution = EffectiveCategoryResolver.resolve(transaction: transaction)

        #expect(resolution.isOverridingPlaid == false)
        #expect(resolution.overrideOrigin == nil)
    }

    @Test("Nil Plaid with no override does not read as overriding Plaid")
    func nilPlaidNoOverrideIsNotOverriding() {
        let transaction = tx(id: "nil-no-ov", name: "SQ *UNKNOWN", category: nil, merchantName: nil)

        let resolution = EffectiveCategoryResolver.resolve(transaction: transaction)

        #expect(resolution.isOverridingPlaid == false)
        #expect(resolution.overrideOrigin == nil)
    }

    @Test("A user override over a confident Plaid category reads as a user override")
    func userOverrideOverConfidentPlaidIsUserOrigin() {
        let transaction = tx(id: "user-ov", category: .shopping)
        let metadata = TransactionReviewMetadata(id: "user-ov", userCategory: .foodAndDrink)

        let resolution = EffectiveCategoryResolver.resolve(transaction: transaction, metadata: metadata)

        #expect(resolution.isOverridingPlaid == true)
        #expect(resolution.overrideOrigin == .user)
    }

    @Test("A rule over a confident Plaid category reads as a rule override")
    func ruleOverConfidentPlaidIsRuleOrigin() {
        let transaction = tx(id: "rule-ov", name: "ACME STORE", category: .shopping, merchantName: "Acme")
        let rule = TransactionRule(matchMerchantContains: "Acme", category: .homeImprovement)

        let resolution = EffectiveCategoryResolver.resolve(transaction: transaction, rules: [rule])

        #expect(resolution.isOverridingPlaid == true)
        #expect(resolution.overrideOrigin == .rule)
    }

    @Test("A user override over a LOW-confidence Plaid category is not restorable")
    func userOverrideOverLowConfidencePlaidNotRestorable() {
        // The user overrode a row whose Plaid category is low-confidence. Restoring it
        // would just be re-rejected (confidentPlaidCategory == nil), so the affordance
        // must not be offered: isOverridingPlaid is false even though a user override
        // exists. Budget precedence is unaffected — the user's category still wins.
        let transaction = tx(id: "user-low", category: .shopping, merchantName: nil, lowConfidence: true)
        let metadata = TransactionReviewMetadata(id: "user-low", userCategory: .foodAndDrink)

        let resolution = EffectiveCategoryResolver.resolve(transaction: transaction, metadata: metadata)

        #expect(resolution.category == .foodAndDrink) // override still wins for budgets
        #expect(resolution.isOverridingPlaid == false)
        #expect(resolution.overrideOrigin == nil)
    }

    @Test("Plaid passthrough does not change the budget precedence (invariant)")
    func plaidPassthroughDoesNotChangeBudgetCategory() {
        // A nil-category, NL-recognizable transaction: the budget category must stay
        // nil (NL is display-only) regardless of the new passthrough fields.
        let transaction = tx(id: "inv", name: "BLUE BOTTLE COFFEE", category: nil, merchantName: nil)

        let resolution = EffectiveCategoryResolver.resolve(transaction: transaction)

        #expect(resolution.category == nil)
        #expect(resolution.source == nil)
        #expect(resolution.suggestedCategory == .foodAndDrink)
        #expect(resolution.plaidCategory == nil)
        #expect(resolution.isOverridingPlaid == false)
    }

    private func tx(
        id: String,
        amount: Double = 12,
        date: String = "2026-06-01",
        name: String = "MERCHANT",
        category: SpendingCategory?,
        merchantName: String? = "Merchant",
        lowConfidence: Bool = false
    ) -> TransactionDTO {
        TransactionDTO(
            id: id,
            accountId: "test-account",
            amount: amount,
            date: date,
            name: name,
            merchantName: merchantName,
            category: category,
            pending: false,
            isLowConfidenceCategory: lowConfidence
        )
    }
}
