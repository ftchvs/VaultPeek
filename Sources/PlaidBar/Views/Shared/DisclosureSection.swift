import PlaidBarCore
import SwiftUI

// MARK: - Disclosure section (design-elevation shared kit)
//
// The collapsible sibling of ``WindowSection``: same title style, padding, and
// quiet solid card surface, with the header doubling as the expand/collapse
// control. Collapsing hides the body but keeps the count in the header, so a
// folded section still answers "how much is in here?".

/// A collapsible titled card matching ``WindowSection``'s visual language.
///
/// The header is a real `Button` (keyboard- and VoiceOver-reachable) that stays
/// a VoiceOver header; its accessibility value announces the count and the
/// expanded/collapsed state ("4 items, collapsed"). The chevron rotation is
/// disabled under Reduce Motion — state still reads from the disclosed content
/// and the announced value, never from the chevron angle alone.
struct DisclosureSection<Content: View>: View {
    let title: String
    /// Optional SF Symbol shown before the title (shape, not color, for meaning).
    var systemImage: String?
    /// Optional item count shown as a header accessory and voiced in the
    /// header's accessibility value.
    var count: Int?
    @Binding var isExpanded: Bool
    @ViewBuilder var content: () -> Content

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        VStack(alignment: .leading, spacing: isExpanded ? WindowMetrics.md : 0) {
            Button {
                withAnimation(MotionTokens.animation(MotionTokens.standard, reduceMotion: reduceMotion)) {
                    isExpanded.toggle()
                }
            } label: {
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

                    Spacer(minLength: WindowMetrics.sm)

                    if let count {
                        Text("\(count)")
                            .windowSupportingText()
                            .monospacedDigit()
                    }

                    Image(systemName: "chevron.down")
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(.secondary)
                        .rotationEffect(.degrees(isExpanded ? 0 : -90))
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityAddTraits(.isHeader)
            .accessibilityValue(accessibilityStateValue)

            if isExpanded {
                content()
            }
        }
        .padding(WindowMetrics.md)
        .frame(maxWidth: .infinity, alignment: .leading)
        .windowCardSurface()
        .accessibilityElement(children: .contain)
    }

    private var accessibilityStateValue: String {
        let state = isExpanded ? "expanded" : "collapsed"
        guard let count else { return state }
        return "\(count) \(count == 1 ? "item" : "items"), \(state)"
    }
}

#if canImport(PreviewsMacros)
private struct DisclosureSectionPreviewHost: View {
    @State private var expanded = true
    @State private var collapsed = false

    var body: some View {
        VStack(spacing: WindowMetrics.lg) {
            DisclosureSection(title: "Needs review", systemImage: "tray", count: 4, isExpanded: $expanded) {
                VStack(alignment: .leading, spacing: WindowMetrics.sm) {
                    Text("Whole Foods Market — $86.20")
                    Text("City of Oakland Parking — $2.00")
                }
                .windowBodyText()
            }
            DisclosureSection(title: "Resolved this week", count: 12, isExpanded: $collapsed) {
                Text("Resolved rows go here")
                    .windowBodyText()
            }
        }
        .padding(WindowMetrics.canvasMargin)
        .frame(width: 520)
    }
}

#Preview("Disclosure sections") {
    DisclosureSectionPreviewHost()
}

#Preview("Disclosure sections — dark") {
    DisclosureSectionPreviewHost()
        .preferredColorScheme(.dark)
}
#endif
