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

    // The `lockOnLaunch` / `lockWhenBackgrounded` flags are persisted by
    // `AppState` through `UserDefaults` (PlaidBar target, not unit-testable here
    // because PlaidBar is an `@main` executable that cannot be `@testable`
    // imported). `AppLockPreferences` is the round-trippable Core model the
    // persistence reads into and writes out of, so this asserts a non-default
    // value pair survives initialization rather than collapsing to the defaults
    // (the bug was that the persisted value never made it back into the model).
    @Test("non-default lock-on-launch / lock-when-backgrounded survive a model round-trip")
    func lockTriggerFlagsRoundTripThroughModel() {
        let stored = AppLockPreferences(
            lockOnLaunch: true,
            lockWhenBackgrounded: false
        )

        let restored = AppLockPreferences(
            lockOnLaunch: stored.lockOnLaunch,
            lockWhenBackgrounded: stored.lockWhenBackgrounded
        )

        #expect(restored.lockOnLaunch == true)
        #expect(restored.lockWhenBackgrounded == false)
        // Guard against silently inheriting the defaults (false / true).
        #expect(restored.lockOnLaunch != AppLockPreferences().lockOnLaunch)
        #expect(restored.lockWhenBackgrounded != AppLockPreferences().lockWhenBackgrounded)
    }

    @Test("suppress-while-locked toggle maps to canonical modes and reads honestly")
    func suppressWhileLockedTogglesCanonicalModes() {
        // Only `.offWhileLocked` suppresses; the three generic-equivalent modes
        // all read as "off" because they deliver identical (always-generic) copy.
        #expect(NotificationPrivacyMode.offWhileLocked.suppressesNotificationsWhileLocked == true)
        #expect(NotificationPrivacyMode.detailed.suppressesNotificationsWhileLocked == false)
        #expect(NotificationPrivacyMode.genericWhenPrivate.suppressesNotificationsWhileLocked == false)
        #expect(NotificationPrivacyMode.alwaysGeneric.suppressesNotificationsWhileLocked == false)

        var mode = NotificationPrivacyMode.alwaysGeneric
        mode.suppressesNotificationsWhileLocked = true
        #expect(mode == .offWhileLocked)
        mode.suppressesNotificationsWhileLocked = false
        #expect(mode == .alwaysGeneric)
    }

    @Test("unlock outcomes map to the locked-surface message (nil on success)")
    func unlockOutcomesMapToSurfaceMessage() {
        #expect(AppLockAuthenticationMessage(unlockResult: .success) == nil)
        #expect(AppLockAuthenticationMessage(unlockResult: .cancelled) == .canceled)
        #expect(AppLockAuthenticationMessage(unlockResult: .failure(.authenticationFailed)) == .failed)
        #expect(AppLockAuthenticationMessage(unlockResult: .unavailable(.biometryLockout)) == .lockout)
        #expect(AppLockAuthenticationMessage(unlockResult: .unavailable(.passcodeNotSet)) == .unavailable)
    }

    @Test("locked display mode is distinct from masked so content can be gated")
    func lockedDisplayModeIsDistinctFromMasked() {
        // FIX 3 contract: a full lock must be distinguishable from Privacy Mask
        // at the policy layer so the UI can gate content (hide account/
        // institution names), not merely dot currency.
        let locked = AppLockPreferences(privacyMaskEnabled: true, appLockEnabled: true)
        #expect(locked.effectiveDisplayMode(isAppLocked: true) == .locked)

        let masked = AppLockPreferences(privacyMaskEnabled: true, appLockEnabled: false)
        #expect(masked.effectiveDisplayMode(isAppLocked: false) == .masked)

        // The idle surface copy exists for the no-attempt-yet gate state.
        #expect(!AppLockAuthenticationMessage.idleSurfaceCopy.isEmpty)
    }

    @Test("inactivity intervals normalize to supported options")
    func inactivityIntervalsNormalize() {
        #expect(AppLockPreferences.normalizedInactivityInterval(75) == 60)
        #expect(AppLockPreferences.normalizedInactivityInterval(301) == 300)
        #expect(AppLockPreferences.normalizedInactivityInterval(1_600) == 1_800)
    }
}
