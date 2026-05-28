import Foundation
#if os(macOS)
import Darwin
#endif

public struct LocalDataResetResult: Equatable, Sendable {
    public let directoryPath: String
    public let removedEntries: [String]

    public var removedEntryCount: Int {
        removedEntries.count
    }

    public init(directoryPath: String, removedEntries: [String]) {
        self.directoryPath = directoryPath
        self.removedEntries = removedEntries
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
    public static let transactionCacheFilename = "transactions.json"
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

    @discardableResult
    public static func resetLocalData(
        at directory: URL = storageDirectoryURL(),
        fileManager: FileManager = .default
    ) throws -> LocalDataResetResult {
        var removedEntries: [String] = []
        var isDirectory: ObjCBool = false

        if fileManager.fileExists(atPath: directory.path, isDirectory: &isDirectory) {
            if isDirectory.boolValue {
                let entries = try fileManager.contentsOfDirectory(
                    at: directory,
                    includingPropertiesForKeys: nil
                )
                for entry in entries where entry.lastPathComponent != authTokenFilename {
                    try fileManager.removeItem(at: entry)
                    removedEntries.append(entry.lastPathComponent)
                }
                removedEntries = removedEntries
                    .sorted()
            } else {
                removedEntries = [directory.lastPathComponent]
                try fileManager.removeItem(at: directory)
            }
        }

        try ensurePrivateDirectory(directory, fileManager: fileManager)

        return LocalDataResetResult(
            directoryPath: directory.path,
            removedEntries: removedEntries
        )
    }

    public static func transactionCacheURL(
        in directory: URL = storageDirectoryURL(),
        context: TransactionCacheContext? = nil
    ) -> URL {
        directory.appendingPathComponent(transactionCacheFilename(for: context))
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
        try data.write(to: url, options: [.atomic])
        try setPrivateCacheFilePermissions(url, fileManager: fileManager)
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
}

private struct TransactionCache: Codable, Sendable {
    let context: TransactionCacheContext?
    let transactions: [TransactionDTO]
}

private extension String {
    var trimmedNonEmpty: String? {
        let value = trimmingCharacters(in: .whitespacesAndNewlines)
        return value.isEmpty ? nil : value
    }
}
