import Foundation

/// Confidence band for an income subtype inference (priority #5).
///
/// `high`/`medium` are *trusted* — strong enough to fill a display subtype when
/// the user hasn't confirmed one. `low` is surfaced (so the inference can still be
/// shown) but is NOT trusted, so genuinely ambiguous inflows keep prompting the
/// user instead of getting a confident wrong guess. Mirrors `NLCategoryConfidence`
/// for the expense tier so the two read consistently.
public enum IncomeCategoryConfidence: String, Sendable, Codable, Hashable, CaseIterable {
    case high
    case medium
    case low

    /// Whether this band is trusted enough to fill a display subtype.
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

/// A single income subtype inference: the suggested `IncomeCategory` plus its
/// confidence band.
public struct IncomeCategoryInference: Sendable, Equatable, Hashable {
    public let category: IncomeCategory
    public let confidence: IncomeCategoryConfidence

    public init(category: IncomeCategory, confidence: IncomeCategoryConfidence) {
        self.category = category
        self.confidence = confidence
    }

    /// Whether this inference is trusted enough to fill a display subtype.
    public var isTrusted: Bool {
        confidence.isTrusted
    }
}

/// Deterministic, on-device income subtype classifier (priority #5).
///
/// The income analogue of `NLMerchantCategorizer` + `MerchantCategoryLexicon`: it
/// reads an income transaction's redaction-safe `name`/`merchantName` and the
/// recurring signal and maps it to an `IncomeCategory` with a confidence band. It
/// is a pure, unit-tested *floor* — no model, no network — so the trusted band is
/// fully reproducible regardless of FM availability.
///
/// Strategy, in precedence order:
/// 1. Normalize the raw name (lowercase, strip punctuation/digit noise), reusing
///    `NLMerchantCategorizer.normalize` so it matches the expense tier exactly.
/// 2. Match income-specific phrases/keywords in the deterministic lexicon. A
///    distinctive phrase ("tax refund", "direct deposit") → `high`; a single
///    keyword ("payroll", "dividend") → `medium`.
/// 3. On a lexicon miss, fall back to the recurring heuristic: a *recurring* inflow
///    is most likely salary (`medium`); a one-off inflow is `otherIncome` (`low`,
///    untrusted) so it keeps prompting for confirmation.
///
/// Pure value type; every call is non-isolated and side-effect-free.
public struct IncomeMerchantClassifier: Sendable {
    public init() {}

    /// Infer an income subtype for a transaction. Returns `nil` for a non-income
    /// transaction (so callers never mis-bucket a spend) — never a guess.
    ///
    /// `isRecurring` is a caller-supplied flag (recurring streams live in
    /// `AppState`, not on the DTO); it defaults to `false` so the deterministic
    /// lexicon floor still runs everywhere.
    public func infer(
        for transaction: TransactionDTO,
        isRecurring: Bool = false
    ) -> IncomeCategoryInference? {
        guard transaction.isIncome else { return nil }

        // Prefer the raw name (most signal), fall back to the cleaned merchant.
        if let raw = infer(rawName: transaction.name, isRecurring: isRecurring), raw.isTrusted {
            return raw
        }
        if let merchant = transaction.merchantName,
           let merchantInference = infer(rawName: merchant, isRecurring: isRecurring),
           merchantInference.isTrusted {
            return merchantInference
        }
        // Neither field gave a trusted lexicon hit — fall back to the recurring
        // heuristic over the raw name (which carries the untrusted result too).
        return infer(rawName: transaction.name, isRecurring: isRecurring)
            ?? infer(rawName: transaction.merchantName ?? "", isRecurring: isRecurring)
    }

    /// Infer an income subtype from a raw merchant/description string. Deterministic
    /// for any lexicon hit; the recurring fallback only yields the heuristic bands.
    public func infer(rawName: String, isRecurring: Bool = false) -> IncomeCategoryInference? {
        let normalized = NLMerchantCategorizer.normalize(rawName)
        guard !normalized.isEmpty else {
            // No text signal at all: a recurring inflow still reads as likely salary.
            return isRecurring ? IncomeCategoryInference(category: .salary, confidence: .medium) : nil
        }

        if let match = Self.lexiconMatch(normalized: normalized) {
            let confidence: IncomeCategoryConfidence = match.strength == .phrase ? .high : .medium
            return IncomeCategoryInference(category: match.category, confidence: confidence)
        }

        // Lexicon miss: lean on the recurring signal. A recurring inflow is most
        // plausibly salary (trusted-medium); a one-off inflow is generic other
        // income at an untrusted `low` band so it keeps prompting.
        if isRecurring {
            return IncomeCategoryInference(category: .salary, confidence: .medium)
        }
        return IncomeCategoryInference(category: .otherIncome, confidence: .low)
    }

    // MARK: - Lexicon

    enum MatchStrength: Sendable, Equatable {
        /// A distinctive multi-word phrase (e.g. "tax refund"): the strongest signal.
        case phrase
        /// A single descriptive keyword (e.g. "payroll", "dividend").
        case keyword
    }

    struct Match: Sendable, Equatable {
        let category: IncomeCategory
        let strength: MatchStrength
    }

    /// Multi-word phrases checked against the whole normalized string first, so a
    /// distinctive phrase always beats a generic single-token keyword.
    static let phraseTable: [(phrase: String, category: IncomeCategory)] = [
        ("tax refund", .government),
        ("irs treas", .government),
        ("treasury", .government),
        ("social security", .government),
        ("unemployment", .government),
        ("direct deposit", .salary),
        ("payroll deposit", .salary),
        ("interest payment", .interest),
        ("interest earned", .interest),
        ("dividend payment", .dividend),
        ("capital gain", .dividend),
        ("expense reimbursement", .reimbursement),
    ]

    /// Single keyword tokens. Each matches a normalized token exactly OR as a prefix
    /// of a longer token (so "payroll" matches "payrolldep" after digits strip).
    static let keywordTable: [String: IncomeCategory] = [
        "payroll": .salary,
        "salary": .salary,
        "paycheck": .salary,
        "wages": .salary,
        "payco": .salary,
        "gusto": .salary,
        "adp": .salary,
        "interest": .interest,
        "apy": .interest,
        "dividend": .dividend,
        "refund": .refund,
        "return": .refund,
        "reimbursement": .reimbursement,
        "reimburse": .reimbursement,
        "venmo": .reimbursement,
        "zelle": .reimbursement,
        "irs": .government,
        "stimulus": .government,
        "benefits": .government,
    ]

    /// Best lexicon match for a normalized income string: phrases win over single
    /// keywords. Returns nil when nothing applies so the caller falls back to the
    /// recurring heuristic.
    static func lexiconMatch(normalized: String) -> Match? {
        for entry in phraseTable where normalized.contains(entry.phrase) {
            return Match(category: entry.category, strength: .phrase)
        }
        let tokens = normalized.split(separator: " ").map(String.init)
        for token in tokens {
            if let exact = keywordTable[token] {
                return Match(category: exact, strength: .keyword)
            }
            for (key, category) in keywordTable where token.hasPrefix(key) && key.count >= 4 {
                return Match(category: category, strength: .keyword)
            }
        }
        return nil
    }
}
