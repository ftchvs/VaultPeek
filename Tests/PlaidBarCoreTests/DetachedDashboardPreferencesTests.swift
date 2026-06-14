import CoreGraphics
import PlaidBarCore
import Testing

@Suite("Detached dashboard preferences (AND-384)")
struct DetachedDashboardPreferencesTests {
    @Test("Storage keys, autosave name, and window title are stable identifiers")
    func stableIdentifiers() {
        // These strings are persisted to UserDefaults / read by VoiceOver, so
        // changing them silently is a breaking change. Pin them.
        #expect(DetachedDashboardPreferences.detachedStorageKey == "dashboard.detached")
        #expect(DetachedDashboardPreferences.frameAutosaveName == "VaultPeekDetachedDashboard")
        #expect(DetachedDashboardPreferences.windowTitle == "VaultPeek Dashboard")
    }

    @Test("Default content size matches the popover's two-column footprint")
    func defaultContentSize() {
        // A freshly detached window opens at the same width the popover uses with
        // no account selected (two-column) and the realistic popover height.
        #expect(DetachedDashboardPreferences.defaultContentWidth == PopoverGeometry.width(for: .twoColumn))
        #expect(
            DetachedDashboardPreferences.defaultContentHeight
                == CGFloat(DashboardOverviewHeightBudget.realisticPopoverHeight)
        )
        #expect(DetachedDashboardPreferences.defaultContentSize.width == DetachedDashboardPreferences.defaultContentWidth)
        #expect(DetachedDashboardPreferences.defaultContentSize.height == DetachedDashboardPreferences.defaultContentHeight)
    }

    @Test("Minimum content width keeps the rail plus a usable dashboard")
    func minContentWidth() {
        // The fixed rail + divider + the flexible center's floor — so the Wealth
        // Summary rail and a legible dashboard always fit when resized small.
        let expected = PopoverGeometry.railWidth
            + PopoverGeometry.dividerWidth
            + PopoverGeometry.minDashboardWidth
        #expect(DetachedDashboardPreferences.minContentWidth == expected)
        #expect(DetachedDashboardPreferences.minContentSize.width == expected)
        #expect(DetachedDashboardPreferences.minContentSize.height == DetachedDashboardPreferences.minContentHeight)
    }

    @Test("Minimum size never exceeds the default size")
    func minNeverExceedsDefault() {
        // A window can always open at its default and still be shrinkable, so the
        // floor must be ≤ the default in both dimensions.
        #expect(DetachedDashboardPreferences.minContentWidth <= DetachedDashboardPreferences.defaultContentWidth)
        #expect(DetachedDashboardPreferences.minContentHeight <= DetachedDashboardPreferences.defaultContentHeight)
    }

    @Test("Outside a snapshot render, the persisted detach intent is honored")
    func resolvedDetachedIntentHonorsStoredValue() {
        // Normal launches mirror exactly what the Settings toggle persisted,
        // defaulting to docked when the key has never been written.
        #expect(DetachedDashboardPreferences.resolvedDetachedIntent(storedValue: true, isRenderingSnapshot: false))
        #expect(!DetachedDashboardPreferences.resolvedDetachedIntent(storedValue: false, isRenderingSnapshot: false))
        #expect(!DetachedDashboardPreferences.resolvedDetachedIntent(storedValue: nil, isRenderingSnapshot: false))
    }

    @Test("A snapshot render always resolves to docked, ignoring host defaults")
    func resolvedDetachedIntentForcesDockedDuringSnapshot() {
        // The renderer captures the popover; a host/CI machine with
        // `dashboard.detached = true` must not spawn the floating window or
        // intercept the popover-open path. False wins regardless of stored value.
        #expect(!DetachedDashboardPreferences.resolvedDetachedIntent(storedValue: true, isRenderingSnapshot: true))
        #expect(!DetachedDashboardPreferences.resolvedDetachedIntent(storedValue: false, isRenderingSnapshot: true))
        #expect(!DetachedDashboardPreferences.resolvedDetachedIntent(storedValue: nil, isRenderingSnapshot: true))
    }
}
