import Foundation

/// Local cache model for accounts, persisted as JSON
struct CachedAccount: Codable, Sendable, Identifiable {
    var id: String { accountId }
    let accountId: String
    let itemId: String
    var name: String
    var officialName: String?
    var type: String
    var subtype: String?
    var mask: String?
    var balanceAvailable: Double?
    var balanceCurrent: Double?
    var balanceLimit: Double?
    var currencyCode: String?
    var institutionName: String?
    var lastUpdated: Date

    init(
        accountId: String,
        itemId: String,
        name: String,
        officialName: String? = nil,
        type: String,
        subtype: String? = nil,
        mask: String? = nil,
        balanceAvailable: Double? = nil,
        balanceCurrent: Double? = nil,
        balanceLimit: Double? = nil,
        currencyCode: String? = nil,
        institutionName: String? = nil
    ) {
        self.accountId = accountId
        self.itemId = itemId
        self.name = name
        self.officialName = officialName
        self.type = type
        self.subtype = subtype
        self.mask = mask
        self.balanceAvailable = balanceAvailable
        self.balanceCurrent = balanceCurrent
        self.balanceLimit = balanceLimit
        self.currencyCode = currencyCode
        self.institutionName = institutionName
        self.lastUpdated = Date()
    }
}
