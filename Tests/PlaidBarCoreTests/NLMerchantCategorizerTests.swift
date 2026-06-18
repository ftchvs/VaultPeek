import Foundation
@testable import PlaidBarCore
import Testing

@Suite("NL Merchant Categorizer Tests")
struct NLMerchantCategorizerTests {
    private let categorizer = NLMerchantCategorizer()

    // MARK: - (1) Lexicon hits

    @Test("Recognizable raw merchant names resolve to the right category with a trusted confidence")
    func lexiconHits() {
        let cases: [(name: String, category: SpendingCategory)] = [
            ("WHOLEFDS MKT 10234", .foodAndDrink),
            ("BLUE BOTTLE COFFEE", .foodAndDrink),
            ("UBER TRIP", .transportation),
            ("SHELL OIL 4821", .transportation),
            ("CVS/PHARMACY #2231", .healthAndFitness),
            ("NETFLIX.COM", .entertainment),
        ]

        for testCase in cases {
            let inference = categorizer.infer(rawName: testCase.name)
            #expect(inference?.category == testCase.category, "\(testCase.name) should resolve to \(testCase.category)")
            // High (brand) or medium (keyword) — both are trusted, never low.
            #expect(inference?.isTrusted == true, "\(testCase.name) should be a trusted inference")
            #expect(inference?.confidence != .low, "\(testCase.name) should not be low confidence")
        }
    }

    @Test("Brand tokens earn high confidence; bare keyword tokens earn medium")
    func confidenceBands() {
        // "uber" is a brand token.
        #expect(categorizer.infer(rawName: "UBER TRIP")?.confidence == .high)
        // "pharmacy" (no brand present) is a descriptive keyword token.
        #expect(categorizer.infer(rawName: "NEIGHBORHOOD PHARMACY")?.confidence == .medium)
    }

    // MARK: - (2) Unknown merchant

    @Test("Unknown/gibberish merchant returns nil or low confidence — never a trusted wrong guess")
    func unknownMerchantIsNotGuessed() {
        let unknown = categorizer.infer(rawName: "SQ *KMNT LLC 9921")
        // Either no inference, or only the untrusted low band from embeddings.
        if let unknown {
            #expect(unknown.isTrusted == false, "An unknown merchant must never produce a trusted inference")
            #expect(unknown.confidence == .low)
        }
    }

    @Test("Empty / digit-only names yield no inference")
    func emptyNamesYieldNothing() {
        #expect(categorizer.infer(rawName: "") == nil)
        #expect(categorizer.infer(rawName: "   ") == nil)
        #expect(categorizer.infer(rawName: "4821 99021 #221") == nil)
    }

    // MARK: - (3) Determinism

    @Test("Same input yields the same output across repeated calls")
    func determinism() {
        let names = ["WHOLEFDS MKT 10234", "UBER TRIP", "SQ *KMNT LLC 9921", "NETFLIX.COM"]
        for name in names {
            let first = categorizer.infer(rawName: name)
            for _ in 0 ..< 8 {
                #expect(categorizer.infer(rawName: name) == first, "\(name) inference must be stable")
            }
        }
    }

    // MARK: - (5) Case-insensitivity & punctuation normalization

    @Test("Case and punctuation in raw Plaid names do not change the inferred category")
    func caseAndPunctuationNormalization() {
        let variants = [
            "netflix.com",
            "NETFLIX.COM",
            "Netflix.Com",
            "  NETFLIX  .  COM  ",
        ]
        let expected = SpendingCategory.entertainment
        for variant in variants {
            #expect(categorizer.infer(rawName: variant)?.category == expected, "\(variant) should resolve to entertainment")
        }

        // Digit/terminal suffixes must not block the merchant match.
        #expect(categorizer.infer(rawName: "CVS/PHARMACY #2231")?.category == .healthAndFitness)
        #expect(categorizer.infer(rawName: "SHELL OIL 4821")?.category == .transportation)
    }

    @Test("Inference falls back to merchantName when the raw name has no signal")
    func merchantNameFallback() {
        let transaction = TransactionDTO(
            id: "t",
            accountId: "a",
            amount: 10,
            date: "2026-06-01",
            name: "POS PURCHASE 0011",
            merchantName: "Netflix"
        )
        #expect(categorizer.infer(for: transaction)?.category == .entertainment)
    }
}
