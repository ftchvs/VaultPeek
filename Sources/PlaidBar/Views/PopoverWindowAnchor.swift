import AppKit
import SwiftUI

/// Pins the popover window's trailing (right) edge while the left fly-out is
/// open.
///
/// A window-style `MenuBarExtra` centers its window's `midX` under the status
/// item regardless of width, so when the fly-out grows the popover
/// (collapsed → collapsed + fly-out) AppKit re-centers the wider window and
/// the dashboard column visibly slides sideways. Holding the window's `maxX`
/// constant across resizes adds the extra width on the leading edge only, so
/// the dashboard stays put.
struct PopoverTrailingEdgeAnchor: NSViewRepresentable {
    /// True while the fly-out is shown (popover is in its widened state).
    let isExpanded: Bool
    /// The popover's collapsed (fly-out closed) width. Used to derive the
    /// trailing-edge anchor even when the popover first opens already widened
    /// (e.g. a persisted account selection): because the window is centered on
    /// the status item independent of width, collapsed `maxX == midX + width/2`.
    let collapsedWidth: CGFloat

    func makeNSView(context: Context) -> AnchorHostView {
        let view = AnchorHostView()
        context.coordinator.configure(isExpanded: isExpanded, collapsedWidth: collapsedWidth)
        view.onMoveToWindow = { [coordinator = context.coordinator] window in
            coordinator.attach(to: window)
        }
        return view
    }

    func updateNSView(_ nsView: AnchorHostView, context: Context) {
        context.coordinator.configure(isExpanded: isExpanded, collapsedWidth: collapsedWidth)
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
        private var isExpanded = false
        private var collapsedWidth: CGFloat = 0
        private weak var window: NSWindow?
        /// The popover's right-edge screen position the widened window is
        /// pinned to. Captured from the collapsed geometry, or derived from the
        /// centered `midX` when the popover opens already expanded.
        private var anchorMaxX: CGFloat?
        private var resizeObserver: NSObjectProtocol?

        func configure(isExpanded: Bool, collapsedWidth: CGFloat) {
            self.isExpanded = isExpanded
            self.collapsedWidth = collapsedWidth
        }

        func attach(to window: NSWindow?) {
            guard let window else { return }
            if window !== self.window {
                detach()
                self.window = window
                resizeObserver = NotificationCenter.default.addObserver(
                    forName: NSWindow.didResizeNotification,
                    object: window,
                    queue: .main
                ) { [weak self] _ in
                    MainActor.assumeIsolated { self?.pinTrailingEdge() }
                }
            }
            captureAnchor()
        }

        func detach() {
            if let resizeObserver {
                NotificationCenter.default.removeObserver(resizeObserver)
                self.resizeObserver = nil
            }
            window = nil
        }

        /// Establish the trailing-edge anchor. When collapsed, it is simply the
        /// current right edge. When the popover opens already expanded, derive
        /// the collapsed right edge from the centered window: the status item
        /// fixes `midX`, so collapsed `maxX = midX + collapsedWidth / 2`.
        private func captureAnchor() {
            guard let window, anchorMaxX == nil else { return }
            if isExpanded {
                guard collapsedWidth > 0 else { return }
                anchorMaxX = window.frame.midX + collapsedWidth / 2
            } else {
                anchorMaxX = window.frame.maxX
            }
        }

        private func pinTrailingEdge() {
            guard let window else { return }

            // Returning to the collapsed width re-establishes the natural
            // anchor (the status item may move between sessions or displays).
            guard isExpanded else {
                anchorMaxX = window.frame.maxX
                return
            }

            if anchorMaxX == nil { captureAnchor() }
            guard let anchorMaxX else { return }
            let targetX = anchorMaxX - window.frame.width
            guard abs(window.frame.origin.x - targetX) > 0.5 else { return }
            window.setFrameOrigin(NSPoint(x: targetX, y: window.frame.origin.y))
        }
    }
}
