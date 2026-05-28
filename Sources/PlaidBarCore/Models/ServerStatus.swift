import Foundation

/// Response from server's /api/status
public struct ServerStatus: Codable, Sendable {
    private enum CodingKeys: String, CodingKey {
        case version
        case environment
        case itemCount
        case lastSync
        case credentialsConfigured
        case storagePath
        case syncReady
        case syncedItemCount
    }

    public let version: String
    public let environment: PlaidEnvironment
    public let itemCount: Int
    public let lastSync: Date?
    public let credentialsConfigured: Bool
    public let storagePath: String
    public let syncReady: Bool
    public let syncedItemCount: Int

    public init(
        version: String,
        environment: PlaidEnvironment,
        itemCount: Int,
        lastSync: Date? = nil,
        credentialsConfigured: Bool = true,
        storagePath: String = LocalDataStore.displayPath,
        syncReady: Bool? = nil,
        syncedItemCount: Int? = nil
    ) {
        self.version = version
        self.environment = environment
        self.itemCount = itemCount
        self.lastSync = lastSync
        self.credentialsConfigured = credentialsConfigured
        self.storagePath = storagePath
        self.syncReady = syncReady ?? (itemCount > 0)
        self.syncedItemCount = syncedItemCount ?? (lastSync == nil ? 0 : itemCount)
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let version = try container.decode(String.self, forKey: .version)
        let environment = try container.decode(PlaidEnvironment.self, forKey: .environment)
        let itemCount = try container.decode(Int.self, forKey: .itemCount)
        let lastSync = try container.decodeIfPresent(Date.self, forKey: .lastSync)
        let credentialsConfigured = try container.decodeIfPresent(Bool.self, forKey: .credentialsConfigured)
        let storagePath = try container.decodeIfPresent(String.self, forKey: .storagePath)
        let syncReady = try container.decodeIfPresent(Bool.self, forKey: .syncReady)
        let syncedItemCount = try container.decodeIfPresent(Int.self, forKey: .syncedItemCount)

        self.init(
            version: version,
            environment: environment,
            itemCount: itemCount,
            lastSync: lastSync,
            credentialsConfigured: credentialsConfigured ?? true,
            storagePath: storagePath ?? LocalDataStore.displayPath,
            syncReady: syncReady,
            syncedItemCount: syncedItemCount
        )
    }
}

public enum PlaidEnvironment: String, Codable, Sendable {
    case sandbox
    case production
}
