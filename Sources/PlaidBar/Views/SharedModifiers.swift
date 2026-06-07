import SwiftUI
import PlaidBarCore

// MARK: - Native Panel Surface

struct NativePanelSurface: ViewModifier {
    let cornerRadius: CGFloat
    let fill: AnyShapeStyle
    let stroke: Color
    let useLiquidGlass: Bool

    @ViewBuilder
    func body(content: Content) -> some View {
        let shape = RoundedRectangle(cornerRadius: cornerRadius)

        if useLiquidGlass {
            #if compiler(>=6.3)
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
    @State private var isHovered = false

    func body(content: Content) -> some View {
        content
            .contentShape(Rectangle())
            .background(isHovered ? Color.primary.opacity(0.04) : .clear)
            .onHover { hovering in
                isHovered = hovering
            }
    }
}

extension View {
    func hoverHighlight() -> some View {
        modifier(HoverHighlight())
    }
}

// MARK: - Refresh Icon (smooth spin via repeatForever)

struct RefreshIcon: View {
    let isLoading: Bool
    @State private var rotation: Double = 0

    var body: some View {
        Image(systemName: "arrow.clockwise")
            .rotationEffect(.degrees(rotation))
            .onChange(of: isLoading) { _, loading in
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
                if isLoading {
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
