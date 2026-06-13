import AppKit
import PlaidBarCore
import SwiftUI

struct PopoverMaterialBackground: View {
    let transparencySetting: PopoverTransparencySetting

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency
    @AppStorage(DecorativeEffectsPreference.storageKey) private var decorativeRaw = DecorativeEffectsPreference.defaultValue.rawValue

    /// The decorative mesh texture is optional: the "Reduced" preference, system
    /// Reduce Transparency, or system Reduce Motion all suppress it or its drift
    /// (AND-365 closes AND-342's always-on texture). System settings win.
    private var effects: ResolvedDecorativeEffects {
        (DecorativeEffectsPreference(rawValue: decorativeRaw) ?? .followSystem)
            .resolved(systemReduceMotion: reduceMotion, systemReduceTransparency: reduceTransparency)
    }

    var body: some View {
        let effects = effects

        ZStack {
            if effects.allowsTexture {
                PopoverMeshTexture(
                    opacity: SurfaceTokens.popoverTextureOpacity,
                    reduceMotion: !effects.allowsMotion
                )
            }

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
