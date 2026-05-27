import Foundation

public enum AccountPresentation {
    public static func isDebt(_ account: AccountDTO) -> Bool {
        account.type == .credit || account.type == .loan
    }

    public static func displayBalance(for account: AccountDTO) -> Double {
        let amount = account.balances.current ?? account.balances.effectiveBalance
        return isDebt(account) ? abs(amount) : amount
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
