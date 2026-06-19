import SwiftUI

// MARK: - Type Scale Notes (AND-515)
//
// Dynamic Type: every modifier here is built on a semantic text style
// (`.largeTitle`, `.title`, `.caption`, `.callout`, `.caption2`) rather than a
// fixed `.system(size:)`, so the type scales with the user's text-size /
// accessibility setting automatically — a `.system(size:)` font would ignore
// Dynamic Type entirely and stay pinned. The two display sizes
// (`DisplayBalance`, `HeroBalance`) additionally clamp the environment to
// `.dynamicTypeSize(.xSmall ... .accessibility3)` so the hero figure grows but
// stops before the layout-breaking AX4/AX5 steps. `monospacedDigit()` is applied
// on the font value (not as a trailing modifier) on numeric surfaces so tabular
// column alignment is preserved at every Dynamic Type size and under the Liquid
// Glass material.
//
// Never-color-alone (ACCESSIBILITY.md): this file controls weight, size, and
// tabular alignment only — it never encodes balance, risk, utilization, sync,
// or trend meaning through color. Direction/severity always carry a text or
// glyph backup at the call site (e.g. signed amounts, "Very high" labels,
// the heatmap legend), which keeps reading correctly over translucent glass
// where foreground/background contrast varies. No change needed here.

// MARK: - Rolling Tabular Numerics

/// Centralized numeric-display modifier (AND-378): monospaced (tabular) digits so
/// decimals align into a column, plus a `.numericText()` content transition that
/// rolls the figure only when it changes (the value-keyed `.animation` does not run
/// on first render, so no "slot machine" on open) and is disabled under Reduce
/// Motion via `MotionTokens.animation` (which returns nil). Pass the exact string
/// the wrapped `Text` displays as `value`.
struct RollingTabularNumber: ViewModifier {
    let value: String
    let reduceMotion: Bool

    func body(content: Content) -> some View {
        content
            .monospacedDigit()
            .contentTransition(.numericText())
            .animation(MotionTokens.animation(MotionTokens.standard, reduceMotion: reduceMotion), value: value)
    }
}

// MARK: - Type Scale ViewModifiers

/// Level 0 — Display: the one hero number per surface (net worth).
/// Standard SF Pro (not rounded) with tabular digits: instrument, not toy.
/// Dynamic Type (AND-515): built on the semantic `.largeTitle` style so the
/// figure actually scales with the user's text-size / accessibility setting
/// (a `.system(size:)` font would ignore it). `.monospacedDigit()` keeps the
/// figures column-aligned at every size; the `.dynamicTypeSize` clamp lets it
/// grow but stops before the layout-breaking AX4/AX5 steps.
struct DisplayBalance: ViewModifier {
    func body(content: Content) -> some View {
        content
            .font(.system(.largeTitle, design: .default).weight(.semibold).monospacedDigit())
            .dynamicTypeSize(.xSmall ... .accessibility3)
    }
}

/// Level 1 — Hero: rounded balance header (detail surfaces).
/// Dynamic Type (AND-515): built on the semantic `.title` style so it scales
/// with text-size; rounded design and tabular digits preserved, capped at
/// `.accessibility3` to stay inside the layout.
struct HeroBalance: ViewModifier {
    func body(content: Content) -> some View {
        content
            .font(.system(.title, design: .rounded).weight(.bold).monospacedDigit())
            .dynamicTypeSize(.xSmall ... .accessibility3)
    }
}

/// Level 2 — Title: section headers (ACCOUNTS, 365D SPEND). Medium weight:
/// labels are quiet; hierarchy comes from casing and opacity, not boldness.
/// Built on the semantic `.caption` style, so it already scales with Dynamic
/// Type (AND-515) — no fixed point size to clamp.
struct SectionTitle: ViewModifier {
    func body(content: Content) -> some View {
        content
            .font(.caption.weight(.medium))
            .textCase(.uppercase)
    }
}

/// Data — row amounts and tabular figures. Semibold, never bold.
/// Built on the semantic `.callout` style so it scales with Dynamic Type
/// (AND-515); `.monospacedDigit()` is applied to the font itself so the
/// tabular alignment survives at every Dynamic Type size.
struct DataText: ViewModifier {
    func body(content: Content) -> some View {
        content
            .font(.callout.weight(.semibold).monospacedDigit())
    }
}

/// Level 3 — Detail: Masks, categories, dates
struct DetailText: ViewModifier {
    func body(content: Content) -> some View {
        content
            .font(.caption)
            .foregroundStyle(.secondary)
    }
}

/// Level 4 — Micro: Pending badge, percentages
struct MicroText: ViewModifier {
    func body(content: Content) -> some View {
        content
            .font(.caption2.weight(.medium))
    }
}

// MARK: - View Extensions

extension View {
    func displayBalance() -> some View {
        modifier(DisplayBalance())
    }

    func dataText() -> some View {
        modifier(DataText())
    }

    /// Monospaced + rolls on value change (never on first appearance; instant under
    /// Reduce Motion). Pass the rendered string. See `RollingTabularNumber`.
    func rollingTabularNumber(_ value: String, reduceMotion: Bool) -> some View {
        modifier(RollingTabularNumber(value: value, reduceMotion: reduceMotion))
    }

    func heroBalance() -> some View {
        modifier(HeroBalance())
    }

    func sectionTitle() -> some View {
        modifier(SectionTitle())
    }

    func detailText() -> some View {
        modifier(DetailText())
    }

    func microText() -> some View {
        modifier(MicroText())
    }
}
