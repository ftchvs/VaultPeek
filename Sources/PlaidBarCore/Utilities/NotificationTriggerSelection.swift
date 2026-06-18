import CryptoKit
import Foundation

public struct NotificationTriggers: Sendable {
    public var largeTransaction: Bool
    public var lowBalance: Bool
    public var highUtilization: Bool
    public var recurringChargeDetected: Bool
    public var recurringChargeChanged: Bool
    public var recurringChargeDueSoon: Bool
    public var staleSync: Bool
    public var loginRequired: Bool
    public var itemError: Bool
    /// Gate for watchlist spend nudges (AND-501).
    public var watchlist: Bool
    public var largeTransactionThreshold: Double
    public var lowBalanceThreshold: Double
    public var creditUtilizationThreshold: Double
    public var recurringDueSoonDays: Int

    public init(
        largeTransaction: Bool = true,
        lowBalance: Bool = true,
        highUtilization: Bool = true,
        recurringChargeDetected: Bool = true,
        recurringChargeChanged: Bool = true,
        recurringChargeDueSoon: Bool = true,
        staleSync: Bool = true,
        loginRequired: Bool = true,
        itemError: Bool = true,
        watchlist: Bool = true,
        largeTransactionThreshold: Double = 500,
        lowBalanceThreshold: Double = 100,
        creditUtilizationThreshold: Double = 30,
        recurringDueSoonDays: Int = 3
    ) {
        self.largeTransaction = largeTransaction
        self.lowBalance = lowBalance
        self.highUtilization = highUtilization
        self.recurringChargeDetected = recurringChargeDetected
        self.recurringChargeChanged = recurringChargeChanged
        self.recurringChargeDueSoon = recurringChargeDueSoon
        self.staleSync = staleSync
        self.loginRequired = loginRequired
        self.itemError = itemError
        self.watchlist = watchlist
        self.largeTransactionThreshold = largeTransactionThreshold
        self.lowBalanceThreshold = lowBalanceThreshold
        self.creditUtilizationThreshold = creditUtilizationThreshold
        self.recurringDueSoonDays = recurringDueSoonDays
    }
}

public enum NotificationTriggerKind: String, Codable, CaseIterable, Sendable {
    case itemError = "item-error"
    case providerOutage = "provider-outage"
    case loginRequired = "login-required"
    case syncStale = "sync-stale"
    case highUtilization = "high-utilization"
    case lowBalance = "low-balance"
    case largeTransaction = "large-transaction"
    case recurringChargeDetected = "recurring-charge-detected"
    case recurringChargeChanged = "recurring-charge-changed"
    case recurringChargeDueSoon = "recurring-charge-due-soon"
    case merchantWatch = "merchant-watch"
    case categoryWatch = "category-watch"

    public var clearsWhenResolved: Bool {
        switch self {
        case .itemError, .providerOutage, .loginRequired, .syncStale, .highUtilization, .lowBalance,
             .recurringChargeChanged, .recurringChargeDueSoon:
            true
        // A crossed watchlist threshold is a one-shot like largeTransaction:
        // the spend already happened, so it should not auto-clear when the
        // month-to-date sum later changes.
        case .largeTransaction, .recurringChargeDetected, .merchantWatch, .categoryWatch:
            false
        }
    }
}

public enum NotificationTriggerSeverity: String, Codable, Sendable {
    case informational
    case warning
    case blocking
}

public struct NotificationTriggerDecision: Equatable, Identifiable, Sendable {
    public var id: String { dedupKey }

    public let kind: NotificationTriggerKind
    public let dedupKey: String
    public let title: String
    public let body: String
    public let severity: NotificationTriggerSeverity

    public init(
        kind: NotificationTriggerKind,
        dedupKey: String,
        title: String,
        body: String,
        severity: NotificationTriggerSeverity
    ) {
        self.kind = kind
        self.dedupKey = dedupKey
        self.title = title
        self.body = body
        self.severity = severity
    }
}

public struct NotificationTriggerEvaluation: Equatable, Sendable {
    public let decisions: [NotificationTriggerDecision]
    public let activeDedupKeys: Set<String>
    public let resolvedDedupKeys: Set<String>

    public init(
        decisions: [NotificationTriggerDecision],
        activeDedupKeys: Set<String>,
        resolvedDedupKeys: Set<String>
    ) {
        self.decisions = decisions
        self.activeDedupKeys = activeDedupKeys
        self.resolvedDedupKeys = resolvedDedupKeys
    }
}

public enum NotificationTriggerSelection {
    public static func evaluate(
        transactions: [TransactionDTO] = [],
        accounts: [AccountDTO] = [],
        recurringTransactions: [RecurringTransaction] = [],
        itemStatuses: [ItemStatus] = [],
        watchlistTargets: [WatchlistTarget] = [],
        isSyncStale: Bool = false,
        now: Date = Date(),
        calendar: Calendar = .current,
        config: NotificationTriggers = NotificationTriggers(),
        deliveredDedupKeys: Set<String> = []
    ) -> NotificationTriggerEvaluation {
        var activeDecisions: [NotificationTriggerDecision] = []
        var activeDedupKeys = Set<String>()

        func append(_ decision: NotificationTriggerDecision) {
            guard activeDedupKeys.insert(decision.dedupKey).inserted else { return }
            activeDecisions.append(decision)
        }

        if config.itemError {
            for item in itemStatuses where item.status == .error {
                append(itemErrorDecision(for: item))
            }
            // Provider outages are connection-health signals but emit a distinct,
            // non-actionable advisory kind (not itemError) — VaultPeek retries
            // automatically, so no reconnect is prompted.
            for item in itemStatuses where item.status == .providerOutage {
                append(providerOutageDecision(for: item))
            }
        }

        if config.loginRequired {
            for item in itemStatuses where item.status.needsUpdateMode {
                append(loginRequiredDecision(for: item))
            }
        }

        if config.staleSync, isSyncStale {
            append(syncStaleDecision())
        }

        if config.highUtilization {
            for account in highUtilizationAccounts(
                from: accounts,
                threshold: config.creditUtilizationThreshold
            ) {
                append(highUtilizationDecision(for: account))
            }
        }

        if config.lowBalance {
            for account in lowBalanceAccounts(from: accounts, threshold: config.lowBalanceThreshold) {
                append(lowBalanceDecision(for: account))
            }
        }

        if config.recurringChargeChanged {
            for recurring in changedRecurringCharges(from: recurringTransactions) {
                append(recurringChargeChangedDecision(for: recurring))
            }
        }

        if config.recurringChargeDueSoon {
            for recurring in dueSoonRecurringCharges(
                from: recurringTransactions,
                withinDays: config.recurringDueSoonDays,
                now: now,
                calendar: calendar
            ) {
                append(recurringChargeDueSoonDecision(for: recurring))
            }
        }

        if config.recurringChargeDetected {
            for recurring in detectedRecurringCharges(from: recurringTransactions) {
                append(recurringChargeDetectedDecision(for: recurring))
            }
        }

        if config.largeTransaction {
            for transaction in largeTransactions(
                from: transactions,
                threshold: config.largeTransactionThreshold
            ) {
                append(largeTransactionDecision(for: transaction))
            }
        }

        if config.watchlist {
            for match in WatchlistEvaluator.evaluate(
                transactions: transactions,
                targets: watchlistTargets,
                now: now,
                calendar: calendar
            ) {
                append(watchlistDecision(for: match))
            }
        }

        let decisions = activeDecisions.filter { !deliveredDedupKeys.contains($0.dedupKey) }
        let clearableDeliveredKeys = deliveredDedupKeys.filter { key in
            guard let kind = kind(forDedupKey: key) else { return false }
            return kind.clearsWhenResolved
        }
        let resolvedDedupKeys = Set(clearableDeliveredKeys).subtracting(activeDedupKeys)

        return NotificationTriggerEvaluation(
            decisions: decisions,
            activeDedupKeys: activeDedupKeys,
            resolvedDedupKeys: resolvedDedupKeys
        )
    }

    public static func dedupKey(kind: NotificationTriggerKind, sourceID: String) -> String {
        let normalizedSourceID = sourceID.trimmingCharacters(in: .whitespacesAndNewlines)
        let sourceID = normalizedSourceID.isEmpty ? "global" : normalizedSourceID
        let digest = SHA256.hash(data: Data("\(kind.rawValue):\(sourceID)".utf8))
            .prefix(16)
            .map { String(format: "%02x", $0) }
            .joined()
        return "\(kind.rawValue):\(digest)"
    }

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

    public static func detectedRecurringCharges(
        from recurringTransactions: [RecurringTransaction],
        minimumConfidence: Double = RecurringTransaction.priceIncreaseConfidenceThreshold
    ) -> [RecurringTransaction] {
        recurringTransactions.filter { $0.confidence >= minimumConfidence }
    }

    public static func changedRecurringCharges(
        from recurringTransactions: [RecurringTransaction]
    ) -> [RecurringTransaction] {
        recurringTransactions.filter(\.hasPriceIncrease)
    }

    public static func dueSoonRecurringCharges(
        from recurringTransactions: [RecurringTransaction],
        withinDays: Int,
        now: Date = Date(),
        calendar: Calendar = .current
    ) -> [RecurringTransaction] {
        guard withinDays >= 0 else { return [] }
        let today = calendar.startOfDay(for: now)
        guard let windowEnd = calendar.date(byAdding: .day, value: withinDays, to: today) else {
            return []
        }

        return recurringTransactions.filter { recurring in
            guard recurring.confidence >= RecurringTransaction.priceIncreaseConfidenceThreshold,
                  let dueDate = Formatters.parseTransactionDate(recurring.nextExpectedDate)
            else { return false }

            let dueStart = calendar.startOfDay(for: dueDate)
            return dueStart >= today && dueStart <= windowEnd
        }
    }

    private static func itemErrorDecision(for item: ItemStatus) -> NotificationTriggerDecision {
        NotificationTriggerDecision(
            kind: .itemError,
            dedupKey: dedupKey(kind: .itemError, sourceID: item.id),
            title: "Institution needs attention",
            body: "A linked institution reported a sync error. Reconnect, then refresh.",
            severity: .blocking
        )
    }

    private static func providerOutageDecision(for item: ItemStatus) -> NotificationTriggerDecision {
        NotificationTriggerDecision(
            kind: .providerOutage,
            dedupKey: dedupKey(kind: .providerOutage, sourceID: item.id),
            title: "Bank temporarily unavailable",
            body: "A linked institution or Plaid is temporarily unavailable. VaultPeek will retry automatically — no action needed.",
            severity: .informational
        )
    }

    private static func loginRequiredDecision(for item: ItemStatus) -> NotificationTriggerDecision {
        NotificationTriggerDecision(
            kind: .loginRequired,
            dedupKey: dedupKey(kind: .loginRequired, sourceID: item.id),
            title: "Bank login required",
            body: "A linked institution needs a fresh login before sync can continue.",
            severity: .warning
        )
    }

    private static func syncStaleDecision() -> NotificationTriggerDecision {
        NotificationTriggerDecision(
            kind: .syncStale,
            dedupKey: dedupKey(kind: .syncStale, sourceID: "global"),
            title: "Sync may be stale",
            body: "VaultPeek has not refreshed recently. Open the app to refresh local data.",
            severity: .warning
        )
    }

    private static func highUtilizationDecision(for account: AccountDTO) -> NotificationTriggerDecision {
        NotificationTriggerDecision(
            kind: .highUtilization,
            dedupKey: dedupKey(kind: .highUtilization, sourceID: account.id),
            title: "Credit utilization alert",
            body: "A credit account is above your configured utilization threshold.",
            severity: .warning
        )
    }

    private static func lowBalanceDecision(for account: AccountDTO) -> NotificationTriggerDecision {
        NotificationTriggerDecision(
            kind: .lowBalance,
            dedupKey: dedupKey(kind: .lowBalance, sourceID: account.id),
            title: "Low balance alert",
            body: "A depository account is below your configured low-balance threshold.",
            severity: .warning
        )
    }

    private static func largeTransactionDecision(for transaction: TransactionDTO) -> NotificationTriggerDecision {
        NotificationTriggerDecision(
            kind: .largeTransaction,
            dedupKey: dedupKey(kind: .largeTransaction, sourceID: transaction.id),
            title: "Large transaction alert",
            body: "A local transaction crossed your configured threshold.",
            severity: .informational
        )
    }

    private static func recurringChargeDetectedDecision(
        for recurring: RecurringTransaction
    ) -> NotificationTriggerDecision {
        NotificationTriggerDecision(
            kind: .recurringChargeDetected,
            dedupKey: dedupKey(kind: .recurringChargeDetected, sourceID: recurring.id),
            title: "Recurring charge detected",
            body: "VaultPeek found a repeated local charge pattern.",
            severity: .informational
        )
    }

    private static func recurringChargeChangedDecision(
        for recurring: RecurringTransaction
    ) -> NotificationTriggerDecision {
        // Key on the changed amount, not just the stream id, so a second price
        // increase on the same stream (e.g. $10→$15 then $15→$20) produces a
        // new dedupe key and is not suppressed by the first change alert.
        let latestAmountCents = Int((recurring.latestAmount * 100).rounded())
        return NotificationTriggerDecision(
            kind: .recurringChargeChanged,
            dedupKey: dedupKey(
                kind: .recurringChargeChanged,
                sourceID: "\(recurring.id)#\(latestAmountCents)"
            ),
            title: "Recurring charge changed",
            body: "A recurring charge appears higher than its recent pattern.",
            severity: .warning
        )
    }

    private static func recurringChargeDueSoonDecision(
        for recurring: RecurringTransaction
    ) -> NotificationTriggerDecision {
        // Key on the specific due date so each due occurrence can notify
        // independently. Using only the stream id would let one cycle's
        // delivered key suppress the next cycle's due-soon alert when the app
        // was asleep across the gap and sync advanced nextExpectedDate.
        return NotificationTriggerDecision(
            kind: .recurringChargeDueSoon,
            dedupKey: dedupKey(
                kind: .recurringChargeDueSoon,
                sourceID: "\(recurring.id)#\(recurring.nextExpectedDate)"
            ),
            title: "Recurring charge due soon",
            body: "An inferred recurring charge is expected soon.",
            severity: .informational
        )
    }

    private static func watchlistDecision(
        for match: WatchlistEvaluator.Match
    ) -> NotificationTriggerDecision {
        let target = match.target
        let kind: NotificationTriggerKind = target.kind == .merchant ? .merchantWatch : .categoryWatch
        // Key on target + month + threshold (in cents) so each month re-arms the
        // nudge and raising the limit re-notifies once the higher bar is crossed.
        let thresholdCents = Int((target.monthlyThreshold * 100).rounded())
        let sourceID = "\(target.kind.rawValue):\(target.key)#\(match.monthKey)#\(thresholdCents)"
        // Lock-screen copy stays generic — no merchant name, category, or amount
        // (privacy hard rule, see NotificationTriggerEvaluationTests). The exact
        // "$X at Y this month" framing lives in-app where the device is unlocked.
        let body: String = switch target.kind {
        case .merchant: "A merchant you're watching crossed its monthly spend limit. Open VaultPeek for details."
        case .category: "A spending category you're watching crossed its monthly limit. Open VaultPeek for details."
        }
        return NotificationTriggerDecision(
            kind: kind,
            dedupKey: dedupKey(kind: kind, sourceID: sourceID),
            title: "Watchlist nudge",
            body: body,
            severity: .informational
        )
    }

    private static func kind(forDedupKey dedupKey: String) -> NotificationTriggerKind? {
        guard let rawKind = dedupKey.split(separator: ":", maxSplits: 1).first else {
            return nil
        }
        return NotificationTriggerKind(rawValue: String(rawKind))
    }
}
