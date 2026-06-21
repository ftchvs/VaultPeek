import PlaidBarCore
import SwiftUI

struct BalanceCompositionBarSegment: Identifiable, Equatable {
    let id: String
    let title: String
    let value: Double
    let share: Double
    let tint: Color
    /// Privacy-mask-aware value spoken to VoiceOver. Built through
    /// PrivacyMaskPresentation by the caller so the bar never leaks raw
    /// per-bucket balances while Privacy Mask is on (matches the legend rows).
    let accessibilityValueText: String

    var fillColor: Color {
        value > 0 ? tint.opacity(0.82) : Color.primary.opacity(0.08)
    }
}

struct AnimatedBalanceCompositionBar: View {
    let segments: [BalanceCompositionBarSegment]
    var height: CGFloat = 8

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var revealProgress = 0.0

    private let segmentSpacing: CGFloat = 2

    var body: some View {
        GeometryReader { proxy in
            HStack(spacing: segmentSpacing) {
                ForEach(segments) { segment in
                    RoundedRectangle(cornerRadius: Radius.cell)
                        .fill(segment.fillColor)
                        .overlay(
                            // Non-color cue: a hairline outline separates adjacent
                            // segments so the mix is legible without relying on hue.
                            // Uses the window background so it reads as a "cut" in
                            // both light and dark appearances.
                            RoundedRectangle(cornerRadius: Radius.cell)
                                .strokeBorder(Color(nsColor: .windowBackgroundColor).opacity(0.7), lineWidth: 0.5)
                        )
                        .frame(
                            width: segmentWidth(
                                segment,
                                totalWidth: proxy.size.width,
                                segmentCount: segments.count
                            )
                        )
                        .accessibilityLabel(segmentAccessibility(segment))
                }
            }
        }
        .frame(height: height)
        .onAppear(perform: reveal)
        .onChange(of: segments) { _, _ in
            reveal()
        }
        .accessibilityElement(children: .contain)
    }

    private func reveal() {
        if reduceMotion {
            revealProgress = 1
        } else {
            revealProgress = 0
            withAnimation(MotionTokens.animation(MotionTokens.standard, reduceMotion: reduceMotion)) {
                revealProgress = 1
            }
        }
    }

    private func segmentWidth(
        _ segment: BalanceCompositionBarSegment,
        totalWidth: CGFloat,
        segmentCount: Int
    ) -> CGFloat {
        let gaps = CGFloat(max(segmentCount - 1, 0)) * segmentSpacing
        let availableWidth = max(totalWidth - gaps, 0)
        return max(availableWidth * CGFloat(segment.share) * revealProgress, 6)
    }

    private func segmentAccessibility(_ segment: BalanceCompositionBarSegment) -> String {
        "\(segment.title), \(segment.accessibilityValueText), \(percentText(segment.share)) of balance mix"
    }
}

private func percentText(_ share: Double) -> String {
    "\(Int((share * 100).rounded()))%"
}
