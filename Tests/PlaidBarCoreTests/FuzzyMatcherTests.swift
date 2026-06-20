import Foundation
import PlaidBarCore
import Testing

@Suite("FuzzyMatcher")
struct FuzzyMatcherTests {
    // MARK: - Subsequence matching

    @Test("Matches an ordered subsequence, rejects a non-subsequence")
    func subsequence() {
        // "bdg" is an ordered subsequence of "Budgets"; "gub" is not (wrong order).
        #expect(FuzzyMatcher.score(query: "bdg", in: "Budgets") != nil)
        #expect(FuzzyMatcher.score(query: "gub", in: "Budgets") == nil)
        // A character not present at all fails.
        #expect(FuzzyMatcher.score(query: "budz", in: "Budgets") == nil)
    }

    @Test("Matching is case- and diacritic-insensitive")
    func caseAndDiacritics() {
        #expect(FuzzyMatcher.score(query: "BUDGETS", in: "budgets") != nil)
        #expect(FuzzyMatcher.score(query: "cafe", in: "Café") != nil)
        #expect(FuzzyMatcher.score(query: "CAFÉ", in: "cafe") != nil)
    }

    @Test("Empty query returns a neutral (matchable) score, not nil")
    func emptyQueryNeutral() {
        let hit = FuzzyMatcher.score(query: "", in: "Anything")
        #expect(hit != nil)
        #expect(hit?.score == 0)
        #expect(hit?.matchedRanges.isEmpty == true)
    }

    @Test("Matched ranges are the field indices the query hit")
    func matchedRanges() {
        // "bg" hits index 0 (B) and 3 (g) of "Budgets".
        let hit = FuzzyMatcher.score(query: "bg", in: "Budgets")
        #expect(hit?.matchedRanges == [0, 3])
    }

    // MARK: - Ranking quality

    @Test("Exact match outranks prefix match outranks scattered subsequence")
    func rankingTiers() {
        let exact = FuzzyMatcher.score(query: "review", in: "Review")!.score
        let prefix = FuzzyMatcher.score(query: "rev", in: "Review")!.score
        let scattered = FuzzyMatcher.score(query: "rw", in: "Review")!.score
        #expect(exact > prefix)
        #expect(prefix > scattered)
    }

    @Test("A prefix hit beats the same query buried later in the field")
    func earlierBeatsLater() {
        // "go" as a prefix of "Goals" should beat "go" inside "Go to Settings"-style
        // late placement.
        let early = FuzzyMatcher.score(query: "goal", in: "Goals")!.score
        let late = FuzzyMatcher.score(query: "goal", in: "Set a goal")!.score
        #expect(early > late)
    }

    @Test("Word-boundary matches beat mid-word matches of equal length")
    func wordBoundaryBonus() {
        // "ns" — in "Net Spend" both hit word starts (N..., S...); in "Insights" they
        // are mid-word. The boundary hits should score higher.
        let boundary = FuzzyMatcher.score(query: "ns", in: "Net Spend")!.score
        let midWord = FuzzyMatcher.score(query: "ns", in: "Insights")!.score
        #expect(boundary > midWord)
    }

    @Test("Consecutive matches beat gapped matches")
    func consecutiveBonus() {
        // "rev" consecutive in "Review" beats "rvw"-style gapped match in the same word.
        let consecutive = FuzzyMatcher.score(query: "rev", in: "Reverie")!.score
        let gapped = FuzzyMatcher.score(query: "rvr", in: "Reverie")!.score
        #expect(consecutive > gapped)
    }

    // MARK: - search() over candidates

    private struct Item: Sendable, Equatable {
        let title: String
        let keywords: [String]
    }

    private let items = [
        Item(title: "Dashboard", keywords: ["home", "overview"]),
        Item(title: "Budgets", keywords: ["spending", "categories"]),
        Item(title: "Review", keywords: ["inbox", "triage"]),
        Item(title: "Accounts", keywords: ["banks", "balances"]),
    ]

    @Test("search() ranks the best title match first")
    func searchRanksBest() {
        let results = FuzzyMatcher.search(
            query: "bud",
            candidates: items,
            title: { $0.title },
            keywords: { $0.keywords }
        )
        #expect(results.first?.element.title == "Budgets")
    }

    @Test("search() with an empty query returns all candidates in input order")
    func searchEmptyQuery() {
        let results = FuzzyMatcher.search(
            query: "   ",
            candidates: items,
            title: { $0.title },
            keywords: { $0.keywords }
        )
        #expect(results.count == items.count)
        #expect(results.map(\.element.title) == items.map(\.title))
        #expect(results.allSatisfy { $0.score == 0 })
    }

    @Test("search() drops candidates that match nowhere")
    func searchDropsNonMatches() {
        let results = FuzzyMatcher.search(
            query: "zzzz",
            candidates: items,
            title: { $0.title },
            keywords: { $0.keywords }
        )
        #expect(results.isEmpty)
    }

    @Test("A keyword match surfaces a candidate whose title does not match")
    func keywordMatch() {
        // "spend" is a keyword of Budgets but not in any title.
        let results = FuzzyMatcher.search(
            query: "spend",
            candidates: items,
            title: { $0.title },
            keywords: { $0.keywords }
        )
        #expect(results.first?.element.title == "Budgets")
    }

    @Test("A title hit outranks a keyword-only hit on a competing candidate")
    func titleBeatsKeyword() {
        // Query "ban": "Accounts" matches only via keyword "banks"; add a decoy whose
        // title contains the letters at a word start.
        let candidates = [
            Item(title: "Accounts", keywords: ["banks"]),
            Item(title: "Ban Hammer", keywords: []),
        ]
        let results = FuzzyMatcher.search(
            query: "ban",
            candidates: candidates,
            title: { $0.title },
            keywords: { $0.keywords }
        )
        // The title match ("Ban Hammer", prefix) should beat the keyword-only match.
        #expect(results.first?.element.title == "Ban Hammer")
    }

    @Test("Ties break by input order (stable result)")
    func stableTiebreak() {
        // Two identical titles: the earlier one must come first.
        let candidates = [
            Item(title: "Same", keywords: []),
            Item(title: "Same", keywords: []),
        ]
        let results = FuzzyMatcher.search(
            query: "same",
            candidates: candidates,
            title: { $0.title },
            keywords: { $0.keywords }
        )
        #expect(results.map(\.index) == [0, 1])
    }
}
