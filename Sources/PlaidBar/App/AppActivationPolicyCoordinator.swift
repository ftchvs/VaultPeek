import AppKit
import PlaidBarCore

/// Single owner of `NSApplication.activationPolicy` elevation, shared by every
/// surface that needs the menu-bar (`.accessory`) app to temporarily become a
/// regular, front-and-Dock app: the detached dashboard window, the Category
/// Dashboard / Review Table windows, the Settings window, and — behind the
/// window-first flag — the declarative primary `Window` (via
/// ``WindowActivationPolicy``, ADR-001 / AND-620).
///
/// It is **refcounted**. The pre-elevation baseline policy is captured only on
/// the *first* request and restored only when the *last* request is released, so
/// two surfaces open at once cannot strand the app in `.regular`. Without this,
/// each surface saved its own "previous" policy — and whichever opened second
/// captured the already-elevated `.regular` as its baseline, leaving a spurious
/// Dock / ⌘-Tab presence after both closed.
///
/// The fragile refcount + baseline-capture *decision* lives in the pure,
/// `@testable`-importable ``ActivationPolicyRefcount`` in `PlaidBarCore` (the app
/// target is not test-importable). This shim is the only place that touches
/// `NSApplication`: it maps the live `NSApp.activationPolicy()` into the pure
/// decision and applies the policy the decision returns, mutating
/// `NSApp.setActivationPolicy` only when it actually changes. The window-first
/// helper drives this same instance, so every surface shares one authoritative
/// refcount (R-01).
///
/// `@MainActor`-isolated; all `NSApplication` mutation happens on the main actor.
@MainActor
final class AppActivationPolicyCoordinator {
    static let shared = AppActivationPolicyCoordinator()

    private init() {}

    /// The pure refcount/baseline state. Every decision is computed here; this
    /// shim only reads/writes `NSApp` around it.
    private var refcount = ActivationPolicyRefcount()

    /// Elevate to `.regular` for a surface that needs front/Dock presence. Balance
    /// every call with exactly one `releaseRegular()`.
    func requestRegular() {
        if let target = refcount.request(currentPolicy: Self.currentPolicy()) {
            NSApp.setActivationPolicy(target.appKitPolicy)
        }
    }

    /// Release a previous `requestRegular()`. When the last outstanding request is
    /// released, restore the policy captured before the first elevation (the
    /// menu-bar app's `.accessory`, unless a launch flag had already set `.regular`).
    func releaseRegular() {
        if let target = refcount.release(currentPolicy: Self.currentPolicy()) {
            NSApp.setActivationPolicy(target.appKitPolicy)
        }
    }

    /// The live `NSApp` policy mapped into the pure `ActivationPolicy` domain.
    private static func currentPolicy() -> ActivationPolicyRefcount.ActivationPolicy {
        ActivationPolicyRefcount.ActivationPolicy(NSApp.activationPolicy())
    }
}

extension ActivationPolicyRefcount.ActivationPolicy {
    /// Map a live `NSApplication.ActivationPolicy` into the pure domain. Any future
    /// AppKit case (there is none today) falls back to `.accessory`, the safe
    /// menu-bar default.
    init(_ policy: NSApplication.ActivationPolicy) {
        switch policy {
        case .regular: self = .regular
        case .accessory: self = .accessory
        case .prohibited: self = .prohibited
        @unknown default: self = .accessory
        }
    }

    /// The `NSApplication.ActivationPolicy` to apply for this pure decision.
    var appKitPolicy: NSApplication.ActivationPolicy {
        switch self {
        case .regular: .regular
        case .accessory: .accessory
        case .prohibited: .prohibited
        }
    }
}
