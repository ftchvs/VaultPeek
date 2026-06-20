import Testing
@testable import PlaidBarCore

@Suite("Window chrome glass decision (AND-588 / R-08)")
struct WindowChromeGlassTests {
    // MARK: - chromeBackground(reduceTransparency:)

    @Test("Chrome uses Liquid Glass when transparency is not reduced")
    func usesGlassByDefault() {
        #expect(WindowChromeGlass.chromeBackground(reduceTransparency: false) == .glass)
    }

    @Test("Chrome falls back to a solid background when Reduce Transparency is on")
    func solidUnderReduceTransparency() {
        #expect(WindowChromeGlass.chromeBackground(reduceTransparency: true) == .solid)
    }

    // MARK: - allowsGlass(on:) — chrome-only policy (R-08)

    @Test("Glass is allowed on chrome surfaces")
    func glassAllowedOnChrome() {
        #expect(WindowChromeGlass.allowsGlass(on: .chrome) == true)
    }

    @Test("Glass is never allowed on data surfaces (lists, tables, charts) — R-08")
    func glassForbiddenOnData() {
        #expect(WindowChromeGlass.allowsGlass(on: .data) == false)
    }

    // MARK: - Cross-check against the decorative-effects resolution

    @Test("Reduced decorative-effects preference forces the solid fallback even when the system setting is off")
    func reducedPreferenceForcesSolid() {
        // Mirrors the popover: when the user picks "Reduced" decorative effects,
        // `allowsTexture` is false, which the window modifier maps to
        // reduceTransparency == true → solid chrome.
        let effects = DecorativeEffectsPreference.reduced.resolved(
            systemReduceMotion: false,
            systemReduceTransparency: false
        )
        let reduceTransparency = !effects.allowsTexture
        #expect(reduceTransparency == true)
        #expect(WindowChromeGlass.chromeBackground(reduceTransparency: reduceTransparency) == .solid)
    }

    @Test("System Reduce Transparency forces solid regardless of the app preference")
    func systemSettingWins() {
        for preference in DecorativeEffectsPreference.allCases {
            let effects = preference.resolved(systemReduceMotion: false, systemReduceTransparency: true)
            let reduceTransparency = !effects.allowsTexture
            #expect(reduceTransparency == true)
            #expect(WindowChromeGlass.chromeBackground(reduceTransparency: reduceTransparency) == .solid)
        }
    }

    @Test("With the system setting off and effects allowed (follow-system / on), chrome is glass")
    func glassWhenEffectsAllowed() {
        for preference in [DecorativeEffectsPreference.followSystem, .on] {
            let effects = preference.resolved(systemReduceMotion: false, systemReduceTransparency: false)
            let reduceTransparency = !effects.allowsTexture
            #expect(reduceTransparency == false)
            #expect(WindowChromeGlass.chromeBackground(reduceTransparency: reduceTransparency) == .glass)
        }
    }
}
