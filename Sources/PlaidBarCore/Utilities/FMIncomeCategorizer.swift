import Foundation

/// A single income-subtype *suggestion* with its provenance and trust band
/// (priority #5).
///
/// The income analogue of `MerchantCategorySuggestion`. Critically this is a
/// SUGGESTION, never a persisted/applied subtype: it follows the exact display-only
/// contract the expense tiers use — it never re-writes the raw Plaid category, never
/// becomes budget spend (income is not spend), and must flow through the
/// review/confirm flow before it sticks.
public struct IncomeCategorySuggestion: Sendable, Equatable, Hashable {
    public let category: IncomeCategory
    public let tier: MerchantCategorySuggestionTier
    /// Whether the suggestion is trusted enough to fill a display subtype. The
    /// heuristic tier carries its high/medium/low band; the FM tier is treated as
    /// trusted (a constrained-enum result is always a valid case) but is still only
    /// ever a suggestion.
    public let isTrusted: Bool

    public init(category: IncomeCategory, tier: MerchantCategorySuggestionTier, isTrusted: Bool) {
        self.category = category
        self.tier = tier
        self.isTrusted = isTrusted
    }

    /// The provenance source for the existing display badge.
    public var resolutionSource: LocalAICategoryResolutionSource {
        tier.resolutionSource
    }
}

/// Maps the *constrained* string output of an income guided generation back onto
/// the `IncomeCategory` enum (priority #5).
///
/// Symmetric with `FMSpendingCategoryMapper`: the live FM seam constrains income
/// generation to `IncomeCategory.allCases`, but the value crosses the app→Core
/// boundary as a plain `String` so Core stays free of any FoundationModels
/// dependency. This is the single, unit-tested place that string is resolved. It
/// accepts the raw enum value (`"SALARY"`) or the human display name (`"Salary"`),
/// case- and whitespace-insensitively, and returns `nil` for anything it cannot
/// resolve — so a malformed value degrades to the heuristic floor, not a wrong
/// guess.
public enum FMIncomeCategoryMapper {
    public static func category(from rawOutput: String) -> IncomeCategory? {
        let trimmed = rawOutput.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }

        if let exact = IncomeCategory(rawValue: trimmed) {
            return exact
        }
        let upper = trimmed.uppercased()
        if let caseInsensitive = IncomeCategory.allCases.first(where: { $0.rawValue == upper }) {
            return caseInsensitive
        }
        let lowered = trimmed.lowercased()
        if let byDisplay = IncomeCategory.allCases.first(where: { $0.displayName.lowercased() == lowered }) {
            return byDisplay
        }
        return nil
    }
}

/// The on-device Foundation Models income-categorization seam (priority #5).
///
/// The concrete implementation lives in the app target, where the FoundationModels
/// framework is available and gated behind `#available(macOS 26, *)` +
/// `#if canImport(FoundationModels)`. PlaidBarCore stays free of any model
/// dependency so it remains pure and testable; tests inject a deterministic stub.
///
/// Privacy contract (identical to the expense seam): the implementation runs
/// entirely on-device and is given ONLY an injection-safe, identifier-free
/// `CategorySuggestionContext` — never raw account ids, transaction ids, item ids,
/// tokens, amounts, or Plaid payloads.
public protocol FMIncomeCategorizing: Sendable {
    /// Suggest an income subtype for an injection-safe context using guided
    /// generation constrained to the `IncomeCategory` cases.
    ///
    /// The result crosses the app→Core boundary as the *constrained string* (the
    /// `IncomeCategory.rawValue`), not a resolved enum, so Core stays free of any
    /// FoundationModels dependency and `FMIncomeCategoryMapper` remains the single
    /// place that string is turned back into a category. Returns `nil` when the
    /// model produced no usable result (so the caller falls back to the heuristic).
    /// Must never throw across the boundary — failures degrade to `nil`.
    func suggestIncomeCategory(context: CategorySuggestionContext) async -> String?
}

public extension FMMerchantCategorizer {
    /// Suggest an income subtype for a transaction, preferring an on-device
    /// Foundation Models suggestion when Apple Intelligence is available, otherwise
    /// falling back to the deterministic `IncomeMerchantClassifier` heuristic floor
    /// (priority #5).
    ///
    /// Mirrors `suggest(for:context:)`: FM is attempted only when its probe reports
    /// `.available`, an income categorizer is wired, and there is a merchant signal;
    /// the constrained string is resolved through `FMIncomeCategoryMapper`. On FM
    /// unavailable / unwired / miss / no signal, it degrades to the heuristic tier,
    /// which is fully deterministic and runs on every device. The result is always a
    /// SUGGESTION (with provenance) — never auto-applied, never budget spend.
    ///
    /// `incomeCategorizer` is the injected FM seam (defaults to `nil` so the
    /// heuristic-only path needs no FM wiring); `classifier` is the deterministic
    /// floor (injectable for tests).
    func suggestIncome(
        for transaction: TransactionDTO,
        context: CategorySuggestionContext,
        incomeCategorizer: (any FMIncomeCategorizing)? = nil,
        classifier: IncomeMerchantClassifier = IncomeMerchantClassifier()
    ) async -> IncomeCategorySuggestion? {
        guard transaction.isIncome else { return nil }

        if FMCategorizationTierDecision.shouldAttemptFoundationModels(foundationModels: probedFoundationModelsState),
           let incomeCategorizer,
           context.hasMerchantSignal {
            if let rawCategory = await incomeCategorizer.suggestIncomeCategory(context: context),
               let category = FMIncomeCategoryMapper.category(from: rawCategory) {
                return IncomeCategorySuggestion(category: category, tier: .foundationModels, isTrusted: true)
            }
        }

        return Self.heuristicIncomeSuggestion(
            for: transaction,
            isRecurring: context.isRecurring,
            classifier: classifier
        )
    }

    /// The deterministic heuristic income suggestion (no FM), expressed in the
    /// unified suggestion shape. Exposed so the no-FM path is trivially
    /// regression-testable.
    static func heuristicIncomeSuggestion(
        for transaction: TransactionDTO,
        isRecurring: Bool,
        classifier: IncomeMerchantClassifier = IncomeMerchantClassifier()
    ) -> IncomeCategorySuggestion? {
        guard let inference = classifier.infer(for: transaction, isRecurring: isRecurring) else { return nil }
        return IncomeCategorySuggestion(
            category: inference.category,
            // The deterministic floor surfaces under the same NL "Suggested" badge.
            tier: .naturalLanguage,
            isTrusted: inference.isTrusted
        )
    }
}
