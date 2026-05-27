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

public enum LocalDataStore {
    public static let displayPath = "~/.plaidbar/"
    public static let dataDirectoryEnvironmentVariable = "PLAIDBAR_DATA_DIR"

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
}

private extension String {
    var trimmedNonEmpty: String? {
        let value = trimmingCharacters(in: .whitespacesAndNewlines)
        return value.isEmpty ? nil : value
    }
}
