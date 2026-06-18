import Foundation
#if canImport(NaturalLanguage)
import NaturalLanguage
#endif

/// Confidence band for a zero-setup NL category inference (AND-507).
///
/// `high`/`medium` are *trusted* — strong enough to fill `effectiveCategory`
/// when the user hasn't overridden and Plaid returned nothing usable. `low`
/// is surfaced (so the inference source can still be shown) but is NOT trusted
/// to fill the category, so genuinely uncertain merchants keep flowing to the
/// Review Inbox instead of getting a confident wrong guess.
public enum NLCategoryConfidence: String, Sendable, Codable, Hashable, CaseIterable {
    case high
    case medium
    case low

    /// Whether this band is trusted enough to fill `effectiveCategory`.
    public var isTrusted: Bool {
        self == .high || self == .medium
    }

    public var displayName: String {
        switch self {
        case .high: "High"
        case .medium: "Medium"
        case .low: "Low"
        }
    }
}

/// A single zero-setup NL inference: the suggested category plus its confidence.
public struct NLCategoryInference: Sendable, Equatable, Hashable {
    public let category: SpendingCategory
    public let confidence: NLCategoryConfidence

    public init(category: SpendingCategory, confidence: NLCategoryConfidence) {
        self.category = category
        self.confidence = confidence
    }

    /// Whether this inference is trusted enough to fill `effectiveCategory`.
    public var isTrusted: Bool {
        confidence.isTrusted
    }
}

/// Zero-setup, on-device merchant categorizer backed by Apple's NaturalLanguage
/// framework over a deterministic lexicon floor (AND-507).
///
/// `NaturalLanguage` is a pure system framework — no entitlement, Info.plist,
/// App Group, or extension surface — so SwiftPM links it automatically and this
/// tier is always-on (it does NOT depend on the `localAIEnabled` Ollama toggle).
///
/// Strategy, in precedence order:
/// 1. Normalize the raw Plaid name (lowercase, strip punctuation/digits noise).
/// 2. Lemmatize tokens with `NLTagger` so "groceries"→"grocery" still hits the
///    lexicon (widens recall deterministically; falls back to the raw token).
/// 3. Look the tokens up in `MerchantCategoryLexicon` — the deterministic,
///    unit-tested floor. Brand hits → `high`, keyword hits → `medium`.
/// 4. On a lexicon miss, optionally widen recall with `NLEmbedding` nearest-
///    neighbor over category seed words — but only ever as a `low`-confidence
///    (untrusted) inference, because embedding-model availability varies by
///    locale. The trusted band therefore stays fully deterministic and never
///    flakes across repeated calls.
///
/// Pure value type; all calls are non-isolated and side-effect-free.
public struct NLMerchantCategorizer: Sendable {
    public init() {}

    /// Infer a category for a transaction, preferring the raw `name` (which
    /// carries the most signal, e.g. "BLUE BOTTLE COFFEE") and falling back to
    /// `merchantName`. Returns nil when nothing applies — never a guess.
    ///
    /// A *trusted* (lexicon) hit always wins over an untrusted (`low`) embedding
    /// guess, regardless of which field produced it: a generic raw name like
    /// "STORE 1234" must not short-circuit a clean `merchantName` such as
    /// "Netflix" with only a low-confidence embedding match, which
    /// `resolveCategory` would then discard — leaving the row uncategorized
    /// instead of using the trusted merchant fallback.
    public func infer(for transaction: TransactionDTO) -> NLCategoryInference? {
        let rawInference = infer(rawName: transaction.name)
        if let rawInference, rawInference.isTrusted {
            return rawInference
        }
        if let merchant = transaction.merchantName,
            let merchantInference = infer(rawName: merchant) {
            // A trusted merchant hit beats a low-confidence raw guess; otherwise
            // keep whichever we have (prefer the raw one for stability).
            if merchantInference.isTrusted || rawInference == nil {
                return merchantInference
            }
        }
        return rawInference
    }

    /// Infer a category from a raw merchant string. Deterministic for any input
    /// whose result comes from the lexicon (the trusted band); the embedding
    /// fallback only ever yields the untrusted `low` band.
    public func infer(rawName: String) -> NLCategoryInference? {
        let normalized = Self.normalize(rawName)
        guard !normalized.isEmpty else { return nil }
        let tokens = Self.lemmatizedTokens(from: normalized)

        if let match = MerchantCategoryLexicon.match(normalizedString: normalized, tokens: tokens) {
            let confidence: NLCategoryConfidence = match.strength == .brand ? .high : .medium
            return NLCategoryInference(category: match.category, confidence: confidence)
        }

        // Lexicon miss: optionally widen recall via word embeddings, but cap at
        // the untrusted `low` band so model-availability differences never leak
        // into the trusted (deterministic) path.
        if let embedded = Self.embeddingInference(tokens: tokens) {
            return NLCategoryInference(category: embedded, confidence: .low)
        }
        return nil
    }

    // MARK: - Normalization & tokenization

    /// Lowercase, replace punctuation with spaces, and drop pure-digit noise
    /// tokens (Plaid store/terminal codes like "10234") so the lexicon matches
    /// on the merchant words, not the numbers.
    static func normalize(_ raw: String) -> String {
        let lowered = raw.lowercased()
        var scalars = String.UnicodeScalarView()
        for scalar in lowered.unicodeScalars {
            if CharacterSet.alphanumerics.contains(scalar) {
                scalars.append(scalar)
            } else {
                scalars.append(" ")
            }
        }
        let collapsed = String(scalars)
        let kept = collapsed
            .split(separator: " ")
            .filter { token in
                // Drop pure-digit tokens; keep alphanumerics like "att".
                !token.allSatisfy(\.isNumber)
            }
        return kept.joined(separator: " ")
    }

    /// Tokenize a normalized string and lemmatize each token with `NLTagger`
    /// so morphological variants collapse onto their lemma before lexicon
    /// lookup. Always returns the raw token too, so a missing lemma never drops
    /// a token the lexicon could have matched.
    static func lemmatizedTokens(from normalized: String) -> [String] {
        let rawTokens = normalized.split(separator: " ").map(String.init)
        guard !rawTokens.isEmpty else { return [] }

        var lemmas: [String] = []
        #if canImport(NaturalLanguage)
        let tagger = NLTagger(tagSchemes: [.lemma])
        tagger.string = normalized
        tagger.enumerateTags(
            in: normalized.startIndex ..< normalized.endIndex,
            unit: .word,
            scheme: .lemma,
            options: [.omitWhitespace, .omitPunctuation]
        ) { tag, range in
            if let tag, !tag.rawValue.isEmpty {
                lemmas.append(tag.rawValue.lowercased())
            } else {
                lemmas.append(String(normalized[range]))
            }
            return true
        }
        #endif
        // On toolchains without NaturalLanguage (Linux/CI server + tests),
        // `lemmas` stays empty and we fall back to the raw tokens below, so the
        // deterministic lexicon floor still runs everywhere.

        // Keep both raw and lemma forms, de-duplicated, raw first so ordering
        // (and thus the deterministic "first keyword wins") is stable.
        var seen = Set<String>()
        var combined: [String] = []
        for token in rawTokens + lemmas where seen.insert(token).inserted {
            combined.append(token)
        }
        return combined
    }

    // MARK: - Embedding fallback (untrusted, low confidence only)

    /// Seed words per category for the optional embedding nearest-neighbor
    /// pass. Deliberately small and generic; this only widens recall on lexicon
    /// misses and never produces a trusted inference.
    private static let embeddingSeeds: [(category: SpendingCategory, seeds: [String])] = [
        (.foodAndDrink, ["food", "restaurant", "coffee", "grocery"]),
        (.transportation, ["transport", "fuel", "transit", "ride"]),
        (.healthAndFitness, ["pharmacy", "medical", "fitness", "health"]),
        (.entertainment, ["entertainment", "music", "movie", "streaming"]),
        (.shopping, ["shopping", "store", "merchandise", "retail"]),
        (.travel, ["travel", "hotel", "flight", "airline"]),
        (.billsAndUtilities, ["utility", "electricity", "internet", "phone"]),
    ]

    /// Nearest-neighbor over category seed words using the English word
    /// embedding, when the model is available for the current locale. Returns
    /// nil when the model is unavailable so behavior degrades gracefully to the
    /// deterministic lexicon-only floor.
    static func embeddingInference(tokens: [String]) -> SpendingCategory? {
        #if canImport(NaturalLanguage)
        guard let embedding = NLEmbedding.wordEmbedding(for: .english) else { return nil }

        var bestCategory: SpendingCategory?
        var bestDistance = Double.greatestFiniteMagnitude
        for token in tokens where embedding.contains(token) {
            for entry in embeddingSeeds {
                for seed in entry.seeds {
                    let distance = embedding.distance(between: token, and: seed, distanceType: .cosine)
                    if distance < bestDistance {
                        bestDistance = distance
                        bestCategory = entry.category
                    }
                }
            }
        }
        // Only accept a genuinely close neighbor; cosine distance ranges 0...2.
        guard bestDistance <= 0.55 else { return nil }
        return bestCategory
        #else
        // No embedding model on this toolchain — degrade to the lexicon floor.
        return nil
        #endif
    }
}
