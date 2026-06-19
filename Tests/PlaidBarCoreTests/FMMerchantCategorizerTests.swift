import Foundation
@testable import PlaidBarCore
import Testing

/// AND-565: the Foundation Models guided-generation categorization tier that
/// slots ABOVE NaturalLanguage in the suggestion order.
///
/// The live FM call is injected (a deterministic stub here) so these tests run
/// on any OS without Apple Intelligence. The two contracts under test:
///   1. When FM is `.available`, an FM suggestion is preferred over NL.
///   2. When FM is NOT available (any non-`.available` state), behavior is
///      byte-identical to the pre-FM NaturalLanguage/heuristic path — the
///      regression guard for the reversible, availability-gated design.
@Suite("FM Merchant Categorizer Tests")
struct FMMerchantCategorizerTests {
    // A deterministic FM stub that returns a fixed category (or nil = a miss),
    // and records every merchant string it was asked about so privacy/redaction
    // can be asserted.
    final class StubFMCategorizer: FMMerchantCategorizing, @unchecked Sendable {
        let fixedCategory: SpendingCategory?
        private let lock = NSLock()
        private var _seenMerchants: [String] = []

        init(returning category: SpendingCategory?) {
            fixedCategory = category
        }

        var seenMerchants: [String] {
            lock.lock(); defer { lock.unlock() }
            return _seenMerchants
        }

        func suggestCategory(merchant: String) async -> SpendingCategory? {
            lock.lock()
            _seenMerchants.append(merchant)
            lock.unlock()
            return fixedCategory
        }
    }

    private func transaction(
        id: String = "txn-1",
        name: String,
        merchantName: String? = nil,
        category: SpendingCategory? = nil,
        isLowConfidenceCategory: Bool = false
    ) -> TransactionDTO {
        TransactionDTO(
            id: id,
            accountId: "acct-1",
            amount: 12.34,
            date: "2026-06-19",
            name: name,
            merchantName: merchantName,
            category: category,
            isLowConfidenceCategory: isLowConfidenceCategory
        )
    }

    // MARK: - Tier decision (pure)

    @Test("FM is attempted only when its probe reports available")
    func fmAttemptedOnlyWhenAvailable() {
        #expect(FMCategorizationTierDecision.shouldAttemptFoundationModels(foundationModels: .available))
        for state: LocalAIFoundationModelsTierState in [
            .unsupported, .deviceNotEligible, .appleIntelligenceNotEnabled, .modelNotReady, .unavailableOther,
        ] {
            #expect(!FMCategorizationTierDecision.shouldAttemptFoundationModels(foundationModels: state))
        }
    }

    // MARK: - FM available: FM suggestion preferred over NL

    @Test("When FM is available, the FM suggestion is preferred over NaturalLanguage")
    func fmAvailablePrefersFMSuggestion() async {
        // "Netflix" is a clean NL brand hit (entertainment). Force FM to a
        // *different* category so we can prove FM won.
        let stub = StubFMCategorizer(returning: .shopping)
        let categorizer = FMMerchantCategorizer(
            foundationModelsState: .available,
            fmCategorizer: stub
        )
        let txn = transaction(name: "NETFLIX.COM", merchantName: "Netflix")

        let suggestion = await categorizer.suggest(for: txn)
        #expect(suggestion?.category == .shopping)
        #expect(suggestion?.tier == .foundationModels)
        #expect(suggestion?.resolutionSource == .appleFoundationModels)
        #expect(suggestion?.isTrusted == true)
    }

    @Test("An FM result maps to a valid SpendingCategory carried through the suggestion")
    func fmResultMapsToValidCategory() async {
        for category in SpendingCategory.allCases {
            let stub = StubFMCategorizer(returning: category)
            let categorizer = FMMerchantCategorizer(foundationModelsState: .available, fmCategorizer: stub)
            let suggestion = await categorizer.suggest(for: transaction(name: "Some Merchant \(category.rawValue)"))
            #expect(suggestion?.category == category)
            #expect(suggestion?.tier == .foundationModels)
            // The carried category is always a real enum case.
            #expect(SpendingCategory.allCases.contains(suggestion!.category))
        }
    }

    @Test("FM only receives the redaction-safe merchant string, never identifiers")
    func fmReceivesOnlyMerchantString() async {
        let stub = StubFMCategorizer(returning: .foodAndDrink)
        let categorizer = FMMerchantCategorizer(foundationModelsState: .available, fmCategorizer: stub)
        let txn = transaction(
            id: "txn-secret-id-123",
            name: "BLUE BOTTLE COFFEE",
            merchantName: "Blue Bottle"
        )

        _ = await categorizer.suggest(for: txn)

        #expect(stub.seenMerchants == ["Blue Bottle"])
        // The transaction/account id must never have been handed to the model.
        for merchant in stub.seenMerchants {
            #expect(!merchant.contains("txn-secret-id-123"))
            #expect(!merchant.contains("acct-1"))
        }
    }

    @Test("FM falls back to the raw name when no cleaned merchant name exists")
    func fmFallsBackToRawNameForMerchantString() async {
        let stub = StubFMCategorizer(returning: .transportation)
        let categorizer = FMMerchantCategorizer(foundationModelsState: .available, fmCategorizer: stub)
        let txn = transaction(name: "UBER TRIP", merchantName: nil)

        _ = await categorizer.suggest(for: txn)
        #expect(stub.seenMerchants == ["UBER TRIP"])
    }

    @Test("On an FM miss, the categorizer falls back to the NaturalLanguage tier")
    func fmMissFallsBackToNL() async {
        // FM available but returns nil (a miss). NL should produce the suggestion.
        let stub = StubFMCategorizer(returning: nil)
        let categorizer = FMMerchantCategorizer(foundationModelsState: .available, fmCategorizer: stub)
        let txn = transaction(name: "NETFLIX.COM", merchantName: "Netflix")

        let suggestion = await categorizer.suggest(for: txn)
        let nlOnly = categorizer.nlSuggestion(for: txn)
        #expect(suggestion == nlOnly)
        #expect(suggestion?.tier == .naturalLanguage)
    }

    @Test("FM available but no categorizer wired reproduces the NL path")
    func fmAvailableButUnwiredUsesNL() async {
        let categorizer = FMMerchantCategorizer(foundationModelsState: .available, fmCategorizer: nil)
        let txn = transaction(name: "NETFLIX.COM", merchantName: "Netflix")

        let suggestion = await categorizer.suggest(for: txn)
        #expect(suggestion == categorizer.nlSuggestion(for: txn))
        #expect(suggestion?.tier == .naturalLanguage)
    }

    // MARK: - Regression guard: FM unavailable == today's NL/heuristic path

    @Test("FM unavailable for any reason reproduces the exact NaturalLanguage suggestion")
    func fmUnavailableReproducesNLPath() async {
        let unavailableStates: [LocalAIFoundationModelsTierState] = [
            .unsupported, .deviceNotEligible, .appleIntelligenceNotEnabled, .modelNotReady, .unavailableOther,
        ]
        // A stub that, if it were ever consulted, would change the answer — so a
        // wrongly-engaged FM tier would fail this test loudly.
        let pollutingStub = StubFMCategorizer(returning: .government)

        let cases: [(name: String, merchant: String?)] = [
            ("NETFLIX.COM", "Netflix"),         // clean NL brand hit
            ("STARBUCKS STORE 123", "Starbucks"), // brand hit
            ("ZZQ UNKNOWN VENDOR 9", nil),       // NL miss (nil)
        ]

        for state in unavailableStates {
            for testCase in cases {
                let txn = transaction(name: testCase.name, merchantName: testCase.merchant)
                let categorizer = FMMerchantCategorizer(
                    foundationModelsState: state,
                    fmCategorizer: pollutingStub
                )
                // Baseline: the pure NL tier via the bare NLMerchantCategorizer.
                let nlBaseline = NLMerchantCategorizer().infer(for: txn)
                let suggestion = await categorizer.suggest(for: txn)

                #expect(suggestion?.category == nlBaseline?.category)
                #expect(suggestion?.isTrusted == nlBaseline?.isTrusted)
                if nlBaseline == nil {
                    #expect(suggestion == nil)
                } else {
                    #expect(suggestion?.tier == .naturalLanguage)
                    #expect(suggestion?.resolutionSource == .appleNaturalLanguage)
                }
            }
        }
        // The FM stub must never have been consulted in any unavailable state.
        #expect(pollutingStub.seenMerchants.isEmpty)
    }

    @Test("Default initializer (no FM, no wired categorizer) is the pure NL path")
    func defaultInitIsNLPath() async {
        let categorizer = FMMerchantCategorizer()
        let txn = transaction(name: "NETFLIX.COM", merchantName: "Netflix")
        let suggestion = await categorizer.suggest(for: txn)
        let nlBaseline = NLMerchantCategorizer().infer(for: txn)
        #expect(suggestion?.category == nlBaseline?.category)
        #expect(suggestion?.tier == .naturalLanguage)
    }

    // MARK: - Never auto-applies / EffectiveCategoryResolver untouched

    @Test("A suggestion never becomes a persisted budget category on its own")
    func suggestionNeverAutoApplies() async {
        // Even with FM available and returning a confident category, the budget
        // resolution path (EffectiveCategoryResolver) — which knows nothing about
        // this tier — must still treat the row as uncategorized when there is no
        // user override / rule / confident Plaid category. The suggestion is
        // display-only.
        let stub = StubFMCategorizer(returning: .foodAndDrink)
        let categorizer = FMMerchantCategorizer(foundationModelsState: .available, fmCategorizer: stub)
        let txn = transaction(name: "BLUE BOTTLE COFFEE", merchantName: "Blue Bottle", category: nil)

        let suggestion = await categorizer.suggest(for: txn)
        #expect(suggestion?.category == .foodAndDrink)

        // The persisted resolver is unaffected: no user category → budget category nil.
        let resolution = EffectiveCategoryResolver.resolve(transaction: txn, metadata: nil, rules: [])
        #expect(resolution.category == nil)
        #expect(resolution.source == nil)
    }
}

/// AND-565: the pure constrained-output → SpendingCategory mapper. The live FM
/// seam constrains generation to the 16 cases, but the value crosses the
/// app→Core boundary as a String; this is the single place it is mapped back.
@Suite("FM Spending Category Mapper Tests")
struct FMSpendingCategoryMapperTests {
    @Test("Every raw enum value round-trips through the mapper")
    func rawValuesRoundTrip() {
        for category in SpendingCategory.allCases {
            #expect(FMSpendingCategoryMapper.category(from: category.rawValue) == category)
        }
    }

    @Test("Every display name maps back to its category (case-insensitive)")
    func displayNamesMap() {
        for category in SpendingCategory.allCases {
            #expect(FMSpendingCategoryMapper.category(from: category.displayName) == category)
            #expect(FMSpendingCategoryMapper.category(from: category.displayName.lowercased()) == category)
        }
    }

    @Test("Whitespace and case noise are tolerated")
    func toleratesNoise() {
        #expect(FMSpendingCategoryMapper.category(from: "  food_and_drink  ") == .foodAndDrink)
        #expect(FMSpendingCategoryMapper.category(from: "Transportation") == .transportation)
        #expect(FMSpendingCategoryMapper.category(from: "GENERAL_MERCHANDISE") == .shopping)
    }

    @Test("Unknown / malformed output returns nil so the caller falls back")
    func unknownReturnsNil() {
        #expect(FMSpendingCategoryMapper.category(from: "") == nil)
        #expect(FMSpendingCategoryMapper.category(from: "   ") == nil)
        #expect(FMSpendingCategoryMapper.category(from: "NOT_A_CATEGORY") == nil)
        #expect(FMSpendingCategoryMapper.category(from: "I think this is food and drink") == nil)
    }

    @Test("Suggestion tier maps to the expected display provenance")
    func tierProvenanceMapping() {
        #expect(MerchantCategorySuggestionTier.foundationModels.resolutionSource == .appleFoundationModels)
        #expect(MerchantCategorySuggestionTier.naturalLanguage.resolutionSource == .appleNaturalLanguage)
        // Both FM and NL surface under the existing "Suggested" badge.
        #expect(LocalAICategoryResolutionSource.appleFoundationModels.displayName == "Suggested")
    }
}
