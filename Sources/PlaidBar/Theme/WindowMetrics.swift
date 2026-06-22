import SwiftUI

// MARK: - Window-Scale Design Foundation (AND-624)
//
// The menu-bar popover is a *compact*, arm's-length surface: its spacing
// (``Spacing``) and type roles (``Typography``) are tuned for a dense, ~360pt
// glance read at close range. The window-first workspace is a
// *desk-distance* surface — a resizable `Window` the user works in like Mail or
// Finder — so it wants more generous spacing, a taller type ramp, and section
// heads that the popover's caption-scale titles cannot carry.
//
// `WindowMetrics` / `WindowTypography` are the **additive** window-scale layer.
// They live alongside the popover tokens and never replace them: the popover
// keeps reading ``Spacing`` / ``Typography`` byte-for-byte (flag-OFF parity),
// while the window-first surfaces read these. The window is tuned as a dense,
// RepoBar-style finance instrument (post-1.0): tight card padding, crisp card
// separation (gap > padding), and compact hero figures — high signal, low
// chrome — read at desk distance. (This intentionally supersedes the original
// AND-624 "comfortable density" tuning for a denser, more scannable dashboard.)
//
// Never-color-alone (ACCESSIBILITY.md): like ``Typography``, this file controls
// only size, weight, and tabular alignment. It never encodes financial meaning
// (balance / risk / utilization / trend) through color — direction and severity
// always carry a text or glyph backup at the call site.

// MARK: - Window-scale spacing

/// Desk-distance spacing for the window-first workspace, tuned for RepoBar-style
/// density: tighter than the original AND-624 "comfortable" scale so the dashboard
/// reads as a high-signal finance instrument, but still a step coarser than the
/// popover's compact 8pt grid (``Spacing``) because the window is read at desk
/// distance, not arm's length.
///
/// Kept deliberately separate from ``Spacing`` so tuning the window never risks
/// shifting the popover. Values stay on the 4pt sub-grid so they compose cleanly
/// with the popover tokens where the two meet (e.g. a re-hosted popover card
/// inside a window section).
enum WindowMetrics {
    // MARK: Spacing scale (4pt grid, RepoBar-dense)
    //
    // Tuned for a dense, scannable macOS 26 desktop dashboard: figures and rows
    // first, chrome second. Steps sit on the 4pt grid so cards align to one even
    // rhythm, and the gap *between* cards (``lg``) is kept strictly *greater* than
    // the padding *inside* a card (``md``) — that separation is what lets a dense
    // grid still read as crisply separated surfaces rather than crammed.

    /// Tight inner spacing — label↔value, icon↔text within a metric tile.
    static let xs: CGFloat = 8
    /// Within-card spacing — rows inside a card, label↔figure clusters.
    static let sm: CGFloat = 12
    /// Card content padding and header↔body spacing. Kept strictly tighter than
    /// the inter-card gap (``lg``) so cards read as crisply separated, RepoBar-dense
    /// surfaces rather than one soft run.
    static let md: CGFloat = 16
    /// Between cards within a column, and section header↔content. Strictly greater
    /// than the card padding (``md``) so the grid reads as separated, not crammed.
    static let lg: CGFloat = 20
    /// Between major sections of a canvas (hero row ↔ the column grid).
    static let xl: CGFloat = 24
    /// The gap between the two canvas columns. ≥ the inter-card gap so the two
    /// columns read as two distinct regions, not one run-on grid.
    static let columnGap: CGFloat = 24
    /// Outer canvas margin — the window's content inset from its chrome.
    static let canvasMargin: CGFloat = 20

    // MARK: Layout

    /// Corner radius for window-scale cards. Larger than the popover's
    /// ``Radius/panel`` (8) so cards read as comfortable desk-distance surfaces.
    static let cardCornerRadius: CGFloat = 14

    /// The minimum width a metric/content card may shrink to before the grid
    /// reflows to fewer columns. Tuned so a hero tile keeps its large figure
    /// readable and a content card keeps its section header on one line.
    static let cardMinWidth: CGFloat = 220

    /// The content width below which a two-column canvas stacks into one column
    /// (a narrow window). Mirrors the popover's behavior of dropping its side
    /// rail when space is tight, at the window's larger scale.
    static let twoColumnBreakpoint: CGFloat = 820

    /// The hero metrics row's minimum tile width before it wraps. Below this the
    /// hero figures lose their tabular legibility, so the row reflows.
    static let heroTileMinWidth: CGFloat = 200

    /// The minimum height the hero activity heatmap card reserves for its grid,
    /// so the signature year-scale instrument reads as a prominent, full-width
    /// hero at the top of the Activity column rather than a small lost strip.
    static let heatmapHeroMinHeight: CGFloat = 120
}

// MARK: - Window-scale type ramp

// The window type ramp is taller than the popover's caption-scale roles: a
// `largeTitle` page identity, `title2`/`title3` section heads, and a dedicated
// hero-metric role for the dashboard's big figures. Each role is built on a
// semantic SwiftUI text style so it scales with Dynamic Type automatically
// (AND-515), except the hero-metric figure, which scales its fixed base point
// size via `@ScaledMetric(relativeTo:)` exactly like ``DisplayBalance`` so the
// big number grows with the user's text-size setting instead of staying pinned.
// Numeric roles apply `.monospacedDigit()` on the font value so tabular columns
// stay aligned at every Dynamic Type size and under Liquid Glass.

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
/// (net worth, safe-to-spend, this-month spend). Scales its 30pt base with the
/// user's text-size / accessibility setting via `@ScaledMetric(relativeTo:
/// .largeTitle)` (a plain `.system(size:)` font would not), with tabular digits
/// so multiple tiles' figures align, and the same `.xSmall ... .accessibility3`
/// clamp as ``DisplayBalance`` to stop before the layout-breaking AX4/AX5 steps.
struct WindowHeroMetric: ViewModifier {
    @ScaledMetric(relativeTo: .largeTitle) private var size: CGFloat = 30

    func body(content: Content) -> some View {
        content
            .font(.system(size: size, weight: .semibold, design: .default).monospacedDigit())
            .dynamicTypeSize(.xSmall ... .accessibility3)
    }
}

/// Window-scale tabular data / figure role — the desk-distance counterpart to the
/// popover's ``DataText``. `.body`, semibold, with `.monospacedDigit()` baked into
/// the font value so every amount, count, and percentage in a window card aligns
/// into a tabular column. Centralizing the tabular digits here means a new numeric
/// column physically cannot forget them: replace ad-hoc `.font(.body.weight(...))`
/// + `.monospacedDigit()` on window figures with `.windowDataText()`. Built on the
/// semantic `.body` style, so it scales with the in-app Text Size preference
/// (`AppTextSizeApplier`) exactly like the other window roles.
struct WindowDataText: ViewModifier {
    func body(content: Content) -> some View {
        content
            .font(.body.weight(.semibold).monospacedDigit())
    }
}

/// Window-scale caption / micro label role — the small secondary label for column
/// headers and figure sub-labels in a window card (the desk-distance counterpart
/// to the popover's ``MicroText``). `.caption2`, medium weight. Built on the
/// semantic `.caption2` style (scales with the in-app Text Size preference). Use
/// for column headings and the small label above a figure — not body copy (use
/// ``WindowSupportingText``) or section heads (use ``WindowCardTitle``).
struct WindowFigureCaption: ViewModifier {
    func body(content: Content) -> some View {
        content
            .font(.caption2.weight(.medium))
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

    /// Window-scale tabular data / figure (body, semibold, monospaced digits).
    /// See ``WindowDataText``. Tabular digits are baked in — do not add a separate
    /// `.monospacedDigit()` at the call site.
    func windowDataText() -> some View { modifier(WindowDataText()) }

    /// Window-scale caption / micro label for column headers and figure sub-labels
    /// (`caption2`, medium). See ``WindowFigureCaption``.
    func windowFigureCaption() -> some View { modifier(WindowFigureCaption()) }
}
