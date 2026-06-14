import CoreGraphics

/// Pure, `Sendable` configuration for the detached (floating-window) dashboard
/// mode (AND-384): UserDefaults keys, the default content size, and the
/// clamp that keeps a restored frame size sane.
///
/// Kept in `PlaidBarCore` so the storage keys and sizing math are a single
/// source of truth shared by the SwiftUI views (`MainPopover`, `SettingsView`),
/// the app scene (`PlaidBarApp`), and the AppKit window controller
/// (`DetachedDashboardWindowController`), and so the size derivation stays
/// unit-testable without importing AppKit.
public enum DetachedDashboardPreferences {
    /// `@AppStorage` key for the user preference that the dashboard should live
    /// in a floating desktop window instead of the menu-bar popover. This is the
    /// durable intent; `AppState.isDashboardDetached` mirrors it at runtime.
    public static let detachedStorageKey = "dashboard.detached"

    /// Resolves the detached intent to apply at launch from the persisted value.
    ///
    /// A headless snapshot render must ignore any persisted intent: on a host/CI
    /// machine where `dashboard.detached = true`, honoring it would spawn the
    /// floating window *and* make the scene intercept the renderer's
    /// `isPopoverPresented = true` (snapping it back to false), so the popover
    /// never opens and the wrong window — or none — is captured. Returns `false`
    /// during a snapshot render regardless of the stored value; otherwise returns
    /// the stored value, defaulting to `false` when unset.
    public static func resolvedDetachedIntent(storedValue: Bool?, isRenderingSnapshot: Bool) -> Bool {
        guard !isRenderingSnapshot else { return false }
        return storedValue ?? false
    }

    /// `frameAutosaveName` for the floating panel. AppKit persists the panel's
    /// origin and size under this name in the standard user defaults, so the
    /// window reopens where the user last left it across launches.
    public static let frameAutosaveName = "VaultPeekDetachedDashboard"

    /// Accessibility / window title for the floating panel. Read by VoiceOver and
    /// shown in the window menu and Mission Control.
    public static let windowTitle = "VaultPeek Dashboard"

    /// Default content width of the floating panel before any persisted frame is
    /// restored: the popover's two-column base (rail + divider + dashboard), so
    /// the detached window opens at the same width the popover uses with no
    /// account selected.
    public static var defaultContentWidth: CGFloat {
        PopoverGeometry.width(for: .twoColumn)
    }

    /// Default content height of the floating panel before any persisted frame is
    /// restored: the realistic popover height budget, so a freshly detached
    /// window matches the popover's vertical footprint.
    public static var defaultContentHeight: CGFloat {
        CGFloat(DashboardOverviewHeightBudget.realisticPopoverHeight)
    }

    /// Minimum content width the floating panel may be resized to: the
    /// two-column minimum (fixed rail + the flexible center's floor), so the
    /// Wealth Summary rail and a usable dashboard always stay legible.
    public static var minContentWidth: CGFloat {
        minContentWidth(isInspectorOpen: false)
    }

    /// Minimum content width the floating panel may be resized to for the current
    /// inspector state. When the trailing account inspector is open the floor
    /// must include its fixed-width column, or a window resized to the two-column
    /// minimum would clip the inspector the moment an account is selected
    /// (AND-384/405). Shares `PopoverGeometry` so the panel's `contentMinSize`
    /// and `MainPopover`'s SwiftUI `frame(minWidth:)` agree on the floor.
    public static func minContentWidth(isInspectorOpen: Bool) -> CGFloat {
        PopoverGeometry.detachedMinContentWidth(isInspectorOpen: isInspectorOpen)
    }

    /// Minimum content height the floating panel may be resized to: enough for
    /// the header, status strip, and a couple of account rows before the body
    /// scrolls.
    public static let minContentHeight: CGFloat = 360

    /// The default content size used when the panel has no persisted frame yet.
    public static var defaultContentSize: CGSize {
        CGSize(width: defaultContentWidth, height: defaultContentHeight)
    }

    /// The minimum content size enforced as the panel's `contentMinSize`.
    public static var minContentSize: CGSize {
        CGSize(width: minContentWidth, height: minContentHeight)
    }
}
