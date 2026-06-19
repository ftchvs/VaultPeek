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
    /// Persistent left fly-out panel.
    case leftPanel
    /// Primary content panels: account list, fly-out, heatmap.
    case raised
    /// Quiet secondary surfaces: metric strips, legends, chips.
    case inset
    /// Decorative hero emphasis. Never carries finance meaning by itself.
    case hero(Color)
    /// Attention states only: tinted fill plus hairline.
    case emphasized(Color)

    var fill: AnyShapeStyle {
        // Fills sit over the popover's `.ultraThinMaterial` root: the thinner
        // material lets the desktop through, so panels need a little more body
        // than over `.regularMaterial` to keep separation and keep `.secondary`
        // text legible over a busy wallpaper.
        switch self {
        case .leftPanel: AnyShapeStyle(.quaternary.opacity(0.72))
        case .raised: AnyShapeStyle(.quaternary)
        case .inset: AnyShapeStyle(.quaternary.opacity(0.55))
        case let .hero(tint):
            AnyShapeStyle(
                LinearGradient(
                    colors: [
                        tint.opacity(SurfaceTokens.heroGlowOpacity),
                        Color.primary.opacity(0.035),
                        Color.clear,
                    ],
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                )
            )
        case let .emphasized(tint): AnyShapeStyle(tint.opacity(0.12))
        }
    }

    var depth: SurfaceTokens.SurfaceDepth {
        switch self {
        case .leftPanel:
            SurfaceTokens.leftPanelDepth
        case .raised:
            SurfaceTokens.raisedDepth
        case .inset:
            SurfaceTokens.insetDepth
        case .hero:
            SurfaceTokens.heroDepth
        case .emphasized:
            SurfaceTokens.emphasizedDepth
        }
    }

    func stroke(multiplier: Double) -> Color {
        switch self {
        case let .emphasized(tint):
            tint.opacity(min(depth.strokeOpacity * multiplier, 0.22))
        case let .hero(tint):
            tint.opacity(min(depth.strokeOpacity * multiplier, 0.16))
        case .leftPanel, .raised, .inset:
            Color.primary.opacity(min(depth.strokeOpacity * multiplier, 0.16))
        }
    }

    func innerStroke(multiplier: Double) -> Color {
        Color.white.opacity(min(depth.innerStrokeOpacity * multiplier, 0.10))
    }
}

private struct GlassSurface: ViewModifier {
    let rank: SurfaceRank
    let cornerRadius: CGFloat
    @AppStorage(PopoverTransparencySetting.storageKey) private var popoverTransparency = PopoverTransparencySetting.defaultValue

    func body(content: Content) -> some View {
        let shape = RoundedRectangle(cornerRadius: cornerRadius)
        let multiplier = PopoverTransparencySetting(value: popoverTransparency).surfaceDepthMultiplier

        // Raised/inset ranks carry no underlay fill so the Liquid Glass material
        // reads clean, but the emphasized rank keeps its tinted wash — attention
        // states must survive the glass path.
        content
            .background(liquidGlassFill, in: shape)
            .glassEffect(.regular, in: .rect(cornerRadius: cornerRadius))
            .overlay { surfaceStroke(shape: shape, multiplier: multiplier) }
            .surfaceShadow(rank.depth.shadow, multiplier: multiplier)
    }

    private var liquidGlassFill: AnyShapeStyle {
        switch rank {
        case .raised, .inset:
            AnyShapeStyle(.clear)
        case .leftPanel, .hero, .emphasized:
            rank.fill
        }
    }

    private func surfaceStroke(shape: RoundedRectangle, multiplier: Double) -> some View {
        shape.stroke(rank.stroke(multiplier: multiplier), lineWidth: 1)
            .overlay {
                shape
                    .inset(by: 1)
                    .stroke(rank.innerStroke(multiplier: multiplier), lineWidth: 0.5)
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

    func leftPanelSurface() -> some View {
        glassSurface(.leftPanel, cornerRadius: SurfaceTokens.panelCornerRadius)
    }

    func heroAccentSurface(tint: Color = SemanticColors.brand) -> some View {
        glassSurface(.hero(tint), cornerRadius: Radius.panel)
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

private extension View {
    func surfaceShadow(_ shadow: SurfaceTokens.SurfaceShadow?, multiplier: Double) -> some View {
        self.shadow(
            color: Color.black.opacity((shadow?.opacity ?? 0) * multiplier),
            radius: shadow?.radius ?? 0,
            x: shadow?.x ?? 0,
            y: shadow?.y ?? 0
        )
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
            content
                .background(fill, in: shape)
                .glassEffect(.regular, in: .rect(cornerRadius: cornerRadius))
                .overlay {
                    shape.stroke(stroke, lineWidth: 1)
                }
        } else {
            content
                .background(fill, in: shape)
                .overlay {
                    shape.stroke(stroke, lineWidth: 1)
                }
        }
    }
}

extension View {
    /// Legacy fill+stroke surface treatment. New surfaces should use the
    /// rank-based `glassSurface(_:cornerRadius:)` vibrancy system above;
    /// this remains for setup/attention surfaces not yet migrated.
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
