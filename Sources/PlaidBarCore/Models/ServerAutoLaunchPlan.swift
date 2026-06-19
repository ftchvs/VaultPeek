import Foundation

/// Decides whether the app should start the `PlaidBarServer` executable that
/// ships inside `VaultPeek.app`, and with what process configuration.
///
/// The plan exists so DMG installs work without a separate server step while
/// developer workflows stay untouched: `swift run`, `Scripts/run.sh`, and any
/// externally managed server all suppress auto-launch.
public struct ServerAutoLaunchPlan: Equatable, Sendable {
    public let executablePath: String
    public let arguments: [String]
    public let logFilePath: String

    public init(executablePath: String, arguments: [String], logFilePath: String) {
        self.executablePath = executablePath
        self.arguments = arguments
        self.logFilePath = logFilePath
    }

    public static let logFilename = "server.log"
    public static let blockedManagedConfigKeys: Set<String> = [
        LocalDataStore.dataDirectoryEnvironmentVariable,
    ]

    /// Returns a launch plan only when every precondition for managing a
    /// bundled server holds:
    /// - the app is running from a real `.app` bundle (not `swift run`),
    /// - the bundle actually contains a `PlaidBarServer` executable,
    /// - no reachable server is already serving the configured port,
    /// - the app is not in demo mode.
    ///
    /// `<data dir>/server.conf` is optional: the server boots credential-less
    /// into a setup state (`/health` and `/api/status` respond, Plaid-backed
    /// routes return 503), so a fresh DMG install can start its server before
    /// any config exists. When `server.conf` is present the plan passes it
    /// via `--config` so the credentials and environment selection configured
    /// there apply to the app-managed server; when it is absent the flag is
    /// omitted and a later restart (re-evaluated through this plan) picks the
    /// file up. Managed launches reject config files that move storage
    /// because the Finder-launched app would otherwise keep reading the
    /// default auth-token path while the server writes elsewhere. The plan
    /// always passes the app's resolved port via `--port` (CLI beats config)
    /// so a `PLAIDBAR_SERVER_PORT` line in `server.conf` cannot start the
    /// server somewhere the app is not listening, and the app's PID via
    /// `--exit-with-parent` so the server never outlives a crashed app.
    public static func evaluate(
        bundledServerPath: String?,
        isAppBundle: Bool,
        isDemoMode: Bool,
        serverAlreadyReachable: Bool,
        dataDirectoryPath: String,
        configFileExists: Bool,
        configFileContents: String? = "",
        port: Int,
        parentProcessId: Int32?
    ) -> ServerAutoLaunchPlan? {
        guard isAppBundle, !isDemoMode, !serverAlreadyReachable else { return nil }
        guard let bundledServerPath, !bundledServerPath.isEmpty else { return nil }

        let normalizedDataDirectory = dataDirectoryPath.hasSuffix("/")
            ? String(dataDirectoryPath.dropLast())
            : dataDirectoryPath

        var arguments: [String] = []
        if configFileExists {
            guard let configFileContents else { return nil }
            if containsBlockedManagedConfigKey(in: configFileContents) {
                return nil
            }
            arguments += ["--config", normalizedDataDirectory + "/" + LocalDataStore.serverConfigFilename]
        }
        arguments += ["--port", String(port)]
        if let parentProcessId {
            arguments += ["--exit-with-parent", String(parentProcessId)]
        }

        return ServerAutoLaunchPlan(
            executablePath: bundledServerPath,
            arguments: arguments,
            logFilePath: normalizedDataDirectory + "/" + logFilename
        )
    }

    public static func containsBlockedManagedConfigKey(in contents: String) -> Bool {
        contents.components(separatedBy: .newlines).contains { rawLine in
            guard let entry = ServerConfigLine.parse(rawLine) else { return false }
            return blockedManagedConfigKeys.contains(entry.key)
        }
    }

    /// Whether the config file would give the server Plaid credentials. A
    /// managed server that booted credential-less is only worth restarting
    /// once this is true; restarting on every config edit would loop when the
    /// file still lacks credentials.
    public static func configProvidesCredentials(in contents: String) -> Bool {
        var values: [String: String] = [:]
        for rawLine in contents.components(separatedBy: .newlines) {
            guard let entry = ServerConfigLine.parse(rawLine) else { continue }
            values[entry.key] = entry.value
        }
        return ["PLAID_CLIENT_ID", "PLAID_SECRET"].allSatisfy { key in
            guard let value = values[key] else { return false }
            return !ServerConfigLine.unquote(value).trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        }
    }
}
