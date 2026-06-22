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

    @Test("The chrome-vs-data glass policy is exhaustive: every surface kind maps to chrome⇒glass / data⇒solid")
    func policyExhaustiveOverAllSurfaceKinds() {
        // Iterate ALL cases so adding a new `WindowSurfaceKind` without an
        // explicit glass decision fails this test (the switch in `allowsGlass`
        // is non-exhaustive at compile time, this guards the runtime contract).
        for surface in WindowSurfaceKind.allCases {
            let allowsGlass = WindowChromeGlass.allowsGlass(on: surface)
            switch surface {
            case .chrome:
                #expect(allowsGlass == true, "Chrome surfaces must be glass-eligible")
            case .data:
                #expect(allowsGlass == false, "Data surfaces must never carry glass (R-08)")
            }
        }
        // Exactly one kind is glass-eligible (chrome), and at least one is not
        // (data) — there is no fallback path that silently solidifies chrome.
        let glassEligible = WindowSurfaceKind.allCases.filter(WindowChromeGlass.allowsGlass(on:))
        #expect(glassEligible == [.chrome])
    }

    @Test("Glass is the unconditional default when transparency is not reduced (no material fallback)")
    func glassIsTheDefault() {
        // With Reduce Transparency off, the chrome is ALWAYS glass — there is no
        // version-gated material fallback (AND-511). Solid is reachable only via
        // the accessibility degradation path.
        #expect(WindowChromeGlass.chromeBackground(reduceTransparency: false) == .glass)
        #expect(WindowChromeGlass.chromeBackground(reduceTransparency: false) != .solid)
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
