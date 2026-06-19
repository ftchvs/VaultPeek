import Foundation
@testable import PlaidBarCore
import Testing

/// AND-563 foundation: the pure tier-ordering decision that slots Apple
/// Foundation Models at the TOP of the on-device AI tier order when available,
/// and otherwise resolves EXACTLY as the runtime did before FM existed.
///
/// The availability *probe* (the actual `SystemLanguageModel` call) lives in the
/// app target behind `#available`; only its boolean result is injected here, so
/// these tests run on any OS without Apple Intelligence.
@Suite("Local AI Tier Resolver Tests")
struct LocalAITierResolverTests {
    // Facts that reproduce "today" (pre-FM) for each rung.
    private func legacyFacts(
        foundationModels: LocalAIFoundationModelsTierState = .unsupported,
        ollamaEngaged: Bool = false,
        naturalLanguageReady: Bool = true
    ) -> LocalAITierFacts {
        LocalAITierFacts(
            foundationModels: foundationModels,
            ollamaEngaged: ollamaEngaged,
            naturalLanguageReady: naturalLanguageReady
        )
    }

    // MARK: - Foundation Models preference (the new behavior)

    @Test("Foundation Models is preferred at the top of the order when available")
    func foundationModelsPreferredWhenAvailable() {
        // Even with Ollama engaged AND NaturalLanguage ready, FM wins.
        let resolved = LocalAITierResolver.resolvePreferredTier(
            facts: legacyFacts(
                foundationModels: .available,
                ollamaEngaged: true,
                naturalLanguageReady: true
            )
        )
        #expect(resolved == .foundationModels)
    }

    @Test("Foundation Models outranks every lower rung individually")
    func foundationModelsOutranksEachRung() {
        for ollama in [true, false] {
            for nl in [true, false] {
                let resolved = LocalAITierResolver.resolvePreferredTier(
                    facts: LocalAITierFacts(
                        foundationModels: .available,
                        ollamaEngaged: ollama,
                        naturalLanguageReady: nl
                    )
                )
                #expect(resolved == .foundationModels)
            }
        }
    }

    // MARK: - Regression guard: FM unavailable == today's resolution

    @Test("FM unavailable for any reason resolves identically to the pre-FM order")
    func fmUnavailableMatchesLegacyResolution() {
        // For every non-available FM state, the resolver must behave as if FM did
        // not exist: the outcome depends only on the legacy rungs.
        let unavailableStates: [LocalAIFoundationModelsTierState] = [
            .unsupported,
            .deviceNotEligible,
            .appleIntelligenceNotEnabled,
            .modelNotReady,
            .unavailableOther,
        ]

        for state in unavailableStates {
            // Ollama engaged → Ollama is the preferred generation tier (today).
            #expect(
                LocalAITierResolver.resolvePreferredTier(
                    facts: legacyFacts(foundationModels: state, ollamaEngaged: true, naturalLanguageReady: true)
                ) == .ollama
            )
            // No Ollama, NL ready → NaturalLanguage (today's zero-setup tier).
            #expect(
                LocalAITierResolver.resolvePreferredTier(
                    facts: legacyFacts(foundationModels: state, ollamaEngaged: false, naturalLanguageReady: true)
                ) == .naturalLanguage
            )
            // No Ollama, no NL → deterministic heuristic floor (always present).
            #expect(
                LocalAITierResolver.resolvePreferredTier(
                    facts: legacyFacts(foundationModels: state, ollamaEngaged: false, naturalLanguageReady: false)
                ) == .heuristic
            )
        }
    }

    // MARK: - Fallback rungs (each one explicitly)

    @Test("Ollama is preferred over NaturalLanguage and heuristic when engaged and FM is absent")
    func ollamaRungPreferredOverLowerTiers() {
        let resolved = LocalAITierResolver.resolvePreferredTier(
            facts: legacyFacts(foundationModels: .unsupported, ollamaEngaged: true, naturalLanguageReady: true)
        )
        #expect(resolved == .ollama)
    }

    @Test("NaturalLanguage is preferred over heuristic when ready and no higher tier is engaged")
    func naturalLanguageRungPreferredOverHeuristic() {
        let resolved = LocalAITierResolver.resolvePreferredTier(
            facts: legacyFacts(foundationModels: .unsupported, ollamaEngaged: false, naturalLanguageReady: true)
        )
        #expect(resolved == .naturalLanguage)
    }

    @Test("Heuristic is the floor when nothing else is available")
    func heuristicIsTheFloor() {
        let resolved = LocalAITierResolver.resolvePreferredTier(
            facts: legacyFacts(foundationModels: .unsupported, ollamaEngaged: false, naturalLanguageReady: false)
        )
        #expect(resolved == .heuristic)
    }

    // MARK: - Tier ordering metadata

    @Test("Tier rank places Foundation Models strictly above all legacy tiers")
    func tierRankOrders() {
        #expect(LocalAIRuntimeTier.foundationModels.rank < LocalAIRuntimeTier.ollama.rank)
        #expect(LocalAIRuntimeTier.ollama.rank < LocalAIRuntimeTier.naturalLanguage.rank)
        #expect(LocalAIRuntimeTier.naturalLanguage.rank < LocalAIRuntimeTier.heuristic.rank)
    }

    @Test("Only Foundation Models is considered available from its tier state")
    func foundationModelsStateAvailability() {
        #expect(LocalAIFoundationModelsTierState.available.isAvailable == true)
        #expect(LocalAIFoundationModelsTierState.unsupported.isAvailable == false)
        #expect(LocalAIFoundationModelsTierState.deviceNotEligible.isAvailable == false)
        #expect(LocalAIFoundationModelsTierState.appleIntelligenceNotEnabled.isAvailable == false)
        #expect(LocalAIFoundationModelsTierState.modelNotReady.isAvailable == false)
        #expect(LocalAIFoundationModelsTierState.unavailableOther.isAvailable == false)
    }

    // MARK: - Display surfacing parity (tier appears like existing tiers)

    @Test("Every tier has a non-empty display name and short status label")
    func tierDisplayMetadataExists() {
        for tier in LocalAIRuntimeTier.allCases {
            #expect(!tier.displayName.isEmpty)
            #expect(!tier.shortStatusLabel.isEmpty)
        }
        // The FM tier surfaces an Apple Intelligence affordance distinct from Ollama.
        #expect(LocalAIRuntimeTier.foundationModels.displayName.contains("Apple"))
    }

    @Test("Foundation Models unavailability reasons map to human-readable cause copy")
    func foundationModelsCauseCopy() {
        #expect(LocalAIFoundationModelsTierState.deviceNotEligible.causeLabel != nil)
        #expect(LocalAIFoundationModelsTierState.appleIntelligenceNotEnabled.causeLabel != nil)
        #expect(LocalAIFoundationModelsTierState.modelNotReady.causeLabel != nil)
        // "available" and the generic unsupported case have no remediation cause.
        #expect(LocalAIFoundationModelsTierState.available.causeLabel == nil)
        #expect(LocalAIFoundationModelsTierState.unsupported.causeLabel == nil)
    }
}
