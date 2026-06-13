import Testing
@testable import PlaidBarCore

@Suite("Notification Trigger Evaluation Tests")
struct NotificationTriggerEvaluationTests {
    @Test("Evaluator emits threshold and status decisions in stable priority order")
    func emitsThresholdAndStatusDecisions() {
        let evaluation = NotificationTriggerSelection.evaluate(
            transactions: [
                transaction(id: "tx-large", amount: 650),
                transaction(id: "tx-at-threshold", amount: 500),
                transaction(id: "tx-income", amount: -1_000),
                transaction(id: "tx-small", amount: 20),
            ],
            accounts: [
                depository(id: "acct-low", balance: 50),
                depository(id: "acct-at-threshold", balance: 100),
                credit(id: "acct-high-util", current: -4_500, limit: 5_000),
                credit(id: "acct-at-util-threshold", current: -300, limit: 1_000),
            ],
            itemStatuses: [
                ItemStatus(id: "item-login", institutionName: "Example Bank", status: .loginRequired),
                ItemStatus(id: "item-error", institutionName: "City Credit", status: .error),
                ItemStatus(id: "item-ok", institutionName: "Healthy Bank", status: .connected),
            ],
            isSyncStale: true,
            config: testConfig
        )

        let kinds = evaluation.decisions.map(\NotificationTriggerDecision.kind)
        #expect(kinds == [
            NotificationTriggerKind.itemError,
            NotificationTriggerKind.loginRequired,
            NotificationTriggerKind.syncStale,
            NotificationTriggerKind.highUtilization,
            NotificationTriggerKind.lowBalance,
            NotificationTriggerKind.largeTransaction,
            NotificationTriggerKind.largeTransaction,
        ])
        let severities = evaluation.decisions.map(\NotificationTriggerDecision.severity)
        #expect(severities == [
            NotificationTriggerSeverity.blocking,
            NotificationTriggerSeverity.warning,
            NotificationTriggerSeverity.warning,
            NotificationTriggerSeverity.warning,
            NotificationTriggerSeverity.warning,
            NotificationTriggerSeverity.informational,
            NotificationTriggerSeverity.informational,
        ])
        #expect(evaluation.activeDedupKeys == Set(evaluation.decisions.map(\NotificationTriggerDecision.dedupKey)))
        #expect(evaluation.resolvedDedupKeys.isEmpty)
    }

    @Test("Delivered dedup keys suppress active decisions and clear when stateful alerts resolve")
    func deliveredDedupKeysSuppressAndResolveStatefulAlerts() {
        let active = NotificationTriggerSelection.evaluate(
            transactions: [transaction(id: "tx-large", amount: 650)],
            accounts: [
                depository(id: "acct-low", balance: 50),
                credit(id: "acct-high-util", current: -4_500, limit: 5_000),
            ],
            itemStatuses: [
                ItemStatus(id: "item-login", status: .loginRequired),
                ItemStatus(id: "item-error", status: .error),
            ],
            isSyncStale: true,
            config: testConfig
        )
        let deliveredKeys = active.activeDedupKeys

        let repeated = NotificationTriggerSelection.evaluate(
            transactions: [transaction(id: "tx-large", amount: 650)],
            accounts: [
                depository(id: "acct-low", balance: 50),
                credit(id: "acct-high-util", current: -4_500, limit: 5_000),
            ],
            itemStatuses: [
                ItemStatus(id: "item-login", status: .loginRequired),
                ItemStatus(id: "item-error", status: .error),
            ],
            isSyncStale: true,
            config: testConfig,
            deliveredDedupKeys: deliveredKeys
        )

        #expect(repeated.decisions.isEmpty)
        #expect(repeated.activeDedupKeys == deliveredKeys)
        #expect(repeated.resolvedDedupKeys.isEmpty)

        let resolved = NotificationTriggerSelection.evaluate(
            transactions: [],
            accounts: [
                depository(id: "acct-low", balance: 500),
                credit(id: "acct-high-util", current: -200, limit: 5_000),
            ],
            itemStatuses: [
                ItemStatus(id: "item-login", status: .connected),
                ItemStatus(id: "item-error", status: .connected),
            ],
            isSyncStale: false,
            config: testConfig,
            deliveredDedupKeys: deliveredKeys
        )

        let stickyLargeTransactionKey = NotificationTriggerSelection.dedupKey(
            kind: .largeTransaction,
            sourceID: "tx-large"
        )

        #expect(resolved.decisions.isEmpty)
        #expect(resolved.activeDedupKeys.isEmpty)
        #expect(resolved.resolvedDedupKeys == deliveredKeys.subtracting([stickyLargeTransactionKey]))
        #expect(resolved.resolvedDedupKeys.contains(stickyLargeTransactionKey) == false)
    }

    @Test("Dedup keys are stable and do not expose source identifiers")
    func dedupKeysAreStableAndOpaque() {
        let key = NotificationTriggerSelection.dedupKey(
            kind: .lowBalance,
            sourceID: "  acct_synthetic_private_abcdef  "
        )
        let repeatedKey = NotificationTriggerSelection.dedupKey(
            kind: .lowBalance,
            sourceID: "acct_synthetic_private_abcdef"
        )

        #expect(key == repeatedKey)
        #expect(key.hasPrefix("low-balance:"))
        #expect(key.contains("acct_synthetic_private_abcdef") == false)
        #expect(key.count == "low-balance:".count + 32)
    }

    @Test("Notification copy avoids identifiers, account names, merchants, institutions, and amounts")
    func notificationCopyAvoidsPrivateDetails() {
        let rawAccountID = "acct_synthetic_private_abcdef"
        let rawTransactionID = "tx_synthetic_private_abcdef"
        let rawItemID = "item_synthetic_private_abcdef"
        let accountName = "Sensitive Checking 4321"
        let merchantName = "Sensitive Merchant"
        let institutionName = "Sensitive Bank"

        let evaluation = NotificationTriggerSelection.evaluate(
            transactions: [
                TransactionDTO(
                    id: rawTransactionID,
                    accountId: rawAccountID,
                    amount: 9_876.54,
                    date: "2026-06-12",
                    name: "Raw Sensitive Merchant",
                    merchantName: merchantName
                ),
            ],
            accounts: [
                AccountDTO(
                    id: rawAccountID,
                    itemId: rawItemID,
                    name: accountName,
                    type: .depository,
                    balances: BalanceDTO(available: 12.34),
                    institutionName: institutionName
                ),
            ],
            itemStatuses: [
                ItemStatus(id: rawItemID, institutionName: institutionName, status: .error),
            ],
            isSyncStale: true,
            config: testConfig
        )

        let renderedCopy = evaluation.decisions
            .flatMap { [$0.title, $0.body, $0.dedupKey] }
            .joined(separator: " ")

        for privateText in [
            rawAccountID,
            rawTransactionID,
            rawItemID,
            accountName,
            merchantName,
            institutionName,
            "Raw Sensitive Merchant",
            "9876.54",
            "12.34",
        ] {
            #expect(renderedCopy.contains(privateText) == false)
        }

        #expect(evaluation.decisions.allSatisfy { !$0.body.contains("$") })
    }

    private var testConfig: NotificationTriggers {
        NotificationTriggers(
            largeTransactionThreshold: 500,
            lowBalanceThreshold: 100,
            creditUtilizationThreshold: 30
        )
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
