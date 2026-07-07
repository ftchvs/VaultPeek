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
// Liquid Glass goes on *chrome*, not data: a `WindowSection`'s card
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

// MARK: - Hero metric grid

/// The hero-row grid for a destination's headline metric tiles.
///
/// `LazyVGrid` with `.adaptive` columns allocates as many ≥`heroTileMinWidth`
/// columns as *fit the width*, regardless of how many tiles exist — with three
/// tiles in a four-column-wide canvas that leaves a phantom empty fourth slot
/// (visible dead space), and in a two-column-wide canvas the row wraps 2+1 with
/// a hole. This grid instead measures its width and clamps the column count to
/// `min(itemCount, whatFits)`, with each column flexible — so the tiles always
/// share the full row, and the row still wraps on genuinely narrow windows.
struct HeroMetricGrid<Content: View>: View {
    /// How many tiles the content contains (columns never exceed this).
    let itemCount: Int
    @ViewBuilder var content: Content

    @State private var availableWidth: CGFloat = 0

    private var columns: [GridItem] {
        let spacing = WindowMetrics.lg
        let fits: Int
        if availableWidth <= 0 {
            fits = itemCount // first layout pass: assume one row
        } else {
            fits = Int((availableWidth + spacing) / (WindowMetrics.heroTileMinWidth + spacing))
        }
        let count = max(1, min(itemCount, fits))
        return Array(repeating: GridItem(.flexible(), spacing: spacing), count: count)
    }

    var body: some View {
        LazyVGrid(columns: columns, alignment: .leading, spacing: WindowMetrics.lg) {
            content
        }
        .onGeometryChange(for: CGFloat.self) { proxy in
            proxy.size.width
        } action: { width in
            availableWidth = width
        }
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
    /// Optional "where from / how fresh / what excluded" provenance for the figure
    /// (AND-641). When set, an info affordance is shown beside the label; tapping it
    /// explains the number's sources, freshness, and exclusions. Already
    /// privacy-mask-aware (built masked when values are hidden).
    var provenance: FigureProvenance?

    var body: some View {
        VStack(alignment: .leading, spacing: WindowMetrics.xs) {
            HStack(alignment: .firstTextBaseline, spacing: WindowMetrics.xs) {
                // The figure (label + value + detail) reads as one VoiceOver
                // element; the provenance affordance, when present, stays a
                // separately-focusable control beside it (AND-641).
                figure
                    .accessibilityElement(children: .ignore)
                    .accessibilityLabel(accessibilityLabel)

                if let provenance {
                    Spacer(minLength: WindowMetrics.xs)
                    ProvenancePopoverButton(provenance: provenance)
                }
            }
        }
        .padding(WindowMetrics.md)
        .frame(maxWidth: .infinity, minHeight: 76, alignment: .leading)
        .windowHeroSurface(accent: accent)
        .accessibilityElement(children: .contain)
    }

    private var figure: some View {
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
        .frame(maxWidth: .infinity, alignment: .leading)
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
        // Data stays solid (glass on chrome, not data): a window card
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
    /// ``WindowHeroMetricTile``. Data surfaces stay solid; glass is
    /// reserved for the shell chrome applied at the scene/shell level.
    func windowCardSurface() -> some View {
        modifier(WindowCardSurface())
    }
}

// MARK: - Window hero surface

/// A higher-presence card surface for the dashboard hero metrics (AND-726). The
/// heroes carry the screen's most important numbers, so they earn more weight
/// than a plain section card: a slightly stronger solid fill, an accent-tinted
/// hairline, and a leading accent **rail** keyed to the metric's meaning
/// (positive / warning / brand). The rail and tint *reinforce* the existing
/// glyph + label/detail text; meaning is never carried by color alone, and the
/// rail is hidden from VoiceOver (ACCESSIBILITY.md). Stays solid (glass is
/// chrome, not data) and is unchanged under Reduce Transparency.
private struct WindowHeroSurface: ViewModifier {
    let accent: Color
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency

    func body(content: Content) -> some View {
        let shape = RoundedRectangle(cornerRadius: WindowMetrics.cardCornerRadius)
        content
            .background(.quaternary.opacity(reduceTransparency ? 1.0 : 0.85), in: shape)
            .overlay {
                shape.strokeBorder(accent.opacity(0.22), lineWidth: 1)
            }
            .overlay(alignment: .leading) {
                Capsule(style: .continuous)
                    .fill(accent)
                    .frame(width: 3)
                    .padding(.vertical, WindowMetrics.sm)
                    .padding(.leading, WindowMetrics.xs)
                    .accessibilityHidden(true)
            }
            .clipShape(shape)
    }
}

extension View {
    /// The higher-presence hero-metric surface (accent rail + tinted hairline).
    /// See ``WindowHeroSurface``.
    func windowHeroSurface(accent: Color) -> some View {
        modifier(WindowHeroSurface(accent: accent))
    }
}

#if canImport(PreviewsMacros)
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
#endif
