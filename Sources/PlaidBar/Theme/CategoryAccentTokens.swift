import PlaidBarCore
import SwiftUI

enum CategoryAccentTokens {
    static func color(for category: SpendingCategory) -> Color {
        switch category {
        case .foodAndDrink:
            .pink
        case .transportation:
            .teal
        case .shopping:
            .cyan
        case .entertainment:
            .mint
        case .personalCare:
            .purple
        case .healthAndFitness:
            .red
        case .billsAndUtilities:
            .orange
        case .homeImprovement:
            .brown
        case .travel:
            .indigo
        case .education:
            .blue
        case .subscriptions:
            SemanticColors.recurring
        case .income:
            SemanticColors.positive
        case .transfer, .transferOut:
            .secondary
        case .bankFees:
            SemanticColors.negative
        case .government:
            SemanticColors.brandSecondary
        case .other:
            .secondary
        }
    }
}
