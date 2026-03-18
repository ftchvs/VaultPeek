import Foundation

/// Shared account model between app and server
public struct AccountDTO: Codable, Sendable, Identifiable, Hashable {
    public let id: String          // Plaid account_id
    public let itemId: String      // Plaid item_id
    public let name: String        // e.g., "Chase Checking"
    public let officialName: String?
    public let type: AccountType
    public let subtype: String?
    public let mask: String?       // Last 4 digits
    public let balances: BalanceDTO
    public let institutionName: String?

    public init(
        id: String,
        itemId: String,
        name: String,
        officialName: String? = nil,
        type: AccountType,
        subtype: String? = nil,
        mask: String? = nil,
        balances: BalanceDTO,
        institutionName: String? = nil
    ) {
        self.id = id
        self.itemId = itemId
        self.name = name
        self.officialName = officialName
        self.type = type
        self.subtype = subtype
        self.mask = mask
        self.balances = balances
        self.institutionName = institutionName
    }
}

public enum AccountType: String, Codable, Sendable {
    case depository
    case credit
    case loan
    case investment
    case other
}
