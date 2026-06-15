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
    private enum CodingKeys: String, CodingKey {
        case id
        case institutionName
        case status
        case lastSync
        case lastWebhookAt
        case lastWebhookEvent
        case needsSync
    }

    public let id: String        // item_id
    public let institutionName: String?
    public let status: ItemConnectionStatus
    public let lastSync: Date?
    public let lastWebhookAt: Date?
    public let lastWebhookEvent: String?
    public let needsSync: Bool

    public init(
        id: String,
        institutionName: String? = nil,
        status: ItemConnectionStatus,
        lastSync: Date? = nil,
        lastWebhookAt: Date? = nil,
        lastWebhookEvent: String? = nil,
        needsSync: Bool = false
    ) {
        self.id = id
        self.institutionName = institutionName
        self.status = status
        self.lastSync = lastSync
        self.lastWebhookAt = lastWebhookAt
        self.lastWebhookEvent = lastWebhookEvent
        self.needsSync = needsSync
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.init(
            id: try container.decode(String.self, forKey: .id),
            institutionName: try container.decodeIfPresent(String.self, forKey: .institutionName),
            status: try container.decode(ItemConnectionStatus.self, forKey: .status),
            lastSync: try container.decodeIfPresent(Date.self, forKey: .lastSync),
            lastWebhookAt: try container.decodeIfPresent(Date.self, forKey: .lastWebhookAt),
            lastWebhookEvent: try container.decodeIfPresent(String.self, forKey: .lastWebhookEvent),
            needsSync: try container.decodeIfPresent(Bool.self, forKey: .needsSync) ?? false
        )
    }
}

public enum ItemConnectionStatus: String, Codable, Sendable {
    case connected
    case loginRequired = "login_required"
    case error
}
