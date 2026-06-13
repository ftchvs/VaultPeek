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

    // MARK: Defaults

    @Test("Defaults are the conservative, system-following options")
    func defaults() {
        #expect(AppAppearanceMode.defaultValue == .followSystem)
        #expect(AppContrastPreference.defaultValue == .followSystem)
        #expect(DecorativeEffectsPreference.defaultValue == .followSystem)
        #expect(AppDensityPreference.defaultValue == .comfortable)
    }
}
