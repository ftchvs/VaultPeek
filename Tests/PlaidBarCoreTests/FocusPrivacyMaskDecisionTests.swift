import Foundation
@testable import PlaidBarCore
import Testing

@Suite("Focus-aware Privacy Mask decision (AND-506)")
struct FocusPrivacyMaskDecisionTests {
    @Test("Focus activates with masking on → mask turns on and the prior visible state is remembered")
    func activationFromVisibleEnablesMaskAndRemembers() {
        let outcome = FocusPrivacyMaskDecision.resolve(
            focusActive: true,
            maskWhileFocused: true,
            currentMaskEnabled: false,
            rememberedMask: nil
        )
        #expect(outcome.desiredMaskEnabled == true)
        #expect(outcome.rememberedMask == false)
    }

    @Test("Focus activates while already masked → mask stays on and the prior masked state is remembered")
    func activationWhileAlreadyMaskedRemembersTrue() {
        let outcome = FocusPrivacyMaskDecision.resolve(
            focusActive: true,
            maskWhileFocused: true,
            currentMaskEnabled: true,
            rememberedMask: nil
        )
        #expect(outcome.desiredMaskEnabled == true)
        // So that deactivation restores the user's pre-Focus masked preference.
        #expect(outcome.rememberedMask == true)
    }

    @Test("Repeated activation does not overwrite the originally remembered prior state")
    func repeatedActivationKeepsOriginalPrior() {
        // First activation captured `false` (user was visible). A second perform()
        // call while focused must not clobber it with the now-masked `true`.
        let outcome = FocusPrivacyMaskDecision.resolve(
            focusActive: true,
            maskWhileFocused: true,
            currentMaskEnabled: true,
            rememberedMask: false
        )
        #expect(outcome.desiredMaskEnabled == true)
        #expect(outcome.rememberedMask == false)
    }

    @Test("Focus deactivates → restores the remembered visible state and clears the bookkeeping")
    func deactivationRestoresVisible() {
        let outcome = FocusPrivacyMaskDecision.resolve(
            focusActive: false,
            maskWhileFocused: true,
            currentMaskEnabled: true,
            rememberedMask: false
        )
        #expect(outcome.desiredMaskEnabled == false)
        #expect(outcome.rememberedMask == nil)
    }

    @Test("Focus deactivates → restores a remembered masked preference")
    func deactivationRestoresMaskedPreference() {
        let outcome = FocusPrivacyMaskDecision.resolve(
            focusActive: false,
            maskWhileFocused: true,
            currentMaskEnabled: true,
            rememberedMask: true
        )
        // User had Privacy Mask on before the Focus; keep it on afterwards.
        #expect(outcome.desiredMaskEnabled == true)
        #expect(outcome.rememberedMask == nil)
    }

    @Test("Focus deactivates with no remembered state → reveals (the filter was the only thing masking)")
    func deactivationWithoutMemoryReveals() {
        let outcome = FocusPrivacyMaskDecision.resolve(
            focusActive: false,
            maskWhileFocused: true,
            currentMaskEnabled: true,
            rememberedMask: nil
        )
        #expect(outcome.desiredMaskEnabled == false)
        #expect(outcome.rememberedMask == nil)
    }

    @Test("An inert filter (masking unchecked) never moves the mask and clears any stray memory")
    func inertFilterIsNoOp() {
        // Active focus, but the user did not ask this Focus to mask.
        let active = FocusPrivacyMaskDecision.resolve(
            focusActive: true,
            maskWhileFocused: false,
            currentMaskEnabled: false,
            rememberedMask: true
        )
        #expect(active.desiredMaskEnabled == false)
        #expect(active.rememberedMask == nil)

        // Inactive focus, inert filter, currently masked by the user themselves.
        let inactive = FocusPrivacyMaskDecision.resolve(
            focusActive: false,
            maskWhileFocused: false,
            currentMaskEnabled: true,
            rememberedMask: nil
        )
        #expect(inactive.desiredMaskEnabled == true)
        #expect(inactive.rememberedMask == nil)
    }
}
