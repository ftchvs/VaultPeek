import Testing
@testable import PlaidBarCore

@Suite("SummonHotkeyConfiguration (AND-487)")
struct SummonHotkeyConfigurationTests {

    @Test("Default chord maps to the Carbon V key with cmd+shift modifiers")
    func defaultChordKeyAndModifiers() {
        let config = SummonHotkeyConfiguration.summonDefault
        // kVK_ANSI_V == 0x09
        #expect(config.keyCode == 0x09)
        #expect(config.keyCode == SummonHotkeyConfiguration.keyCodeV)

        let expectedMask = SummonHotkeyConfiguration.cmdKeyMask | SummonHotkeyConfiguration.shiftKeyMask
        #expect(config.modifierFlags == expectedMask)
        // Command and shift bits set, option and control bits clear.
        #expect(config.modifierFlags & SummonHotkeyConfiguration.cmdKeyMask != 0)
        #expect(config.modifierFlags & SummonHotkeyConfiguration.shiftKeyMask != 0)
        #expect(config.modifierFlags & SummonHotkeyConfiguration.optionKeyMask == 0)
        #expect(config.modifierFlags & SummonHotkeyConfiguration.controlKeyMask == 0)
    }

    @Test("Default chord renders the human-readable label")
    func defaultChordDisplayString() {
        #expect(SummonHotkeyConfiguration.summonDefault.displayString == "⇧⌘V")
    }

    @Test("Carbon modifier mask bit values match Carbon constants")
    func modifierMaskBitValues() {
        // These restate <Carbon/Carbon.h> cmdKey/shiftKey/optionKey/controlKey.
        #expect(SummonHotkeyConfiguration.cmdKeyMask == 1 << 8)
        #expect(SummonHotkeyConfiguration.shiftKeyMask == 1 << 9)
        #expect(SummonHotkeyConfiguration.optionKeyMask == 1 << 11)
        #expect(SummonHotkeyConfiguration.controlKeyMask == 1 << 12)
    }
}
