import CoreGraphics
import PlaidBarCore
import Testing

@Suite("Three-column popover geometry")
struct PopoverGeometryTests {
    @Test("Layout widths match the three-column contract (480 / 801 / 1122)")
    func layoutWidths() {
        #expect(PopoverGeometry.width(for: .setup) == 480)
        #expect(PopoverGeometry.width(for: .twoColumn) == 801)
        #expect(PopoverGeometry.width(for: .threeColumn) == 1122)
    }

    @Test("Two-column equals the setup-to-dashboard plus one rail and divider")
    func twoColumnComposition() {
        // Selecting an account widens by exactly a divider + a rail, so the
        // left edge can stay anchored while the inspector grows rightward.
        let delta = PopoverGeometry.width(for: .threeColumn) - PopoverGeometry.width(for: .twoColumn)
        #expect(delta == PopoverGeometry.dividerWidth + PopoverGeometry.railWidth)
    }

    @Test("A popover that already fits is not moved")
    func clampLeavesFittingPopover() {
        // 1122 popover at x=200 on a 1680-wide display fits with room to spare.
        let x = PopoverGeometry.clampedLeadingX(
            desiredLeadingX: 200,
            width: 1122,
            visibleMinX: 0,
            visibleMaxX: 1680,
            margin: 12
        )
        #expect(x == 200)
    }

    @Test("Near the right edge the popover is pulled left so the trailing edge fits")
    func clampPullsLeftNearRightEdge() {
        // Desired leading edge would push the trailing edge past the right edge.
        let width: CGFloat = 1122
        let visibleMaxX: CGFloat = 1440
        let margin: CGFloat = 12
        let x = PopoverGeometry.clampedLeadingX(
            desiredLeadingX: 1000,
            width: width,
            visibleMinX: 0,
            visibleMaxX: visibleMaxX,
            margin: margin
        )
        #expect(x == visibleMaxX - margin - width) // 306
        #expect(x + width <= visibleMaxX - margin)
    }

    @Test("On a display too narrow for the full width, the leading edge wins")
    func clampKeepsLeadingEdgeOnNarrowDisplay() {
        // 1122 cannot fit on a 1024-wide display; the rail (leading edge) must
        // stay visible, so the result is pinned to the left margin even though
        // the trailing edge overflows (documented Tier-2 fallback).
        let margin: CGFloat = 12
        let x = PopoverGeometry.clampedLeadingX(
            desiredLeadingX: 400,
            width: 1122,
            visibleMinX: 0,
            visibleMaxX: 1024,
            margin: margin
        )
        #expect(x == margin) // leading edge on-screen
    }

    @Test("A leading edge left of the screen is pushed in to the margin")
    func clampPushesRightOffLeftEdge() {
        let x = PopoverGeometry.clampedLeadingX(
            desiredLeadingX: -50,
            width: 801,
            visibleMinX: 0,
            visibleMaxX: 1680,
            margin: 12
        )
        #expect(x == 12)
    }

    @Test("Clamp respects a non-zero visibleMinX (secondary display)")
    func clampHonorsDisplayOrigin() {
        // A display whose visible frame starts at x=1680 (a second monitor).
        let x = PopoverGeometry.clampedLeadingX(
            desiredLeadingX: 1680,
            width: 801,
            visibleMinX: 1680,
            visibleMaxX: 3360,
            margin: 12
        )
        #expect(x == 1692) // 1680 + margin
    }
}
