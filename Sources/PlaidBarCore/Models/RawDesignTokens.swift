import Foundation

// MARK: - Raw design tokens (Gate-0 doctrine, AND-979)
//
// Pure, `Sendable`, SwiftUI-free numeric values shared by the popover-scale
// (`Sources/PlaidBar/Theme/DesignTokens.swift`) and window-scale
// (`Sources/PlaidBar/Theme/WindowMetrics.swift`) token layers, following the
// same Core-owns-the-value / app-bridges-to-SwiftUI split already used by
// `AppAccentColor`/`AppAccentSwatch` (`AppearancePreferences.swift`) for the
// resolved accent color. Colors stay `Color`-typed and app-target-only —
// they are dynamic system colors that must resolve per-appearance / Increase
// Contrast at draw time, not frozen RGB values — so only numerics move here.
//
// This is the additive first step of the redesign token migration: nothing
// in the app target consumes these yet (Epic 1, AND-980). The window-scale
// `WindowMetrics.md`/`.lg` (16/20) already numerically match `cardPadding`/
// `cardGap` below; `RawRadius` is the one genuine numeric change (adopts the
// redesign's clean 3-role ladder, replacing the app's two disagreeing
// "panel" radii — `Radius.panel = 8` vs `SurfaceTokens.panelCornerRadius = 7`).

/// The 8pt-grid spacing scale shared across popover and window surfaces.
/// `cardGap` is strictly greater than `cardPadding` by design — separation
/// between sibling cards comes from spacing, not from strokes or nested
/// chrome, so a dense grid still reads as distinct surfaces.
public enum RawSpacing: Sendable {
    public static let xxs: Double = 2
    public static let xs: Double = 4
    public static let sm: Double = 8
    public static let md: Double = 12
    /// The one intra-card content inset. Matches `WindowMetrics.md` today.
    public static let cardPadding: Double = 16
    /// The one inter-card gap. Matches `WindowMetrics.lg` today. Always
    /// greater than `cardPadding` — see `RawTokenInvariantTests`.
    public static let cardGap: Double = 20
    public static let xxl: Double = 32
}

/// The corner-radius ladder: three roles, no more. Adopts the redesign's
/// scale, which also resolves the app's existing internal disagreement
/// between `Radius.panel` (8) and `SurfaceTokens.panelCornerRadius` (7).
public enum RawRadius: Sendable {
    /// Heatmap cells, tiny chips.
    public static let cell: Double = 3
    /// Rows, buttons, hover washes, segmented filters, badges.
    public static let control: Double = 7
    /// Cards, panels, popover content, sheets.
    public static let card: Double = 12
}

/// Fixed-frame sizes so a visual role renders at the same size everywhere.
/// Values already match the app's existing `Sizing` enum — centralized here
/// so both token layers read one source instead of two independently-tuned
/// copies.
public enum RawSizing: Sendable {
    public static let iconInline: Double = 16
    public static let iconNav: Double = 20
    public static let iconChip: Double = 28
    public static let statusDot: Double = 8
    /// The macOS pointer-target floor for borderless glyph controls — not
    /// the 44pt touch-input minimum, which would wreck desktop density.
    public static let pointerTargetMin: Double = 28
    public static let rowMinHeight: Double = 44
}

/// Raw animation durations/response values. `Animation` itself is a SwiftUI
/// type and stays app-target-only (`MotionTokens.animation(_:reduceMotion:)`
/// wraps these); only the numeric curve parameters live in Core so they can
/// be asserted here without an app-target test dependency.
public enum RawMotionDurations: Sendable {
    /// Hover, press, chip toggles.
    public static let micro: Double = 0.12
    /// Selection, filter swaps, disclosure, banner entrances.
    public static let standard: Double = 0.2
    /// Spring response for drill-in/fly-out expansion.
    public static let contentResponse: Double = 0.3
    /// Spring damping fraction for drill-in/fly-out expansion.
    public static let contentDamping: Double = 0.85
    /// Once-per-appearance chart reveal.
    public static let chartReveal: Double = 0.55
}
