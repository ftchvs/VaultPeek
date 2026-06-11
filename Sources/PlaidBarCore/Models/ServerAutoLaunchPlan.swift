import Foundation

/// Decides whether the app should start the `PlaidBarServer` executable that
/// ships inside `PlaidBar.app`, and with what process configuration.
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

    /// Returns a launch plan only when every precondition for managing a
    /// bundled server holds:
    /// - the app is running from a real `.app` bundle (not `swift run`),
    /// - the bundle actually contains a `PlaidBarServer` executable,
    /// - no reachable server is already serving the configured port,
    /// - the app is not in demo mode,
    /// - `<data dir>/server.conf` exists.
    ///
    /// The config file is a hard requirement because the server refuses to
    /// boot without Plaid credentials: spawning it credential-less would just
    /// crash-loop. Without `server.conf`, first launch stays serverless and
    /// the app offers demo mode and setup guidance instead. The plan passes
    /// the config via `--config` so the credentials and environment selection
    /// configured there apply to the app-managed server, and the app's PID
    /// via `--exit-with-parent` so the server never outlives a crashed app.
    public static func evaluate(
        bundledServerPath: String?,
        isAppBundle: Bool,
        isDemoMode: Bool,
        serverAlreadyReachable: Bool,
        dataDirectoryPath: String,
        configFileExists: Bool,
        parentProcessId: Int32?
    ) -> ServerAutoLaunchPlan? {
        guard isAppBundle, !isDemoMode, !serverAlreadyReachable, configFileExists else { return nil }
        guard let bundledServerPath, !bundledServerPath.isEmpty else { return nil }

        let normalizedDataDirectory = dataDirectoryPath.hasSuffix("/")
            ? String(dataDirectoryPath.dropLast())
            : dataDirectoryPath

        var arguments = ["--config", normalizedDataDirectory + "/" + LocalDataStore.serverConfigFilename]
        if let parentProcessId {
            arguments += ["--exit-with-parent", String(parentProcessId)]
        }

        return ServerAutoLaunchPlan(
            executablePath: bundledServerPath,
            arguments: arguments,
            logFilePath: normalizedDataDirectory + "/" + logFilename
        )
    }
}
