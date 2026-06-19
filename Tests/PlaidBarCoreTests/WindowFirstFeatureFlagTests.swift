import Foundation
import Testing
@testable import PlaidBarCore

@Suite("Window-first feature flag")
struct WindowFirstFeatureFlagTests {
    // MARK: - Default

    @Test("Defaults OFF when neither a CLI override nor a stored preference is set")
    func defaultsOff() {
        #expect(WindowFirstFeatureFlag.defaultValue == false)
        #expect(WindowFirstFeatureFlag.resolve(cliOverrideRaw: nil, storedValue: nil) == false)
    }

    @Test("With no override, the stored preference wins")
    func storedPreferenceWins() {
        #expect(WindowFirstFeatureFlag.resolve(cliOverrideRaw: nil, storedValue: true) == true)
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
        // Falls through to stored value when present, else the OFF default.
        #expect(WindowFirstFeatureFlag.resolve(cliOverrideRaw: "garbage", storedValue: true) == true)
        #expect(WindowFirstFeatureFlag.resolve(cliOverrideRaw: "garbage", storedValue: nil) == false)
    }

    // MARK: - resolved() wiring (UserDefaults + arguments)

    @Test("resolved() returns OFF for an empty store and no CLI flag")
    func resolvedDefaultsOff() {
        let defaults = Self.emptyDefaults()
        #expect(WindowFirstFeatureFlag.resolved(arguments: ["PlaidBar"], defaults: defaults) == false)
    }

    @Test("resolved() reads the stored preference when no CLI flag is present")
    func resolvedReadsStoredPreference() {
        let defaults = Self.emptyDefaults()
        defaults.set(true, forKey: WindowFirstFeatureFlag.storageKey)
        #expect(WindowFirstFeatureFlag.resolved(arguments: ["PlaidBar"], defaults: defaults) == true)
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
