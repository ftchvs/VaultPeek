import SwiftUI

// MARK: - Semantic Colors

enum SemanticColors {

    // MARK: - Financial Meaning

    /// Money received — paycheck deposits, refunds, Venmo inflows.
    /// Used in transaction rows and Income vs Expense chart bars.
    static let income = Color.green

    /// Default text color for outgoing transactions
    /// (uses `.primary` to follow system appearance).
    static let expense = Color.primary

    /// Outstanding credit card balance shown in account rows
    /// and credit utilization display.
    static let creditDebt = Color.red

    /// Available/spendable balance in depository account rows.
    static let available = Color.green

    // MARK: - Status Indicators

    /// General caution indicator — moderate credit utilization (30-50%),
    /// stale sync badge.
    static let warning = Color.orange

    /// Favorable delta — spending decreased vs. prior period, balance increased.
    static let positive = Color.green

    /// Unfavorable delta — spending increased vs. prior period,
    /// "Remove" destructive actions.
    static let negative = Color.red

    /// Uncommitted transactions that haven't cleared yet.
    static let pending = Color.orange

    // MARK: - Charts

    /// Balance history mini-chart and spending trend line/area fill.
    static let sparkline = Color.blue

    // MARK: - Brand Identity

    /// Primary app accent — hero icons, step dots, active controls.
    static let brand = Color.blue

    /// Secondary accent — sandbox mode icon, complementary highlights.
    static let brandSecondary = Color.orange

    // MARK: - Recurring

    /// Detected recurring charges badge and recurring transaction section header.
    static let recurring = Color.indigo

    // Utilization thresholds
    static func utilization(for percent: Double, threshold: Double = 30) -> Color {
        guard percent >= threshold else { return .green }
        switch percent {
        case ..<50: return .yellow
        case 50..<75: return .orange
        default: return .red
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

// MARK: - Spacing (8pt grid)

enum Spacing {
    static let xxs: CGFloat = 2
    static let xs: CGFloat = 4
    static let sm: CGFloat = 8
    static let md: CGFloat = 12
    static let lg: CGFloat = 16
    static let xl: CGFloat = 24
    static let rowVertical: CGFloat = 6
    static let compactRowHorizontalPadding: CGFloat = sm
    static let compactRowVerticalPadding: CGFloat = xs
    static let compactRowContentSpacing: CGFloat = sm
    static let compactRowTextSpacing: CGFloat = xxs
}

// MARK: - Native Surfaces

enum SurfaceTokens {
    static let popoverCornerRadius: CGFloat = 12
    static let panelCornerRadius: CGFloat = 7
    static let compactCornerRadius: CGFloat = 6

    static let panelFillOpacity = 0.022
    static let insetFillOpacity = 0.045
    static let controlFillOpacity = 0.07
    static let selectedFillOpacity = 0.13

    static let panelStrokeOpacity = 0.075
    static let emphasizedStrokeOpacity = 0.16

    /// Liquid Glass is a progressive enhancement on macOS 26+.
    /// macOS 15 users keep the same layout with SwiftUI material/fill fallback.
    static let liquidGlassAvailability = "macOS 26+ progressive enhancement; macOS 15 uses material fallback"

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
