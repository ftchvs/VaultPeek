import Foundation
@testable import PlaidBarCore
import Testing

@Suite("Inline Category Rule Prompt Tests")
struct InlineCategoryRulePromptTests {
    // MARK: buildRule

    @Test("Built rule matches the merchant and carries the assigned category")
    func buildRuleMatchesMerchantAndCategory() {
        let prompt = InlineCategoryRulePrompt(
            transactionID: "tx1",
            merchantName: "Blue Bottle Coffee",
            category: .foodAndDrink
        )

        let rule = prompt.buildRule()

        #expect(rule?.matchMerchantContains == "Blue Bottle Coffee")
        #expect(rule?.category == .foodAndDrink)
        // A category rule never silently sets transfer/exclusion flags.
        #expect(rule?.isTransfer == nil)
        #expect(rule?.excludedFromBudgets == nil)
    }

    @Test("Built rule actually matches a transaction from that merchant")
    func builtRuleMatchesTransaction() {
        let prompt = InlineCategoryRulePrompt(
            transactionID: "tx1",
            merchantName: "Blue Bottle",
            category: .foodAndDrink
        )
        let rule = prompt.buildRule()

        let transaction = TransactionDTO(
            id: "tx1",
            accountId: "acc1",
            amount: 6.50,
            date: "2026-06-18",
            name: "SQ *BLUE BOTTLE 0421",
            merchantName: "Blue Bottle",
            category: nil,
            pending: false
        )

        #expect(rule?.matches(transaction) == true)
    }

    @Test("Merchant token is trimmed of surrounding whitespace")
    func ruleMatcherTrimsWhitespace() {
        let prompt = InlineCategoryRulePrompt(
            transactionID: "tx1",
            merchantName: "  Trader Joe's  ",
            category: .shopping
        )

        #expect(prompt.ruleMatcher == "Trader Joe's")
        #expect(prompt.buildRule()?.matchMerchantContains == "Trader Joe's")
    }

    @Test("Blank merchant yields no rule")
    func blankMerchantBuildsNoRule() {
        let prompt = InlineCategoryRulePrompt(
            transactionID: "tx1",
            merchantName: "   ",
            category: .shopping
        )

        #expect(prompt.buildRule() == nil)
    }

    // MARK: dedupe / make

    @Test("make returns a prompt when no matching rule exists")
    func makeReturnsPromptWhenNoExistingRule() {
        let prompt = InlineCategoryRulePrompt.make(
            transactionID: "tx1",
            merchantName: "Netflix",
            category: .subscriptions,
            existingRules: []
        )

        #expect(prompt != nil)
        #expect(prompt?.merchantName == "Netflix")
        #expect(prompt?.category == .subscriptions)
    }

    @Test("make suppresses the prompt when an identical rule already exists")
    func makeDedupesIdenticalRule() {
        let existing = TransactionRule(
            matchMerchantContains: "Netflix",
            category: .subscriptions
        )

        let prompt = InlineCategoryRulePrompt.make(
            transactionID: "tx1",
            merchantName: "Netflix",
            category: .subscriptions,
            existingRules: [existing]
        )

        #expect(prompt == nil)
    }

    @Test("Dedupe is case-insensitive on the merchant token")
    func dedupeIsCaseInsensitive() {
        let existing = TransactionRule(
            matchMerchantContains: "netflix",
            category: .subscriptions
        )

        #expect(InlineCategoryRulePrompt.make(
            transactionID: "tx1",
            merchantName: "Netflix",
            category: .subscriptions,
            existingRules: [existing]
        ) == nil)
    }

    @Test("Same merchant but a different category still offers a prompt")
    func differentCategoryStillPrompts() {
        let existing = TransactionRule(
            matchMerchantContains: "Amazon",
            category: .shopping
        )

        let prompt = InlineCategoryRulePrompt.make(
            transactionID: "tx1",
            merchantName: "Amazon",
            category: .entertainment,
            existingRules: [existing]
        )

        // The existing rule targets a different category, so a new offer is not a
        // duplicate — the user may genuinely want to recategorize.
        #expect(prompt != nil)
        #expect(prompt?.category == .entertainment)
    }

    @Test("A transfer-only rule for the merchant does not suppress a category prompt")
    func transferRuleDoesNotDedupeCategoryPrompt() {
        let existing = TransactionRule(
            matchMerchantContains: "Venmo",
            category: nil,
            isTransfer: true
        )

        let prompt = InlineCategoryRulePrompt.make(
            transactionID: "tx1",
            merchantName: "Venmo",
            category: .other,
            existingRules: [existing]
        )

        // The existing rule carries no category, so it does not cover this
        // category assignment.
        #expect(prompt != nil)
    }

    @Test("make returns nil for a blank merchant")
    func makeReturnsNilForBlankMerchant() {
        #expect(InlineCategoryRulePrompt.make(
            transactionID: "tx1",
            merchantName: "",
            category: .shopping,
            existingRules: []
        ) == nil)
    }

    @Test("isAlreadyCovered is false for a blank merchant")
    func isAlreadyCoveredFalseForBlankMerchant() {
        let prompt = InlineCategoryRulePrompt(
            transactionID: "tx1",
            merchantName: "  ",
            category: .shopping
        )
        let existing = TransactionRule(matchMerchantContains: "", category: .shopping)

        #expect(prompt.isAlreadyCovered(by: [existing]) == false)
    }

    @Test("Prompt identity is the transaction id so a newer correction replaces an older")
    func identityIsTransactionID() {
        let prompt = InlineCategoryRulePrompt(
            transactionID: "tx-42",
            merchantName: "Spotify",
            category: .subscriptions
        )

        #expect(prompt.id == "tx-42")
    }
}
