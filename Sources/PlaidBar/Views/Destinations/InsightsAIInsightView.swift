import PlaidBarCore
import SwiftUI

/// The streaming Foundation Models spending-insight surface for the **Insights**
/// destination (Epic 7 / AND-585). A thin renderer over the existing AI engine —
/// it adds no model logic:
///
/// - The headline + evidence + provenance come from ``LocalAIInsightReceipt.make``
///   (the same builder the popover's insight card uses), so the two surfaces can
///   never disagree.
/// - The incremental Foundation Models `@Generable` stream is surfaced reactively:
///   ``AppState/localAIActivitySummaries`` returns the deterministic on-device
///   headline immediately and is replaced in place when the model-generated
///   headline streams in (the cache is `@Observable`), so this view re-renders
///   from "generating on-device" into the streamed result without any extra
///   plumbing. FM availability is detected with a graceful NaturalLanguage /
///   deterministic fallback (AND-563).
/// - AI stays **off by default** behind a visible toggle (the AND-564 consent
///   contract): with the toggle off no model is invoked and the surface shows only
///   the enable affordance.
///
/// Liquid Glass never touches a chart; this is a text/receipt surface, so it uses
/// the standard raised card chrome. Phase + provenance are carried by text + SF
/// Symbol, never color alone (ACCESSIBILITY.md).
struct InsightsAIInsightView: View {
    @Environment(AppState.self) private var appState
    @Environment(\.openSettings) private var openSettings
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private var summaries: [LocalAIActivitySummary] {
        appState.localAIActivitySummaries
    }

    private var primarySummary: LocalAIActivitySummary? {
        summaries.first { $0.window == .lastMonth } ?? summaries.first
    }

    private var availability: LocalAIAvailability {
        primarySummary?.availability ?? appState.localAIAvailability
    }

    private var receipt: LocalAIInsightReceipt {
        LocalAIInsightReceipt.make(
            summary: primarySummary,
            availability: availability,
            privacyMaskEnabled: appState.shouldMaskFinancialValues
        )
    }

    /// Whether a model produced the headline yet (non-empty `generatedSummary`),
    /// vs. the deterministic fallback. Drives the generating → streamed phase.
    private var hasModelGeneratedHeadline: Bool {
        !(primarySummary?.generatedSummary.isEmpty ?? true)
    }

    private var phase: InsightsStreamingPhase {
        InsightsStreamingPhase.resolve(
            isEnabled: appState.localAIEnabled,
            availabilityState: availability.state,
            hasModelGeneratedHeadline: hasModelGeneratedHeadline
        )
    }

    private var enabledBinding: Binding<Bool> {
        Binding(
            get: { appState.localAIEnabled },
            set: { appState.localAIEnabled = $0 }
        )
    }

    var body: some View {
        VStack(alignment: .leading, spacing: Spacing.md) {
            header

            if phase == .off {
                offState
            } else {
                insightBody
            }
        }
        .padding(Spacing.md)
        .glassSurface(.raised)
        .accessibilityElement(children: .contain)
        .accessibilityLabel(accessibilityLabel)
        // Probe the on-device runtime when the surface appears so an enabled-but-
        // unprobed state resolves to a truthful availability without waiting for a
        // data change. A no-op while disabled or already checking.
        .task(id: appState.localAIEnabled) {
            guard appState.localAIEnabled else { return }
            await appState.checkLocalAIAvailability()
        }
    }

    // MARK: - Header

    private var header: some View {
        HStack(alignment: .firstTextBaseline, spacing: Spacing.sm) {
            Label("Spending insights", systemImage: "sparkles")
                .sectionTitle()
                .foregroundStyle(.secondary)

            Spacer(minLength: Spacing.sm)

            phasePill

            // The off-by-default consent toggle, always visible (AND-564).
            Toggle("Local AI", isOn: enabledBinding)
                .toggleStyle(.switch)
                .controlSize(.mini)
                .labelsHidden()
                .help(appState.localAIEnabled ? "Turn off on-device AI insights" : "Turn on on-device AI insights")
                .accessibilityLabel("Local AI insights")
                .accessibilityValue(appState.localAIEnabled ? "On" : "Off")
                .accessibilityHint("Generates spending insights on this Mac. Off by default.")
        }
    }

    /// Phase status pill — glyph + text so the state never rides on tint alone.
    /// The generating phase animates a non-looping shimmer, suppressed under
    /// Reduce Motion.
    private var phasePill: some View {
        HStack(spacing: Spacing.xxs) {
            Image(systemName: phase.systemImage)
                .font(.caption2.weight(.semibold))
                .symbolEffect(.pulse, options: .repeating, isActive: phase.isWorking && !reduceMotion)
                .accessibilityHidden(true)
            Text(phase.statusLabel)
                .font(.caption2.weight(.semibold))
                .lineLimit(1)
        }
        .foregroundStyle(phaseTint)
        .padding(.horizontal, 7)
        .padding(.vertical, 3)
        .background(phaseTint.opacity(0.12), in: Capsule())
        .overlay { Capsule().stroke(phaseTint.opacity(0.20), lineWidth: 1) }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(phase.accessibilityLabel)
    }

    private var phaseTint: Color {
        switch phase {
        case .off: .secondary
        case .unavailable: SemanticColors.warning
        case .generating: SemanticColors.brand
        case .streamed: SemanticColors.positive
        }
    }

    // MARK: - Off state (consent)

    private var offState: some View {
        VStack(alignment: .leading, spacing: Spacing.sm) {
            Text("On-device spending summaries are off")
                .font(.callout.weight(.semibold))

            Text("Turn on Local AI to generate a short, factual summary of your spending on this Mac. Nothing leaves your device — there is no cloud fallback.")
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)

            HStack(spacing: Spacing.sm) {
                Button {
                    appState.localAIEnabled = true
                } label: {
                    Label("Enable Local AI", systemImage: "sparkles")
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.small)
                .accessibilityHint("Enables on-device spending insights. Off by default.")

                Button {
                    openSettings()
                } label: {
                    Label("Where your data lives", systemImage: "lock.shield")
                }
                .buttonStyle(.bordered)
                .controlSize(.small)
                .accessibilityHint("Opens Settings to the local data section.")
            }
        }
        .padding(Spacing.sm)
        .nativeInsetSurface()
    }

    // MARK: - Insight body (generating / streamed / unavailable)

    private var insightBody: some View {
        VStack(alignment: .leading, spacing: Spacing.sm) {
            // Headline — the deterministic fallback while generating, replaced in
            // place by the model-generated headline when it streams in.
            HStack(alignment: .firstTextBaseline, spacing: Spacing.sm) {
                Text(receipt.headline)
                    .font(.callout.weight(.semibold))
                    .fixedSize(horizontal: false, vertical: true)
                    .transition(.opacity)
                    .id(receipt.headline) // cross-fade as the streamed text lands
                    .animation(MotionTokens.animation(MotionTokens.standard, reduceMotion: reduceMotion), value: receipt.headline)

                if phase.isWorking {
                    ProgressView()
                        .controlSize(.small)
                        .accessibilityLabel("Generating on-device")
                }
            }

            if !receipt.evidenceChips.isEmpty {
                evidenceChips
            }

            provenance

            if phase == .unavailable {
                unavailableNote
            }

            footer
        }
    }

    private var evidenceChips: some View {
        // Wrap so chips reflow rather than clip on a narrow column.
        InsightsFlowLayout(spacing: Spacing.xs) {
            ForEach(receipt.evidenceChips) { chip in
                InsightsEvidenceChipView(chip: chip)
            }
        }
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Evidence")
    }

    /// Provenance / consent receipt lines — confidence, runtime limitations, and
    /// the reversible-action note — each as a bulleted detail line.
    private var provenance: some View {
        VStack(alignment: .leading, spacing: Spacing.xs) {
            ForEach(Array(provenanceLines.enumerated()), id: \.offset) { _, line in
                HStack(alignment: .top, spacing: Spacing.sm) {
                    Image(systemName: "circle.fill")
                        .font(.system(size: 4))
                        .foregroundStyle(.secondary)
                        .padding(.top, 6)
                        .accessibilityHidden(true)
                    Text(line)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
        }
    }

    private var provenanceLines: [String] {
        var lines: [String] = [receipt.confidence]
        if let unavailableState = receipt.unavailableState {
            lines.append(unavailableState)
        }
        lines.append(contentsOf: receipt.limitations.prefix(2))
        return Array(lines.prefix(3))
    }

    private var unavailableNote: some View {
        Label(availability.detail, systemImage: "exclamationmark.triangle")
            .font(.caption.weight(.medium))
            .foregroundStyle(SemanticColors.warning)
            .fixedSize(horizontal: false, vertical: true)
            .padding(Spacing.sm)
            .nativeInsetSurface(stroke: SemanticColors.warning.opacity(0.18))
            .accessibilityLabel("Runtime unavailable. \(availability.detail)")
    }

    private var footer: some View {
        HStack(spacing: Spacing.xs) {
            Image(systemName: "lock.shield.fill")
                .font(.caption2.weight(.semibold))
                .foregroundStyle(.secondary)
                .accessibilityHidden(true)
            Text("\(receipt.localOnlyBadge). \(receipt.reversibleActionCopy)")
                .font(.caption2)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)

            Spacer(minLength: Spacing.xs)

            Button {
                openSettings()
            } label: {
                Label("Where your data lives", systemImage: "externaldrive.badge.questionmark")
                    .labelStyle(.titleAndIcon)
                    .font(.caption2)
            }
            .buttonStyle(.plain)
            .foregroundStyle(.secondary)
            .help("Open Settings to see where VaultPeek stores your data on this Mac.")
            .accessibilityLabel("Where your data lives")
            .accessibilityHint("Opens Settings to the local data section.")
        }
    }

    private var accessibilityLabel: String {
        if phase == .off {
            return "Spending insights. \(phase.accessibilityLabel)"
        }
        return "Spending insights. \(phase.accessibilityLabel) \(receipt.accessibilitySummary)"
    }
}

/// A single evidence chip — glyph + label + value, color-independent (the accent
/// is supplementary; the glyph and text carry the meaning). Mirrors the popover's
/// chip presentation without depending on its private view.
struct InsightsEvidenceChipView: View {
    let chip: LocalAIInsightReceipt.EvidenceChip

    private var accent: Color {
        guard let category = chip.accentCategory else { return .secondary }
        return CategoryAccentTokens.color(for: category)
    }

    var body: some View {
        HStack(spacing: Spacing.xxs) {
            Image(systemName: chip.systemImage)
                .font(.caption2.weight(.semibold))
                .foregroundStyle(accent)
                .accessibilityHidden(true)
            Text(chip.label)
                .font(.caption2)
                .foregroundStyle(.secondary)
            Text(chip.value)
                .font(.caption2.weight(.semibold))
                .monospacedDigit()
        }
        .padding(.horizontal, 7)
        .padding(.vertical, 3)
        .background(Color.primary.opacity(0.05), in: Capsule())
        .overlay { Capsule().stroke(Color.primary.opacity(0.08), lineWidth: 1) }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("\(chip.label): \(chip.value)")
    }
}

/// A minimal left-to-right wrapping layout for the evidence chips, so they reflow
/// onto a new row instead of clipping on a narrow content column. Pure geometry —
/// no animation or state.
struct InsightsFlowLayout: Layout {
    var spacing: CGFloat = Spacing.xs

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout Void) -> CGSize {
        let maxWidth = proposal.width ?? .infinity
        let rows = computeRows(maxWidth: maxWidth, subviews: subviews)
        guard !rows.isEmpty else { return .zero }
        let rowsHeight = rows.reduce(CGFloat.zero) { $0 + $1.height }
        let interRowSpacing = spacing * CGFloat(rows.count - 1)
        let width = rows.map(\.width).max() ?? 0
        return CGSize(width: min(width, maxWidth), height: rowsHeight + interRowSpacing)
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout Void) {
        let rows = computeRows(maxWidth: bounds.width, subviews: subviews)
        var y = bounds.minY
        for row in rows {
            var x = bounds.minX
            for index in row.indices {
                let size = subviews[index].sizeThatFits(.unspecified)
                subviews[index].place(
                    at: CGPoint(x: x, y: y),
                    anchor: .topLeading,
                    proposal: ProposedViewSize(size)
                )
                x += size.width + spacing
            }
            y += row.height + spacing
        }
    }

    private struct Row {
        var indices: [Int] = []
        var width: CGFloat = 0
        var height: CGFloat = 0
    }

    private func computeRows(maxWidth: CGFloat, subviews: Subviews) -> [Row] {
        var rows: [Row] = []
        var current = Row()
        for index in subviews.indices {
            let size = subviews[index].sizeThatFits(.unspecified)
            let projected = current.width == 0 ? size.width : current.width + spacing + size.width
            if projected > maxWidth, !current.indices.isEmpty {
                rows.append(current)
                current = Row()
                current.indices = [index]
                current.width = size.width
                current.height = size.height
            } else {
                current.indices.append(index)
                current.width = projected
                current.height = max(current.height, size.height)
            }
        }
        if !current.indices.isEmpty { rows.append(current) }
        return rows
    }
}
