import Foundation

/// The display phase for the **Insights** destination's streaming spending-insight
/// surface (Epic 7 / AND-585).
///
/// The Foundation Models `@Generable` insight is produced asynchronously: the
/// service first returns a deterministic, on-device fallback headline (so the
/// surface is never blank), then — when the FM/Ollama runtime is engaged — streams
/// a model-generated headline that replaces it. This pure enum reduces the three
/// observable inputs (the AI toggle, the runtime availability, and whether a
/// model-generated headline has landed yet) into the single state the view
/// renders, so the "off-by-default / generating / streamed" UX policy is
/// unit-testable without the app target (CLAUDE.md) and the view stays a thin
/// renderer.
///
/// AI is **off by default**: with the toggle off the phase is ``off`` and the
/// surface shows only the visible enable affordance — no model is ever invoked
/// (the consent contract, AND-564). Every phase is conveyed by text + SF Symbol,
/// never color alone (ACCESSIBILITY.md).
public enum InsightsStreamingPhase: String, Sendable, Equatable, CaseIterable {
    /// AI is disabled (the default). Nothing is generated; the view offers to
    /// enable it and explains that everything stays on-device.
    case off
    /// AI is enabled but the local runtime is not usable (no model installed /
    /// Apple Intelligence not enabled / runtime offline). The view shows the
    /// deterministic local summary and the remediation hint — there is no cloud
    /// fallback.
    case unavailable
    /// AI is enabled and the runtime is reachable, but a model-generated headline
    /// has not arrived yet — the on-device model is still producing it. The view
    /// shows the deterministic headline with a "generating on-device" indicator
    /// that resolves into the streamed result.
    case generating
    /// A model-generated headline has streamed in. The view shows it as the
    /// finished insight.
    case streamed

    /// Derive the phase from the live observable inputs.
    ///
    /// - Parameters:
    ///   - isEnabled: the AI toggle (`AppState.localAIEnabled`). Off ⇒ ``off``.
    ///   - availabilityState: the resolved local-AI availability state.
    ///   - hasModelGeneratedHeadline: whether the primary summary's
    ///     `generatedSummary` is non-empty, i.e. a model (not the deterministic
    ///     fallback) produced it.
    public static func resolve(
        isEnabled: Bool,
        availabilityState: LocalAIAvailabilityState,
        hasModelGeneratedHeadline: Bool
    ) -> InsightsStreamingPhase {
        guard isEnabled else { return .off }

        switch availabilityState {
        case .disabled:
            // Enabled toggle but the service reports disabled (e.g. preference
            // race during a rebuild) — treat as off-equivalent for the surface.
            return .off
        case .unavailable:
            return .unavailable
        case .available, .checking:
            return hasModelGeneratedHeadline ? .streamed : .generating
        }
    }

    /// Whether the on-device model is actively working — the cue the view animates
    /// (a non-looping, Reduce-Motion-aware indicator).
    public var isWorking: Bool { self == .generating }

    /// Whether a finished, model-generated insight is being shown.
    public var hasStreamedResult: Bool { self == .streamed }

    /// SF Symbol for the phase's status pill (shape distinguishes it, not just
    /// tint — ACCESSIBILITY.md).
    public var systemImage: String {
        switch self {
        case .off: "sparkles"
        case .unavailable: "exclamationmark.triangle"
        case .generating: "wand.and.stars"
        case .streamed: "checkmark.seal"
        }
    }

    /// Short visible status label that backs up the icon and tint.
    public var statusLabel: String {
        switch self {
        case .off: "AI off"
        case .unavailable: "Runtime unavailable"
        case .generating: "Generating on-device"
        case .streamed: "On-device summary"
        }
    }

    /// VoiceOver-friendly sentence describing the phase, so the state is spoken
    /// rather than implied by the indicator.
    public var accessibilityLabel: String {
        switch self {
        case .off:
            "Local AI insights are off. Everything stays on this Mac when enabled."
        case .unavailable:
            "Local AI is enabled but the on-device runtime is unavailable. Showing the deterministic local summary."
        case .generating:
            "Generating a spending insight on-device."
        case .streamed:
            "On-device spending insight ready."
        }
    }
}
