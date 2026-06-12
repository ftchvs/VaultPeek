import PlaidBarCore
import SwiftUI

// MARK: - Glass Surface Ranks

/// The popover's three-rank surface system. Ranks use *hierarchical* shape
/// styles (not flat `Color` fills) so surfaces participate in macOS vibrancy
/// over the `.regularMaterial` popover root, and respond to Reduce
/// Transparency / Increase Contrast for free. Default surfaces draw no
/// stroke — separation comes from spacing; hairlines are reserved for
/// emphasized (attention) states.
enum SurfaceRank {
    /// Primary content panels: account list, fly-out, heatmap.
    case raised
    /// Quiet secondary surfaces: metric strips, legends, chips.
    case inset
    /// Attention states only: tinted fill plus hairline.
    case emphasized(Color)

    var fill: AnyShapeStyle {
        switch self {
        case .raised: AnyShapeStyle(.quaternary.opacity(0.5))
        case .inset: AnyShapeStyle(.quinary)
        case let .emphasized(tint): AnyShapeStyle(tint.opacity(0.10))
        }
    }

    var stroke: Color? {
        switch self {
        case .raised, .inset: nil
        case let .emphasized(tint): tint.opacity(0.16)
        }
    }
}

private struct GlassSurface: ViewModifier {
    let rank: SurfaceRank
    let cornerRadius: CGFloat

    func body(content: Content) -> some View {
        let shape = RoundedRectangle(cornerRadius: cornerRadius)

        // Liquid Glass is a macOS 26+ progressive enhancement. Raised/inset
        // ranks carry no underlay fill so the material reads clean, but the
        // emphasized rank keeps its tinted wash — attention states must
        // survive the glass path.
        #if compiler(>=6.3) && canImport(SwiftUI, _version: 7.0)
            if #available(macOS 26.0, *) {
                content
                    .background(emphasizedFill ?? AnyShapeStyle(.clear), in: shape)
                    .glassEffect(.regular, in: .rect(cornerRadius: cornerRadius))
                    .overlay {
                        if let stroke = rank.stroke {
                            shape.stroke(stroke, lineWidth: 1)
                        }
                    }
            } else {
                fallback(content: content, shape: shape)
            }
        #else
            fallback(content: content, shape: shape)
        #endif
    }

    private var emphasizedFill: AnyShapeStyle? {
        if case .emphasized = rank {
            return rank.fill
        }
        return nil
    }

    private func fallback(content: Content, shape: RoundedRectangle) -> some View {
        content
            .background(rank.fill, in: shape)
            .overlay {
                if let stroke = rank.stroke {
                    shape.stroke(stroke, lineWidth: 1)
                }
            }
    }
}

extension View {
    func glassSurface(
        _ rank: SurfaceRank = .raised,
        cornerRadius: CGFloat = Radius.panel
    ) -> some View {
        modifier(GlassSurface(rank: rank, cornerRadius: cornerRadius))
    }
}

// MARK: - Native Panel Surface

struct NativePanelSurface: ViewModifier {
    let cornerRadius: CGFloat
    let fill: AnyShapeStyle
    let stroke: Color
    let useLiquidGlass: Bool

    func body(content: Content) -> some View {
        let shape = RoundedRectangle(cornerRadius: cornerRadius)

        if useLiquidGlass {
            // Keep every reference to Liquid Glass APIs inside this compile-time
            // gate. PlaidBar supports macOS 15, where the fallback fill/material
            // surface below must remain the active type-checked path.
            #if compiler(>=6.3) && canImport(SwiftUI, _version: 7.0)
                if #available(macOS 26.0, *) {
                    content
                        .background(fill, in: shape)
                        .glassEffect(.regular, in: .rect(cornerRadius: cornerRadius))
                        .overlay {
                            shape.stroke(stroke, lineWidth: 1)
                        }
                } else {
                    fallback(content: content, shape: shape)
                }
            #else
                fallback(content: content, shape: shape)
            #endif
        } else {
            fallback(content: content, shape: shape)
        }
    }

    private func fallback(content: Content, shape: RoundedRectangle) -> some View {
        content
            .background(fill, in: shape)
            .overlay {
                shape.stroke(stroke, lineWidth: 1)
            }
    }
}

extension View {
    func nativePanelSurface(
        cornerRadius: CGFloat = SurfaceTokens.panelCornerRadius,
        fill: AnyShapeStyle = AnyShapeStyle(SurfaceTokens.panelFill()),
        stroke: Color = SurfaceTokens.panelStroke(),
        useLiquidGlass: Bool = true
    ) -> some View {
        modifier(
            NativePanelSurface(
                cornerRadius: cornerRadius,
                fill: fill,
                stroke: stroke,
                useLiquidGlass: useLiquidGlass
            )
        )
    }

    func nativeInsetSurface(
        cornerRadius: CGFloat = SurfaceTokens.compactCornerRadius,
        stroke: Color = Color.primary.opacity(0.055)
    ) -> some View {
        nativePanelSurface(
            cornerRadius: cornerRadius,
            fill: AnyShapeStyle(Color.primary.opacity(SurfaceTokens.insetFillOpacity)),
            stroke: stroke,
            useLiquidGlass: false
        )
    }
}

// MARK: - Hover Highlight

struct HoverHighlight: ViewModifier {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var isHovered = false
    var cornerRadius: CGFloat = Radius.control

    func body(content: Content) -> some View {
        content
            .contentShape(Rectangle())
            .background(
                .quaternary.opacity(isHovered ? 0.55 : 0),
                in: RoundedRectangle(cornerRadius: cornerRadius)
            )
            .onHover { hovering in
                withAnimation(MotionTokens.animation(MotionTokens.micro, reduceMotion: reduceMotion)) {
                    isHovered = hovering
                }
            }
    }
}

extension View {
    func hoverHighlight(cornerRadius: CGFloat = Radius.control) -> some View {
        modifier(HoverHighlight(cornerRadius: cornerRadius))
    }
}

// MARK: - Refresh Icon (smooth spin via repeatForever)

struct RefreshIcon: View {
    let isLoading: Bool
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var rotation: Double = 0

    var body: some View {
        // Under Reduce Motion the infinite spin is replaced by a static
        // dimmed state — loading is still visible, nothing moves.
        Image(systemName: "arrow.clockwise")
            .rotationEffect(.degrees(rotation))
            .opacity(reduceMotion && isLoading ? 0.5 : 1)
            .onChange(of: isLoading) { _, loading in
                guard !reduceMotion else { return }
                if loading {
                    withAnimation(.linear(duration: 0.8).repeatForever(autoreverses: false)) {
                        rotation = 360
                    }
                } else {
                    withAnimation(.linear(duration: 0.3)) {
                        rotation = 0
                    }
                }
            }
            .onAppear {
                if isLoading, !reduceMotion {
                    withAnimation(.linear(duration: 0.8).repeatForever(autoreverses: false)) {
                        rotation = 360
                    }
                }
            }
    }
}

// MARK: - Secondary Empty State

struct SecondaryUnavailableView: View {
    let presentation: SecondaryContentUnavailableState
    let action: () -> Void

    var body: some View {
        ContentUnavailableView {
            Label(presentation.title, systemImage: presentation.iconName)
        } description: {
            Text(presentation.detail)
                .multilineTextAlignment(.center)
        } actions: {
            actionButton
        }
        .padding()
        .frame(maxWidth: .infinity, minHeight: 180)
        .accessibilityElement(children: .contain)
    }

    @ViewBuilder
    private var actionButton: some View {
        let button = Button(action: action) {
            Label(presentation.actionTitle, systemImage: presentation.actionIconName)
        }
        .buttonStyle(.borderedProminent)
        .controlSize(.small)
        .help(presentation.actionTitle)

        if let hint = presentation.actionAccessibilityHint {
            button.accessibilityHint(Text(hint))
        } else {
            button
        }
    }
}
