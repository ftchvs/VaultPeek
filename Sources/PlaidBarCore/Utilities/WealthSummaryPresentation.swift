import Foundation

public struct WealthSummaryPresentation: Sendable, Equatable {
    public struct CashflowSummary: Sendable, Equatable {
        public let windowDays: Int
        public let income: Double
        public let spending: Double
        public let net: Double
        public let transactionCount: Int

        public init(
            windowDays: Int,
            income: Double,
            spending: Double,
            net: Double,
            transactionCount: Int
        ) {
            self.windowDays = windowDays
            self.income = income
            self.spending = spending
            self.net = net
            self.transactionCount = transactionCount
        }
    }

    public struct CreditUtilizationSummary: Sendable, Equatable {
        public let percent: Double
        public let usedCredit: Double
        public let totalLimit: Double
        public let statusLabel: String
        public let exceedsThreshold: Bool

        public init(
            percent: Double,
            usedCredit: Double,
            totalLimit: Double,
            statusLabel: String,
            exceedsThreshold: Bool
        ) {
            self.percent = percent
            self.usedCredit = usedCredit
            self.totalLimit = totalLimit
            self.statusLabel = statusLabel
            self.exceedsThreshold = exceedsThreshold
        }
    }

    public struct AttentionSummary: Sendable, Equatable {
        public let severity: AttentionQueueSeverity
        public let title: String
        public let detail: String
        public let visibleRowCount: Int

        public init(
            severity: AttentionQueueSeverity,
            title: String,
            detail: String,
            visibleRowCount: Int
        ) {
            self.severity = severity
            self.title = title
            self.detail = detail
            self.visibleRowCount = visibleRowCount
        }
    }

    public struct SyncHealthSummary: Sendable, Equatable {
        public let severity: AttentionQueueSeverity
        public let title: String
        public let detail: String
        public let statusText: String
        public let iconName: String

        public init(
            severity: AttentionQueueSeverity,
            title: String,
            detail: String,
            statusText: String,
            iconName: String
        ) {
            self.severity = severity
            self.title = title
            self.detail = detail
            self.statusText = statusText
            self.iconName = iconName
        }
    }

    public let accountCount: Int
    public let transactionCount: Int
    public let netWorth: Double
    public let totalAssets: Double
    public let totalDebt: Double
    public let balanceMix: BalanceCompositionPresentation
    public let netWorthTrend: NetWorthTrendPresentation
    public let cashflow: CashflowSummary
    public let creditUtilization: CreditUtilizationSummary?
    public let attention: AttentionSummary
    public let syncHealth: SyncHealthSummary

    public init(
        accountCount: Int,
        transactionCount: Int,
        netWorth: Double,
        totalAssets: Double,
        totalDebt: Double,
        balanceMix: BalanceCompositionPresentation,
        netWorthTrend: NetWorthTrendPresentation = .insufficientHistory(
            pointCount: 0,
            requiredPointCount: BalanceTrend.requiredPointCount
        ),
        cashflow: CashflowSummary,
        creditUtilization: CreditUtilizationSummary?,
        attention: AttentionSummary,
        syncHealth: SyncHealthSummary
    ) {
        self.accountCount = accountCount
        self.transactionCount = transactionCount
        self.netWorth = netWorth
        self.totalAssets = totalAssets
        self.totalDebt = totalDebt
        self.balanceMix = balanceMix
        self.netWorthTrend = netWorthTrend
        self.cashflow = cashflow
        self.creditUtilization = creditUtilization
        self.attention = attention
        self.syncHealth = syncHealth
    }

    public static func evaluate(
        accounts: [AccountDTO],
        transactions: [TransactionDTO],
        isDemoMode: Bool,
        serverConnected: Bool,
        credentialsConfigured: Bool?,
        linkedItemCount: Int,
        syncedItemCount: Int,
        itemStatuses: [ItemStatus],
        isSyncStale: Bool,
        lastSyncRelative: String?,
        statusSyncText: String,
        errorMessage: String?,
        creditUtilizationThreshold: Double = PlaidBarConstants.creditUtilizationWarningThreshold,
        lowCashThreshold: Double = 100,
        largeTransactionThreshold: Double = 500,
        balanceHistory: [BalanceSnapshot] = [],
        windowDays: Int = 30,
        now: Date = Date(),
        calendar: Calendar = .current
    ) -> WealthSummaryPresentation {
        let attentionQueue = AttentionQueue.evaluate(
            isDemoMode: isDemoMode,
            serverConnected: serverConnected,
            credentialsConfigured: credentialsConfigured,
            linkedItemCount: linkedItemCount,
            accountCount: accounts.count,
            syncedItemCount: syncedItemCount,
            itemStatuses: itemStatuses,
            isSyncStale: isSyncStale,
            lastSyncRelative: lastSyncRelative,
            errorMessage: errorMessage,
            accounts: accounts,
            transactions: transactions,
            lowCashThreshold: lowCashThreshold,
            largeTransactionThreshold: largeTransactionThreshold,
            creditUtilizationThreshold: creditUtilizationThreshold
        )
        let attention = attentionSummary(from: attentionQueue)

        return WealthSummaryPresentation(
            accountCount: accounts.count,
            transactionCount: transactions.count,
            netWorth: MenuBarSummary.netCash(from: accounts),
            totalAssets: totalAssets(from: accounts),
            totalDebt: MenuBarSummary.totalDebt(from: accounts),
            balanceMix: BalanceCompositionPresentation(accounts: accounts),
            netWorthTrend: NetWorthTrendPresentation.evaluate(
                history: balanceHistory,
                now: now,
                calendar: calendar
            ),
            cashflow: cashflowSummary(
                from: transactions,
                windowDays: windowDays,
                now: now,
                calendar: calendar
            ),
            creditUtilization: creditUtilizationSummary(
                from: accounts,
                threshold: creditUtilizationThreshold
            ),
            attention: attention,
            syncHealth: syncHealthSummary(
                from: attention,
                isDemoMode: isDemoMode,
                statusSyncText: statusSyncText
            )
        )
    }

    private static func totalAssets(from accounts: [AccountDTO]) -> Double {
        accounts.reduce(0) { total, account in
            guard !AccountPresentation.isDebt(account) else { return total }
            return total + max(account.balances.effectiveBalance, 0)
        }
    }

    private static func cashflowSummary(
        from transactions: [TransactionDTO],
        windowDays: Int,
        now: Date,
        calendar: Calendar
    ) -> CashflowSummary {
        let normalizedWindowDays = max(windowDays, 1)
        let referenceDate = calendar.startOfDay(for: now)
        let currentStart = calendar.startOfDay(
            for: calendar.date(byAdding: .day, value: -(normalizedWindowDays - 1), to: referenceDate)
                ?? referenceDate
        )

        var income = 0.0
        var spending = 0.0
        var transactionCount = 0

        for transaction in transactions {
            guard !transaction.isCashflowTransfer,
                  let date = Formatters.parseTransactionDate(transaction.date),
                  date >= currentStart,
                  date <= referenceDate
            else {
                continue
            }

            transactionCount += 1
            if transaction.isIncome {
                income += transaction.displayAmount
            } else {
                spending += transaction.displayAmount
            }
        }

        return CashflowSummary(
            windowDays: normalizedWindowDays,
            income: income,
            spending: spending,
            net: income - spending,
            transactionCount: transactionCount
        )
    }

    private static func creditUtilizationSummary(
        from accounts: [AccountDTO],
        threshold: Double
    ) -> CreditUtilizationSummary? {
        let creditBalances = accounts
            .filter { $0.type == .credit }
            .map(\.balances)

        let totalLimit = creditBalances.reduce(0) { $0 + max($1.limit ?? 0, 0) }
        guard totalLimit > 0 else { return nil }

        let usedCredit = creditBalances.reduce(0) { $0 + abs($1.current ?? 0) }
        let percent = (usedCredit / totalLimit) * 100

        return CreditUtilizationSummary(
            percent: percent,
            usedCredit: usedCredit,
            totalLimit: totalLimit,
            statusLabel: AccountPresentation.utilizationStatusLabel(
                for: percent,
                threshold: threshold
            ),
            exceedsThreshold: percent >= threshold
        )
    }

    private static func attentionSummary(from queue: AttentionQueue) -> AttentionSummary {
        let row = queue.rows.first
        return AttentionSummary(
            severity: row?.severity ?? .healthy,
            title: row?.title ?? "Sync healthy",
            detail: row?.detail ?? "No attention items.",
            visibleRowCount: queue.rows.count
        )
    }

    private static func syncHealthSummary(
        from attention: AttentionSummary,
        isDemoMode: Bool,
        statusSyncText: String
    ) -> SyncHealthSummary {
        guard attention.severity != .healthy else {
            return SyncHealthSummary(
                severity: .healthy,
                title: isDemoMode ? "Demo data ready" : "Sync healthy",
                detail: statusSyncText,
                statusText: statusSyncText,
                iconName: isDemoMode ? "play.circle.fill" : "checkmark.circle.fill"
            )
        }

        return SyncHealthSummary(
            severity: attention.severity,
            title: attention.title,
            detail: attention.detail,
            statusText: statusSyncText,
            iconName: attention.severity == .blocked ? "xmark.octagon.fill" : "exclamationmark.triangle.fill"
        )
    }
}

private extension TransactionDTO {
    var isCashflowTransfer: Bool {
        category == .transfer || category == .transferOut
    }
}
