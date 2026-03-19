import SwiftUI

// MARK: - Type Scale ViewModifiers

/// Level 1 — Hero: Net balance header
struct HeroBalance: ViewModifier {
    func body(content: Content) -> some View {
        content
            .font(.system(size: 28, weight: .bold, design: .rounded))
            .monospacedDigit()
    }
}

/// Level 2 — Title: Section headers (BANK ACCOUNTS, CREDIT CARDS)
struct SectionTitle: ViewModifier {
    func body(content: Content) -> some View {
        content
            .font(.caption.weight(.semibold))
            .textCase(.uppercase)
    }
}

/// Level 4 — Detail: Masks, categories, dates
struct DetailText: ViewModifier {
    func body(content: Content) -> some View {
        content
            .font(.caption)
            .foregroundStyle(.secondary)
    }
}

/// Level 5 — Micro: Pending badge, percentages
struct MicroText: ViewModifier {
    func body(content: Content) -> some View {
        content
            .font(.caption2.weight(.medium))
    }
}

// MARK: - View Extensions

extension View {
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
