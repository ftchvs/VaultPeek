import AppKit
import PlaidBarCore
import SwiftUI

/// Routes the declarative window-first `Window`'s open/close lifecycle through the
/// shared, refcounted ``AppActivationPolicyCoordinator`` so the menu-bar app
/// (`.accessory`) elevates to `.regular` while the primary workspace is on screen
/// and drops back to `.accessory` when the last managed window closes (ADR-001 /
/// AND-620, R-01).
///
/// SwiftUI gives a declarative `Window` no `NSWindowController` to hang
/// `windowDidLoad` / `windowWillClose` on, so this helper bridges the gap with
/// `.onAppear` / `.onDisappear` on the scene's root view. The legacy AppKit
/// windows (detached dashboard, Category Dashboard, Review Table, Settings) keep
/// their own imperative `requestRegular()` / `releaseRegular()` calls; retiring
/// those controllers is Epic 3 (R-01). Because this helper drives the *same*
/// shared coordinator instance, the new `Window` and the legacy windows share one
/// authoritative refcount — opening a legacy window while the primary window is up,
/// then closing one, does not prematurely drop the app to `.accessory`.
///
/// Idempotent guard: SwiftUI can deliver `.onAppear` / `.onDisappear` more than
/// once for a single visible window (re-layout, occlusion). `held` ensures this
/// instance contributes at most **one** outstanding request to the shared
/// refcount, so a redundant appear/disappear pair cannot unbalance it.
///
/// Flag-OFF safety: nothing constructs or drives this helper unless the
/// window-first `Window` actually opens, and that only happens behind
/// `WindowFirstFeatureFlag` (the scene is `.defaultLaunchBehavior(.suppressed)`
/// and its only opener is gated). With the flag OFF the window never appears, so
/// `onWindowAppear` / `onWindowDisappear` never fire and activation behavior is
/// byte-identical to the popover-first build.
///
/// `@MainActor`-isolated and `@Observable` so it can be held as `@State` across
/// `body` recomputes for the process lifetime, mirroring the other window
/// coordinators in `App/`.
@MainActor
@Observable
final class WindowActivationPolicy {
    /// The shared coordinator this helper drives. Injectable so a future test or
    /// alternate surface can target a different instance; defaults to the app-wide
    /// `.shared` so the new `Window` and the legacy AppKit windows share one
    /// refcount.
    private let coordinator: AppActivationPolicyCoordinator

    /// True while this helper holds exactly one outstanding `.regular` request with
    /// the shared coordinator. Prevents a duplicate `.onAppear` from double-counting
    /// and a duplicate `.onDisappear` from over-releasing.
    private(set) var held = false

    init(coordinator: AppActivationPolicyCoordinator = .shared) {
        self.coordinator = coordinator
    }

    /// Called when the primary `Window`'s root view appears. Elevates to `.regular`
    /// via the shared coordinator the first time, then no-ops until a matching
    /// `onWindowDisappear`.
    func onWindowAppear() {
        guard !held else { return }
        held = true
        coordinator.requestRegular()
    }

    /// Called when the primary `Window`'s root view disappears (the window closed).
    /// Releases this helper's single outstanding request; the shared coordinator
    /// only drops the app back to its baseline (`.accessory`) once *every* surface
    /// — legacy windows included — has released.
    func onWindowDisappear() {
        guard held else { return }
        held = false
        coordinator.releaseRegular()
    }
}
