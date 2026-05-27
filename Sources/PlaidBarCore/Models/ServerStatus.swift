import Foundation

/// Response from server's /api/status
public struct ServerStatus: Codable, Sendable {
    public let version: String
    public let environment: PlaidEnvironment
    public let itemCount: Int
    public let lastSync: Date?
    public let credentialsConfigured: Bool
    public let storagePath: String
    public let syncReady: Bool

    public init(
        version: String,
        environment: PlaidEnvironment,
        itemCount: Int,
        lastSync: Date? = nil,
        credentialsConfigured: Bool = true,
        storagePath: String = LocalDataStore.displayPath,
        syncReady: Bool? = nil
    ) {
        self.version = version
        self.environment = environment
        self.itemCount = itemCount
        self.lastSync = lastSync
        self.credentialsConfigured = credentialsConfigured
        self.storagePath = storagePath
        self.syncReady = syncReady ?? (itemCount > 0)
    }
}

public enum PlaidEnvironment: String, Codable, Sendable {
    case sandbox
    case production
}
