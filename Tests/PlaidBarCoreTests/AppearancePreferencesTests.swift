import PlaidBarCore
import Testing

@Suite("Appearance preferences resolution")
struct AppearancePreferencesTests {
    // MARK: Appearance mode

    @Test("Appearance mode maps to a forced scheme; Follow System defers")
    func appearanceModeForcedScheme() {
        #expect(AppAppearanceMode.followSystem.forcedScheme == nil)
        #expect(AppAppearanceMode.light.forcedScheme == .light)
        #expect(AppAppearanceMode.dark.forcedScheme == .dark)
    }

    @Test("The --appearance CLI override wins over the stored mode")
    func cliOverrideWins() {
        // CLI says light, stored says dark -> CLI wins.
        #expect(AppAppearanceMode.resolvedScheme(cliOverride: .light, storedMode: .dark) == .light)
        // No CLI -> stored mode decides.
        #expect(AppAppearanceMode.resolvedScheme(cliOverride: nil, storedMode: .dark) == .dark)
        #expect(AppAppearanceMode.resolvedScheme(cliOverride: nil, storedMode: .followSystem) == nil)
    }

    // MARK: Contrast

    @Test("System Increase Contrast always wins; otherwise the app pref decides")
    func contrastPrecedence() {
        // System on -> always increased, regardless of app pref.
        #expect(AppContrastPreference.standard.resolvedIncreasedContrast(systemIncreaseContrast: true))
        #expect(AppContrastPreference.followSystem.resolvedIncreasedContrast(systemIncreaseContrast: true))
        // System off -> app pref decides.
        #expect(AppContrastPreference.increased.resolvedIncreasedContrast(systemIncreaseContrast: false))
        #expect(!AppContrastPreference.standard.resolvedIncreasedContrast(systemIncreaseContrast: false))
        #expect(!AppContrastPreference.followSystem.resolvedIncreasedContrast(systemIncreaseContrast: false))
    }

    // MARK: Decorative effects

    @Test("Follow System / On allow effects unless the system reduces them")
    func decorativeFollowSystemHonorsSystem() {
        let allOn = DecorativeEffectsPreference.followSystem.resolved(
            systemReduceMotion: false, systemReduceTransparency: false
        )
        #expect(allOn == ResolvedDecorativeEffects(allowsMotion: true, allowsTexture: true))

        // System Reduce Motion gates motion only; texture survives.
        let motionReduced = DecorativeEffectsPreference.on.resolved(
            systemReduceMotion: true, systemReduceTransparency: false
        )
        #expect(motionReduced == ResolvedDecorativeEffects(allowsMotion: false, allowsTexture: true))

        // System Reduce Transparency gates texture only; motion survives.
        let textureReduced = DecorativeEffectsPreference.on.resolved(
            systemReduceMotion: false, systemReduceTransparency: true
        )
        #expect(textureReduced == ResolvedDecorativeEffects(allowsMotion: true, allowsTexture: false))
    }

    @Test("Reduced turns all optional effects off regardless of system state")
    func decorativeReducedForcesOff() {
        let off = DecorativeEffectsPreference.reduced.resolved(
            systemReduceMotion: false, systemReduceTransparency: false
        )
        #expect(off == ResolvedDecorativeEffects(allowsMotion: false, allowsTexture: false))
    }

    @Test("On with both system reduce flags set still suppresses both (system wins)")
    func decorativeOnHonorsBothSystemFlags() {
        let both = DecorativeEffectsPreference.on.resolved(
            systemReduceMotion: true, systemReduceTransparency: true
        )
        #expect(both == ResolvedDecorativeEffects(allowsMotion: false, allowsTexture: false))
    }

    // MARK: Defaults

    @Test("Defaults are the conservative, system-following options")
    func defaults() {
        #expect(AppAppearanceMode.defaultValue == .followSystem)
        #expect(AppContrastPreference.defaultValue == .followSystem)
        #expect(DecorativeEffectsPreference.defaultValue == .followSystem)
        #expect(AppDensityPreference.defaultValue == .comfortable)
    }

    // MARK: Human-readable titles

    @Test("Each preference exposes a stable human-readable title")
    func titles() {
        #expect(AppAppearanceMode.followSystem.title == "Follow System")
        #expect(AppAppearanceMode.light.title == "Light")
        #expect(AppAppearanceMode.dark.title == "Dark")

        #expect(AppContrastPreference.followSystem.title == "Follow System")
        #expect(AppContrastPreference.standard.title == "Standard")
        #expect(AppContrastPreference.increased.title == "Increased")

        #expect(DecorativeEffectsPreference.followSystem.title == "Follow System")
        #expect(DecorativeEffectsPreference.on.title == "On")
        #expect(DecorativeEffectsPreference.reduced.title == "Reduced")

        #expect(AppDensityPreference.comfortable.title == "Comfortable")
        #expect(AppDensityPreference.compact.title == "Compact")
    }

    // MARK: Identifiable + storage keys

    @Test("Identifiable id mirrors the persisted raw value for every case")
    func identifiersMatchRawValues() {
        for mode in AppAppearanceMode.allCases { #expect(mode.id == mode.rawValue) }
        for contrast in AppContrastPreference.allCases { #expect(contrast.id == contrast.rawValue) }
        for effects in DecorativeEffectsPreference.allCases { #expect(effects.id == effects.rawValue) }
        for density in AppDensityPreference.allCases { #expect(density.id == density.rawValue) }
    }

    @Test("Storage keys are namespaced under appearance.* and are distinct")
    func storageKeys() {
        #expect(AppAppearanceMode.storageKey == "appearance.appColorScheme")
        #expect(AppContrastPreference.storageKey == "appearance.contrast")
        #expect(DecorativeEffectsPreference.storageKey == "appearance.decorativeEffects")
        #expect(AppDensityPreference.storageKey == "appearance.density")

        let keys = Set([
            AppAppearanceMode.storageKey,
            AppContrastPreference.storageKey,
            DecorativeEffectsPreference.storageKey,
            AppDensityPreference.storageKey,
        ])
        #expect(keys.count == 4)
    }

    @Test("CaseIterable exposes every option")
    func caseCounts() {
        #expect(AppAppearanceMode.allCases.count == 3)
        #expect(AppContrastPreference.allCases.count == 3)
        #expect(DecorativeEffectsPreference.allCases.count == 3)
        #expect(AppDensityPreference.allCases.count == 2)
    }

    @Test("Raw values round-trip through the persisted string representation")
    func rawValueRoundTrip() {
        #expect(AppAppearanceMode(rawValue: "dark") == .dark)
        #expect(AppContrastPreference(rawValue: "increased") == .increased)
        #expect(DecorativeEffectsPreference(rawValue: "reduced") == .reduced)
        #expect(AppDensityPreference(rawValue: "compact") == .compact)
        #expect(ForcedColorScheme(rawValue: "light") == .light)
    }
}
