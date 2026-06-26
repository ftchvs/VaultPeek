import Foundation

/// A security held in (or referenced by) an investment account: the instrument
/// identity (`securityId`, ticker, name) plus the latest unit price Plaid
/// reports. Prices are *reference* values, not balances — a holding's market
/// value is `quantity × institutionPrice` (see ``HoldingDTO``).
///
/// Deliberately minimal: VaultPeek surfaces the human-readable name, ticker,
/// type, and unit price. CUSIP/ISIN/SEDOL identifiers stay server-side until a
/// detail surface needs them, keeping the shared DTO small and free of
/// regulatory identifiers we do not render.
public struct SecurityDTO: Codable, Sendable, Equatable, Identifiable {
    public let id: String              // Plaid security_id
    public let name: String?           // e.g. "Apple Inc."
    public let tickerSymbol: String?   // e.g. "AAPL"
    /// Plaid security type, e.g. `equity`, `etf`, `mutual fund`, `cash`,
    /// `fixed income`, `derivative`. Lower-cased as Plaid returns it.
    public let type: String?
    /// Most recent unit price Plaid has for the security (`close_price` /
    /// `institution_price`). Nil when Plaid omits a price (e.g. an unpriced
    /// security or a cash sweep).
    public let closePrice: Double?
    public let isoCurrencyCode: String?

    public init(
        id: String,
        name: String? = nil,
        tickerSymbol: String? = nil,
        type: String? = nil,
        closePrice: Double? = nil,
        isoCurrencyCode: String? = nil
    ) {
        self.id = id
        self.name = name
        self.tickerSymbol = tickerSymbol
        self.type = type
        self.closePrice = closePrice
        self.isoCurrencyCode = isoCurrencyCode
    }
}

/// One position inside an investment account: a quantity of a ``SecurityDTO``
/// and its market value. Comes from Plaid `/investments/holdings/get`.
///
/// `institutionValue` is Plaid's authoritative market value for the position;
/// when absent we fall back to `quantity × institutionPrice`. `costBasis` is
/// the total amount paid for the position (nullable — many institutions omit
/// it). Both are balance-like financial values, so every surface that renders
/// them must honor Privacy Mask (see ``InvestmentHoldingsPresentation``).
public struct HoldingDTO: Codable, Sendable, Equatable, Identifiable {
    public let accountId: String       // Plaid account_id (the brokerage account)
    public let securityId: String      // Plaid security_id (links to SecurityDTO)
    public let quantity: Double
    /// Per-unit price the institution reported for this holding. May differ from
    /// the security's `closePrice` when the institution prices intraday.
    public let institutionPrice: Double?
    /// Plaid's market value for the position. Authoritative when present.
    public let institutionValue: Double?
    /// Total cost paid for the position. Nil when the institution omits it.
    public let costBasis: Double?
    public let isoCurrencyCode: String?

    /// Stable, display-safe identity for `Identifiable`/`ForEach`.
    ///
    /// Never expose Plaid account/security identifiers as SwiftUI row ids. They
    /// can end up in diagnostics or generated artifacts, so derive a deterministic
    /// opaque id from the underlying identity instead.
    public var id: String {
        "holding-\(StableHash.hexPadded("\(accountId):\(securityId)"))"
    }

    public init(
        accountId: String,
        securityId: String,
        quantity: Double,
        institutionPrice: Double? = nil,
        institutionValue: Double? = nil,
        costBasis: Double? = nil,
        isoCurrencyCode: String? = nil
    ) {
        self.accountId = accountId
        self.securityId = securityId
        self.quantity = quantity
        self.institutionPrice = institutionPrice
        self.institutionValue = institutionValue
        self.costBasis = costBasis
        self.isoCurrencyCode = isoCurrencyCode
    }

    /// The position's market value: Plaid's `institutionValue` when present,
    /// otherwise `quantity × institutionPrice`, otherwise 0. Never negative for a
    /// long position, but short positions can carry a negative quantity/value —
    /// callers that need a non-negative asset total should clamp at the summary
    /// layer, mirroring `WealthSummaryPresentation.totalAssets`.
    public var marketValue: Double {
        if let institutionValue { return institutionValue }
        if let institutionPrice { return quantity * institutionPrice }
        return 0
    }

    /// Unrealized gain/loss: `marketValue − costBasis`. Nil when cost basis is
    /// unavailable, so callers can omit the cue rather than imply a $0 gain.
    public var unrealizedGain: Double? {
        guard let costBasis else { return nil }
        return marketValue - costBasis
    }

    /// Normalized currency identity for this holding's market value/cost basis.
    /// Wraps the raw Plaid `iso_currency_code`; an absent/empty code resolves to
    /// ``CurrencyCode/unknown`` (never silently assumed to be USD), so a EUR
    /// position is grouped and rendered as EUR rather than mislabeled `$`.
    public var currency: CurrencyCode {
        CurrencyCode(isoCurrencyCode)
    }
}

/// A buy/sell/dividend/fee event inside an investment account, from Plaid
/// `/investments/transactions/get`. Distinct from the cash-account
/// ``TransactionDTO`` feed: investment transactions reference a security and
/// carry a quantity/price, and are not part of the budgeting/cashflow surfaces.
public struct InvestmentTransactionDTO: Codable, Sendable, Equatable, Identifiable {
    public let id: String              // Plaid investment_transaction_id
    public let accountId: String
    public let securityId: String?
    /// `YYYY-MM-DD` settlement/posted date.
    public let date: String
    public let name: String
    public let quantity: Double
    public let price: Double
    /// Signed amount of the transaction: positive when cash moved *out* of the
    /// account (a buy), negative when cash moved *in* (a sell/dividend), per
    /// Plaid's sign convention.
    public let amount: Double
    public let fees: Double?
    /// Plaid investment-transaction type, e.g. `buy`, `sell`, `cash`, `fee`,
    /// `transfer`. Lower-cased as Plaid returns it.
    public let type: String?
    public let subtype: String?
    public let isoCurrencyCode: String?

    public init(
        id: String,
        accountId: String,
        securityId: String? = nil,
        date: String,
        name: String,
        quantity: Double,
        price: Double,
        amount: Double,
        fees: Double? = nil,
        type: String? = nil,
        subtype: String? = nil,
        isoCurrencyCode: String? = nil
    ) {
        self.id = id
        self.accountId = accountId
        self.securityId = securityId
        self.date = date
        self.name = name
        self.quantity = quantity
        self.price = price
        self.amount = amount
        self.fees = fees
        self.type = type
        self.subtype = subtype
        self.isoCurrencyCode = isoCurrencyCode
    }
}

/// The wire shape returned by the server's `/api/investments/holdings`
/// endpoint: holdings joined to their securities, plus the brokerage accounts
/// they belong to. The app reconstitutes per-account holdings from this in
/// ``InvestmentHoldingsPresentation``.
public struct InvestmentsResponse: Codable, Sendable, Equatable {
    public let accounts: [AccountDTO]
    public let holdings: [HoldingDTO]
    public let securities: [SecurityDTO]

    public init(
        accounts: [AccountDTO] = [],
        holdings: [HoldingDTO] = [],
        securities: [SecurityDTO] = []
    ) {
        self.accounts = accounts
        self.holdings = holdings
        self.securities = securities
    }
}
