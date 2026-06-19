import Foundation
import PlaidBarCore

// MARK: - Widget control command bridge (AND-513, Epic E)
//
// The macOS 26 Control Center controls (Refresh balances, Privacy Mask toggle)
// cannot mutate app state directly — a control runs in the WidgetKit extension,
// not the app process. They instead drop a tiny *command* file in the shared App
// Group container, then nudge the app (via `openAppWhenRun` / activation) which
// consumes the file and performs the work.
//
// The existing `GlanceSnapshotStore.saveCommand` / `consumeCommand` pair (Epic D,
// PlaidBarCore) carries the refresh command. This file adds a sibling channel for
// the **privacy-mask** command using a distinct filename so the two control
// surfaces never clobber one another, and so it can ship entirely within the
// Epic E ownership boundary without editing the shared `GlanceCommand` enum.
//
// Values only — never tokens or balances. The file holds a single bool intent.

/// A privacy-mask command requested by the Control Center toggle.
struct PrivacyMaskCommandRequest: Codable, Sendable, Equatable {
    /// Desired privacy-mask state: `true` hides figures, `false` reveals them.
    let maskEnabled: Bool
    /// When the toggle was flipped, for cooldown / staleness reasoning app-side.
    let requestedAt: Date
}

/// Reads/writes the privacy-mask command in the shared App Group container.
///
/// Mirrors `GlanceSnapshotStore`'s container resolution and atomic, owner-only
/// (`0o600`) write. The control is the only **writer**; the app is the only
/// **reader** (it consumes-and-deletes on activation).
enum WidgetControlCommandStore {
    /// Distinct from `GlanceSnapshot.commandFilename` so the privacy command and
    /// the refresh command coexist without overwriting each other.
    static let privacyCommandFilename = "privacy-mask-command.json"

    private static var encoder: JSONEncoder {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = [.sortedKeys]
        return encoder
    }

    private static var decoder: JSONDecoder {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return decoder
    }

    /// Resolves the shared command directory, reusing the glance store's
    /// container-or-local-fallback logic so all sharing surfaces agree on a
    /// single App Group location.
    static func directory(fileManager: FileManager = .default) -> URL {
        GlanceSnapshotStore.snapshotDirectory(fileManager: fileManager)
    }

    static func privacyCommandURL(directory: URL) -> URL {
        directory.appendingPathComponent(privacyCommandFilename)
    }

    /// Writes the privacy command (control side). Creates the directory if needed
    /// and writes atomically with owner-only permissions.
    static func savePrivacyCommand(
        _ request: PrivacyMaskCommandRequest,
        directory: URL = directory(),
        fileManager: FileManager = .default
    ) throws {
        let url = privacyCommandURL(directory: directory)
        try fileManager.createDirectory(
            at: url.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        let data = try encoder.encode(request)
        try data.write(to: url, options: [.atomic])
        #if os(macOS)
        try? fileManager.setAttributes([.posixPermissions: 0o600], ofItemAtPath: url.path)
        #endif
    }

    /// Consumes (reads-and-deletes) the privacy command (app side). Returns `nil`
    /// when no command is pending so calling it on every activation is cheap.
    static func consumePrivacyCommand(
        directory: URL = directory(),
        fileManager: FileManager = .default
    ) throws -> PrivacyMaskCommandRequest? {
        let url = privacyCommandURL(directory: directory)
        guard fileManager.fileExists(atPath: url.path) else { return nil }
        let data = try Data(contentsOf: url)
        try fileManager.removeItem(at: url)
        return try decoder.decode(PrivacyMaskCommandRequest.self, from: data)
    }
}
