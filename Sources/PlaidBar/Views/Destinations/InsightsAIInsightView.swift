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
/// This is the Insights canvas **hero** (AND-624): a prominent full-width card at
/// the top of the destination, at the window (desk-distance) scale —
/// ``WindowMetrics`` / ``WindowTypography``. Data stays solid (glass on
/// chrome, not data), so the receipt sits on the quiet ``windowCardSurface()``
/// rather than a translucent wash. Phase + provenance are carried by text + SF
/// Symbol, never color alone (ACCESSIBILITY.md).
struct InsightsAIInsightView: View {
    @Environment(AppState.self) private var appState
    @Environment(\.openSettings) private var openSettings
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private var summaries: [LocalAIActivitySummary] {
        appState.localAIActivitySummaries
    }

    private var primarySummary: LocalAIActivitySummary? {
        appState.selectedInsightSummary
    }

    /// Ordered window options + which are usable + the resolved selection, computed
    /// in Core from the already-on-device summaries (no new model run).
    private var windowSelection: LocalAIInsightWindowSelection {
        appState.localAIWindowSelection
    }

    private var selectedWindowBinding: Binding<LocalAIInsightWindow> {
        Binding(
            get: { appState.selectedInsightWindow },
            set: { appState.selectedInsightWindow = $0 }
        )
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
        VStack(alignment: .leading, spacing: WindowMetrics.md) {
            header

            if phase == .off {
                offState
            } else {
                windowSelector
                insightBody
            }
        }
        .padding(WindowMetrics.md)
        .frame(maxWidth: .infinity, alignment: .leading)
        .windowCardSurface()
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
        HStack(alignment: .firstTextBaseline, spacing: WindowMetrics.sm) {
            Label {
                Text("Spending insights").windowCardTitle()
            } icon: {
                Image(systemName: "sparkles").foregroundStyle(.secondary)
            }
            .labelStyle(.titleAndIcon)
            .accessibilityAddTraits(.isHeader)

            Spacer(minLength: WindowMetrics.sm)

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
    /// Reduce Motion. When the runtime is unavailable — the expected graceful
    /// fallback on a Mac without on-device AI, not an error — the pill reads as a
    /// passive *info* status (neutral tint + info glyph), never an alarm (HIG:
    /// match delivery to significance; never imply something's wrong). The long
    /// availability detail and any raw probe diagnostic live only here, on the
    /// `.help(...)` tooltip, so they never shout from the card body.
    private var phasePill: some View {
        HStack(spacing: Spacing.xxs) {
            Image(systemName: phaseGlyph)
                .windowFigureCaption()
                .symbolEffect(.pulse, options: .repeating, isActive: phase.isWorking && !reduceMotion)
                .accessibilityHidden(true)
            Text(phase.statusLabel)
                .windowFigureCaption()
                .lineLimit(1)
        }
        .foregroundStyle(phaseTint)
        .padding(.horizontal, Spacing.sm)
        .padding(.vertical, Spacing.chipVertical)
        .background(phaseTint.opacity(0.12), in: Capsule())
        .overlay { Capsule().stroke(phaseTint.opacity(0.20), lineWidth: 1) }
        .help(phaseHelpText)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(phase.accessibilityLabel)
    }

    /// Glyph for the pill. The unavailable state uses a neutral info glyph rather
    /// than the enum's `exclamationmark.triangle`, so the expected fallback reads
    /// as information, not caution.
    private var phaseGlyph: String {
        switch phase {
        case .unavailable: "info.circle"
        default: phase.systemImage
        }
    }

    private var phaseTint: Color {
        switch phase {
        // Unavailable is the expected fallback, not a fault — keep it secondary.
        // `SemanticColors.warning` is reserved for true caution.
        case .off, .unavailable: .secondary
        case .generating: SemanticColors.brand
        case .streamed: SemanticColors.positive
        }
    }

    /// Tooltip text for the pill. For the unavailable state it carries the long,
    /// calm availability detail and — only here — the raw probe diagnostic, so
    /// dev jargon never reaches the visible card (mirrors the popover sibling's
    /// `.help(LocalAIAvailabilityPresentation.helpText(for:))`).
    private var phaseHelpText: String {
        guard phase == .unavailable else { return phase.accessibilityLabel }
        var text = LocalAIAvailabilityPresentation.helpText(for: availability)
        if let probe = availability.probeErrorText, !probe.isEmpty {
            text += " (\(probe))"
        }
        return text
    }

    // MARK: - Window selector

    /// Three-window switcher (7-day / 30-day / year-over-year). A chip row rather
    /// than a plain segmented `Picker` so an unusable window (e.g. year-over-year
    /// before a year of history) can be disabled in place with an explanation,
    /// keeping the menu shape stable. Each chip carries an SF Symbol + text label so
    /// the selected/disabled state never rides on color alone (ACCESSIBILITY.md).
    private var windowSelector: some View {
        let selection = windowSelection
        return HStack(spacing: WindowMetrics.xs) {
            ForEach(selection.options) { option in
                windowChip(for: option)
            }
        }
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Insight time window")
    }

    @ViewBuilder
    private func windowChip(for option: LocalAIInsightWindowSelection.Option) -> some View {
        let window = option.window
        let isSelected = appState.selectedInsightWindow == window
        Button {
            selectedWindowBinding.wrappedValue = window
        } label: {
            Label {
                Text(window.longDisplayName)
            } icon: {
                Image(systemName: window.systemImage)
            }
            .labelStyle(.titleAndIcon)
            .font(.subheadline.weight(isSelected ? .semibold : .regular))
            .padding(.horizontal, Spacing.sm)
            .padding(.vertical, Spacing.xs)
            .frame(maxWidth: .infinity)
            .background(
                isSelected ? AnyShapeStyle(SemanticColors.brand.opacity(0.16)) : AnyShapeStyle(Color.primary.opacity(0.05)),
                in: Capsule()
            )
            .overlay {
                Capsule().stroke(
                    isSelected ? SemanticColors.brand.opacity(0.45) : Color.primary.opacity(0.08),
                    lineWidth: isSelected ? 1.5 : 1
                )
            }
            // The selected chip also carries a checkmark so selection reads without
            // relying on the tint/weight difference alone.
            .overlay(alignment: .topTrailing) {
                if isSelected {
                    Image(systemName: "checkmark.circle.fill")
                        .font(.caption2)
                        .foregroundStyle(SemanticColors.brand)
                        .padding(2)
                        .accessibilityHidden(true)
                }
            }
        }
        .buttonStyle(.plain)
        .disabled(!option.isUsable)
        .opacity(option.isUsable ? 1 : 0.5)
        .help(option.isUsable ? window.accessibilityName : (option.unavailableReason ?? "Not available yet."))
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(window.accessibilityName)
        .accessibilityAddTraits(isSelected ? [.isButton, .isSelected] : .isButton)
        .accessibilityHint(option.isUsable
            ? "Shows the \(window.accessibilityName.lowercased()) spending summary."
            : (option.unavailableReason ?? "Not available yet."))
    }

    // MARK: - Off state (consent)

    private var offState: some View {
        VStack(alignment: .leading, spacing: WindowMetrics.sm) {
            Text("On-device spending summaries are off")
                .font(.body.weight(.semibold))

            Text("Turn on Local AI to generate a short, factual summary of your spending on this Mac. Nothing leaves your device — there is no cloud fallback.")
                .windowSupportingText()
                .fixedSize(horizontal: false, vertical: true)

            HStack(spacing: WindowMetrics.sm) {
                Button {
                    appState.localAIEnabled = true
                } label: {
                    Label("Enable Local AI", systemImage: "sparkles")
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.large)
                .accessibilityHint("Enables on-device spending insights. Off by default.")

                Button {
                    openSettings()
                } label: {
                    Label("Where your data lives", systemImage: "lock.shield")
                }
                .buttonStyle(.bordered)
                .controlSize(.large)
                .accessibilityHint("Opens Settings to the local data section.")
            }
        }
        .padding(WindowMetrics.sm)
        .nativeInsetSurface()
    }

    // MARK: - Insight body (generating / streamed / unavailable)

    private var insightBody: some View {
        VStack(alignment: .leading, spacing: WindowMetrics.sm) {
            // Headline — the deterministic fallback while generating, replaced in
            // place by the model-generated headline when it streams in. The hero
            // figure of the card, so it reads at window `title3` rather than the
            // popover's callout scale.
            HStack(alignment: .firstTextBaseline, spacing: WindowMetrics.sm) {
                Text(receipt.headline)
                    .windowCardTitle()
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

            footer
        }
    }

    private var evidenceChips: some View {
        // Wrap so chips reflow rather than clip on a narrow column.
        InsightsFlowLayout(spacing: WindowMetrics.xs) {
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
        VStack(alignment: .leading, spacing: WindowMetrics.xs) {
            ForEach(Array(provenanceLines.enumerated()), id: \.offset) { _, line in
                HStack(alignment: .top, spacing: WindowMetrics.sm) {
                    Circle()
                        .fill(.secondary)
                        .frame(width: 4, height: 4)
                        .padding(.top, 7)
                        .accessibilityHidden(true)
                    Text(line)
                        .windowSupportingText()
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

    private var footer: some View {
        HStack(spacing: WindowMetrics.xs) {
            Image(systemName: "lock.shield.fill")
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(.secondary)
                .accessibilityHidden(true)
            Text("\(receipt.localOnlyBadge). \(receipt.reversibleActionCopy)")
                .windowSupportingText()
                .fixedSize(horizontal: false, vertical: true)

            Spacer(minLength: WindowMetrics.xs)

            Button {
                openSettings()
            } label: {
                Label("Where your data lives", systemImage: "externaldrive.badge.questionmark")
                    .labelStyle(.titleAndIcon)
                    .font(.subheadline)
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
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(accent)
                .accessibilityHidden(true)
            Text(chip.label)
                .windowFigureCaption()
                .foregroundStyle(.secondary)
            Text(chip.value)
                .windowDataText()
        }
        .padding(.horizontal, Spacing.sm)
        .padding(.vertical, Spacing.xs)
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
