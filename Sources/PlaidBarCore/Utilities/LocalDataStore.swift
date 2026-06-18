import Foundation
#if canImport(Security)
import Security
#endif
#if os(macOS)
import Darwin
#endif

public struct LocalDataResetResult: Equatable, Sendable {
    public let directoryPath: String
    public let removedEntries: [String]
    public let preservedEntries: [String]
    public let keychainTokensCleared: Bool

    public var removedEntryCount: Int {
        removedEntries.count
    }

    public var preservedEntryCount: Int {
        preservedEntries.count
    }

    public init(
        directoryPath: String,
        removedEntries: [String],
        preservedEntries: [String] = [],
        keychainTokensCleared: Bool
    ) {
        self.directoryPath = directoryPath
        self.removedEntries = removedEntries
        self.preservedEntries = preservedEntries
        self.keychainTokensCleared = keychainTokensCleared
    }
}

public struct LocalDataMigrationResult: Equatable, Sendable {
    public let legacyDirectoryPath: String
    public let currentDirectoryPath: String
    public let copiedEntries: [String]
    public let preservedCurrentEntries: [String]
    public let legacyDirectoryFound: Bool

    public var didCopyEntries: Bool {
        !copiedEntries.isEmpty
    }

    public init(
        legacyDirectoryPath: String,
        currentDirectoryPath: String,
        copiedEntries: [String],
        preservedCurrentEntries: [String],
        legacyDirectoryFound: Bool
    ) {
        self.legacyDirectoryPath = legacyDirectoryPath
        self.currentDirectoryPath = currentDirectoryPath
        self.copiedEntries = copiedEntries
        self.preservedCurrentEntries = preservedCurrentEntries
        self.legacyDirectoryFound = legacyDirectoryFound
    }
}

public struct TransactionCacheContext: Codable, Equatable, Sendable {
    public let environment: PlaidEnvironment
    public let storagePath: String

    public init(environment: PlaidEnvironment, storagePath: String) {
        self.environment = environment
        self.storagePath = storagePath
    }
}

public enum LocalDataStore {
    public static let displayPath = "~/.vaultpeek/"
    public static let legacyDisplayPath = "~/.plaidbar/"
    public static let dataDirectoryEnvironmentVariable = "PLAIDBAR_DATA_DIR"
    public static let authTokenFilename = "auth-token"
    public static let serverConfigFilename = "server.conf"
    public static let accountCacheFilename = "accounts.json"
    public static let transactionCacheFilename = "transactions.json"
    public static let transactionReviewMetadataFilename = "transaction-review-metadata.json"
    public static let transactionRulesFilename = "transaction-rules.json"
    public static let pendingLinkSessionsFilename = "pending-link-sessions.json"
    /// Stable, non-PII install-scoped Plaid `client_user_id`. Cleared on local
    /// reset so a fresh bank-link after reset does not reuse the pre-reset Plaid
    /// dashboard/log identity (the reset boundary clears local Plaid state).
    public static let linkClientUserIdFilename = "link-client-user-id"
    public static let legacyMigrationResetMarkerFilename = ".legacy-migration-reset"
    /// Preserve the existing Keychain service while moving local files so
    /// SQLite `keychain:<item_id>` references continue to resolve.
    public static let plaidAccessTokenKeychainService = "PlaidBar.PlaidAccessToken"
    private static let currentDirectoryName = ".vaultpeek"
    private static let legacyDirectoryName = ".plaidbar"
    private static let directoryPermissions = 0o700
    private static let cacheFilePermissions = 0o600

    public static func accountHomeDirectoryURL() -> URL {
        #if os(macOS)
        if let user = getpwuid(getuid()),
           let home = user.pointee.pw_dir {
            return URL(fileURLWithPath: String(cString: home), isDirectory: true)
        }
        #endif

        return FileManager.default.homeDirectoryForCurrentUser
    }

    public static func storageDirectoryURL(
        homeDirectory: URL = accountHomeDirectoryURL(),
        environment: [String: String] = ProcessInfo.processInfo.environment
    ) -> URL {
        if let override = environment[dataDirectoryEnvironmentVariable]?.trimmedNonEmpty {
            return URL(fileURLWithPath: NSString(string: override).expandingTildeInPath, isDirectory: true)
        }

        return currentStorageDirectoryURL(homeDirectory: homeDirectory)
    }

    public static func legacyStorageDirectoryURL(
        homeDirectory: URL = accountHomeDirectoryURL()
    ) -> URL {
        homeDirectory.appendingPathComponent(legacyDirectoryName, isDirectory: true)
    }

    public static func currentStorageDirectoryURL(
        homeDirectory: URL = accountHomeDirectoryURL()
    ) -> URL {
        homeDirectory.appendingPathComponent(currentDirectoryName, isDirectory: true)
    }

    public static func storageDirectoryURL(
        forServerStoragePath serverStoragePath: String?,
        fallback: URL = storageDirectoryURL()
    ) -> URL {
        guard let storagePath = serverStoragePath?.trimmedNonEmpty else {
            return fallback
        }

        if storagePath == displayPath {
            return fallback
        }

        let expandedPath = NSString(string: storagePath).expandingTildeInPath
        let storageURL = URL(fileURLWithPath: expandedPath)
        if storageURL.pathExtension.lowercased() == "sqlite" {
            return storageURL.deletingLastPathComponent()
        }

        return URL(fileURLWithPath: expandedPath, isDirectory: true)
    }

    public static func displayPath(
        for url: URL,
        homeDirectory: URL = accountHomeDirectoryURL()
    ) -> String {
        let homePath = homeDirectory.standardizedFileURL.path
        let path = url.standardizedFileURL.path

        if path == homePath {
            return "~"
        }

        if path.hasPrefix(homePath + "/") {
            return "~" + String(path.dropFirst(homePath.count))
        }

        return path
    }

    @discardableResult
    public static func resetLocalData(
        at directory: URL = storageDirectoryURL(),
        fileManager: FileManager = .default,
        resetKeychainTokens: Bool = true,
        keychainTokenReset: (() throws -> Void)? = nil
    ) throws -> LocalDataResetResult {
        var removedEntries: [String] = []
        var preservedEntries: [String] = []
        var isDirectory: ObjCBool = false

        if fileManager.fileExists(atPath: directory.path, isDirectory: &isDirectory) {
            if isDirectory.boolValue {
                let entries = try fileManager.contentsOfDirectory(
                    at: directory,
                    includingPropertiesForKeys: nil
                )
                for entry in entries {
                    let filename = entry.lastPathComponent
                    if shouldRemoveDuringReset(filename) {
                        try fileManager.removeItem(at: entry)
                        removedEntries.append(filename)
                    } else {
                        preservedEntries.append(filename)
                    }
                }
                removedEntries = removedEntries
                    .sorted()
                preservedEntries = preservedEntries
                    .sorted()
            } else {
                removedEntries = [directory.lastPathComponent]
                try fileManager.removeItem(at: directory)
            }
        }

        try ensurePrivateDirectory(directory, fileManager: fileManager)
        try ensurePrivatePreservedFilePermissions(in: directory, fileManager: fileManager)
        try writeLegacyMigrationResetMarker(in: directory, fileManager: fileManager)

        var keychainTokensCleared = false
        if resetKeychainTokens {
            try (keychainTokenReset ?? resetPlaidAccessTokenKeychainItems)()
            keychainTokensCleared = true
        }

        return LocalDataResetResult(
            directoryPath: directory.path,
            removedEntries: removedEntries,
            preservedEntries: preservedEntries,
            keychainTokensCleared: keychainTokensCleared
        )
    }

    private static func shouldRemoveDuringReset(_ filename: String) -> Bool {
        if resetPreservedFilenames.contains(filename) {
            return false
        }

        if isAccountCacheFilename(filename) ||
            isTransactionCacheFilename(filename) ||
            isTransactionReviewMetadataFilename(filename) ||
            isTransactionRulesFilename(filename) ||
            isPendingLinkSessionsFilename(filename) ||
            filename == linkClientUserIdFilename ||
            // Merchant logo cache directory (AND-494): clear cached brand images.
            filename == "logo-cache" {
            return true
        }

        return plaidBarDatabaseFilenames.contains { databaseFilename in
            filename == databaseFilename ||
                sqliteSidecarSuffixes.contains { filename == databaseFilename + $0 } ||
                filename.hasPrefix(databaseFilename + ".backup-") ||
                filename.hasPrefix(databaseFilename + ".migration-") ||
                filename == databaseFilename + ".migrated-from-legacy"
        }
    }

    private static var resetPreservedFilenames: Set<String> {
        [authTokenFilename, serverConfigFilename]
    }

    private static var plaidBarDatabaseFilenames: [String] {
        [
            "plaidbar.sqlite",
            "plaidbar-sandbox.sqlite",
            "plaidbar-production.sqlite",
        ]
    }

    private static var sqliteSidecarSuffixes: [String] {
        ["-wal", "-shm", "-journal"]
    }

    private static func ensurePrivateKnownDataFilePermissions(
        in directory: URL,
        fileManager: FileManager
    ) throws {
        let entries = try fileManager.contentsOfDirectory(
            at: directory,
            includingPropertiesForKeys: [.isDirectoryKey],
            options: [.skipsHiddenFiles]
        )
        for entry in entries where isKnownPrivateDataFilename(entry.lastPathComponent) {
            try setPrivateCacheFilePermissions(entry, fileManager: fileManager)
        }
    }

    private static func isKnownPrivateDataFilename(_ filename: String) -> Bool {
        filename == legacyMigrationResetMarkerFilename ||
            resetPreservedFilenames.contains(filename) ||
            filename == ServerAutoLaunchPlan.logFilename ||
            isTransactionReviewMetadataFilename(filename) ||
            isTransactionRulesFilename(filename) ||
            isAccountCacheFilename(filename) ||
            isTransactionCacheFilename(filename) ||
            isPendingLinkSessionsFilename(filename) ||
            filename == linkClientUserIdFilename ||
            plaidBarDatabaseFilenames.contains { databaseFilename in
                filename == databaseFilename ||
                    sqliteSidecarSuffixes.contains { filename == databaseFilename + $0 } ||
                    filename.hasPrefix(databaseFilename + ".backup-") ||
                    filename.hasPrefix(databaseFilename + ".migration-") ||
                    filename == databaseFilename + ".migrated-from-legacy"
            }
    }

    private static func sqliteStoreBaseFilename(for filename: String) -> String? {
        plaidBarDatabaseFilenames.first { databaseFilename in
            filename == databaseFilename ||
                sqliteSidecarSuffixes.contains { filename == databaseFilename + $0 }
        }
    }

    private static func sqliteStorePathCandidates(
        in directory: URL,
        databaseFilename: String
    ) -> [URL] {
        ([databaseFilename] + sqliteSidecarSuffixes.map { databaseFilename + $0 })
            .map { directory.appendingPathComponent($0) }
    }

    private static func isTransactionCacheFilename(_ filename: String) -> Bool {
        isScopedCacheFilename(filename, legacyFilename: transactionCacheFilename, prefix: "transactions")
    }

    private static func isAccountCacheFilename(_ filename: String) -> Bool {
        isScopedCacheFilename(filename, legacyFilename: accountCacheFilename, prefix: "accounts")
    }

    /// Matches only VaultPeek-generated cache files: the legacy unscoped name
    /// (e.g. `transactions.json`), an optional `.json.backup-...` variant of
    /// either shape, or the scoped `{prefix}-{sandbox|production}-{16hex}.json`
    /// form the cache writers emit. Unrelated user/export files such as
    /// `transactions-2026.json` are intentionally not matched, so local data
    /// reset preserves them.
    private static func isScopedCacheFilename(
        _ filename: String,
        legacyFilename: String,
        prefix: String
    ) -> Bool {
        let cacheFilename = normalizedCacheFilename(filename)
        if cacheFilename == legacyFilename { return true }

        return [PlaidEnvironment.sandbox.rawValue, PlaidEnvironment.production.rawValue].contains { environment in
            let scopedPrefix = "\(prefix)-\(environment)-"
            guard cacheFilename.hasPrefix(scopedPrefix),
                  cacheFilename.hasSuffix(".json") else { return false }

            let hashStart = cacheFilename.index(cacheFilename.startIndex, offsetBy: scopedPrefix.count)
            let hashEnd = cacheFilename.index(cacheFilename.endIndex, offsetBy: -".json".count)
            let hash = cacheFilename[hashStart..<hashEnd]
            return hash.count == 16 && hash.allSatisfy(\.isHexDigit)
        }
    }

    private static func normalizedCacheFilename(_ filename: String) -> String {
        guard let backupRange = filename.range(of: ".json.backup-") else {
            return filename
        }

        return String(filename[..<backupRange.lowerBound]) + ".json"
    }

    private static func isPendingLinkSessionsFilename(_ filename: String) -> Bool {
        filename == pendingLinkSessionsFilename ||
            filename.hasPrefix(pendingLinkSessionsFilename + ".backup-")
    }

    private static func resetPlaidAccessTokenKeychainItems() throws {
        #if canImport(Security)
        let status = SecItemDelete(plaidAccessTokenKeychainServiceQuery() as CFDictionary)
        guard status == errSecSuccess || status == errSecItemNotFound else {
            throw NSError(
                domain: NSOSStatusErrorDomain,
                code: Int(status),
                userInfo: [
                    NSLocalizedDescriptionKey: "Failed to delete stored Plaid access tokens from Keychain (status \(status))"
                ]
            )
        }
        #endif
    }

    #if canImport(Security)
    private static func plaidAccessTokenKeychainServiceQuery() -> [String: Any] {
        [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: plaidAccessTokenKeychainService
        ]
    }
    #endif

    public static func transactionCacheURL(
        in directory: URL = storageDirectoryURL(),
        context: TransactionCacheContext? = nil
    ) -> URL {
        directory.appendingPathComponent(transactionCacheFilename(for: context))
    }

    public static func accountCacheURL(
        in directory: URL = storageDirectoryURL(),
        context: TransactionCacheContext? = nil
    ) -> URL {
        directory.appendingPathComponent(accountCacheFilename(for: context))
    }

    public static func authTokenURL(
        in directory: URL = storageDirectoryURL()
    ) -> URL {
        directory.appendingPathComponent(authTokenFilename)
    }

    public static func transactionReviewMetadataURL(
        in directory: URL = storageDirectoryURL(),
        context: TransactionCacheContext? = nil
    ) -> URL {
        directory.appendingPathComponent(transactionReviewMetadataFilename(for: context))
    }

    public static func transactionRulesURL(
        in directory: URL = storageDirectoryURL(),
        context: TransactionCacheContext? = nil
    ) -> URL {
        directory.appendingPathComponent(transactionRulesFilename(for: context))
    }

    public static func prepareStorageDirectory(
        at directory: URL = storageDirectoryURL(),
        fileManager: FileManager = .default
    ) throws {
        try migrateLegacyDefaultStorageIfNeeded(
            destinationDirectory: directory,
            fileManager: fileManager
        )
        try ensurePrivateDirectory(directory, fileManager: fileManager)
    }

    @discardableResult
    public static func migrateLegacyDefaultStorageIfNeeded(
        homeDirectory: URL = accountHomeDirectoryURL(),
        fileManager: FileManager = .default
    ) throws -> LocalDataMigrationResult {
        try migrateLegacyDefaultStorageIfNeeded(
            homeDirectory: homeDirectory,
            destinationDirectory: currentStorageDirectoryURL(homeDirectory: homeDirectory),
            fileManager: fileManager
        )
    }

    @discardableResult
    public static func migrateLegacyDefaultStorageIfNeeded(
        homeDirectory: URL = accountHomeDirectoryURL(),
        destinationDirectory: URL,
        fileManager: FileManager = .default
    ) throws -> LocalDataMigrationResult {
        let currentDirectory = currentStorageDirectoryURL(homeDirectory: homeDirectory)
        let legacyDirectory = legacyStorageDirectoryURL(homeDirectory: homeDirectory)

        guard destinationDirectory.standardizedFileURL == currentDirectory.standardizedFileURL else {
            return LocalDataMigrationResult(
                legacyDirectoryPath: legacyDirectory.path,
                currentDirectoryPath: destinationDirectory.path,
                copiedEntries: [],
                preservedCurrentEntries: [],
                legacyDirectoryFound: false
            )
        }

        var isDirectory: ObjCBool = false
        guard fileManager.fileExists(atPath: legacyDirectory.path, isDirectory: &isDirectory),
              isDirectory.boolValue else {
            try ensurePrivateDirectory(currentDirectory, fileManager: fileManager)
            return LocalDataMigrationResult(
                legacyDirectoryPath: legacyDirectory.path,
                currentDirectoryPath: currentDirectory.path,
                copiedEntries: [],
                preservedCurrentEntries: [],
                legacyDirectoryFound: false
            )
        }

        try ensurePrivateDirectory(currentDirectory, fileManager: fileManager)

        var copiedEntries: [String] = []
        var preservedCurrentEntries: [String] = []
        let resetMarkerExists = fileManager.fileExists(
            atPath: currentDirectory.appendingPathComponent(legacyMigrationResetMarkerFilename).path
        )
        let legacyEntries = try fileManager.contentsOfDirectory(
            at: legacyDirectory,
            includingPropertiesForKeys: [.isDirectoryKey],
            options: [.skipsHiddenFiles]
        )
        let preservedSQLiteBases = Set(plaidBarDatabaseFilenames.filter { databaseFilename in
            sqliteStorePathCandidates(
                in: currentDirectory,
                databaseFilename: databaseFilename
            ).contains { fileManager.fileExists(atPath: $0.path) }
        })

        for sourceURL in legacyEntries {
            let filename = sourceURL.lastPathComponent
            if resetMarkerExists && shouldRemoveDuringReset(filename) {
                continue
            }

            if let databaseFilename = sqliteStoreBaseFilename(for: filename),
               preservedSQLiteBases.contains(databaseFilename) {
                preservedCurrentEntries.append(filename)
                continue
            }

            let preparedCopy = try preparedLegacyMigrationCopy(
                from: sourceURL,
                legacyDirectory: legacyDirectory,
                currentDirectory: currentDirectory
            )
            let destinationURL = preparedCopy.destinationURL
            if fileManager.fileExists(atPath: destinationURL.path) {
                preservedCurrentEntries.append(destinationURL.lastPathComponent)
                continue
            }

            if let data = preparedCopy.data {
                try writePrivateCacheFile(data, to: destinationURL, fileManager: fileManager)
            } else {
                try fileManager.copyItem(at: sourceURL, to: destinationURL)
            }
            copiedEntries.append(destinationURL.lastPathComponent)
        }

        try ensurePrivatePreservedFilePermissions(in: currentDirectory, fileManager: fileManager)
        try ensurePrivateKnownDataFilePermissions(in: currentDirectory, fileManager: fileManager)

        return LocalDataMigrationResult(
            legacyDirectoryPath: legacyDirectory.path,
            currentDirectoryPath: currentDirectory.path,
            copiedEntries: copiedEntries.sorted(),
            preservedCurrentEntries: preservedCurrentEntries.sorted(),
            legacyDirectoryFound: true
        )
    }

    private static func preparedLegacyMigrationCopy(
        from sourceURL: URL,
        legacyDirectory: URL,
        currentDirectory: URL
    ) throws -> (destinationURL: URL, data: Data?) {
        let filename = sourceURL.lastPathComponent
        if isTransactionCacheFilename(filename),
           let remapped = try remappedTransactionCacheCopy(
            from: sourceURL,
            legacyDirectory: legacyDirectory,
            currentDirectory: currentDirectory
           ) {
            return remapped
        }

        if isAccountCacheFilename(filename),
           let remapped = try remappedAccountCacheCopy(
            from: sourceURL,
            legacyDirectory: legacyDirectory,
            currentDirectory: currentDirectory
           ) {
            return remapped
        }

        return (currentDirectory.appendingPathComponent(filename), nil)
    }

    private static func remappedTransactionCacheCopy(
        from sourceURL: URL,
        legacyDirectory: URL,
        currentDirectory: URL
    ) throws -> (destinationURL: URL, data: Data)? {
        let data = try Data(contentsOf: sourceURL)
        guard let cache = try? JSONDecoder().decode(TransactionCache.self, from: data) else {
            return nil
        }
        guard let context = cache.context,
              let remappedContext = remappedLegacyContext(
                context,
                legacyDirectory: legacyDirectory,
                currentDirectory: currentDirectory
              ) else {
            return nil
        }

        let remappedCache = TransactionCache(
            context: remappedContext,
            transactions: cache.transactions
        )
        return (
            transactionCacheURL(in: currentDirectory, context: remappedContext),
            try JSONEncoder().encode(remappedCache)
        )
    }

    private static func remappedAccountCacheCopy(
        from sourceURL: URL,
        legacyDirectory: URL,
        currentDirectory: URL
    ) throws -> (destinationURL: URL, data: Data)? {
        let data = try Data(contentsOf: sourceURL)
        guard let cache = try? JSONDecoder().decode(AccountCache.self, from: data) else {
            return nil
        }
        guard let context = cache.context,
              let remappedContext = remappedLegacyContext(
                context,
                legacyDirectory: legacyDirectory,
                currentDirectory: currentDirectory
              ) else {
            return nil
        }

        let remappedCache = AccountCache(
            context: remappedContext,
            accounts: cache.accounts
        )
        return (
            accountCacheURL(in: currentDirectory, context: remappedContext),
            try JSONEncoder().encode(remappedCache)
        )
    }

    private static func remappedLegacyContext(
        _ context: TransactionCacheContext,
        legacyDirectory: URL,
        currentDirectory: URL
    ) -> TransactionCacheContext? {
        let legacyPath = legacyDirectory.standardizedFileURL.path
        let currentPath = currentDirectory.standardizedFileURL.path
        let storagePath = URL(fileURLWithPath: context.storagePath).standardizedFileURL.path

        if storagePath == legacyPath {
            return TransactionCacheContext(
                environment: context.environment,
                storagePath: currentPath
            )
        }

        guard storagePath.hasPrefix(legacyPath + "/") else { return nil }
        return TransactionCacheContext(
            environment: context.environment,
            storagePath: currentPath + String(storagePath.dropFirst(legacyPath.count))
        )
    }

    public static func loadTransactions(
        from directory: URL = storageDirectoryURL(),
        context: TransactionCacheContext? = nil,
        fileManager: FileManager = .default
    ) throws -> [TransactionDTO] {
        let url = transactionCacheURL(in: directory, context: context)
        guard fileManager.fileExists(atPath: url.path) else { return [] }

        let data = try Data(contentsOf: url)
        let cache = try JSONDecoder().decode(TransactionCache.self, from: data)
        guard context == nil || cache.context == context else { return [] }
        return cache.transactions
    }

    public static func loadAccounts(
        from directory: URL = storageDirectoryURL(),
        context: TransactionCacheContext? = nil,
        fileManager: FileManager = .default
    ) throws -> [AccountDTO] {
        let url = accountCacheURL(in: directory, context: context)
        guard fileManager.fileExists(atPath: url.path) else { return [] }

        let data = try Data(contentsOf: url)
        let cache = try JSONDecoder().decode(AccountCache.self, from: data)
        guard context == nil || cache.context == context else { return [] }
        return cache.accounts
    }

    public static func loadTransactionReviewMetadata(
        from directory: URL = storageDirectoryURL(),
        context: TransactionCacheContext? = nil,
        fileManager: FileManager = .default
    ) throws -> [TransactionReviewMetadata] {
        let url = transactionReviewMetadataURL(in: directory, context: context)
        guard fileManager.fileExists(atPath: url.path) else { return [] }

        let data = try Data(contentsOf: url)
        return try JSONDecoder().decode([TransactionReviewMetadata].self, from: data)
    }

    public static func loadTransactionRules(
        from directory: URL = storageDirectoryURL(),
        context: TransactionCacheContext? = nil,
        fileManager: FileManager = .default
    ) throws -> [TransactionRule] {
        let url = transactionRulesURL(in: directory, context: context)
        guard fileManager.fileExists(atPath: url.path) else { return [] }

        let data = try Data(contentsOf: url)
        return try JSONDecoder().decode([TransactionRule].self, from: data)
    }

    public static func saveTransactions(
        _ transactions: [TransactionDTO],
        to directory: URL = storageDirectoryURL(),
        context: TransactionCacheContext? = nil,
        fileManager: FileManager = .default
    ) throws {
        try ensurePrivateDirectory(directory, fileManager: fileManager)

        let url = transactionCacheURL(in: directory, context: context)
        let cache = TransactionCache(context: context, transactions: transactions)
        let data = try JSONEncoder().encode(cache)
        try writePrivateCacheFile(data, to: url, fileManager: fileManager)
        try setPrivateCacheFilePermissions(url, fileManager: fileManager)
    }

    public static func saveAccounts(
        _ accounts: [AccountDTO],
        to directory: URL = storageDirectoryURL(),
        context: TransactionCacheContext? = nil,
        fileManager: FileManager = .default
    ) throws {
        try ensurePrivateDirectory(directory, fileManager: fileManager)

        let url = accountCacheURL(in: directory, context: context)
        let cache = AccountCache(context: context, accounts: accounts)
        let data = try JSONEncoder().encode(cache)
        try writePrivateCacheFile(data, to: url, fileManager: fileManager)
        try setPrivateCacheFilePermissions(url, fileManager: fileManager)
    }

    public static func saveTransactionReviewMetadata(
        _ metadata: [TransactionReviewMetadata],
        to directory: URL = storageDirectoryURL(),
        context: TransactionCacheContext? = nil,
        fileManager: FileManager = .default
    ) throws {
        try ensurePrivateDirectory(directory, fileManager: fileManager)

        let url = transactionReviewMetadataURL(in: directory, context: context)
        let data = try JSONEncoder().encode(metadata.sorted { $0.id < $1.id })
        try writePrivateCacheFile(data, to: url, fileManager: fileManager)
        try setPrivateCacheFilePermissions(url, fileManager: fileManager)
    }

    public static func saveTransactionRules(
        _ rules: [TransactionRule],
        to directory: URL = storageDirectoryURL(),
        context: TransactionCacheContext? = nil,
        fileManager: FileManager = .default
    ) throws {
        try ensurePrivateDirectory(directory, fileManager: fileManager)

        let url = transactionRulesURL(in: directory, context: context)
        let data = try JSONEncoder().encode(rules.sorted { $0.createdAt < $1.createdAt })
        try writePrivateCacheFile(data, to: url, fileManager: fileManager)
        try setPrivateCacheFilePermissions(url, fileManager: fileManager)
    }

    private static func accountCacheFilename(for context: TransactionCacheContext?) -> String {
        guard let context else { return accountCacheFilename }

        let key = "\(context.environment.rawValue)|\(context.storagePath)"
        return "accounts-\(context.environment.rawValue)-\(stableHashHex(key)).json"
    }

    private static func transactionCacheFilename(for context: TransactionCacheContext?) -> String {
        guard let context else { return transactionCacheFilename }

        let key = "\(context.environment.rawValue)|\(context.storagePath)"
        return "transactions-\(context.environment.rawValue)-\(stableHashHex(key)).json"
    }

    // Review metadata and merchant rules are scoped to the active cache context
    // the same way account/transaction caches are, so switching environment or
    // storage directory cannot load sandbox review state for production data.
    static let transactionReviewMetadataScopedPrefix = "transaction-review-metadata"
    static let transactionRulesScopedPrefix = "transaction-rules"

    private static func transactionReviewMetadataFilename(for context: TransactionCacheContext?) -> String {
        guard let context else { return transactionReviewMetadataFilename }

        let key = "\(context.environment.rawValue)|\(context.storagePath)"
        return "\(transactionReviewMetadataScopedPrefix)-\(context.environment.rawValue)-\(stableHashHex(key)).json"
    }

    private static func transactionRulesFilename(for context: TransactionCacheContext?) -> String {
        guard let context else { return transactionRulesFilename }

        let key = "\(context.environment.rawValue)|\(context.storagePath)"
        return "\(transactionRulesScopedPrefix)-\(context.environment.rawValue)-\(stableHashHex(key)).json"
    }

    private static func isTransactionReviewMetadataFilename(_ filename: String) -> Bool {
        isScopedCacheFilename(
            filename,
            legacyFilename: transactionReviewMetadataFilename,
            prefix: transactionReviewMetadataScopedPrefix
        )
    }

    private static func isTransactionRulesFilename(_ filename: String) -> Bool {
        isScopedCacheFilename(
            filename,
            legacyFilename: transactionRulesFilename,
            prefix: transactionRulesScopedPrefix
        )
    }

    private static func stableHashHex(_ value: String) -> String {
        var hash: UInt64 = 14_695_981_039_346_656_037
        for byte in value.utf8 {
            hash ^= UInt64(byte)
            hash &*= 1_099_511_628_211
        }
        return String(format: "%016llx", hash)
    }

    private static func ensurePrivateDirectory(
        _ directory: URL,
        fileManager: FileManager
    ) throws {
        try fileManager.createDirectory(
            at: directory,
            withIntermediateDirectories: true,
            attributes: [.posixPermissions: directoryPermissions]
        )
        try fileManager.setAttributes(
            [.posixPermissions: directoryPermissions],
            ofItemAtPath: directory.path
        )
    }

    private static func setPrivateCacheFilePermissions(
        _ url: URL,
        fileManager: FileManager
    ) throws {
        try fileManager.setAttributes(
            [.posixPermissions: cacheFilePermissions],
            ofItemAtPath: url.path
        )
    }

    private static func writePrivateCacheFile(
        _ data: Data,
        to url: URL,
        fileManager: FileManager
    ) throws {
        #if os(macOS)
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
                try? fileManager.removeItem(at: temporaryURL)
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
    }

    private static func ensurePrivatePreservedFilePermissions(
        in directory: URL,
        fileManager: FileManager
    ) throws {
        for filename in resetPreservedFilenames {
            let url = directory.appendingPathComponent(filename)
            guard fileManager.fileExists(atPath: url.path) else { continue }
            try fileManager.setAttributes(
                [.posixPermissions: cacheFilePermissions],
                ofItemAtPath: url.path
            )
        }
    }

    private static func writeLegacyMigrationResetMarker(
        in directory: URL,
        fileManager: FileManager
    ) throws {
        let url = directory.appendingPathComponent(legacyMigrationResetMarkerFilename)
        let marker = "reset_at=\(ISO8601DateFormatter().string(from: Date()))\n"
        try writePrivateCacheFile(Data(marker.utf8), to: url, fileManager: fileManager)
        try setPrivateCacheFilePermissions(url, fileManager: fileManager)
    }
}

private struct TransactionCache: Codable, Sendable {
    let context: TransactionCacheContext?
    let transactions: [TransactionDTO]
}

private struct AccountCache: Codable, Sendable {
    let context: TransactionCacheContext?
    let accounts: [AccountDTO]
}

private extension String {
    var trimmedNonEmpty: String? {
        let value = trimmingCharacters(in: .whitespacesAndNewlines)
        return value.isEmpty ? nil : value
    }
}
