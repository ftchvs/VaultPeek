import Foundation

/// Local cache model for transactions, persisted as JSON
struct CachedTransaction: Codable, Sendable, Identifiable {
    var id: String { transactionId }
    let transactionId: String
    let accountId: String
    var amount: Double
    var date: String
    var name: String
    var merchantName: String?
    var categoryRaw: String?
    var pending: Bool
    var currencyCode: String?
    var lastUpdated: Date

    init(
        transactionId: String,
        accountId: String,
        amount: Double,
        date: String,
        name: String,
        merchantName: String? = nil,
        categoryRaw: String? = nil,
        pending: Bool = false,
        currencyCode: String? = nil
    ) {
        self.transactionId = transactionId
        self.accountId = accountId
        self.amount = amount
        self.date = date
        self.name = name
        self.merchantName = merchantName
        self.categoryRaw = categoryRaw
        self.pending = pending
        self.currencyCode = currencyCode
        self.lastUpdated = Date()
    }
}
