import PlaidBarCore
import SwiftUI

// MARK: - Hero Accent + Emphasized Data Surfaces

extension View {
    /// Decorative hero-accent solid surface: a tinted gradient wash, never
    /// glass (R-08 — a financial figure must never sample translucency).
    /// Never carries financial/status meaning by itself.
    func heroAccentSurface(tint: Color = SemanticColors.brand) -> some View {
        solidDataSurface(
            cornerRadius: Radius.panel,
            fill: AnyShapeStyle(
                LinearGradient(
                    colors: [
                        tint.opacity(SurfaceTokens.heroGlowOpacity),
                        Color.primary.opacity(0.035),
                        Color.clear,
                    ],
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                )
            ),
            stroke: tint.opacity(0.10)
        )
    }

    /// Solid attention-state data surface: tinted fill + tinted hairline
    /// stroke. The emphasized-state counterpart to `solidDataSurface()` for
    /// attention rows/cards that need a color wash while staying non-glass
    /// (R-08). Attention states are the one place a tinted wash is
    /// appropriate on a data surface — the tint plus an accompanying
    /// icon/text label carries the meaning, never color alone.
    func emphasizedDataSurface(tint: Color, cornerRadius: CGFloat = Radius.panel) -> some View {
        solidDataSurface(
            cornerRadius: cornerRadius,
            fill: AnyShapeStyle(tint.opacity(0.12)),
            stroke: tint.opacity(0.16)
        )
    }

    /// Subtle scroll-edge depth (AND-383): a scrolling row fades as it approaches the
    /// top/bottom of the scroll viewport and returns to identity when fully visible.
    /// Render-only (opacity) — zero layout impact, so row heights and the density
    /// rhythm are unchanged, and there is no horizontal drift on left-aligned content.
    /// Under Reduce Motion it renders at full opacity throughout (effect disabled).
    /// Apply to each scrolling row or section — never to pinned headers/footers.
    func scrollEdgeDepth(reduceMotion: Bool) -> some View {
        scrollTransition { content, phase in
            content
                .opacity(reduceMotion || phase.isIdentity ? 1 : MotionTokens.scrollEdgeFadeOpacity)
        }
    }
}

// MARK: - Native Panel Surface (chrome = glass, data = solid)
//
// The chrome-vs-data split is expressed by the surface *type*, not a boolean:
// chrome-rank panels (`NativePanelGlassSurface`) unconditionally carry native
// Liquid Glass; data surfaces (`SolidDataSurface`) are always solid. There is no
// material fallback path — glass is the macOS-26 baseline (AND-511), and the
// chrome-vs-data eligibility rule itself is the pure `WindowChromeGlass.allowsGlass`.

/// Chrome-rank panel surface: a fill + hairline stroke under native Liquid Glass.
/// For navigation/chrome surfaces only — never dense data, which must stay solid
/// (see `SolidDataSurface`).
struct NativePanelGlassSurface: ViewModifier {
    let cornerRadius: CGFloat
    let fill: AnyShapeStyle
    let stroke: Color

    func body(content: Content) -> some View {
        let shape = RoundedRectangle(cornerRadius: cornerRadius)
        content
            .background(fill, in: shape)
            .glassEffect(.regular, in: .rect(cornerRadius: cornerRadius))
            .overlay {
                shape.stroke(stroke, lineWidth: 1)
            }
    }
}

/// Solid data surface: a fill + hairline stroke with **no** glass. Used for data
/// (lists, rows, dense cards, insight bodies) so values never sample a
/// translucent backdrop — the "Liquid Glass on chrome, not data" doctrine (R-08).
struct SolidDataSurface: ViewModifier {
    let cornerRadius: CGFloat
    let fill: AnyShapeStyle
    let stroke: Color

    func body(content: Content) -> some View {
        let shape = RoundedRectangle(cornerRadius: cornerRadius)
        content
            .background(fill, in: shape)
            .overlay {
                shape.stroke(stroke, lineWidth: 1)
            }
    }
}

extension View {
    /// Chrome-rank fill+stroke surface under native Liquid Glass. Chrome
    /// only — route data surfaces through ``solidDataSurface`` /
    /// ``nativeInsetSurface``.
    func nativePanelSurface(
        cornerRadius: CGFloat = SurfaceTokens.panelCornerRadius,
        fill: AnyShapeStyle = AnyShapeStyle(SurfaceTokens.panelFill()),
        stroke: Color = SurfaceTokens.panelStroke()
    ) -> some View {
        modifier(
            NativePanelGlassSurface(
                cornerRadius: cornerRadius,
                fill: fill,
                stroke: stroke
            )
        )
    }

    /// Solid (non-glass) data surface: fill + hairline stroke. The explicit
    /// data-surface treatment — values stay legible over an opaque backdrop and
    /// never sample translucency (R-08).
    func solidDataSurface(
        cornerRadius: CGFloat = SurfaceTokens.compactCornerRadius,
        fill: AnyShapeStyle = AnyShapeStyle(Color.primary.opacity(SurfaceTokens.insetFillOpacity)),
        stroke: Color = Color.primary.opacity(0.055)
    ) -> some View {
        modifier(
            SolidDataSurface(
                cornerRadius: cornerRadius,
                fill: fill,
                stroke: stroke
            )
        )
    }

    /// Quiet inset data surface. A thin convenience over ``solidDataSurface`` for
    /// the common inset-card case (secondary rows, metric strips); always solid.
    func nativeInsetSurface(
        cornerRadius: CGFloat = SurfaceTokens.compactCornerRadius,
        stroke: Color = Color.primary.opacity(0.055)
    ) -> some View {
        solidDataSurface(cornerRadius: cornerRadius, stroke: stroke)
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

// MARK: - Symbol Motion (shared, Reduce Motion-aware)

/// The status/state SF Symbol-motion patterns used across VaultPeek
/// (refresh/sync, attention severity, menu-bar status swaps). Centralizes the
/// native symbol APIs behind one Reduce Motion gate so future icon animation
/// uses a single pattern instead of scattered per-call logic (AND-358). Meaning
/// always survives motion loss via the symbol's shape/state — these effects are
/// decorative reinforcement only.
enum SymbolMotion {
    /// Cross-fade between glyphs when the symbol name changes.
    case replace
    /// A single, non-repeating discrete effect when the view appears/activates.
    case bounceOnce
    /// A continuous effect that loops while active (e.g. an in-progress spinner).
    case rotateContinuously
}

extension View {
    /// Apply a `SymbolMotion` pattern, disabled under Reduce Motion (the symbol's
    /// shape/state still conveys meaning). `isActive` gates the discrete and
    /// continuous effects; it is ignored by `.replace`, which keys off the symbol
    /// name change. Reduce Motion is gated here so call sites pass only intent.
    @ViewBuilder
    func symbolMotion(_ motion: SymbolMotion, isActive: Bool = true, reduceMotion: Bool) -> some View {
        switch motion {
        case .replace:
            contentTransition(reduceMotion ? .identity : .symbolEffect(.replace))
        case .bounceOnce:
            symbolEffect(.bounce, options: .nonRepeating, isActive: isActive && !reduceMotion)
        case .rotateContinuously:
            symbolEffect(.rotate, options: .repeat(.continuous), isActive: isActive && !reduceMotion)
        }
    }
}

// MARK: - Refresh Icon (native continuous symbol effect)

struct RefreshIcon: View {
    let isLoading: Bool
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        // The active refresh state is driven by a native SF Symbol effect that
        // loops continuously while `isLoading` is true. Under Reduce Motion the
        // symbol helpers swap in the filled static glyph at a dimmed opacity and
        // the effect is gated inactive, so loading reads without any movement.
        Image(systemName: MotionTokens.refreshSymbolName(isLoading: isLoading, reduceMotion: reduceMotion))
            .symbolMotion(.rotateContinuously, isActive: isLoading, reduceMotion: reduceMotion)
            .opacity(MotionTokens.refreshOpacity(isLoading: isLoading, reduceMotion: reduceMotion))
            .accessibilityLabel(isLoading ? "Refreshing" : "Refresh")
            .accessibilityValue(isLoading ? "In progress" : "Ready")
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
            // Loading is passive: no recovery action until the first fetch
            // delivers a verdict the user can act on.
            if !presentation.isLoading {
                actionButton
            }
        }
        .padding()
        .frame(maxWidth: .infinity, minHeight: 180)
        .accessibilityElement(children: .contain)
        .task(id: presentation.isLoading) {
            guard presentation.isLoading else { return }
            await Task.yield()
            AccessibilityNotification.Announcement("\(presentation.title). \(presentation.detail)").post()
        }
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
