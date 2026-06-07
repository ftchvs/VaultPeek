import Foundation

public enum NotificationPermissionKind: String, Sendable {
    case unsupported
    case authorized
    case denied
    case notDetermined
    case provisional
    case ephemeral
    case unknown
}

public enum NotificationPermissionTone: String, Sendable {
    case positive
    case warning
    case secondary
}

public enum NotificationPermissionRecoveryAction: String, Sendable {
    case requestPermission
    case openSystemSettings
    case runBundledApp
    case checkAgain
}

public struct NotificationPermissionPresentation: Equatable, Sendable {
    public let label: String
    public let detail: String
    public let iconName: String
    public let tone: NotificationPermissionTone
    public let recoveryAction: NotificationPermissionRecoveryAction?
    public let recoveryActionTitle: String?
    public let recoveryActionIconName: String?
    public let isRecoveryActionInteractive: Bool
    public let isNotificationToggleDisabled: Bool
    public let shouldDisableNotifications: Bool

    public init(
        label: String,
        detail: String,
        iconName: String,
        tone: NotificationPermissionTone,
        recoveryAction: NotificationPermissionRecoveryAction? = nil,
        recoveryActionTitle: String? = nil,
        recoveryActionIconName: String? = nil,
        isRecoveryActionInteractive: Bool = true,
        isNotificationToggleDisabled: Bool,
        shouldDisableNotifications: Bool
    ) {
        self.label = label
        self.detail = detail
        self.iconName = iconName
        self.tone = tone
        self.recoveryAction = recoveryAction
        self.recoveryActionTitle = recoveryActionTitle ?? recoveryAction?.defaultTitle
        self.recoveryActionIconName = recoveryActionIconName ?? recoveryAction?.defaultIconName
        self.isRecoveryActionInteractive = isRecoveryActionInteractive
        self.isNotificationToggleDisabled = isNotificationToggleDisabled
        self.shouldDisableNotifications = shouldDisableNotifications
    }

    public static func evaluate(kind: NotificationPermissionKind) -> NotificationPermissionPresentation {
        switch kind {
        case .unsupported:
            return NotificationPermissionPresentation(
                label: "Unavailable",
                detail: "This PlaidBar launch does not have a macOS notification identity. Run PlaidBar from the app bundle so macOS can register it as a notification source.",
                iconName: "bell.slash.fill",
                tone: .secondary,
                recoveryAction: .runBundledApp,
                isRecoveryActionInteractive: false,
                isNotificationToggleDisabled: true,
                shouldDisableNotifications: true
            )
        case .authorized:
            return NotificationPermissionPresentation(
                label: "Allowed",
                detail: "PlaidBar can show local transaction, balance, and credit utilization alerts.",
                iconName: "checkmark.circle.fill",
                tone: .positive,
                isNotificationToggleDisabled: false,
                shouldDisableNotifications: false
            )
        case .denied:
            return NotificationPermissionPresentation(
                label: "Denied",
                detail: "macOS is blocking PlaidBar notifications. Enable PlaidBar in System Settings to recover local alerts.",
                iconName: "exclamationmark.triangle.fill",
                tone: .warning,
                recoveryAction: .openSystemSettings,
                isNotificationToggleDisabled: true,
                shouldDisableNotifications: true
            )
        case .notDetermined:
            return NotificationPermissionPresentation(
                label: "Not requested",
                detail: "Request macOS permission before enabling local transaction, balance, and credit alerts.",
                iconName: "questionmark.circle",
                tone: .secondary,
                recoveryAction: .requestPermission,
                isNotificationToggleDisabled: false,
                shouldDisableNotifications: true
            )
        case .provisional:
            return NotificationPermissionPresentation(
                label: "Provisional",
                detail: "macOS may deliver alerts quietly until permission is fully allowed.",
                iconName: "checkmark.circle.fill",
                tone: .positive,
                isNotificationToggleDisabled: false,
                shouldDisableNotifications: false
            )
        case .ephemeral:
            return NotificationPermissionPresentation(
                label: "Temporary",
                detail: "macOS granted a temporary notification permission.",
                iconName: "checkmark.circle.fill",
                tone: .positive,
                isNotificationToggleDisabled: false,
                shouldDisableNotifications: false
            )
        case .unknown:
            return NotificationPermissionPresentation(
                label: "Unknown",
                detail: "PlaidBar could not classify the current notification permission. Check again before relying on local alerts.",
                iconName: "questionmark.circle",
                tone: .secondary,
                recoveryAction: .checkAgain,
                isNotificationToggleDisabled: false,
                shouldDisableNotifications: true
            )
        }
    }
}

private extension NotificationPermissionRecoveryAction {
    var defaultTitle: String {
        switch self {
        case .requestPermission: "Request Permission"
        case .openSystemSettings: "Open System Settings"
        case .runBundledApp: "Run App Bundle"
        case .checkAgain: "Check Again"
        }
    }

    var defaultIconName: String {
        switch self {
        case .requestPermission: "bell.badge"
        case .openSystemSettings: "gearshape"
        case .runBundledApp: "app.badge"
        case .checkAgain: "arrow.clockwise"
        }
    }
}
