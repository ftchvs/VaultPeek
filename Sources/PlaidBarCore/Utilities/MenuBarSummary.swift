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

    public static func creditUtilization(from accounts: [AccountDTO]) -> Double? {
        let creditBalances = accounts
            .filter { $0.type == .credit }
            .map(\.balances)

        let totalLimit = creditBalances.reduce(0) { $0 + ($1.limit ?? 0) }
        guard totalLimit > 0 else { return nil }

        let usedCredit = creditBalances.reduce(0) { $0 + abs($1.current ?? 0) }
        return (usedCredit / totalLimit) * 100
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
            return MultiCurrencyBalancePresentation.displayText(
                from: MultiCurrencyBalancePresentation.netWorth(accounts: accounts),
                format: currencyFormat
            )
        case .netCash:
            guard !accounts.isEmpty else { return PlaidBarConstants.appName }
            guard !privacyMaskEnabled else { return PrivacyMaskPresentation.heroValue }
            return MultiCurrencyBalancePresentation.displayText(
                from: MultiCurrencyBalancePresentation.netWorth(accounts: accounts),
                format: currencyFormat
            )
        case .totalCash:
            guard !accounts.isEmpty else { return PlaidBarConstants.appName }
            guard !privacyMaskEnabled else { return PrivacyMaskPresentation.heroValue }
            return MultiCurrencyBalancePresentation.displayText(
                from: MultiCurrencyBalancePresentation.totalCash(accounts: accounts),
                format: currencyFormat
            )
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
}
