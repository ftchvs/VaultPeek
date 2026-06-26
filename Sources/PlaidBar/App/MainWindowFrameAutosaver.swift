import AppKit
import SwiftUI

/// Persists and restores the window-first primary `Window`'s position and size
/// across relaunch (AND-593).
///
/// SwiftUI's declarative `Window` scene gives no `NSWindowController` and no
/// hook for the host window's frame, so — exactly like ``PopoverLeadingEdgeAnchor``
/// and the legacy AppKit window controllers (`CategoryDashboardWindowController`,
/// `ReviewTableWindowController`, `DetachedDashboardWindowController`, which all
/// set a `frameAutosaveName`) — this reaches the real `NSWindow` through a tiny
/// `NSViewRepresentable` bridge and applies a stable
/// ``NSWindow/setFrameAutosaveName(_:)`` once. AppKit then writes the frame to
/// `UserDefaults` whenever the user moves/resizes the window and restores it on
/// the next launch. `.defaultSize` only supplies the *first-ever* frame; the
/// autosave name is what makes the choice durable.
///
/// Hosted in a zero-size `.background` view so it never participates in layout.
/// The name is applied on `viewDidMoveToWindow` (when the host first acquires a
/// window) and is idempotent: setting the same autosave name twice is harmless,
/// so repeated SwiftUI re-layout / re-host passes cannot corrupt the saved frame.
///
/// Flag-OFF safety: the primary `Window` only opens behind `WindowFirstFeatureFlag`
/// (`.defaultLaunchBehavior(.suppressed)`, gated opener), so this bridge is never
/// mounted on the popover-first escape-hatch path and activation/restoration
/// behavior there is byte-identical to before.
struct MainWindowFrameAutosaver: NSViewRepresentable {
    /// Stable, app-wide-unique autosave key for the primary window's frame.
    let autosaveName: String

    func makeNSView(context: Context) -> AutosaverHostView {
        let view = AutosaverHostView()
        view.autosaveName = autosaveName
        return view
    }

    func updateNSView(_ nsView: AutosaverHostView, context: Context) {
        nsView.autosaveName = autosaveName
        nsView.applyIfPossible()
    }

    /// Zero-size host that applies the autosave name as soon as it has a window.
    /// `viewDidMoveToWindow` fires once the representable is attached to the real
    /// window hierarchy, which is exactly when the `NSWindow` exists to configure.
    final class AutosaverHostView: NSView {
        var autosaveName: String?

        override func viewDidMoveToWindow() {
            super.viewDidMoveToWindow()
            applyIfPossible()
        }

        /// Applies the autosave name to the host window once it is available.
        /// Idempotent: AppKit no-ops when the name is unchanged, so this is safe to
        /// call from both `viewDidMoveToWindow` and `updateNSView`.
        func applyIfPossible() {
            guard let window, let autosaveName,
                  window.frameAutosaveName != autosaveName else { return }
            window.setFrameAutosaveName(autosaveName)
        }
    }
}
