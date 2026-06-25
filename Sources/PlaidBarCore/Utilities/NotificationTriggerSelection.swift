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
    /// Gate for per-category budget alerts (AND-642).
    public var categoryBudgetAlert: Bool
    public var largeTransactionThreshold: Double
    public var lowBalanceThreshold: Double
    public var creditUtilizationThreshold: Double
    public var recurringDueSoonDays: Int
    /// `under`/`nearing` boundary for category-budget alerts, as a fraction of
    /// the limit. Defaults to ``CategoryBudgetStatus/nearingThreshold`` so the
    /// alert band matches the in-app budget UI (AND-642).
    public var budgetAlertNearThreshold: Double

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
        categoryBudgetAlert: Bool = true,
        largeTransactionThreshold: Double = 500,
        lowBalanceThreshold: Double = 100,
        creditUtilizationThreshold: Double = 30,
        recurringDueSoonDays: Int = 3,
        budgetAlertNearThreshold: Double = CategoryBudgetStatus.nearingThreshold
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
        self.categoryBudgetAlert = categoryBudgetAlert
        self.largeTransactionThreshold = largeTransactionThreshold
        self.lowBalanceThreshold = lowBalanceThreshold
        self.creditUtilizationThreshold = creditUtilizationThreshold
        self.recurringDueSoonDays = recurringDueSoonDays
        self.budgetAlertNearThreshold = budgetAlertNearThreshold
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
    /// A budgeted category reaching its `nearing`/`over` band this month (AND-642).
    case categoryBudgetAlert = "category-budget-alert"

    public var clearsWhenResolved: Bool {
        switch self {
        case .itemError, .providerOutage, .loginRequired, .syncStale, .highUtilization, .lowBalance,
             .recurringChargeChanged, .recurringChargeDueSoon:
            true
        // A crossed watchlist threshold is a one-shot like largeTransaction:
        // the spend already happened, so it should not auto-clear when the
        // month-to-date sum later changes. A category-budget alert is keyed on
        // its band, and within a month spend only climbs (under → nearing →
        // over), so a delivered band-crossing should likewise not auto-resolve —
        // each higher band carries its own one-shot key.
        case .largeTransaction, .recurringChargeDetected, .merchantWatch, .categoryWatch,
             .categoryBudgetAlert:
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
        budgetPresentation: CategoryBudgetPresentation = .empty,
        isSyncStale: Bool = false,
        privacyMaskActive: Bool = false,
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
            // Constrain OS notifications to the recent window so a fresh install's
            // ~90-day import does not fire one alert per historical large charge
            // (the delivered-dedup set is empty on first sync). Mirrors the
            // AttentionQueue window.
            for transaction in largeTransactions(
                from: transactions,
                threshold: config.largeTransactionThreshold,
                now: now,
                windowDays: PlaidBarConstants.largeTransactionNotificationWindowDays,
                calendar: calendar
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

        if config.categoryBudgetAlert {
            for alert in CategoryBudgetAlertEvaluator.evaluate(
                presentation: budgetPresentation,
                nearThreshold: config.budgetAlertNearThreshold,
                now: now,
                calendar: calendar
            ) {
                append(categoryBudgetAlertDecision(for: alert, privacyMaskActive: privacyMaskActive))
            }
        }

        let decisions = activeDecisions.filter { !deliveredDedupKeys.contains($0.dedupKey) }
        let clearableDeliveredKeys = deliveredDedupKeys.filter { key in
            guard let kind = kind(forDedupKey: key) else { return false }
            // Only resolve a delivered key when its family was actually evaluated
            // this pass. If the family is disabled in config, its block was
            // skipped, so the underlying condition was never re-checked —
            // preserving the delivered key prevents a still-active stateful alert
            // from re-firing when the family is toggled off and back on.
            return kind.clearsWhenResolved && isEnabled(kind, in: config)
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
        excluding notifiedTransactionIds: Set<String> = [],
        now: Date? = nil,
        windowDays: Int? = nil,
        calendar: Calendar = .current
    ) -> [TransactionDTO] {
        // Optional recency window: when both `now` and `windowDays` are supplied,
        // also require the transaction date within [startOfDay(now) - windowDays,
        // startOfDay(now)]. Unparseable dates are dropped. When either is nil the
        // filter behaves exactly as before so windowless callers (AttentionQueue,
        // FirstRunSnapshot) keep their existing behavior.
        let window: (start: Date, end: Date)? = {
            guard let now, let windowDays else { return nil }
            let end = calendar.startOfDay(for: now)
            guard let start = calendar.date(byAdding: .day, value: -windowDays, to: end) else {
                return nil
            }
            return (start, end)
        }()

        return transactions.filter { transaction in
            guard !transaction.isIncome,
                  transaction.displayAmount >= threshold,
                  !notifiedTransactionIds.contains(transaction.id)
            else { return false }

            guard let window else { return true }
            guard let date = Formatters.parseTransactionDate(transaction.date) else { return false }
            let day = calendar.startOfDay(for: date)
            return day >= window.start && day <= window.end
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
            // Inclusive (>=) so an account exactly at the threshold fires the OS
            // notification too, matching every in-app surface (AttentionQueue,
            // AccountPresentation, AccountsDestinationView, MainPopover).
            $0.type == .credit && ($0.balances.utilizationPercent ?? 0) >= threshold
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

    /// Decision for a budgeted category crossing its `nearing`/`over` band
    /// (AND-642).
    ///
    /// De-dup grain: `category + month + band`. Within a month spend climbs
    /// monotonically (under → nearing → over), so a category fires once when it
    /// nears its limit and once more if it exceeds — never on every refresh while
    /// it sits in the same band, and the next month re-arms with a new month key.
    ///
    /// ## Privacy
    /// The body never carries an amount. When Privacy Mask is active it omits the
    /// category name too — a masked surface must not leak *which* category is
    /// under pressure to the lock screen. When unmasked the body names the
    /// category and its status (e.g. "Dining is over its monthly budget"), still
    /// without any dollar figure (the exact spend lives in-app, behind the mask /
    /// App Lock). An `.over` band raises severity to `.warning`; a `.nearing`
    /// band is an advisory `.informational` heads-up.
    private static func categoryBudgetAlertDecision(
        for alert: CategoryBudgetAlertEvaluator.Alert,
        privacyMaskActive: Bool
    ) -> NotificationTriggerDecision {
        let isOver = alert.band == .over
        let body: String
        if privacyMaskActive {
            // Masked: no category name, no amount — status verb only.
            body = isOver
                ? "A budget category is over its monthly limit. Open VaultPeek for details."
                : "A budget category is nearing its monthly limit. Open VaultPeek for details."
        } else {
            let name = alert.category.displayName
            body = isOver
                ? "\(name) is over its monthly budget. Open VaultPeek for details."
                : "\(name) is nearing its monthly budget. Open VaultPeek for details."
        }
        return NotificationTriggerDecision(
            kind: .categoryBudgetAlert,
            dedupKey: dedupKey(
                kind: .categoryBudgetAlert,
                sourceID: "\(alert.category.rawValue)#\(alert.monthKey)#\(alert.band.rawValue)"
            ),
            title: isOver ? "Over budget" : "Budget warning",
            body: body,
            severity: isOver ? .warning : .informational
        )
    }

    /// Whether the given trigger family is enabled in `config`, i.e. whether its
    /// block in `evaluate()` actually ran this pass. Mirrors the per-family
    /// gating above so delivered-key resolution only happens for re-evaluated
    /// families.
    private static func isEnabled(
        _ kind: NotificationTriggerKind,
        in config: NotificationTriggers
    ) -> Bool {
        switch kind {
        case .itemError, .providerOutage:
            config.itemError
        case .loginRequired:
            config.loginRequired
        case .syncStale:
            config.staleSync
        case .highUtilization:
            config.highUtilization
        case .lowBalance:
            config.lowBalance
        case .largeTransaction:
            config.largeTransaction
        case .recurringChargeDetected:
            config.recurringChargeDetected
        case .recurringChargeChanged:
            config.recurringChargeChanged
        case .recurringChargeDueSoon:
            config.recurringChargeDueSoon
        case .merchantWatch, .categoryWatch:
            config.watchlist
        case .categoryBudgetAlert:
            config.categoryBudgetAlert
        }
    }

    private static func kind(forDedupKey dedupKey: String) -> NotificationTriggerKind? {
        guard let rawKind = dedupKey.split(separator: ":", maxSplits: 1).first else {
            return nil
        }
        return NotificationTriggerKind(rawValue: String(rawKind))
    }
}
