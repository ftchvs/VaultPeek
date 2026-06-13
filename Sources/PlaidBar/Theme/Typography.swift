import SwiftUI

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
struct DisplayBalance: ViewModifier {
    func body(content: Content) -> some View {
        content
            .font(.system(size: 30, weight: .semibold))
            .monospacedDigit()
    }
}

/// Level 1 — Hero: legacy 28pt rounded balance header (detail surfaces).
struct HeroBalance: ViewModifier {
    func body(content: Content) -> some View {
        content
            .font(.system(size: 28, weight: .bold, design: .rounded))
            .monospacedDigit()
    }
}

/// Level 2 — Title: section headers (ACCOUNTS, 365D SPEND). Medium weight:
/// labels are quiet; hierarchy comes from casing and opacity, not boldness.
struct SectionTitle: ViewModifier {
    func body(content: Content) -> some View {
        content
            .font(.caption.weight(.medium))
            .textCase(.uppercase)
    }
}

/// Data — row amounts and tabular figures. Semibold, never bold.
struct DataText: ViewModifier {
    func body(content: Content) -> some View {
        content
            .font(.callout.weight(.semibold))
            .monospacedDigit()
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
