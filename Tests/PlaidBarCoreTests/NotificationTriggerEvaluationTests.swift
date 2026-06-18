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
            recurringTransactions: [
                recurring(id: "Changed Stream", latestAmount: 16, trailingAverageAmount: 10, nextExpectedDate: "2026-06-16"),
                recurring(id: "Detected Stream", latestAmount: 20, trailingAverageAmount: 20, nextExpectedDate: "2026-07-16"),
            ],
            itemStatuses: [
                ItemStatus(id: "item-login", institutionName: "Example Bank", status: .loginRequired),
                ItemStatus(id: "item-error", institutionName: "City Credit", status: .error),
                ItemStatus(id: "item-ok", institutionName: "Healthy Bank", status: .connected),
            ],
            isSyncStale: true,
            now: fixedNow,
            config: testConfig
        )

        let kinds = evaluation.decisions.map(\NotificationTriggerDecision.kind)
        #expect(kinds == [
            NotificationTriggerKind.itemError,
            NotificationTriggerKind.loginRequired,
            NotificationTriggerKind.syncStale,
            NotificationTriggerKind.highUtilization,
            NotificationTriggerKind.lowBalance,
            NotificationTriggerKind.recurringChargeChanged,
            NotificationTriggerKind.recurringChargeDueSoon,
            NotificationTriggerKind.recurringChargeDetected,
            NotificationTriggerKind.recurringChargeDetected,
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
            NotificationTriggerSeverity.warning,
            NotificationTriggerSeverity.informational,
            NotificationTriggerSeverity.informational,
            NotificationTriggerSeverity.informational,
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
            recurringTransactions: [
                recurring(id: "Changed Stream", latestAmount: 16, trailingAverageAmount: 10, nextExpectedDate: "2026-06-16"),
                recurring(id: "Detected Stream", latestAmount: 20, trailingAverageAmount: 20, nextExpectedDate: "2026-07-16"),
            ],
            itemStatuses: [
                ItemStatus(id: "item-login", status: .loginRequired),
                ItemStatus(id: "item-error", status: .error),
            ],
            isSyncStale: true,
            now: fixedNow,
            config: testConfig
        )
        let deliveredKeys = active.activeDedupKeys

        let repeated = NotificationTriggerSelection.evaluate(
            transactions: [transaction(id: "tx-large", amount: 650)],
            accounts: [
                depository(id: "acct-low", balance: 50),
                credit(id: "acct-high-util", current: -4_500, limit: 5_000),
            ],
            recurringTransactions: [
                recurring(id: "Changed Stream", latestAmount: 16, trailingAverageAmount: 10, nextExpectedDate: "2026-06-16"),
                recurring(id: "Detected Stream", latestAmount: 20, trailingAverageAmount: 20, nextExpectedDate: "2026-07-16"),
            ],
            itemStatuses: [
                ItemStatus(id: "item-login", status: .loginRequired),
                ItemStatus(id: "item-error", status: .error),
            ],
            isSyncStale: true,
            now: fixedNow,
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
            recurringTransactions: [
                recurring(id: "Detected Stream", latestAmount: 20, trailingAverageAmount: 20, nextExpectedDate: "2026-07-16"),
            ],
            itemStatuses: [
                ItemStatus(id: "item-login", status: .connected),
                ItemStatus(id: "item-error", status: .connected),
            ],
            isSyncStale: false,
            now: fixedNow,
            config: testConfig,
            deliveredDedupKeys: deliveredKeys
        )

        let stickyLargeTransactionKey = NotificationTriggerSelection.dedupKey(
            kind: .largeTransaction,
            sourceID: "tx-large"
        )
        let stickyDetectedKey = NotificationTriggerSelection.dedupKey(
            kind: .recurringChargeDetected,
            sourceID: recurring(id: "Detected Stream").id
        )
        let stickyChangedStreamDetectedKey = NotificationTriggerSelection.dedupKey(
            kind: .recurringChargeDetected,
            sourceID: recurring(id: "Changed Stream").id
        )

        #expect(resolved.decisions.isEmpty)
        #expect(resolved.activeDedupKeys == [stickyDetectedKey])
        #expect(
            resolved.resolvedDedupKeys == deliveredKeys.subtracting([
                stickyLargeTransactionKey,
                stickyDetectedKey,
                stickyChangedStreamDetectedKey,
            ])
        )
        #expect(resolved.resolvedDedupKeys.contains(stickyLargeTransactionKey) == false)
        #expect(resolved.resolvedDedupKeys.contains(stickyDetectedKey) == false)
        #expect(resolved.resolvedDedupKeys.contains(stickyChangedStreamDetectedKey) == false)
    }

    @Test("A second price increase on the same stream notifies after the first was delivered")
    func secondPriceIncreaseNotifiesAfterFirstDelivered() {
        let firstChange = NotificationTriggerSelection.evaluate(
            recurringTransactions: [
                recurring(id: "Stream", latestAmount: 15, trailingAverageAmount: 10, nextExpectedDate: "2026-07-16"),
            ],
            now: fixedNow,
            config: testConfig
        )
        let delivered = firstChange.activeDedupKeys
        #expect(firstChange.decisions.contains { $0.kind == .recurringChargeChanged })

        // Same stream id, higher latest amount: the second increase must not be
        // suppressed by the first change alert's delivered key.
        let secondChange = NotificationTriggerSelection.evaluate(
            recurringTransactions: [
                recurring(id: "Stream", latestAmount: 20, trailingAverageAmount: 10, nextExpectedDate: "2026-07-16"),
            ],
            now: fixedNow,
            config: testConfig,
            deliveredDedupKeys: delivered
        )
        #expect(secondChange.decisions.contains { $0.kind == .recurringChargeChanged })
    }

    @Test("A new due-soon cycle notifies even after the prior cycle was delivered")
    func dueSoonNotifiesPerCycle() {
        let june = NotificationTriggerSelection.evaluate(
            recurringTransactions: [
                recurring(id: "Stream", latestAmount: 20, trailingAverageAmount: 20, nextExpectedDate: "2026-06-16"),
            ],
            now: fixedNow,
            config: testConfig
        )
        let delivered = june.activeDedupKeys
        #expect(june.decisions.contains { $0.kind == .recurringChargeDueSoon })

        // Next cycle's due date, evaluated when it enters the window, must not be
        // suppressed by the previous cycle's delivered due-soon key.
        let july = NotificationTriggerSelection.evaluate(
            recurringTransactions: [
                recurring(id: "Stream", latestAmount: 20, trailingAverageAmount: 20, nextExpectedDate: "2026-07-16"),
            ],
            now: Formatters.parseTransactionDate("2026-07-14")!,
            config: testConfig,
            deliveredDedupKeys: delivered
        )
        #expect(july.decisions.contains { $0.kind == .recurringChargeDueSoon })
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
            recurringTransactions: [
                recurring(
                    id: "Sensitive Subscription",
                    latestAmount: 22.22,
                    trailingAverageAmount: 10,
                    nextExpectedDate: "2026-06-16"
                ),
            ],
            itemStatuses: [
                ItemStatus(id: rawItemID, institutionName: institutionName, status: .error),
            ],
            watchlistTargets: [
                // A watchlist nudge whose label/key is the sensitive merchant —
                // its lock-screen copy must still avoid that name and the amount.
                WatchlistTarget.merchant(merchantName, threshold: 10),
            ],
            isSyncStale: true,
            now: fixedNow,
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
            "Sensitive Subscription",
            "9876.54",
            "12.34",
            "22.22",
        ] {
            #expect(renderedCopy.contains(privateText) == false)
        }

        #expect(evaluation.decisions.allSatisfy { !$0.body.contains("$") })
    }

    @Test("Disabled trigger families suppress their decisions")
    func disabledTriggerFamiliesSuppressDecisions() {
        let evaluation = NotificationTriggerSelection.evaluate(
            transactions: [transaction(id: "tx-large", amount: 650)],
            accounts: [
                depository(id: "acct-low", balance: 50),
                credit(id: "acct-high-util", current: -4_500, limit: 5_000),
            ],
            recurringTransactions: [
                recurring(id: "Changed Stream", latestAmount: 16, trailingAverageAmount: 10, nextExpectedDate: "2026-06-16"),
            ],
            itemStatuses: [
                ItemStatus(id: "item-login", status: .loginRequired),
                ItemStatus(id: "item-error", status: .error),
            ],
            isSyncStale: true,
            now: fixedNow,
            config: NotificationTriggers(
                largeTransaction: false,
                lowBalance: false,
                highUtilization: false,
                recurringChargeDetected: false,
                recurringChargeChanged: false,
                recurringChargeDueSoon: false,
                staleSync: false,
                loginRequired: false,
                itemError: false,
                largeTransactionThreshold: 500,
                lowBalanceThreshold: 100,
                creditUtilizationThreshold: 30
            )
        )

        #expect(evaluation.decisions.isEmpty)
        #expect(evaluation.activeDedupKeys.isEmpty)
        #expect(evaluation.resolvedDedupKeys.isEmpty)
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

    private var fixedNow: Date {
        Formatters.parseTransactionDate("2026-06-14")!
    }

    private func recurring(
        id merchantName: String,
        latestAmount: Double = 20,
        trailingAverageAmount: Double? = 20,
        nextExpectedDate: String = "2026-07-16"
    ) -> RecurringTransaction {
        RecurringTransaction(
            merchantName: merchantName,
            frequency: .monthly,
            averageAmount: trailingAverageAmount ?? latestAmount,
            latestAmount: latestAmount,
            trailingAverageAmount: trailingAverageAmount,
            lastDate: "2026-05-16",
            nextExpectedDate: nextExpectedDate,
            category: nil,
            transactionCount: 3,
            confidence: 0.9
        )
    }
}
