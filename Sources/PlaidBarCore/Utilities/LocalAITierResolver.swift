import Foundation

/// The ordered on-device AI tiers VaultPeek can draw on, highest preference
/// first. This is the *generation/preference* order — which on-device facility
/// is the best available producer of insight/categorization output — not a
/// privacy boundary (that stays in `LocalAIRuntimeResolution`).
///
/// AND-563 adds `foundationModels` at the TOP. The lower three rungs are exactly
/// the tiers that existed before:
///   - `ollama`         — the toggle-gated local Ollama insight runtime.
///   - `naturalLanguage`— the always-on zero-setup Apple NaturalLanguage
///                        categorizer (AND-507).
///   - `heuristic`      — deterministic local summaries/totals; always present.
///
/// This issue is detection + ordering only. It does NOT route insight generation
/// through Foundation Models — that wiring is a held follow-up (AND-564/565). The
/// resolver merely reports which tier would be preferred so Settings/status can
/// surface it; the existing generation path is unchanged.
public enum LocalAIRuntimeTier: String, Codable, Sendable, Hashable, CaseIterable {
    case foundationModels
    case ollama
    case naturalLanguage
    case heuristic

    /// Lower rank == higher preference. Stable, test-pinned ordering so the
    /// resolver and any UI agree on "which tier is on top."
    public var rank: Int {
        switch self {
        case .foundationModels: 0
        case .ollama: 1
        case .naturalLanguage: 2
        case .heuristic: 3
        }
    }

    /// Full, user-facing name for Settings copy.
    public var displayName: String {
        switch self {
        case .foundationModels: "Apple Intelligence (Foundation Models)"
        case .ollama: "Local Ollama runtime"
        case .naturalLanguage: "Apple NaturalLanguage (on-device)"
        case .heuristic: "Deterministic local summaries"
        }
    }

    /// Compact label for dense menu/popover status.
    public var shortStatusLabel: String {
        switch self {
        case .foundationModels: "Apple Intelligence"
        case .ollama: "Local Ollama"
        case .naturalLanguage: "On-device NL"
        case .heuristic: "Deterministic"
        }
    }
}

/// Configuration-level availability of Apple Foundation Models, mirroring
/// `SystemLanguageModel.Availability` but as a plain, `Sendable`, OS-independent
/// value so the pure resolver and its tests never touch FoundationModels APIs.
///
/// The app target maps the real `SystemLanguageModel.default.availability` into
/// one of these cases behind `#available(macOS 26, *)` + `canImport`; everywhere
/// else (older OS, no FoundationModels SDK) it stays `.unsupported`.
public enum LocalAIFoundationModelsTierState: String, Codable, Sendable, Hashable, CaseIterable {
    /// Foundation Models cannot be probed on this build/OS (no SDK or < macOS 26).
    case unsupported
    /// The on-device model is available and ready.
    case available
    /// `SystemLanguageModel.Availability.UnavailableReason.deviceNotEligible`.
    case deviceNotEligible
    /// `…UnavailableReason.appleIntelligenceNotEnabled`.
    case appleIntelligenceNotEnabled
    /// `…UnavailableReason.modelNotReady`.
    case modelNotReady
    /// Any other / future unavailability reason.
    case unavailableOther

    /// Only `.available` engages the Foundation Models tier; every other state
    /// (including `.unsupported`) leaves the legacy order untouched.
    public var isAvailable: Bool {
        self == .available
    }

    /// Short remediation cause for Settings, or `nil` when there is nothing the
    /// user can act on (available, or generically unsupported on this OS/build).
    public var causeLabel: String? {
        switch self {
        case .available, .unsupported, .unavailableOther:
            nil
        case .deviceNotEligible:
            "This Mac doesn't support Apple Intelligence"
        case .appleIntelligenceNotEnabled:
            "Apple Intelligence is turned off in System Settings"
        case .modelNotReady:
            "Apple Intelligence model is still preparing"
        }
    }
}

/// The facts the pure tier resolver needs, one boolean-ish per rung. Gathering
/// these (probing FM, checking the Ollama opt-in/liveness, asking whether NL can
/// categorize) happens in the app/Core call sites; the decision itself is pure.
public struct LocalAITierFacts: Sendable, Hashable {
    /// Result of the Foundation Models availability probe (injected from the app).
    public let foundationModels: LocalAIFoundationModelsTierState
    /// True when the opted-in local Ollama runtime is engaged (i.e. the existing
    /// resolution would feed it prompts — `LocalAIRuntimeResolution.usesModel`).
    public let ollamaEngaged: Bool
    /// True when the always-on NaturalLanguage categorizer can run on this build
    /// (i.e. `canImport(NaturalLanguage)` at the call site).
    public let naturalLanguageReady: Bool

    public init(
        foundationModels: LocalAIFoundationModelsTierState,
        ollamaEngaged: Bool,
        naturalLanguageReady: Bool
    ) {
        self.foundationModels = foundationModels
        self.ollamaEngaged = ollamaEngaged
        self.naturalLanguageReady = naturalLanguageReady
    }
}

/// Pure decision: given the per-rung facts, which on-device tier is preferred.
///
/// Foundation Models sits at the top *only* when its probe reports `.available`.
/// For every other FM state the function ignores FM entirely and returns the
/// same tier the runtime resolved before AND-563 — this equivalence is the
/// regression guard the unit tests pin.
public enum LocalAITierResolver {
    public static func resolvePreferredTier(facts: LocalAITierFacts) -> LocalAIRuntimeTier {
        if facts.foundationModels.isAvailable {
            return .foundationModels
        }
        // Legacy order, unchanged by AND-563.
        if facts.ollamaEngaged {
            return .ollama
        }
        if facts.naturalLanguageReady {
            return .naturalLanguage
        }
        return .heuristic
    }
}
