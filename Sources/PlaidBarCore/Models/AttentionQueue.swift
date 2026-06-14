import Foundation

public enum AttentionQueueSeverity: String, Codable, Sendable {
    case healthy
    case warning
    case blocked

    /// Short visible text that backs up the row's status icon and tint.
    public var statusLabel: String {
        switch self {
        case .healthy: "Healthy"
        case .warning: "Needs attention"
        case .blocked: "Blocked"
        }
    }

    /// SF Symbol selected for distinct shape, not just tint.
    public var statusSymbolName: String {
        switch self {
        case .healthy: "checkmark.circle.fill"
        case .warning: "exclamationmark.triangle.fill"
        case .blocked: "xmark.octagon.fill"
        }
    }

    /// Severity tier of the failure this row represents; `nil` for healthy
    /// rows, which carry no error. Warnings are advisory (inline recovery),
    /// blocked rows gate the connection or credential path.
    public var errorSeverity: ErrorSeverity? {
        switch self {
        case .healthy: nil
        case .warning: .advisory
        case .blocked: .blocking
        }
    }
}

public struct AttentionQueueRow: Equatable, Identifiable, Sendable {
    public let id: String
    public let severity: AttentionQueueSeverity
    public let title: String
    public let detail: String
    public let menuBarAttentionText: String?
    public let action: DashboardStatusReadinessAction?
    public let actionTitle: String?
    public let actionIconName: String?
    public let targetItemId: String?
    public let accessibilityLabel: String
    public let accessibilityHint: String?

    /// Id prefix for financial cockpit rows (low cash, high utilization,
    /// unusual spend). Used to keep these out of sync-health treatment.
    public static let financialAttentionIDPrefix = "financial-"

    /// Severity tier derived from the row's existing severity state.
    public var errorSeverity: ErrorSeverity? {
        severity.errorSeverity
    }

    /// `true` when this row is a financial cockpit warning rather than a
    /// sync/connection state. Sync-health UI should ignore these rows.
    public var isFinancialAttention: Bool {
        id.hasPrefix(Self.financialAttentionIDPrefix)
    }

    public init(
        id: String,
        severity: AttentionQueueSeverity,
        title: String,
        detail: String,
        menuBarAttentionText: String? = nil,
        action: DashboardStatusReadinessAction? = nil,
        actionTitle: String? = nil,
        actionIconName: String? = nil,
        targetItemId: String? = nil,
        accessibilityLabel: String? = nil,
        accessibilityHint: String? = nil
    ) {
        self.id = id
        self.severity = severity
        self.title = title
        self.detail = detail
        self.menuBarAttentionText = menuBarAttentionText
        self.action = action
        self.actionTitle = actionTitle ?? action?.defaultTitle
        self.actionIconName = actionIconName ?? action?.defaultIconName
        self.targetItemId = targetItemId
        self.accessibilityLabel = accessibilityLabel ?? "\(severity.statusLabel). \(title). \(detail)"
        self.accessibilityHint = accessibilityHint
    }
}

public struct AttentionQueue: Equatable, Sendable {
    public static let maximumRowCount = 3
    private static let maxRenderedErrorLength = 160

    public let rows: [AttentionQueueRow]

    public init(rows: [AttentionQueueRow]) {
        self.rows = Array(rows.prefix(Self.maximumRowCount))
    }

    /// Highest severity tier across the visible rows; `nil` when every row
    /// is healthy. Chrome-level alert treatments (menu bar, status strip)
    /// should key off `.blocking` only.
    public var highestErrorSeverity: ErrorSeverity? {
        rows.compactMap(\.errorSeverity).max()
    }

    public static func evaluate(
        isDemoMode: Bool,
        serverConnected: Bool,
        credentialsConfigured: Bool?,
        linkedItemCount: Int,
        accountCount: Int,
        syncedItemCount: Int,
        itemStatuses: [ItemStatus],
        isSyncStale: Bool,
        lastSyncRelative: String?,
        errorMessage: String?,
        accounts: [AccountDTO] = [],
        transactions: [TransactionDTO] = [],
        lowCashThreshold: Double = 100,
        largeTransactionThreshold: Double = 500,
        creditUtilizationThreshold: Double = PlaidBarConstants.creditUtilizationWarningThreshold,
        now: Date = Date(),
        calendar: Calendar = .current
    ) -> AttentionQueue {
        if isDemoMode {
            return AttentionQueue(rows: [healthyDemoRow])
        }

        var rows: [AttentionQueueRow] = []

        if let authRow = localServerAuthRow(from: errorMessage) {
            rows.append(authRow)
        } else if !serverConnected {
            rows.append(AttentionQueueRow(
                id: "server-offline",
                severity: .blocked,
                title: "Server offline",
                detail: "Start the VaultPeek companion server, then check the connection.",
                action: .checkServer,
                accessibilityHint: "Checks the local VaultPeek companion server connection."
            ))
        }

        if serverConnected, credentialsConfigured == false {
            rows.append(AttentionQueueRow(
                id: "credentials-missing",
                severity: .blocked,
                title: "Plaid credentials missing",
                detail: "Add local Plaid credentials before linking or refreshing.",
                action: .openSettings,
                accessibilityHint: "Opens Settings without showing credential values."
            ))
        }

        let credentialsReady = credentialsConfigured != false

        if let modeMismatch = serverModeMismatchRow(from: errorMessage) {
            rows.append(modeMismatch)
        }

        if credentialsReady {
            rows.append(contentsOf: degradedItemRows(from: itemStatuses))
        }

        if let safeError = userFacingErrorDetail(from: errorMessage),
           localServerAuthRow(from: errorMessage) == nil,
           serverModeMismatchRow(from: errorMessage) == nil {
            rows.append(AttentionQueueRow(
                id: "recent-error",
                severity: .warning,
                title: "Recent action failed",
                detail: safeError,
                action: .refresh,
                accessibilityHint: "Refreshes local VaultPeek data."
            ))
        }

        if credentialsReady, serverConnected, linkedItemCount == 0 {
            rows.append(AttentionQueueRow(
                id: "no-items",
                severity: .warning,
                title: "No institution linked",
                detail: "Connect a Plaid institution to show balances and activity.",
                action: .addAccount,
                actionTitle: "Connect Bank",
                actionIconName: "plus.circle",
                accessibilityHint: "Starts Plaid Link."
            ))
        } else if credentialsReady, serverConnected, linkedItemCount > 0, accountCount == 0 {
            rows.append(AttentionQueueRow(
                id: "balances-not-loaded",
                severity: .warning,
                title: "Balances not loaded",
                detail: "Refresh to load account balances from linked items.",
                action: .refresh,
                actionTitle: "Load Balances"
            ))
        } else if credentialsReady, serverConnected, linkedItemCount > 0, syncedItemCount == 0 {
            rows.append(AttentionQueueRow(
                id: "first-sync-needed",
                severity: .warning,
                title: "First sync needed",
                detail: "Run the first transaction sync for linked items.",
                action: .refresh,
                actionTitle: "Run First Sync"
            ))
        } else if credentialsReady, serverConnected, syncedItemCount < linkedItemCount {
            rows.append(AttentionQueueRow(
                id: "first-sync-incomplete",
                severity: .warning,
                title: "First sync incomplete",
                detail: "\(syncedItemCount) of \(linkedItemCount) linked item\(linkedItemCount == 1 ? "" : "s") synced.",
                action: .refresh,
                actionTitle: "Finish Sync"
            ))
        } else if credentialsReady, serverConnected, isSyncStale {
            rows.append(AttentionQueueRow(
                id: "sync-stale",
                severity: .warning,
                title: "Sync is stale",
                detail: "Last sync: \(lastSyncRelative ?? "never"). Refresh for current data.",
                menuBarAttentionText: lastSyncRelative == nil ? "Never" : "Stale",
                action: .refresh,
                actionTitle: "Refresh Now"
            ))
        }

        // Only evaluate aggregate finance warnings once every linked item has
        // completed its first sync. With a partially-synced set, balances and
        // transactions from the unsynced item are absent, so aggregate
        // cash/utilization/spend could fire on incomplete data.
        if credentialsReady, serverConnected, linkedItemCount > 0, accountCount > 0,
           syncedItemCount >= linkedItemCount {
            rows.append(contentsOf: financialAttentionRows(
                accounts: accounts,
                transactions: transactions,
                lowCashThreshold: lowCashThreshold,
                largeTransactionThreshold: largeTransactionThreshold,
                creditUtilizationThreshold: creditUtilizationThreshold,
                now: now,
                calendar: calendar
            ))
        }

        guard !rows.isEmpty else {
            return AttentionQueue(rows: [healthyRow(linkedItemCount: linkedItemCount, lastSyncRelative: lastSyncRelative)])
        }

        return AttentionQueue(rows: rows.sorted(by: rowSort))
    }

    private static var healthyDemoRow: AttentionQueueRow {
        AttentionQueueRow(
            id: "demo-healthy",
            severity: .healthy,
            title: "Demo data ready",
            detail: "Local demo accounts are loaded.",
            action: .addAccount,
            actionTitle: "Connect Bank"
        )
    }

    private static func healthyRow(linkedItemCount: Int, lastSyncRelative: String?) -> AttentionQueueRow {
        AttentionQueueRow(
            id: "healthy",
            severity: .healthy,
            title: "Plaid sync healthy",
            detail: "\(linkedItemCount) linked item\(linkedItemCount == 1 ? "" : "s") connected. Last sync: \(lastSyncRelative ?? "just now").",
            action: .refresh,
            actionTitle: "Refresh Data"
        )
    }

    private static func degradedItemRows(from itemStatuses: [ItemStatus]) -> [AttentionQueueRow] {
        itemStatuses.enumerated().compactMap { index, item in
            switch item.status {
            case .connected:
                return nil
            case .error:
                return AttentionQueueRow(
                    id: "item-error-\(index)",
                    severity: .blocked,
                    title: itemTitle(item, fallback: "Institution needs attention"),
                    detail: itemDetail(item, fallback: "Plaid reported an item error. Reconnect, then refresh."),
                    action: .reconnect,
                    actionTitle: reconnectTitle(item),
                    actionIconName: "link.badge.plus",
                    targetItemId: item.id,
                    accessibilityHint: "Reconnects this institution through Plaid Link."
                )
            case .loginRequired:
                return AttentionQueueRow(
                    id: "item-login-\(index)",
                    severity: .warning,
                    title: itemTitle(item, fallback: "Fresh login needed"),
                    detail: itemDetail(item, fallback: "Plaid requires a fresh bank login before sync can continue."),
                    action: .reconnect,
                    actionTitle: reconnectTitle(item),
                    actionIconName: "link.badge.plus",
                    targetItemId: item.id,
                    accessibilityHint: "Reconnects this institution through Plaid Link."
                )
            }
        }
    }

    /// Sliding window for "recent spending changed". A large transaction older
    /// than this no longer keeps the Spend attention state active.
    static let unusualSpendingWindowDays = 7

    private static func financialAttentionRows(
        accounts: [AccountDTO],
        transactions: [TransactionDTO],
        lowCashThreshold: Double,
        largeTransactionThreshold: Double,
        creditUtilizationThreshold: Double,
        now: Date,
        calendar: Calendar
    ) -> [AttentionQueueRow] {
        var rows: [AttentionQueueRow] = []

        // Low cash is per-account: a single checking account below the threshold
        // is a low-cash signal even if a savings account holds enough, matching
        // NotificationTriggerSelection.lowBalanceAccounts.
        let lowCashAccounts = NotificationTriggerSelection.lowBalanceAccounts(
            from: accounts,
            threshold: lowCashThreshold
        )
        if !lowCashAccounts.isEmpty {
            rows.append(AttentionQueueRow(
                id: "financial-low-cash",
                severity: .warning,
                title: "Cash buffer is low",
                detail: "A cash account is below your local attention threshold. Review cash accounts before upcoming payments.",
                menuBarAttentionText: "Cash",
                action: .refresh,
                actionTitle: "Refresh Data",
                accessibilityHint: "Refreshes local balances before you review cash accounts."
            ))
        }

        if let utilization = MenuBarSummary.creditUtilization(from: accounts),
           utilization >= creditUtilizationThreshold {
            rows.append(AttentionQueueRow(
                id: "financial-high-utilization",
                severity: .warning,
                title: "Credit utilization is high",
                detail: "Credit usage is at or above your local attention threshold. Review credit accounts for the next payment step.",
                menuBarAttentionText: "Credit",
                action: .refresh,
                actionTitle: "Refresh Data",
                accessibilityHint: "Refreshes local credit balances before you review utilization."
            ))
        }

        // Only count large transactions inside the recent window so a one-time
        // months-old purchase does not keep the Spend badge active indefinitely.
        let windowStart = calendar.date(
            byAdding: .day,
            value: -unusualSpendingWindowDays,
            to: calendar.startOfDay(for: now)
        )
        let unusualSpendCount = NotificationTriggerSelection.largeTransactions(
            from: transactions,
            threshold: largeTransactionThreshold
        )
        .filter { transaction in
            guard let windowStart,
                  let date = Formatters.parseTransactionDate(transaction.date)
            else { return false }
            let day = calendar.startOfDay(for: date)
            return day >= windowStart && day <= calendar.startOfDay(for: now)
        }
        .count
        if unusualSpendCount > 0 {
            rows.append(AttentionQueueRow(
                id: "financial-unusual-spending",
                severity: .warning,
                title: "Recent spending changed",
                detail: unusualSpendCount == 1
                    ? "One local transaction crossed your spending attention threshold. Review recent activity."
                    : "\(unusualSpendCount) local transactions crossed your spending attention threshold. Review recent activity.",
                menuBarAttentionText: "Spend",
                action: .refresh,
                actionTitle: "Refresh Data",
                accessibilityHint: "Refreshes local transactions before you review recent activity."
            ))
        }

        return rows
    }

    private static func itemTitle(_ item: ItemStatus, fallback: String) -> String {
        guard let institutionName = normalizedInstitutionName(item.institutionName) else { return fallback }
        switch item.status {
        case .connected:
            return institutionName
        case .loginRequired:
            return "\(institutionName) needs login"
        case .error:
            return "\(institutionName) needs attention"
        }
    }

    private static func itemDetail(_ item: ItemStatus, fallback: String) -> String {
        guard let institutionName = normalizedInstitutionName(item.institutionName) else { return fallback }
        switch item.status {
        case .connected:
            return "Connected."
        case .loginRequired:
            return "Plaid requires a fresh \(institutionName) login before sync can continue."
        case .error:
            return "Plaid reported an item error for \(institutionName). Reconnect, then refresh."
        }
    }

    private static func reconnectTitle(_ item: ItemStatus) -> String {
        guard let institutionName = normalizedInstitutionName(item.institutionName) else { return "Reconnect Item" }
        return "Reconnect \(institutionName)"
    }

    private static func localServerAuthRow(from message: String?) -> AttentionQueueRow? {
        guard let message else { return nil }
        let normalized = message
            .split(whereSeparator: \.isWhitespace)
            .joined(separator: " ")
            .lowercased()

        if normalized.contains("auth token is unavailable") {
            return AttentionQueueRow(
                id: "local-auth-missing",
                severity: .blocked,
                title: "Local server auth missing",
                detail: "Restart the VaultPeek companion server, then check the connection.",
                action: .openSettings
            )
        }

        if normalized.contains("plaidbar server returned 401") ||
            normalized.contains("plaidbar server returned 403") ||
            normalized.contains("vaultpeek companion server returned 401") ||
            normalized.contains("vaultpeek companion server returned 403") {
            return AttentionQueueRow(
                id: "local-auth-rejected",
                severity: .blocked,
                title: "Local server auth rejected",
                detail: "Restart the VaultPeek companion server so the local token is regenerated.",
                action: .openSettings
            )
        }

        return nil
    }

    private static func serverModeMismatchRow(from message: String?) -> AttentionQueueRow? {
        guard let message else { return nil }
        let normalized = message
            .split(whereSeparator: \.isWhitespace)
            .joined(separator: " ")
        let lowercased = normalized.lowercased()

        guard lowercased.contains("server is running in"),
              lowercased.contains("not sandbox") || lowercased.contains("not production")
        else { return nil }

        return AttentionQueueRow(
            id: "server-mode-mismatch",
            severity: .blocked,
            title: "Server mode mismatch",
            detail: UserFacingError.sanitizedDetail(from: normalized, maxLength: maxRenderedErrorLength) ?? "Restart the VaultPeek companion server in the selected environment.",
            action: .checkServer,
            accessibilityHint: "Checks whether the VaultPeek companion server is running in the selected Plaid environment."
        )
    }

    private static func userFacingErrorDetail(from message: String?) -> String? {
        UserFacingError.sanitizedDetail(from: message, maxLength: maxRenderedErrorLength)
    }

    private static func normalizedInstitutionName(_ institutionName: String?) -> String? {
        guard let institutionName else { return nil }
        let trimmed = institutionName.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }

    private static func rowSort(_ lhs: AttentionQueueRow, _ rhs: AttentionQueueRow) -> Bool {
        let lhsRank = rowRank(lhs)
        let rhsRank = rowRank(rhs)
        if lhsRank != rhsRank { return lhsRank < rhsRank }
        return lhs.id < rhs.id
    }

    private static func rowRank(_ row: AttentionQueueRow) -> Int {
        switch row.id {
        case "local-auth-missing", "local-auth-rejected": return 0
        case "server-offline": return 1
        case "credentials-missing": return 2
        default:
            if row.id.hasPrefix("item-error-") { return 4 }
            if row.id.hasPrefix("item-login-") { return 5 }
            switch row.id {
            case "server-mode-mismatch": return 3
            case "recent-error": return 6
            case "no-items": return 7
            case "balances-not-loaded": return 8
            case "first-sync-needed": return 9
            case "first-sync-incomplete": return 10
            case "sync-stale": return 11
            case "financial-low-cash": return 12
            case "financial-high-utilization": return 13
            case "financial-unusual-spending": return 14
            default:
                // Unknown rows fall back to severity-tier ordering: blocking
                // failures first, advisories next, healthy rows last.
                switch row.errorSeverity {
                case .blocking: return 20
                case .advisory: return 30
                case nil: return 40
                }
            }
        }
    }
}
