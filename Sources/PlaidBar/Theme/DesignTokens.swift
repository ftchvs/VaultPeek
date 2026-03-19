import SwiftUI

// MARK: - Semantic Colors

enum SemanticColors {
    // Financial meaning
    static let income = Color.green
    static let expense = Color.primary
    static let creditDebt = Color.red
    static let available = Color.green

    // Status
    static let warning = Color.orange
    static let positive = Color.green
    static let negative = Color.red
    static let pending = Color.orange

    // Utilization thresholds
    static func utilization(for percent: Double) -> Color {
        switch percent {
        case ..<30: return .green
        case 30..<50: return .yellow
        case 50..<75: return .orange
        default: return .red
        }
    }

    /// SF Symbol for utilization status
    static func utilizationIcon(for percent: Double) -> String {
        switch percent {
        case ..<30: return "checkmark.circle"
        case 30..<50: return "exclamationmark.triangle"
        case 50..<75: return "exclamationmark.triangle"
        default: return "xmark.octagon"
        }
    }
}

// MARK: - Spacing (8pt grid)

enum Spacing {
    static let xs: CGFloat = 4
    static let sm: CGFloat = 8
    static let md: CGFloat = 12
    static let lg: CGFloat = 16
    static let xl: CGFloat = 24
}
