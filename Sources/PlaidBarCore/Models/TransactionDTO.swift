import Foundation

public struct TransactionDTO: Codable, Sendable, Identifiable, Hashable {
    public let id: String           // Plaid transaction_id
    public let accountId: String
    public let amount: Double       // Positive = money out, Negative = money in (Plaid convention)
    public let date: String         // YYYY-MM-DD
    public let name: String         // Raw merchant name
    public let merchantName: String? // Cleaned merchant name
    public let category: SpendingCategory?
    public let pending: Bool
    public let isoCurrencyCode: String?

    public init(
        id: String,
        accountId: String,
        amount: Double,
        date: String,
        name: String,
        merchantName: String? = nil,
        category: SpendingCategory? = nil,
        pending: Bool = false,
        isoCurrencyCode: String? = nil
    ) {
        self.id = id
        self.accountId = accountId
        self.amount = amount
        self.date = date
        self.name = name
        self.merchantName = merchantName
        self.category = category
        self.pending = pending
        self.isoCurrencyCode = isoCurrencyCode
    }

    /// Display name: merchantName if available, otherwise raw name
    public var displayName: String {
        merchantName ?? name
    }

    /// Whether this is income (money in)
    public var isIncome: Bool {
        amount < 0  // Plaid: negative = money in
    }

    /// Absolute display amount
    public var displayAmount: Double {
        abs(amount)
    }
}
