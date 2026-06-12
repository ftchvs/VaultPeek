import Foundation

public enum MenuBarSummaryMode: String, CaseIterable, Codable, Sendable {
    case netCash
    case totalCash
    case creditUtilization
    case recentSpend
    case iconOnly

    public var displayName: String {
        switch self {
        case .netCash: return "Net cash"
        case .totalCash: return "Total cash"
        case .creditUtilization: return "Credit utilization"
        case .recentSpend: return "Recent spend"
        case .iconOnly: return "Icon only"
        }
    }
}

public enum MenuBarSummary {
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
        currencyFormat: CurrencyFormat
    ) -> String {
        switch mode {
        case .netCash:
            guard !accounts.isEmpty else { return PlaidBarConstants.appName }
            return Formatters.currency(netCash(from: accounts), format: currencyFormat)
        case .totalCash:
            guard !accounts.isEmpty else { return PlaidBarConstants.appName }
            return Formatters.currency(totalCash(from: accounts), format: currencyFormat)
        case .creditUtilization:
            guard !accounts.isEmpty else { return PlaidBarConstants.appName }
            guard let utilization = creditUtilization(from: accounts) else { return "No credit" }
            return Formatters.percent(utilization, decimals: 0)
        case .recentSpend:
            guard !transactions.isEmpty else { return "No spend" }
            return Formatters.currency(recentSpend(from: transactions), format: currencyFormat)
        case .iconOnly:
            return ""
        }
    }
}
