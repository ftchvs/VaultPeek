import Foundation

/// A pure, `Sendable` subsequence fuzzy matcher + ranker for the ⌘K command
/// palette (ADR-001, IA §3.3, AND-596).
///
/// The palette needs the same "type a few letters, the right command floats to
/// the top" behavior every spotlight-style launcher has. Keeping the matcher
/// here in `PlaidBarCore` (not in the SwiftUI palette) makes the ranking policy
/// pure, `Sendable`, and unit-testable without the app target — CLAUDE.md's "put
/// shared logic in Core" rule. The palette view becomes a thin renderer over
/// `FuzzyMatcher.search(...)`.
///
/// The algorithm is deliberately simple and predictable (not a full
/// Smith-Waterman): a **case- and diacritic-insensitive ordered subsequence
/// match** with a score that rewards the qualities users feel —
///
/// - an exact / prefix hit on the title beats a scattered subsequence,
/// - consecutive matched characters beat gaps,
/// - matches at word starts (after a space / separator) beat mid-word matches,
/// - an earlier first match beats a later one,
/// - a title hit beats a keyword-only hit.
///
/// Ties break by the candidate's natural order (so a stable input order yields a
/// stable output order). An empty query returns every candidate in input order
/// with a neutral score, so the palette shows the full command list before the
/// user types.
public enum FuzzyMatcher {
    /// One ranked search hit: the candidate's index in the input array plus its
    /// score and the matched character positions (so a view can bold them).
    public struct Match<Element>: Sendable where Element: Sendable {
        /// The matched candidate.
        public let element: Element
        /// The candidate's position in the input array (stable tiebreak key).
        public let index: Int
        /// Higher is a better match. Comparable only within one `search` call.
        public let score: Int
        /// Indices (into the *matched field's* characters) that the query hit.
        /// Empty for an empty query. Useful for highlighting the title.
        public let matchedRanges: [Int]

        public init(element: Element, index: Int, score: Int, matchedRanges: [Int]) {
            self.element = element
            self.index = index
            self.score = score
            self.matchedRanges = matchedRanges
        }
    }

    // MARK: - Scoring weights (tuned for the palette; pure constants)

    /// Base reward for each matched character.
    private static let perCharacter = 8
    /// Bonus when a matched character immediately follows a previous match
    /// (a run of consecutive hits, e.g. "bud" in "Budgets").
    private static let consecutiveBonus = 12
    /// Bonus when a match lands at a word boundary (start, or after a separator).
    private static let wordBoundaryBonus = 14
    /// Bonus when the whole query is a prefix of the field ("bud" → "Budgets").
    private static let prefixBonus = 40
    /// Bonus when the query equals the field exactly.
    private static let exactBonus = 60
    /// Penalty per leading unmatched character before the first hit (rewards an
    /// early first match), capped so a long title can't drown the signal.
    private static let leadingGapPenalty = 2
    private static let maxLeadingGapPenalty = 20
    /// Keyword-only matches are real but rank below any title match.
    private static let keywordFieldPenalty = 30

    // MARK: - Public API

    /// Scores a single `query` against one `field`. Returns `nil` when the query
    /// is not an ordered subsequence of the field; returns a neutral
    /// `(score: 0, ranges: [])` for an empty query. Diacritic- and
    /// case-insensitive.
    ///
    /// `isKeywordField` applies the keyword penalty so a title hit always
    /// outranks a keyword-only hit on the same candidate.
    public static func score(
        query: String,
        in field: String,
        isKeywordField: Bool = false
    ) -> (score: Int, matchedRanges: [Int])? {
        let normalizedQuery = normalize(query)
        guard !normalizedQuery.isEmpty else { return (0, []) }

        let fieldChars = Array(normalize(field))
        let queryChars = Array(normalizedQuery)
        guard !fieldChars.isEmpty else { return nil }

        var total = 0
        var matched: [Int] = []
        var queryIdx = 0
        var previousMatchIdx: Int? = nil

        for (fieldIdx, char) in fieldChars.enumerated() where queryIdx < queryChars.count {
            guard char == queryChars[queryIdx] else { continue }

            total += perCharacter
            if let previous = previousMatchIdx, previous == fieldIdx - 1 {
                total += consecutiveBonus
            }
            if isWordBoundary(fieldChars, at: fieldIdx) {
                total += wordBoundaryBonus
            }
            matched.append(fieldIdx)
            previousMatchIdx = fieldIdx
            queryIdx += 1
        }

        // Not all query characters were consumed ⇒ not a subsequence.
        guard queryIdx == queryChars.count else { return nil }

        if let first = matched.first {
            total -= min(first * leadingGapPenalty, maxLeadingGapPenalty)
        }
        if fieldChars == queryChars {
            total += exactBonus
        } else if fieldChars.starts(with: queryChars) {
            total += prefixBonus
        }
        if isKeywordField {
            total -= keywordFieldPenalty
        }

        return (total, matched)
    }

    /// Ranks `candidates` against `query`, best first.
    ///
    /// Each candidate is scored against its `title` and, separately, every one of
    /// its `keywords`; the candidate keeps its **best** field score (the title is
    /// already favored by the keyword penalty). Candidates that match nowhere are
    /// dropped. An empty/whitespace query returns *all* candidates in input order
    /// (neutral score), so the palette lists everything before the user types.
    ///
    /// - Parameters:
    ///   - query: the raw search text.
    ///   - candidates: the items to rank.
    ///   - title: the primary searchable string for a candidate.
    ///   - keywords: additional searchable strings (subtitle words, synonyms).
    public static func search<Element>(
        query: String,
        candidates: [Element],
        title: (Element) -> String,
        keywords: (Element) -> [String] = { _ in [] }
    ) -> [Match<Element>] where Element: Sendable {
        let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines)

        guard !trimmed.isEmpty else {
            return candidates.enumerated().map { index, element in
                Match(element: element, index: index, score: 0, matchedRanges: [])
            }
        }

        var matches: [Match<Element>] = []
        for (index, element) in candidates.enumerated() {
            var best: (score: Int, matchedRanges: [Int])? = nil

            if let titleHit = score(query: trimmed, in: title(element)) {
                best = titleHit
            }
            for keyword in keywords(element) {
                guard let keywordHit = score(query: trimmed, in: keyword, isKeywordField: true) else {
                    continue
                }
                if best == nil || keywordHit.score > best!.score {
                    // Keep the title's ranges when the title also matched but a
                    // keyword scored higher — highlight stays on the visible title.
                    best = (keywordHit.score, best?.matchedRanges ?? [])
                }
            }

            guard let best else { continue }
            matches.append(
                Match(element: element, index: index, score: best.score, matchedRanges: best.matchedRanges)
            )
        }

        // Best score first; ties fall back to input order for a stable result.
        return matches.sorted { lhs, rhs in
            lhs.score != rhs.score ? lhs.score > rhs.score : lhs.index < rhs.index
        }
    }

    // MARK: - Helpers

    /// Lowercased + diacritic-folded so "Café" matches "cafe" and case never
    /// matters. Folding to the current locale keeps it deterministic for tests.
    private static func normalize(_ string: String) -> String {
        string.folding(options: [.diacriticInsensitive, .caseInsensitive], locale: nil)
    }

    /// A field index is a word boundary when it is the first character or follows
    /// a separator (space, hyphen, slash, or other non-alphanumeric).
    private static func isWordBoundary(_ chars: [Character], at index: Int) -> Bool {
        guard index > 0 else { return true }
        let previous = chars[index - 1]
        return !previous.isLetter && !previous.isNumber
    }
}
