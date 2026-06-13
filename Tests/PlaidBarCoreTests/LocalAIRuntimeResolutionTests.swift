import Foundation
@testable import PlaidBarCore
import Testing

@Suite("Local AI Runtime Resolution Tests")
struct LocalAIRuntimeResolutionTests {
    // MARK: - Opt-in (privacy boundary)

    @Test("Local AI stays opt-in: unset/disabled/unsupported values never wire a model")
    func optInRequiresExplicitSupportedValue() {
        // The critical case: an unset variable must NOT opt in, so a user who
        // happens to run Ollama on localhost never has finance prompts routed to
        // it without consent.
        #expect(LocalAIRuntimeResolution.isOptedIn(rawValue: nil) == false)
        #expect(LocalAIRuntimeResolution.isOptedIn(rawValue: "") == false)
        #expect(LocalAIRuntimeResolution.isOptedIn(rawValue: "   ") == false)
        #expect(LocalAIRuntimeResolution.isOptedIn(rawValue: "disabled") == false)
        #expect(LocalAIRuntimeResolution.isOptedIn(rawValue: "off") == false)
        #expect(LocalAIRuntimeResolution.isOptedIn(rawValue: "openai") == false)

        // Explicit, supported opt-in (case/whitespace tolerant).
        #expect(LocalAIRuntimeResolution.isOptedIn(rawValue: "ollama") == true)
        #expect(LocalAIRuntimeResolution.isOptedIn(rawValue: "auto") == true)
        #expect(LocalAIRuntimeResolution.isOptedIn(rawValue: "  Ollama ") == true)
    }

    // MARK: - Configured (synchronous) availability

    @Test("Unset runtime resolves to disabled with opt-in guidance")
    func unsetRuntimeIsDisabled() {
        let availability = LocalAIRuntimeResolution.configuredAvailability(
            rawValue: nil,
            hasWiredModel: false,
            endpointIsLocalhost: true
        )
        #expect(availability.state == .disabled)
        #expect(availability.detail.contains(LocalAIRuntimeResolution.optInEnvironmentKey))
    }

    @Test("Opted-in localhost runtime reports checking, never available, until verified")
    func optedInRuntimeReportsChecking() {
        let availability = LocalAIRuntimeResolution.configuredAvailability(
            rawValue: "ollama",
            hasWiredModel: true,
            endpointIsLocalhost: true
        )
        // Liveness is unproven synchronously, so it must not claim availability.
        #expect(availability.state == .checking)
        #expect(availability.runtimeName == "ollama")
    }

    @Test("Opted-in runtime on a non-local endpoint is unavailable")
    func nonLocalEndpointIsUnavailable() {
        let availability = LocalAIRuntimeResolution.configuredAvailability(
            rawValue: "ollama",
            hasWiredModel: false,
            endpointIsLocalhost: false
        )
        #expect(availability.state == .unavailable)
        #expect(availability.detail.lowercased().contains("localhost"))
    }

    @Test("Opted-in runtime that wired no model is unavailable, not checking")
    func optedInWithoutModelIsUnavailable() {
        let availability = LocalAIRuntimeResolution.configuredAvailability(
            rawValue: "ollama",
            hasWiredModel: false,
            endpointIsLocalhost: true
        )
        #expect(availability.state == .unavailable)
    }

    @Test("Unsupported runtime value is disabled with a clear reason")
    func unsupportedRuntimeIsDisabled() {
        let availability = LocalAIRuntimeResolution.configuredAvailability(
            rawValue: "openai",
            hasWiredModel: false,
            endpointIsLocalhost: true
        )
        #expect(availability.state == .disabled)
        #expect(availability.detail.contains("openai"))
    }

    // MARK: - Resolution from a real generation

    @Test("A successful generation upgrades checking to available")
    func successfulGenerationUpgradesToAvailable() {
        let base = LocalAIRuntimeResolution.configuredAvailability(
            rawValue: "ollama",
            hasWiredModel: true,
            endpointIsLocalhost: true
        )
        let resolved = LocalAIRuntimeResolution.resolved(
            base: base,
            usedModelOutput: true,
            fallbackReason: nil
        )
        #expect(resolved.state == .available)
        #expect(resolved.runtimeName == "ollama")
    }

    @Test("A fallback downgrades checking to unavailable with the reason")
    func fallbackDowngradesToUnavailable() {
        let base = LocalAIRuntimeResolution.configuredAvailability(
            rawValue: "ollama",
            hasWiredModel: true,
            endpointIsLocalhost: true
        )
        let resolved = LocalAIRuntimeResolution.resolved(
            base: base,
            usedModelOutput: false,
            fallbackReason: .runtimeUnavailable
        )
        #expect(resolved.state == .unavailable)
        #expect(resolved.detail.contains("not reachable"))
    }

    @Test("Terminal states pass through resolution unchanged")
    func terminalStatesPassThrough() {
        let disabled = LocalAIAvailability(state: .disabled, detail: "off")
        let resolved = LocalAIRuntimeResolution.resolved(
            base: disabled,
            usedModelOutput: true,
            fallbackReason: nil
        )
        #expect(resolved.state == .disabled)
    }

    @Test("Only engaged runtimes feed the model")
    func onlyEngagedRuntimesUseModel() {
        #expect(LocalAIRuntimeResolution.usesModel(for: .checking) == true)
        #expect(LocalAIRuntimeResolution.usesModel(for: .available) == true)
        #expect(LocalAIRuntimeResolution.usesModel(for: .disabled) == false)
        #expect(LocalAIRuntimeResolution.usesModel(for: .unavailable) == false)
    }
}
