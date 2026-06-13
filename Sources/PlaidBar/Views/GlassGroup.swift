import PlaidBarCore
import SwiftUI

// MARK: - Glass Effect Container Grouping (AND-381)

/// Groups coexisting Liquid Glass surfaces so the system samples and blends them
/// as one glass field instead of each `glassSurface` resolving its own isolated
/// sampling region.
///
/// `GlassEffectContainer(spacing:)`'s `spacing` is the glass **merge radius** —
/// the proximity under which two glass shapes fuse into one blob — NOT layout
/// spacing. It is intentionally small (`SurfaceTokens.glassMergeRadius`) so only
/// genuinely-adjacent glass merges; distant glass islands in a tall scroll column
/// stay visually distinct, which is why wrapping a whole scroll body is safe.
///
/// macOS-26 / SwiftUI-7 only; on macOS 15 (and the Swift <6.3 CI toolchain where
/// the glass APIs aren't compiled at all) this is a transparent passthrough — the
/// wrapped content renders byte-for-byte as it does today, so the fallback look
/// never regresses. Glass is chrome only: wrap regions that *contain* glass
/// surfaces; `GlassEffectContainer` only samples/merges its `glassEffect`
/// descendants, so non-glass content/text inside is unaffected.
struct GlassGroup<Content: View>: View {
    var spacing: CGFloat
    @ViewBuilder var content: () -> Content

    init(spacing: CGFloat = SurfaceTokens.glassMergeRadius, @ViewBuilder content: @escaping () -> Content) {
        self.spacing = spacing
        self.content = content
    }

    var body: some View {
        #if compiler(>=6.3) && canImport(SwiftUI, _version: 7.0)
            if #available(macOS 26.0, *) {
                GlassEffectContainer(spacing: spacing) {
                    content()
                }
            } else {
                content()
            }
        #else
            content()
        #endif
    }
}

extension View {
    /// Group this region's descendant `glassSurface(...)` shapes into one
    /// `GlassEffectContainer` sampling region on macOS 26 (passthrough on macOS 15
    /// / pre-6.3 CI). `spacing` is the glass merge radius, default
    /// `SurfaceTokens.glassMergeRadius` — apply at the smallest ancestor that
    /// contains the coexisting glass shapes.
    func glassGroup(spacing: CGFloat = SurfaceTokens.glassMergeRadius) -> some View {
        GlassGroup(spacing: spacing) { self }
    }
}
