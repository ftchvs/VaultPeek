import Foundation
import Testing
@testable import PlaidBarCore

@Suite("Subscription cancel guidance (AND-497)")
struct SubscriptionCancelGuidanceTests {
    @Test("Known merchant resolves to a specific cancellation page")
    func knownMerchantResolvesSpecific() {
        let result = SubscriptionCancelGuidance.guidance(for: "Netflix")
        #expect(result.isSpecific)
        #expect(result.url.host?.contains("netflix.com") == true)
        #expect(!result.linkText.isEmpty)
    }

    @Test("Merchant match is case- and whitespace-insensitive")
    func matchIsNormalized() {
        let spaced = SubscriptionCancelGuidance.guidance(for: "  NETFLIX  ")
        let lower = SubscriptionCancelGuidance.guidance(for: "netflix")
        #expect(spaced.isSpecific)
        #expect(spaced.url == lower.url)
    }

    @Test("Unknown merchant falls back to a well-formed generic search URL")
    func unknownMerchantFallsBack() {
        let result = SubscriptionCancelGuidance.guidance(for: "Obscure Gym XYZ")
        #expect(!result.isSpecific)
        #expect(result.url.scheme == "https")
        let query = result.url.query ?? ""
        #expect(query.contains("cancel"))
        // The encoded merchant name should appear in the query.
        #expect(query.lowercased().contains("obscure"))
    }

    @Test("Empty merchant name still yields a valid generic URL")
    func emptyMerchantYieldsValidURL() {
        let result = SubscriptionCancelGuidance.guidance(for: "   ")
        #expect(!result.isSpecific)
        #expect(result.url.scheme == "https")
        #expect(result.url.host != nil)
    }

    @Test("All curated cancellation URLs are valid https URLs")
    func curatedURLsAreValid() {
        // Probe several known merchants spanning the map.
        for merchant in ["Netflix", "Spotify", "Adobe", "Hulu", "Planet Fitness", "Audible"] {
            let result = SubscriptionCancelGuidance.guidance(for: merchant)
            #expect(result.isSpecific, "Expected \(merchant) to resolve to a specific page")
            #expect(result.url.scheme == "https")
            #expect(result.url.host != nil)
        }
    }

    @Test("normalize lowercases and trims")
    func normalizeBehaviour() {
        #expect(SubscriptionCancelGuidance.normalize("  Whole Foods  ") == "whole foods")
        #expect(SubscriptionCancelGuidance.normalize("NETFLIX") == "netflix")
    }
}
