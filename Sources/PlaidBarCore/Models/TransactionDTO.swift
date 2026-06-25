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
    /// App-owned, provider-neutral signal derived server-side from Plaid PFCv2
    /// confidence: true only when Plaid reports LOW/UNKNOWN. The Review Inbox uses
    /// it to surface uncertain categorizations. (The raw Plaid `confidence_level`
    /// enum is intentionally not carried into the app.)
    public let isLowConfidenceCategory: Bool
    /// Plaid enriched merchant logo URL (a Plaid CDN image). The app loads it
    /// only through the local server's authenticated logo proxy, never directly.
    public let logoURL: String?

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
        isLowConfidenceCategory: Bool = false,
        logoURL: String? = nil
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
        self.isLowConfidenceCategory = isLowConfidenceCategory
        self.logoURL = logoURL
    }

    public init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(String.self, forKey: .id)
        itemId = try container.decodeIfPresent(String.self, forKey: .itemId)
        accountId = try container.decode(String.self, forKey: .accountId)
        amount = try container.decode(Double.self, forKey: .amount)
        date = try container.decode(String.self, forKey: .date)
        name = try container.decode(String.self, forKey: .name)
        merchantName = try container.decodeIfPresent(String.self, forKey: .merchantName)
        category = try container.decodeIfPresent(SpendingCategory.self, forKey: .category)
        pending = try container.decode(Bool.self, forKey: .pending)
        pendingTransactionId = try container.decodeIfPresent(String.self, forKey: .pendingTransactionId)
        isoCurrencyCode = try container.decodeIfPresent(String.self, forKey: .isoCurrencyCode)
        // New field — default to "confident" when absent so older cached
        // transactions.json (written before this field existed) still decode.
        isLowConfidenceCategory = try container.decodeIfPresent(Bool.self, forKey: .isLowConfidenceCategory) ?? false
        logoURL = try container.decodeIfPresent(String.self, forKey: .logoURL)
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

    /// Normalized currency identity for this transaction. Wraps the raw Plaid
    /// `iso_currency_code`; an absent/empty code resolves to
    /// ``CurrencyCode/unknown`` so a transaction is rendered in its own native
    /// currency, never coerced to USD.
    public var currency: CurrencyCode {
        CurrencyCode(isoCurrencyCode)
    }
}
