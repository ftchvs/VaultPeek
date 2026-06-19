import Foundation

/// Pure, `Sendable` refcount + baseline-capture decision for the menu-bar app's
/// `.accessory ↔ .regular` activation policy (ADR-001 R-01, AND-620).
///
/// `.accessory↔.regular` thrash is the single most-repeatedly-patched area in repo
/// history: every surface that needs front/Dock presence (the detached dashboard,
/// the Category Dashboard / Review Table windows, Settings, and — now — the
/// window-first primary `Window`) must elevate to `.regular` while it is open and
/// the app must drop back to `.accessory` only when the **last** of them closes.
/// When each surface saved its own "previous" policy, whichever opened second
/// captured the already-elevated `.regular` as its baseline and stranded a
/// spurious Dock / ⌘-Tab presence after both closed.
///
/// This type concentrates that fragile bookkeeping into one value type with **no
/// AppKit dependency**, so the whole policy is unit-testable without launching the
/// app or touching `NSApplication`. The decision is expressed as a pure
/// `ActivationPolicy` enum (mirroring the three `NSApplication.ActivationPolicy`
/// cases the app uses); the thin `@MainActor` `AppActivationPolicyCoordinator`
/// shim in the app target maps it to `NSApp.setActivationPolicy` and the
/// window-first helper drives the same instance, so every surface shares one
/// authoritative refcount.
///
/// Contract:
/// - The pre-elevation **baseline** is captured only on the *first* outstanding
///   request and restored only when the *last* request is released. A launch flag
///   that already set `.regular` (e.g. `--regular-activation`) is preserved as the
///   baseline, so releasing the last surface does not strip an intentional Dock
///   presence.
/// - `request`/`release` each return the policy that *should now be applied*, or
///   `nil` when no change is needed — so the AppKit shim only mutates
///   `NSApp.activationPolicy` when it actually differs, and a balanced
///   request→release cycle leaves the app exactly where it started.
/// - `release` past zero is a no-op (`nil`), so an over-release can never wedge the
///   policy or strand a negative refcount.
public struct ActivationPolicyRefcount: Sendable, Equatable {
    /// The activation policies the menu-bar app moves between. A SwiftUI/AppKit-free
    /// mirror of the three `NSApplication.ActivationPolicy` cases VaultPeek uses, so
    /// the decision stays in Core and is `Equatable` for tests.
    public enum ActivationPolicy: String, Sendable, Equatable {
        /// Menu-bar-only: no Dock icon, not in ⌘-Tab. The shipping default.
        case accessory
        /// Conventional foreground app: Dock icon + ⌘-Tab. Elevated while a window
        /// or Settings is open.
        case regular
        /// Background-only (no UI). VaultPeek never sets this itself, but it can be
        /// the live policy momentarily during launch; modeled so a captured baseline
        /// round-trips faithfully.
        case prohibited
    }

    /// Outstanding `.regular` elevation requests. `.accessory` (or the captured
    /// baseline) is restored when this returns to zero.
    public private(set) var requestCount: Int = 0

    /// The policy captured before the first elevation, restored when the last
    /// request is released. `nil` while no request is outstanding.
    public private(set) var baseline: ActivationPolicy?

    public init() {}

    /// Register one `.regular` elevation request for a surface that needs
    /// front/Dock presence. `currentPolicy` is the live policy *before* this call —
    /// captured as the baseline only on the first outstanding request.
    ///
    /// - Returns: `.regular` when the policy must change to elevate, or `nil` when
    ///   the app is already `.regular` (e.g. a second surface opening). Balance every
    ///   `request` with exactly one `release`.
    public mutating func request(currentPolicy: ActivationPolicy) -> ActivationPolicy? {
        if requestCount == 0 {
            baseline = currentPolicy
        }
        requestCount += 1
        return currentPolicy == .regular ? nil : .regular
    }

    /// Release one previous `request`. When the last outstanding request is
    /// released, return the captured baseline so the app drops back to where it was
    /// before the first elevation (normally `.accessory`).
    ///
    /// - Returns: the policy to restore when the last request is released and it
    ///   differs from `currentPolicy`; `nil` when requests remain, when releasing
    ///   past zero, or when no change is needed.
    public mutating func release(currentPolicy: ActivationPolicy) -> ActivationPolicy? {
        guard requestCount > 0 else { return nil }
        requestCount -= 1
        guard requestCount == 0 else { return nil }
        let restore = baseline ?? .accessory
        baseline = nil
        return currentPolicy == restore ? nil : restore
    }
}
