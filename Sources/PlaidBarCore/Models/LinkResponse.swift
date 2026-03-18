import Foundation

/// Response from server's /api/link/create endpoint
public struct LinkResponse: Codable, Sendable {
    public let linkToken: String
    public let linkUrl: String  // URL to open in browser

    public init(linkToken: String, linkUrl: String) {
        self.linkToken = linkToken
        self.linkUrl = linkUrl
    }
}

/// Response from token exchange (server internal, but also useful for status)
public struct ItemStatus: Codable, Sendable, Identifiable {
    public let id: String        // item_id
    public let institutionName: String?
    public let status: ItemConnectionStatus
    public let lastSync: Date?

    public init(id: String, institutionName: String? = nil, status: ItemConnectionStatus, lastSync: Date? = nil) {
        self.id = id
        self.institutionName = institutionName
        self.status = status
        self.lastSync = lastSync
    }
}

public enum ItemConnectionStatus: String, Codable, Sendable {
    case connected
    case loginRequired = "login_required"
    case error
}
