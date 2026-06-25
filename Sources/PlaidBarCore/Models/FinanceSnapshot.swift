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

    /// Per-currency spendable balance subtotal. This lets App Intents and widgets
    /// avoid collapsing mixed-currency accounts into one arbitrary headline.
    public struct CurrencySubtotal: Codable, Sendable, Equatable, Identifiable {
        public let currency: CurrencyCode
        public let amount: Double

        public var id: String { currency.rawValue }

        public init(currency: CurrencyCode, amount: Double) {
            self.currency = currency
            self.amount = amount
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

    /// One spending category's period total, reduced to a stable category-key, a
    /// user-facing label, and the amount spent. The `categoryKey` is the
    /// ``SpendingCategory`` raw value so a reader (the "show spending" intent, the
    /// Spotlight snippet, a `systemLarge` widget) can recover the icon/colour from
    /// `SpendingCategory(rawValue:)` without the snapshot carrying UI concerns.
    public struct CategorySpend: Codable, Sendable, Equatable, Identifiable {
        public let categoryKey: String
        public let displayName: String
        public let amount: Double

        public var id: String { categoryKey }

        /// The ``SpendingCategory`` this row maps to, or `nil` for an unknown key
        /// (forward-compat if a future build adds a category this one can't decode).
        public var category: SpendingCategory? { SpendingCategory(rawValue: categoryKey) }

        public init(categoryKey: String, displayName: String, amount: Double) {
            self.categoryKey = categoryKey
            self.displayName = displayName
            self.amount = amount
        }

        public init(category: SpendingCategory, amount: Double) {
            self.categoryKey = category.rawValue
            self.displayName = category.displayName
            self.amount = amount
        }
    }

    /// Conservative discretionary balance through the look-ahead horizon
    /// (`SafeToSpendResult.amount`). May be negative — reported honestly.
    public let safeToSpend: Double
    /// Net cash / total spendable balance across depository accounts.
    public let totalBalance: Double
    /// Per-account spendable balances, display-safe.
    public let accountBalances: [AccountBalance]
    /// Native-currency subtotals for ``accountBalances``.
    public let currencySubtotals: [CurrencySubtotal]
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
    /// Total spend across the current period (month-to-date), used by the
    /// "show spending" intent and the Spotlight snippet. Zero when unknown.
    public let periodSpending: Double
    /// Top spending categories this period, largest first, already truncated to a
    /// small count (the writer keeps only the leaders). Empty when unknown.
    public let topSpendingCategories: [CategorySpend]
    /// How much trust to place in `safeToSpend`, mirroring
    /// ``SafeToSpendResult/confidence`` so the safe-to-spend snippet can show the
    /// same "Estimate only / Lower confidence / On track" cue the in-app view does.
    /// `nil` for a pre-AND-637 snapshot (decoded defensively) — the snippet then
    /// simply omits the cue.
    public let safeToSpendConfidence: SafeToSpendConfidence?
    /// Inclusive end of the look-ahead window `safeToSpend` covers, mirroring
    /// ``SafeToSpendResult/horizonEnd`` so the snippet can say "through <date>"
    /// without re-deriving the horizon. `nil` for a pre-AND-637 snapshot.
    public let safeToSpendHorizonEnd: Date?

    public init(
        safeToSpend: Double,
        totalBalance: Double,
        accountBalances: [AccountBalance],
        currencySubtotals: [CurrencySubtotal] = [],
        nextRecurringBills: [UpcomingBill],
        creditUtilization: Double?,
        isoCurrencyCode: String = "USD",
        generatedAt: Date,
        isMasked: Bool,
        periodSpending: Double = 0,
        topSpendingCategories: [CategorySpend] = [],
        safeToSpendConfidence: SafeToSpendConfidence? = nil,
        safeToSpendHorizonEnd: Date? = nil
    ) {
        self.safeToSpend = safeToSpend
        self.totalBalance = totalBalance
        self.accountBalances = accountBalances
        self.currencySubtotals = currencySubtotals
        self.nextRecurringBills = nextRecurringBills
        self.creditUtilization = creditUtilization
        self.isoCurrencyCode = isoCurrencyCode
        self.generatedAt = generatedAt
        self.isMasked = isMasked
        self.periodSpending = periodSpending
        self.topSpendingCategories = topSpendingCategories
        self.safeToSpendConfidence = safeToSpendConfidence
        self.safeToSpendHorizonEnd = safeToSpendHorizonEnd
    }

    // Decode the spending fields defensively: a snapshot written by an older build
    // (no `periodSpending` / `topSpendingCategories` keys) decodes them as their
    // empty defaults, so an upgrade never fails to read a pre-AND-586 snapshot.
    private enum CodingKeys: String, CodingKey {
        case safeToSpend, totalBalance, accountBalances, nextRecurringBills
        case currencySubtotals, creditUtilization, isoCurrencyCode, generatedAt, isMasked
        case periodSpending, topSpendingCategories
        case safeToSpendConfidence, safeToSpendHorizonEnd
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        safeToSpend = try container.decode(Double.self, forKey: .safeToSpend)
        totalBalance = try container.decode(Double.self, forKey: .totalBalance)
        accountBalances = try container.decode([AccountBalance].self, forKey: .accountBalances)
        currencySubtotals = try container.decodeIfPresent([CurrencySubtotal].self, forKey: .currencySubtotals) ?? []
        nextRecurringBills = try container.decode([UpcomingBill].self, forKey: .nextRecurringBills)
        creditUtilization = try container.decodeIfPresent(Double.self, forKey: .creditUtilization)
        isoCurrencyCode = try container.decodeIfPresent(String.self, forKey: .isoCurrencyCode) ?? "USD"
        generatedAt = try container.decode(Date.self, forKey: .generatedAt)
        isMasked = try container.decode(Bool.self, forKey: .isMasked)
        periodSpending = try container.decodeIfPresent(Double.self, forKey: .periodSpending) ?? 0
        topSpendingCategories = try container.decodeIfPresent([CategorySpend].self, forKey: .topSpendingCategories) ?? []
        // Defensive: a pre-AND-637 snapshot has neither key — decode them as nil so
        // the upgrade still reads the older payload, and an unknown confidence raw
        // value degrades to nil rather than throwing the whole read.
        safeToSpendConfidence = try container.decodeIfPresent(SafeToSpendConfidence.self, forKey: .safeToSpendConfidence)
        safeToSpendHorizonEnd = try container.decodeIfPresent(Date.self, forKey: .safeToSpendHorizonEnd)
    }

    /// Empty placeholder used before the first real snapshot exists. Treated as
    /// "no data yet" by the intents rather than a misleading "$0".
    public static func placeholder(generatedAt: Date = Date()) -> FinanceSnapshot {
        FinanceSnapshot(
            safeToSpend: 0,
            totalBalance: 0,
            accountBalances: [],
            currencySubtotals: [],
            nextRecurringBills: [],
            creditUtilization: nil,
            generatedAt: generatedAt,
            isMasked: false
        )
    }

    /// Returns the value-free, `isMasked == true` form of this snapshot: every
    /// figure zeroed, every list emptied, only the timestamp and currency code
    /// preserved. Mirrors the inline masked construction in
    /// ``FinanceSnapshotBuilder`` so the app and the widget extension can re-redact
    /// an already-persisted snapshot the instant Privacy Mask is enabled (from the
    /// Control Center control / Focus filter) instead of leaking real balances
    /// until the app is next foregrounded.
    ///
    /// Idempotent: calling `masked()` on an already-masked snapshot returns an
    /// equivalent value-free snapshot.
    public func masked() -> FinanceSnapshot {
        FinanceSnapshot(
            safeToSpend: 0,
            totalBalance: 0,
            accountBalances: [],
            currencySubtotals: [],
            nextRecurringBills: [],
            creditUtilization: nil,
            isoCurrencyCode: isoCurrencyCode,
            generatedAt: generatedAt,
            isMasked: true
        )
    }

    /// True when the snapshot carries no usable figures. Used to drive a
    /// setup/unavailable intent response. A credit-only user (paid-off cards, no
    /// cash accounts, no bills) still has a usable `creditUtilization`, so a
    /// non-nil utilization keeps the snapshot non-empty. Likewise a user with
    /// recorded spend but no linked cash account stays non-empty.
    public var isEmpty: Bool {
        accountBalances.isEmpty
            && nextRecurringBills.isEmpty
            && totalBalance == 0
            && creditUtilization == nil
            && periodSpending == 0
            && topSpendingCategories.isEmpty
    }

    public var hasMixedCurrencyBalances: Bool {
        let currencies = currencySubtotals.isEmpty
            ? accountBalances.map { CurrencyCode($0.isoCurrencyCode) }
            : currencySubtotals.map(\.currency)
        return Set(currencies).count > 1
    }

    public var currencySubtotalText: String {
        let subtotals = currencySubtotals.isEmpty
            ? CurrencyAggregation.aggregate(accountBalances.map {
                (amount: $0.balance, currency: CurrencyCode($0.isoCurrencyCode))
            }).subtotals
            : currencySubtotals.map {
                CurrencyAggregation.Subtotal(currency: $0.currency, amount: $0.amount)
            }
        return MultiCurrencyBalancePresentation.subtotalRows(
            from: CurrencyAggregation(subtotals: subtotals, convertedTotal: .unavailable),
            format: .full,
            privacyMaskEnabled: isMasked
        )
        .map { "\($0.currency.rawValue) \($0.formattedAmount)" }
        .joined(separator: ", ")
    }
}
