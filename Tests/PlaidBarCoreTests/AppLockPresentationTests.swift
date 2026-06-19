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

    @Test("normal mode passes the menu-bar text through untouched")
    func normalModePassesTextThrough() {
        let preferences = AppLockPreferences()

        #expect(preferences.effectiveDisplayMode(isAppLocked: false) == .normal)
        #expect(preferences.effectiveDisplayMode(isAppLocked: true) == .normal)
        #expect(preferences.menuBarText(currentText: "$42,000", isAppLocked: false, isIconOnly: false) == "$42,000")
    }

    @Test("private Review Inbox header does not expose queue counts")
    func privateReviewInboxHeaderDoesNotExposeCounts() {
        let presentation = ReviewInboxPrivacyPresentation.make(
            totalCount: 7,
            highPriorityCount: 3,
            isPrivate: true
        )

        #expect(presentation.subtitle == "Items need attention")
        #expect(presentation.highPriorityBadge == nil)
        #expect(presentation.highPriorityAccessibilityLabel == nil)
        #expect(presentation.accessibilityLabel == "Review inbox. Items are hidden while VaultPeek is private.")
        #expect(!presentation.subtitle.contains("7"))
        #expect(!presentation.accessibilityLabel.contains("7"))
        #expect(!presentation.accessibilityLabel.contains("3"))
    }

    @Test("normal Review Inbox header keeps actionable queue counts")
    func normalReviewInboxHeaderKeepsCounts() {
        let presentation = ReviewInboxPrivacyPresentation.make(
            totalCount: 2,
            highPriorityCount: 1,
            isPrivate: false
        )

        #expect(presentation.subtitle == "2 items need attention")
        #expect(presentation.highPriorityBadge == "1 high priority")
        #expect(presentation.highPriorityAccessibilityLabel == "1 high priority review item")
        #expect(presentation.accessibilityLabel == "Review inbox. 2 transactions need attention.")
    }

    @Test("unreviewed count badge shows 'N to review' when unmasked with a non-empty queue")
    func unreviewedBadgeShowsCountWhenUnmasked() {
        #expect(ReviewInboxPrivacyPresentation.unreviewedBadge(count: 5, isMasked: false) == "5 to review")
        #expect(ReviewInboxPrivacyPresentation.unreviewedBadge(count: 1, isMasked: false) == "1 to review")
    }

    @Test("unreviewed count badge is hidden under Privacy Mask so no count leaks")
    func unreviewedBadgeHiddenWhileMasked() {
        // AND-483: the masked surface must never expose the queue size.
        #expect(ReviewInboxPrivacyPresentation.unreviewedBadge(count: 7, isMasked: true) == nil)
    }

    @Test("unreviewed count badge is hidden when the queue is empty")
    func unreviewedBadgeHiddenWhenEmpty() {
        #expect(ReviewInboxPrivacyPresentation.unreviewedBadge(count: 0, isMasked: false) == nil)
        // Masked-and-empty also yields nil (no count to leak, nothing to badge).
        #expect(ReviewInboxPrivacyPresentation.unreviewedBadge(count: 0, isMasked: true) == nil)
    }

    @Test("private Review Inbox confirmation hides merchant details")
    func privateReviewInboxConfirmationHidesMerchantDetails() {
        let presentation = ReviewActionConfirmationPrivacyPresentation.make(
            actionMessage: "Approved",
            merchantName: "Sensitive Merchant",
            isPrivate: true
        )

        #expect(presentation.message == "Review action completed")
        #expect(presentation.accessibilityLabel == "Review action completed. Details are hidden while VaultPeek is private.")
        #expect(!presentation.message.contains("Approved"))
        #expect(!presentation.message.contains("Sensitive Merchant"))
        #expect(!presentation.accessibilityLabel.contains("Sensitive Merchant"))
    }

    @Test("normal Review Inbox confirmation keeps merchant details")
    func normalReviewInboxConfirmationKeepsMerchantDetails() {
        let presentation = ReviewActionConfirmationPrivacyPresentation.make(
            actionMessage: "Ignored",
            merchantName: "Local Grocer",
            isPrivate: false
        )

        #expect(presentation.message == "Ignored: Local Grocer")
        #expect(presentation.accessibilityLabel == "Review action completed: Ignored for Local Grocer")
    }

    @Test("normal bulk-review confirmation has no merchant subject")
    func normalBulkReviewConfirmationHasNoMerchantSubject() {
        // Bulk "Mark N reviewed" actions resolve a count, not one merchant, so
        // the confirmation carries no merchant name (nil) and the copy falls
        // back to the action message alone.
        let presentation = ReviewActionConfirmationPrivacyPresentation.make(
            actionMessage: "Marked 5 reviewed",
            merchantName: nil,
            isPrivate: false
        )

        #expect(presentation.message == "Marked 5 reviewed")
        #expect(presentation.accessibilityLabel == "Review action completed: Marked 5 reviewed")
    }

    @Test("private bulk-review confirmation stays generic")
    func privateBulkReviewConfirmationStaysGeneric() {
        let presentation = ReviewActionConfirmationPrivacyPresentation.make(
            actionMessage: "Marked 5 reviewed",
            merchantName: nil,
            isPrivate: true
        )

        #expect(presentation.message == "Review action completed")
        #expect(presentation.accessibilityLabel == "Review action completed. Details are hidden while VaultPeek is private.")
        #expect(!presentation.message.contains("5"))
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

    @Test("launch/background lock policies require App Lock plus their trigger")
    func launchAndBackgroundLockPoliciesRequireEnabledLock() {
        #expect(AppLockPreferences(appLockEnabled: true, lockOnLaunch: true).shouldLockOnLaunch == true)
        #expect(AppLockPreferences(appLockEnabled: false, lockOnLaunch: true).shouldLockOnLaunch == false)
        #expect(AppLockPreferences(appLockEnabled: true, lockOnLaunch: false).shouldLockOnLaunch == false)

        #expect(AppLockPreferences(appLockEnabled: true, lockWhenBackgrounded: true).shouldLockWhenBackgrounded == true)
        #expect(AppLockPreferences(appLockEnabled: false, lockWhenBackgrounded: true).shouldLockWhenBackgrounded == false)
        #expect(AppLockPreferences(appLockEnabled: true, lockWhenBackgrounded: false).shouldLockWhenBackgrounded == false)
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

    @Test("notification privacy modes expose a stable display name")
    func notificationPrivacyDisplayNames() {
        #expect(NotificationPrivacyMode.detailed.displayName == "Detailed")
        #expect(NotificationPrivacyMode.genericWhenPrivate.displayName == "Generic when private")
        #expect(NotificationPrivacyMode.alwaysGeneric.displayName == "Always generic")
        #expect(NotificationPrivacyMode.offWhileLocked.displayName == "Off while locked")
    }

    @Test("only off-while-locked describes suppression; the rest share generic copy")
    func notificationPrivacyDetailCopy() {
        let generic = NotificationPrivacyMode.alwaysGeneric.detail
        #expect(NotificationPrivacyMode.detailed.detail == generic)
        #expect(NotificationPrivacyMode.genericWhenPrivate.detail == generic)
        #expect(generic.contains("alerts still arrive while VaultPeek is locked"))
        #expect(NotificationPrivacyMode.offWhileLocked.detail.contains("suppressed entirely while VaultPeek is locked"))
        #expect(NotificationPrivacyMode.offWhileLocked.detail != generic)
    }

    @Test("shouldSend suppresses only off-while-locked while locked")
    func notificationShouldSend() {
        #expect(NotificationPrivacyMode.offWhileLocked.shouldSend(isLocked: true) == false)
        #expect(NotificationPrivacyMode.offWhileLocked.shouldSend(isLocked: false) == true)
        #expect(NotificationPrivacyMode.alwaysGeneric.shouldSend(isLocked: true) == true)
        #expect(NotificationPrivacyMode.detailed.shouldSend(isLocked: true) == true)
    }

    @Test("each authentication outcome has distinct, non-empty locked-surface copy")
    func authenticationMessageSurfaceCopy() {
        let messages: [AppLockAuthenticationMessage] = [.failed, .canceled, .unavailable, .lockout]
        let copies = messages.map(\.lockedSurfaceCopy)
        #expect(copies.allSatisfy { !$0.isEmpty })
        #expect(Set(copies).count == messages.count)
        #expect(AppLockAuthenticationMessage.failed.lockedSurfaceCopy.contains("Try again"))
        #expect(AppLockAuthenticationMessage.lockout.lockedSurfaceCopy.contains("Touch ID"))
    }
}
