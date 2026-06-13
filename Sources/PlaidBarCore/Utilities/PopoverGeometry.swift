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
