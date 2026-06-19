import Foundation
import PlaidBarCore

// MARK: - Privacy-mask control command reader (AND-513, Epic E)
//
// The Control Center "Privacy Mask" toggle (PlaidBarWidgetExtension) cannot mutate
// app state directly — it runs in the WidgetKit extension. It instead writes a tiny
// command file to the shared App Group container. This reader is the app-side half:
// it consumes (reads-and-deletes) that command so `AppState` can apply the desired
// mask state.
//
// The JSON contract is the coupling between the two halves, not a shared Swift type
// — the writer (`WidgetControlCommandStore` in the extension) and this reader keep
// independent copies of the same `Codable` shape and the same filename so each ships
// within its own ownership boundary. Keep the two in sync:
//   filename: "privacy-mask-command.json"  ·  fields: { maskEnabled: Bool, requestedAt: Date(iso8601) }
//
// Values only — never tokens or balances.

/// The privacy-mask command requested by the Control Center toggle. Mirrors
/// `PrivacyMaskCommandRequest` in the widget extension target.
struct PrivacyMaskControlCommand: Codable, Sendable, Equatable {
    /// Desired privacy-mask state: `true` hides figures, `false` reveals them.
    let maskEnabled: Bool
    /// When the toggle was flipped, for staleness reasoning.
    let requestedAt: Date
}

/// Reads/consumes the privacy-mask command from the shared App Group container.
enum PrivacyMaskControlCommandReader {
    /// Must match `WidgetControlCommandStore.privacyCommandFilename`.
    static let filename = "privacy-mask-command.json"

    private static var decoder: JSONDecoder {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return decoder
    }

    private static var encoder: JSONEncoder {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = [.sortedKeys]
        return encoder
    }

    /// Resolves the shared command directory, reusing the glance store's
    /// container-or-local-fallback logic so the reader and the control agree on a
    /// single App Group location.
    static func directory(fileManager: FileManager = .default) -> URL {
        GlanceSnapshotStore.snapshotDirectory(fileManager: fileManager)
    }

    static func commandURL(directory: URL) -> URL {
        directory.appendingPathComponent(filename)
    }

    /// Consumes (reads-and-deletes) the pending privacy command, or returns `nil`
    /// when none is pending — so calling it on every app activation is cheap.
    static func consume(
        directory: URL = directory(),
        fileManager: FileManager = .default
    ) throws -> PrivacyMaskControlCommand? {
        let url = commandURL(directory: directory)
        guard fileManager.fileExists(atPath: url.path) else { return nil }
        let data = try Data(contentsOf: url)
        try fileManager.removeItem(at: url)
        return try decoder.decode(PrivacyMaskControlCommand.self, from: data)
    }

    /// Writes a pending privacy command into the shared container so it is applied
    /// on the next `applyPendingPrivacyMaskControlCommand()` activation — the same
    /// channel the Control Center toggle uses (`WidgetControlCommandStore`), but
    /// from the **app** side. The Focus filter intent (AND-506) uses this so it
    /// drives the existing apply path instead of new state machinery. Writes
    /// atomically with owner-only permissions, byte-identical to the extension's
    /// writer so the contract stays in sync.
    static func write(
        _ command: PrivacyMaskControlCommand,
        directory: URL = directory(),
        fileManager: FileManager = .default
    ) throws {
        let url = commandURL(directory: directory)
        try fileManager.createDirectory(
            at: url.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        let data = try encoder.encode(command)
        try data.write(to: url, options: [.atomic])
        #if os(macOS)
        try? fileManager.setAttributes([.posixPermissions: 0o600], ofItemAtPath: url.path)
        #endif
    }
}

// MARK: - AppState integration
//
// `applyPendingPrivacyMaskControlCommand()` is wired into the app's activation
// hook (`PlaidBarApp`'s `didBecomeActive` handler, alongside
// `consumePendingGlanceCommand()`), so the Control Center toggle takes effect the
// next time VaultPeek activates. The privacy control deliberately does NOT open
// the app (silent masking), so it relies on the next natural activation — opening
// the popover, summoning the window, or any focus change — to consume the pending
// command. The reader is consume-and-delete, so a stale file never lingers and
// re-running on every activation is a cheap no-op when nothing is pending.

extension AppState {
    /// Applies a pending Control Center privacy-mask command, if any. Drives the
    /// same `appLockPreferences.privacyMaskEnabled` path as the in-app eye toggle
    /// so persistence, the masked snapshot rewrite, and control reload all happen
    /// through the existing flow. A no-op (returns `false`) when no command is
    /// pending. Skipped while fully locked — App Lock already masks everything and
    /// owns reveal (mirrors `togglePrivacyMask`).
    @discardableResult
    func applyPendingPrivacyMaskControlCommand() -> Bool {
        guard let command = try? PrivacyMaskControlCommandReader.consume() else { return false }
        guard !isContentLocked else { return true }
        if appLockPreferences.privacyMaskEnabled != command.maskEnabled {
            appLockPreferences.privacyMaskEnabled = command.maskEnabled
        }
        return true
    }
}
