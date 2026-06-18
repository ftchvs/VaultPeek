import Foundation

/// Pure, AppKit-free description of the global "summon VaultPeek" hotkey
/// (AND-487). For v1 the chord is fixed to ⇧⌘V — there is no key recorder, so
/// this type carries only the Carbon key code, the modifier mask, and a
/// human-readable label, all unit-testable without AppKit/Carbon.
///
/// The actual `RegisterEventHotKey` glue lives in `SummonHotkeyMonitor`
/// (app target); this stays in Core so the key mapping and the displayed
/// label never disagree and can be verified in isolation.
public struct SummonHotkeyConfiguration: Equatable, Sendable {
    /// Carbon virtual key code (`kVK_*`). `0x09` is the ANSI "V" key.
    public let keyCode: UInt32
    /// Carbon modifier mask bits (`cmdKey`/`shiftKey`/`optionKey`/`controlKey`).
    public let modifierFlags: UInt32
    /// Human-readable chord, e.g. "⇧⌘V", using the canonical macOS symbol order.
    public let displayString: String

    public init(keyCode: UInt32, modifierFlags: UInt32, displayString: String) {
        self.keyCode = keyCode
        self.modifierFlags = modifierFlags
        self.displayString = displayString
    }

    // Carbon modifier mask bit values (from <Carbon/Carbon.h>), restated here so
    // Core does not import Carbon. The app-side monitor uses the same constants.
    public static let cmdKeyMask: UInt32 = 1 << 8
    public static let shiftKeyMask: UInt32 = 1 << 9
    public static let optionKeyMask: UInt32 = 1 << 11
    public static let controlKeyMask: UInt32 = 1 << 12

    /// Carbon virtual key code for the ANSI "V" key (`kVK_ANSI_V`).
    public static let keyCodeV: UInt32 = 0x09

    /// The fixed v1 chord: ⇧⌘V.
    public static let summonDefault = SummonHotkeyConfiguration(
        keyCode: keyCodeV,
        modifierFlags: cmdKeyMask | shiftKeyMask,
        displayString: "⇧⌘V"
    )
}
