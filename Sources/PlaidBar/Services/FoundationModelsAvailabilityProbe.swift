import Foundation
import PlaidBarCore

// Gate on BOTH the framework and its macro module. On a CLT-only macOS 26 you
// can `import FoundationModels` but not `FoundationModelsMacros`, so the
// `@Generable`/`@Guide` macros the categorizers rely on are unavailable even
// though `SystemLanguageModel.default.availability` may report `.available`.
// The merchant/income categorizers already dual-gate on the same condition, so
// matching it here keeps the probe (the single source of truth for the FM tier
// state) from reporting `.available` for a configuration that cannot compile or
// run the macro-backed generation path (AND-656).
#if canImport(FoundationModels) && canImport(FoundationModelsMacros)
import FoundationModels
#endif

/// Detects whether Apple's on-device Foundation Models (Apple Intelligence) is
/// available, mapping the platform `SystemLanguageModel.Availability` into the
/// OS-independent `LocalAIFoundationModelsTierState` the pure tier resolver
/// understands (AND-563).
///
/// This is the ONLY place that touches the FoundationModels framework. It is
/// fully additive and reversible:
///   - When the SDK is absent (`canImport` false) or the OS is older than
///     macOS 26, the probe returns `.unsupported`, so the tier resolver behaves
///     exactly as it did before this type existed.
///   - It performs detection only. It never constructs a session or routes any
///     transaction-derived prompt through Foundation Models — insight generation
///     stays on the existing path until a separate, held follow-up wires it.
///
/// The probe is cheap and synchronous (`SystemLanguageModel.default.availability`
/// is a stored/computed property, not a network or model call), so callers can
/// read it on demand without scheduling work.
struct FoundationModelsAvailabilityProbe: Sendable {
    /// Returns the current Foundation Models availability as a Core tier state.
    ///
    /// Safe to call on any OS/build: returns `.unsupported` whenever Foundation
    /// Models cannot be queried here.
    func currentState() -> LocalAIFoundationModelsTierState {
        #if canImport(FoundationModels) && canImport(FoundationModelsMacros)
        if #available(macOS 26, *) {
            return Self.map(SystemLanguageModel.default.availability)
        } else {
            return .unsupported
        }
        #else
        return .unsupported
        #endif
    }
}

#if canImport(FoundationModels) && canImport(FoundationModelsMacros)
@available(macOS 26, *)
extension FoundationModelsAvailabilityProbe {
    /// Maps `SystemLanguageModel.Availability` to the Core tier state. Unknown or
    /// future unavailability reasons collapse to `.unavailableOther` so new SDK
    /// cases never break the build or silently read as available.
    static func map(_ availability: SystemLanguageModel.Availability) -> LocalAIFoundationModelsTierState {
        switch availability {
        case .available:
            return .available
        case .unavailable(.deviceNotEligible):
            return .deviceNotEligible
        case .unavailable(.appleIntelligenceNotEnabled):
            return .appleIntelligenceNotEnabled
        case .unavailable(.modelNotReady):
            return .modelNotReady
        case .unavailable:
            return .unavailableOther
        }
    }
}
#endif
