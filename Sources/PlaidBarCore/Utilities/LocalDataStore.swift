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
    public static let transactionCacheFilename = "transactions.json"

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
                removedEntries = try fileManager
                    .contentsOfDirectory(at: directory, includingPropertiesForKeys: nil)
                    .map(\.lastPathComponent)
                    .sorted()
            } else {
                removedEntries = [directory.lastPathComponent]
            }

            try fileManager.removeItem(at: directory)
        }

        try fileManager.createDirectory(at: directory, withIntermediateDirectories: true)

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
        try fileManager.createDirectory(at: directory, withIntermediateDirectories: true)

        let url = transactionCacheURL(in: directory, context: context)
        let cache = TransactionCache(context: context, transactions: transactions)
        let data = try JSONEncoder().encode(cache)
        try data.write(to: url, options: [.atomic])
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
