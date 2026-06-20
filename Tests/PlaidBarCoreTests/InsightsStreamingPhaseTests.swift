import Foundation
@testable import PlaidBarCore
import Testing

@Suite("InsightsStreamingPhase Tests")
struct InsightsStreamingPhaseTests {
    @Test("Disabled toggle is always off, regardless of availability")
    func disabledIsOff() {
        for state in [LocalAIAvailabilityState.available, .checking, .unavailable, .disabled] {
            for hasHeadline in [true, false] {
                let phase = InsightsStreamingPhase.resolve(
                    isEnabled: false,
                    availabilityState: state,
                    hasModelGeneratedHeadline: hasHeadline
                )
                #expect(phase == .off)
            }
        }
    }

    @Test("Enabled but service-disabled resolves to off")
    func enabledButServiceDisabled() {
        let phase = InsightsStreamingPhase.resolve(
            isEnabled: true,
            availabilityState: .disabled,
            hasModelGeneratedHeadline: false
        )
        #expect(phase == .off)
    }

    @Test("Enabled but runtime unavailable resolves to unavailable")
    func enabledUnavailable() {
        let phase = InsightsStreamingPhase.resolve(
            isEnabled: true,
            availabilityState: .unavailable,
            hasModelGeneratedHeadline: false
        )
        #expect(phase == .unavailable)
    }

    @Test("Available without a model headline is generating")
    func availableGenerating() {
        let phase = InsightsStreamingPhase.resolve(
            isEnabled: true,
            availabilityState: .available,
            hasModelGeneratedHeadline: false
        )
        #expect(phase == .generating)
        #expect(phase.isWorking)
        #expect(!phase.hasStreamedResult)
    }

    @Test("Checking without a model headline is generating")
    func checkingGenerating() {
        let phase = InsightsStreamingPhase.resolve(
            isEnabled: true,
            availabilityState: .checking,
            hasModelGeneratedHeadline: false
        )
        #expect(phase == .generating)
    }

    @Test("Available with a model headline is streamed")
    func availableStreamed() {
        let phase = InsightsStreamingPhase.resolve(
            isEnabled: true,
            availabilityState: .available,
            hasModelGeneratedHeadline: true
        )
        #expect(phase == .streamed)
        #expect(phase.hasStreamedResult)
        #expect(!phase.isWorking)
    }

    @Test("Every phase carries distinct text + symbol (never color alone)")
    func phasesCarryTextAndSymbol() {
        let phases = InsightsStreamingPhase.allCases
        let labels = Set(phases.map(\.statusLabel))
        let symbols = Set(phases.map(\.systemImage))
        let a11y = Set(phases.map(\.accessibilityLabel))
        // Distinct, non-empty text/symbol/a11y for each phase.
        #expect(labels.count == phases.count)
        #expect(symbols.count == phases.count)
        #expect(a11y.count == phases.count)
        #expect(phases.allSatisfy { !$0.statusLabel.isEmpty })
        #expect(phases.allSatisfy { !$0.systemImage.isEmpty })
        #expect(phases.allSatisfy { !$0.accessibilityLabel.isEmpty })
    }

    @Test("Only the generating phase reports working")
    func onlyGeneratingIsWorking() {
        #expect(InsightsStreamingPhase.generating.isWorking)
        #expect(!InsightsStreamingPhase.off.isWorking)
        #expect(!InsightsStreamingPhase.unavailable.isWorking)
        #expect(!InsightsStreamingPhase.streamed.isWorking)
    }
}
