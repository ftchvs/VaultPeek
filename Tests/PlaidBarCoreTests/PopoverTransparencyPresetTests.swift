import PlaidBarCore
import Testing

@Suite("Popover transparency presets")
struct PopoverTransparencyPresetTests {
    @Test("Presets map to the anchor values within the legible range")
    func presetValues() {
        #expect(PopoverTransparencySetting.Preset.solid.value == PopoverTransparencySetting.minimumValue)
        #expect(PopoverTransparencySetting.Preset.balanced.value == PopoverTransparencySetting.defaultValue)
        #expect(PopoverTransparencySetting.Preset.glass.value == PopoverTransparencySetting.maximumValue)
        for preset in PopoverTransparencySetting.Preset.allCases {
            #expect(preset.value >= PopoverTransparencySetting.minimumValue)
            #expect(preset.value <= PopoverTransparencySetting.maximumValue)
        }
    }

    @Test("A value on a preset highlights that preset")
    func matchingPresetOnAnchor() {
        #expect(PopoverTransparencySetting(value: PopoverTransparencySetting.minimumValue).matchingPreset == .solid)
        #expect(PopoverTransparencySetting(value: PopoverTransparencySetting.defaultValue).matchingPreset == .balanced)
        #expect(PopoverTransparencySetting(value: PopoverTransparencySetting.maximumValue).matchingPreset == .glass)
    }

    @Test("A fine-tuned value off any preset highlights none")
    func noMatchingPresetOffAnchor() {
        // 50 sits between solid (20) and balanced (70) — a custom, non-preset value.
        #expect(PopoverTransparencySetting(value: 50).matchingPreset == nil)
    }

    @Test("Preset titles are stable and human-readable")
    func presetTitles() {
        #expect(PopoverTransparencySetting.Preset.solid.title == "Solid")
        #expect(PopoverTransparencySetting.Preset.balanced.title == "Balanced")
        #expect(PopoverTransparencySetting.Preset.glass.title == "Glass")
    }
}
