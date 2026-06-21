import SwiftUI

// MARK: - Window-Scale Design Foundation (AND-624)
//
// The menu-bar popover is a *compact*, arm's-length surface: its spacing
// (``Spacing``) and type roles (``Typography``) are tuned for a dense, ~360pt
// glance read at close range. The window-first workspace (ADR-001) is a
// *desk-distance* surface — a resizable `Window` the user works in like Mail or
// Finder — so it wants more generous spacing, a taller type ramp, and section
// heads that the popover's caption-scale titles cannot carry.
//
// `WindowMetrics` / `WindowTypography` are the **additive** window-scale layer.
// They live alongside the popover tokens and never replace them: the popover
// keeps reading ``Spacing`` / ``Typography`` byte-for-byte (flag-OFF parity),
// while the window-first surfaces read these. Apple's *Designing for macOS*
// guidance — "more content, fewer nested levels, less modality, comfortable
// density" — maps directly onto this split: comfortable density at the window,
// compact density at the glance.
//
// Never-color-alone (ACCESSIBILITY.md): like ``Typography``, this file controls
// only size, weight, and tabular alignment. It never encodes financial meaning
// (balance / risk / utilization / trend) through color — direction and severity
// always carry a text or glyph backup at the call site.

// MARK: - Window-scale spacing

/// Desk-distance spacing for the window-first workspace. A coarser step than the
/// popover's compact 8pt grid (``Spacing``): the window has room to breathe, so
/// section gaps and card padding are larger and the rhythm reads as "comfortable
/// density" (Apple HIG) rather than the glance's tight pack.
///
/// Kept deliberately separate from ``Spacing`` so tuning the window never risks
/// shifting the popover. Values stay on the 4pt sub-grid so they compose cleanly
/// with the popover tokens where the two meet (e.g. a re-hosted popover card
/// inside a window section).
enum WindowMetrics {
    // MARK: Spacing scale (8pt grid, coarser steps than the popover's Spacing)
    //
    // Tuned up for desk-distance "comfortable density" (AND-624): a calm,
    // spacious macOS 26 desktop dashboard reads as breathing room first, dense
    // figures second. Steps sit on the 8pt grid (with one 4pt half-step for the
    // tightest inner spacing) so cards align to a single even rhythm — the gap
    // *between* cards is never smaller than the gap *inside* a card, which is
    // what makes a grid read as separated rather than crammed.

    /// Tight inner spacing — label↔value, icon↔text within a metric tile.
    static let xs: CGFloat = 8
    /// Within-card spacing — rows inside a card, label↔figure clusters.
    static let sm: CGFloat = 12
    /// Card content padding and header↔body spacing (≥20pt: generous interior
    /// breathing room so figures don't crowd the card edge).
    static let md: CGFloat = 20
    /// Between cards within a column, and section header↔content (≥20pt: cards
    /// read as distinctly separated surfaces, not a stuck-together stack).
    static let lg: CGFloat = 20
    /// Between major sections of a canvas (hero row ↔ the column grid).
    static let xl: CGFloat = 32
    /// The gap between the two canvas columns. Wider than the inter-card gap so
    /// the two columns read as two distinct regions, not one run-on grid (≥24pt).
    static let columnGap: CGFloat = 28
    /// Outer canvas margin — the window's content inset from its chrome.
    static let canvasMargin: CGFloat = 28

    // MARK: Layout

    /// Corner radius for window-scale cards. Larger than the popover's
    /// ``Radius/panel`` (8) so cards read as comfortable desk-distance surfaces.
    static let cardCornerRadius: CGFloat = 14

    /// The minimum width a metric/content card may shrink to before the grid
    /// reflows to fewer columns. Tuned so a hero tile keeps its large figure
    /// readable and a content card keeps its section header on one line.
    static let cardMinWidth: CGFloat = 260

    /// The content width below which a two-column canvas stacks into one column
    /// (a narrow window). Mirrors the popover's behavior of dropping its side
    /// rail when space is tight, at the window's larger scale.
    static let twoColumnBreakpoint: CGFloat = 820

    /// The hero metrics row's minimum tile width before it wraps. Below this the
    /// hero figures lose their tabular legibility, so the row reflows.
    static let heroTileMinWidth: CGFloat = 240

    /// The minimum height the hero activity heatmap card reserves for its grid,
    /// so the signature year-scale instrument reads as a prominent, full-width
    /// hero at the top of the Activity column rather than a small lost strip.
    static let heatmapHeroMinHeight: CGFloat = 132
}

// MARK: - Window-scale type ramp

// The window type ramp is taller than the popover's caption-scale roles: a
// `largeTitle` page identity, `title2`/`title3` section heads, and a dedicated
// hero-metric role for the dashboard's big figures. The text-style roles are
// built on semantic SwiftUI text styles; the hero-metric figure uses a fixed
// point size because macOS has no Dynamic Type. Numeric roles apply
// `.monospacedDigit()` on the font value so tabular columns stay aligned under
// Liquid Glass.

/// Window page identity — the workspace/section title at desk distance.
/// `largeTitle`, bold. Used for a canvas's lead heading where one is shown.
struct WindowLargeTitle: ViewModifier {
    func body(content: Content) -> some View {
        content.font(.largeTitle.weight(.bold))
    }
}

/// Primary section head inside a window canvas (`title2`, semibold). One step
/// down from the page identity; groups several cards under one banner.
struct WindowSectionTitle: ViewModifier {
    func body(content: Content) -> some View {
        content.font(.title2.weight(.semibold))
    }
}

/// Card / sub-section head (`title3`, semibold). The workhorse heading for a
/// single card in the dashboard grid ("Accounts", "Recent activity").
struct WindowCardTitle: ViewModifier {
    func body(content: Content) -> some View {
        content.font(.title3.weight(.semibold))
    }
}

/// Body text at window scale (`.body`). The reading size for descriptions and
/// list rows inside a window card — larger than the popover's `.callout`/`.caption`.
struct WindowBodyText: ViewModifier {
    func body(content: Content) -> some View {
        content.font(.body)
    }
}

/// Secondary / supporting label at window scale (`.subheadline`, secondary).
/// Captions, metric labels, and supporting detail inside a card.
struct WindowSupportingText: ViewModifier {
    func body(content: Content) -> some View {
        content
            .font(.subheadline)
            .foregroundStyle(.secondary)
    }
}

/// The dashboard's hero metric figure — the big tabular number in a metric tile
/// (net worth, safe-to-spend, this-month spend). A fixed 38pt point size because
/// macOS has no Dynamic Type (*HIG › Typography › macOS*), with tabular digits so
/// multiple tiles' figures align in a column.
struct WindowHeroMetric: ViewModifier {
    private let size: CGFloat = 38

    func body(content: Content) -> some View {
        content.font(.system(size: size, weight: .semibold, design: .default).monospacedDigit())
    }
}

/// Window-scale tabular figure / data role (DS-4) — the window counterpart to the
/// popover's ``DataText``. `.body`, semibold, with `monospacedDigit()` baked into
/// the font value so any numeric column rendered through this role gets tabular
/// alignment by construction and can't forget it. No `@ScaledMetric` /
/// `.dynamicTypeSize` (macOS has no Dynamic Type — *HIG › Typography › macOS*),
/// and no manual `.tracking` (the system tracks per size automatically).
struct WindowDataText: ViewModifier {
    func body(content: Content) -> some View {
        content.font(.body.weight(.semibold).monospacedDigit())
    }
}

/// Window micro / caption role — column headers and table sub-labels at desk
/// distance. `.caption2`, medium weight: a quiet figure-supporting label one step
/// below ``WindowSupportingText``.
struct WindowFigureCaption: ViewModifier {
    func body(content: Content) -> some View {
        content.font(.caption2.weight(.medium))
    }
}

extension View {
    /// Window page identity (`largeTitle`, bold).
    func windowLargeTitle() -> some View { modifier(WindowLargeTitle()) }

    /// Primary window section head (`title2`, semibold).
    func windowSectionTitle() -> some View { modifier(WindowSectionTitle()) }

    /// Window card / sub-section head (`title3`, semibold).
    func windowCardTitle() -> some View { modifier(WindowCardTitle()) }

    /// Window-scale body text (`.body`).
    func windowBodyText() -> some View { modifier(WindowBodyText()) }

    /// Window-scale secondary / supporting label (`.subheadline`, secondary).
    func windowSupportingText() -> some View { modifier(WindowSupportingText()) }

    /// The dashboard hero metric figure (scaled, tabular). See ``WindowHeroMetric``.
    func windowHeroMetric() -> some View { modifier(WindowHeroMetric()) }

    /// Window-scale tabular figure / data role: body, semibold, tabular digits baked in (DS-4).
    func windowDataText() -> some View { modifier(WindowDataText()) }

    /// Window micro / caption role (`caption2`, medium): column headers & figure sub-labels.
    func windowFigureCaption() -> some View { modifier(WindowFigureCaption()) }
}
