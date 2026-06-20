import PlaidBarCore
import SwiftUI

// MARK: - Window-scale shared desktop components (AND-624)
//
// The reference-quality building blocks the window-first destinations compose
// from: a titled section card and a hero metric tile, both at the window
// (desk-distance) scale defined in ``WindowMetrics`` / ``WindowTypography``.
// They set the design language the propagation pass (the other 8 destinations)
// will follow.
//
// These are pure layout/presentation — they hold no model logic and read no
// `AppState`; data and Core presentations are passed in by the call site. That
// keeps them reusable across destinations and trivially previewable.
//
// Liquid Glass goes on *chrome*, not data (ADR-001): a `WindowSection`'s card
// uses a quiet, solid hierarchical fill so the figures inside stay crisp and
// legible. Section separation comes from spacing and the title, with a hairline
// stroke for definition — never from a translucent wash behind the numbers.

// MARK: - Window section card

/// A titled content card for a window-first canvas: a `title3` section header
/// (with an optional trailing accessory) above its content, on a quiet rounded
/// surface at window scale.
///
/// The header is read as one VoiceOver element naming the section; the content
/// stays separately navigable. Meaning is never color-only — the title text
/// carries the section's identity, accessories carry their own labels.
struct WindowSection<Content: View, Accessory: View>: View {
    let title: String
    /// Optional SF Symbol shown before the title (shape, not color, for meaning).
    var systemImage: String?
    /// A trailing header accessory (a count, a small control). Carries its own
    /// accessibility; folded into nothing here so it stays separately reachable.
    @ViewBuilder var accessory: () -> Accessory
    @ViewBuilder var content: () -> Content

    init(
        _ title: String,
        systemImage: String? = nil,
        @ViewBuilder accessory: @escaping () -> Accessory = { EmptyView() },
        @ViewBuilder content: @escaping () -> Content
    ) {
        self.title = title
        self.systemImage = systemImage
        self.accessory = accessory
        self.content = content
    }

    var body: some View {
        VStack(alignment: .leading, spacing: WindowMetrics.md) {
            HStack(alignment: .firstTextBaseline, spacing: WindowMetrics.xs) {
                Label {
                    Text(title)
                        .windowCardTitle()
                } icon: {
                    if let systemImage {
                        Image(systemName: systemImage)
                            .foregroundStyle(.secondary)
                    }
                }
                .labelStyle(.titleAndIcon)
                .accessibilityAddTraits(.isHeader)

                Spacer(minLength: WindowMetrics.sm)

                accessory()
            }

            content()
        }
        .padding(WindowMetrics.md)
        .frame(maxWidth: .infinity, alignment: .leading)
        .windowCardSurface()
        .accessibilityElement(children: .contain)
    }
}

// MARK: - Hero metric tile

/// A single hero metric in the dashboard's top row: a large tabular figure with
/// a label above it and optional supporting detail below. The figure uses the
/// ``WindowHeroMetric`` role (scaled, monospaced); the label and detail give the
/// number meaning in text, so the tile never relies on color or position alone
/// to communicate (ACCESSIBILITY.md).
struct WindowHeroMetricTile: View {
    let label: String
    /// The already-formatted, privacy-mask-aware value string the figure shows.
    let value: String
    var systemImage: String?
    /// Optional supporting line under the figure (e.g. "across 6 accounts").
    var detail: String?
    /// Optional emphasis tint for the leading glyph only — never the figure, so
    /// meaning is carried by the label/detail text, not the color.
    var accent: Color = .secondary
    /// Rolls the figure on change (disabled under Reduce Motion). Pass the live
    /// `reduceMotion` environment value.
    var reduceMotion: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: WindowMetrics.xs) {
            Label {
                Text(label)
                    .windowSupportingText()
                    .textCase(.uppercase)
            } icon: {
                if let systemImage {
                    Image(systemName: systemImage)
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(accent)
                }
            }
            .labelStyle(.titleAndIcon)

            Text(value)
                .windowHeroMetric()
                .rollingTabularNumber(value, reduceMotion: reduceMotion)
                .foregroundStyle(AppearanceTextColors.primary)
                .lineLimit(1)
                .minimumScaleFactor(0.6)

            if let detail {
                Text(detail)
                    .windowSupportingText()
                    .lineLimit(2)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .padding(WindowMetrics.md)
        .frame(maxWidth: .infinity, minHeight: 96, alignment: .leading)
        .windowCardSurface()
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(accessibilityLabel)
    }

    private var accessibilityLabel: String {
        var parts = ["\(label): \(value)"]
        if let detail { parts.append(detail) }
        return parts.joined(separator: ". ")
    }
}

// MARK: - Window card surface

private struct WindowCardSurface: ViewModifier {
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency

    func body(content: Content) -> some View {
        let shape = RoundedRectangle(cornerRadius: WindowMetrics.cardCornerRadius)
        // Data stays solid (ADR-001 — glass on chrome, not data): a window card
        // backs its figures with a quiet hierarchical `.quaternary` fill so the
        // tabular numbers read crisply, rather than a translucent wash. Under
        // Reduce Transparency the same solid fill is used (it is already solid),
        // so no contrast regression. Separation is the hairline stroke + spacing.
        content
            .background(.quaternary.opacity(reduceTransparency ? 0.9 : 0.6), in: shape)
            .overlay {
                shape.stroke(Color.primary.opacity(0.07), lineWidth: 1)
            }
    }
}

extension View {
    /// The quiet, solid window-scale card surface used by ``WindowSection`` and
    /// ``WindowHeroMetricTile``. Data surfaces stay solid (ADR-001); glass is
    /// reserved for the shell chrome applied at the scene/shell level.
    func windowCardSurface() -> some View {
        modifier(WindowCardSurface())
    }
}

#Preview("Window section") {
    VStack(spacing: WindowMetrics.lg) {
        HStack(spacing: WindowMetrics.lg) {
            WindowHeroMetricTile(
                label: "Net worth",
                value: "$48,250",
                systemImage: "chart.line.uptrend.xyaxis",
                detail: "across 6 accounts",
                accent: SemanticColors.brand,
                reduceMotion: false
            )
            WindowHeroMetricTile(
                label: "Safe to spend",
                value: "$1,240",
                systemImage: "checkmark.shield",
                detail: "through end of month",
                accent: SemanticColors.positive,
                reduceMotion: false
            )
        }
        WindowSection("Accounts", systemImage: "building.columns") {
            Text("3 accounts")
                .windowSupportingText()
        } content: {
            Text("Account rows go here")
                .windowBodyText()
        }
    }
    .padding(WindowMetrics.canvasMargin)
    .frame(width: 720)
}
