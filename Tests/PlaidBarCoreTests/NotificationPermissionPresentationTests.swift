import Foundation
import Testing
@testable import PlaidBarCore

@Suite("Notification permission presentation")
struct NotificationPermissionPresentationTests {
    @Test("Authorized is positive with notifications enabled and no recovery")
    func authorized() {
        let presentation = NotificationPermissionPresentation.evaluate(kind: .authorized)
        #expect(presentation.label == "Allowed")
        #expect(presentation.tone == .positive)
        #expect(presentation.recoveryAction == nil)
        #expect(presentation.isNotificationToggleDisabled == false)
        #expect(presentation.shouldDisableNotifications == false)
    }

    @Test("Denied warns and routes to System Settings")
    func denied() {
        let presentation = NotificationPermissionPresentation.evaluate(kind: .denied)
        #expect(presentation.tone == .warning)
        #expect(presentation.recoveryAction == .openSystemSettings)
        #expect(presentation.recoveryActionTitle == "Open System Settings")
        #expect(presentation.recoveryActionIconName == "gearshape")
        #expect(presentation.isNotificationToggleDisabled)
        #expect(presentation.shouldDisableNotifications)
    }

    @Test("Not-determined offers a permission request and keeps the toggle live")
    func notDetermined() {
        let presentation = NotificationPermissionPresentation.evaluate(kind: .notDetermined)
        #expect(presentation.recoveryAction == .requestPermission)
        #expect(presentation.recoveryActionTitle == "Request Permission")
        #expect(presentation.recoveryActionIconName == "bell.badge")
        #expect(presentation.isNotificationToggleDisabled == false)
        // Still gated until the user actually grants permission.
        #expect(presentation.shouldDisableNotifications)
    }

    @Test("Unsupported launch points at the app bundle and is non-interactive")
    func unsupported() {
        let presentation = NotificationPermissionPresentation.evaluate(kind: .unsupported)
        #expect(presentation.tone == .secondary)
        #expect(presentation.recoveryAction == .runBundledApp)
        #expect(presentation.recoveryActionTitle == "Run App Bundle")
        #expect(presentation.recoveryActionIconName == "app.badge")
        #expect(presentation.isRecoveryActionInteractive == false)
        #expect(presentation.isNotificationToggleDisabled)
    }

    @Test("Unknown asks the user to check again")
    func unknown() {
        let presentation = NotificationPermissionPresentation.evaluate(kind: .unknown)
        #expect(presentation.recoveryAction == .checkAgain)
        #expect(presentation.recoveryActionTitle == "Check Again")
        #expect(presentation.recoveryActionIconName == "arrow.clockwise")
    }

    @Test("Provisional and ephemeral are positive with no recovery needed")
    func provisionalAndEphemeral() {
        for kind in [NotificationPermissionKind.provisional, .ephemeral] {
            let presentation = NotificationPermissionPresentation.evaluate(kind: kind)
            #expect(presentation.tone == .positive)
            #expect(presentation.recoveryAction == nil)
            #expect(presentation.shouldDisableNotifications == false)
        }
    }

    @Test("Explicit recovery title and icon override the action defaults")
    func explicitOverrides() {
        let presentation = NotificationPermissionPresentation(
            label: "Custom",
            detail: "Detail",
            iconName: "icon",
            tone: .secondary,
            recoveryAction: .checkAgain,
            recoveryActionTitle: "Custom Title",
            recoveryActionIconName: "custom.icon",
            isNotificationToggleDisabled: false,
            shouldDisableNotifications: false
        )
        #expect(presentation.recoveryActionTitle == "Custom Title")
        #expect(presentation.recoveryActionIconName == "custom.icon")
    }

    @Test("No recovery action means no derived title or icon")
    func noRecoveryNoTitle() {
        let presentation = NotificationPermissionPresentation.evaluate(kind: .authorized)
        #expect(presentation.recoveryActionTitle == nil)
        #expect(presentation.recoveryActionIconName == nil)
    }
}
