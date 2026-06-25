import PlaidBarCore
import Testing

/// Pure preference → accent-swatch mapping for the theme/accent customization
/// feature (AND-647). The accent is decorative/brand only; these tests pin the
/// resolution (including CLI-override precedence and the system-follows default)
/// without touching SwiftUI/AppKit.
@Suite("App accent color resolution")
struct AppAccentColorTests {
    // MARK: Defaults

    @Test("Default accent follows the system accent (no app override)")
    func defaultFollowsSystem() {
        #expect(AppAccentColor.defaultValue == .system)
        #expect(AppAccentColor.system.swatch == nil)
    }

    // MARK: Swatch mapping

    @Test("Every non-system case maps to a concrete sRGB swatch; system maps to nil")
    func swatchPresence() {
        for accent in AppAccentColor.allCases {
            if accent == .system {
                #expect(accent.swatch == nil)
            } else {
                #expect(accent.swatch != nil)
            }
        }
    }

    @Test("Concrete swatches are in-gamut sRGB (0...1 per channel)")
    func swatchComponentsInRange() {
        for accent in AppAccentColor.allCases {
            guard let swatch = accent.swatch else { continue }
            #expect((0.0...1.0).contains(swatch.red))
            #expect((0.0...1.0).contains(swatch.green))
            #expect((0.0...1.0).contains(swatch.blue))
        }
    }

    @Test("Distinct accents produce distinct swatches (no accidental duplicates)")
    func swatchesAreDistinct() {
        let swatches = AppAccentColor.allCases.compactMap(\.swatch)
        // Eight concrete (non-system) accents, all different.
        #expect(swatches.count == AppAccentColor.allCases.count - 1)
        #expect(Set(swatches.map { "\($0.red)-\($0.green)-\($0.blue)" }).count == swatches.count)
    }

    @Test("A representative swatch round-trips its exact components")
    func swatchComponentsExact() {
        #expect(AppAccentColor.blue.swatch == AppAccentSwatch(red: 0.0, green: 0.478, blue: 1.0))
    }

    // MARK: CLI override precedence

    @Test("The accent CLI override wins over the stored choice (mirrors --appearance)")
    func cliOverrideWins() {
        // Override says graphite, stored says blue -> override wins.
        #expect(
            AppAccentColor.resolvedSwatch(cliOverride: .graphite, storedAccent: .blue)
                == AppAccentColor.graphite.swatch
        )
        // No override -> stored choice decides.
        #expect(
            AppAccentColor.resolvedSwatch(cliOverride: nil, storedAccent: .purple)
                == AppAccentColor.purple.swatch
        )
        // Stored "system" with no override -> follow the system accent (nil).
        #expect(AppAccentColor.resolvedSwatch(cliOverride: nil, storedAccent: .system) == nil)
        // Override of "system" also means follow the system accent.
        #expect(AppAccentColor.resolvedSwatch(cliOverride: .system, storedAccent: .red) == nil)
    }

    // MARK: Titles / identifiers / storage

    @Test("Each accent exposes a stable human-readable title")
    func titles() {
        #expect(AppAccentColor.system.title == "System")
        #expect(AppAccentColor.blue.title == "Blue")
        #expect(AppAccentColor.purple.title == "Purple")
        #expect(AppAccentColor.pink.title == "Pink")
        #expect(AppAccentColor.red.title == "Red")
        #expect(AppAccentColor.orange.title == "Orange")
        #expect(AppAccentColor.green.title == "Green")
        #expect(AppAccentColor.teal.title == "Teal")
        #expect(AppAccentColor.graphite.title == "Graphite")
    }

    @Test("Identifiable id mirrors the persisted raw value for every case")
    func identifiersMatchRawValues() {
        for accent in AppAccentColor.allCases { #expect(accent.id == accent.rawValue) }
    }

    @Test("Storage key is namespaced under appearance.* and distinct from siblings")
    func storageKey() {
        #expect(AppAccentColor.storageKey == "appearance.accentColor")
        let keys = Set([
            AppAppearanceMode.storageKey,
            AppContrastPreference.storageKey,
            DecorativeEffectsPreference.storageKey,
            AppDensityPreference.storageKey,
            AppAccentColor.storageKey,
        ])
        #expect(keys.count == 5)
    }

    @Test("Raw values round-trip through the persisted string representation")
    func rawValueRoundTrip() {
        #expect(AppAccentColor(rawValue: "graphite") == .graphite)
        #expect(AppAccentColor(rawValue: "system") == .system)
        #expect(AppAccentColor(rawValue: "nope") == nil)
    }

    @Test("CaseIterable exposes system plus eight concrete accents")
    func caseCount() {
        #expect(AppAccentColor.allCases.count == 9)
    }
}
