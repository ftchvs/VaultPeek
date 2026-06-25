import Foundation
@testable import PlaidBarCore
import Testing

@Suite("Transaction Rule Manager Tests")
struct TransactionRuleManagerTests {
    // Fixed reference date so createdAt ordering is deterministic.
    private let base = Date(timeIntervalSince1970: 1_700_000_000)

    private func rule(
        id: String,
        merchant: String? = nil,
        original: String? = nil,
        category: SpendingCategory? = nil,
        rename: String? = nil,
        isTransfer: Bool? = nil,
        excluded: Bool? = nil,
        createdOffsetDays: Int = 0
    ) -> TransactionRule {
        TransactionRule(
            id: UUID(uuidString: id)!,
            matchMerchantContains: merchant,
            matchOriginalNameContains: original,
            category: category,
            merchantName: rename,
            isTransfer: isTransfer,
            excludedFromBudgets: excluded,
            createdAt: base.addingTimeInterval(Double(createdOffsetDays) * 86_400)
        )
    }

    private func transaction(name: String, merchant: String?, category: SpendingCategory? = nil) -> TransactionDTO {
        TransactionDTO(
            id: "tx-\(name)",
            accountId: "acc1",
            amount: 12.34,
            date: "2026-06-20",
            name: name,
            merchantName: merchant,
            category: category,
            pending: false
        )
    }

    // MARK: - Sort / display order (AC #1)

    @Test("Display order is newest createdAt first, with id tiebreaker")
    func sortedNewestFirst() {
        let older = rule(id: "00000000-0000-0000-0000-000000000001", merchant: "A", category: .shopping, createdOffsetDays: 0)
        let newer = rule(id: "00000000-0000-0000-0000-000000000002", merchant: "B", category: .shopping, createdOffsetDays: 5)
        let sorted = TransactionRuleManager.sortedForDisplay([older, newer])
        #expect(sorted.map(\.id) == [newer.id, older.id])
    }

    @Test("Equal timestamps break ties deterministically by id descending")
    func tiebreakById() {
        let a = rule(id: "00000000-0000-0000-0000-00000000000A", merchant: "A", category: .shopping)
        let b = rule(id: "00000000-0000-0000-0000-00000000000B", merchant: "B", category: .shopping)
        let sorted = TransactionRuleManager.sortedForDisplay([a, b])
        // "...B" > "...A" so B is first.
        #expect(sorted.first?.id == b.id)
    }

    // MARK: - Effects + match copy (AC #1)

    @Test("Effects list reflects every set field in stable order")
    func effectsListed() {
        let r = rule(
            id: "00000000-0000-0000-0000-000000000010",
            merchant: "Venmo",
            category: .transfer,
            rename: "Venmo Cashout",
            isTransfer: true,
            excluded: true
        )
        let effects = TransactionRuleManager.effects(of: r)
        #expect(effects == [
            .category(.transfer),
            .merchant("Venmo Cashout"),
            .transfer(true),
            .excludeFromBudgets(true),
        ])
        #expect(effects[0].label == "Categorize as Transfer In")
        #expect(effects[3].label == "Exclude from budgets")
    }

    @Test("A rule with no effect yields an empty effects list")
    func noEffect() {
        let r = rule(id: "00000000-0000-0000-0000-000000000011", merchant: "Ghost")
        #expect(TransactionRuleManager.effects(of: r).isEmpty)
    }

    @Test("Match description covers merchant and original-name as an OR clause")
    func matchDescriptionOr() {
        let r = rule(id: "00000000-0000-0000-0000-000000000012", merchant: "Amazon", original: "AMZN")
        let copy = TransactionRuleManager.matchDescription(of: r)
        #expect(copy.contains("merchant contains"))
        #expect(copy.contains("description contains"))
        #expect(copy.contains(" or "))
    }

    @Test("Match description of a matcherless rule is non-empty")
    func matchDescriptionEmpty() {
        let r = rule(id: "00000000-0000-0000-0000-000000000013", category: .shopping)
        #expect(!TransactionRuleManager.matchDescription(of: r).isEmpty)
    }

    // MARK: - Conflict / shadowing (AC #4)

    @Test("Newer overlapping rule shadows the older rule's category")
    func newerShadowsOlder() {
        let older = rule(id: "00000000-0000-0000-0000-000000000020", merchant: "Amazon", category: .shopping, createdOffsetDays: 0)
        let newer = rule(id: "00000000-0000-0000-0000-000000000021", merchant: "Amazon", category: .entertainment, createdOffsetDays: 3)
        let rows = TransactionRuleManager.rows(for: [older, newer])

        // Newest first.
        #expect(rows.first?.id == newer.id)
        // The winner is fully effective.
        #expect(rows.first?.isShadowed == false)
        // The older rule is shadowed on category by the newer one.
        let olderRow = rows.first { $0.id == older.id }
        #expect(olderRow?.isShadowed == true)
        #expect(olderRow?.shadowedFields.first?.field == .category)
        #expect(olderRow?.shadowedFields.first?.winningRuleID == newer.id)
        #expect(olderRow?.shadowedFields.first?.winningRuleLabel == "Amazon")
    }

    @Test("Non-overlapping rules never shadow each other")
    func noOverlapNoShadow() {
        let a = rule(id: "00000000-0000-0000-0000-000000000022", merchant: "Amazon", category: .shopping, createdOffsetDays: 0)
        let b = rule(id: "00000000-0000-0000-0000-000000000023", merchant: "Starbucks", category: .foodAndDrink, createdOffsetDays: 3)
        let rows = TransactionRuleManager.rows(for: [a, b])
        #expect(rows.allSatisfy { !$0.isShadowed })
    }

    @Test("Shadowing is per-field: distinct fields do not conflict")
    func perFieldShadowing() {
        // Older sets category; newer sets only transfer. They overlap on merchant
        // but touch different fields, so neither shadows the other.
        let older = rule(id: "00000000-0000-0000-0000-000000000024", merchant: "Venmo", category: .shopping, createdOffsetDays: 0)
        let newer = rule(id: "00000000-0000-0000-0000-000000000025", merchant: "Venmo", isTransfer: true, createdOffsetDays: 3)
        let rows = TransactionRuleManager.rows(for: [older, newer])
        #expect(rows.allSatisfy { !$0.isShadowed })
    }

    @Test("Token containment counts as overlap (Amazon vs Amazon Prime)")
    func tokenContainmentOverlap() {
        let broad = rule(id: "00000000-0000-0000-0000-000000000026", merchant: "Amazon", category: .shopping, createdOffsetDays: 3)
        let specific = rule(id: "00000000-0000-0000-0000-000000000027", merchant: "Amazon Prime", category: .entertainment, createdOffsetDays: 0)
        // broad is newer → it shadows the older specific rule on category.
        let rows = TransactionRuleManager.rows(for: [broad, specific])
        let specificRow = rows.first { $0.id == specific.id }
        #expect(specificRow?.isShadowed == true)
    }

    // MARK: - Provenance (AC #3)

    @Test("Provenance points each field at the most-recently-created matching rule")
    func provenanceWinner() {
        let older = rule(id: "00000000-0000-0000-0000-000000000030", merchant: "Amazon", category: .shopping, createdOffsetDays: 0)
        let newer = rule(id: "00000000-0000-0000-0000-000000000031", merchant: "Amazon", category: .entertainment, createdOffsetDays: 3)
        let tx = transaction(name: "AMAZON MKTPL", merchant: "Amazon")
        let prov = TransactionRuleManager.provenance(for: tx, in: [older, newer])
        #expect(prov.hasMatch)
        #expect(prov.matchingRules.first?.id == newer.id)
        #expect(prov.categoryRuleID == newer.id)
    }

    @Test("Provenance category matches EffectiveCategoryResolver's winning category")
    func provenanceMatchesResolver() {
        let older = rule(id: "00000000-0000-0000-0000-000000000032", merchant: "Amazon", category: .shopping, createdOffsetDays: 0)
        let newer = rule(id: "00000000-0000-0000-0000-000000000033", merchant: "Amazon", category: .entertainment, createdOffsetDays: 3)
        let tx = transaction(name: "AMAZON MKTPL", merchant: "Amazon")

        let prov = TransactionRuleManager.provenance(for: tx, in: [older, newer])
        let winningRule = prov.matchingRules.first { $0.id == prov.categoryRuleID }

        let resolution = EffectiveCategoryResolver.resolve(transaction: tx, metadata: nil, rules: [older, newer])
        // The rule the manager credits is the rule whose category the resolver applies.
        #expect(winningRule?.category == resolution.category)
        #expect(resolution.category == .entertainment)
    }

    @Test("Provenance has no match when no rule matches the transaction")
    func provenanceNoMatch() {
        let r = rule(id: "00000000-0000-0000-0000-000000000034", merchant: "Amazon", category: .shopping)
        let tx = transaction(name: "STARBUCKS 123", merchant: "Starbucks")
        let prov = TransactionRuleManager.provenance(for: tx, in: [r])
        #expect(!prov.hasMatch)
        #expect(prov.categoryRuleID == nil)
    }

    // MARK: - Validation (AC #2 editing)

    @Test("A rule with no matcher and no effect reports both problems")
    func validateEmpty() {
        let r = TransactionRule()
        let problems = TransactionRuleManager.validate(r)
        #expect(problems.contains(.noMatcher))
        #expect(problems.contains(.noEffect))
    }

    @Test("Whitespace-only matcher counts as no matcher")
    func validateWhitespaceMatcher() {
        let r = rule(id: "00000000-0000-0000-0000-000000000040", merchant: "   ", category: .shopping)
        let problems = TransactionRuleManager.validate(TransactionRuleManager.normalized(r))
        #expect(problems.contains(.noMatcher))
        #expect(!problems.contains(.noEffect))
    }

    @Test("A complete rule validates with no problems")
    func validateComplete() {
        let r = rule(id: "00000000-0000-0000-0000-000000000041", merchant: "Amazon", category: .shopping)
        #expect(TransactionRuleManager.validate(r).isEmpty)
    }

    // MARK: - Editing (AC #2)

    @Test("Editing a rule preserves its id and createdAt so precedence is stable")
    func editPreservesIdentity() {
        let original = rule(id: "00000000-0000-0000-0000-000000000050", merchant: "Amazon", category: .shopping, createdOffsetDays: 7)
        var edited = original
        edited = TransactionRule(
            id: original.id,
            matchMerchantContains: "Amazon",
            category: .entertainment,
            // A caller might naively pass a fresh createdAt; applyingEdit must ignore it.
            createdAt: base.addingTimeInterval(999_999)
        )
        let result = TransactionRuleManager.applyingEdit(edited, to: [original])
        #expect(result.count == 1)
        #expect(result[0].id == original.id)
        #expect(result[0].createdAt == original.createdAt)
        #expect(result[0].category == .entertainment)
    }

    @Test("Editing trims free-text fields")
    func editNormalizes() {
        let original = rule(id: "00000000-0000-0000-0000-000000000051", merchant: "Amazon", category: .shopping)
        let edited = TransactionRule(
            id: original.id,
            matchMerchantContains: "  Amazon Fresh  ",
            category: .shopping,
            merchantName: "  Groceries  "
        )
        let result = TransactionRuleManager.applyingEdit(edited, to: [original])
        #expect(result[0].matchMerchantContains == "Amazon Fresh")
        #expect(result[0].merchantName == "Groceries")
    }

    @Test("Editing an unknown id appends a new rule")
    func editAppendsNew() {
        let existing = rule(id: "00000000-0000-0000-0000-000000000052", merchant: "Amazon", category: .shopping)
        let fresh = rule(id: "00000000-0000-0000-0000-000000000053", merchant: "Costco", category: .shopping)
        let result = TransactionRuleManager.applyingEdit(fresh, to: [existing])
        #expect(result.count == 2)
        #expect(result.contains { $0.id == fresh.id })
    }

    // MARK: - Deletion (AC #2)

    @Test("Deleting removes only the targeted rule")
    func deleteRemovesOnlyTarget() {
        let a = rule(id: "00000000-0000-0000-0000-000000000060", merchant: "Amazon", category: .shopping)
        let b = rule(id: "00000000-0000-0000-0000-000000000061", merchant: "Costco", category: .shopping)
        let result = TransactionRuleManager.deleting(ruleID: a.id, from: [a, b])
        #expect(result.map(\.id) == [b.id])
    }

    @Test("Deleting an absent id is a no-op")
    func deleteAbsent() {
        let a = rule(id: "00000000-0000-0000-0000-000000000062", merchant: "Amazon", category: .shopping)
        let result = TransactionRuleManager.deleting(
            ruleID: UUID(uuidString: "00000000-0000-0000-0000-0000000000FF")!,
            from: [a]
        )
        #expect(result.count == 1)
    }
}
