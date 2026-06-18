import Foundation

/// Synthetic demo-mode fixture data shared by `--demo` launches, screenshots,
/// and tests.
///
/// Every account, balance, merchant, and amount here is invented. Nothing maps
/// to a real institution login, Plaid item, or person — keep it that way: this
/// data ships in README screenshots and public demo builds.
///
/// Continuity contract (locked in by `DemoFixturesTests`):
/// - The explicit set covers the most recent ~60 days; the historical
///   generator bridges from day 43 through day 364, so the year-long spending
///   heatmap (`MainPopover` uses a 364-day lookback) never shows a blank
///   week column.
/// - Income recurs monthly across the entire year (explicit DIRECT DEPOSIT
///   entries for the recent window, then the historical Employer series), so
///   the cashflow heatmap mode reads two-sided everywhere.
/// - `demo_savings` has activity inside the trailing 30 days, so its
///   account-detail Changes block is never $0 in / $0 out.
public enum DemoFixtures {
    /// Net worth implied by `accounts`:
    /// 8,241.56 + 15,420.00 − 1,847.32 − 4,210.00.
    public static let netWorth = 17_604.24

    public static let accounts: [AccountDTO] = [
        AccountDTO(
            id: "demo_checking", itemId: "demo_chase", name: "Chase Checking",
            officialName: "Chase Total Checking", type: .depository, subtype: "checking",
            mask: "4892", balances: BalanceDTO(available: 8_241.56, current: 8_241.56, isoCurrencyCode: "USD"),
            institutionName: "Chase"
        ),
        AccountDTO(
            id: "demo_savings", itemId: "demo_chase", name: "Chase Savings",
            officialName: "Chase Savings", type: .depository, subtype: "savings",
            mask: "7731", balances: BalanceDTO(available: 15_420.00, current: 15_420.00, isoCurrencyCode: "USD"),
            institutionName: "Chase"
        ),
        AccountDTO(
            id: "demo_amex", itemId: "demo_amex_item", name: "Amex Platinum",
            officialName: "American Express Platinum Card", type: .credit, subtype: "credit card",
            mask: "1008", balances: BalanceDTO(current: -1_847.32, limit: 20_000, isoCurrencyCode: "USD"),
            institutionName: "American Express"
        ),
        AccountDTO(
            id: "demo_visa", itemId: "demo_chase", name: "Chase Freedom",
            officialName: "Chase Freedom Unlimited", type: .credit, subtype: "credit card",
            mask: "3345", balances: BalanceDTO(current: -4_210.00, limit: 5_000, isoCurrencyCode: "USD"),
            institutionName: "Chase"
        ),
    ]

    /// Demo liabilities for the two demo credit cards, with due dates derived
    /// from `now` so `--demo` and screenshots never go stale. Mirrors the trimmed
    /// `LiabilityDTO` (APR + next due date + overdue).
    public static func liabilities(now: Date = Date(), calendar: Calendar = .current) -> [LiabilityDTO] {
        func due(inDays days: Int) -> String {
            dateString(daysAgo: -days, now: now, calendar: calendar)
        }
        return [
            LiabilityDTO(accountId: "demo_amex", purchaseAprPercentage: 21.24, nextPaymentDueDate: due(inDays: 9), isOverdue: false),
            LiabilityDTO(accountId: "demo_visa", purchaseAprPercentage: 24.99, nextPaymentDueDate: due(inDays: 16), isOverdue: false),
        ]
    }

    /// Explicit recent transactions plus the deterministic historical series.
    public static func transactions(now: Date = Date(), calendar: Calendar = .current) -> [TransactionDTO] {
        explicitTransactions(now: now, calendar: calendar)
            + historicalTransactions(now: now, calendar: calendar)
            + forgottenSubscriptionTransactions(now: now, calendar: calendar)
    }

    /// A small, long-running subscription seeded so `--demo` always shows the
    /// "You may have forgotten this" callout (AND-497). $4.99/mo "Cloud Backup"
    /// (Netflix is in the cancel-guidance map for a non-generic link; this one is
    /// deliberately small and obscure so it reads as easy-to-forget). Twelve
    /// monthly occurrences land well over the forgotten min-cycle threshold, the
    /// fixed amount keeps the detected average under the cost ceiling, and the
    /// most recent charge is recent so it is never read as stale.
    private static func forgottenSubscriptionTransactions(now: Date, calendar: Calendar) -> [TransactionDTO] {
        (0..<12).map { monthsAgo in
            let daysAgo = 4 + (monthsAgo * 30)
            return TransactionDTO(
                id: "demo_forgotten_cloud_\(monthsAgo)",
                accountId: "demo_visa",
                amount: 4.99,
                date: dateString(daysAgo: daysAgo, now: now, calendar: calendar),
                name: "CLOUDVAULT BACKUP",
                merchantName: "CloudVault",
                category: .subscriptions
            )
        }
    }

    /// Seeded watchlist nudges for demo mode (AND-501). Chosen so they cross
    /// against the demo transactions' month-to-date spend (Starbucks coffees and
    /// the Shopping category both clear early), populating the Settings
    /// Watchlists section and firing the evaluator in `--demo`. Fixed UUIDs keep
    /// the order and identity deterministic for screenshots.
    public static func watchlistTargets() -> [WatchlistTarget] {
        [
            WatchlistTarget.merchant(
                "Starbucks",
                threshold: 10,
                id: UUID(uuidString: "00000000-0000-0000-0000-0000000000A1")!
            ),
            WatchlistTarget.category(
                .shopping,
                threshold: 200,
                id: UUID(uuidString: "00000000-0000-0000-0000-0000000000A2")!
            ),
        ]
    }

    /// Deterministic 60-day net-worth history with a gentle upward drift so the
    /// header trend reads the same on every demo launch and screenshots
    /// reproduce.
    public static func balanceHistory(now: Date = Date(), calendar: Calendar = .current) -> [BalanceSnapshot] {
        (0..<60).reversed().map { daysAgo in
            let date = calendar.date(byAdding: .day, value: -daysAgo, to: now) ?? now
            let progress = Double(60 - daysAgo) / 60
            let drift = -650.0 + (650.0 * progress)
            let wobble = sin(Double(daysAgo) / 4.5) * 180
            return BalanceSnapshot(date: date, balance: netWorth + drift + wobble)
        }
    }

    public static func accountBalanceHistory(
        forAccountId accountId: String,
        now: Date = Date(),
        calendar: Calendar = .current
    ) -> [BalanceSnapshot] {
        guard let accountIndex = accounts.firstIndex(where: { $0.id == accountId }),
              let currentBalance = accounts[accountIndex].balances.current ?? accounts[accountIndex].balances.available
        else {
            return []
        }

        let amplitude = max(abs(currentBalance) * 0.045, 120 + (Double(accountIndex) * 35))
        let direction = accountIndex.isMultiple(of: 2) ? 1.0 : -1.0

        return (0..<60).reversed().map { daysAgo in
            let date = calendar.date(byAdding: .day, value: -daysAgo, to: now) ?? now
            let progress = Double(59 - daysAgo) / 59
            let drift = -direction * amplitude * (1 - progress)
            let wobble = daysAgo == 0 ? 0 : sin((Double(daysAgo) + Double(accountIndex)) / 5.5) * (amplitude * 0.18)
            return BalanceSnapshot(date: date, balance: currentBalance + drift + wobble)
        }
    }

    // MARK: - Explicit recent window

    private static func explicitTransactions(now: Date, calendar: Calendar) -> [TransactionDTO] {
        let today = dateString(daysAgo: 0, now: now, calendar: calendar)
        let yesterday = dateString(daysAgo: 1, now: now, calendar: calendar)
        let twoDaysAgo = dateString(daysAgo: 2, now: now, calendar: calendar)
        let threeDaysAgo = dateString(daysAgo: 3, now: now, calendar: calendar)
        let oneWeekAgo = dateString(daysAgo: 8, now: now, calendar: calendar)
        let twoWeeksAgo = dateString(daysAgo: 15, now: now, calendar: calendar)
        let threeWeeksAgo = dateString(daysAgo: 22, now: now, calendar: calendar)
        let nearlyFourWeeksAgo = dateString(daysAgo: 26, now: now, calendar: calendar)
        let oneMonthAgo = dateString(daysAgo: 30, now: now, calendar: calendar)
        let fiveWeeksAgo = dateString(daysAgo: 35, now: now, calendar: calendar)
        let sixWeeksAgo = dateString(daysAgo: 42, now: now, calendar: calendar)
        let twoMonthsAgo = dateString(daysAgo: 60, now: now, calendar: calendar)

        return [
            // Today
            TransactionDTO(id: "tx1", accountId: "demo_checking", amount: 67.42, date: today, name: "WHOLEFDS MKT 10234", merchantName: "Whole Foods", category: .foodAndDrink),
            TransactionDTO(id: "tx2", accountId: "demo_checking", amount: 23.50, date: today, name: "UBER TRIP", merchantName: "Uber", category: .transportation),
            TransactionDTO(id: "tx3", accountId: "demo_checking", amount: -3_200.00, date: today, name: "STRIPE TRANSFER", merchantName: "Stripe", category: .income),
            TransactionDTO(id: "tx4", accountId: "demo_amex", amount: 142.80, date: today, name: "AMAZON.COM", merchantName: "Amazon", category: .shopping),
            // Yesterday
            TransactionDTO(id: "tx5", accountId: "demo_checking", amount: 15.99, date: yesterday, name: "NETFLIX.COM", merchantName: "Netflix", category: .entertainment),
            TransactionDTO(id: "tx6", accountId: "demo_checking", amount: 45.00, date: yesterday, name: "SHELL OIL 57422", merchantName: "Shell", category: .transportation),
            TransactionDTO(id: "tx7", accountId: "demo_amex", amount: 89.00, date: yesterday, name: "BLUE APRON", merchantName: "Blue Apron", category: .foodAndDrink),
            TransactionDTO(id: "tx8", accountId: "demo_visa", amount: 34.50, date: yesterday, name: "SPOTIFY", merchantName: "Spotify", category: .entertainment),
            // 2 days ago
            TransactionDTO(id: "tx9", accountId: "demo_checking", amount: 250.00, date: twoDaysAgo, name: "VERIZON WIRELESS", merchantName: "Verizon", category: .billsAndUtilities),
            TransactionDTO(id: "tx10", accountId: "demo_amex", amount: 320.00, date: twoDaysAgo, name: "DELTA AIR LINES", merchantName: "Delta Airlines", category: .travel),
            TransactionDTO(id: "tx11", accountId: "demo_checking", amount: 12.50, date: twoDaysAgo, name: "STARBUCKS 8823", merchantName: "Starbucks", category: .foodAndDrink),
            TransactionDTO(id: "tx12", accountId: "demo_amex", amount: 650.00, date: twoDaysAgo, name: "FURNITURE STORE", merchantName: "West Elm", category: .shopping, pending: true),
            // Pending OUTFLOW on a depository (cash) account so the pending-aware
            // safe-to-spend holds component is non-zero in --demo (AND-499). tx12
            // is on a credit account and is therefore excluded from cash holds.
            TransactionDTO(id: "tx48", accountId: "demo_checking", amount: 86.40, date: today, name: "TRADER JOES 442", merchantName: "Trader Joe's", category: .foodAndDrink, pending: true),
            // 3 days ago
            TransactionDTO(id: "tx13", accountId: "demo_visa", amount: 75.00, date: threeDaysAgo, name: "PLANET FITNESS", merchantName: "Planet Fitness", category: .healthAndFitness),
            TransactionDTO(id: "tx14", accountId: "demo_checking", amount: -1_500.00, date: threeDaysAgo, name: "VENMO PAYMENT", merchantName: "Venmo", category: .income),
            TransactionDTO(id: "tx15", accountId: "demo_amex", amount: 55.00, date: threeDaysAgo, name: "TARGET 0392", merchantName: "Target", category: .shopping),
            TransactionDTO(id: "tx16", accountId: "demo_checking", amount: 1_850.00, date: threeDaysAgo, name: "RENT PAYMENT", merchantName: "Rent Payment", category: .billsAndUtilities),
            // ~1 week ago
            TransactionDTO(id: "tx17", accountId: "demo_checking", amount: 85.00, date: oneWeekAgo, name: "COSTCO WHOLESALE", merchantName: "Costco", category: .shopping),
            TransactionDTO(id: "tx18", accountId: "demo_amex", amount: 220.00, date: oneWeekAgo, name: "AIRBNB", merchantName: "Airbnb", category: .travel),
            TransactionDTO(id: "tx19", accountId: "demo_checking", amount: -2_800.00, date: oneWeekAgo, name: "DIRECT DEPOSIT", merchantName: "Employer", category: .income),
            TransactionDTO(id: "tx20", accountId: "demo_visa", amount: 42.00, date: oneWeekAgo, name: "DOORDASH", merchantName: "DoorDash", category: .foodAndDrink),
            // ~2 weeks ago
            TransactionDTO(id: "tx21", accountId: "demo_checking", amount: 130.00, date: twoWeeksAgo, name: "CON EDISON", merchantName: "Con Edison", category: .billsAndUtilities),
            TransactionDTO(id: "tx22", accountId: "demo_amex", amount: 64.99, date: twoWeeksAgo, name: "ADOBE CREATIVE", merchantName: "Adobe", category: .entertainment),
            TransactionDTO(id: "tx23", accountId: "demo_checking", amount: 95.00, date: twoWeeksAgo, name: "CVS PHARMACY", merchantName: "CVS", category: .healthAndFitness),
            // ~3 weeks ago
            TransactionDTO(id: "tx24", accountId: "demo_visa", amount: 175.00, date: threeWeeksAgo, name: "NORDSTROM", merchantName: "Nordstrom", category: .shopping),
            TransactionDTO(id: "tx25", accountId: "demo_checking", amount: 48.00, date: threeWeeksAgo, name: "LYFT RIDE", merchantName: "Lyft", category: .transportation),
            TransactionDTO(id: "tx26", accountId: "demo_amex", amount: 35.00, date: threeWeeksAgo, name: "HULU", merchantName: "Hulu", category: .entertainment),
            // ~4 weeks ago — bridges the day-23..29 quiet stretch so no
            // calendar week in the heatmap is fully blank.
            TransactionDTO(id: "tx42", accountId: "demo_checking", amount: 14.25, date: nearlyFourWeeksAgo, name: "STARBUCKS 8823", merchantName: "Starbucks", category: .foodAndDrink),

            // === ~1 month ago — recurring merchants (2nd occurrence) ===
            TransactionDTO(id: "tx27", accountId: "demo_checking", amount: 15.99, date: oneMonthAgo, name: "NETFLIX.COM", merchantName: "Netflix", category: .entertainment),
            TransactionDTO(id: "tx28", accountId: "demo_visa", amount: 34.50, date: oneMonthAgo, name: "SPOTIFY", merchantName: "Spotify", category: .entertainment),
            TransactionDTO(id: "tx29", accountId: "demo_visa", amount: 75.00, date: oneMonthAgo, name: "PLANET FITNESS", merchantName: "Planet Fitness", category: .healthAndFitness),
            TransactionDTO(id: "tx30", accountId: "demo_checking", amount: 1_850.00, date: oneMonthAgo, name: "RENT PAYMENT", merchantName: "Rent Payment", category: .billsAndUtilities),
            TransactionDTO(id: "tx31", accountId: "demo_checking", amount: -2_800.00, date: oneMonthAgo, name: "DIRECT DEPOSIT", merchantName: "Employer", category: .income),
            TransactionDTO(id: "tx32", accountId: "demo_checking", amount: 72.00, date: fiveWeeksAgo, name: "WHOLEFDS MKT 10234", merchantName: "Whole Foods", category: .foodAndDrink),
            TransactionDTO(id: "tx33", accountId: "demo_amex", amount: 38.00, date: fiveWeeksAgo, name: "HULU", merchantName: "Hulu", category: .entertainment),
            TransactionDTO(id: "tx34", accountId: "demo_amex", amount: 64.99, date: sixWeeksAgo, name: "ADOBE CREATIVE", merchantName: "Adobe", category: .entertainment),

            // === ~2 months ago — recurring merchants (3rd occurrence) ===
            TransactionDTO(id: "tx35", accountId: "demo_checking", amount: 15.99, date: twoMonthsAgo, name: "NETFLIX.COM", merchantName: "Netflix", category: .entertainment),
            TransactionDTO(id: "tx36", accountId: "demo_visa", amount: 34.50, date: twoMonthsAgo, name: "SPOTIFY", merchantName: "Spotify", category: .entertainment),
            TransactionDTO(id: "tx37", accountId: "demo_visa", amount: 75.00, date: twoMonthsAgo, name: "PLANET FITNESS", merchantName: "Planet Fitness", category: .healthAndFitness),
            TransactionDTO(id: "tx38", accountId: "demo_checking", amount: 1_850.00, date: twoMonthsAgo, name: "RENT PAYMENT", merchantName: "Rent Payment", category: .billsAndUtilities),
            TransactionDTO(id: "tx39", accountId: "demo_checking", amount: -2_800.00, date: twoMonthsAgo, name: "DIRECT DEPOSIT", merchantName: "Employer", category: .income),
            TransactionDTO(id: "tx40", accountId: "demo_amex", amount: 64.99, date: twoMonthsAgo, name: "ADOBE CREATIVE", merchantName: "Adobe", category: .entertainment),
            TransactionDTO(id: "tx41", accountId: "demo_amex", amount: 36.00, date: twoMonthsAgo, name: "HULU", merchantName: "Hulu", category: .entertainment),

            // === demo_savings — keeps the savings fly-out's 30-day Changes
            // block two-sided (interest in, service fee out). Fee rows keep a
            // nil merchant so RecurringDetector ignores them.
            TransactionDTO(id: "tx43", accountId: "demo_savings", amount: -38.12, date: threeDaysAgo, name: "INTEREST PAYMENT", merchantName: "Chase Interest", category: .income),
            TransactionDTO(id: "tx44", accountId: "demo_savings", amount: 5.00, date: twoDaysAgo, name: "MONTHLY SERVICE FEE", category: .bankFees),
            TransactionDTO(id: "tx45", accountId: "demo_savings", amount: -36.40, date: oneMonthAgo, name: "INTEREST PAYMENT", merchantName: "Chase Interest", category: .income),
            TransactionDTO(id: "tx46", accountId: "demo_savings", amount: 5.00, date: oneMonthAgo, name: "MONTHLY SERVICE FEE", category: .bankFees),
            TransactionDTO(id: "tx47", accountId: "demo_savings", amount: -37.18, date: twoMonthsAgo, name: "INTEREST PAYMENT", merchantName: "Chase Interest", category: .income),
        ]
    }

    // MARK: - Historical series (days 43...364)

    private struct DemoMerchant {
        let interval: Int
        /// Days-ago of the first generated occurrence. Frequent merchants
        /// start at day 43 to bridge straight out of the explicit set; the
        /// monthly Rent/Employer pair starts one interval after its last
        /// explicit occurrence (day 60) so the cadence stays believable.
        let firstDayAgo: Int
        let accountId: String
        let amount: Double
        let name: String
        let merchantName: String
        let category: SpendingCategory
    }

    private static func historicalTransactions(now: Date, calendar: Calendar) -> [TransactionDTO] {
        let merchants = [
            DemoMerchant(interval: 7, firstDayAgo: 43, accountId: "demo_checking", amount: 78.40, name: "WHOLEFDS MKT 10234", merchantName: "Whole Foods", category: .foodAndDrink),
            DemoMerchant(interval: 10, firstDayAgo: 45, accountId: "demo_amex", amount: 42.25, name: "SWEETGREEN", merchantName: "Sweetgreen", category: .foodAndDrink),
            DemoMerchant(interval: 14, firstDayAgo: 48, accountId: "demo_checking", amount: 28.60, name: "UBER TRIP", merchantName: "Uber", category: .transportation),
            DemoMerchant(interval: 16, firstDayAgo: 51, accountId: "demo_visa", amount: 63.15, name: "TARGET 0392", merchantName: "Target", category: .shopping),
            DemoMerchant(interval: 21, firstDayAgo: 56, accountId: "demo_amex", amount: 118.90, name: "COSTCO WHOLESALE", merchantName: "Costco", category: .shopping),
            DemoMerchant(interval: 30, firstDayAgo: 45, accountId: "demo_checking", amount: 132.00, name: "CON EDISON", merchantName: "Con Edison", category: .billsAndUtilities),
            DemoMerchant(interval: 31, firstDayAgo: 91, accountId: "demo_checking", amount: 1_850.00, name: "RENT PAYMENT", merchantName: "Rent Payment", category: .billsAndUtilities),
            DemoMerchant(interval: 45, firstDayAgo: 77, accountId: "demo_amex", amount: 310.00, name: "DELTA AIR LINES", merchantName: "Delta Airlines", category: .travel),
            // Year-round income: monthly paychecks continuing the explicit
            // DIRECT DEPOSIT cadence (days 8/30/60), so the cashflow heatmap
            // mode is two-sided across the whole 364-day window.
            DemoMerchant(interval: 31, firstDayAgo: 90, accountId: "demo_checking", amount: -2_800.00, name: "DIRECT DEPOSIT", merchantName: "Employer", category: .income),
        ]

        return merchants.flatMap { merchant in
            stride(from: merchant.firstDayAgo, through: 364, by: merchant.interval).map { daysAgo in
                let merchantSlug = merchant.merchantName
                    .lowercased()
                    .replacingOccurrences(of: " ", with: "_")
                return TransactionDTO(
                    id: "demo_hist_\(merchantSlug)_\(daysAgo)",
                    accountId: merchant.accountId,
                    amount: merchant.amount + seasonalAdjustment(daysAgo: daysAgo, interval: merchant.interval),
                    date: dateString(daysAgo: daysAgo, now: now, calendar: calendar),
                    name: merchant.name,
                    merchantName: merchant.merchantName,
                    category: merchant.category
                )
            }
        }
    }

    private static func seasonalAdjustment(daysAgo: Int, interval: Int) -> Double {
        let cycle = Double((daysAgo / max(interval, 1)) % 5)
        return cycle * 8.75
    }

    private static func dateString(daysAgo: Int, now: Date, calendar: Calendar) -> String {
        let date = calendar.date(byAdding: .day, value: -daysAgo, to: now) ?? now
        return Formatters.transactionDateString(date)
    }
}
