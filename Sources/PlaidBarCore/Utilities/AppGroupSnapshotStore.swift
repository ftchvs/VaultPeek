import Foundation

/// Reads and writes the shared ``FinanceSnapshot`` in the App Group container so
/// App Intents (Spotlight / Siri / Shortcuts) and extensions can answer finance
/// queries without touching the local server, Plaid, or any credential (AND-512).
///
/// Mirrors ``GlanceSnapshotStore``: the same container-URL-or-local-fallback
/// resolution and the same atomic, owner-only (`0o600`) JSON write, but a
/// distinct filename (``FinanceSnapshot/filename``) so the App Intents payload
/// never collides with the glance widget snapshot.
///
/// - The app is the only **writer** (`save`).
/// - Intents / extensions are **readers** (`load`).
/// Values only — never tokens or secrets. See ``FinanceSnapshot``.
public enum AppGroupSnapshotStore {
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

    /// Resolves the App Group container directory, falling back to the local
    /// data store directory when the group container is unavailable (e.g. an
    /// unsigned SwiftPM build or tests). Matches ``GlanceSnapshotStore``.
    public static func snapshotDirectory(
        fileManager: FileManager = .default,
        appGroupIdentifier: String = FinanceSnapshot.appGroupIdentifier
    ) -> URL {
        if let url = fileManager.containerURL(forSecurityApplicationGroupIdentifier: appGroupIdentifier) {
            return url
        }
        return LocalDataStore.storageDirectoryURL()
    }

    public static func snapshotURL(directory: URL) -> URL {
        directory.appendingPathComponent(FinanceSnapshot.filename)
    }

    /// Writes the snapshot (app side). Creates the container directory if needed
    /// and writes atomically with owner-only permissions.
    public static func save(
        _ snapshot: FinanceSnapshot,
        directory: URL = snapshotDirectory(),
        fileManager: FileManager = .default
    ) throws {
        let url = snapshotURL(directory: directory)
        try fileManager.createDirectory(
            at: url.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        let data = try encoder.encode(snapshot)
        try data.write(to: url, options: [.atomic])
        #if os(macOS)
        try? fileManager.setAttributes([.posixPermissions: 0o600], ofItemAtPath: url.path)
        #endif
    }

    /// Reads the snapshot (intent / extension side). Throws when no snapshot has
    /// been written yet so callers can present a setup state.
    public static func load(
        directory: URL = snapshotDirectory(),
        fileManager: FileManager = .default
    ) throws -> FinanceSnapshot {
        let data = try Data(contentsOf: snapshotURL(directory: directory))
        return try decoder.decode(FinanceSnapshot.self, from: data)
    }

    /// Non-throwing read used by intents: returns `nil` when no snapshot exists
    /// or it cannot be decoded.
    public static func loadIfAvailable(
        directory: URL = snapshotDirectory(),
        fileManager: FileManager = .default
    ) -> FinanceSnapshot? {
        try? load(directory: directory, fileManager: fileManager)
    }

    public static func clear(
        directory: URL = snapshotDirectory(),
        fileManager: FileManager = .default
    ) throws {
        let url = snapshotURL(directory: directory)
        if fileManager.fileExists(atPath: url.path) {
            try fileManager.removeItem(at: url)
        }
    }
}
