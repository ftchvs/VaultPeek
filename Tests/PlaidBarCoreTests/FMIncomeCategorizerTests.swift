import Foundation
@testable import PlaidBarCore
import Testing

/// Priority #5: the on-device Foundation Models *income* categorization tier and
/// its constrained string→enum mapper. The live FM call is injected (a
/// deterministic stub) so these run on any OS without Apple Intelligence.
@Suite("FM Income Categorizer Tests")
struct FMIncomeCategorizerTests {
    /// Deterministic income FM stub that returns a fixed constrained string (or nil
    /// = a miss), recording every context it was asked about for privacy assertions.
    final class StubIncomeCategorizer: FMIncomeCategorizing, Sendable {
        actor Recorder {
            private var seen: [CategorySuggestionContext] = []
            func append(_ context: CategorySuggestionContext) { seen.append(context) }
            func snapshot() -> [CategorySuggestionContext] { seen }
        }

        let fixedRaw: String?
        private let recorder = Recorder()

        init(returning category: IncomeCategory?) { fixedRaw = category?.rawValue }
        init(returningRaw raw: String?) { fixedRaw = raw }

        func seenContexts() async -> [CategorySuggestionContext] { await recorder.snapshot() }

        func suggestIncomeCategory(context: CategorySuggestionContext) async -> String? {
            await recorder.append(context)
            return fixedRaw
        }
    }

    private func income(
        id: String = "inc-1",
        amount: Double = -2_500,
        name: String,
        merchantName: String? = nil,
        category: SpendingCategory? = .income
    ) -> TransactionDTO {
        TransactionDTO(
            id: id,
            accountId: "acct-1",
            amount: amount,
            date: "2026-06-19",
            name: name,
            merchantName: merchantName,
            category: category
        )
    }

    private func context(for transaction: TransactionDTO, isRecurring: Bool = false) -> CategorySuggestionContext {
        CategorySuggestionContext.make(for: transaction, isRecurring: isRecurring)
    }

    // MARK: - Mapper

    @Test("Every IncomeCategory raw value round-trips through the mapper")
    func mapperRoundTrips() {
        for category in IncomeCategory.allCases {
            #expect(FMIncomeCategoryMapper.category(from: category.rawValue) == category)
            #expect(FMIncomeCategoryMapper.category(from: category.displayName) == category)
        }
    }

    @Test("Mapper tolerates case/whitespace noise and rejects garbage")
    func mapperNoise() {
        #expect(FMIncomeCategoryMapper.category(from: "  salary  ") == .salary)
        #expect(FMIncomeCategoryMapper.category(from: "GOVERNMENT") == .government)
        #expect(FMIncomeCategoryMapper.category(from: "") == nil)
        #expect(FMIncomeCategoryMapper.category(from: "NOT_A_REAL_SUBTYPE") == nil)
    }

    // MARK: - FM available

    @Test("When FM is available, the FM income suggestion is preferred over the heuristic")
    func fmAvailablePrefersFM() async {
        // A payroll name would heuristically be salary; force FM to dividend to prove FM won.
        let stub = StubIncomeCategorizer(returning: .dividend)
        let categorizer = FMMerchantCategorizer(foundationModelsState: .available)
        let txn = income(name: "ACME PAYROLL DEP")

        let suggestion = await categorizer.suggestIncome(for: txn, context: context(for: txn), incomeCategorizer: stub)
        #expect(suggestion?.category == .dividend)
        #expect(suggestion?.tier == .foundationModels)
        #expect(suggestion?.resolutionSource == .appleFoundationModels)
        #expect(suggestion?.isTrusted == true)
    }

    @Test("FM income receives only an identifier-free context")
    func fmReceivesOnlySafeContext() async {
        let stub = StubIncomeCategorizer(returning: .salary)
        let categorizer = FMMerchantCategorizer(foundationModelsState: .available)
        let txn = income(id: "inc-secret-id-999", name: "ACME PAYROLL", merchantName: "Acme Co")

        _ = await categorizer.suggestIncome(for: txn, context: context(for: txn), incomeCategorizer: stub)

        let seen = await stub.seenContexts()
        #expect(seen.count == 1)
        #expect(seen.first?.merchant == "Acme Co")
        for ctx in seen {
            #expect(!ctx.merchant.contains("inc-secret-id-999"))
            #expect(!ctx.merchant.contains("acct-1"))
        }
    }

    @Test("An unparseable FM string degrades to the heuristic, never a wrong guess")
    func fmUnparseableFallsBackToHeuristic() async {
        let stub = StubIncomeCategorizer(returningRaw: "NOT_A_SUBTYPE")
        let categorizer = FMMerchantCategorizer(foundationModelsState: .available)
        let txn = income(name: "ACME PAYROLL DEP")

        let suggestion = await categorizer.suggestIncome(for: txn, context: context(for: txn), incomeCategorizer: stub)
        let heuristic = FMMerchantCategorizer.heuristicIncomeSuggestion(for: txn, isRecurring: false)
        #expect(suggestion == heuristic)
        #expect(suggestion?.category == .salary)
        #expect(suggestion?.tier == .naturalLanguage)
    }

    // MARK: - FM unavailable (regression guard)

    @Test("FM unavailable reproduces the deterministic heuristic income suggestion")
    func fmUnavailableUsesHeuristic() async {
        let unavailable: [LocalAIFoundationModelsTierState] = [
            .unsupported, .deviceNotEligible, .appleIntelligenceNotEnabled, .modelNotReady, .unavailableOther,
        ]
        // A polluting stub: if it were ever consulted it would change the answer.
        let pollutingStub = StubIncomeCategorizer(returning: .dividend)

        for state in unavailable {
            let categorizer = FMMerchantCategorizer(foundationModelsState: state)
            let txn = income(name: "ACME PAYROLL DEP")
            let suggestion = await categorizer.suggestIncome(
                for: txn,
                context: context(for: txn),
                incomeCategorizer: pollutingStub
            )
            #expect(suggestion?.category == .salary)
            #expect(suggestion?.tier == .naturalLanguage)
        }
        // The FM income stub must never have been consulted while unavailable.
        #expect(await pollutingStub.seenContexts().isEmpty)
    }

    @Test("No wired income categorizer falls back to the heuristic floor")
    func noWiredCategorizerUsesHeuristic() async {
        let categorizer = FMMerchantCategorizer(foundationModelsState: .available)
        let txn = income(name: "IRS TAX REFUND")
        let suggestion = await categorizer.suggestIncome(for: txn, context: context(for: txn))
        #expect(suggestion?.category == .government)
        #expect(suggestion?.tier == .naturalLanguage)
    }

    @Test("A spend transaction never produces an income suggestion")
    func spendNeverSuggested() async {
        let categorizer = FMMerchantCategorizer(foundationModelsState: .available)
        let spend = income(amount: 42, name: "STARBUCKS", category: .foodAndDrink)
        let suggestion = await categorizer.suggestIncome(for: spend, context: context(for: spend))
        #expect(suggestion == nil)
    }
}
