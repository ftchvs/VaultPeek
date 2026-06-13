import CryptoKit
import Foundation

public struct NotificationTriggers: Sendable {
    public var largeTransaction: Bool
    public var lowBalance: Bool
    public var highUtilization: Bool
    public var staleSync: Bool
    public var loginRequired: Bool
    public var itemError: Bool
    public var largeTransactionThreshold: Double
    public var lowBalanceThreshold: Double
    public var creditUtilizationThreshold: Double

    public init(
        largeTransaction: Bool = true,
        lowBalance: Bool = true,
        highUtilization: Bool = true,
        staleSync: Bool = true,
        loginRequired: Bool = true,
        itemError: Bool = true,
        largeTransactionThreshold: Double = 500,
        lowBalanceThreshold: Double = 100,
        creditUtilizationThreshold: Double = 30
    ) {
        self.largeTransaction = largeTransaction
        self.lowBalance = lowBalance
        self.highUtilization = highUtilization
        self.staleSync = staleSync
        self.loginRequired = loginRequired
        self.itemError = itemError
        self.largeTransactionThreshold = largeTransactionThreshold
        self.lowBalanceThreshold = lowBalanceThreshold
        self.creditUtilizationThreshold = creditUtilizationThreshold
    }
}

public enum NotificationTriggerKind: String, Codable, CaseIterable, Sendable {
    case itemError = "item-error"
    case loginRequired = "login-required"
    case syncStale = "sync-stale"
    case highUtilization = "high-utilization"
    case lowBalance = "low-balance"
    case largeTransaction = "large-transaction"

    public var clearsWhenResolved: Bool {
        switch self {
        case .itemError, .loginRequired, .syncStale, .highUtilization, .lowBalance:
            true
        case .largeTransaction:
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
        itemStatuses: [ItemStatus] = [],
        isSyncStale: Bool = false,
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
        }

        if config.loginRequired {
            for item in itemStatuses where item.status == .loginRequired {
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

        if config.largeTransaction {
            for transaction in largeTransactions(
                from: transactions,
                threshold: config.largeTransactionThreshold
            ) {
                append(largeTransactionDecision(for: transaction))
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

    private static func itemErrorDecision(for item: ItemStatus) -> NotificationTriggerDecision {
        NotificationTriggerDecision(
            kind: .itemError,
            dedupKey: dedupKey(kind: .itemError, sourceID: item.id),
            title: "Institution needs attention",
            body: "A linked institution reported a sync error. Reconnect, then refresh.",
            severity: .blocking
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

    private static func kind(forDedupKey dedupKey: String) -> NotificationTriggerKind? {
        guard let rawKind = dedupKey.split(separator: ":", maxSplits: 1).first else {
            return nil
        }
        return NotificationTriggerKind(rawValue: String(rawKind))
    }
}
