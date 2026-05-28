import Foundation
import PlaidBarCore

struct ServerConfig: Sendable {
    static let legacyDatabaseFilename = "plaidbar.sqlite"
    static let legacyMigrationEnvironmentVariable = "PLAIDBAR_MIGRATE_LEGACY_DATABASE"
    private static let sqliteSidecarSuffixes = ["-wal", "-shm", "-journal"]

    let port: Int
    let plaidEnvironment: PlaidEnvironment
    let plaidClientId: String
    let plaidSecret: String
    let databasePath: String
    let redirectUri: String
    let authToken: String

    var plaidBaseURL: String {
        switch plaidEnvironment {
        case .sandbox: "https://sandbox.plaid.com"
        case .production: "https://production.plaid.com"
        }
    }

    static func load(
        from configPath: String? = nil,
        portOverride: Int? = nil,
        sandboxOverride: Bool? = nil
    ) throws -> ServerConfig {
        let dataDir = dataDirectory()
        try FileManager.default.createDirectory(
            atPath: dataDir,
            withIntermediateDirectories: true
        )
        try FileManager.default.setAttributes(
            [.posixPermissions: 0o700],
            ofItemAtPath: dataDir
        )

        let environment: PlaidEnvironment = (sandboxOverride == true)
            ? .sandbox
            : .production

        let environmentValues = ProcessInfo.processInfo.environment
        guard let clientId = environmentValues["PLAID_CLIENT_ID"]?.trimmedNonEmpty else {
            throw ServerConfigError.missingEnvironmentVariable("PLAID_CLIENT_ID")
        }
        guard let secret = environmentValues["PLAID_SECRET"]?.trimmedNonEmpty else {
            throw ServerConfigError.missingEnvironmentVariable("PLAID_SECRET")
        }

        // Generate or load persistent auth token for app<->server auth
        let authTokenURL = LocalDataStore.authTokenURL(
            in: URL(fileURLWithPath: dataDir, isDirectory: true)
        )
        let authToken: String
        if let existing = try? String(contentsOf: authTokenURL, encoding: .utf8)
            .trimmingCharacters(in: .whitespacesAndNewlines),
            !existing.isEmpty
        {
            try FileManager.default.setAttributes(
                [.posixPermissions: 0o600],
                ofItemAtPath: authTokenURL.path
            )
            authToken = existing
        } else {
            let generated = UUID().uuidString
            try generated.write(to: authTokenURL, atomically: true, encoding: .utf8)
            try FileManager.default.setAttributes(
                [.posixPermissions: 0o600],
                ofItemAtPath: authTokenURL.path
            )
            authToken = generated
        }

        let resolvedPort = portOverride ?? PlaidBarConstants.defaultServerPort

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
            redirectUri: "http://localhost:\(resolvedPort)/oauth/callback",
            authToken: authToken
        )
    }

    static func dataDirectory() -> String {
        LocalDataStore.storageDirectoryURL().path
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
    case missingEnvironmentVariable(String)
    case invalidEnvironmentVariable(String, String)

    var errorDescription: String? {
        switch self {
        case .missingEnvironmentVariable(let name):
            "Missing required environment variable: \(name)"
        case .invalidEnvironmentVariable(let name, let value):
            "Invalid value for \(name): \(value)"
        }
    }
}

private extension String {
    var trimmedNonEmpty: String? {
        let value = trimmingCharacters(in: .whitespacesAndNewlines)
        return value.isEmpty ? nil : value
    }
}
