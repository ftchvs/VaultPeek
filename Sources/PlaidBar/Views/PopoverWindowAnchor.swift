import AppKit
import SwiftUI

/// Pins the popover window's leading (left) edge so the persistent Wealth
/// Summary rail and center dashboard stay put while the trailing account
/// inspector opens, and clamps the widened popover inside the visible screen.
///
/// A window-style `MenuBarExtra` centers its window's `midX` under the status
/// item regardless of width, so when the inspector grows the popover
/// (two-column → three-column) AppKit re-centers the wider window and the left
/// rail visibly slides sideways. Holding the window's `minX` constant across
/// resizes adds the extra width on the trailing edge only, so the left rail and
/// center stay anchored (AND-370). When the widened popover would extend past
/// the screen's visible edge it is shifted back on-screen — the leading edge
/// wins so the Wealth Summary rail always stays visible (AND-374 primary
/// fallback).
struct PopoverLeadingEdgeAnchor: NSViewRepresentable {
    /// True while the trailing account inspector is shown (popover is in its
    /// widened three-column state).
    let isInspectorOpen: Bool
    /// The popover's width with the inspector closed (two-column base). Used to
    /// derive the leading-edge anchor even when the popover first opens already
    /// widened (e.g. a persisted account selection): because the window is
    /// centered on the status item independent of width, collapsed
    /// `minX == midX - collapsedWidth / 2`.
    let collapsedWidth: CGFloat
    /// Gap kept between the popover and the screen's visible edges when the
    /// widened popover is clamped on-screen.
    let screenEdgeMargin: CGFloat

    func makeNSView(context: Context) -> AnchorHostView {
        let view = AnchorHostView()
        context.coordinator.configure(
            isInspectorOpen: isInspectorOpen,
            collapsedWidth: collapsedWidth,
            screenEdgeMargin: screenEdgeMargin
        )
        view.onMoveToWindow = { [coordinator = context.coordinator] window in
            coordinator.attach(to: window)
        }
        return view
    }

    func updateNSView(_ nsView: AnchorHostView, context: Context) {
        context.coordinator.configure(
            isInspectorOpen: isInspectorOpen,
            collapsedWidth: collapsedWidth,
            screenEdgeMargin: screenEdgeMargin
        )
        context.coordinator.attach(to: nsView.window)
    }

    static func dismantleNSView(_ nsView: AnchorHostView, coordinator: Coordinator) {
        coordinator.detach()
    }

    func makeCoordinator() -> Coordinator {
        Coordinator()
    }

    /// Reports window-hierarchy changes so the anchor attaches as soon as the
    /// view has a window, without a fragile deferred runloop hop.
    final class AnchorHostView: NSView {
        var onMoveToWindow: ((NSWindow?) -> Void)?

        override func viewDidMoveToWindow() {
            super.viewDidMoveToWindow()
            onMoveToWindow?(window)
        }
    }

    @MainActor
    final class Coordinator {
        private var isInspectorOpen = false
        private var collapsedWidth: CGFloat = 0
        private var screenEdgeMargin: CGFloat = 0
        private weak var window: NSWindow?
        /// The popover's left-edge screen position the widened window is pinned
        /// to. Captured from the collapsed (two-column) geometry, or derived
        /// from the centered `midX` when the popover opens already expanded.
        private var anchorMinX: CGFloat?
        private var resizeObserver: NSObjectProtocol?

        func configure(isInspectorOpen: Bool, collapsedWidth: CGFloat, screenEdgeMargin: CGFloat) {
            self.isInspectorOpen = isInspectorOpen
            self.collapsedWidth = collapsedWidth
            self.screenEdgeMargin = screenEdgeMargin
        }

        func attach(to window: NSWindow?) {
            guard let window else { return }
            if window !== self.window {
                detach()
                // A MenuBarExtra recreates its window between opens; drop the
                // stale anchor so each fresh window re-derives it from the new
                // centered geometry (the status item may have moved or the
                // display changed). Without this a popover that opens already
                // expanded would pin to the previous session's X.
                anchorMinX = nil
                self.window = window
                resizeObserver = NotificationCenter.default.addObserver(
                    forName: NSWindow.didResizeNotification,
                    object: window,
                    queue: .main
                ) { [weak self] _ in
                    MainActor.assumeIsolated { self?.pinLeadingEdge() }
                }
            }
            captureAnchor()
            // Pin immediately so a popover that opens already widened (a
            // persisted account selection) lands in the correct three-column
            // geometry without waiting for a resize event that may never fire
            // (AND-370). The no-op guard in `pinLeadingEdge` keeps this cheap.
            pinLeadingEdge()
        }

        func detach() {
            if let resizeObserver {
                NotificationCenter.default.removeObserver(resizeObserver)
                self.resizeObserver = nil
            }
            window = nil
        }

        /// Establish the leading-edge anchor. When collapsed, it is simply the
        /// current left edge. When the popover opens already expanded, derive
        /// the collapsed left edge from the centered window: the status item
        /// fixes `midX`, so collapsed `minX = midX - collapsedWidth / 2`.
        private func captureAnchor() {
            guard let window, anchorMinX == nil else { return }
            if isInspectorOpen {
                guard collapsedWidth > 0 else { return }
                anchorMinX = window.frame.midX - collapsedWidth / 2
            } else {
                anchorMinX = window.frame.minX
            }
        }

        private func pinLeadingEdge() {
            guard let window else { return }

            // Collapsing back to two columns: re-derive the natural anchor from
            // the centered window, then hold that leading edge (clamped) for the
            // collapsed width too. Letting AppKit re-center the narrower window
            // unmanaged would jump the rail right when the expanded popover had
            // been clamped left near a display edge (AND-370 no-jump on close).
            guard isInspectorOpen else {
                let naturalLeading = window.frame.midX - collapsedWidth / 2
                anchorMinX = naturalLeading
                applyOrigin(clampedOriginX(naturalLeading, width: window.frame.width, in: window), to: window)
                return
            }

            if anchorMinX == nil { captureAnchor() }
            guard let anchorMinX else { return }
            applyOrigin(clampedOriginX(anchorMinX, width: window.frame.width, in: window), to: window)
        }

        /// Clamp a desired leading-edge X so the popover of the given width stays
        /// inside the screen's visible frame: pull the trailing edge in if it
        /// would overflow the right edge, then keep the leading edge on-screen.
        /// On displays too narrow to fit the full width the leading edge wins
        /// (applied last) so the Wealth Summary rail stays visible (AND-374).
        private func clampedOriginX(_ leadingX: CGFloat, width: CGFloat, in window: NSWindow) -> CGFloat {
            guard let screen = window.screen ?? NSScreen.main else { return leadingX }
            let visible = screen.visibleFrame
            var targetX = leadingX
            let maxOriginX = visible.maxX - screenEdgeMargin - width
            let minOriginX = visible.minX + screenEdgeMargin
            if targetX > maxOriginX { targetX = maxOriginX }
            if targetX < minOriginX { targetX = minOriginX }
            return targetX
        }

        private func applyOrigin(_ targetX: CGFloat, to window: NSWindow) {
            guard abs(window.frame.origin.x - targetX) > 0.5 else { return }
            window.setFrameOrigin(NSPoint(x: targetX, y: window.frame.origin.y))
        }
    }
}
