import Testing
@testable import PlaidBarCore

@Suite("App lock settings control policy")
struct AppLockSettingsControlTests {
    @Test("available capability enables the toggle and names the biometry")
    func availableCapabilityEnablesToggle() {
        let control = AppLockSettingsControl.resolve(
            capability: .available(biometry: .touchID),
            isEnabled: false
        )

        #expect(control.isToggleEnabled == true)
        #expect(control.explanation.contains("Touch ID"))
    }

    @Test("enabled state describes the active lock behavior")
    func enabledStateDescribesBehavior() {
        let control = AppLockSettingsControl.resolve(
            capability: .available(biometry: .faceID),
            isEnabled: true
        )

        #expect(control.isToggleEnabled == true)
        #expect(control.explanation.contains("Face ID"))
        #expect(control.explanation.contains("launch"))
    }

    @Test("unavailable capability disables the toggle with a reason")
    func unavailableCapabilityDisablesToggle() {
        let control = AppLockSettingsControl.resolve(
            capability: .unavailable(.biometryNotEnrolled),
            isEnabled: false
        )

        #expect(control.isToggleEnabled == false)
        #expect(control.explanation == AppLockSettingsControl.unavailableReason(.biometryNotEnrolled))
    }

    @Test("biometry names fall back to the Mac password for non-biometric devices")
    func biometryNameFallbacks() {
        #expect(AppLockSettingsControl.biometryName(.touchID) == "Touch ID")
        #expect(AppLockSettingsControl.biometryName(.faceID) == "Face ID")
        #expect(AppLockSettingsControl.biometryName(.opticID) == "Optic ID")
        #expect(AppLockSettingsControl.biometryName(.none) == "your Mac password")
        #expect(AppLockSettingsControl.biometryName(.unknown) == "your Mac password")
    }

    @Test("unknown unavailable reason surfaces a trimmed description or a fallback")
    func unknownReasonHandling() {
        #expect(AppLockSettingsControl.unavailableReason(.unknown("  Boom  ")) == "Boom")
        #expect(AppLockSettingsControl.unavailableReason(.unknown("   ")) == "Authentication is unavailable right now.")
    }
}
