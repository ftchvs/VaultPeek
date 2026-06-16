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

/// User-facing remediation buckets for the optional Local AI runtime.
///
/// `LocalAIAvailability` intentionally stays small and stable; this helper keeps
/// the view-layer copy centralized so Settings and the popover do not drift.
public enum LocalAIRemediationCategory: String, Sendable {
    case none
    case disabled
    case checking
    case noInstalledModel
    case runtimeUnavailable
    case unsupportedConfiguration
    case modelError
}

/// Maps local AI availability to settings status iconography.
public enum LocalAIAvailabilityPresentation {
    public static func iconName(for state: LocalAIAvailabilityState) -> String {
        switch state {
        case .available: "cpu.fill"
        case .disabled: "pause.circle.fill"
        case .unavailable: "exclamationmark.triangle.fill"
        case .checking: "hourglass"
        }
    }

    public static func tone(for state: LocalAIAvailabilityState) -> SettingsStatusTone {
        switch state {
        case .available: .positive
        case .disabled: .secondary
        case .unavailable: .warning
        case .checking: .secondary
        }
    }

    public static func remediationCategory(for availability: LocalAIAvailability) -> LocalAIRemediationCategory {
        switch availability.state {
        case .available:
            return .none
        case .disabled:
            let normalizedDetail = availability.detail.lowercased()
            if normalizedDetail.contains("not supported") || normalizedDetail.contains("non-local endpoint") {
                return .unsupportedConfiguration
            }
            return .disabled
        case .checking:
            return .checking
        case .unavailable:
            break
        }

        let normalizedDetail = "\(availability.detail) \(availability.probeErrorText ?? "")"
            .lowercased()
        if normalizedDetail.contains("no installed local model") {
            return .noInstalledModel
        }
        if normalizedDetail.contains("non-local endpoint")
            || normalizedDetail.contains("unsupported local endpoint")
            || normalizedDetail.contains("not supported")
            || normalizedDetail.contains("no model adapter")
        {
            return .unsupportedConfiguration
        }
        if normalizedDetail.contains("not reachable")
            || normalizedDetail.contains("timed out")
            || normalizedDetail.contains("could not connect")
            || normalizedDetail.contains("connection refused")
        {
            return .runtimeUnavailable
        }
        if normalizedDetail.contains("returned an error")
            || normalizedDetail.contains("invalid or unsafe output")
        {
            return .modelError
        }
        return .runtimeUnavailable
    }

    public static func settingsLabel(for availability: LocalAIAvailability) -> String {
        switch remediationCategory(for: availability) {
        case .none:
            return "Available"
        case .disabled:
            return "Disabled"
        case .checking:
            return "Checking…"
        case .noInstalledModel:
            return "Model Missing"
        case .runtimeUnavailable:
            return "Ollama Offline"
        case .unsupportedConfiguration:
            return "Needs Setup"
        case .modelError:
            return "Model Error"
        }
    }

    public static func popoverLabel(for availability: LocalAIAvailability) -> String {
        switch remediationCategory(for: availability) {
        case .none:
            return "Local On"
        case .disabled:
            return "Local Off"
        case .checking:
            return "Checking…"
        case .noInstalledModel:
            return "No Model"
        case .runtimeUnavailable:
            return "Local Offline"
        case .unsupportedConfiguration:
            return "Needs Setup"
        case .modelError:
            return "Local Error"
        }
    }

    public static func causeLabel(for availability: LocalAIAvailability) -> String? {
        switch remediationCategory(for: availability) {
        case .none, .disabled, .checking:
            return nil
        case .noInstalledModel:
            return "No local model installed"
        case .runtimeUnavailable:
            return "Ollama not reachable"
        case .unsupportedConfiguration:
            return "Unsupported local setup"
        case .modelError:
            return "Probe returned an error"
        }
    }

    public static func helpText(for availability: LocalAIAvailability) -> String {
        switch remediationCategory(for: availability) {
        case .none, .disabled, .checking:
            return availability.detail
        case .noInstalledModel:
            return "Install a local Ollama model to enable on-device summaries. \(availability.detail)"
        case .runtimeUnavailable:
            return "Start Ollama, then retry. \(availability.detail)"
        case .unsupportedConfiguration:
            return "Open Local AI settings to review the unsupported configuration. \(availability.detail)"
        case .modelError:
            return "Retry the local model probe or inspect the exact error in Settings. \(availability.detail)"
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
