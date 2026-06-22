import PlaidBarCore
import SwiftUI

/// **Insights** destination — a window-first **composed 2-column canvas** (AND-624,
/// matching the Dashboard reference; `[⌘6]`), Epic 7 / AND-585.
///
/// This re-*hosts* the Insights data — the on-device Foundation Models summary, the
/// weekly review, and the trend charts — in a desk-distance desktop layout rather
/// than re-using the popover's compact stack. It reads the *same* `AppState` +
/// `PlaidBarCore` engines as the popover and the menu-bar surfaces, so the two can
/// never diverge; **no model or chart logic lives here** (surface only).
///
/// Layout (desk-distance, ``WindowMetrics`` / ``WindowTypography`` — "comfortable
/// density", a calm canvas of a few generous cards):
/// 1. a **hero**: the streaming FM spending-insight headline + the on-device
///    ``LocalAIInsightReceipt`` (tier + provenance + consent), surfaced via
///    ``InsightsAIInsightView`` as a prominent full-width hero card. AI is **off by
///    default with a visible toggle** (AND-564); availability is detected with a
///    graceful NaturalLanguage / deterministic fallback (AND-563);
/// 2. a **two-column card grid** below it, **at most three cards per column** under a
///    `title2` column banner:
///    - left **Trends** column — the net-worth trend, the spend donut, and the
///      activity heatmap, each its own ``WindowSection`` chart card
///      (``InsightsTrendsView``). Every chart ships its ``ChartAudioGraph`` audio
///      graph (AND-569) + a `reduceTransparency` / Privacy Mask text alternative;
///      **Liquid Glass never touches a chart** and no meaning rides on color alone
///      (ACCESSIBILITY.md);
///    - right **Review** column — the existing ``WeeklyReviewCard`` re-hosted
///      unchanged, so the window-first surface and the popover drive the same
///      review state.
///   On a narrow window the two columns stack.
///
/// **Privacy Mask / App Lock:** the shell paints the full lock gate over the whole
/// window while *locked* (Epic 10), so this canvas never double-gates; it
/// honors Privacy *Mask* the way the re-hosted subviews do (figures run through
/// `PrivacyMaskPresentation` / `shouldMaskFinancialValues`), so masked figures stay
/// hidden and are never leaked here.
///
/// **Flag-OFF inert:** reached only when the window-first `Window` opens
/// (`WindowFirstFeatureFlag` ON). With the flag off the popover is byte-identical —
/// this file is never instantiated.
struct InsightsDestinationView: View {
    @Environment(AppState.self) private var appState

    var body: some View {
        GeometryReader { proxy in
            let isWide = proxy.size.width >= WindowMetrics.twoColumnBreakpoint

            ScrollView {
                VStack(alignment: .leading, spacing: WindowMetrics.xl) {
                    // Hero — the on-device spending insight + receipt, given the
                    // full canvas width so it reads as the destination's headline
                    // instrument (like the Dashboard's heatmap hero).
                    InsightsAIInsightView()

                    if isWide {
                        HStack(alignment: .top, spacing: WindowMetrics.columnGap) {
                            trendsColumn
                                .frame(maxWidth: .infinity, alignment: .topLeading)
                            reviewColumn
                                .frame(maxWidth: .infinity, alignment: .topLeading)
                        }
                    } else {
                        VStack(alignment: .leading, spacing: WindowMetrics.xl) {
                            trendsColumn
                            reviewColumn
                        }
                    }
                }
                .padding(WindowMetrics.canvasMargin)
                .frame(maxWidth: .infinity, alignment: .topLeading)
            }
            .scrollContentBackground(.hidden)
        }
        .navigationTitle(RouteDestination.insights.title)
        .accessibilityElement(children: .contain)
        .task { await appState.loadInitialData() }
    }

    // MARK: - Columns

    /// The left/primary **Trends** column — the three trend chart cards (net-worth
    /// trend, spend donut, activity heatmap). Each self-cards as a ``WindowSection``
    /// inside ``InsightsTrendsView``; the column banner above them is a `title2`
    /// region header. Charts stay solid (never glass) and re-host the same Core
    /// engines as the popover.
    private var trendsColumn: some View {
        VStack(alignment: .leading, spacing: WindowMetrics.lg) {
            columnHeader("Trends", systemImage: "chart.xyaxis.line")
            InsightsTrendsView()
        }
        .accessibilityElement(children: .contain)
    }

    /// The right/secondary **Review** column — the weekly review, re-hosted
    /// unchanged so this surface and the popover drive the same review state.
    private var reviewColumn: some View {
        VStack(alignment: .leading, spacing: WindowMetrics.lg) {
            columnHeader("Review", systemImage: "calendar.badge.checkmark")
            WeeklyReviewCard()
        }
        .accessibilityElement(children: .contain)
    }

    /// A window-scale **column** region header (`title2` via ``WindowSectionTitle``)
    /// — one step up from a card's `title3` title, so the column reads as a region
    /// grouping its cards. A heading, not a card, so it sits cleanly above the
    /// self-carding cards below without nesting a card in a card.
    private func columnHeader(_ title: String, systemImage: String) -> some View {
        Label {
            Text(title).windowSectionTitle()
        } icon: {
            Image(systemName: systemImage).foregroundStyle(.secondary)
        }
        .labelStyle(.titleAndIcon)
        .accessibilityAddTraits(.isHeader)
    }
}

#Preview {
    InsightsDestinationView()
        .environment(AppState())
}
