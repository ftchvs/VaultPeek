import PlaidBarCore
import Testing

@Suite("Haptic feedback policy (AND-576)")
struct HapticFeedbackPolicyTests {
    // MARK: Preference

    @Test("Haptics default to on, opt-out-able")
    func preferenceDefault() {
        #expect(HapticFeedbackPreference.defaultValue == .on)
        #expect(HapticFeedbackPreference.on.isEnabled)
        #expect(!HapticFeedbackPreference.off.isEnabled)
    }

    @Test("Preference round-trips through its storage raw value")
    func preferenceRawValueRoundTrip() {
        for pref in HapticFeedbackPreference.allCases {
            #expect(HapticFeedbackPreference(rawValue: pref.rawValue) == pref)
        }
        #expect(HapticFeedbackPreference(rawValue: "garbage") == nil)
    }

    // MARK: Enabled gate

    @Test("Disabled returns no pattern for every interaction (behavior equals today)")
    func disabledSuppressesAllFeedback() {
        for interaction in HapticInteraction.allCases {
            #expect(HapticFeedbackPolicy.pattern(for: interaction, enabled: false) == nil)
        }
    }

    @Test("Enabled returns the same pattern the unguarded mapping yields")
    func enabledMatchesUnguardedMapping() {
        for interaction in HapticInteraction.allCases {
            #expect(
                HapticFeedbackPolicy.pattern(for: interaction, enabled: true)
                    == HapticFeedbackPolicy.pattern(for: interaction)
            )
        }
    }

    // MARK: Mapping

    @Test("Each interaction maps to its expected pattern")
    func interactionMapping() {
        #expect(HapticFeedbackPolicy.pattern(for: .reviewResolved) == .generic)
        #expect(HapticFeedbackPolicy.pattern(for: .reviewIgnored) == .levelChange)
        #expect(HapticFeedbackPolicy.pattern(for: .toggle) == .levelChange)
        #expect(HapticFeedbackPolicy.pattern(for: .pinToggle) == .alignment)
        #expect(HapticFeedbackPolicy.pattern(for: .reorder) == .alignment)
    }

    @Test("The mapping is total — every interaction yields a non-nil pattern when enabled")
    func mappingIsTotal() {
        for interaction in HapticInteraction.allCases {
            #expect(HapticFeedbackPolicy.pattern(for: interaction, enabled: true) != nil)
        }
    }
}
