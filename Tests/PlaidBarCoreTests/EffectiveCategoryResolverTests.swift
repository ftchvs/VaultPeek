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

    @Test("A nil-category transaction with a resolvable name carries the NL suggestion")
    func nlBackfillsResolvableMissingCategory() {
        let transaction = tx(id: "nl", name: "BLUE BOTTLE COFFEE", category: nil, merchantName: nil)

        let resolution = EffectiveCategoryResolver.resolve(transaction: transaction)

        #expect(resolution.category == .foodAndDrink)
        #expect(resolution.source == .appleNaturalLanguage)
    }

    @Test("A low-confidence Plaid category gets a trusted NL suggestion")
    func nlBackfillsLowConfidencePlaidCategory() {
        let transaction = tx(
            id: "nl-low",
            name: "NETFLIX.COM",
            category: .other,
            merchantName: nil,
            lowConfidence: true
        )

        let resolution = EffectiveCategoryResolver.resolve(transaction: transaction)

        #expect(resolution.category == .entertainment)
        #expect(resolution.source == .appleNaturalLanguage)
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

    @Test("Metadata exclusion=false is respected even for a transfer")
    func metadataNotExcludedBeatsTransferDefault() {
        // The user explicitly chose to keep a transfer-categorized row in budgets.
        let transaction = tx(id: "keep", category: .transfer)
        let metadata = TransactionReviewMetadata(
            id: "keep",
            isTransferOverride: false,
            excludedFromBudgets: false
        )

        let resolution = EffectiveCategoryResolver.resolve(transaction: transaction, metadata: metadata)

        #expect(resolution.excludedFromBudgets == false)
    }

    // MARK: - Parity with TransactionReviewInbox

    @Test("Resolver category matches the inbox's effective category across mixed inputs")
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
            #expect(resolution.category == item.effectiveCategory)
            #expect(resolution.source == item.categorySource)
        }
    }

    // MARK: - Helpers

    private let now = Date(timeIntervalSince1970: 1_800_000_000)

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
