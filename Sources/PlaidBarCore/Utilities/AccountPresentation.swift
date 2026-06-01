import Foundation

public enum AccountPresentation {
    public static func isDebt(_ account: AccountDTO) -> Bool {
        account.type == .credit || account.type == .loan
    }

    public static func displayBalance(for account: AccountDTO) -> Double {
        if isDebt(account) {
            return abs(account.balances.current ?? 0)
        }
        return account.balances.effectiveBalance
    }

    public static func availableBalance(for account: AccountDTO) -> Double {
        if let available = account.balances.available {
            return available
        }

        guard isDebt(account) else {
            return account.balances.effectiveBalance
        }

        guard account.type == .credit,
              let limit = account.balances.limit,
              limit > 0
        else {
            return 0
        }

        return max(0, limit - displayBalance(for: account))
    }

    public static func displayName(for account: AccountDTO) -> String {
        account.officialName ?? account.name
    }

    public static func subtitle(for account: AccountDTO) -> String {
        let subtype = account.subtype?.capitalized ?? account.type.rawValue.capitalized
        let mask = account.mask.map { " •••• \($0)" } ?? ""
        return "\(account.type.rawValue.capitalized) • \(subtype)\(mask)"
    }

    public static func iconName(for account: AccountDTO) -> String {
        switch account.type {
        case .credit:
            return "creditcard.fill"
        case .loan:
            return "dollarsign.circle.fill"
        case .investment:
            return "chart.line.uptrend.xyaxis"
        case .depository:
            return depositoryIconName(forSubtype: account.subtype)
        case .other:
            return "building.columns.fill"
        }
    }

    public static func utilizationStatusLabel(
        for percent: Double,
        threshold: Double = PlaidBarConstants.creditUtilizationWarningThreshold
    ) -> String {
        guard percent >= threshold else { return "Good" }

        switch percent {
        case ..<50:
            return "Warning"
        case 50..<75:
            return "High"
        default:
            return "Very high"
        }
    }

    private static func depositoryIconName(forSubtype subtype: String?) -> String {
        let normalized = subtype?.lowercased() ?? ""

        if normalized.contains("saving") {
            return "tray.full.fill"
        }

        if normalized.contains("money market") {
            return "chart.pie.fill"
        }

        if normalized.contains("checking") {
            return "banknote.fill"
        }

        return "building.columns.fill"
    }
}
