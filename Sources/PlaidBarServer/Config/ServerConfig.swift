import Foundation
import PlaidBarCore
#if canImport(Darwin)
import Darwin
#endif
#if canImport(Security)
import Security
#endif

struct ServerConfig: Sendable {
    static let legacyDatabaseFilename = "plaidbar.sqlite"
    static let legacyMigrationEnvironmentVariable = "PLAIDBAR_MIGRATE_LEGACY_DATABASE"
    static let pendingLinkSessionsFilename = "pending-link-sessions.json"
    // Shared with LocalDataStore so the reset boundary clears this exact file.
    static let linkClientUserIdFilename = LocalDataStore.linkClientUserIdFilename
    private static let sqliteSidecarSuffixes = ["-wal", "-shm", "-journal"]

    let port: Int
    let plaidEnvironment: PlaidEnvironment
    let plaidClientId: String
    let plaidSecret: String
    let databasePath: String
    let pendingLinkSessionsPath: String
    let redirectUri: String
    let oauthRedirect: OAuthRedirectConfiguration
    let authToken: String
    let linkClientUserId: String
    let link: PlaidLinkConfiguration

    /// Deployment posture. `load` resolves it from config/env, defaulting to
    /// `.local` (today's BYO-keys behavior). `.hostedBridge` is inert
    /// foundation — see `DeploymentMode`. Declared without a stored default so
    /// it stays part of the implicit memberwise initializer; `load` is the only
    /// construction site and always supplies it.
    let deployment: DeploymentMode

    /// Placeholder hosted-bridge config. `.unconfigured` in `.local` mode and
    /// until the bridge is provisioned. Nothing dials these endpoints yet.
    let remoteBridge: RemoteBridgeConfig

    var dataDirectoryPath: String {
        URL(fileURLWithPath: databasePath)
            .deletingLastPathComponent()
            .path
    }

    var plaidBaseURL: String {
        switch plaidEnvironment {
        case .sandbox: "https://sandbox.plaid.com"
        case .production: "https://production.plaid.com"
        }
    }

    /// `false` means the server is in a credential-less setup state: it boots
    /// and serves `/health` and `/api/status`, but Plaid-backed routes return
    /// 503 until credentials are configured and the server restarts. This is
    /// what lets a fresh DMG install auto-start its bundled server before
    /// `server.conf` exists.
    var credentialsConfigured: Bool {
        credentialDiagnosis.isConfigured
    }

    /// Which credential is missing (if any), so setup-state responses and
    /// the boot log can name the exact variable to fix.
    var credentialDiagnosis: CredentialSetupDiagnosis {
        .diagnose(clientId: plaidClientId, secret: plaidSecret)
    }

    static func load(
        from configPath: String? = nil,
        portOverride: Int? = nil,
        sandboxOverride: Bool? = nil
    ) throws -> ServerConfig {
        // Validate the explicit `--port` override before any filesystem work so
        // an out-of-range value cannot create the data dir, write the auth-token
        // file, or trigger migrations. The env-var/default path is already
        // clamped by PlaidBarConstants.serverPort(environment:).
        if let portOverride, !(1...65_535).contains(portOverride) {
            throw ServerConfigError.invalidPort(portOverride)
        }

        let environmentValues = try resolvedEnvironment(from: configPath)

        // The standalone `--config` path consumes a server.conf that may hold
        // PLAID_CLIENT_ID/PLAID_SECRET; tighten it to owner-only the same way
        // app-managed launches do (ServerProcessService.enforcePrivatePermissions).
        // This must run before any further validation that can throw (e.g. Link
        // config resolution), otherwise an invalid setting could abort startup
        // and leave a secret-bearing server.conf at its original loose mode.
        tightenConfigFilePermissions(at: configPath)

        let link = try PlaidLinkConfiguration.resolved(from: environmentValues)

        if environmentValues[LocalDataStore.dataDirectoryEnvironmentVariable]?.trimmedNonEmpty == nil {
            try LocalDataStore.migrateLegacyDefaultStorageIfNeeded()
        }
        let dataDir = dataDirectory(environment: environmentValues)
        try FileManager.default.createDirectory(
            atPath: dataDir,
            withIntermediateDirectories: true
        )
        try FileManager.default.setAttributes(
            [.posixPermissions: 0o700],
            ofItemAtPath: dataDir
        )

        let environment = try plaidEnvironment(
            from: environmentValues,
            sandboxOverride: sandboxOverride
        )

        // Missing credentials are not a boot failure: the server starts in a
        // setup state so a fresh install can probe /health and /api/status
        // before any credentials exist. Plaid-backed routes refuse to run
        // until both values are present.
        let clientId = environmentValues["PLAID_CLIENT_ID"]?.trimmedNonEmpty ?? ""
        let secret = environmentValues["PLAID_SECRET"]?.trimmedNonEmpty ?? ""

        let authTokenURL = LocalDataStore.authTokenURL(
            in: URL(fileURLWithPath: dataDir, isDirectory: true)
        )
        let authToken = try loadOrCreateAuthToken(at: authTokenURL)
        let linkClientUserId = try loadOrCreateLinkClientUserId(in: dataDir)

        let resolvedPort = portOverride ?? PlaidBarConstants.serverPort(environment: environmentValues)

        // Deployment seam: read from config/env, defaulting to `.local` so
        // today's BYO-keys behavior is byte-for-byte unchanged. `.hostedBridge`
        // is inert foundation; the bridge placeholder holds no live endpoints
        // until the owner provisions them (see consumer-production-checklist.md).
        let deployment = DeploymentMode.resolved(from: environmentValues)
        let remoteBridge = RemoteBridgeConfig.resolved(from: environmentValues)
        if deployment == .hostedBridge, link.webhookURL == nil {
            throw ServerConfigError.missingManagedLinkWebhookURL
        }
        let oauthRedirect = try OAuthRedirectConfiguration.resolved(
            from: environmentValues,
            deployment: deployment,
            plaidEnvironment: environment,
            port: resolvedPort
        )

        return ServerConfig(
            port: resolvedPort,
            plaidEnvironment: environment,
            plaidClientId: clientId,
            plaidSecret: secret,
            databasePath: try databasePathForStartup(
                in: dataDir,
                environment: environment,
                legacyMigrationEnvironment: try legacyMigrationEnvironment(from: environmentValues)
            ),
            pendingLinkSessionsPath: URL(fileURLWithPath: dataDir, isDirectory: true)
                .appendingPathComponent(pendingLinkSessionsFilename)
                .path,
            redirectUri: oauthRedirect.uri,
            oauthRedirect: oauthRedirect,
            authToken: authToken,
            linkClientUserId: linkClientUserId,
            link: link,
            deployment: deployment,
            remoteBridge: remoteBridge
        )
    }

    static func authTokenString(randomBytes bytes: [UInt8]) -> String {
        Data(bytes)
            .base64EncodedString()
            .replacingOccurrences(of: "+", with: "-")
            .replacingOccurrences(of: "/", with: "_")
            .replacingOccurrences(of: "=", with: "")
    }

    private static func generateAuthToken() throws -> String {
        authTokenString(randomBytes: try secureRandomBytes(count: 32))
    }

    private static func secureRandomBytes(count: Int) throws -> [UInt8] {
        var bytes = [UInt8](repeating: 0, count: count)
        #if canImport(Security)
        let result = SecRandomCopyBytes(kSecRandomDefault, bytes.count, &bytes)
        guard result == errSecSuccess else {
            // Fail loudly rather than silently downgrading to UUID-derived
            // material: the auth token is the only thing guarding /api, so a
            // CSPRNG failure must be surfaced, not masked by a weaker fallback.
            throw ServerConfigError.secureRandomUnavailable(status: result)
        }
        return bytes
        #else
        throw ServerConfigError.secureRandomUnavailable(status: nil)
        #endif
    }

    private static func loadOrCreateAuthToken(at url: URL) throws -> String {
        if let existing = try? String(contentsOf: url, encoding: .utf8)
            .trimmingCharacters(in: .whitespacesAndNewlines),
            !existing.isEmpty
        {
            try FileManager.default.setAttributes(
                [.posixPermissions: 0o600],
                ofItemAtPath: url.path
            )
            return existing
        }

        let generated = try generateAuthToken()
        try writePrivateTextFile(generated, to: url)
        return generated
    }

    private static func loadOrCreateLinkClientUserId(in dataDir: String) throws -> String {
        let url = URL(fileURLWithPath: dataDir, isDirectory: true)
            .appendingPathComponent(linkClientUserIdFilename)
        if let existing = try? String(contentsOf: url, encoding: .utf8)
            .trimmingCharacters(in: .whitespacesAndNewlines),
            isValidStoredLinkClientUserId(existing)
        {
            try FileManager.default.setAttributes(
                [.posixPermissions: 0o600],
                ofItemAtPath: url.path
            )
            return existing
        }

        let generated = "vaultpeek-install-\(authTokenString(randomBytes: try secureRandomBytes(count: 32)))"
        try writePrivateTextFile(generated, to: url)
        return generated
    }

    static func isValidStoredLinkClientUserId(_ value: String) -> Bool {
        value.hasPrefix("vaultpeek-install-")
            && value.count == "vaultpeek-install-".count + 43
            && value.allSatisfy { character in
                character.isLetter || character.isNumber || character == "-" || character == "_"
            }
    }

    private static func writePrivateTextFile(_ value: String, to url: URL) throws {
        let data = Data(value.utf8)

        #if canImport(Darwin)
        let temporaryURL = url
            .deletingLastPathComponent()
            .appendingPathComponent(".\(url.lastPathComponent).\(UUID().uuidString).tmp")
        let descriptor = open(
            temporaryURL.path,
            O_WRONLY | O_CREAT | O_EXCL,
            S_IRUSR | S_IWUSR
        )
        guard descriptor >= 0 else {
            throw POSIXError(POSIXErrorCode(rawValue: errno) ?? .EIO)
        }
        var shouldRemoveTemporaryFile = true
        defer {
            close(descriptor)
            if shouldRemoveTemporaryFile {
                try? FileManager.default.removeItem(at: temporaryURL)
            }
        }

        try data.withUnsafeBytes { buffer in
            guard let baseAddress = buffer.baseAddress else { return }
            var bytesWritten = 0
            while bytesWritten < buffer.count {
                let result = write(
                    descriptor,
                    baseAddress.advanced(by: bytesWritten),
                    buffer.count - bytesWritten
                )
                if result < 0 {
                    if errno == EINTR { continue }
                    throw POSIXError(POSIXErrorCode(rawValue: errno) ?? .EIO)
                }
                guard result > 0 else {
                    throw POSIXError(.EIO)
                }
                bytesWritten += result
            }
        }

        guard rename(temporaryURL.path, url.path) == 0 else {
            throw POSIXError(POSIXErrorCode(rawValue: errno) ?? .EIO)
        }
        shouldRemoveTemporaryFile = false
        #else
        try data.write(to: url, options: [.atomic])
        #endif

        try FileManager.default.setAttributes(
            [.posixPermissions: 0o600],
            ofItemAtPath: url.path
        )
    }

    private static func createPrivateEmptyFile(
        at path: String,
        fileManager: FileManager
    ) throws {
        #if canImport(Darwin)
        let descriptor = open(path, O_WRONLY | O_CREAT | O_EXCL, S_IRUSR | S_IWUSR)
        if descriptor >= 0 {
            close(descriptor)
            return
        }
        if errno == EEXIST {
            return
        }
        throw POSIXError(POSIXErrorCode(rawValue: errno) ?? .EIO)
        #else
        guard fileManager.createFile(atPath: path, contents: Data()) else {
            throw CocoaError(.fileWriteUnknown)
        }
        try fileManager.setAttributes(
            [.posixPermissions: 0o600],
            ofItemAtPath: path
        )
        #endif
    }

    static func dataDirectory() -> String {
        dataDirectory(environment: ProcessInfo.processInfo.environment)
    }

    static func dataDirectory(environment: [String: String]) -> String {
        LocalDataStore.storageDirectoryURL(environment: environment).path
    }

    static func databaseFilename(for environment: PlaidEnvironment) -> String {
        "plaidbar-\(environment.rawValue).sqlite"
    }

    static func databasePath(in dataDir: String, environment: PlaidEnvironment) -> String {
        URL(fileURLWithPath: dataDir, isDirectory: true)
            .appendingPathComponent(databaseFilename(for: environment))
            .path
    }

    static func databasePathForStartup(
        in dataDir: String,
        environment: PlaidEnvironment,
        legacyMigrationEnvironment: PlaidEnvironment? = nil,
        fileManager: FileManager = .default
    ) throws -> String {
        let scopedPath = databasePath(in: dataDir, environment: environment)
        let legacyPath = URL(fileURLWithPath: dataDir, isDirectory: true)
            .appendingPathComponent(legacyDatabaseFilename)
            .path
        guard fileManager.fileExists(atPath: legacyPath) else { return scopedPath }

        let isReplacingScopedStore = fileManager.fileExists(atPath: scopedPath)
        if isReplacingScopedStore {
            guard legacyMigrationEnvironment == environment else { return scopedPath }
            guard !fileManager.fileExists(
                atPath: legacyMigrationMarkerPath(for: scopedPath)
            ) else {
                return scopedPath
            }
        }

        guard shouldMigrateLegacyDatabase(
            in: dataDir,
            environment: environment,
            legacyPath: legacyPath,
            legacyMigrationEnvironment: legacyMigrationEnvironment,
            fileManager: fileManager
        ) else {
            return scopedPath
        }

        if isReplacingScopedStore {
            try replaceScopedStoreWithLegacy(
                in: dataDir,
                environment: environment,
                legacyPath: legacyPath,
                scopedPath: scopedPath,
                fileManager: fileManager
            )
        } else {
            try installLegacyStoreIntoEmptyScopedPath(
                in: dataDir,
                environment: environment,
                legacyDatabasePath: legacyPath,
                scopedDatabasePath: scopedPath,
                fileManager: fileManager
            )
        }
        return scopedPath
    }

    static func enforcePrivateSQLiteStorePermissions(
        at path: String,
        fileManager: FileManager = .default
    ) throws {
        for storePath in sqliteStorePaths(for: path, fileManager: fileManager) {
            try fileManager.setAttributes(
                [.posixPermissions: 0o600],
                ofItemAtPath: storePath
            )
        }
    }

    static func preparePrivateSQLiteStoreForOpen(
        at path: String,
        fileManager: FileManager = .default
    ) throws {
        let directoryPath = URL(fileURLWithPath: path)
            .deletingLastPathComponent()
            .path
        try fileManager.createDirectory(
            atPath: directoryPath,
            withIntermediateDirectories: true
        )
        try fileManager.setAttributes(
            [.posixPermissions: 0o700],
            ofItemAtPath: directoryPath
        )

        if !fileManager.fileExists(atPath: path) {
            try createPrivateEmptyFile(at: path, fileManager: fileManager)
        }

        try enforcePrivateSQLiteStorePermissions(at: path, fileManager: fileManager)
    }

    private static func legacyMigrationEnvironment(
        from environmentValues: [String: String]
    ) throws -> PlaidEnvironment? {
        guard let value = environmentValues[legacyMigrationEnvironmentVariable]?.trimmedNonEmpty else {
            return nil
        }
        guard let environment = PlaidEnvironment(rawValue: value) else {
            throw ServerConfigError.invalidEnvironmentVariable(
                legacyMigrationEnvironmentVariable,
                value
            )
        }
        return environment
    }

    private static func plaidEnvironment(
        from environmentValues: [String: String],
        sandboxOverride: Bool?
    ) throws -> PlaidEnvironment {
        if let sandboxOverride {
            return sandboxOverride ? .sandbox : .production
        }

        guard let value = environmentValues["PLAID_ENV"]?.trimmedNonEmpty else {
            return .production
        }
        guard let environment = PlaidEnvironment(rawValue: value) else {
            throw ServerConfigError.invalidEnvironmentVariable("PLAID_ENV", value)
        }
        return environment
    }

    private static func resolvedEnvironment(from configPath: String?) throws -> [String: String] {
        var environmentValues = ProcessInfo.processInfo.environment
        guard let configPath = configPath?.trimmedNonEmpty else {
            return environmentValues
        }

        let configValues = try loadConfigFile(at: configPath)
        for (key, value) in configValues {
            environmentValues[key] = value
        }
        return environmentValues
    }

    /// Tightens a user-supplied config file to owner-only (`0o600`) so a
    /// `server.conf` created with loose `0644` shell permissions cannot leak
    /// Plaid credentials to other local users. Best-effort: a chmod failure
    /// must not turn into a boot failure (matches the app-managed helper in
    /// ServerProcessService.enforcePrivatePermissions). `nil`/blank paths and
    /// missing files are no-ops; the path is tilde-expanded to match
    /// `loadConfigFile`.
    private static func tightenConfigFilePermissions(at configPath: String?) {
        guard let configPath = configPath?.trimmedNonEmpty else { return }
        let expandedPath = NSString(string: configPath).expandingTildeInPath
        guard FileManager.default.fileExists(atPath: expandedPath) else { return }
        try? FileManager.default.setAttributes(
            [.posixPermissions: 0o600],
            ofItemAtPath: expandedPath
        )
    }

    private static func loadConfigFile(at path: String) throws -> [String: String] {
        let expandedPath = NSString(string: path).expandingTildeInPath
        let contents = try String(
            contentsOfFile: expandedPath,
            encoding: .utf8
        )
        var values: [String: String] = [:]

        for (offset, rawLine) in contents.components(separatedBy: .newlines).enumerated() {
            switch ServerConfigLine.classify(rawLine) {
            case .ignored:
                continue
            case .malformed:
                throw ServerConfigError.invalidConfigLine(path: expandedPath, line: offset + 1)
            case let .pair(key, value):
                values[key] = ServerConfigLine.unquote(value)
            }
        }

        return values
    }

    private static func shouldMigrateLegacyDatabase(
        in dataDir: String,
        environment: PlaidEnvironment,
        legacyPath: String,
        legacyMigrationEnvironment: PlaidEnvironment?,
        fileManager: FileManager
    ) -> Bool {
        if let legacyMigrationEnvironment {
            return legacyMigrationEnvironment == environment
        }

        let otherEnvironment: PlaidEnvironment = environment == .sandbox ? .production : .sandbox
        let currentCacheExists = legacyTransactionCacheExists(
            in: dataDir,
            environment: environment,
            legacyPath: legacyPath,
            fileManager: fileManager
        )
        let otherCacheExists = legacyTransactionCacheExists(
            in: dataDir,
            environment: otherEnvironment,
            legacyPath: legacyPath,
            fileManager: fileManager
        )
        return currentCacheExists && !otherCacheExists
    }

    private static func legacyTransactionCacheExists(
        in dataDir: String,
        environment: PlaidEnvironment,
        legacyPath: String,
        fileManager: FileManager
    ) -> Bool {
        let directory = URL(fileURLWithPath: dataDir, isDirectory: true)
        let context = TransactionCacheContext(environment: environment, storagePath: legacyPath)
        return fileManager.fileExists(
            atPath: LocalDataStore.transactionCacheURL(in: directory, context: context).path
        )
    }

    private static func copyLegacySQLiteStore(
        from legacyPath: String,
        to scopedPath: String,
        fileManager: FileManager
    ) throws {
        var copiedPaths: [String] = []

        do {
            try fileManager.copyItem(atPath: legacyPath, toPath: scopedPath)
            copiedPaths.append(scopedPath)

            for suffix in sqliteSidecarSuffixes {
                let sourcePath = legacyPath + suffix
                guard fileManager.fileExists(atPath: sourcePath) else { continue }

                let destinationPath = scopedPath + suffix
                try fileManager.copyItem(atPath: sourcePath, toPath: destinationPath)
                copiedPaths.append(destinationPath)
            }
        } catch {
            for path in copiedPaths {
                try? fileManager.removeItem(atPath: path)
            }
            throw error
        }
    }

    private static func replaceScopedStoreWithLegacy(
        in dataDir: String,
        environment: PlaidEnvironment,
        legacyPath: String,
        scopedPath: String,
        fileManager: FileManager
    ) throws {
        let stagingPath = availableSQLiteStagingPath(for: scopedPath, fileManager: fileManager)
        var storeBackupPath: String?
        var cacheBackupPath: String?

        do {
            try copyLegacySQLiteStore(from: legacyPath, to: stagingPath, fileManager: fileManager)
            storeBackupPath = try moveSQLiteStoreAside(at: scopedPath, fileManager: fileManager)
            cacheBackupPath = try moveTransactionCacheAside(
                in: dataDir,
                environment: environment,
                scopedDatabasePath: scopedPath,
                fileManager: fileManager
            )
            try moveSQLiteStore(from: stagingPath, to: scopedPath, fileManager: fileManager)
            copyLegacyTransactionCache(
                in: dataDir,
                environment: environment,
                legacyDatabasePath: legacyPath,
                scopedDatabasePath: scopedPath,
                fileManager: fileManager
            )
            try writeLegacyMigrationMarker(
                for: scopedPath,
                environment: environment,
                fileManager: fileManager
            )
        } catch {
            try? removeSQLiteStore(at: scopedPath, fileManager: fileManager)
            try? removeTransactionCache(
                in: dataDir,
                environment: environment,
                scopedDatabasePath: scopedPath,
                fileManager: fileManager
            )
            if let storeBackupPath {
                try? moveSQLiteStore(from: storeBackupPath, to: scopedPath, fileManager: fileManager)
            }
            if let cacheBackupPath {
                try? moveTransactionCache(
                    from: cacheBackupPath,
                    in: dataDir,
                    environment: environment,
                    scopedDatabasePath: scopedPath,
                    fileManager: fileManager
                )
            }
            try? removeSQLiteStore(at: stagingPath, fileManager: fileManager)
            throw error
        }
    }

    private static func installLegacyStoreIntoEmptyScopedPath(
        in dataDir: String,
        environment: PlaidEnvironment,
        legacyDatabasePath: String,
        scopedDatabasePath: String,
        fileManager: FileManager
    ) throws {
        let stagingPath = availableSQLiteStagingPath(
            for: scopedDatabasePath,
            fileManager: fileManager
        )

        do {
            try copyLegacySQLiteStore(
                from: legacyDatabasePath,
                to: stagingPath,
                fileManager: fileManager
            )
            try writeLegacyMigrationMarker(
                for: scopedDatabasePath,
                environment: environment,
                fileManager: fileManager
            )
            try moveSQLiteStore(
                from: stagingPath,
                to: scopedDatabasePath,
                fileManager: fileManager
            )
            copyLegacyTransactionCache(
                in: dataDir,
                environment: environment,
                legacyDatabasePath: legacyDatabasePath,
                scopedDatabasePath: scopedDatabasePath,
                fileManager: fileManager
            )
        } catch {
            try? removeSQLiteStore(at: stagingPath, fileManager: fileManager)
            if !fileManager.fileExists(atPath: scopedDatabasePath) {
                try? fileManager.removeItem(
                    atPath: legacyMigrationMarkerPath(for: scopedDatabasePath)
                )
            }
            throw error
        }
    }

    private static func moveSQLiteStoreAside(
        at path: String,
        fileManager: FileManager
    ) throws -> String {
        let backupPath = availableSQLiteBackupPath(for: path, fileManager: fileManager)
        try moveSQLiteStore(from: path, to: backupPath, fileManager: fileManager)
        return backupPath
    }

    private static func moveSQLiteStore(
        from path: String,
        to destinationPath: String,
        fileManager: FileManager
    ) throws {
        for storePath in sqliteStorePaths(for: path, fileManager: fileManager) {
            let suffix = String(storePath.dropFirst(path.count))
            try fileManager.moveItem(atPath: storePath, toPath: destinationPath + suffix)
        }
    }

    private static func removeSQLiteStore(
        at path: String,
        fileManager: FileManager
    ) throws {
        for storePath in sqliteStorePaths(for: path, fileManager: fileManager) {
            try fileManager.removeItem(atPath: storePath)
        }
    }

    private static func sqliteStorePaths(
        for path: String,
        fileManager: FileManager
    ) -> [String] {
        ([path] + sqliteSidecarSuffixes.map { path + $0 })
            .filter { fileManager.fileExists(atPath: $0) }
    }

    private static func availableSQLiteBackupPath(
        for path: String,
        fileManager: FileManager
    ) -> String {
        let timestamp = Int(Date().timeIntervalSince1970)
        let base = "\(path).backup-\(timestamp)"
        guard fileManager.fileExists(atPath: base) else { return base }
        return "\(base)-\(UUID().uuidString)"
    }

    private static func availableSQLiteStagingPath(
        for path: String,
        fileManager: FileManager
    ) -> String {
        let base = "\(path).migration-\(UUID().uuidString)"
        guard fileManager.fileExists(atPath: base) else { return base }
        return "\(base)-\(UUID().uuidString)"
    }

    private static func moveTransactionCacheAside(
        in dataDir: String,
        environment: PlaidEnvironment,
        scopedDatabasePath: String,
        fileManager: FileManager
    ) throws -> String? {
        let directory = URL(fileURLWithPath: dataDir, isDirectory: true)
        let context = TransactionCacheContext(
            environment: environment,
            storagePath: scopedDatabasePath
        )
        let cachePath = LocalDataStore.transactionCacheURL(
            in: directory,
            context: context
        ).path
        guard fileManager.fileExists(atPath: cachePath) else { return nil }
        let backupPath = availableTransactionCacheBackupPath(for: cachePath, fileManager: fileManager)

        try fileManager.moveItem(
            atPath: cachePath,
            toPath: backupPath
        )
        return backupPath
    }

    private static func removeTransactionCache(
        in dataDir: String,
        environment: PlaidEnvironment,
        scopedDatabasePath: String,
        fileManager: FileManager
    ) throws {
        let cachePath = transactionCachePath(
            in: dataDir,
            environment: environment,
            scopedDatabasePath: scopedDatabasePath
        )
        guard fileManager.fileExists(atPath: cachePath) else { return }
        try fileManager.removeItem(atPath: cachePath)
    }

    private static func moveTransactionCache(
        from backupPath: String,
        in dataDir: String,
        environment: PlaidEnvironment,
        scopedDatabasePath: String,
        fileManager: FileManager
    ) throws {
        let cachePath = transactionCachePath(
            in: dataDir,
            environment: environment,
            scopedDatabasePath: scopedDatabasePath
        )
        try fileManager.moveItem(atPath: backupPath, toPath: cachePath)
    }

    private static func transactionCachePath(
        in dataDir: String,
        environment: PlaidEnvironment,
        scopedDatabasePath: String
    ) -> String {
        let directory = URL(fileURLWithPath: dataDir, isDirectory: true)
        let context = TransactionCacheContext(
            environment: environment,
            storagePath: scopedDatabasePath
        )
        return LocalDataStore.transactionCacheURL(in: directory, context: context).path
    }

    private static func availableTransactionCacheBackupPath(
        for path: String,
        fileManager: FileManager
    ) -> String {
        let timestamp = Int(Date().timeIntervalSince1970)
        let base = "\(path).backup-\(timestamp)"
        guard fileManager.fileExists(atPath: base) else { return base }
        return "\(base)-\(UUID().uuidString)"
    }

    private static func legacyMigrationMarkerPath(for scopedPath: String) -> String {
        "\(scopedPath).migrated-from-legacy"
    }

    private static func writeLegacyMigrationMarker(
        for scopedPath: String,
        environment: PlaidEnvironment,
        fileManager: FileManager
    ) throws {
        let markerPath = legacyMigrationMarkerPath(for: scopedPath)
        let contents = "environment=\(environment.rawValue)\n"
        try Data(contents.utf8).write(
            to: URL(fileURLWithPath: markerPath),
            options: [.atomic]
        )
        try fileManager.setAttributes([.posixPermissions: 0o600], ofItemAtPath: markerPath)
    }

    private static func copyLegacyTransactionCache(
        in dataDir: String,
        environment: PlaidEnvironment,
        legacyDatabasePath: String,
        scopedDatabasePath: String,
        fileManager: FileManager
    ) {
        let directory = URL(fileURLWithPath: dataDir, isDirectory: true)
        let destinationContext = TransactionCacheContext(
            environment: environment,
            storagePath: scopedDatabasePath
        )
        let destinationURL = LocalDataStore.transactionCacheURL(
            in: directory,
            context: destinationContext
        )
        guard !fileManager.fileExists(atPath: destinationURL.path) else { return }

        let sourceContext = TransactionCacheContext(
            environment: environment,
            storagePath: legacyDatabasePath
        )
        guard let transactions = try? LocalDataStore.loadTransactions(
            from: directory,
            context: sourceContext,
            fileManager: fileManager
        ), !transactions.isEmpty else { return }

        try? LocalDataStore.saveTransactions(
            transactions,
            to: directory,
            context: destinationContext,
            fileManager: fileManager
        )
    }
}

enum ServerConfigError: LocalizedError {
    case invalidEnvironmentVariable(String, String)
    case invalidConfigLine(path: String, line: Int)
    case invalidPort(Int)
    case missingManagedLinkWebhookURL
    case missingManagedRedirectURI
    case invalidManagedRedirectURI
    case appRedirectRequiresHTTPS
    case secureRandomUnavailable(status: Int32?)

    var errorDescription: String? {
        switch self {
        case .invalidEnvironmentVariable(let name, let value):
            "Invalid value for \(name): \(value)"
        case .invalidConfigLine(let path, let line):
            "Invalid config line \(line) in \(path)"
        case .invalidPort(let port):
            "Invalid server port \(port): must be between 1 and 65535"
        case .missingManagedLinkWebhookURL:
            "PLAID_LINK_WEBHOOK_URL is required when PLAIDBAR_DEPLOYMENT=hosted-bridge"
        case .missingManagedRedirectURI:
            "Managed production Hosted Link requires PLAIDBAR_OAUTH_REDIRECT_URI to be configured"
        case .invalidManagedRedirectURI:
            "Managed production Hosted Link redirect URI must be configured as HTTPS"
        case .appRedirectRequiresHTTPS:
            "App or Universal Link OAuth redirect mode requires an HTTPS Universal Link callback"
        case .secureRandomUnavailable(let status):
            if let status {
                "Secure random generation failed (OSStatus \(status)); refusing to fall back to weaker auth-token material"
            } else {
                "Secure random generation is unavailable on this platform; refusing to fall back to weaker auth-token material"
            }
        }
    }
}

enum OAuthRedirectMode: String, Sendable, Equatable, CaseIterable {
    case local
    case managed
    case app

    static let environmentVariable = "PLAIDBAR_OAUTH_REDIRECT_MODE"

    static func resolved(from environment: [String: String], deployment: DeploymentMode) -> OAuthRedirectMode {
        guard let rawValue = environment[environmentVariable]?.trimmedNonEmpty else {
            return deployment == .hostedBridge ? .managed : .local
        }
        return OAuthRedirectMode(rawValue: rawValue) ?? (deployment == .hostedBridge ? .managed : .local)
    }
}

struct OAuthRedirectConfiguration: Sendable, Equatable {
    static let uriEnvironmentVariable = "PLAIDBAR_OAUTH_REDIRECT_URI"

    let mode: OAuthRedirectMode
    let uri: String

    var isProductionReadyForHostedLink: Bool {
        switch mode {
        case .local:
            return false
        case .managed, .app:
            return Self.isHTTPS(uri)
        }
    }

    static func resolved(
        from environment: [String: String],
        deployment: DeploymentMode,
        plaidEnvironment: PlaidEnvironment,
        port: Int
    ) throws -> OAuthRedirectConfiguration {
        let mode = OAuthRedirectMode.resolved(from: environment, deployment: deployment)
        let configuredURI = environment[uriEnvironmentVariable]?.trimmedNonEmpty

        switch mode {
        case .local:
            return OAuthRedirectConfiguration(
                mode: .local,
                uri: configuredURI ?? "http://localhost:\(port)/oauth/callback"
            )
        case .managed:
            guard let configuredURI else {
                throw ServerConfigError.missingManagedRedirectURI
            }
            // Production OAuth redirect URIs must be HTTPS regardless of
            // deployment mode (mirrors the `.app` branch): a plaintext callback
            // would carry the one-time `state` over http. Gating on `.hostedBridge`
            // alone left managed + local deployment + production accepting an
            // http:// redirect — a TLS-downgrade hole.
            if plaidEnvironment == .production, !isHTTPS(configuredURI) {
                throw ServerConfigError.invalidManagedRedirectURI
            }
            return OAuthRedirectConfiguration(mode: .managed, uri: configuredURI)
        case .app:
            guard let configuredURI else {
                throw ServerConfigError.missingManagedRedirectURI
            }
            guard isHTTPS(configuredURI) else {
                throw ServerConfigError.appRedirectRequiresHTTPS
            }
            return OAuthRedirectConfiguration(mode: .app, uri: configuredURI)
        }
    }

    private static func isHTTPS(_ uri: String) -> Bool {
        guard let components = URLComponents(string: uri) else { return false }
        return components.scheme?.lowercased() == "https"
            && components.host?.isEmpty == false
    }
}

private extension String {
    var trimmedNonEmpty: String? {
        let value = trimmingCharacters(in: .whitespacesAndNewlines)
        return value.isEmpty ? nil : value
    }
}
