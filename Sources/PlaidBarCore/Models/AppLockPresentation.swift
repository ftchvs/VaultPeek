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
        switch self {
        case .detailed:
            return "Show merchant, account, and amount details when VaultPeek is not private."
        case .genericWhenPrivate:
            return "Hide notification details whenever Privacy Mask or App Lock is active."
        case .alwaysGeneric:
            return "Never show financial details in notifications."
        case .offWhileLocked:
            return "Suppress financial alerts until VaultPeek is unlocked."
        }
    }

    public func shouldSend(isLocked: Bool) -> Bool {
        !(self == .offWhileLocked && isLocked)
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
}
