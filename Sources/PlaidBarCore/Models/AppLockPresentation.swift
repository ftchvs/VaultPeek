import Foundation

public enum PrivacyDisplayMode: Sendable, Equatable {
    case normal
    case masked
    case locked
}

public enum NotificationPrivacyMode: String, CaseIterable, Sendable, Equatable {
    case detailed
    case genericWhenPrivate
    case alwaysGeneric
    case offWhileLocked

    public var displayName: String {
        switch self {
        case .detailed: return "Detailed"
        case .genericWhenPrivate: return "Generic when private"
        case .alwaysGeneric: return "Always generic"
        case .offWhileLocked: return "Off while locked"
        }
    }

    public var detail: String {
        // VaultPeek's notification bodies are always generic — they never include
        // a merchant, account, or amount (see NotificationTriggerSelection). So the
        // only behavior that actually differs between modes is whether financial
        // alerts are suppressed while App Lock is engaged (`.offWhileLocked`). These
        // descriptions state what each mode really does rather than promising
        // detailed copy the app does not produce.
        switch self {
        case .detailed, .genericWhenPrivate, .alwaysGeneric:
            return "Financial notifications never include merchant, account, or amount details; alerts still arrive while VaultPeek is locked."
        case .offWhileLocked:
            return "Financial notifications stay generic and are also suppressed entirely while VaultPeek is locked, then resume once you unlock."
        }
    }

    public func shouldSend(isLocked: Bool) -> Bool {
        !(self == .offWhileLocked && isLocked)
    }

    /// The single behavior that actually differs between modes: whether financial
    /// notifications are suppressed entirely while App Lock is engaged. All other
    /// modes deliver the same always-generic copy, so this is the only meaningful
    /// user-facing choice. Reading it collapses the three generic-equivalent cases
    /// to `false`; writing it picks the canonical case for each side, while every
    /// persisted raw value stays decodable.
    public var suppressesNotificationsWhileLocked: Bool {
        get { self == .offWhileLocked }
        set { self = newValue ? .offWhileLocked : .alwaysGeneric }
    }

    public func usesGenericCopy(isPrivate: Bool) -> Bool {
        guard !isPrivate else { return true }

        switch self {
        case .detailed, .offWhileLocked:
            return false
        case .genericWhenPrivate:
            return isPrivate
        case .alwaysGeneric:
            return true
        }
    }
}

public struct AppLockPreferences: Sendable, Equatable {
    public static let defaultInactivityInterval: TimeInterval = 300
    public static let allowedInactivityIntervals: [TimeInterval] = [60, 300, 900, 1_800]

    public var privacyMaskEnabled: Bool
    public var appLockEnabled: Bool
    public var lockOnLaunch: Bool
    public var lockAfterInactivityEnabled: Bool
    public var lockAfterInactivityInterval: TimeInterval
    public var lockWhenBackgrounded: Bool
    public var notificationPrivacyMode: NotificationPrivacyMode
    public var pauseRefreshWhileLocked: Bool

    public init(
        privacyMaskEnabled: Bool = false,
        appLockEnabled: Bool = false,
        lockOnLaunch: Bool = false,
        lockAfterInactivityEnabled: Bool = true,
        lockAfterInactivityInterval: TimeInterval = Self.defaultInactivityInterval,
        lockWhenBackgrounded: Bool = true,
        notificationPrivacyMode: NotificationPrivacyMode = .genericWhenPrivate,
        pauseRefreshWhileLocked: Bool = false
    ) {
        self.privacyMaskEnabled = privacyMaskEnabled
        self.appLockEnabled = appLockEnabled
        self.lockOnLaunch = lockOnLaunch
        self.lockAfterInactivityEnabled = lockAfterInactivityEnabled
        self.lockAfterInactivityInterval = Self.normalizedInactivityInterval(lockAfterInactivityInterval)
        self.lockWhenBackgrounded = lockWhenBackgrounded
        self.notificationPrivacyMode = notificationPrivacyMode
        self.pauseRefreshWhileLocked = pauseRefreshWhileLocked
    }

    public static func normalizedInactivityInterval(_ interval: TimeInterval) -> TimeInterval {
        guard let nearest = allowedInactivityIntervals.min(by: { abs($0 - interval) < abs($1 - interval) }) else {
            return defaultInactivityInterval
        }
        return nearest
    }

    public func effectiveDisplayMode(isAppLocked: Bool) -> PrivacyDisplayMode {
        if appLockEnabled && isAppLocked { return .locked }
        if privacyMaskEnabled { return .masked }
        return .normal
    }

    public func menuBarText(currentText: String, isAppLocked: Bool, isIconOnly: Bool) -> String {
        guard !isIconOnly else { return "" }
        switch effectiveDisplayMode(isAppLocked: isAppLocked) {
        case .normal:
            return currentText
        case .masked:
            return "Private"
        case .locked:
            return "Locked"
        }
    }

    public var shouldLockOnLaunch: Bool {
        appLockEnabled && lockOnLaunch
    }

    public var shouldLockWhenBackgrounded: Bool {
        appLockEnabled && lockWhenBackgrounded
    }

    public func shouldEvaluateFinancialNotifications(isAppLocked: Bool) -> Bool {
        guard appLockEnabled && isAppLocked else { return true }
        return notificationPrivacyMode != .offWhileLocked
    }

    public func shouldRefreshFinancialData(isAppLocked: Bool) -> Bool {
        !(appLockEnabled && isAppLocked && pauseRefreshWhileLocked)
    }
}

public enum AppLockAuthenticationMessage: Sendable, Equatable {
    case failed
    case canceled
    case unavailable
    case lockout

    /// The default prompt shown on the locked gate before (or between) unlock
    /// attempts — no error has occurred, so it just explains why the dashboard
    /// is hidden and how to reveal it.
    public static let idleSurfaceCopy =
        "VaultPeek is locked. Authenticate to view your balances and activity."

    public var lockedSurfaceCopy: String {
        switch self {
        case .failed:
            return "Could not unlock VaultPeek. Try again or use your Mac password."
        case .canceled:
            return "VaultPeek stayed locked."
        case .unavailable:
            return "Authentication is unavailable right now. VaultPeek will stay locked until macOS authentication is available again."
        case .lockout:
            return "Touch ID is locked. Use your Mac password to unlock VaultPeek."
        }
    }

    /// Maps the outcome of an unlock attempt to the locked-surface message to
    /// show, or `nil` when the attempt succeeded (the gate is dismissed). Kept in
    /// Core so the surface copy selection is unit-testable.
    public init?(unlockResult: AppLockAuthenticationResult) {
        switch unlockResult {
        case .success:
            return nil
        case .cancelled:
            self = .canceled
        case .unavailable(let reason):
            self = reason == .biometryLockout ? .lockout : .unavailable
        case .failure:
            self = .failed
        }
    }
}

public struct ReviewInboxPrivacyPresentation: Sendable, Equatable {
    public let subtitle: String
    public let highPriorityBadge: String?
    public let highPriorityAccessibilityLabel: String?
    public let accessibilityLabel: String

    public static func make(
        totalCount: Int,
        highPriorityCount: Int,
        isPrivate: Bool
    ) -> ReviewInboxPrivacyPresentation {
        if isPrivate {
            return ReviewInboxPrivacyPresentation(
                subtitle: "Items need attention",
                highPriorityBadge: nil,
                highPriorityAccessibilityLabel: nil,
                accessibilityLabel: "Review inbox. Items are hidden while VaultPeek is private."
            )
        }

        let itemSuffix = totalCount == 1 ? "item" : "items"
        let transactionSuffix = totalCount == 1 ? "transaction" : "transactions"
        let highPrioritySuffix = highPriorityCount == 1 ? "item" : "items"
        return ReviewInboxPrivacyPresentation(
            subtitle: "\(totalCount) \(itemSuffix) need attention",
            highPriorityBadge: highPriorityCount > 0 ? "\(highPriorityCount) high priority" : nil,
            highPriorityAccessibilityLabel: highPriorityCount > 0
                ? "\(highPriorityCount) high priority review \(highPrioritySuffix)"
                : nil,
            accessibilityLabel: "Review inbox. \(totalCount) \(transactionSuffix) need attention."
        )
    }
}
