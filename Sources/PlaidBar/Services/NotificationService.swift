import Foundation
@preconcurrency import UserNotifications
import PlaidBarCore

@MainActor
protocol NotificationServiceProtocol {
    func requestPermission() async -> Bool
    func checkPermissionStatus() async -> NotificationPermissionState
    func resetDeduplicationState()
    func evaluateTriggers(
        transactions: [TransactionDTO],
        accounts: [AccountDTO],
        config: NotificationTriggers
    ) async
}

enum NotificationPermissionState {
    case unsupported
    case status(UNAuthorizationStatus)

    static let notDetermined: NotificationPermissionState = .status(.notDetermined)

    var presentationKind: NotificationPermissionKind {
        switch self {
        case .unsupported:
            return .unsupported
        case .status(let status):
            switch status {
            case .authorized:
                return .authorized
            case .denied:
                return .denied
            case .notDetermined:
                return .notDetermined
            case .provisional:
                return .provisional
            case .ephemeral:
                return .ephemeral
            @unknown default:
                return .unknown
            }
        }
    }

    var shouldDisableNotifications: Bool {
        NotificationPermissionPresentation.evaluate(kind: presentationKind).shouldDisableNotifications
    }
}

@MainActor
final class NotificationService: NotificationServiceProtocol {
    static let shared = NotificationService()

    private static let notifiedTxKey = "notifiedTransactionIds"
    private static let notifiedAccountKey = "notifiedAccountIds"
    private static var hasNotificationIdentity: Bool {
        guard let identifier = Bundle.main.bundleIdentifier ??
            (Bundle.main.object(forInfoDictionaryKey: "CFBundleIdentifier") as? String)
        else {
            return false
        }

        return !identifier.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

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

    func resetDeduplicationState() {
        notifiedTransactionIds = []
        notifiedTransactionIdSet = []
        notifiedAccountIds = []

        let defaults = UserDefaults.standard
        defaults.removeObject(forKey: Self.notifiedTxKey)
        defaults.removeObject(forKey: Self.notifiedAccountKey)
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
        guard Self.hasNotificationIdentity else { return false }

        do {
            return try await UNUserNotificationCenter.current()
                .requestAuthorization(options: [.alert, .sound])
        } catch {
            return false
        }
    }

    func checkPermissionStatus() async -> NotificationPermissionState {
        guard Self.hasNotificationIdentity else { return .unsupported }

        let settings = await UNUserNotificationCenter.current().notificationSettings()
        return .status(settings.authorizationStatus)
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
        let large = NotificationTriggerSelection.largeTransactions(
            from: transactions,
            threshold: threshold,
            excluding: notifiedTransactionIdSet
        )

        for tx in large {
            let didSchedule = await sendNotification(
                title: "Large Transaction",
                body: "A transaction crossed your configured review threshold. Open VaultPeek to review it privately.",
                identifier: NotifKey.largeTx(tx.id)
            )
            guard didSchedule else { continue }
            notifiedTransactionIds.append(tx.id)
            notifiedTransactionIdSet.insert(tx.id)
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
        let lowAccounts = NotificationTriggerSelection.lowBalanceAccounts(
            from: accounts,
            threshold: threshold
        )

        clearResolvedDedup(
            activeIds: Set(lowAccounts.map(\.id)),
            allIds: Set(accounts.filter { $0.type == .depository }.map(\.id)),
            keyPrefix: NotifKey.dedupLow
        )

        for account in lowAccounts {
            let key = NotifKey.dedupLow(account.id)
            guard !notifiedAccountIds.contains(key) else { continue }
            let didSchedule = await sendNotification(
                title: "Low Balance",
                body: "A depository account is below your configured threshold. Open VaultPeek to review it privately.",
                identifier: NotifKey.lowBalance(account.id)
            )
            if didSchedule {
                notifiedAccountIds.insert(key)
            }
        }
    }

    private func checkHighUtilization(accounts: [AccountDTO], threshold: Double) async {
        let highUtil = NotificationTriggerSelection.highUtilizationAccounts(
            from: accounts,
            threshold: threshold
        )

        clearResolvedDedup(
            activeIds: Set(highUtil.map(\.id)),
            allIds: Set(accounts.filter { $0.type == .credit }.map(\.id)),
            keyPrefix: NotifKey.dedupUtil
        )

        for account in highUtil {
            let key = NotifKey.dedupUtil(account.id)
            guard !notifiedAccountIds.contains(key) else { continue }
            let didSchedule = await sendNotification(
                title: "High Credit Utilization",
                body: "A credit account is above your configured utilization threshold. Open VaultPeek to review it privately.",
                identifier: NotifKey.highUtil(account.id)
            )
            if didSchedule {
                notifiedAccountIds.insert(key)
            }
        }
    }

    /// Remove dedup entries for accounts whose condition resolved
    private func clearResolvedDedup(activeIds: Set<String>, allIds: Set<String>, keyPrefix: (String) -> String) {
        for id in allIds where !activeIds.contains(id) {
            notifiedAccountIds.remove(keyPrefix(id))
        }
    }

    private func sendNotification(title: String, body: String, identifier: String) async -> Bool {
        guard Self.hasNotificationIdentity else { return false }

        let content = UNMutableNotificationContent()
        content.title = title
        content.body = body
        content.sound = .default

        let request = UNNotificationRequest(identifier: identifier, content: content, trigger: nil)
        do {
            try await UNUserNotificationCenter.current().add(request)
            return true
        } catch {
            return false
        }
    }
}
