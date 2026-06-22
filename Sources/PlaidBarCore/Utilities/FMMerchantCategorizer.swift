import Foundation

/// The provenance tier that produced a merchant-category *suggestion* (AND-565).
///
/// Mirrors the on-device AI generation order: Foundation Models (Apple
/// Intelligence) sits ABOVE NaturalLanguage, which sits above the heuristic
/// floor. This is the suggestion's source-of-truth provenance, carried so the
/// display layer can badge it the same way the Review Inbox already badges the
/// NL "Suggested" path.
public enum MerchantCategorySuggestionTier: String, Sendable, Equatable, Hashable, Codable {
    /// Apple Foundation Models guided generation, constrained to `SpendingCategory`.
    case foundationModels
    /// Apple NaturalLanguage lexicon/embedding inference (AND-507).
    case naturalLanguage

    /// The persisted resolution-source provenance this tier maps onto, so a
    /// suggestion can be surfaced through the existing `categorySource` badge
    /// path without inventing a parallel display vocabulary.
    public var resolutionSource: LocalAICategoryResolutionSource {
        switch self {
        case .foundationModels: .appleFoundationModels
        case .naturalLanguage: .appleNaturalLanguage
        }
    }
}

/// A single merchant-category *suggestion* with its provenance and trust band.
///
/// Critically this is a SUGGESTION, never a persisted/applied category: it is
/// the same display-only contract the NL tier already uses. `EffectiveCategory-
/// Resolver` remains the source of truth for persisted (`userCategory`) values;
/// an unapproved suggestion stays display-only and must flow through the
/// review/override flow before it can count as spend.
public struct MerchantCategorySuggestion: Sendable, Equatable, Hashable {
    public let category: SpendingCategory
    public let tier: MerchantCategorySuggestionTier
    /// Whether the suggestion is trusted enough to fill a display category. The
    /// NL tier carries its high/medium/low band here; the FM tier is treated as
    /// trusted (a constrained-enum result is always a valid case), but it is
    /// still only ever a suggestion.
    public let isTrusted: Bool

    public init(category: SpendingCategory, tier: MerchantCategorySuggestionTier, isTrusted: Bool) {
        self.category = category
        self.tier = tier
        self.isTrusted = isTrusted
    }

    /// The provenance source for the existing display badge.
    public var resolutionSource: LocalAICategoryResolutionSource {
        tier.resolutionSource
    }
}

/// Centralized limits for on-device Foundation Models generation (AND-564/565).
///
/// An on-device generation can block its `await` unbounded (model warm-up,
/// contention, a stuck guardrail), so the app-side FM seams race generation
/// against this deadline and return `nil` on timeout — degrading to the
/// deterministic NL/heuristic floor rather than hanging. Defined here in
/// `PlaidBarCore` (not the app target) so the value is shared, pure, and unit-
/// testable; the value is intentionally aligned with the insight runtime's 8s
/// generation timeout.
public enum FMGenerationLimits {
    /// Hard deadline (seconds) for a single on-device FM generation call.
    public static let generationTimeout: TimeInterval = 8
}

/// Pure decision: should the Foundation Models categorization step be *attempted*
/// for this run, given the probed FM tier state (AND-565)?
///
/// FM is attempted ONLY when its availability probe reports `.available`. For
/// every other state (older OS, no SDK, device ineligible, Apple Intelligence
/// off, model not ready, or any future reason) FM is skipped entirely and the
/// categorizer reproduces the exact NL/heuristic path that existed before this
/// tier — this equivalence is the regression guard the unit tests pin.
public enum FMCategorizationTierDecision {
    /// Whether the live FM categorization call should be attempted at all.
    public static func shouldAttemptFoundationModels(
        foundationModels state: LocalAIFoundationModelsTierState
    ) -> Bool {
        state.isAvailable
    }
}

/// Maps the *constrained* string output of a Foundation Models guided
/// generation back onto the 16-case `SpendingCategory` enum (AND-565).
///
/// The live FM seam constrains generation to `SpendingCategory.allCases` (so the
/// model can only ever emit one of the valid cases), but the value crosses the
/// app→Core boundary as a plain `String` to keep Core free of any FoundationModels
/// dependency. This mapper is the single, unit-tested place that string is turned
/// back into a `SpendingCategory`. It accepts either the raw enum value
/// (`"FOOD_AND_DRINK"`) or the human display name (`"Food & Drink"`), case- and
/// whitespace-insensitively, and returns `nil` for anything it cannot resolve —
/// so a malformed value degrades to the NL fallback rather than a wrong guess.
public enum FMSpendingCategoryMapper {
    public static func category(from rawOutput: String) -> SpendingCategory? {
        let trimmed = rawOutput.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }

        // 1. Exact raw-value match (the constrained generation's natural output).
        if let exact = SpendingCategory(rawValue: trimmed) {
            return exact
        }

        // 2. Case-insensitive raw-value match.
        let upper = trimmed.uppercased()
        if let caseInsensitive = SpendingCategory.allCases.first(where: { $0.rawValue == upper }) {
            return caseInsensitive
        }

        // 3. Display-name match (case-insensitive), e.g. "Food & Drink".
        let lowered = trimmed.lowercased()
        if let byDisplay = SpendingCategory.allCases.first(where: { $0.displayName.lowercased() == lowered }) {
            return byDisplay
        }

        return nil
    }
}

/// The on-device Foundation Models categorization seam (AND-565).
///
/// The concrete implementation lives in the app target, where the FoundationModels
/// framework is available and gated behind `#available(macOS 26, *)` +
/// `#if canImport(FoundationModels)`. PlaidBarCore stays free of any model
/// dependency so it remains pure and testable; tests inject a deterministic stub.
///
/// Privacy contract (identical to the NL/Ollama seams): the implementation runs
/// entirely on-device and is given ONLY a redaction-safe merchant string — never
/// raw account ids, transaction ids, item ids, tokens, or Plaid payloads.
public protocol FMMerchantCategorizing: Sendable {
    /// Suggest a category for a redaction-safe merchant string using guided
    /// generation constrained to the 16-case enum.
    ///
    /// The result crosses the app→Core boundary as the *constrained string* (the
    /// `SpendingCategory.rawValue` the guided generation was restricted to), not a
    /// resolved enum, so Core stays free of any FoundationModels dependency and
    /// `FMSpendingCategoryMapper` remains the single, unit-tested place that string
    /// is turned back into a `SpendingCategory`. Returns `nil` when the model
    /// produced no usable result (so the caller falls back to NL). Must never throw
    /// across the boundary — failures (incl. timeout/cancellation) degrade to `nil`.
    func suggestCategory(merchant: String) async -> String?

    /// Suggest a category using the richer, injection-safe `CategorySuggestion-
    /// Context` (Plaid hint + recurring flag + inflow/outflow) instead of the bare
    /// merchant string. Additive: a default implementation falls back to the
    /// merchant-only call, so existing conformers (and the no-op when FM is absent)
    /// keep compiling and behaving identically. Same boundary contract — returns the
    /// constrained `SpendingCategory.rawValue` string or `nil`, never throws.
    func suggestCategory(context: CategorySuggestionContext) async -> String?
}

public extension FMMerchantCategorizing {
    /// Default: ignore the extra context and categorize from the merchant string,
    /// so a conformer that hasn't adopted the richer prompt still works unchanged.
    func suggestCategory(context: CategorySuggestionContext) async -> String? {
        await suggestCategory(merchant: context.merchant)
    }
}

/// The Foundation Models categorization tier, sitting ABOVE NaturalLanguage in
/// the suggestion order (AND-565).
///
/// Strategy:
/// 1. If FM is `.available` AND a categorizer is wired, ask it for a constrained
///    suggestion using only the redaction-safe merchant string. The constrained
///    string is resolved back to a `SpendingCategory` through `FMSpendingCategory-
///    Mapper` (the single tested boundary parser); a resolved result is returned
///    as a `.foundationModels` suggestion (trusted — the generation is constrained
///    to the 16 cases — but still a *suggestion*, never applied).
/// 2. On FM unavailable, no wired categorizer, an FM miss, or an unparseable
///    string, fall back to the existing `NLMerchantCategorizer` — byte-identically
///    to today's behavior.
///
/// The categorizer is a pure value type; the only side effect is the injected,
/// on-device FM call, which is gated by the availability decision above.
public struct FMMerchantCategorizer: Sendable {
    private let foundationModelsState: LocalAIFoundationModelsTierState
    private let nlCategorizer: NLMerchantCategorizer
    private let fmCategorizer: (any FMMerchantCategorizing)?

    /// Module-internal read of the probed FM tier state, so the income extension
    /// (`suggestIncome(for:context:…)`, defined in `FMIncomeCategorizer.swift`) can
    /// reuse the same availability gate without exposing it publicly.
    var probedFoundationModelsState: LocalAIFoundationModelsTierState {
        foundationModelsState
    }

    public init(
        foundationModelsState: LocalAIFoundationModelsTierState = .unsupported,
        nlCategorizer: NLMerchantCategorizer = NLMerchantCategorizer(),
        fmCategorizer: (any FMMerchantCategorizing)? = nil
    ) {
        self.foundationModelsState = foundationModelsState
        self.nlCategorizer = nlCategorizer
        self.fmCategorizer = fmCategorizer
    }

    /// Suggest a category for a transaction, preferring an on-device Foundation
    /// Models suggestion when Apple Intelligence is available, otherwise falling
    /// back to the NaturalLanguage tier. Returns `nil` when nothing applies —
    /// never a guess. The result is always a SUGGESTION (with provenance); it is
    /// never auto-applied and never bypasses the review/override flow.
    public func suggest(for transaction: TransactionDTO) async -> MerchantCategorySuggestion? {
        if FMCategorizationTierDecision.shouldAttemptFoundationModels(foundationModels: foundationModelsState),
           let fmCategorizer {
            // Only the redaction-safe merchant string is sent to the model.
            let merchant = Self.redactionSafeMerchantString(for: transaction)
            if !merchant.isEmpty,
               let rawCategory = await fmCategorizer.suggestCategory(merchant: merchant),
               // Resolve the constrained string back to an enum through the single,
               // unit-tested boundary parser. A malformed/unknown value degrades to
               // the NL fallback rather than a wrong guess.
               let fmCategory = FMSpendingCategoryMapper.category(from: rawCategory) {
                return MerchantCategorySuggestion(
                    category: fmCategory,
                    tier: .foundationModels,
                    isTrusted: true
                )
            }
        }

        // FM unavailable / unwired / missed → exact NL/heuristic path as today.
        return nlSuggestion(for: transaction)
    }

    /// Suggest a category using the richer, injection-safe `CategorySuggestion-
    /// Context` (priority #5): the Plaid primary hint, recurring flag, and
    /// inflow/outflow are passed to the on-device model so it can disambiguate
    /// better than from the merchant string alone. Additive overload — same
    /// strategy and fallbacks as `suggest(for:)`; when FM is unavailable / unwired /
    /// misses, it degrades byte-identically to the NL tier (which reads only the
    /// transaction's merchant string, exactly as today). The model still only ever
    /// receives identifier-free context.
    public func suggest(
        for transaction: TransactionDTO,
        context: CategorySuggestionContext
    ) async -> MerchantCategorySuggestion? {
        if FMCategorizationTierDecision.shouldAttemptFoundationModels(foundationModels: foundationModelsState),
           let fmCategorizer,
           context.hasMerchantSignal {
            if let rawCategory = await fmCategorizer.suggestCategory(context: context),
               let fmCategory = FMSpendingCategoryMapper.category(from: rawCategory) {
                return MerchantCategorySuggestion(
                    category: fmCategory,
                    tier: .foundationModels,
                    isTrusted: true
                )
            }
        }

        // FM unavailable / unwired / missed / no merchant signal → NL tier as today.
        return nlSuggestion(for: transaction)
    }

    /// The NaturalLanguage suggestion for a transaction, expressed in the unified
    /// suggestion shape. This is the verbatim NL inference (AND-507); only the
    /// wrapper differs. Exposed so the no-FM path is trivially regression-testable.
    public func nlSuggestion(for transaction: TransactionDTO) -> MerchantCategorySuggestion? {
        guard let inference = nlCategorizer.infer(for: transaction) else { return nil }
        return MerchantCategorySuggestion(
            category: inference.category,
            tier: .naturalLanguage,
            isTrusted: inference.isTrusted
        )
    }

    /// The redaction-safe merchant string fed to Foundation Models: the cleaned
    /// merchant name when present, else the raw transaction name. No identifiers,
    /// amounts, dates, or Plaid payload text — only the merchant label the user
    /// already sees, mirroring what the NL tier reads.
    static func redactionSafeMerchantString(for transaction: TransactionDTO) -> String {
        let merchant = transaction.merchantName?.trimmingCharacters(in: .whitespacesAndNewlines)
        if let merchant, !merchant.isEmpty {
            return merchant
        }
        return transaction.name.trimmingCharacters(in: .whitespacesAndNewlines)
    }
}
