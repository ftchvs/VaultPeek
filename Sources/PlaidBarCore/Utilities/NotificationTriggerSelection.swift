public struct NotificationTriggers: Sendable {
    public var largeTransaction: Bool
    public var lowBalance: Bool
    public var highUtilization: Bool
    public var largeTransactionThreshold: Double
    public var lowBalanceThreshold: Double
    public var creditUtilizationThreshold: Double

    public init(
        largeTransaction: Bool = true,
        lowBalance: Bool = true,
        highUtilization: Bool = true,
        largeTransactionThreshold: Double = 500,
        lowBalanceThreshold: Double = 100,
        creditUtilizationThreshold: Double = 30
    ) {
        self.largeTransaction = largeTransaction
        self.lowBalance = lowBalance
        self.highUtilization = highUtilization
        self.largeTransactionThreshold = largeTransactionThreshold
        self.lowBalanceThreshold = lowBalanceThreshold
        self.creditUtilizationThreshold = creditUtilizationThreshold
    }
}

public enum NotificationTriggerSelection {
    public static func largeTransactions(
        from transactions: [TransactionDTO],
        threshold: Double,
        excluding notifiedTransactionIds: Set<String> = []
    ) -> [TransactionDTO] {
        transactions.filter {
            !$0.isIncome &&
                $0.displayAmount >= threshold &&
                !notifiedTransactionIds.contains($0.id)
        }
    }

    public static func lowBalanceAccounts(
        from accounts: [AccountDTO],
        threshold: Double
    ) -> [AccountDTO] {
        accounts.filter {
            $0.type == .depository && $0.balances.effectiveBalance < threshold
        }
    }

    public static func highUtilizationAccounts(
        from accounts: [AccountDTO],
        threshold: Double
    ) -> [AccountDTO] {
        accounts.filter {
            $0.type == .credit && ($0.balances.utilizationPercent ?? 0) > threshold
        }
    }
}
