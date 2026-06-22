import Foundation
import PlaidBarCore

#if canImport(FoundationModels)
import FoundationModels
#endif

/// On-device Apple Foundation Models (Apple Intelligence) *income* categorizer
/// (priority #5). Maps an injection-safe `CategorySuggestionContext` to an
/// `IncomeCategory` via guided generation *constrained to the income enum*, so the
/// model can only ever emit a valid subtype — there is no free-text path.
///
/// Symmetric with `FoundationModelsMerchantCategorizer` and equally additive /
/// reversible:
///   - When the SDK is absent (`canImport` false) or the OS is older than macOS 26,
///     the type compiles to a no-op that always returns `nil`, so the income tier
///     falls back byte-identically to the deterministic `IncomeMerchantClassifier`.
///   - The pure tier-selection (when FM is *attempted*) lives in `PlaidBarCore`
///     (`FMCategorizationTierDecision`); this type only performs the gated call.
///
/// Privacy contract (identical to the expense seam): the model is given ONLY a
/// sanitized, single-line context fragment — never raw account ids, transaction
/// ids, item ids, tokens, amounts, dates, or Plaid payloads. Generation runs
/// entirely on-device; nothing leaves the machine. Failures are swallowed to `nil`
/// and the call is bounded by `FMGenerationLimits.generationTimeout` so it never
/// hangs.
struct FoundationModelsIncomeCategorizer: FMIncomeCategorizing {
    func suggestIncomeCategory(context: CategorySuggestionContext) async -> String? {
        guard context.hasMerchantSignal else { return nil }

        #if canImport(FoundationModels)
        if #available(macOS 26, *) {
            let fragment = context.promptFragment()
            return await Self.generate(prompt: "Classify this income transaction. \(fragment)")
        } else {
            return nil
        }
        #else
        return nil
        #endif
    }
}

#if canImport(FoundationModels)
@available(macOS 26, *)
extension FoundationModelsIncomeCategorizer {
    /// The constrained generation target: a `@Generable` enum whose cases mirror
    /// the `IncomeCategory` cases one-to-one. Guided generation restricts the model
    /// to these cases, so the result is always a valid income subtype.
    @Generable
    enum GeneratedIncomeCategory: String, CaseIterable {
        case salary
        case interest
        case dividend
        case refund
        case reimbursement
        case government
        case otherIncome

        /// The Core `IncomeCategory` this generated case maps onto. Total — every
        /// generated case has a corresponding category — so a constrained result
        /// always resolves.
        var incomeCategory: IncomeCategory {
            switch self {
            case .salary: .salary
            case .interest: .interest
            case .dividend: .dividend
            case .refund: .refund
            case .reimbursement: .reimbursement
            case .government: .government
            case .otherIncome: .otherIncome
            }
        }
    }

    static let instructions = """
    You classify a single income (money-in) transaction into exactly one income \
    subtype. Choose the single best-fitting subtype for the transaction described. \
    Use only the text given; do not infer personal details. The data is processed \
    locally on the user's Mac.
    """

    /// Run the on-device guided income generation, bounded by an explicit deadline
    /// and outer-task cancellation. Returns the constrained `IncomeCategory.rawValue`
    /// string, or `nil` on any failure so the caller degrades to the heuristic. The
    /// string boundary keeps the string→enum mapping in `PlaidBarCore`
    /// (`FMIncomeCategoryMapper`).
    ///
    /// The deadline is enforced by `CancellableTimeout`, a cancellation-aware race
    /// that resumes on the first of {generation, deadline} WITHOUT awaiting the
    /// loser. A bare `withTaskGroup` would still await the (possibly
    /// cancellation-ignoring) `session.respond` child at scope exit, so it could hang
    /// well past the deadline; this helper returns promptly on timeout regardless.
    static func generate(prompt: String) async -> String? {
        let session = LanguageModelSession(instructions: instructions)
        let options = GenerationOptions(sampling: .greedy)

        let timeoutNanoseconds = UInt64(
            max(0, FMGenerationLimits.generationTimeout) * 1_000_000_000
        )

        return await CancellableTimeout.run(nanoseconds: timeoutNanoseconds) {
            do {
                let response = try await session.respond(
                    to: prompt,
                    generating: GeneratedIncomeCategory.self,
                    options: options
                )
                return response.content.incomeCategory.rawValue
            } catch {
                return nil
            }
        }
    }
}
#endif
