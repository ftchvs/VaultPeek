import AppKit
import Foundation
import PlaidBarCore

/// Starts and supervises the `PlaidBarServer` executable bundled inside
/// `PlaidBar.app`, so a drag-installed app works without a manual server step.
///
/// The service only ever manages a server it spawned itself. Externally
/// started servers (Homebrew `plaidbar-run`, `Scripts/run.sh`, manual runs)
/// are detected through an unauthenticated `/health` probe before any spawn
/// decision and left alone.
@MainActor
final class ServerProcessService {
    static let shared = ServerProcessService()

    private(set) var managedProcess: Process?
    private var terminationObserver: NSObjectProtocol?

    var isManagingServer: Bool {
        managedProcess?.isRunning == true
    }

    /// Launches the bundled server when `ServerAutoLaunchPlan` allows it.
    /// Returns `true` when a process was actually started.
    func launchBundledServerIfNeeded(isDemoMode: Bool, serverAlreadyReachable: Bool) -> Bool {
        // A previously managed server that already exited must not block a
        // retry (e.g. it crashed on a bad config the user has since fixed).
        if let process = managedProcess, !process.isRunning {
            managedProcess = nil
        }
        guard managedProcess == nil else { return false }

        let storageDirectory = LocalDataStore.storageDirectoryURL()
        let configFileURL = storageDirectory.appendingPathComponent(LocalDataStore.serverConfigFilename)
        let configFileContents = try? String(contentsOf: configFileURL, encoding: .utf8)
        guard let plan = ServerAutoLaunchPlan.evaluate(
            bundledServerPath: Self.bundledServerExecutablePath(),
            isAppBundle: Self.isRunningFromAppBundle(),
            isDemoMode: isDemoMode,
            serverAlreadyReachable: serverAlreadyReachable,
            dataDirectoryPath: storageDirectory.path,
            configFileExists: FileManager.default.fileExists(atPath: configFileURL.path),
            configFileContents: configFileContents,
            port: PlaidBarConstants.serverPort(environment: ProcessInfo.processInfo.environment),
            parentProcessId: ProcessInfo.processInfo.processIdentifier
        ) else {
            return false
        }

        try? LocalDataStore.prepareStorageDirectory(at: storageDirectory)
        Self.enforcePrivatePermissions(atPath: configFileURL.path)
        Self.enforcePrivatePermissions(atPath: plan.logFilePath)
        let logHandle = Self.makePrivateLogHandle(atPath: plan.logFilePath)

        let process = Process()
        process.executableURL = URL(fileURLWithPath: plan.executablePath)
        process.arguments = plan.arguments
        process.standardInput = FileHandle.nullDevice
        process.standardOutput = logHandle ?? FileHandle.nullDevice
        process.standardError = logHandle ?? FileHandle.nullDevice
        process.terminationHandler = { exited in
            // Clear only the process that exited: a stale handler must never
            // nil out a newer managed server.
            let exitedPid = exited.processIdentifier
            Task { @MainActor in
                let service = ServerProcessService.shared
                if service.managedProcess?.processIdentifier == exitedPid {
                    service.managedProcess = nil
                }
            }
        }

        do {
            try process.run()
        } catch {
            return false
        }

        managedProcess = process
        installTerminationObserverIfNeeded()
        return true
    }

    /// Stops the managed server and relaunches it through a freshly
    /// evaluated `ServerAutoLaunchPlan`. Used when a server that booted
    /// credential-less (setup state) should pick up a newly written
    /// `server.conf`: the server cannot hot-reload credentials, but a managed
    /// restart re-reads the config. Waits for the old process to exit so the
    /// relaunch never races it for the port. Returns `true` when a new
    /// process was started.
    ///
    /// The old process stays referenced as `managedProcess` until its exit is
    /// observed: a server slow to honor SIGTERM still occupies the port, and
    /// dropping the reference early would flip `isManagingServer` to false,
    /// making later credential-upgrade checks skip the retry and leaving the
    /// app stuck in setup state.
    func restartManagedServer(isDemoMode: Bool) async -> Bool {
        if let process = managedProcess, process.isRunning {
            process.terminate()
            for _ in 0 ..< 25 where process.isRunning {
                try? await Task.sleep(for: .milliseconds(200))
            }
            guard !process.isRunning else { return false }
        }
        managedProcess = nil
        return launchBundledServerIfNeeded(
            isDemoMode: isDemoMode,
            serverAlreadyReachable: false
        )
    }

    /// Sends SIGTERM to the managed server so Hummingbird can shut down
    /// gracefully. Safe to call when nothing is managed.
    func terminateManagedServer() {
        guard let process = managedProcess, process.isRunning else {
            managedProcess = nil
            return
        }
        process.terminate()
        managedProcess = nil
    }

    private func installTerminationObserverIfNeeded() {
        guard terminationObserver == nil else { return }
        terminationObserver = NotificationCenter.default.addObserver(
            forName: NSApplication.willTerminateNotification,
            object: nil,
            queue: .main
        ) { _ in
            MainActor.assumeIsolated {
                ServerProcessService.shared.terminateManagedServer()
            }
        }
    }

    private static func isRunningFromAppBundle() -> Bool {
        Bundle.main.bundleURL.pathExtension.lowercased() == "app"
    }

    private static func bundledServerExecutablePath() -> String? {
        guard let url = Bundle.main.url(forAuxiliaryExecutable: "PlaidBarServer"),
              FileManager.default.isExecutableFile(atPath: url.path)
        else {
            return nil
        }
        return url.path
    }

    /// `server.conf` holds Plaid credentials and `server.log` may hold server
    /// diagnostics; both must stay owner-only even if the user created them
    /// with looser permissions.
    private static func enforcePrivatePermissions(atPath path: String) {
        guard FileManager.default.fileExists(atPath: path) else { return }
        try? FileManager.default.setAttributes(
            [.posixPermissions: 0o600],
            ofItemAtPath: path
        )
    }

    /// Opens the server log for appending with owner-only permissions,
    /// matching the repo's private-file conventions for `~/.plaidbar`.
    private static func makePrivateLogHandle(atPath path: String) -> FileHandle? {
        let fileManager = FileManager.default
        if !fileManager.fileExists(atPath: path) {
            fileManager.createFile(
                atPath: path,
                contents: nil,
                attributes: [.posixPermissions: 0o600]
            )
        }
        guard let handle = FileHandle(forWritingAtPath: path) else { return nil }
        handle.seekToEndOfFile()
        return handle
    }
}
