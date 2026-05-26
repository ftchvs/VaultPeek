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

        return transactions.reduce(0) { total, transaction in
            guard !transaction.isIncome,
                  transaction.category != .transfer,
                  transaction.category != .transferOut,
                  let date = Formatters.parseTransactionDate(transaction.date),
                  date >= startDate,
                  date <= now
            else {
                return total
            }
            return total + transaction.displayAmount
        }
    }

    public static func text(
        mode: MenuBarSummaryMode,
        accounts: [AccountDTO],
        transactions: [TransactionDTO],
        currencyFormat: CurrencyFormat
    ) -> String {
        switch mode {
        case .netCash:
            guard !accounts.isEmpty else { return "PlaidBar" }
            return Formatters.currency(netCash(from: accounts), format: currencyFormat)
        case .totalCash:
            guard !accounts.isEmpty else { return "PlaidBar" }
            return Formatters.currency(totalCash(from: accounts), format: currencyFormat)
        case .creditUtilization:
            guard !accounts.isEmpty else { return "PlaidBar" }
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
