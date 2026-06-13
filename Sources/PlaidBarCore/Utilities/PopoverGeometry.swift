import CoreGraphics

/// Geometry for the three-column popover (AND-367): deterministic column widths,
/// the content width for each layout state, and the on-screen clamp for the
/// widened popover.
///
/// Pure and `Sendable` so it can be unit-tested and shared by the SwiftUI layout
/// (`MainPopover`) and the AppKit window anchor (`PopoverWindowAnchor`), keeping
/// a single source of truth for the 480 / 801 / 1122 geometry and the
/// screen-constrained fallback (AND-370/374/375).
public enum PopoverGeometry {
    /// The Wealth Summary rail and the account inspector share this width.
    public static let railWidth: CGFloat = 320
    /// The center dashboard column width (also the setup-screen width).
    public static let dashboardWidth: CGFloat = 480
    /// A single divider between two adjacent columns.
    public static let dividerWidth: CGFloat = 1
    /// Default gap kept between the widened popover and the screen's visible
    /// edges when it is clamped on-screen.
    public static let screenEdgeMargin: CGFloat = 12
    /// The minimum width the flexible center dashboard keeps when the popover is
    /// capped on a narrow/scaled display. The rail and inspector stay fixed at
    /// `railWidth`, so the center absorbs the difference down to this floor. Set
    /// so a scaled 1024-wide display (center ≈ 358pt) still fits the full
    /// three-column layout without overflow (AND-405).
    public static let minDashboardWidth: CGFloat = 340

    /// The three popover layout states and their column composition.
    public enum Layout: Sendable, CaseIterable {
        /// Setup screen — dashboard width only, no side columns.
        case setup
        /// No account selected — Wealth Summary rail + center dashboard.
        case twoColumn
        /// Account selected — rail + dashboard + trailing account inspector.
        case threeColumn
    }

    /// The popover's content width for a layout state.
    public static func width(for layout: Layout) -> CGFloat {
        switch layout {
        case .setup:
            dashboardWidth
        case .twoColumn:
            railWidth + dividerWidth + dashboardWidth
        case .threeColumn:
            railWidth + dividerWidth + dashboardWidth + dividerWidth + railWidth
        }
    }

    /// The popover's content width capped to fit the available screen width.
    ///
    /// When the full layout width exceeds the available width (minus a margin on
    /// each side), the popover is capped so it never renders off-screen — the
    /// rail and inspector keep their fixed widths and the center dashboard flexes
    /// to absorb the difference (down to `minDashboardWidth`), keeping the
    /// trailing inspector and its close control on-screen on narrow/scaled
    /// displays (AND-405). Pass a very large `availableWidth` (e.g. headless,
    /// where no screen exists) to get the full, uncapped width.
    public static func fittedWidth(
        for layout: Layout,
        availableWidth: CGFloat,
        margin: CGFloat = screenEdgeMargin
    ) -> CGFloat {
        let full = width(for: layout)
        // Guards the degenerate inputs; the headless sentinel is a large *finite*
        // value (e.g. .greatestFiniteMagnitude), which passes through to a no-op
        // min() below — `subtracting 2*margin from it stays effectively itself.
        guard availableWidth.isFinite, availableWidth > 0 else { return full }
        let usable = availableWidth - (2 * margin)
        guard usable > 0 else { return full }
        return min(full, usable)
    }

    /// Prefer the popover window's actual screen width over a global fallback.
    ///
    /// `NSScreen.main` can point at a different display than the menu-bar
    /// popover window, so callers should pass the active window screen when
    /// available and use the fallback only before the window attaches.
    public static func availableWidth(
        activeScreenWidth: CGFloat?,
        fallbackScreenWidth: CGFloat?
    ) -> CGFloat {
        if let activeScreenWidth, activeScreenWidth.isFinite, activeScreenWidth > 0 {
            return activeScreenWidth
        }
        if let fallbackScreenWidth, fallbackScreenWidth.isFinite, fallbackScreenWidth > 0 {
            return fallbackScreenWidth
        }
        return .greatestFiniteMagnitude
    }

    /// Clamp a desired leading-edge X so a popover of `width` stays within a
    /// screen's visible horizontal span `[visibleMinX, visibleMaxX]`, keeping
    /// `margin` from each edge.
    ///
    /// The trailing edge is pulled in first, then the leading edge wins: on a
    /// display too narrow to fit the full width the leading edge stays on-screen
    /// and the Wealth Summary rail remains visible — the primary
    /// screen-constrained fallback (AND-374).
    public static func clampedLeadingX(
        desiredLeadingX: CGFloat,
        width: CGFloat,
        visibleMinX: CGFloat,
        visibleMaxX: CGFloat,
        margin: CGFloat = screenEdgeMargin
    ) -> CGFloat {
        var x = desiredLeadingX
        let maxOriginX = visibleMaxX - margin - width
        let minOriginX = visibleMinX + margin
        if x > maxOriginX { x = maxOriginX }
        if x < minOriginX { x = minOriginX }
        return x
    }
}
