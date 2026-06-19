import Foundation
@testable import PlaidBarCore
import Testing

/// AND-564: pure-logic tests for the Foundation Models structured-insight path.
///
/// These cover the two pieces extracted into PlaidBarCore so they run on any OS
/// without Apple Intelligence:
///   1. the `@Generable` schema → display-string mapping (incl. empty + partial
///      streaming states), and
///   2. the engine-routing decision (FM-active-and-available → FM, else the
///      existing engine — the regression guard).
@Suite("Foundation Models Structured Insight Tests")
struct FoundationModelsInsightTests {
    // MARK: - Schema → display mapping

    @Test("A complete generated headline maps to a trimmed display string")
    func completeHeadlineMaps() {
        let content = FoundationModelsInsightContent(
            headline: "You spent $1,200 across 14 transactions this month.",
            supportingPoints: ["Groceries led at $400."]
        )
        #expect(
            FoundationModelsInsightMapper.displaySummary(from: content)
                == "You spent $1,200 across 14 transactions this month."
        )
    }

    @Test("Surrounding and internal whitespace/newlines collapse to single spaces")
    func whitespaceCollapses() {
        let content = FoundationModelsInsightContent(
            headline: "  You spent\n\n$1,200   across\t14 transactions.  "
        )
        #expect(
            FoundationModelsInsightMapper.displaySummary(from: content)
                == "You spent $1,200 across 14 transactions."
        )
    }

    @Test("An empty or whitespace-only headline maps to nil so the caller falls back")
    func emptyHeadlineMapsToNil() {
        #expect(FoundationModelsInsightMapper.displaySummary(from: FoundationModelsInsightContent(headline: "")) == nil)
        #expect(
            FoundationModelsInsightMapper.displaySummary(from: FoundationModelsInsightContent(headline: "   \n\t "))
                == nil
        )
    }

    // MARK: - Streaming partial mapping

    @Test("A nil partial headline (field not yet generated) yields nil")
    func partialNilHeadlineYieldsNil() {
        #expect(FoundationModelsInsightMapper.partialDisplaySummary(fromHeadline: nil) == nil)
    }

    @Test("A partial headline that is only whitespace yields nil, not a blank line")
    func partialWhitespaceHeadlineYieldsNil() {
        #expect(FoundationModelsInsightMapper.partialDisplaySummary(fromHeadline: "   ") == nil)
    }

    @Test("A non-empty partial headline streams through, whitespace-collapsed")
    func partialHeadlineStreams() {
        #expect(
            FoundationModelsInsightMapper.partialDisplaySummary(fromHeadline: "You spent $1,2")
                == "You spent $1,2"
        )
        #expect(
            FoundationModelsInsightMapper.partialDisplaySummary(fromHeadline: "You  spent\n$1,200")
                == "You spent $1,200"
        )
    }

    // MARK: - Engine routing (FM-active vs. regression guard)

    @Test("FM generates only when it is the preferred tier AND available")
    func fmRoutesWhenPreferredAndAvailable() {
        #expect(
            FoundationModelsInsightRouting.shouldUseFoundationModels(
                preferredTier: .foundationModels,
                foundationModelsState: .available
            ) == true
        )
    }

    @Test("FM does not generate when it is the preferred tier but not available")
    func fmDoesNotRouteWhenPreferredButUnavailable() {
        // The resolver only returns `.foundationModels` when `.available`, but the
        // routing guard double-checks availability so a stale tier never engages
        // an unusable model.
        let unavailable: [LocalAIFoundationModelsTierState] = [
            .unsupported, .deviceNotEligible, .appleIntelligenceNotEnabled, .modelNotReady, .unavailableOther,
        ]
        for state in unavailable {
            #expect(
                FoundationModelsInsightRouting.shouldUseFoundationModels(
                    preferredTier: .foundationModels,
                    foundationModelsState: state
                ) == false
            )
        }
    }

    @Test("Every non-FM preferred tier uses the existing engine even if FM is available")
    func nonFMTiersNeverRouteToFM() {
        // Regression guard: when the resolved tier is anything other than FM, the
        // existing engine generates — regardless of FM availability — so behaviour
        // is byte-identical to today.
        for tier in [LocalAIRuntimeTier.ollama, .naturalLanguage, .heuristic] {
            for state in LocalAIFoundationModelsTierState.allCases {
                #expect(
                    FoundationModelsInsightRouting.shouldUseFoundationModels(
                        preferredTier: tier,
                        foundationModelsState: state
                    ) == false
                )
            }
        }
    }

    // MARK: - Engine selection (the path LocalAIInsightsService actually takes)

    @Test("Selector chooses the FM engine only when FM is wired, preferred, and available")
    func selectorChoosesFMWhenWiredAndActive() {
        #expect(
            FoundationModelsInsightEngineSelector.selectEngine(
                foundationModelsModelWired: true,
                preferredTier: .foundationModels,
                foundationModelsState: .available
            ) == .foundationModels
        )
    }

    @Test("Selector falls back to the existing engine when no FM model is wired")
    func selectorFallsBackWhenFMNotWired() {
        // Even if the tier/state say FM, an unwired engine (older OS / no SDK)
        // must use the existing path — the engine literally cannot be constructed.
        #expect(
            FoundationModelsInsightEngineSelector.selectEngine(
                foundationModelsModelWired: false,
                preferredTier: .foundationModels,
                foundationModelsState: .available
            ) == .existing
        )
    }

    @Test("Selector reproduces today's behavior for every non-active FM combination")
    func selectorRegressionGuard() {
        // The whole matrix that must remain `.existing` (byte-identical to today):
        //  - any non-FM preferred tier, regardless of wiring/state, OR
        //  - FM preferred but not available, OR
        //  - FM not wired.
        for wired in [true, false] {
            for state in LocalAIFoundationModelsTierState.allCases {
                for tier in [LocalAIRuntimeTier.ollama, .naturalLanguage, .heuristic] {
                    #expect(
                        FoundationModelsInsightEngineSelector.selectEngine(
                            foundationModelsModelWired: wired,
                            preferredTier: tier,
                            foundationModelsState: state
                        ) == .existing
                    )
                }
            }

            // FM preferred but unavailable → existing, for every unavailable state.
            for state in LocalAIFoundationModelsTierState.allCases where !state.isAvailable {
                #expect(
                    FoundationModelsInsightEngineSelector.selectEngine(
                        foundationModelsModelWired: wired,
                        preferredTier: .foundationModels,
                        foundationModelsState: state
                    ) == .existing
                )
            }
        }
    }
}
