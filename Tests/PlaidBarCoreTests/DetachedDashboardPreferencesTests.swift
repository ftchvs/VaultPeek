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

    @Test("Default content size opens the full three-column workspace")
    func defaultContentSize() {
        // The inspector column is always present, so a freshly detached window
        // opens at the full three-column width (and the realistic popover height)
        // — wide enough to show all three columns without clipping the inspector.
        #expect(DetachedDashboardPreferences.defaultContentWidth == PopoverGeometry.width(for: .threeColumn))
        #expect(
            DetachedDashboardPreferences.defaultContentHeight
                == CGFloat(DashboardOverviewHeightBudget.realisticPopoverHeight)
        )
        #expect(DetachedDashboardPreferences.defaultContentSize.width == DetachedDashboardPreferences.defaultContentWidth)
        #expect(DetachedDashboardPreferences.defaultContentSize.height == DetachedDashboardPreferences.defaultContentHeight)
    }

    @Test("Minimum content width keeps the rail, a usable dashboard, and the inspector")
    func minContentWidth() {
        // The inspector column is always present, so the floor reserves it too:
        // rail + divider + center floor + divider + inspector — the full
        // three-column minimum, so nothing clips when the window is resized small.
        let expected = PopoverGeometry.railWidth
            + PopoverGeometry.dividerWidth
            + PopoverGeometry.minDashboardWidth
            + PopoverGeometry.dividerWidth
            + PopoverGeometry.railWidth
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
