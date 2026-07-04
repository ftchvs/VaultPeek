import Foundation
@testable import PlaidBarCore
import Testing

@Suite("AttentionQueue Tests")
struct AttentionQueueTests {
    @Test("Severity exposes status text and shaped symbols")
    func severityExposesStatusTextAndSymbols() {
        #expect(AttentionQueueSeverity.healthy.statusLabel == "Healthy")
        #expect(AttentionQueueSeverity.healthy.statusSymbolName == "checkmark.circle.fill")
        #expect(AttentionQueueSeverity.warning.statusLabel == "Needs attention")
        #expect(AttentionQueueSeverity.warning.statusSymbolName == "exclamationmark.triangle.fill")
        #expect(AttentionQueueSeverity.blocked.statusLabel == "Blocked")
        #expect(AttentionQueueSeverity.blocked.statusSymbolName == "xmark.octagon.fill")
    }

    @Test("Visible count text is withheld under Privacy Mask")
    func visibleCountTextWithheldWhenMasked() {
        #expect(AttentionQueue.countText(rowCount: 2, isMasked: false) == "2/3")
        #expect(AttentionQueue.countText(rowCount: 2, isMasked: true) == nil)
    }

    @Test("Container accessibility label withholds exact item counts under Privacy Mask")
    func containerAccessibilityLabelWithholdsCountsWhenMasked() {
        #expect(
            AttentionQueue.containerAccessibilityLabel(title: "Attention", rowCount: 1, isMasked: false)
                == "Attention, 1 item"
        )
        #expect(
            AttentionQueue.containerAccessibilityLabel(title: "Attention", rowCount: 2, isMasked: false)
                == "Attention, 2 items"
        )
        #expect(
            AttentionQueue.containerAccessibilityLabel(title: "Attention", rowCount: 2, isMasked: true)
                == "Attention, private items"
        )
    }

    @Test("Queue row accessibility labels include status text backup")
    func accessibilityLabelsIncludeStatusTextBackup() {
        let queue = AttentionQueue.evaluate(
            isDemoMode: false,
            serverConnected: false,
            credentialsConfigured: true,
            linkedItemCount: 1,
            accountCount: 1,
            syncedItemCount: 1,
            itemStatuses: [
                ItemStatus(id: "item-login-secret", institutionName: "Example Bank", status: .loginRequired),
            ],
            isSyncStale: false,
            lastSyncRelative: "now",
            errorMessage: nil
        )

        #expect(queue.rows.map(\.accessibilityLabel).contains {
            $0.hasPrefix("Blocked. Server offline.")
        })
        #expect(queue.rows.map(\.accessibilityLabel).contains {
            $0.hasPrefix("Needs attention. Example Bank needs login.")
        })
        #expect(queue.rows.allSatisfy { !$0.accessibilityLabel.contains("item-login-secret") })
    }

    @Test("Queue prioritizes blocked recovery before login, stale sync, and healthy rows")
    func orderingPrioritizesBlockedRecovery() {
        let queue = AttentionQueue.evaluate(
            isDemoMode: false,
            serverConnected: true,
            credentialsConfigured: false,
            linkedItemCount: 2,
            accountCount: 4,
            syncedItemCount: 2,
            itemStatuses: [
                ItemStatus(id: "item-login-secret", institutionName: "Example Bank", status: .loginRequired),
                ItemStatus(id: "item-error-secret", institutionName: "City Credit", status: .error),
            ],
            isSyncStale: true,
            lastSyncRelative: "3 days ago",
            errorMessage: nil
        )

        #expect(queue.rows.map(\.id) == [
            "credentials-missing",
        ])
        #expect(queue.rows.count == 1)
        #expect(queue.rows.map(\.severity) == [.blocked])
        #expect(queue.rows[0].action == .openSettings)
        #expect(queue.rows[0].targetItemId == nil)
    }

    @Test("Queue redacts token-like error details from display and accessibility copy")
    func redactsSensitiveErrorDetails() {
        let tokenName = "access" + "-sandbox" + "-abc123456789"
        let secretName = "client" + "_secret"
        let secretValue = "super" + "-secret" + "-value"
        let queue = AttentionQueue.evaluate(
            isDemoMode: false,
            serverConnected: true,
            credentialsConfigured: true,
            linkedItemCount: 1,
            accountCount: 1,
            syncedItemCount: 1,
            itemStatuses: [],
            isSyncStale: false,
            lastSyncRelative: "now",
            errorMessage: #"Plaid failed with \#(tokenName) and \#(secretName)="\#(secretValue)""#
        )

        let joinedDisplayCopy = queue.rows
            .flatMap { [$0.title, $0.detail, $0.actionTitle ?? "", $0.accessibilityLabel, $0.accessibilityHint ?? ""] }
            .joined(separator: " ")

        #expect(joinedDisplayCopy.contains(tokenName) == false)
        #expect(joinedDisplayCopy.contains(secretValue) == false)
        #expect(joinedDisplayCopy.contains("[redacted-token]"))
        #expect(joinedDisplayCopy.contains("\(secretName): [redacted]"))
    }

    @Test("Queue presentation does not expose item IDs or raw balances")
    func presentationHidesSensitiveIdentifiersAndBalances() {
        let accountID = "accountSensitiveIdentifier"
        let itemID = "itemSensitiveIdentifier"
        let balance = "12345.67"
        let currentBalance = "-890.12"

        let queue = AttentionQueue.evaluate(
            isDemoMode: false,
            serverConnected: true,
            credentialsConfigured: true,
            linkedItemCount: 1,
            accountCount: 1,
            syncedItemCount: 1,
            itemStatuses: [
                ItemStatus(id: itemID, institutionName: "Example Bank", status: .loginRequired),
            ],
            isSyncStale: false,
            lastSyncRelative: "now",
            errorMessage: "Plaid failed account_id=\(accountID) item_id=\(itemID) balance=\(balance) current_balance=\(currentBalance)"
        )

        let joinedDisplayCopy = queue.rows
            .flatMap { [$0.title, $0.detail, $0.actionTitle ?? "", $0.accessibilityLabel, $0.accessibilityHint ?? ""] }
            .joined(separator: " ")

        #expect(joinedDisplayCopy.contains(accountID) == false)
        #expect(joinedDisplayCopy.contains(itemID) == false)
        #expect(joinedDisplayCopy.contains(balance) == false)
        #expect(joinedDisplayCopy.contains(currentBalance) == false)
        #expect(joinedDisplayCopy.contains("[redacted-id]"))
        #expect(joinedDisplayCopy.contains("[redacted-balance]"))
    }

    @Test("Queue preserves server mode mismatch recovery action")
    func preservesServerModeMismatchRecoveryAction() {
        let queue = AttentionQueue.evaluate(
            isDemoMode: false,
            serverConnected: true,
            credentialsConfigured: true,
            linkedItemCount: 1,
            accountCount: 1,
            syncedItemCount: 1,
            itemStatuses: [],
            isSyncStale: false,
            lastSyncRelative: "now",
            errorMessage: "Server is running in production, not sandbox. Restart the server in sandbox mode."
        )

        #expect(queue.rows.first?.id == "server-mode-mismatch")
        #expect(queue.rows.first?.severity == .blocked)
        #expect(queue.rows.first?.title == "Server mode mismatch")
        #expect(queue.rows.first?.action == .checkServer)
        #expect(queue.rows.contains { $0.id == "recent-error" } == false)
    }

    @Test("Queue suppresses downstream Plaid actions until credentials are configured")
    func suppressesDownstreamActionsUntilCredentialsConfigured() {
        let queue = AttentionQueue.evaluate(
            isDemoMode: false,
            serverConnected: true,
            credentialsConfigured: false,
            linkedItemCount: 0,
            accountCount: 0,
            syncedItemCount: 0,
            itemStatuses: [
                ItemStatus(id: "item-login-secret", institutionName: "Example Bank", status: .loginRequired),
            ],
            isSyncStale: true,
            lastSyncRelative: "never",
            errorMessage: nil
        )

        #expect(queue.rows.map(\.id) == ["credentials-missing"])
        #expect(queue.rows.first?.action == .openSettings)
        #expect(queue.rows
            .contains { $0.action == .addAccount || $0.action == .reconnect || $0.action == .refresh } == false)
    }

    @Test("Queue ranks server mode mismatch above item reconnect rows")
    func ranksServerModeMismatchAboveItemReconnectRows() {
        let queue = AttentionQueue.evaluate(
            isDemoMode: false,
            serverConnected: true,
            credentialsConfigured: true,
            linkedItemCount: 4,
            accountCount: 4,
            syncedItemCount: 4,
            itemStatuses: [
                ItemStatus(id: "item-error-a", institutionName: "Bank A", status: .error),
                ItemStatus(id: "item-error-b", institutionName: "Bank B", status: .error),
                ItemStatus(id: "item-error-c", institutionName: "Bank C", status: .error),
            ],
            isSyncStale: false,
            lastSyncRelative: "now",
            errorMessage: "Server is running in production, not sandbox."
        )

        #expect(queue.rows.map(\.id).first == "server-mode-mismatch")
        #expect(queue.rows.map(\.id).contains("server-mode-mismatch"))
    }

    @Test("Healthy recovery state collapses to one compact row")
    func healthyStateCollapsesToOneRow() {
        let queue = AttentionQueue.evaluate(
            isDemoMode: false,
            serverConnected: true,
            credentialsConfigured: true,
            linkedItemCount: 2,
            accountCount: 5,
            syncedItemCount: 2,
            itemStatuses: [
                ItemStatus(id: "item-a", institutionName: "Example Bank", status: .connected),
                ItemStatus(id: "item-b", institutionName: "City Credit", status: .connected),
            ],
            isSyncStale: false,
            lastSyncRelative: "4 minutes ago",
            errorMessage: nil
        )

        #expect(queue.rows.count == 1)
        #expect(queue.rows[0].id == "healthy")
        #expect(queue.rows[0].severity == .healthy)
        #expect(queue.rows[0].title == "Plaid sync healthy")
        #expect(queue.rows[0].detail.contains("2 linked items connected"))
    }

    @Test("Queue represents financial attention states in deterministic priority order")
    func representsFinancialAttentionStatesInPriorityOrder() {
        let queue = AttentionQueue.evaluate(
            isDemoMode: false,
            serverConnected: true,
            credentialsConfigured: true,
            linkedItemCount: 1,
            accountCount: 3,
            syncedItemCount: 1,
            itemStatuses: [],
            isSyncStale: false,
            lastSyncRelative: "now",
            errorMessage: nil,
            accounts: [
                depository(id: "checking-sensitive-id", balance: 99),
                credit(id: "card-sensitive-id", current: -300, limit: 1_000),
            ],
            transactions: [
                transaction(id: "tx-sensitive-id", amount: 500),
            ],
            lowCashThreshold: 100,
            largeTransactionThreshold: 500,
            creditUtilizationThreshold: 30,
            now: Formatters.parseTransactionDate("2026-06-14")!
        )

        #expect(queue.rows.map(\.id) == [
            "financial-low-cash",
            "financial-high-utilization",
            "financial-unusual-spending",
        ])
        #expect(queue.rows.map(\.menuBarAttentionText) == ["Cash", "Credit", "Spend"])
        #expect(queue.rows.allSatisfy { $0.severity == .warning })
        #expect(queue.highestErrorSeverity == .advisory)
    }

    @Test("Queue keeps sync and recovery warnings ahead of financial attention")
    func keepsRecoveryWarningsAheadOfFinancialAttention() {
        let queue = AttentionQueue.evaluate(
            isDemoMode: false,
            serverConnected: true,
            credentialsConfigured: true,
            linkedItemCount: 1,
            accountCount: 2,
            syncedItemCount: 1,
            itemStatuses: [
                ItemStatus(id: "item-login-sensitive", institutionName: "Example Bank", status: .loginRequired),
            ],
            isSyncStale: true,
            lastSyncRelative: "3 days ago",
            errorMessage: nil,
            accounts: [
                depository(id: "checking-sensitive-id", balance: 10),
                credit(id: "card-sensitive-id", current: -900, limit: 1_000),
            ],
            transactions: [
                transaction(id: "tx-sensitive-id", amount: 900),
            ],
            lowCashThreshold: 100,
            largeTransactionThreshold: 500,
            creditUtilizationThreshold: 30
        )

        #expect(queue.rows.map(\.id) == [
            "item-repair-0",
            "sync-stale",
            "financial-low-cash",
        ])
        #expect(queue.rows.first?.action == .reconnect)
    }

    @Test("Queue routes new accounts available to update mode")
    func routesNewAccountsAvailableToUpdateMode() {
        let queue = AttentionQueue.evaluate(
            isDemoMode: false,
            serverConnected: true,
            credentialsConfigured: true,
            linkedItemCount: 1,
            accountCount: 1,
            syncedItemCount: 1,
            itemStatuses: [
                ItemStatus(id: "item-new-accounts", institutionName: "Example Bank", status: .newAccountsAvailable),
            ],
            isSyncStale: false,
            lastSyncRelative: "now",
            errorMessage: nil
        )

        #expect(queue.rows.first?.id == "item-repair-0")
        #expect(queue.rows.first?.title == "Example Bank has new accounts")
        #expect(queue.rows.first?.detail == "Example Bank has newly available accounts. Update this item to choose what VaultPeek can access.")
        #expect(queue.rows.first?.action == .reconnect)
        #expect(queue.rows.first?.targetItemId == "item-new-accounts")
    }

    @Test("Financial attention threshold edges are inclusive where configured")
    func financialThresholdEdgesAreInclusiveWhereConfigured() {
        let atThreshold = AttentionQueue.evaluate(
            isDemoMode: false,
            serverConnected: true,
            credentialsConfigured: true,
            linkedItemCount: 1,
            accountCount: 3,
            syncedItemCount: 1,
            itemStatuses: [],
            isSyncStale: false,
            lastSyncRelative: "now",
            errorMessage: nil,
            accounts: [
                depository(id: "checking", balance: 100),
                credit(id: "card", current: -300, limit: 1_000),
            ],
            transactions: [
                transaction(id: "tx-at-threshold", amount: 500),
            ],
            lowCashThreshold: 100,
            largeTransactionThreshold: 500,
            creditUtilizationThreshold: 30,
            now: Formatters.parseTransactionDate("2026-06-14")!
        )
        let belowWarnings = AttentionQueue.evaluate(
            isDemoMode: false,
            serverConnected: true,
            credentialsConfigured: true,
            linkedItemCount: 1,
            accountCount: 3,
            syncedItemCount: 1,
            itemStatuses: [],
            isSyncStale: false,
            lastSyncRelative: "now",
            errorMessage: nil,
            accounts: [
                depository(id: "checking", balance: 100),
                credit(id: "card", current: -299, limit: 1_000),
            ],
            transactions: [
                transaction(id: "tx-below-threshold", amount: 499.99),
            ],
            lowCashThreshold: 100,
            largeTransactionThreshold: 500,
            creditUtilizationThreshold: 30,
            now: Formatters.parseTransactionDate("2026-06-14")!
        )

        #expect(atThreshold.rows.map(\.id) == [
            "financial-high-utilization",
            "financial-unusual-spending",
        ])
        #expect(belowWarnings.rows.map(\.id) == ["healthy"])
    }

    @Test("Stale large transactions outside the recent window do not raise spend attention")
    func staleLargeTransactionsDoNotRaiseSpendAttention() {
        let now = Formatters.parseTransactionDate("2026-06-14")!
        let queue = AttentionQueue.evaluate(
            isDemoMode: false,
            serverConnected: true,
            credentialsConfigured: true,
            linkedItemCount: 1,
            accountCount: 1,
            syncedItemCount: 1,
            itemStatuses: [],
            isSyncStale: false,
            lastSyncRelative: "now",
            errorMessage: nil,
            accounts: [depository(id: "checking", balance: 5_000)],
            transactions: [
                // A large purchase from over a month ago must not keep the Spend
                // badge active once it is outside the recent window.
                TransactionDTO(id: "old-large", accountId: "acct", amount: 900, date: "2026-05-01", name: "Old Purchase"),
            ],
            lowCashThreshold: 100,
            largeTransactionThreshold: 500,
            creditUtilizationThreshold: 30,
            now: now
        )

        #expect(!queue.rows.map(\.id).contains("financial-unusual-spending"))
        #expect(queue.rows.map(\.id) == ["healthy"])
    }

    @Test("Finance attention is suppressed until all linked items finish first sync")
    func financeAttentionWaitsForAllItemsSynced() {
        let now = Formatters.parseTransactionDate("2026-06-14")!
        let queue = AttentionQueue.evaluate(
            isDemoMode: false,
            serverConnected: true,
            credentialsConfigured: true,
            linkedItemCount: 2,
            accountCount: 1,
            syncedItemCount: 1,
            itemStatuses: [],
            isSyncStale: false,
            lastSyncRelative: "now",
            errorMessage: nil,
            accounts: [depository(id: "checking", balance: 10)],
            transactions: [
                TransactionDTO(id: "recent-large", accountId: "acct", amount: 900, date: "2026-06-13", name: "Recent"),
            ],
            lowCashThreshold: 100,
            largeTransactionThreshold: 500,
            creditUtilizationThreshold: 30,
            now: now
        )

        // With one of two items still unsynced, partial data must not drive
        // aggregate finance warnings; only the first-sync-incomplete row shows.
        #expect(!queue.rows.contains { $0.isFinancialAttention })
        #expect(queue.rows.map(\.id) == ["first-sync-incomplete"])
    }

    @Test("Low cash is detected per account, not by summed depository cash")
    func lowCashIsDetectedPerAccount() {
        let now = Formatters.parseTransactionDate("2026-06-14")!
        let queue = AttentionQueue.evaluate(
            isDemoMode: false,
            serverConnected: true,
            credentialsConfigured: true,
            linkedItemCount: 1,
            accountCount: 2,
            syncedItemCount: 1,
            itemStatuses: [],
            isSyncStale: false,
            lastSyncRelative: "now",
            errorMessage: nil,
            accounts: [
                // Checking is below threshold even though total depository cash
                // (checking + savings) is well above it.
                depository(id: "checking", balance: 20),
                depository(id: "savings", balance: 5_000),
            ],
            transactions: [],
            lowCashThreshold: 100,
            largeTransactionThreshold: 500,
            creditUtilizationThreshold: 30,
            now: now
        )

        #expect(queue.rows.map(\.id).contains("financial-low-cash"))
    }

    @Test("Financial attention copy stays private and amount-free")
    func financialAttentionCopyStaysPrivateAndAmountFree() {
        let accountID = "acct_sensitive_private"
        let transactionID = "tx_sensitive_private"
        let accountName = "Sensitive Checking 4321"
        let merchant = "Sensitive Merchant"
        let institution = "Sensitive Bank"
        let queue = AttentionQueue.evaluate(
            isDemoMode: false,
            serverConnected: true,
            credentialsConfigured: true,
            linkedItemCount: 1,
            accountCount: 2,
            syncedItemCount: 1,
            itemStatuses: [],
            isSyncStale: false,
            lastSyncRelative: "now",
            errorMessage: nil,
            accounts: [
                AccountDTO(
                    id: accountID,
                    itemId: "item_sensitive_private",
                    name: accountName,
                    type: .depository,
                    balances: BalanceDTO(available: 12.34),
                    institutionName: institution
                ),
                credit(id: "credit_sensitive_private", current: -900, limit: 1_000),
            ],
            transactions: [
                TransactionDTO(
                    id: transactionID,
                    accountId: accountID,
                    amount: 9_876.54,
                    date: "2026-06-12",
                    name: "Raw Sensitive Merchant",
                    merchantName: merchant
                ),
            ],
            lowCashThreshold: 100,
            largeTransactionThreshold: 500,
            creditUtilizationThreshold: 30
        )

        let renderedCopy = queue.rows
            .flatMap {
                [
                    $0.title,
                    $0.detail,
                    $0.menuBarAttentionText ?? "",
                    $0.actionTitle ?? "",
                    $0.accessibilityLabel,
                    $0.accessibilityHint ?? "",
                ]
            }
            .joined(separator: " ")

        for privateText in [
            accountID,
            transactionID,
            accountName,
            merchant,
            institution,
            "Raw Sensitive Merchant",
            "9876.54",
            "12.34",
            "$",
        ] {
            #expect(renderedCopy.contains(privateText) == false)
        }
    }

    // MARK: - STATE-5: notification-permission row (convergence)

    @Test("Notification permission denied surfaces a recovery row mirroring the dashboard")
    func notificationPermissionDeniedSurfacesRow() {
        let queue = AttentionQueue.evaluate(
            isDemoMode: false,
            serverConnected: true,
            credentialsConfigured: true,
            linkedItemCount: 1,
            accountCount: 1,
            syncedItemCount: 1,
            itemStatuses: [],
            isSyncStale: false,
            lastSyncRelative: "now",
            errorMessage: nil,
            notificationsEnabled: true,
            notificationPermission: .evaluate(kind: .denied)
        )

        let row = queue.rows.first { $0.id == "notification-permission" }
        #expect(row != nil)
        #expect(row?.severity == .warning)
        #expect(row?.title == "Notifications blocked")
        #expect(row?.action == .openNotificationSettings)
        #expect(row?.actionTitle == "Open System Settings")
    }

    @Test("Notification permission not-requested offers the permission request")
    func notificationPermissionNotRequestedOffersRequest() {
        let queue = AttentionQueue.evaluate(
            isDemoMode: false,
            serverConnected: true,
            credentialsConfigured: true,
            linkedItemCount: 1,
            accountCount: 1,
            syncedItemCount: 1,
            itemStatuses: [],
            isSyncStale: false,
            lastSyncRelative: "now",
            errorMessage: nil,
            notificationsEnabled: true,
            notificationPermission: .evaluate(kind: .notDetermined)
        )

        let row = queue.rows.first { $0.id == "notification-permission" }
        #expect(row?.title == "Notification permission not requested")
        #expect(row?.action == .requestNotificationPermission)
    }

    @Test("Notification recovery is suppressed when local alerts are disabled")
    func notificationRecoverySuppressedWhenDisabled() {
        let queue = AttentionQueue.evaluate(
            isDemoMode: false,
            serverConnected: true,
            credentialsConfigured: true,
            linkedItemCount: 1,
            accountCount: 1,
            syncedItemCount: 1,
            itemStatuses: [],
            isSyncStale: false,
            lastSyncRelative: "now",
            errorMessage: nil,
            notificationsEnabled: false,
            notificationPermission: .evaluate(kind: .denied)
        )

        #expect(!queue.rows.contains { $0.id == "notification-permission" })
        #expect(queue.rows.map(\.id) == ["healthy"])
    }

    @Test("Notification recovery is omitted while authorized (no blocking state)")
    func notificationRecoveryOmittedWhenAuthorized() {
        let queue = AttentionQueue.evaluate(
            isDemoMode: false,
            serverConnected: true,
            credentialsConfigured: true,
            linkedItemCount: 1,
            accountCount: 1,
            syncedItemCount: 1,
            itemStatuses: [],
            isSyncStale: false,
            lastSyncRelative: "now",
            errorMessage: nil,
            notificationsEnabled: true,
            notificationPermission: .evaluate(kind: .authorized)
        )

        #expect(!queue.rows.contains { $0.id == "notification-permission" })
    }

    @Test("Notification recovery ranks below sync health and above financial attention")
    func notificationRecoveryRanksBelowSyncAboveFinancial() {
        let queue = AttentionQueue.evaluate(
            isDemoMode: false,
            serverConnected: true,
            credentialsConfigured: true,
            linkedItemCount: 1,
            accountCount: 2,
            syncedItemCount: 1,
            itemStatuses: [],
            isSyncStale: true,
            lastSyncRelative: "3 days ago",
            errorMessage: nil,
            accounts: [
                depository(id: "checking", balance: 10),
            ],
            transactions: [],
            lowCashThreshold: 100,
            largeTransactionThreshold: 500,
            creditUtilizationThreshold: 30,
            notificationsEnabled: true,
            notificationPermission: .evaluate(kind: .denied)
        )

        #expect(queue.rows.map(\.id) == [
            "sync-stale",
            "notification-permission",
            "financial-low-cash",
        ])
    }

    @Test("Notification recovery is suppressed until credentials and server are ready")
    func notificationRecoverySuppressedUntilInfrastructureReady() {
        let queue = AttentionQueue.evaluate(
            isDemoMode: false,
            serverConnected: false,
            credentialsConfigured: true,
            linkedItemCount: 1,
            accountCount: 1,
            syncedItemCount: 1,
            itemStatuses: [],
            isSyncStale: false,
            lastSyncRelative: "now",
            errorMessage: nil,
            notificationsEnabled: true,
            notificationPermission: .evaluate(kind: .denied)
        )

        // Server-offline dominates; notification recovery does not show.
        #expect(!queue.rows.contains { $0.id == "notification-permission" })
        #expect(queue.rows.map(\.id) == ["server-offline"])
    }

    @Test("New-accounts row uses the Update verb title, matching every surface")
    func newAccountsRowUsesUpdateTitle() {
        let queue = AttentionQueue.evaluate(
            isDemoMode: false,
            serverConnected: true,
            credentialsConfigured: true,
            linkedItemCount: 1,
            accountCount: 1,
            syncedItemCount: 1,
            itemStatuses: [
                ItemStatus(id: "item-new", institutionName: "Chase", status: .newAccountsAvailable),
            ],
            isSyncStale: false,
            lastSyncRelative: "now",
            errorMessage: nil
        )

        // STATE-2 convergence: the attention queue now says "Update Chase" for
        // newly-available accounts, matching ItemRecoveryTarget / the chip.
        #expect(queue.rows.first?.actionTitle == "Update Chase")
    }

    private func transaction(id: String, amount: Double) -> TransactionDTO {
        TransactionDTO(
            id: id,
            accountId: "acct-\(id)",
            amount: amount,
            date: "2026-06-12",
            name: "Synthetic Transaction"
        )
    }

    private func depository(id: String, balance: Double) -> AccountDTO {
        AccountDTO(
            id: id,
            itemId: "item-\(id)",
            name: "Synthetic Checking",
            type: .depository,
            balances: BalanceDTO(available: balance)
        )
    }

    private func credit(id: String, current: Double, limit: Double) -> AccountDTO {
        AccountDTO(
            id: id,
            itemId: "item-\(id)",
            name: "Synthetic Credit",
            type: .credit,
            balances: BalanceDTO(current: current, limit: limit)
        )
    }
}
