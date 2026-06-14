import AppKit

/// Single owner of `NSApplication.activationPolicy` elevation, shared by every
/// surface that needs the menu-bar (`.accessory`) app to temporarily become a
/// regular, front-and-Dock app: the detached dashboard window and the Settings
/// window.
///
/// It is **refcounted**. The pre-elevation baseline policy is captured only on
/// the *first* request and restored only when the *last* request is released, so
/// two surfaces open at once cannot strand the app in `.regular`. Without this,
/// each surface saved its own "previous" policy — and whichever opened second
/// captured the already-elevated `.regular` as its baseline, leaving a spurious
/// Dock / ⌘-Tab presence after both closed.
///
/// `@MainActor`-isolated; all `NSApplication` mutation happens on the main actor.
@MainActor
final class AppActivationPolicyCoordinator {
    static let shared = AppActivationPolicyCoordinator()

    private init() {}

    private var requestCount = 0
    private var baselinePolicy: NSApplication.ActivationPolicy?

    /// Elevate to `.regular` for a surface that needs front/Dock presence. Balance
    /// every call with exactly one `releaseRegular()`.
    func requestRegular() {
        if requestCount == 0 {
            baselinePolicy = NSApp.activationPolicy()
        }
        requestCount += 1
        if NSApp.activationPolicy() != .regular {
            NSApp.setActivationPolicy(.regular)
        }
    }

    /// Release a previous `requestRegular()`. When the last outstanding request is
    /// released, restore the policy captured before the first elevation (the
    /// menu-bar app's `.accessory`, unless a launch flag had already set `.regular`).
    func releaseRegular() {
        guard requestCount > 0 else { return }
        requestCount -= 1
        guard requestCount == 0 else { return }
        let restore = baselinePolicy ?? .accessory
        baselinePolicy = nil
        if NSApp.activationPolicy() != restore {
            NSApp.setActivationPolicy(restore)
        }
    }
}
