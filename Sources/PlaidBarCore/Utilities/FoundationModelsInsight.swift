import Foundation

/// AND-564: the pure, OS-independent pieces of the Foundation Models structured
/// insight path — the schema→display mapping and the "which engine generates
/// this insight" routing decision.
///
/// The live Foundation Models call (an `@Generable` struct streamed through
/// `LanguageModelSession`) lives in the app target behind
/// `#available(macOS 26, *)` + `#if canImport(FoundationModels)`. The app's
/// `@Generable` value maps INTO `FoundationModelsInsightContent` here, so all of
/// the schema-shape-to-display-string logic — and every edge case (empty output,
/// a still-streaming partial) — is testable in `PlaidBarCore` on any OS, without
/// ever touching the FoundationModels SDK.
///
/// Privacy contract: this file performs no I/O and sees no raw identifiers. The
/// FM generator reuses the EXISTING redaction-safe prompt seam
/// (`LocalInsightPromptBuilder`) and the EXISTING output validator
/// (`LocalInsightModelOutputValidator`) by conforming to `LocalInsightModel`, so
/// Foundation Models is held to the same privacy + figure-verification guardrails
/// as the current on-device engines.

/// The structured insight the Foundation Models `@Generable` schema guarantees,
/// lifted into a plain `Sendable` value so the mapping is testable without the
/// SDK. Schema-guaranteed shape means no brittle string parsing: the headline is
/// always a field, the supporting bullets are always a list.
public struct FoundationModelsInsightContent: Sendable, Hashable {
    /// A one-to-two sentence factual spending summary for the window.
    public let headline: String
    /// Optional short supporting points. The runtime currently renders only the
    /// headline (the existing UI shows a single generated summary line plus the
    /// deterministic bullets), but the schema captures bullets so a future UI can
    /// surface them without another model round-trip.
    public let supportingPoints: [String]

    public init(headline: String, supportingPoints: [String] = []) {
        self.headline = headline
        self.supportingPoints = supportingPoints
    }
}

/// Pure mapping from the schema-guaranteed `FoundationModelsInsightContent` to the
/// single display string the existing insight runtime/UI consumes.
///
/// This is deliberately conservative: it ONLY collapses whitespace and joins.
/// Content safety (no invented figures, no advice, no prompt echo) is NOT done
/// here — it is enforced downstream by the shared
/// `LocalInsightModelOutputValidator`, exactly as it is for the Ollama engine, so
/// Foundation Models gets no privileged path around the guardrails.
public enum FoundationModelsInsightMapper {
    /// Produce the display summary string from a (possibly partial) generated
    /// insight.
    ///
    /// Returns `nil` when there is nothing usable yet — an empty/whitespace-only
    /// headline. A `nil` result during streaming means "no displayable text yet";
    /// a `nil` final result means the model produced no headline and the caller
    /// must fall back to the deterministic summary (never render a blank line).
    public static func displaySummary(from content: FoundationModelsInsightContent) -> String? {
        let collapsedHeadline = collapseWhitespace(content.headline)
        guard !collapsedHeadline.isEmpty else { return nil }
        return collapsedHeadline
    }

    /// Map a streaming snapshot whose headline may still be `nil` (the
    /// `PartiallyGenerated` field has not arrived yet). Mirrors
    /// `displaySummary(from:)` but tolerates the not-yet-generated state so the UI
    /// can show progressive text as tokens stream in.
    public static func partialDisplaySummary(fromHeadline headline: String?) -> String? {
        guard let headline else { return nil }
        let collapsed = collapseWhitespace(headline)
        return collapsed.isEmpty ? nil : collapsed
    }

    private static func collapseWhitespace(_ text: String) -> String {
        text
            .components(separatedBy: .whitespacesAndNewlines)
            .filter { !$0.isEmpty }
            .joined(separator: " ")
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }
}

/// Pure decision: which on-device engine should generate this insight.
///
/// Foundation Models generates the insight ONLY when the resolved preferred tier
/// is `.foundationModels` AND its availability state is `.available`. For every
/// other combination the existing engine path is used UNCHANGED — this
/// equivalence is the regression guard the tests pin: when FM is not the active,
/// available tier, behaviour must be byte-identical to today.
public enum FoundationModelsInsightRouting {
    /// `true` ⇢ route generation through the Foundation Models engine.
    /// `false` ⇢ use the existing engine (Ollama / deterministic), unchanged.
    public static func shouldUseFoundationModels(
        preferredTier: LocalAIRuntimeTier,
        foundationModelsState: LocalAIFoundationModelsTierState
    ) -> Bool {
        preferredTier == .foundationModels && foundationModelsState.isAvailable
    }
}

/// Which engine the insight service feeds to the shared generation runtime.
public enum FoundationModelsInsightEngine: String, Sendable, Hashable {
    /// Route through the Foundation Models `@Generable` engine (AND-564).
    case foundationModels
    /// Use the pre-AND-564 path (Ollama when engaged, else the deterministic
    /// fallback inside the runtime). Behaviour here is byte-identical to today.
    case existing
}

/// Pure selection of the generation engine `LocalAIInsightsService` uses, lifted
/// out of the (app-target, untestable-because-`@main`) service so the
/// "FM-active → FM; FM-inactive → existing, unchanged" decision is unit-testable
/// in PlaidBarCore.
///
/// The selection depends only on whether a Foundation Models engine is actually
/// wired (`foundationModelsModelWired`) and whether the routing guard says FM is
/// the active, available tier. When either is false, the result is `.existing` —
/// the regression guard.
public enum FoundationModelsInsightEngineSelector {
    public static func selectEngine(
        foundationModelsModelWired: Bool,
        preferredTier: LocalAIRuntimeTier,
        foundationModelsState: LocalAIFoundationModelsTierState
    ) -> FoundationModelsInsightEngine {
        guard foundationModelsModelWired else { return .existing }
        let useFM = FoundationModelsInsightRouting.shouldUseFoundationModels(
            preferredTier: preferredTier,
            foundationModelsState: foundationModelsState
        )
        return useFM ? .foundationModels : .existing
    }
}
