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
        recurringTransactions: [RecurringTransaction],
        itemStatuses: [ItemStatus],
        watchlistTargets: [WatchlistTarget],
        isSyncStale: Bool,
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

    private static let deliveredDedupKeysKey = "deliveredNotificationDedupKeys"
    private static let legacyNotifiedTxKey = "notifiedTransactionIds"
    private static let legacyNotifiedAccountKey = "notifiedAccountIds"
    private static var hasNotificationIdentity: Bool {
        guard let identifier = Bundle.main.bundleIdentifier ??
            (Bundle.main.object(forInfoDictionaryKey: "CFBundleIdentifier") as? String)
        else {
            return false
        }

        return !identifier.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    /// Ordered array for LRU cap (most recent at end).
    private var deliveredDedupKeys: [String]
    private var deliveredDedupKeySet: Set<String>

    private init() {
        let defaults = UserDefaults.standard
        let keys = defaults.stringArray(forKey: Self.deliveredDedupKeysKey)
            ?? Self.migratedLegacyDedupKeys(from: defaults)
        deliveredDedupKeys = keys
        deliveredDedupKeySet = Set(keys)
    }

    private func persistNotifiedIds() {
        let defaults = UserDefaults.standard
        defaults.set(deliveredDedupKeys, forKey: Self.deliveredDedupKeysKey)
    }

    func resetDeduplicationState() {
        deliveredDedupKeys = []
        deliveredDedupKeySet = []

        let defaults = UserDefaults.standard
        defaults.removeObject(forKey: Self.deliveredDedupKeysKey)
        defaults.removeObject(forKey: Self.legacyNotifiedTxKey)
        defaults.removeObject(forKey: Self.legacyNotifiedAccountKey)
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
        recurringTransactions: [RecurringTransaction],
        itemStatuses: [ItemStatus],
        watchlistTargets: [WatchlistTarget] = [],
        isSyncStale: Bool,
        config: NotificationTriggers
    ) async {
        let evaluation = NotificationTriggerSelection.evaluate(
            transactions: transactions,
            accounts: accounts,
            recurringTransactions: recurringTransactions,
            itemStatuses: itemStatuses,
            watchlistTargets: watchlistTargets,
            isSyncStale: isSyncStale,
            config: config,
            deliveredDedupKeys: deliveredDedupKeySet
        )

        for resolvedKey in evaluation.resolvedDedupKeys {
            deliveredDedupKeySet.remove(resolvedKey)
            deliveredDedupKeys.removeAll { $0 == resolvedKey }
        }

        for decision in evaluation.decisions {
            let didSchedule = await sendNotification(
                title: decision.title,
                body: decision.body,
                identifier: decision.dedupKey
            )
            guard didSchedule else { continue }
            deliveredDedupKeys.append(decision.dedupKey)
            deliveredDedupKeySet.insert(decision.dedupKey)
        }

        if deliveredDedupKeys.count > 1_000 {
            let excess = deliveredDedupKeys.count - 1_000
            let removed = deliveredDedupKeys.prefix(excess)
            deliveredDedupKeys.removeFirst(excess)
            for key in removed { deliveredDedupKeySet.remove(key) }
        }

        persistNotifiedIds()
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

    private static func migratedLegacyDedupKeys(from defaults: UserDefaults) -> [String] {
        var keys: [String] = []
        var keySet = Set<String>()

        func append(_ key: String) {
            guard keySet.insert(key).inserted else { return }
            keys.append(key)
        }

        for transactionID in defaults.stringArray(forKey: legacyNotifiedTxKey) ?? [] {
            append(NotificationTriggerSelection.dedupKey(kind: .largeTransaction, sourceID: transactionID))
        }

        for legacyAccountKey in defaults.stringArray(forKey: legacyNotifiedAccountKey) ?? [] {
            if legacyAccountKey.hasPrefix("low-") {
                let accountID = String(legacyAccountKey.dropFirst("low-".count))
                append(NotificationTriggerSelection.dedupKey(kind: .lowBalance, sourceID: accountID))
            } else if legacyAccountKey.hasPrefix("util-") {
                let accountID = String(legacyAccountKey.dropFirst("util-".count))
                append(NotificationTriggerSelection.dedupKey(kind: .highUtilization, sourceID: accountID))
            }
        }

        if !keys.isEmpty {
            defaults.set(keys, forKey: deliveredDedupKeysKey)
        }
        defaults.removeObject(forKey: legacyNotifiedTxKey)
        defaults.removeObject(forKey: legacyNotifiedAccountKey)
        return keys
    }
}
