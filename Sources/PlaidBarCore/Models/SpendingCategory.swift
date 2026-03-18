import Foundation

/// Maps to Plaid's personal_finance_category.primary
public enum SpendingCategory: String, Codable, Sendable, CaseIterable, Hashable {
    case foodAndDrink = "FOOD_AND_DRINK"
    case transportation = "TRANSPORTATION"
    case shopping = "GENERAL_MERCHANDISE"
    case entertainment = "ENTERTAINMENT"
    case personalCare = "PERSONAL_CARE"
    case healthAndFitness = "MEDICAL"
    case billsAndUtilities = "RENT_AND_UTILITIES"
    case homeImprovement = "HOME_IMPROVEMENT"
    case travel = "TRAVEL"
    case education = "EDUCATION"
    case subscriptions = "LOAN_PAYMENTS"  // Including recurring
    case income = "INCOME"
    case transfer = "TRANSFER_IN"
    case transferOut = "TRANSFER_OUT"
    case bankFees = "BANK_FEES"
    case government = "GOVERNMENT_AND_NON_PROFIT"
    case other = "OTHER"

    /// Human-readable display name
    public var displayName: String {
        switch self {
        case .foodAndDrink: "Food & Drink"
        case .transportation: "Transportation"
        case .shopping: "Shopping"
        case .entertainment: "Entertainment"
        case .personalCare: "Personal Care"
        case .healthAndFitness: "Health & Fitness"
        case .billsAndUtilities: "Bills & Utilities"
        case .homeImprovement: "Home"
        case .travel: "Travel"
        case .education: "Education"
        case .subscriptions: "Subscriptions"
        case .income: "Income"
        case .transfer: "Transfer In"
        case .transferOut: "Transfer Out"
        case .bankFees: "Bank Fees"
        case .government: "Government"
        case .other: "Other"
        }
    }

    /// SF Symbol name for category icon
    public var iconName: String {
        switch self {
        case .foodAndDrink: "fork.knife"
        case .transportation: "car.fill"
        case .shopping: "bag.fill"
        case .entertainment: "tv.fill"
        case .personalCare: "heart.fill"
        case .healthAndFitness: "cross.case.fill"
        case .billsAndUtilities: "bolt.fill"
        case .homeImprovement: "house.fill"
        case .travel: "airplane"
        case .education: "book.fill"
        case .subscriptions: "creditcard.fill"
        case .income: "arrow.down.circle.fill"
        case .transfer: "arrow.left.arrow.right"
        case .transferOut: "arrow.right.circle.fill"
        case .bankFees: "banknote.fill"
        case .government: "building.columns.fill"
        case .other: "questionmark.circle.fill"
        }
    }

    /// Color for charts (hex string)
    public var colorHex: String {
        switch self {
        case .foodAndDrink: "#FF6B6B"
        case .transportation: "#4ECDC4"
        case .shopping: "#45B7D1"
        case .entertainment: "#96CEB4"
        case .personalCare: "#FFEAA7"
        case .healthAndFitness: "#DDA0DD"
        case .billsAndUtilities: "#98D8C8"
        case .homeImprovement: "#F7DC6F"
        case .travel: "#BB8FCE"
        case .education: "#85C1E9"
        case .subscriptions: "#F8C471"
        case .income: "#82E0AA"
        case .transfer: "#AEB6BF"
        case .transferOut: "#D5DBDB"
        case .bankFees: "#E74C3C"
        case .government: "#5DADE2"
        case .other: "#BDC3C7"
        }
    }
}
