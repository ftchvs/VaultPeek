import PlaidBarCore
import SwiftUI

/// **Insights** destination (2-column composed canvas — IA §3.1/§5.7, `[⌘6]`) —
/// Epic 7 / AND-585 (ADR-001 window-first workspace).
///
/// A composed reading canvas — no master list, so the shell renders only this
/// content column (no inspector). It stacks the three Insights bands (IA §5.7 —
/// ``InsightSection``), every one surfaced from an existing engine; **no model or
/// chart logic lives here** (surface only):
///
/// - **Spending insights** (``InsightSection/receipts``) — the streaming
///   Foundation Models `@Generable` insight + the on-device ``LocalAIInsightReceipt``
///   (tier + provenance + consent), via ``InsightsAIInsightView``. AI is **off by
///   default with a visible toggle** (AND-564); FM availability is detected with a
///   graceful NaturalLanguage / deterministic fallback (AND-563).
/// - **Weekly review** (``InsightSection/weeklyReview``) — the existing
///   ``WeeklyReviewCard`` re-hosted unchanged, so the window-first surface and the
///   menu-bar popover drive the same review state.
/// - **Trends** (``InsightSection/trends``) — the chart canvas (``InsightsTrendsView``):
///   net-worth trend, spend donut, and activity heatmap. Every chart ships its
///   ``ChartAudioGraph`` audio graph (AND-569) + a `reduceTransparency` / Privacy
///   Mask text alternative; **Liquid Glass never touches a chart**, and no meaning
///   rides on color alone (ACCESSIBILITY.md).
///
/// A segmented section picker jumps between the three bands (scroll-to-anchor),
/// matching the IA's Insights sub-sections without splitting into a master list.
///
/// **Flag-OFF inert:** reached only when the window-first `Window` opens
/// (`WindowFirstFeatureFlag` ON). With the flag off the popover is byte-identical —
/// this file is never instantiated.
struct InsightsDestinationView: View {
    @Environment(AppState.self) private var appState

    /// The section the picker last jumped to. `@SceneStorage` keeps it window-
    /// scoped so each workspace window remembers its own focus without touching
    /// shared `AppState`.
    @SceneStorage("insights.section") private var sectionRaw = InsightSection.receipts.rawValue

    private var section: InsightSection {
        InsightSection(rawValue: sectionRaw) ?? .receipts
    }

    var body: some View {
        ScrollViewReader { scroll in
            ScrollView {
                VStack(alignment: .leading, spacing: Spacing.lg) {
                    header

                    InsightsAIInsightView()
                        .id(InsightSection.receipts)

                    weeklyReviewSection
                        .id(InsightSection.weeklyReview)

                    InsightsTrendsView()
                        .id(InsightSection.trends)
                }
                .padding(Spacing.lg)
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            .scrollContentBackground(.hidden)
            .onChange(of: sectionRaw) { _, raw in
                guard let target = InsightSection(rawValue: raw) else { return }
                withAnimation { scroll.scrollTo(target, anchor: .top) }
            }
        }
        .navigationTitle(RouteDestination.insights.title)
        .accessibilityElement(children: .contain)
    }

    // MARK: - Header

    private var header: some View {
        VStack(alignment: .leading, spacing: Spacing.sm) {
            VStack(alignment: .leading, spacing: Spacing.xxs) {
                Text("Insights")
                    .font(.title2.weight(.bold))
                Text("On-device spending summaries, your weekly review, and the trends behind them — all computed locally on this Mac.")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
            .accessibilityElement(children: .combine)

            sectionPicker
        }
    }

    /// Jumps the canvas to a band. Each segment carries a glyph **and** a label so
    /// the selection is never conveyed by tint alone (ACCESSIBILITY.md).
    private var sectionPicker: some View {
        Picker("Insights section", selection: sectionBinding) {
            ForEach(InsightSection.allCases, id: \.self) { section in
                Label(sectionLabel(section), systemImage: sectionGlyph(section))
                    .tag(section)
            }
        }
        .pickerStyle(.segmented)
        .labelStyle(.titleAndIcon)
        .fixedSize()
        .accessibilityLabel("Insights section")
        .accessibilityHint("Jump to spending insights, the weekly review, or trends.")
    }

    private var sectionBinding: Binding<InsightSection> {
        Binding(get: { section }, set: { sectionRaw = $0.rawValue })
    }

    private func sectionLabel(_ section: InsightSection) -> String {
        switch section {
        case .receipts: "Insights"
        case .weeklyReview: "Weekly review"
        case .trends: "Trends"
        }
    }

    private func sectionGlyph(_ section: InsightSection) -> String {
        switch section {
        case .receipts: "sparkles"
        case .weeklyReview: "calendar.badge.checkmark"
        case .trends: "chart.xyaxis.line"
        }
    }

    // MARK: - Weekly review

    private var weeklyReviewSection: some View {
        VStack(alignment: .leading, spacing: Spacing.sm) {
            Label("Weekly review", systemImage: "calendar.badge.checkmark")
                .sectionTitle()
                .foregroundStyle(.secondary)
            // The existing card, re-hosted unchanged — same review state as the
            // menu-bar popover, so the two surfaces can never diverge.
            WeeklyReviewCard()
        }
        .accessibilityElement(children: .contain)
    }
}

#Preview {
    InsightsDestinationView()
        .environment(AppState())
}
