import Foundation
import UserNotifications
import PlaidBarCore

@MainActor
final class NotificationService {
    static let shared = NotificationService()

    private static let notifiedTxKey = "notifiedTransactionIds"
    private static let notifiedAccountKey = "notifiedAccountIds"

    /// Ordered array for LRU cap (most recent at end)
    private var notifiedTransactionIds: [String]
    private var notifiedTransactionIdSet: Set<String>
    private var notifiedAccountIds: Set<String>

    private init() {
        let defaults = UserDefaults.standard
        let txIds = defaults.stringArray(forKey: Self.notifiedTxKey) ?? []
        notifiedTransactionIds = txIds
        notifiedTransactionIdSet = Set(txIds)
        notifiedAccountIds = Set(defaults.stringArray(forKey: Self.notifiedAccountKey) ?? [])
    }

    private func persistNotifiedIds() {
        let defaults = UserDefaults.standard
        defaults.set(notifiedTransactionIds, forKey: Self.notifiedTxKey)
        defaults.set(Array(notifiedAccountIds), forKey: Self.notifiedAccountKey)
    }

    // MARK: - Notification Key Helpers

    private enum NotifKey {
        static func largeTx(_ id: String) -> String { "large-tx-\(id)" }
        static func lowBalance(_ id: String) -> String { "low-balance-\(id)" }
        static func highUtil(_ id: String) -> String { "high-util-\(id)" }
        static func dedupLow(_ id: String) -> String { "low-\(id)" }
        static func dedupUtil(_ id: String) -> String { "util-\(id)" }
    }

    // MARK: - Permissions

    func requestPermission() async -> Bool {
        do {
            return try await UNUserNotificationCenter.current()
                .requestAuthorization(options: [.alert, .sound])
        } catch {
            return false
        }
    }

    func checkPermissionStatus() async -> UNAuthorizationStatus {
        let settings = await UNUserNotificationCenter.current().notificationSettings()
        return settings.authorizationStatus
    }

    // MARK: - Triggers

    func evaluateTriggers(
        transactions: [TransactionDTO],
        accounts: [AccountDTO],
        config: NotificationTriggers
    ) async {
        if config.largeTransaction {
            await checkLargeTransactions(transactions: transactions, threshold: config.largeTransactionThreshold)
        }
        if config.lowBalance {
            await checkLowBalance(accounts: accounts, threshold: config.lowBalanceThreshold)
        }
        if config.highUtilization {
            await checkHighUtilization(accounts: accounts, threshold: config.creditUtilizationThreshold)
        }
        persistNotifiedIds()
    }

    private func checkLargeTransactions(transactions: [TransactionDTO], threshold: Double) async {
        let large = transactions.filter {
            !$0.isIncome && $0.displayAmount >= threshold && !notifiedTransactionIdSet.contains($0.id)
        }

        for tx in large {
            notifiedTransactionIds.append(tx.id)
            notifiedTransactionIdSet.insert(tx.id)
            await sendNotification(
                title: "Large Transaction",
                body: "\(tx.displayName): \(Formatters.currency(tx.displayAmount, format: .full))",
                identifier: NotifKey.largeTx(tx.id)
            )
        }

        // LRU cap: drop oldest entries first
        if notifiedTransactionIds.count > 500 {
            let excess = notifiedTransactionIds.count - 500
            let removed = notifiedTransactionIds.prefix(excess)
            notifiedTransactionIds.removeFirst(excess)
            for id in removed { notifiedTransactionIdSet.remove(id) }
        }
    }

    private func checkLowBalance(accounts: [AccountDTO], threshold: Double) async {
        let lowAccounts = accounts.filter {
            $0.type == .depository && $0.balances.effectiveBalance < threshold
        }

        clearResolvedDedup(
            activeIds: Set(lowAccounts.map(\.id)),
            allIds: Set(accounts.filter { $0.type == .depository }.map(\.id)),
            keyPrefix: NotifKey.dedupLow
        )

        for account in lowAccounts {
            let key = NotifKey.dedupLow(account.id)
            guard !notifiedAccountIds.contains(key) else { continue }
            notifiedAccountIds.insert(key)
            await sendNotification(
                title: "Low Balance",
                body: "\(account.name): \(Formatters.currency(account.balances.effectiveBalance, format: .full))",
                identifier: NotifKey.lowBalance(account.id)
            )
        }
    }

    private func checkHighUtilization(accounts: [AccountDTO], threshold: Double) async {
        let highUtil = accounts.filter {
            $0.type == .credit && ($0.balances.utilizationPercent ?? 0) > threshold
        }

        clearResolvedDedup(
            activeIds: Set(highUtil.map(\.id)),
            allIds: Set(accounts.filter { $0.type == .credit }.map(\.id)),
            keyPrefix: NotifKey.dedupUtil
        )

        for account in highUtil {
            let key = NotifKey.dedupUtil(account.id)
            guard !notifiedAccountIds.contains(key) else { continue }
            notifiedAccountIds.insert(key)
            let util = account.balances.utilizationPercent ?? 0
            await sendNotification(
                title: "High Credit Utilization",
                body: "\(account.name): \(Formatters.percent(util)) used",
                identifier: NotifKey.highUtil(account.id)
            )
        }
    }

    /// Remove dedup entries for accounts whose condition resolved
    private func clearResolvedDedup(activeIds: Set<String>, allIds: Set<String>, keyPrefix: (String) -> String) {
        for id in allIds where !activeIds.contains(id) {
            notifiedAccountIds.remove(keyPrefix(id))
        }
    }

    private func sendNotification(title: String, body: String, identifier: String) async {
        let content = UNMutableNotificationContent()
        content.title = title
        content.body = body
        content.sound = .default

        let request = UNNotificationRequest(identifier: identifier, content: content, trigger: nil)
        try? await UNUserNotificationCenter.current().add(request)
    }
}

struct NotificationTriggers: Sendable {
    var largeTransaction: Bool = true
    var lowBalance: Bool = true
    var highUtilization: Bool = true
    var largeTransactionThreshold: Double = 500
    var lowBalanceThreshold: Double = 100
    var creditUtilizationThreshold: Double = 30
}
