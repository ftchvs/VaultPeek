import Foundation

public struct TransactionDTO: Codable, Sendable, Identifiable, Hashable {
    public let id: String           // Plaid transaction_id
    public let itemId: String?      // Plaid item_id, available for newly synced transactions
    public let accountId: String
    public let amount: Double       // Positive = money out, Negative = money in (Plaid convention)
    public let date: String         // YYYY-MM-DD
    public let name: String         // Raw merchant name
    public let merchantName: String? // Cleaned merchant name
    public let category: SpendingCategory?
    public let pending: Bool
    /// Plaid `pending_transaction_id`: when a pending charge posts, Plaid removes
    /// the pending transaction and adds a new posted one that points back to the
    /// pending id through this field. Privacy-sensitive like every other id — keep
    /// it out of UI and logs; it exists only to reconcile pending → posted state.
    public let pendingTransactionId: String?
    public let isoCurrencyCode: String?
    /// Plaid Personal Finance Category v2 confidence (`VERY_HIGH`/`HIGH`/`MEDIUM`/
    /// `LOW`/`UNKNOWN`), preserved so the Review Inbox can surface only genuinely
    /// uncertain categorizations. Nil for cached rows or non-PFCv2 sources.
    public let categoryConfidence: String?

    public init(
        id: String,
        itemId: String? = nil,
        accountId: String,
        amount: Double,
        date: String,
        name: String,
        merchantName: String? = nil,
        category: SpendingCategory? = nil,
        pending: Bool = false,
        pendingTransactionId: String? = nil,
        isoCurrencyCode: String? = nil,
        categoryConfidence: String? = nil
    ) {
        self.id = id
        self.itemId = itemId
        self.accountId = accountId
        self.amount = amount
        self.date = date
        self.name = name
        self.merchantName = merchantName
        self.category = category
        self.pending = pending
        self.pendingTransactionId = pendingTransactionId
        self.isoCurrencyCode = isoCurrencyCode
        self.categoryConfidence = categoryConfidence
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

    /// True only when Plaid explicitly reports LOW/UNKNOWN category confidence —
    /// the signal the Review Inbox uses to surface uncertain categorizations.
    /// Missing confidence (nil) is treated as confident and does not flag.
    public var isLowConfidenceCategory: Bool {
        switch categoryConfidence?.uppercased() {
        case "LOW", "UNKNOWN": true
        default: false
        }
    }
}
