import AppKit
import PlaidBarCore
import SwiftUI

struct PopoverMaterialBackground: View {
    let transparencySetting: PopoverTransparencySetting

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency

    var body: some View {
        ZStack {
            PopoverMeshTexture(
                opacity: reduceTransparency
                    ? SurfaceTokens.popoverTextureReduceTransparencyOpacity
                    : SurfaceTokens.popoverTextureOpacity,
                reduceMotion: reduceMotion
            )

            Rectangle()
                .fill(.ultraThinMaterial)

            Color(nsColor: .windowBackgroundColor)
                .opacity(transparencySetting.materialOverlayOpacity)
        }
        .accessibilityHidden(true)
        .allowsHitTesting(false)
    }
}

private struct PopoverMeshTexture: View {
    let opacity: Double
    let reduceMotion: Bool

    @State private var isDrifted = false

    var body: some View {
        LinearGradient(
            colors: [
                SemanticColors.brand.opacity(opacity),
                Color.primary.opacity(opacity * 0.35),
                SemanticColors.brandSecondary.opacity(opacity * 0.82),
                Color.clear,
            ],
            startPoint: isDrifted ? .topTrailing : .topLeading,
            endPoint: isDrifted ? .bottomLeading : .bottomTrailing
        )
        .overlay {
            LinearGradient(
                colors: [
                    Color.clear,
                    Color.primary.opacity(opacity * 0.26),
                    SemanticColors.brand.opacity(opacity * 0.48),
                ],
                startPoint: isDrifted ? .bottomTrailing : .leading,
                endPoint: isDrifted ? .topLeading : .trailing
            )
            .blendMode(.softLight)
        }
        .onAppear {
            guard !reduceMotion else {
                isDrifted = false
                return
            }
            withAnimation(MotionTokens.animation(MotionTokens.backgroundDrift, reduceMotion: reduceMotion)) {
                isDrifted = true
            }
        }
        .onChange(of: reduceMotion) { _, shouldReduceMotion in
            if shouldReduceMotion {
                isDrifted = false
            } else {
                withAnimation(MotionTokens.animation(MotionTokens.backgroundDrift, reduceMotion: shouldReduceMotion)) {
                    isDrifted = true
                }
            }
        }
    }
}
