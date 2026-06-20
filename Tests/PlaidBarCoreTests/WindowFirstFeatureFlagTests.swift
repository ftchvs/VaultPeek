import Foundation
import Testing
@testable import PlaidBarCore

@Suite("Window-first feature flag")
struct WindowFirstFeatureFlagTests {
    // MARK: - Default

    @Test("Defaults ON when neither a CLI override nor a stored preference is set (AND-616 flip)")
    func defaultsOn() {
        // AND-616 flipped the default: window-first is now the shipping
        // experience; the flag is a hidden escape hatch this stage.
        #expect(WindowFirstFeatureFlag.defaultValue == true)
        #expect(WindowFirstFeatureFlag.resolve(cliOverrideRaw: nil, storedValue: nil) == true)
    }

    @Test("With no override, the stored preference wins (escape hatch can force the popover back)")
    func storedPreferenceWins() {
        #expect(WindowFirstFeatureFlag.resolve(cliOverrideRaw: nil, storedValue: true) == true)
        // A user who explicitly stored OFF keeps the legacy popover even though
        // the default is now ON.
        #expect(WindowFirstFeatureFlag.resolve(cliOverrideRaw: nil, storedValue: false) == false)
    }

    // MARK: - CLI override

    @Test("A parseable CLI override wins over the stored preference", arguments: [
        ("on", true), ("true", true), ("yes", true), ("1", true),
        ("off", false), ("false", false), ("no", false), ("0", false),
        ("ON", true), (" Off ", false),
    ])
    func cliOverrideWins(token: String, expected: Bool) {
        // Override wins regardless of the opposite stored value.
        #expect(WindowFirstFeatureFlag.resolve(cliOverrideRaw: token, storedValue: !expected) == expected)
    }

    @Test("An unparseable or empty CLI override falls through to the stored value / default")
    func unparseableOverrideFallsThrough() {
        #expect(WindowFirstFeatureFlag.parse("maybe") == nil)
        #expect(WindowFirstFeatureFlag.parse("") == nil)
        #expect(WindowFirstFeatureFlag.parse("   ") == nil)
        #expect(WindowFirstFeatureFlag.parse(nil) == nil)
        // Falls through to stored value when present, else the now-ON default.
        #expect(WindowFirstFeatureFlag.resolve(cliOverrideRaw: "garbage", storedValue: false) == false)
        #expect(WindowFirstFeatureFlag.resolve(cliOverrideRaw: "garbage", storedValue: nil) == true)
    }

    // MARK: - resolved() wiring (UserDefaults + arguments)

    @Test("resolved() returns ON for an empty store and no CLI flag (AND-616 flip)")
    func resolvedDefaultsOn() {
        let defaults = Self.emptyDefaults()
        #expect(WindowFirstFeatureFlag.resolved(arguments: ["PlaidBar"], defaults: defaults) == true)
    }

    @Test("resolved() reads the stored preference when no CLI flag is present")
    func resolvedReadsStoredPreference() {
        let defaults = Self.emptyDefaults()
        // The escape hatch: an explicitly-stored OFF still forces the legacy popover.
        defaults.set(false, forKey: WindowFirstFeatureFlag.storageKey)
        #expect(WindowFirstFeatureFlag.resolved(arguments: ["PlaidBar"], defaults: defaults) == false)
    }

    @Test("resolved() lets the CLI flag override the stored preference")
    func resolvedCLIOverridesStore() {
        let defaults = Self.emptyDefaults()
        defaults.set(true, forKey: WindowFirstFeatureFlag.storageKey)
        let args = ["PlaidBar", WindowFirstFeatureFlag.commandLineFlag, "off"]
        #expect(WindowFirstFeatureFlag.resolved(arguments: args, defaults: defaults) == false)
    }

    /// An isolated, empty `UserDefaults` suite so the test never reads or writes
    /// the real `.standard` domain.
    private static func emptyDefaults() -> UserDefaults {
        let suiteName = "WindowFirstFeatureFlagTests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        defaults.removePersistentDomain(forName: suiteName)
        return defaults
    }
}
