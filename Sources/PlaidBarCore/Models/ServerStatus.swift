import Foundation

/// Response from server's /api/status
public struct ServerStatus: Codable, Sendable {
    public let version: String
    public let environment: PlaidEnvironment
    public let itemCount: Int
    public let lastSync: Date?

    public init(version: String, environment: PlaidEnvironment, itemCount: Int, lastSync: Date? = nil) {
        self.version = version
        self.environment = environment
        self.itemCount = itemCount
        self.lastSync = lastSync
    }
}

public enum PlaidEnvironment: String, Codable, Sendable {
    case sandbox
    case production
}
