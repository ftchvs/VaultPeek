import AppKit
import Carbon.HIToolbox
import OSLog
import PlaidBarCore

/// Registers a single global "summon VaultPeek" hotkey (⇧⌘V, AND-487) via
/// Carbon's `RegisterEventHotKey`. Carbon global hotkeys need no Accessibility
/// entitlement and work in this SwiftPM `.accessory` app, unlike `CGEventTap`.
///
/// Carbon's event handler is a C function pointer that cannot capture Swift
/// state, so the fired closure is held on this `@MainActor` monitor and reached
/// from the trampoline via a process-wide registry keyed by hotkey id. The whole
/// type is main-actor isolated because it touches AppKit and SwiftUI app state.
@MainActor
final class SummonHotkeyMonitor {
    private static let logger = Logger(subsystem: "com.ftchvs.PlaidBar", category: "SummonHotkey")

    /// Unique signature/id for our one hotkey.
    private static let hotKeyID = EventHotKeyID(signature: OSType(0x56504B59 /* "VPKY" */), id: 1)

    /// Trampoline registry: the C callback looks the live handler up here.
    private static var handlers: [UInt32: @MainActor () -> Void] = [:]

    private var hotKeyRef: EventHotKeyRef?
    private var eventHandlerRef: EventHandlerRef?
    private let configuration: SummonHotkeyConfiguration

    init(configuration: SummonHotkeyConfiguration = .summonDefault) {
        self.configuration = configuration
    }

    /// Installs the global hotkey, firing `onSummon` on the main actor when the
    /// chord is pressed. Idempotent: a second call replaces the prior handler.
    func start(onSummon: @escaping @MainActor () -> Void) {
        stop()
        Self.handlers[Self.hotKeyID.id] = onSummon

        // Install the application-wide event handler once per monitor.
        var eventType = EventTypeSpec(
            eventClass: OSType(kEventClassKeyboard),
            eventKind: OSType(kEventHotKeyPressed)
        )
        let installStatus = InstallEventHandler(
            GetApplicationEventTarget(),
            Self.hotKeyEventHandler,
            1,
            &eventType,
            nil,
            &eventHandlerRef
        )
        guard installStatus == noErr else {
            Self.logger.error("InstallEventHandler failed: \(installStatus)")
            Self.handlers[Self.hotKeyID.id] = nil
            return
        }

        let registerStatus = RegisterEventHotKey(
            configuration.keyCode,
            configuration.modifierFlags,
            Self.hotKeyID,
            GetApplicationEventTarget(),
            0,
            &hotKeyRef
        )
        guard registerStatus == noErr else {
            Self.logger.error("RegisterEventHotKey failed: \(registerStatus)")
            stop()
            return
        }
        Self.logger.debug("Summon hotkey \(self.configuration.displayString) registered")
    }

    /// Unregisters the hotkey and tears down the handler. Safe to call repeatedly.
    func stop() {
        if let hotKeyRef {
            UnregisterEventHotKey(hotKeyRef)
            self.hotKeyRef = nil
        }
        if let eventHandlerRef {
            RemoveEventHandler(eventHandlerRef)
            self.eventHandlerRef = nil
        }
        Self.handlers[Self.hotKeyID.id] = nil
    }

    /// Carbon C trampoline: extracts the fired hotkey id and dispatches to the
    /// registered Swift handler. Carbon delivers hotkey events on the main
    /// thread, so hopping to the main actor is a no-op safety assertion.
    private static let hotKeyEventHandler: EventHandlerUPP = { _, event, _ in
        var firedID = EventHotKeyID()
        let status = GetEventParameter(
            event,
            EventParamName(kEventParamDirectObject),
            EventParamType(typeEventHotKeyID),
            nil,
            MemoryLayout<EventHotKeyID>.size,
            nil,
            &firedID
        )
        guard status == noErr else { return status }
        let id = firedID.id
        MainActor.assumeIsolated {
            SummonHotkeyMonitor.handlers[id]?()
        }
        return noErr
    }
}
