import Foundation
import PlaidBarCore

#if canImport(FoundationModels)
import FoundationModels
#endif

/// AND-564: the on-device Foundation Models (Apple Intelligence) insight engine.
///
/// This is the ONLY place that constructs a `LanguageModelSession` and runs
/// guided generation. It conforms to the EXISTING `LocalInsightModel` seam so it
/// drops straight into `LocalInsightModelRuntime.generateSummary` — reusing,
/// unchanged, the redaction-safe prompt (`LocalInsightPromptBuilder`), the output
/// validator (`LocalInsightModelOutputValidator`: no invented figures, no advice,
/// no prompt echo), and the deterministic fallback. Foundation Models therefore
/// gets no privileged path around VaultPeek's privacy + figure-verification
/// guardrails; it is held to exactly the same contract as the Ollama engine.
///
/// Structured output: instead of free-form text we ask the model for a
/// schema-guaranteed `@Generable` value (`GeneratedSpendingInsight`), so there is
/// no brittle string parsing — the headline is always a typed field. We stream
/// the response so a superseded refresh can cancel mid-generation, and map the
/// schema into the Core `FoundationModelsInsightContent` → display string.
///
/// Availability/reversibility: the whole type is gated behind
/// `#available(macOS 26, *)` + `#if canImport(FoundationModels)`. When Foundation
/// Models is not the active/available tier, the routing decision
/// (`FoundationModelsInsightRouting`) never selects this engine and the existing
/// path runs byte-identically. `summarize` additionally re-checks availability
/// and throws `runtimeUnavailable` if the model is not ready, so even a stale
/// route degrades to the deterministic fallback rather than rendering nothing.
struct FoundationModelsInsightModel: LocalInsightModel {
    func summarize(_ prompt: LocalInsightModelPrompt, maxTokens: Int) async throws -> String {
        #if canImport(FoundationModels)
        if #available(macOS 26, *) {
            return try await Self.generate(prompt: prompt, maxTokens: maxTokens)
        } else {
            throw LocalInsightModelError.unsupportedConfiguration
        }
        #else
        throw LocalInsightModelError.unsupportedConfiguration
        #endif
    }
}

#if canImport(FoundationModels)
@available(macOS 26, *)
extension FoundationModelsInsightModel {
    /// The schema-guaranteed spending insight. The system prompt
    /// (`LocalInsightPromptBuilder.systemInstruction`) already forbids advice,
    /// predictions, invented figures, and AI self-disclosure; the `@Guide` copy
    /// here restates the shape so the model fills the single factual headline.
    @Generable
    struct GeneratedSpendingInsight {
        @Guide(
            description: "A one or two sentence factual summary of the user's own spending for the period, using ONLY the provided numbers. No advice, no predictions, no invented merchants or amounts."
        )
        var headline: String
    }

    static func generate(prompt: LocalInsightModelPrompt, maxTokens: Int) async throws -> String {
        // Re-confirm availability at call time. The routing layer already gates on
        // `.available`, but System Settings can change between probe and call, so a
        // stale route must degrade to the deterministic fallback, never error out
        // of the insight surface.
        guard case .available = SystemLanguageModel.default.availability else {
            throw LocalInsightModelError.runtimeUnavailable
        }

        // The redaction-safe system guardrails become the session instructions;
        // the display-safe aggregates become the prompt. Identical inputs to the
        // Ollama engine — same privacy contract.
        let session = LanguageModelSession(instructions: prompt.system)
        let options = GenerationOptions(temperature: 0.2, maximumResponseTokens: max(1, maxTokens))

        do {
            let stream = session.streamResponse(
                to: Prompt(prompt.user),
                generating: GeneratedSpendingInsight.self,
                options: options
            )

            // Single-pass consumption: each snapshot carries the cumulative
            // partially-generated content, so the LAST snapshot holds the final
            // headline. Tracking it as we stream lets generation stop at the next
            // snapshot boundary once this task is cancelled, without depending on a
            // post-iteration `collect()`.
            //
            // NOTE: cancellation here is only responsive when *this* task is
            // cancelled. Today `LocalInsightModelRuntime.withTimeout` runs the
            // model in an unstructured `Task {}` that does not inherit the outer
            // (superseded-refresh) cancellation, so a superseded refresh still runs
            // to the runtime's 8s deadline. The structural fix lives in that shared
            // runtime helper (run the operation as a `withThrowingTaskGroup` child
            // so parent cancellation propagates); see PR follow-up.
            var latestHeadline: String?
            for try await snapshot in stream {
                try Task.checkCancellation()
                // `content.headline` is `String?` while the field streams in.
                latestHeadline = FoundationModelsInsightMapper.partialDisplaySummary(
                    fromHeadline: snapshot.content.headline
                ) ?? latestHeadline
            }

            return FoundationModelsInsightMapper.displaySummary(
                from: FoundationModelsInsightContent(headline: latestHeadline ?? "")
            ) ?? ""
        } catch is CancellationError {
            throw CancellationError()
        } catch let error as LocalInsightModelError {
            throw error
        } catch {
            // Surface a runtime diagnostic; the shared runtime maps this to a
            // `.modelError` fallback and logs it (no transaction data included).
            throw LocalInsightModelError.runtimeUnavailableWithDiagnostic(
                "Foundation Models generation failed: \(String(describing: type(of: error)))."
            )
        }
    }
}
#endif
