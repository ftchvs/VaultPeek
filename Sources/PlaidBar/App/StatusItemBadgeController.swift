import AppKit
import PlaidBarCore

/// Draws a small count badge for the unreviewed review-inbox count onto the
/// menu-bar status item's button (AND-534).
///
/// The app's menu bar is a SwiftUI `MenuBarExtra`, but the underlying
/// `NSStatusItem` is reachable via `MenuBarExtraAccess` (the same hook
/// `StatusItemContextMenuController` already uses). Per the delivery design
/// §4/§7 the badge is rendered through that custom `NSStatusItem` rather than
/// the SwiftUI label, because a `MenuBarExtra` label can't host the overlapping
/// pill cleanly under the documented glass constraint.
///
/// Rather than fight SwiftUI for ownership of the button's image, the controller
/// pins a lightweight overlay subview to the button's top-trailing corner and
/// draws the pill there. The overlay sits above the SwiftUI-rendered glyph and
/// updates independently whenever the count or Privacy Mask changes.
///
/// All visibility/text rules live in the pure, tested `MenuBarReviewBadge`
/// (PlaidBarCore): the badge is hidden at zero and withheld under Privacy Mask,
/// and meaning is carried by the number (and the spoken accessibility label),
/// never by color alone (`ACCESSIBILITY.md`).
@MainActor
final class StatusItemBadgeController {
    private weak var statusItem: NSStatusItem?
    private weak var badgeView: BadgeOverlayView?

    /// The last applied state, so repeated `update` calls during a single frame
    /// (the menu-bar label reads review state from several accessors per render)
    /// are cheap no-ops that don't churn the overlay.
    private var lastText: String?

    /// Attaches the badge overlay to the status item's button. Idempotent: safe
    /// to call on every `menuBarExtraAccess` callback (the button can be recreated
    /// when the menu-bar item is rebuilt). Re-applies the current badge state to a
    /// freshly attached overlay.
    func configure(statusItem: NSStatusItem) {
        self.statusItem = statusItem
        guard let button = statusItem.button else { return }

        if badgeView?.superview !== button {
            badgeView?.removeFromSuperview()
            let view = BadgeOverlayView()
            view.translatesAutoresizingMaskIntoConstraints = false
            button.addSubview(view)
            // Pin to the top-trailing corner of the button. The slight outward
            // nudge lets the pill sit at the icon's shoulder like a typical
            // notification badge without clipping inside the glyph.
            NSLayoutConstraint.activate([
                view.trailingAnchor.constraint(equalTo: button.trailingAnchor, constant: 3),
                view.topAnchor.constraint(equalTo: button.topAnchor, constant: -1)
            ])
            badgeView = view
            // Re-apply current state to the new overlay.
            let pending = lastText
            lastText = nil
            apply(text: pending)
        }
    }

    /// Updates the badge from the live unreviewed count and Privacy Mask state.
    /// The pure rule lives in `MenuBarReviewBadge`; this only renders the result.
    func update(unreviewedCount: Int, isMasked: Bool) {
        apply(text: MenuBarReviewBadge.text(unreviewedCount: unreviewedCount, isMasked: isMasked),
              accessibilityLabel: MenuBarReviewBadge.accessibilityLabel(
                  unreviewedCount: unreviewedCount, isMasked: isMasked))
    }

    private func apply(text: String?, accessibilityLabel: String? = nil) {
        guard text != lastText else {
            // Text unchanged, but the a11y label might be re-supplied on reattach;
            // keep it in sync without re-laying-out.
            badgeView?.setAccessibilityLabel(accessibilityLabel)
            return
        }
        lastText = text
        guard let badgeView else { return }
        badgeView.text = text
        badgeView.setAccessibilityLabel(accessibilityLabel)
        badgeView.isHidden = (text == nil)
    }
}

/// The overlay view that draws the rounded count pill. A plain `NSView` (not a
/// `NSTextField`) so the pill background and digits render together with full
/// control over insets and corner radius at menu-bar scale.
private final class BadgeOverlayView: NSView {
    var text: String? {
        didSet {
            guard text != oldValue else { return }
            invalidateIntrinsicContentSize()
            needsDisplay = true
            // Expose the badge to VoiceOver as a static-text element only when it
            // carries a count; an empty/hidden badge is not an a11y element. The
            // spoken label (real count, not the capped "99+") is set by the
            // controller via `accessibilityLabel`.
            setAccessibilityElement(text != nil)
            setAccessibilityRole(text != nil ? .staticText : .unknown)
        }
    }

    override var isFlipped: Bool { false }

    /// Whether the overlay should pass mouse events through to the status-item
    /// button beneath it. The badge is decorative; clicks must still open the
    /// popover, so it never intercepts hit-testing.
    override func hitTest(_ point: NSPoint) -> NSView? { nil }

    private static let font = NSFont.systemFont(ofSize: 9, weight: .semibold)
    private let horizontalInset: CGFloat = 3.5
    private let verticalInset: CGFloat = 1
    private let minimumDiameter: CGFloat = 13

    override var intrinsicContentSize: NSSize {
        guard let text, !text.isEmpty else { return .zero }
        let textSize = (text as NSString).size(withAttributes: [.font: Self.font])
        let width = max(minimumDiameter, ceil(textSize.width) + horizontalInset * 2)
        let height = max(minimumDiameter, ceil(textSize.height) + verticalInset * 2)
        return NSSize(width: width, height: height)
    }

    override func draw(_ dirtyRect: NSRect) {
        guard let text, !text.isEmpty else { return }

        let rect = bounds.insetBy(dx: 0.5, dy: 0.5)
        let radius = rect.height / 2
        let pill = NSBezierPath(roundedRect: rect, xRadius: radius, yRadius: radius)

        // The pill uses the system accent / alert red as a background. Per the
        // accessibility rule, color is never the *only* signal: the count digits
        // inside the pill carry the meaning, and the badge is also exposed to
        // VoiceOver via `accessibilityLabel`. A thin contrasting stroke keeps the
        // pill legible on both light and dark menu bars and over wallpapers.
        NSColor.systemRed.setFill()
        pill.fill()
        NSColor.windowBackgroundColor.withAlphaComponent(0.9).setStroke()
        pill.lineWidth = 1
        pill.stroke()

        let attributes: [NSAttributedString.Key: Any] = [
            .font: Self.font,
            .foregroundColor: NSColor.white
        ]
        let textSize = (text as NSString).size(withAttributes: attributes)
        let origin = NSPoint(
            x: bounds.midX - textSize.width / 2,
            y: bounds.midY - textSize.height / 2
        )
        (text as NSString).draw(at: origin, withAttributes: attributes)
    }
}
