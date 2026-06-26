import Foundation

public enum MenuBarSummaryMode: String, CaseIterable, Codable, Sendable {
    case netWorth
    case netCash
    case totalCash
    case creditUtilization
    case highestUtilization
    case recentSpend
    case todaySpend
    case safeToSpend
    case iconOnly

    /// Human-readable name for this mode.
    ///
    /// - Important: this is a single source of truth used in **two** places — the
    ///   Settings picker label AND, via `MenuBarAnnouncement`, the menu-bar tooltip
    ///   and VoiceOver label (the spoken form is `displayName.lowercased()`). A
    ///   re-word here changes accessibility copy; `MenuBarAnnouncementTests` golden
    ///   literals will fail if the wording drifts. Split this out if the two uses
    ///   must diverge.
    public var displayName: String {
        switch self {
        case .netWorth: return "Net worth"
        case .netCash: return "Net cash"
        case .totalCash: return "Total cash"
        case .creditUtilization: return "Credit utilization"
        case .highestUtilization: return "Highest card utilization"
        case .recentSpend: return "Recent spend"
        case .todaySpend: return "Today's spend"
        case .safeToSpend: return "Safe to spend"
        case .iconOnly: return "Icon only"
        }
    }
}

public enum MenuBarSummary {
    public static func netWorth(from accounts: [AccountDTO]) -> Double {
        netCash(from: accounts)
    }

    public static func netCash(from accounts: [AccountDTO]) -> Double {
        accounts.reduce(0) { total, account in
            switch account.type {
            case .depository, .investment:
                return total + account.balances.effectiveBalance
            case .credit, .loan:
                return total - abs(account.balances.current ?? 0)
            case .other:
                return total + account.balances.effectiveBalance
            }
        }
    }

    public static func totalCash(from accounts: [AccountDTO]) -> Double {
        accounts
            .filter { $0.type == .depository }
            .reduce(0) { $0 + $1.balances.effectiveBalance }
    }

    public static func totalDebt(from accounts: [AccountDTO]) -> Double {
        accounts
            .filter(AccountPresentation.isDebt)
            .reduce(0) { $0 + AccountPresentation.displayBalance(for: $1) }
    }

    /// A credit-utilization figure scoped to a *single* currency. Used credit and
    /// total limit are only ever summed within one currency, so the ratio is
    /// always meaningful (AND-660). Pooling a EUR balance against a USD limit — the
    /// pre-AND-660 bug — produced a fabricated denominator and an arbitrary ratio
    /// that fed alerts, App Intents, and AI insights.
    public struct CurrencyUtilization: Sendable, Equatable {
        public let currency: CurrencyCode
        public let usedCredit: Double
        public let totalLimit: Double
        public let percent: Double

        public init(currency: CurrencyCode, usedCredit: Double, totalLimit: Double, percent: Double) {
            self.currency = currency
            self.usedCredit = usedCredit
            self.totalLimit = totalLimit
            self.percent = percent
        }
    }

    /// Per-currency credit utilization: groups credit-card accounts by their own
    /// currency and computes used/limit/percent *within* each currency, never
    /// across currencies (AND-660). Only currencies whose cards report a positive
    /// total limit are included (a denominator of 0 yields no meaningful ratio).
    /// Sorted by descending utilization, then currency, so the worst (most
    /// alert-worthy) currency is first and ties are deterministic.
    public static func creditUtilizationByCurrency(from accounts: [AccountDTO]) -> [CurrencyUtilization] {
        var usedByCurrency: [CurrencyCode: Double] = [:]
        var limitByCurrency: [CurrencyCode: Double] = [:]

        for account in accounts where account.type == .credit {
            let currency = account.balances.currency
            // A negative/garbage limit cannot anchor a denominator; clamp at 0 so
            // a stray value never inflates or deflates the ratio.
            limitByCurrency[currency, default: 0] += max(account.balances.limit ?? 0, 0)
            usedByCurrency[currency, default: 0] += abs(account.balances.current ?? 0)
        }

        return limitByCurrency
            .compactMap { currency, totalLimit -> CurrencyUtilization? in
                guard totalLimit > 0 else { return nil }
                let usedCredit = usedByCurrency[currency] ?? 0
                return CurrencyUtilization(
                    currency: currency,
                    usedCredit: usedCredit,
                    totalLimit: totalLimit,
                    percent: (usedCredit / totalLimit) * 100
                )
            }
            .sorted { lhs, rhs in
                if lhs.percent != rhs.percent { return lhs.percent > rhs.percent }
                return lhs.currency < rhs.currency
            }
    }

    /// The single utilization currency-group that best represents the user's
    /// credit risk: the **highest** per-currency utilization (AND-660). This is
    /// the figure surfaced as the headline and the one that decides whether the
    /// high-utilization alert fires — so a maxed-out EUR card still trips the
    /// threshold even when a large USD limit would dilute a pooled ratio.
    /// Returns `nil` when no currency reports a positive total limit.
    public static func worstCreditUtilization(from accounts: [AccountDTO]) -> CurrencyUtilization? {
        creditUtilizationByCurrency(from: accounts).first
    }

    /// Headline credit-utilization percentage. **Per-currency** as of AND-660: the
    /// worst single-currency utilization, never a cross-currency pooled ratio.
    /// A same-currency portfolio is byte-identical to the pre-AND-660 value
    /// (one currency group → the old `used / limit`).
    public static func creditUtilization(from accounts: [AccountDTO]) -> Double? {
        worstCreditUtilization(from: accounts)?.percent
    }

    /// Highest single-card utilization (used/limit) across all credit cards,
    /// as a percentage. Distinct from `creditUtilization`, which pools every
    /// card's balance and limit into one aggregate ratio: a single near-maxed
    /// card can be invisible in the aggregate but is the number a user worried
    /// about utilization wants in the menu bar. Returns nil when no credit card
    /// reports a positive limit (cards without a limit are skipped, not zeroed).
    public static func highestUtilization(from accounts: [AccountDTO]) -> Double? {
        let ratios = accounts
            .filter { $0.type == .credit }
            .compactMap { account -> Double? in
                guard let limit = account.balances.limit, limit > 0 else { return nil }
                return (abs(account.balances.current ?? 0) / limit) * 100
            }
        return ratios.max()
    }

    public static func recentSpend(
        from transactions: [TransactionDTO],
        now: Date = Date(),
        calendar: Calendar = .current,
        days: Int = 7
    ) -> Double {
        let startDate = calendar.startOfDay(
            for: calendar.date(byAdding: .day, value: -(days - 1), to: now) ?? now
        )
        // Canonical yyyy-MM-dd keys compare lexicographically in date order, so
        // the window filter avoids a DateFormatter parse per transaction. This
        // runs on the menu bar label render path, where parsing dominated cost.
        let startKey = transactionDateKey(for: startDate, calendar: calendar)
        let endKey = transactionDateKey(for: calendar.startOfDay(for: now), calendar: calendar)

        return transactions.reduce(0) { total, transaction in
            guard !transaction.isIncome,
                  transaction.category != .transfer,
                  transaction.category != .transferOut,
                  Formatters.isCanonicalTransactionDateKey(transaction.date),
                  transaction.date >= startKey,
                  transaction.date <= endKey
            else {
                return total
            }
            return total + transaction.displayAmount
        }
    }

    public static func monthToDateSpend(
        from transactions: [TransactionDTO],
        now: Date = Date(),
        calendar: Calendar = .current
    ) -> Double {
        let currentDay = calendar.startOfDay(for: now)
        let components = calendar.dateComponents([.year, .month], from: currentDay)
        let startDate = calendar.date(from: components) ?? currentDay
        let startKey = transactionDateKey(for: startDate, calendar: calendar)
        let endKey = transactionDateKey(for: currentDay, calendar: calendar)

        return transactions.reduce(0) { total, transaction in
            guard !transaction.isIncome,
                  transaction.category != .transfer,
                  transaction.category != .transferOut,
                  Formatters.isCanonicalTransactionDateKey(transaction.date),
                  transaction.date >= startKey,
                  transaction.date <= endKey
            else {
                return total
            }
            return total + transaction.displayAmount
        }
    }

    private static func transactionDateKey(for date: Date, calendar: Calendar) -> String {
        let components = calendar.dateComponents([.year, .month, .day], from: date)
        guard let year = components.year,
              let month = components.month,
              let day = components.day
        else {
            return Formatters.transactionDateString(date)
        }
        return String(format: "%04d-%02d-%02d", year, month, day)
    }

    public static func runwayMonths(
        cash: Double,
        transactions: [TransactionDTO],
        now: Date = Date(),
        calendar: Calendar = .current
    ) -> Double? {
        let monthlySpend = runwayMonthlySpend(from: transactions, now: now, calendar: calendar)
        return runwayMonths(cash: cash, monthlySpend: monthlySpend)
    }

    public static func runwayMonthlySpend(
        from transactions: [TransactionDTO],
        now: Date = Date(),
        calendar: Calendar = .current
    ) -> Double {
        recentSpend(
            from: transactions,
            now: now,
            calendar: calendar,
            days: 30
        )
    }

    public static func runwayMonths(cash: Double, monthlySpend: Double) -> Double? {
        guard cash > 0, monthlySpend > 0 else { return nil }
        return cash / monthlySpend
    }

    public static func runwayText(months: Double?) -> String {
        guard let months else { return "No spend" }
        if months < 1 {
            let days = max(Int((months * 30).rounded()), 1)
            return "\(days)d"
        }
        if months < 10 {
            return String(format: "%.1f mo", months)
        }
        return "\(Int(months.rounded())) mo"
    }

    public static func runwayBasisText(
        cash: Double,
        monthlySpend: Double,
        currencyFormat: CurrencyFormat = .compact
    ) -> String {
        guard cash > 0 else { return "No cash buffer" }
        guard monthlySpend > 0 else { return "No 30D spend" }
        return "30D spend \(Formatters.currency(monthlySpend, format: currencyFormat))"
    }

    public static func text(
        mode: MenuBarSummaryMode,
        accounts: [AccountDTO],
        transactions: [TransactionDTO],
        currencyFormat: CurrencyFormat,
        isInitialLoad: Bool = false,
        privacyMaskEnabled: Bool = false,
        precomputedSafeToSpend: Double? = nil
    ) -> String {
        switch mode {
        case .netWorth:
            guard !accounts.isEmpty else { return PlaidBarConstants.appName }
            guard !privacyMaskEnabled else { return PrivacyMaskPresentation.heroValue }
            return MultiCurrencyBalancePresentation.glance(
                from: MultiCurrencyBalancePresentation.netWorth(accounts: accounts),
                format: currencyFormat
            ).text
        case .netCash:
            guard !accounts.isEmpty else { return PlaidBarConstants.appName }
            guard !privacyMaskEnabled else { return PrivacyMaskPresentation.heroValue }
            return MultiCurrencyBalancePresentation.glance(
                from: MultiCurrencyBalancePresentation.netWorth(accounts: accounts),
                format: currencyFormat
            ).text
        case .totalCash:
            guard !accounts.isEmpty else { return PlaidBarConstants.appName }
            guard !privacyMaskEnabled else { return PrivacyMaskPresentation.heroValue }
            return MultiCurrencyBalancePresentation.glance(
                from: MultiCurrencyBalancePresentation.totalCash(accounts: accounts),
                format: currencyFormat
            ).text
        case .creditUtilization:
            guard !accounts.isEmpty else { return PlaidBarConstants.appName }
            guard let utilization = creditUtilization(from: accounts) else { return "No credit" }
            guard !privacyMaskEnabled else { return PrivacyMaskPresentation.heroValue }
            return Formatters.percent(utilization, decimals: 0)
        case .highestUtilization:
            guard !accounts.isEmpty else { return PlaidBarConstants.appName }
            guard let utilization = highestUtilization(from: accounts) else { return "No credit" }
            guard !privacyMaskEnabled else { return PrivacyMaskPresentation.heroValue }
            return Formatters.percent(utilization, decimals: 0)
        case .recentSpend:
            // During the boot fetch an empty history is unknown, not zero:
            // show the neutral app name instead of a "No spend" verdict.
            guard !transactions.isEmpty else {
                return isInitialLoad ? PlaidBarConstants.appName : "No spend"
            }
            guard !privacyMaskEnabled else { return PrivacyMaskPresentation.heroValue }
            return Formatters.currency(recentSpend(from: transactions), format: currencyFormat)
        case .todaySpend:
            // Today is a single-day window of recentSpend; the same boot-empty
            // guard applies so an in-flight load reads as neutral, not "No spend".
            guard !transactions.isEmpty else {
                return isInitialLoad ? PlaidBarConstants.appName : "No spend"
            }
            guard !privacyMaskEnabled else { return PrivacyMaskPresentation.heroValue }
            return Formatters.currency(recentSpend(from: transactions, days: 1), format: currencyFormat)
        case .safeToSpend:
            // Safe-to-spend needs recurring + cashflow inputs the pure Core text()
            // does not take, so AppState computes it via SafeToSpendCalculator and
            // feeds the amount in. A nil amount means it could not be computed yet.
            guard !accounts.isEmpty else { return PlaidBarConstants.appName }
            guard let amount = precomputedSafeToSpend else {
                return isInitialLoad ? PlaidBarConstants.appName : "No data"
            }
            guard !privacyMaskEnabled else { return PrivacyMaskPresentation.heroValue }
            return Formatters.currency(amount, format: currencyFormat)
        case .iconOnly:
            return ""
        }
    }

    /// The spoken value for VoiceOver. Identical to ``text(mode:accounts:...)`` for
    /// every mode **except** the multi-currency balance modes: there it returns the
    /// glance's spoken label, which names the dominant currency's subtotal in words
    /// and notes that other currencies are shown separately — so a VoiceOver user is
    /// not read a bare `"€1,200+"` whose `+` and currency are visual-only cues.
    ///
    /// For single-currency (or fully converted) balances the spoken value equals the
    /// visible text, so this is a no-op for the common case.
    public static func accessibleValueText(
        mode: MenuBarSummaryMode,
        accounts: [AccountDTO],
        transactions: [TransactionDTO],
        currencyFormat: CurrencyFormat,
        isInitialLoad: Bool = false,
        privacyMaskEnabled: Bool = false,
        precomputedSafeToSpend: Double? = nil
    ) -> String {
        switch mode {
        case .netWorth, .netCash, .totalCash:
            guard !accounts.isEmpty else { return PlaidBarConstants.appName }
            guard !privacyMaskEnabled else { return PrivacyMaskPresentation.heroValue }
            let aggregation = mode == .totalCash
                ? MultiCurrencyBalancePresentation.totalCash(accounts: accounts)
                : MultiCurrencyBalancePresentation.netWorth(accounts: accounts)
            return MultiCurrencyBalancePresentation.glance(
                from: aggregation,
                format: currencyFormat
            ).accessibilityLabel
        default:
            return text(
                mode: mode,
                accounts: accounts,
                transactions: transactions,
                currencyFormat: currencyFormat,
                isInitialLoad: isInitialLoad,
                privacyMaskEnabled: privacyMaskEnabled,
                precomputedSafeToSpend: precomputedSafeToSpend
            )
        }
    }
}
