import AppKit
import SwiftUI

/// Pins the popover window's trailing (right) edge while the left fly-out is
/// open.
///
/// A window-style `MenuBarExtra` is centered horizontally under its status
/// item, so when the fly-out grows the popover (480 → 801pt) AppKit
/// re-centers the wider window and the dashboard column visibly slides
/// sideways. By holding the window's `maxX` constant across resizes, the
/// extra width is added on the leading edge only and the dashboard stays put.
struct PopoverTrailingEdgeAnchor: NSViewRepresentable {
    /// True while the fly-out is shown (popover is in its widened state).
    let isExpanded: Bool

    func makeNSView(context: Context) -> NSView {
        let view = NSView(frame: .zero)
        context.coordinator.isExpanded = isExpanded
        context.coordinator.bind(to: view)
        return view
    }

    func updateNSView(_ nsView: NSView, context: Context) {
        context.coordinator.isExpanded = isExpanded
        context.coordinator.bind(to: nsView)
    }

    func makeCoordinator() -> Coordinator {
        Coordinator()
    }

    @MainActor
    final class Coordinator {
        var isExpanded = false

        private weak var window: NSWindow?
        /// The popover's right-edge screen position captured while collapsed;
        /// this is the anchor the widened window is pinned to.
        private var anchorMaxX: CGFloat?
        private var resizeObserver: NSObjectProtocol?

        func bind(to view: NSView) {
            // The hosting window is not available until the view joins the
            // window hierarchy, so resolve it on the next runloop tick.
            DispatchQueue.main.async { [weak self, weak view] in
                guard let self, let window = view?.window else { return }
                attach(to: window)
            }
        }

        private func attach(to window: NSWindow) {
            guard window !== self.window else {
                captureAnchorIfCollapsed()
                return
            }
            removeObserver()
            self.window = window
            captureAnchorIfCollapsed()

            resizeObserver = NotificationCenter.default.addObserver(
                forName: NSWindow.didResizeNotification,
                object: window,
                queue: .main
            ) { [weak self] _ in
                MainActor.assumeIsolated { self?.pinTrailingEdge() }
            }
        }

        private func captureAnchorIfCollapsed() {
            guard let window, !isExpanded else { return }
            anchorMaxX = window.frame.maxX
        }

        private func pinTrailingEdge() {
            guard let window else { return }

            // Re-capture the natural anchor every time the popover returns to
            // its collapsed width (the status item may move between sessions
            // or displays).
            guard isExpanded else {
                anchorMaxX = window.frame.maxX
                return
            }

            guard let anchorMaxX else { return }
            let targetX = anchorMaxX - window.frame.width
            guard abs(window.frame.origin.x - targetX) > 0.5 else { return }
            window.setFrameOrigin(NSPoint(x: targetX, y: window.frame.origin.y))
        }

        private func removeObserver() {
            guard let resizeObserver else { return }
            NotificationCenter.default.removeObserver(resizeObserver)
            self.resizeObserver = nil
        }
    }
}
