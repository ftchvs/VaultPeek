import Foundation

public enum FirstRunSnapshotTransactionState: String, Codable, Sendable {
    case ready
    case syncing
    case empty
}

/// Display-safe first-run money snapshot computed entirely from local DTOs.
///
/// The presentation intentionally omits raw account IDs, item IDs, transaction
/// IDs, and raw provider payloads. Transaction rows carry only the user-visible
/// merchant/name, date, and amount needed for the first-run "aha" surface.
public struct FirstRunSnapshot: Equatable, Sendable {
    public struct LargeTransaction: Equatable, Sendable, Identifiable {
        public let id: String
        public let displayName: String
        public let amount: Double
        public let date: String

        public init(id: String, displayName: String, amount: Double, date: String) {
            self.id = id
            self.displayName = displayName
            self.amount = amount
            self.date = date
        }
    }

    public let accountCount: Int
    /// Number of depository accounts that contribute to `cashAvailable`. The
    /// cash figure sums only depository balances, so reporting the total
    /// `accountCount` next to it would overstate how many accounts hold cash.
    public let cashAccountCount: Int
    public let transactionCount: Int
    public let netWorth: Double
    public let cashAvailable: Double
    public let debtTotal: Double
    public let creditUtilization: Double?
    public let monthToDateSpend: Double?
    public let transactionState: FirstRunSnapshotTransactionState
    public let largeTransactions: [LargeTransaction]
    public let hasCreditAccounts: Bool
    public let hasDebtAccounts: Bool
    public let accessibilitySummary: String

    public init(
        accountCount: Int,
        cashAccountCount: Int = 0,
        transactionCount: Int,
        netWorth: Double,
        cashAvailable: Double,
        debtTotal: Double,
        creditUtilization: Double?,
        monthToDateSpend: Double?,
        transactionState: FirstRunSnapshotTransactionState,
        largeTransactions: [LargeTransaction],
        hasCreditAccounts: Bool,
        hasDebtAccounts: Bool,
        accessibilitySummary: String
    ) {
        self.accountCount = accountCount
        self.cashAccountCount = cashAccountCount
        self.transactionCount = transactionCount
        self.netWorth = netWorth
        self.cashAvailable = cashAvailable
        self.debtTotal = debtTotal
        self.creditUtilization = creditUtilization
        self.monthToDateSpend = monthToDateSpend
        self.transactionState = transactionState
        self.largeTransactions = largeTransactions
        self.hasCreditAccounts = hasCreditAccounts
        self.hasDebtAccounts = hasDebtAccounts
        self.accessibilitySummary = accessibilitySummary
    }

    public static func evaluate(
        accounts: [AccountDTO],
        transactions: [TransactionDTO],
        completionState: FirstRunCompletionState,
        largeTransactionThreshold: Double = 500,
        now: Date = Date(),
        calendar: Calendar = .current
    ) -> FirstRunSnapshot {
        let transactionState = transactionState(
            transactionCount: transactions.count,
            completionState: completionState
        )
        let monthToDateSpend = transactions.isEmpty
            ? nil
            : MenuBarSummary.monthToDateSpend(from: transactions, now: now, calendar: calendar)
        let largeTransactions = largeTransactions(
            from: transactions,
            threshold: largeTransactionThreshold,
            now: now,
            calendar: calendar
        )
        let netWorth = MenuBarSummary.netCash(from: accounts)
        let cashAvailable = MenuBarSummary.totalCash(from: accounts)
        let debtTotal = MenuBarSummary.totalDebt(from: accounts)
        let creditUtilization = MenuBarSummary.creditUtilization(from: accounts)

        return FirstRunSnapshot(
            accountCount: accounts.count,
            cashAccountCount: accounts.filter { $0.type == .depository }.count,
            transactionCount: transactions.count,
            netWorth: netWorth,
            cashAvailable: cashAvailable,
            debtTotal: debtTotal,
            creditUtilization: creditUtilization,
            monthToDateSpend: monthToDateSpend,
            transactionState: transactionState,
            largeTransactions: largeTransactions,
            hasCreditAccounts: accounts.contains { $0.type == .credit },
            hasDebtAccounts: accounts.contains(where: AccountPresentation.isDebt),
            accessibilitySummary: accessibilitySummary(
                netWorth: netWorth,
                cashAvailable: cashAvailable,
                debtTotal: debtTotal,
                creditUtilization: creditUtilization,
                monthToDateSpend: monthToDateSpend,
                transactionState: transactionState,
                largeTransactionCount: largeTransactions.count
            )
        )
    }

    private static func transactionState(
        transactionCount: Int,
        completionState: FirstRunCompletionState
    ) -> FirstRunSnapshotTransactionState {
        if transactionCount > 0 { return .ready }
        return completionState.step == .syncTransactions ? .syncing : .empty
    }

    private static func largeTransactions(
        from transactions: [TransactionDTO],
        threshold: Double,
        now: Date,
        calendar: Calendar
    ) -> [LargeTransaction] {
        let currentDay = calendar.startOfDay(for: now)
        return Array(NotificationTriggerSelection.largeTransactions(
            from: transactions,
            threshold: threshold
        )
        .filter {
            guard $0.category != .transfer,
                  $0.category != .transferOut,
                  let date = Formatters.parseTransactionDate($0.date)
            else {
                return false
            }
            return calendar.startOfDay(for: date) <= currentDay
        }
        .sorted {
            if $0.date != $1.date { return $0.date > $1.date }
            if $0.displayAmount != $1.displayAmount { return $0.displayAmount > $1.displayAmount }
            return $0.displayName < $1.displayName
        }
        .prefix(3)
        .enumerated()
        .map { offset, transaction in
            LargeTransaction(
                // Two large transactions can share date + name + amount, which
                // would collide on identity and make SwiftUI ForEach diffing
                // undefined. The sorted-occurrence index disambiguates while
                // keeping the id display-safe (no account/transaction ids).
                id: displaySafeLargeTransactionID(for: transaction, occurrence: offset),
                displayName: transaction.displayName,
                amount: transaction.displayAmount,
                date: transaction.date
            )
        })
    }

    private static func displaySafeLargeTransactionID(
        for transaction: TransactionDTO,
        occurrence: Int
    ) -> String {
        let amountCents = Int((transaction.displayAmount * 100).rounded())
        return "\(transaction.date)-\(transaction.displayName)-\(amountCents)-\(occurrence)"
    }

    /// Privacy-Mask-aware VoiceOver summary. The default stored
    /// ``accessibilitySummary`` (computed with `isMasked: false`) leaks every
    /// figure, so the view re-derives the masked form through this method when
    /// Privacy Mask is on — mirroring how sibling surfaces self-dot. When masked,
    /// currency and percent values are replaced with the dotted token so the
    /// spoken label never reveals real magnitudes.
    public func maskedAccessibilitySummary(isMasked: Bool) -> String {
        guard isMasked else { return accessibilitySummary }
        return Self.accessibilitySummary(
            netWorth: netWorth,
            cashAvailable: cashAvailable,
            debtTotal: debtTotal,
            creditUtilization: creditUtilization,
            monthToDateSpend: monthToDateSpend,
            transactionState: transactionState,
            largeTransactionCount: largeTransactions.count,
            isMasked: true
        )
    }

    private static func accessibilitySummary(
        netWorth: Double,
        cashAvailable: Double,
        debtTotal: Double,
        creditUtilization: Double?,
        monthToDateSpend: Double?,
        transactionState: FirstRunSnapshotTransactionState,
        largeTransactionCount: Int,
        isMasked: Bool = false
    ) -> String {
        var parts = [
            "First-run money snapshot.",
            "Net worth \(PrivacyMaskPresentation.currency(netWorth, format: .full, isEnabled: isMasked)).",
            "Cash available \(PrivacyMaskPresentation.currency(cashAvailable, format: .full, isEnabled: isMasked)).",
            "Debt \(PrivacyMaskPresentation.currency(debtTotal, format: .full, isEnabled: isMasked)).",
        ]

        if let creditUtilization {
            parts.append("Credit utilization \(PrivacyMaskPresentation.percent(creditUtilization, decimals: 0, isEnabled: isMasked)).")
        } else {
            parts.append("No credit utilization available.")
        }

        switch (monthToDateSpend, transactionState) {
        case let (.some(spend), _):
            parts.append("Month-to-date spend \(PrivacyMaskPresentation.currency(spend, format: .full, isEnabled: isMasked)).")
        case (.none, .syncing):
            parts.append("Transactions are still syncing.")
        case (.none, .empty):
            parts.append("No transactions synced yet.")
        case (.none, .ready):
            parts.append("No month-to-date spend.")
        }

        if largeTransactionCount > 0 {
            parts.append("\(largeTransactionCount) recent large transaction\(largeTransactionCount == 1 ? "" : "s").")
        }

        return parts.joined(separator: " ")
    }
}

public struct FirstRunSnapshotPresentation: Equatable, Sendable {
    public let snapshot: FirstRunSnapshot
    public let title: String
    public let subtitle: String
    public let primaryAccessibilityLabel: String
    public let dismissalAccessibilityHint: String

    public init(
        snapshot: FirstRunSnapshot,
        title: String,
        subtitle: String,
        primaryAccessibilityLabel: String,
        dismissalAccessibilityHint: String
    ) {
        self.snapshot = snapshot
        self.title = title
        self.subtitle = subtitle
        self.primaryAccessibilityLabel = primaryAccessibilityLabel
        self.dismissalAccessibilityHint = dismissalAccessibilityHint
    }

    public static func evaluate(
        accounts: [AccountDTO],
        transactions: [TransactionDTO],
        completionState: FirstRunCompletionState,
        isDismissed: Bool,
        isInitialLoad: Bool,
        isDemoMode: Bool,
        largeTransactionThreshold: Double = 500,
        now: Date = Date(),
        calendar: Calendar = .current
    ) -> FirstRunSnapshotPresentation? {
        guard !isDismissed,
              !isInitialLoad,
              !isDemoMode,
              completionState.isReady,
              completionState.step == .ready,
              !accounts.isEmpty
        else {
            return nil
        }

        let snapshot = FirstRunSnapshot.evaluate(
            accounts: accounts,
            transactions: transactions,
            completionState: completionState,
            largeTransactionThreshold: largeTransactionThreshold,
            now: now,
            calendar: calendar
        )
        return FirstRunSnapshotPresentation(
            snapshot: snapshot,
            title: "First Snapshot",
            subtitle: subtitle(for: snapshot),
            primaryAccessibilityLabel: snapshot.accessibilitySummary,
            dismissalAccessibilityHint: "Dismisses this first-run snapshot and keeps it hidden on future launches."
        )
    }

    private static func subtitle(for snapshot: FirstRunSnapshot) -> String {
        switch snapshot.transactionState {
        case .ready:
            return "Your local account and transaction sync is ready."
        case .syncing:
            return "Accounts are ready; transaction history is still syncing."
        case .empty:
            return "Accounts are ready; no transaction rows are available yet."
        }
    }
}
