import PlaidBarCore
import Testing

@Suite("In-app text size preference (AND-570)")
struct TextSizePreferenceTests {
    // MARK: Case → Dynamic Type mapping

    @Test("Each case maps to the expected Dynamic Type step")
    func mapsToExpectedStep() {
        #expect(TextSizePreference.default.forcedDynamicTypeSize == .large)
        #expect(TextSizePreference.large.forcedDynamicTypeSize == .xLarge)
        #expect(TextSizePreference.xLarge.forcedDynamicTypeSize == .xxLarge)
        #expect(TextSizePreference.accessibility.forcedDynamicTypeSize == .accessibility1)
    }

    @Test("Larger preferences map to monotonically larger Dynamic Type ranks")
    func mappingIsMonotonic() {
        let ordered: [TextSizePreference] = [.default, .large, .xLarge, .accessibility]
        let ranks = ordered.map(\.forcedDynamicTypeSize.rank)
        #expect(ranks == ranks.sorted())
        // And strictly increasing: no two preferences collapse to one step.
        #expect(Set(ranks).count == ranks.count)
    }

    // MARK: Default

    @Test("Default preference is the macOS-standard (.default → .large) size")
    func defaultIsStandard() {
        #expect(TextSizePreference.defaultValue == .default)
        #expect(TextSizePreference.defaultValue.forcedDynamicTypeSize == .large)
        #expect(ForcedDynamicTypeSize.large.rank == 0)
    }

    // MARK: CLI override precedence

    @Test("The --text-size CLI override wins over the stored preference")
    func cliOverrideWins() {
        // Override says accessibility, stored says default → override wins.
        #expect(
            TextSizePreference.resolved(cliOverride: .accessibility, storedPreference: .default)
                == .accessibility1
        )
        // No override → stored preference decides.
        #expect(
            TextSizePreference.resolved(cliOverride: nil, storedPreference: .xLarge) == .xxLarge
        )
        #expect(
            TextSizePreference.resolved(cliOverride: nil, storedPreference: .default) == .large
        )
    }

    // MARK: Persistence round-trip

    @Test("Raw values are stable and round-trip through the persisted string")
    func rawValueRoundTrip() {
        // Stable persisted identifiers — changing these would silently reset
        // every user's stored choice on upgrade.
        #expect(TextSizePreference.default.rawValue == "default")
        #expect(TextSizePreference.large.rawValue == "large")
        #expect(TextSizePreference.xLarge.rawValue == "xLarge")
        #expect(TextSizePreference.accessibility.rawValue == "accessibility")

        for preference in TextSizePreference.allCases {
            #expect(TextSizePreference(rawValue: preference.rawValue) == preference)
        }
    }

    @Test("ForcedDynamicTypeSize raw values mirror the SwiftUI case names")
    func forcedRawValuesMirrorSwiftUI() {
        #expect(ForcedDynamicTypeSize.large.rawValue == "large")
        #expect(ForcedDynamicTypeSize.xLarge.rawValue == "xLarge")
        #expect(ForcedDynamicTypeSize.xxLarge.rawValue == "xxLarge")
        #expect(ForcedDynamicTypeSize.accessibility1.rawValue == "accessibility1")
    }

    @Test("An unknown persisted raw value decodes to nil (caller falls back to default)")
    func unknownRawValueIsNil() {
        #expect(TextSizePreference(rawValue: "humongous") == nil)
    }

    // MARK: Identifiable + storage key

    @Test("Identifiable id mirrors the persisted raw value for every case")
    func identifiersMatchRawValues() {
        for preference in TextSizePreference.allCases {
            #expect(preference.id == preference.rawValue)
        }
    }

    @Test("Storage key is namespaced under appearance.* and distinct from siblings")
    func storageKey() {
        #expect(TextSizePreference.storageKey == "appearance.textSize")
        // Distinct from the other appearance.* keys so it never collides.
        let siblings = Set([
            AppAppearanceMode.storageKey,
            AppContrastPreference.storageKey,
            DecorativeEffectsPreference.storageKey,
            AppDensityPreference.storageKey,
            PopoverTransparencySetting.storageKey,
        ])
        #expect(!siblings.contains(TextSizePreference.storageKey))
    }

    @Test("CaseIterable exposes every option")
    func caseCount() {
        #expect(TextSizePreference.allCases.count == 4)
        #expect(ForcedDynamicTypeSize.allCases.count == 4)
    }

    // MARK: Human-readable labels

    @Test("Each preference exposes a stable, non-empty title and detail")
    func labels() {
        #expect(TextSizePreference.default.title == "Default")
        #expect(TextSizePreference.large.title == "Large")
        #expect(TextSizePreference.xLarge.title == "Extra Large")
        #expect(TextSizePreference.accessibility.title == "Accessibility")

        for preference in TextSizePreference.allCases {
            #expect(!preference.title.isEmpty)
            #expect(!preference.detail.isEmpty)
        }
    }
}
