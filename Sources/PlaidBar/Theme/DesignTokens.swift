import SwiftUI

// MARK: - Semantic Colors

enum SemanticColors {
    // MARK: - Financial Meaning

    /// Money received — paycheck deposits, refunds, Venmo inflows.
    /// Used in transaction rows and Income vs Expense chart bars.
    static let income = Color(nsColor: .systemGreen)

    /// Default text color for outgoing transactions
    /// (uses `.primary` to follow system appearance).
    static let expense = Color.primary

    /// Outstanding credit card balance shown in account rows
    /// and credit utilization display.
    static let creditDebt = Color(nsColor: .systemRed)

    /// Available/spendable balance in depository account rows.
    static let available = Color(nsColor: .systemGreen)

    // MARK: - Status Indicators

    /// General caution indicator — credit utilization at or above the
    /// user's warning threshold (icon tint), stale sync badge.
    static let warning = Color(nsColor: .systemOrange)

    /// Favorable delta — spending decreased vs. prior period, balance increased.
    static let positive = Color(nsColor: .systemGreen)

    /// Unfavorable delta — spending increased vs. prior period,
    /// "Remove" destructive actions.
    static let negative = Color(nsColor: .systemRed)

    /// Uncommitted transactions that haven't cleared yet.
    static let pending = Color(nsColor: .systemOrange)

    // MARK: - Charts

    /// Balance history mini-chart and spending trend line/area fill.
    static let sparkline = Color(nsColor: .systemBlue)

    // MARK: - Brand Identity

    /// Primary app accent — hero icons, step dots, active controls.
    static let brand = Color(nsColor: .systemBlue)

    /// Secondary accent — sandbox mode icon, complementary highlights.
    static let brandSecondary = Color(nsColor: .systemOrange)

    // MARK: - Recurring

    /// Detected recurring charges badge and recurring transaction section header.
    static let recurring = Color(nsColor: .systemIndigo)

    /// Utilization thresholds. Yellow is excluded from the ramp: yellow text
    /// at caption size falls below 4.5:1 contrast in both appearances, so the
    /// 30-75% band shares orange and the icon ladder (below) carries the
    /// severity distinction.
    static func utilization(for percent: Double, threshold: Double = 30) -> Color {
        guard percent >= threshold else { return Color(nsColor: .systemGreen) }
        switch percent {
        case ..<75: return Color(nsColor: .systemOrange)
        default: return Color(nsColor: .systemRed)
        }
    }

    /// SF Symbol for utilization status
    static func utilizationIcon(for percent: Double, threshold: Double = 30) -> String {
        if percent < threshold { return "checkmark.circle" }
        if percent < 50 { return "exclamationmark.triangle" }
        if percent < 75 { return "exclamationmark.triangle.fill" }
        return "xmark.octagon"
    }
}

enum AppearanceTextColors {
    static let primary = Color(nsColor: .labelColor)
    static let secondary = Color(nsColor: .secondaryLabelColor)
}

// MARK: - Spacing (8pt grid)

enum Spacing {
    static let xxs: CGFloat = 2
    static let xs: CGFloat = 4
    static let sm: CGFloat = 8
    static let md: CGFloat = 12
    static let lg: CGFloat = 16
    static let xl: CGFloat = 24
    static let rowVertical: CGFloat = 6
    static let chipVertical: CGFloat = 3
    static let compactRowHorizontalPadding: CGFloat = sm
    static let compactRowVerticalPadding: CGFloat = xs
    static let compactRowContentSpacing: CGFloat = sm
    static let compactRowTextSpacing: CGFloat = xxs
}

// MARK: - Radius

/// The app-wide corner radius scale. Panels and clipped lists use `panel`,
/// controls/rows/hover washes use `control`, heatmap cells use `cell`.
enum Radius {
    static let panel: CGFloat = 8
    static let control: CGFloat = 6
    static let cell: CGFloat = 2
}

// MARK: - Sizing

/// Fixed-frame sizes for icons, chips, and rows so the same visual role
/// always renders at the same size across surfaces.
enum Sizing {
    static let iconInline: CGFloat = 16
    static let iconNav: CGFloat = 20
    static let iconChip: CGFloat = 28
    static let statusDot: CGFloat = 8
    /// Fixed glyph frame for inline row icons that need a tight bound (e.g.
    /// weekly-review checkbox/severity glyphs) without a backing tile.
    static let glyphSmall: CGFloat = 20
    /// Fixed glyph frame for leading row icons that sit on a tinted tile
    /// (review-inbox / attention-queue leading symbols).
    static let glyphMedium: CGFloat = 24
    /// Minimum clickable frame for borderless glyph controls. 28pt is the
    /// macOS pointer-target floor (compact control height); the 44pt HIG
    /// figure is a touch-input minimum and would break menu bar density.
    static let hitTargetMin: CGFloat = 28
}

// MARK: - Motion

/// The motion system: three durations, one reduce-motion gate. Every
/// animation in the app flows through `animation(_:reduceMotion:)` so
/// Reduce Motion disables movement in one place.
enum MotionTokens {
    /// Hover, press, chip toggles.
    static let micro = Animation.easeOut(duration: 0.12)
    /// Selection, filter swaps, disclosure, banner entrances.
    static let standard = Animation.easeInOut(duration: 0.2)
    /// Drill-in/fly-out expansion and number transitions.
    static let content = Animation.spring(response: 0.3, dampingFraction: 0.85)
    /// Refresh spinner movement. Always pass through `animation`.
    static let refreshSpin = Animation.linear(duration: 0.8).repeatForever(autoreverses: false)
    /// Refresh spinner settle when loading ends.
    static let refreshSettle = Animation.linear(duration: 0.3)
    /// Loading skeleton pulse. Always pass through `animation`.
    static let loadingPulse = Animation.easeInOut(duration: 0.9).repeatForever(autoreverses: true)
    /// Decorative background drift. Always pass through `animation`.
    static let backgroundDrift = Animation.easeInOut(duration: 18).repeatForever(autoreverses: true)
    /// Once-per-appearance left-to-right reveal for glance charts.
    static let chartReveal = Animation.easeOut(duration: 0.55)

    static let staticLoadingOpacity = 0.62
    static let loadingPulseOpacity = 0.55
    /// Scroll-edge depth floor (AND-383): rows/sections fade to this as they reach
    /// the scroll viewport edge; identity (1.0) when fully visible.
    static let scrollEdgeFadeOpacity = 0.6

    static func animation(_ animation: Animation, reduceMotion: Bool) -> Animation? {
        reduceMotion ? nil : animation
    }

    static func refreshSymbolName(isLoading: Bool, reduceMotion: Bool) -> String {
        reduceMotion && isLoading ? "arrow.clockwise.circle.fill" : "arrow.clockwise"
    }

    static func refreshOpacity(isLoading: Bool, reduceMotion: Bool) -> Double {
        reduceMotion && isLoading ? staticLoadingOpacity : 1
    }

    static func loadingOpacity(isDimmed: Bool, reduceMotion: Bool) -> Double {
        reduceMotion ? 1 : (isDimmed ? loadingPulseOpacity : 1)
    }
}

// MARK: - Native Surfaces

enum SurfaceTokens {
    struct SurfaceShadow: Sendable, Equatable {
        let opacity: Double
        let radius: CGFloat
        let x: CGFloat
        let y: CGFloat
    }

    struct SurfaceDepth: Sendable, Equatable {
        let strokeOpacity: Double
        let innerStrokeOpacity: Double
        let shadow: SurfaceShadow?
    }

    static let popoverCornerRadius: CGFloat = 12
    static let panelCornerRadius: CGFloat = 7
    static let compactCornerRadius: CGFloat = 6
    /// Glass merge radius for `GlassEffectContainer` (AND-381): the proximity
    /// under which adjacent Liquid Glass shapes fuse into one sampling blob.
    /// Deliberately small so only genuinely-adjacent glass merges — this is a
    /// merge radius, not layout spacing.
    static let glassMergeRadius: CGFloat = 8

    static let panelFillOpacity = 0.022
    static let insetFillOpacity = 0.045
    static let controlFillOpacity = 0.07
    static let selectedFillOpacity = 0.13

    static let panelStrokeOpacity = 0.075
    static let emphasizedStrokeOpacity = 0.16

    static let popoverTextureOpacity = 0.12

    static let leftPanelDepth = SurfaceDepth(
        strokeOpacity: 0.11,
        innerStrokeOpacity: 0.045,
        shadow: SurfaceShadow(opacity: 0.16, radius: 14, x: 0, y: 8)
    )
    static let raisedDepth = SurfaceDepth(
        strokeOpacity: 0.08,
        innerStrokeOpacity: 0.035,
        shadow: SurfaceShadow(opacity: 0.11, radius: 10, x: 0, y: 5)
    )
    static let insetDepth = SurfaceDepth(
        strokeOpacity: 0.055,
        innerStrokeOpacity: 0.025,
        shadow: SurfaceShadow(opacity: 0.055, radius: 5, x: 0, y: 2)
    )
    static let heroDepth = SurfaceDepth(
        strokeOpacity: 0.10,
        innerStrokeOpacity: 0.055,
        shadow: SurfaceShadow(opacity: 0.12, radius: 12, x: 0, y: 6)
    )
    static let emphasizedDepth = SurfaceDepth(
        strokeOpacity: emphasizedStrokeOpacity,
        innerStrokeOpacity: 0.045,
        shadow: SurfaceShadow(opacity: 0.08, radius: 8, x: 0, y: 4)
    )

    static let heroGlowOpacity = 0.10

    // AND-511: the `liquidGlassAvailability` descriptor was removed. The macOS-26
    // floor (AND-509/510) makes Liquid Glass the only, unconditional path, so the
    // "macOS 15 material fallback" note it carried no longer describes any code.
    // Shadow depths and the spacing grid are intentionally retained — system
    // glass supplies the material, not the depth/elevation language above.

    static func panelFill(emphasisTint: Color? = nil) -> Color {
        if let emphasisTint {
            return emphasisTint.opacity(0.055)
        }
        return Color.primary.opacity(panelFillOpacity)
    }

    static func panelStroke(emphasisTint: Color? = nil) -> Color {
        if let emphasisTint {
            return emphasisTint.opacity(emphasizedStrokeOpacity)
        }
        return Color.primary.opacity(panelStrokeOpacity)
    }
}
