import Foundation

/// Display-safe finance summary shared from the app to App Intents / extensions
/// through the App Group container (AND-512).
///
/// This is the "Tahoe spine": the app computes the headline numbers once (reusing
/// `SafeToSpendCalculator`, the wealth utilities, and `RecurringDetector`) and
/// writes a single small snapshot that Spotlight / Siri / Shortcuts read back.
/// It contains **values only** — never Plaid `access_token`s, `client_secret`s,
/// `account_id`s, `item_id`s, or transaction payloads. The per-account entries
/// carry a user-facing display name and a balance, nothing that identifies the
/// linked institution record.
///
/// When App Lock / Privacy Mask is active the app writes a snapshot with
/// `isMasked == true`; intents then return a withheld response (see
/// `FinanceIntentQueries`) rather than leaking the figures past the lock.
public struct FinanceSnapshot: Codable, Sendable, Equatable {
    /// App Group identifier shared by the app, widget extension, and intents.
    /// Matches `GlanceSnapshot.appGroupIdentifier` so a single container backs
    /// every sharing surface.
    public static let appGroupIdentifier = "group.com.ftchvs.PlaidBar"
    public static let filename = "finance-snapshot.json"

    /// One spendable/holding account, reduced to a display label and a balance.
    /// No Plaid identifiers — `displayName` is the same name the popover shows.
    public struct AccountBalance: Codable, Sendable, Equatable, Identifiable {
        public let displayName: String
        public let balance: Double
        public let isoCurrencyCode: String?

        public var id: String { displayName }

        public init(displayName: String, balance: Double, isoCurrencyCode: String? = nil) {
            self.displayName = displayName
            self.balance = balance
            self.isoCurrencyCode = isoCurrencyCode
        }
    }

    /// One upcoming recurring obligation, reduced to a merchant label, amount,
    /// and the next expected date string (`yyyy-MM-dd`).
    public struct UpcomingBill: Codable, Sendable, Equatable, Identifiable {
        public let merchantName: String
        public let amount: Double
        public let nextExpectedDate: String

        public var id: String { "\(merchantName)-\(nextExpectedDate)" }

        public init(merchantName: String, amount: Double, nextExpectedDate: String) {
            self.merchantName = merchantName
            self.amount = amount
            self.nextExpectedDate = nextExpectedDate
        }
    }

    /// Conservative discretionary balance through the look-ahead horizon
    /// (`SafeToSpendResult.amount`). May be negative — reported honestly.
    public let safeToSpend: Double
    /// Net cash / total spendable balance across depository accounts.
    public let totalBalance: Double
    /// Per-account spendable balances, display-safe.
    public let accountBalances: [AccountBalance]
    /// Upcoming recurring bills within the look-ahead window, soonest first.
    public let nextRecurringBills: [UpcomingBill]
    /// Aggregate credit utilization percent (0–100), nil when no credit limit
    /// is known.
    public let creditUtilization: Double?
    /// ISO currency code for the headline figures (best-effort; "USD" default).
    public let isoCurrencyCode: String
    /// When the snapshot was produced.
    public let generatedAt: Date
    /// True when App Lock / Privacy Mask is active. Intents must withhold values
    /// while this is set.
    public let isMasked: Bool

    public init(
        safeToSpend: Double,
        totalBalance: Double,
        accountBalances: [AccountBalance],
        nextRecurringBills: [UpcomingBill],
        creditUtilization: Double?,
        isoCurrencyCode: String = "USD",
        generatedAt: Date,
        isMasked: Bool
    ) {
        self.safeToSpend = safeToSpend
        self.totalBalance = totalBalance
        self.accountBalances = accountBalances
        self.nextRecurringBills = nextRecurringBills
        self.creditUtilization = creditUtilization
        self.isoCurrencyCode = isoCurrencyCode
        self.generatedAt = generatedAt
        self.isMasked = isMasked
    }

    /// Empty placeholder used before the first real snapshot exists. Treated as
    /// "no data yet" by the intents rather than a misleading "$0".
    public static func placeholder(generatedAt: Date = Date()) -> FinanceSnapshot {
        FinanceSnapshot(
            safeToSpend: 0,
            totalBalance: 0,
            accountBalances: [],
            nextRecurringBills: [],
            creditUtilization: nil,
            generatedAt: generatedAt,
            isMasked: false
        )
    }

    /// True when the snapshot carries no usable figures (no accounts and no
    /// bills). Used to drive a setup/unavailable intent response.
    public var isEmpty: Bool {
        accountBalances.isEmpty && nextRecurringBills.isEmpty && totalBalance == 0
    }
}
