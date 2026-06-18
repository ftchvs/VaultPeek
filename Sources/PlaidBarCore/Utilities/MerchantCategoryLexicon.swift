import Foundation

/// Deterministic merchant/keyword → `SpendingCategory` lexicon.
///
/// This is the unit-tested *floor* of the zero-setup NL categorization tier
/// (AND-507). It maps normalized tokens (and a handful of multi-word phrases)
/// found in a transaction's raw `name`/`merchantName` to a category, with a
/// confidence band per match kind. The `NLMerchantCategorizer` layers
/// NaturalLanguage lemmatization on top, but because embedding-model
/// availability varies by locale, the lexicon stays the deterministic,
/// reproducible source of truth — it never depends on a model being present.
///
/// Pure, `Sendable`, and side-effect-free: every lookup over the same input
/// yields the same output across repeated calls.
public enum MerchantCategoryLexicon {
    /// How a token matched, which determines the confidence band a caller
    /// should attach to the inference.
    public enum MatchStrength: Sendable, Equatable {
        /// A distinctive brand/merchant token (e.g. "netflix", "uber"): the
        /// strongest signal, trusted enough to fill `effectiveCategory`.
        case brand
        /// A descriptive keyword (e.g. "coffee", "pharmacy"): a strong signal,
        /// still trusted to fill `effectiveCategory`.
        case keyword
    }

    public struct Match: Sendable, Equatable {
        public let category: SpendingCategory
        public let strength: MatchStrength
        /// The token/phrase that produced the match (already normalized).
        public let token: String

        public init(category: SpendingCategory, strength: MatchStrength, token: String) {
            self.category = category
            self.strength = strength
            self.token = token
        }
    }

    /// Single-token brand and keyword entries. Tokens are lowercase and
    /// punctuation-free; they match a transaction token exactly OR as a
    /// prefix of a longer token (so "wholefds" matches "wholefds" and
    /// "netflix" matches "netflixcom" after punctuation is stripped).
    static let tokenTable: [String: Match] = build(entries: [
        // Food & Drink
        .keyword("coffee", .foodAndDrink),
        .keyword("cafe", .foodAndDrink),
        .keyword("espresso", .foodAndDrink),
        .keyword("restaurant", .foodAndDrink),
        .keyword("grocery", .foodAndDrink),
        .keyword("grocers", .foodAndDrink),
        .keyword("deli", .foodAndDrink),
        .keyword("bakery", .foodAndDrink),
        .keyword("pizza", .foodAndDrink),
        .keyword("diner", .foodAndDrink),
        .brand("starbucks", .foodAndDrink),
        .brand("wholefds", .foodAndDrink),
        .brand("wholefoods", .foodAndDrink),
        .brand("sweetgreen", .foodAndDrink),
        .brand("chipotle", .foodAndDrink),
        .brand("doordash", .foodAndDrink),
        .brand("grubhub", .foodAndDrink),
        .brand("bluebottle", .foodAndDrink),
        .brand("bluapron", .foodAndDrink),
        .brand("blueapron", .foodAndDrink),
        .brand("trader", .foodAndDrink),
        .brand("safeway", .foodAndDrink),
        .brand("kroger", .foodAndDrink),

        // Transportation. Generic single words like "gas"/"oil"/"subway" are
        // deliberately omitted to avoid false positives on synthetic merchant
        // names; the gas brands below ("shell", "chevron", ...) carry the
        // signal for fuel purchases instead.
        .keyword("transit", .transportation),
        .keyword("parking", .transportation),
        .keyword("rideshare", .transportation),
        .keyword("taxi", .transportation),
        .brand("uber", .transportation),
        .brand("lyft", .transportation),
        .brand("shell", .transportation),
        .brand("chevron", .transportation),
        .brand("exxon", .transportation),
        .brand("mobil", .transportation),
        .brand("bp", .transportation),
        .brand("texaco", .transportation),

        // Health & Fitness (MEDICAL). "health"/"gym" are too generic to be safe
        // single-token signals, so the distinctive words and brands carry it.
        .keyword("pharmacy", .healthAndFitness),
        .keyword("medical", .healthAndFitness),
        .keyword("clinic", .healthAndFitness),
        .keyword("dental", .healthAndFitness),
        .keyword("dentist", .healthAndFitness),
        .keyword("hospital", .healthAndFitness),
        .keyword("fitness", .healthAndFitness),
        .brand("cvs", .healthAndFitness),
        .brand("walgreens", .healthAndFitness),
        .brand("rite", .healthAndFitness), // rite aid
        .brand("planetfitness", .healthAndFitness),
        .brand("equinox", .healthAndFitness),

        // Entertainment
        .keyword("cinema", .entertainment),
        .keyword("theatre", .entertainment),
        .keyword("theater", .entertainment),
        .keyword("movies", .entertainment),
        .brand("netflix", .entertainment),
        .brand("spotify", .entertainment),
        .brand("hulu", .entertainment),
        .brand("disney", .entertainment),
        .brand("hbo", .entertainment),
        .brand("youtube", .entertainment),
        .brand("steam", .entertainment),
        .brand("playstation", .entertainment),
        .brand("xbox", .entertainment),

        // Shopping (GENERAL_MERCHANDISE). "store" is intentionally NOT a
        // keyword: it appears in too many generic merchant names to be a safe
        // signal. Distinctive retail brands carry shopping instead.
        .brand("amazon", .shopping),
        .brand("target", .shopping),
        .brand("walmart", .shopping),
        .brand("costco", .shopping),
        .brand("nordstrom", .shopping),
        .brand("ebay", .shopping),
        .brand("etsy", .shopping),
        .brand("bestbuy", .shopping),

        // Travel
        .keyword("airlines", .travel),
        .keyword("airline", .travel),
        .keyword("hotel", .travel),
        .keyword("motel", .travel),
        .keyword("resort", .travel),
        .brand("airbnb", .travel),
        // "delta"/"united" as bare brand tokens are deliberately omitted: they
        // collide with common non-airline merchants ("Delta Dental", "United
        // Healthcare"), and because brand matches win immediately they would
        // back-fill Travel before a health keyword (e.g. "dental") is even
        // considered, suppressing the `.uncategorized` review prompt. The
        // airline-specific phrases below ("delta air", "united air") carry the
        // real airline signal instead.
        .brand("marriott", .travel),
        .brand("hilton", .travel),
        .brand("expedia", .travel),

        // Bills & Utilities (RENT_AND_UTILITIES)
        .keyword("wireless", .billsAndUtilities),
        .keyword("electric", .billsAndUtilities),
        .keyword("utility", .billsAndUtilities),
        .keyword("utilities", .billsAndUtilities),
        .keyword("energy", .billsAndUtilities),
        .brand("verizon", .billsAndUtilities),
        .brand("comcast", .billsAndUtilities),
        .brand("xfinity", .billsAndUtilities),
        .brand("conedison", .billsAndUtilities),
        .brand("att", .billsAndUtilities),
    ])

    /// Multi-word phrases (checked against the whole normalized string before
    /// single-token matching) so e.g. "blue bottle" and "rite aid" resolve as
    /// brands even when split into separate tokens.
    static let phraseTable: [(phrase: String, match: Match)] = [
        ("blue bottle", Match(category: .foodAndDrink, strength: .brand, token: "blue bottle")),
        ("trader joe", Match(category: .foodAndDrink, strength: .brand, token: "trader joe")),
        ("whole foods", Match(category: .foodAndDrink, strength: .brand, token: "whole foods")),
        ("blue apron", Match(category: .foodAndDrink, strength: .brand, token: "blue apron")),
        ("rite aid", Match(category: .healthAndFitness, strength: .brand, token: "rite aid")),
        ("planet fitness", Match(category: .healthAndFitness, strength: .brand, token: "planet fitness")),
        ("con edison", Match(category: .billsAndUtilities, strength: .brand, token: "con edison")),
        ("best buy", Match(category: .shopping, strength: .brand, token: "best buy")),
        ("delta air", Match(category: .travel, strength: .brand, token: "delta air")),
        ("united air", Match(category: .travel, strength: .brand, token: "united air")),
    ]

    /// Look up the best lexicon match for a set of normalized tokens and the
    /// full normalized string. Phrases win over single tokens; among single
    /// tokens, brand matches win over keyword matches. Returns nil when nothing
    /// in the lexicon applies (so the caller can fall back to NL embeddings or
    /// leave the transaction uncategorized rather than guessing).
    static func match(normalizedString: String, tokens: [String]) -> Match? {
        for entry in phraseTable where normalizedString.contains(entry.phrase) {
            return entry.match
        }

        var best: Match?
        for token in tokens {
            guard let candidate = matchToken(token) else { continue }
            if candidate.strength == .brand { return candidate }
            if best == nil { best = candidate }
        }
        return best
    }

    private static func matchToken(_ token: String) -> Match? {
        if let exact = tokenTable[token] { return exact }
        // Prefix match handles digit-suffixed merchant codes after the digits
        // are stripped to a separate token, plus glued names like "netflixcom".
        for (key, match) in tokenTable where token.hasPrefix(key) && key.count >= 4 {
            return match
        }
        return nil
    }

    // MARK: - Entry construction

    private struct Entry {
        let token: String
        let category: SpendingCategory
        let strength: MatchStrength

        static func brand(_ token: String, _ category: SpendingCategory) -> Entry {
            Entry(token: token, category: category, strength: .brand)
        }

        static func keyword(_ token: String, _ category: SpendingCategory) -> Entry {
            Entry(token: token, category: category, strength: .keyword)
        }
    }

    private static func build(entries: [Entry]) -> [String: Match] {
        var table: [String: Match] = [:]
        for entry in entries {
            table[entry.token] = Match(
                category: entry.category,
                strength: entry.strength,
                token: entry.token
            )
        }
        return table
    }
}
