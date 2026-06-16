import Testing
@testable import PlaidBarCore

@Suite("App lock presentation policy")
struct AppLockPresentationTests {
    @Test("defaults match the app lock UX spec")
    func defaultsMatchUXSpec() {
        let preferences = AppLockPreferences()

        #expect(preferences.privacyMaskEnabled == false)
        #expect(preferences.appLockEnabled == false)
        #expect(preferences.lockOnLaunch == false)
        #expect(preferences.lockAfterInactivityEnabled == true)
        #expect(preferences.lockAfterInactivityInterval == 300)
        #expect(preferences.lockWhenBackgrounded == true)
        #expect(preferences.notificationPrivacyMode == .genericWhenPrivate)
        #expect(preferences.pauseRefreshWhileLocked == false)
    }

    @Test("locked wins over privacy mask and hides menu bar values")
    func lockedWinsOverMask() {
        let preferences = AppLockPreferences(privacyMaskEnabled: true, appLockEnabled: true)

        #expect(preferences.effectiveDisplayMode(isAppLocked: true) == .locked)
        #expect(preferences.menuBarText(currentText: "$42,000", isAppLocked: true, isIconOnly: false) == "Locked")
        #expect(preferences.menuBarText(currentText: "$42,000", isAppLocked: true, isIconOnly: true) == "")
    }

    @Test("privacy mask hides values without locking")
    func privacyMaskHidesValuesWithoutLocking() {
        let preferences = AppLockPreferences(privacyMaskEnabled: true, appLockEnabled: false)

        #expect(preferences.effectiveDisplayMode(isAppLocked: false) == .masked)
        #expect(preferences.menuBarText(currentText: "$42,000", isAppLocked: false, isIconOnly: false) == "Private")
    }

    @Test("locked pause settings fail closed for refresh and notifications")
    func lockedPauseSettingsFailClosed() {
        let paused = AppLockPreferences(appLockEnabled: true, notificationPrivacyMode: .offWhileLocked, pauseRefreshWhileLocked: true)
        let generic = AppLockPreferences(appLockEnabled: true, notificationPrivacyMode: .genericWhenPrivate, pauseRefreshWhileLocked: false)

        #expect(paused.shouldRefreshFinancialData(isAppLocked: true) == false)
        #expect(paused.shouldEvaluateFinancialNotifications(isAppLocked: true) == false)
        #expect(generic.shouldRefreshFinancialData(isAppLocked: true) == true)
        #expect(generic.shouldEvaluateFinancialNotifications(isAppLocked: true) == true)
    }

    @Test("notification modes use generic copy whenever the app is private")
    func notificationModesUseGenericCopyWhenPrivate() {
        #expect(NotificationPrivacyMode.detailed.usesGenericCopy(isPrivate: true) == true)
        #expect(NotificationPrivacyMode.offWhileLocked.usesGenericCopy(isPrivate: true) == true)
        #expect(NotificationPrivacyMode.detailed.usesGenericCopy(isPrivate: false) == false)
        #expect(NotificationPrivacyMode.genericWhenPrivate.usesGenericCopy(isPrivate: false) == false)
        #expect(NotificationPrivacyMode.alwaysGeneric.usesGenericCopy(isPrivate: false) == true)
    }

    @Test("inactivity intervals normalize to supported options")
    func inactivityIntervalsNormalize() {
        #expect(AppLockPreferences.normalizedInactivityInterval(75) == 60)
        #expect(AppLockPreferences.normalizedInactivityInterval(301) == 300)
        #expect(AppLockPreferences.normalizedInactivityInterval(1_600) == 1_800)
    }
}
