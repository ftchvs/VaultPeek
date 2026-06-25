import PlaidBarCore
import SwiftUI

/// A small, reusable "where did this number come from?" affordance (AND-641).
///
/// Renders an info glyph next to a high-trust derived figure; tapping it opens a
/// `.popover` that explains the figure's **sources** (which accounts), **freshness**
/// (how recently the data synced), and **exclusions** (what was deliberately left
/// out). All content comes from a pure ``FigureProvenance`` built in `PlaidBarCore`
/// — this view is presentation only.
///
/// Accessibility: the button is keyboard-focusable (a plain `Button`), carries a
/// descriptive VoiceOver label, and its meaning rides on the glyph SHAPE +
/// text, never color (ACCESSIBILITY.md). The popover body honors Privacy Mask —
/// the caller passes an already-masked ``FigureProvenance`` so no real values are
/// rendered while masked.
struct ProvenancePopoverButton: View {
    let provenance: FigureProvenance

    @State private var isPresented = false

    var body: some View {
        Button {
            isPresented.toggle()
        } label: {
            Image(systemName: "info.circle")
                .font(.caption.weight(.semibold))
                .foregroundStyle(.secondary)
                .accessibilityHidden(true)
        }
        .buttonStyle(.plain)
        .help("Where this number comes from")
        .accessibilityLabel("\(provenance.figureTitle): where this number comes from")
        .accessibilityHint("Shows sources, freshness, and what's excluded.")
        .popover(isPresented: $isPresented, arrowEdge: .bottom) {
            ProvenancePopoverContent(provenance: provenance)
        }
    }
}

/// The popover body for ``ProvenancePopoverButton``. Pure presentation over a
/// ``FigureProvenance``.
private struct ProvenancePopoverContent: View {
    let provenance: FigureProvenance

    var body: some View {
        VStack(alignment: .leading, spacing: Spacing.sm) {
            header

            Text(provenance.derivation)
                .microText()
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)

            freshnessRow

            if !provenance.sources.isEmpty {
                section(title: "Sources", systemImage: "tray.full") {
                    ForEach(provenance.sources) { source in
                        sourceRow(source)
                    }
                }
            }

            if !provenance.exclusions.isEmpty {
                section(title: "Not included", systemImage: "minus.circle") {
                    ForEach(Array(provenance.exclusions.enumerated()), id: \.offset) { _, line in
                        Label {
                            Text(line)
                                .microText()
                                .foregroundStyle(.secondary)
                                .fixedSize(horizontal: false, vertical: true)
                        } icon: {
                            Image(systemName: "circle.fill")
                                .font(.system(size: 4))
                                .foregroundStyle(.tertiary)
                        }
                        .accessibilityElement(children: .combine)
                    }
                }
            }
        }
        .padding(Spacing.md)
        .frame(width: 280, alignment: .leading)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(provenance.accessibilitySummary)
    }

    private var header: some View {
        HStack(spacing: Spacing.xs) {
            Text(provenance.figureTitle)
                .font(.subheadline.weight(.semibold))

            Spacer(minLength: Spacing.sm)

            // Local-only reassurance — paired glyph + text, never color alone.
            Label(provenance.localOnlyBadge, systemImage: "lock.laptopcomputer")
                .microText()
                .foregroundStyle(.secondary)
                .accessibilityLabel("\(provenance.localOnlyBadge), computed on this device.")
        }
    }

    private var freshnessRow: some View {
        Label {
            Text(provenance.freshnessText)
                .microText()
                .foregroundStyle(.secondary)
        } icon: {
            Image(systemName: "clock")
                .font(.caption2.weight(.semibold))
                .foregroundStyle(.secondary)
        }
        .accessibilityElement(children: .combine)
    }

    private func section(
        title: String,
        systemImage: String,
        @ViewBuilder content: () -> some View
    ) -> some View {
        VStack(alignment: .leading, spacing: Spacing.xs) {
            Label(title, systemImage: systemImage)
                .sectionTitle()
                .foregroundStyle(.secondary)
                .accessibilityAddTraits(.isHeader)

            content()
        }
    }

    private func sourceRow(_ source: FigureProvenance.Source) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: Spacing.sm) {
            Label {
                Text(source.label)
                    .microText()
                    .lineLimit(1)
            } icon: {
                Image(systemName: source.systemImage)
                    .font(.caption2.weight(.medium))
                    .foregroundStyle(.secondary)
            }

            Spacer(minLength: Spacing.sm)

            if let value = source.value {
                Text(value)
                    .font(.caption.weight(.semibold))
                    .monospacedDigit()
                    .foregroundStyle(.primary)
                    .lineLimit(1)
            }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(source.accessibilityLabel)
    }
}
