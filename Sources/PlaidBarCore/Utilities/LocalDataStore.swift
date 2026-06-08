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

public struct TransactionCacheContext: Codable, Equatable, Sendable {
    public let environment: PlaidEnvironment
    public let storagePath: String

    public init(environment: PlaidEnvironment, storagePath: String) {
        self.environment = environment
        self.storagePath = storagePath
    }
}

public enum LocalDataStore {
    public static let displayPath = "~/.plaidbar/"
    public static let dataDirectoryEnvironmentVariable = "PLAIDBAR_DATA_DIR"
    public static let authTokenFilename = "auth-token"
    public static let serverConfigFilename = "server.conf"
    public static let accountCacheFilename = "accounts.json"
    public static let transactionCacheFilename = "transactions.json"
    public static let pendingLinkSessionsFilename = "pending-link-sessions.json"
    public static let plaidAccessTokenKeychainService = "PlaidBar.PlaidAccessToken"
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

        return homeDirectory.appendingPathComponent(".plaidbar", isDirectory: true)
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
            isPendingLinkSessionsFilename(filename) {
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

    private static func isTransactionCacheFilename(_ filename: String) -> Bool {
        filename == transactionCacheFilename ||
            (
                filename.hasPrefix("transactions-") &&
                    (filename.hasSuffix(".json") || filename.contains(".json.backup-"))
            )
    }

    private static func isAccountCacheFilename(_ filename: String) -> Bool {
        let cacheFilename = normalizedCacheFilename(filename)
        if cacheFilename == accountCacheFilename { return true }

        return [PlaidEnvironment.sandbox.rawValue, PlaidEnvironment.production.rawValue].contains { environment in
            guard cacheFilename.hasPrefix("accounts-\(environment)-"),
                  cacheFilename.hasSuffix(".json") else { return false }

            let hashStart = cacheFilename.index(cacheFilename.startIndex, offsetBy: "accounts-\(environment)-".count)
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

    public static func prepareStorageDirectory(
        at directory: URL = storageDirectoryURL(),
        fileManager: FileManager = .default
    ) throws {
        try ensurePrivateDirectory(directory, fileManager: fileManager)
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
