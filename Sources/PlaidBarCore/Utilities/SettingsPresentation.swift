import Foundation

/// Tone for settings status indicators.
///
/// Always paired with an icon and visible text so meaning never relies on
/// color alone (see `ACCESSIBILITY.md`).
public enum SettingsStatusTone: String, Sendable {
    case positive
    case warning
    case secondary
}

/// Maps local AI availability to settings status iconography.
public enum LocalAIAvailabilityPresentation {
    public static func iconName(for state: LocalAIAvailabilityState) -> String {
        switch state {
        case .available: "cpu.fill"
        case .disabled: "pause.circle.fill"
        case .unavailable: "exclamationmark.triangle.fill"
        }
    }

    public static func tone(for state: LocalAIAvailabilityState) -> SettingsStatusTone {
        switch state {
        case .available: .positive
        case .disabled: .secondary
        case .unavailable: .warning
        }
    }
}

/// Builds user-facing copy for the Settings "Local data" section.
public enum LocalDataResetPresentation {
    /// Secondary line under the storage path row: prefers the server-reported
    /// storage path, falling back to the locally resolved default.
    public static func storageDetail(
        serverStoragePath: String?,
        defaultResolvedDisplayPath: String,
        homeDirectory: URL = LocalDataStore.accountHomeDirectoryURL()
    ) -> String {
        if let serverStoragePath {
            let expandedPath = NSString(string: serverStoragePath).expandingTildeInPath
            let displayPath = LocalDataStore.displayPath(
                for: URL(fileURLWithPath: expandedPath),
                homeDirectory: homeDirectory
            )
            return "Server: \(displayPath)"
        }

        return "Default: \(defaultResolvedDisplayPath)"
    }

    /// Result-alert message after a local data reset completes.
    public static func successMessage(
        for result: LocalDataResetResult,
        homeDirectory: URL = LocalDataStore.accountHomeDirectoryURL()
    ) -> String {
        let directoryDisplayPath = LocalDataStore.displayPath(
            for: URL(fileURLWithPath: result.directoryPath, isDirectory: true),
            homeDirectory: homeDirectory
        )
        let keychainText = result.keychainTokensCleared
            ? "Keychain token entries were cleared when present."
            : "Keychain token entries were not cleared."
        let preservationText = result.preservedEntryCount > 0
            ? " Left \(result.preservedEntryCount) config or unrelated item\(result.preservedEntryCount == 1 ? "" : "s") untouched."
            : ""

        if result.removedEntryCount == 0 {
            return "No local data found. \(directoryDisplayPath) is ready. \(keychainText)\(preservationText)"
        }

        return "Removed \(result.removedEntryCount) VaultPeek data item\(result.removedEntryCount == 1 ? "" : "s") from \(directoryDisplayPath). \(keychainText)\(preservationText) Restart the VaultPeek companion server."
    }
}
