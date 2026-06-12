import Testing
@testable import PlaidBarCore

@Suite("Popover transparency settings")
struct PopoverTransparencyTests {
    @Test("Defaults preserve the current legible glass opacity")
    func defaultOpacityPreservesCurrentLook() {
        let setting = PopoverTransparencySetting(value: PopoverTransparencySetting.defaultValue)

        #expect(setting.value == 70)
        #expect(setting.materialOverlayOpacity == 0.12)
        #expect(setting.displayPercent == 70)
    }

    @Test("Values are clamped to the legibility floor and opacity ceiling")
    func valuesClampToLegibilityRange() {
        #expect(PopoverTransparencySetting(value: -50).value == 20)
        #expect(PopoverTransparencySetting(value: 150).value == 85)
    }

    @Test("Higher transparency lowers the solid overlay")
    func higherTransparencyLowersSolidOverlay() {
        let lessTransparent = PopoverTransparencySetting(value: 20)
        let moreTransparent = PopoverTransparencySetting(value: 85)

        #expect(lessTransparent.materialOverlayOpacity > moreTransparent.materialOverlayOpacity)
        #expect(lessTransparent.materialOverlayOpacity == 0.32)
        #expect(moreTransparent.materialOverlayOpacity == 0.06)
    }
}
