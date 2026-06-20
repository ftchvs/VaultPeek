import Testing
@testable import PlaidBarCore

/// Codifies the **App Lock + Privacy Mask cross-window parity** decision the
/// window-first shell relies on (ADR-001 Epic 10 / AND-588). The popover, its
/// detached host, and the window-first `AppShellView` all gate on the *same* pure
/// `AppLockPreferences.effectiveDisplayMode(isAppLocked:)` decision via
/// `AppState.isContentLocked` (== `effectiveDisplayMode == .locked`) and
/// `AppState.shouldMaskFinancialValues` (== `effectiveDisplayMode != .normal`).
///
/// These tests pin the invariant that "locked withholds content, masked dots
/// values" resolves identically regardless of which surface is showing — so the
/// window-first window can never display balances/account names while App Lock is
/// engaged, matching the popover.
@Suite("Window-first App Lock / Privacy Mask parity (AND-588)")
struct WindowFirstAppLockParityTests {
    /// The view-level gate predicate the shell + popover share:
    /// `AppState.isContentLocked`.
    private func isContentLocked(_ preferences: AppLockPreferences, isAppLocked: Bool) -> Bool {
        preferences.effectiveDisplayMode(isAppLocked: isAppLocked) == .locked
    }

    /// The view-level mask predicate the shell + popover share:
    /// `AppState.shouldMaskFinancialValues`.
    private func shouldMask(_ preferences: AppLockPreferences, isAppLocked: Bool) -> Bool {
        preferences.effectiveDisplayMode(isAppLocked: isAppLocked) != .normal
    }

    @Test("When App Lock is enabled and engaged, content is withheld (gate shown) on every surface")
    func lockedWithholdsContent() {
        let preferences = AppLockPreferences(appLockEnabled: true)
        // Engaged → locked: the window-first shell mounts AppLockedGateView, same
        // as the popover.
        #expect(isContentLocked(preferences, isAppLocked: true) == true)
        // Not engaged → no gate.
        #expect(isContentLocked(preferences, isAppLocked: false) == false)
    }

    @Test("App Lock disabled never withholds content even if the engaged flag flips")
    func disabledLockNeverGates() {
        let preferences = AppLockPreferences(appLockEnabled: false)
        #expect(isContentLocked(preferences, isAppLocked: true) == false)
        #expect(isContentLocked(preferences, isAppLocked: false) == false)
    }

    @Test("Locked supersedes Privacy Mask — a locked window withholds rather than just dotting values")
    func lockedSupersedesMask() {
        let preferences = AppLockPreferences(privacyMaskEnabled: true, appLockEnabled: true)
        #expect(preferences.effectiveDisplayMode(isAppLocked: true) == .locked)
        #expect(isContentLocked(preferences, isAppLocked: true) == true)
        // Still considered "masking" (a superset), so amount call sites stay dotted
        // underneath the gate too.
        #expect(shouldMask(preferences, isAppLocked: true) == true)
    }

    @Test("Privacy Mask alone dots values on every surface without withholding content")
    func maskDotsWithoutWithholding() {
        let preferences = AppLockPreferences(privacyMaskEnabled: true, appLockEnabled: false)
        #expect(isContentLocked(preferences, isAppLocked: false) == false)
        #expect(shouldMask(preferences, isAppLocked: false) == true)
    }

    @Test("Normal mode shows content unmasked on every surface")
    func normalShowsEverything() {
        let preferences = AppLockPreferences()
        #expect(isContentLocked(preferences, isAppLocked: false) == false)
        #expect(shouldMask(preferences, isAppLocked: false) == false)
    }
}
