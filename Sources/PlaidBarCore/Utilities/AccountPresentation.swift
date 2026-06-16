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

    public static func positiveBalanceTotal(
        from accounts: [AccountDTO],
        type: AccountType
    ) -> Double {
        accounts
            .filter { $0.type == type }
            .reduce(0) { $0 + max($1.balances.effectiveBalance, 0) }
    }

    public static func debtBalanceTotal(
        from accounts: [AccountDTO],
        type: AccountType
    ) -> Double {
        accounts
            .filter { $0.type == type }
            .reduce(0) { $0 + displayBalance(for: $1) }
    }

    public static func displayName(for account: AccountDTO) -> String {
        account.officialName ?? account.name
    }

    public static func subtitle(for account: AccountDTO) -> String {
        subtitle(for: account, privacyMaskEnabled: false)
    }

    public static func subtitle(for account: AccountDTO, privacyMaskEnabled: Bool) -> String {
        let subtype = account.subtype?.capitalized ?? account.type.rawValue.capitalized
        let mask = account.mask.map { privacyMaskEnabled ? " ••••" : " •••• \($0)" } ?? ""
        return "\(account.type.rawValue.capitalized) • \(subtype)\(mask)"
    }

    public static func rowAmountText(
        for account: AccountDTO,
        format: CurrencyFormat = .full,
        privacyMaskEnabled: Bool = false
    ) -> String {
        PrivacyMaskPresentation.currency(displayBalance(for: account), format: format, isEnabled: privacyMaskEnabled)
    }

    public static func dashboardRowSubtitle(
        for account: AccountDTO,
        connectionLabel: String,
        pendingCount: Int = 0,
        privacyMaskEnabled: Bool = false
    ) -> String {
        let mask = account.mask.map { privacyMaskEnabled ? " ••••" : " •••• \($0)" } ?? ""
        let pending = pendingCount > 0 ? " • \(pendingCount) pending" : ""
        return "\(account.institutionName ?? account.type.rawValue.capitalized)\(mask) • \(connectionLabel)\(pending)"
    }

    public static func dashboardTrailingDetailText(
        for account: AccountDTO,
        connectionLabel: String,
        format: CurrencyFormat = .compact,
        privacyMaskEnabled: Bool = false
    ) -> String {
        guard account.type == .credit else {
            return connectionLabel
        }

        let availableText = "\(PrivacyMaskPresentation.currency(availableBalance(for: account), format: format, isEnabled: privacyMaskEnabled)) available"
        let dueText = creditDueMetadataText(for: account)

        guard let utilization = account.balances.utilizationPercent else {
            return "\(availableText) • \(dueText)"
        }

        return "\(PrivacyMaskPresentation.percent(utilization, decimals: 0, isEnabled: privacyMaskEnabled)) • \(availableText) • \(dueText)"
    }

    public static func creditDueMetadataText(for account: AccountDTO) -> String {
        guard account.type == .credit else { return "" }

        // Plaid's account/balance payload does not include a card statement due
        // date in PlaidBar's local DTO today. Keep the row honest and readable
        // instead of implying a budgeting workflow or silently omitting due state.
        return "due not synced"
    }

    public static func dashboardAvailableTitle(for account: AccountDTO) -> String {
        account.type == .credit ? "Avail Credit" : "Available"
    }

    public static func dashboardCurrentTitle(for account: AccountDTO) -> String {
        isDebt(account) ? "Owed" : "Current"
    }

    public static func dashboardUtilizationDetailText(
        for account: AccountDTO,
        threshold: Double = PlaidBarConstants.creditUtilizationWarningThreshold,
        format: CurrencyFormat = .compact,
        privacyMaskEnabled: Bool = false
    ) -> String? {
        guard let utilization = account.balances.utilizationPercent else {
            return nil
        }

        let status = utilizationStatusLabel(for: utilization, threshold: threshold)
        guard let limit = account.balances.limit, limit > 0 else {
            return "\(PrivacyMaskPresentation.percent(utilization, decimals: 0, isEnabled: privacyMaskEnabled)), \(status)"
        }

        return "\(PrivacyMaskPresentation.percent(utilization, decimals: 0, isEnabled: privacyMaskEnabled)) of \(PrivacyMaskPresentation.currency(limit, format: format, isEnabled: privacyMaskEnabled)), \(status)"
    }

    public static func rowAccessibilityLabel(
        for account: AccountDTO,
        amountText: String? = nil,
        connectionLabel: String? = nil,
        pendingCount: Int = 0,
        isSelected: Bool? = nil,
        utilizationThreshold: Double = PlaidBarConstants.creditUtilizationWarningThreshold,
        privacyMaskEnabled: Bool = false
    ) -> String {
        var components = [String]()
        components.append(account.name)
        if let institutionName = account.institutionName {
            components.append(institutionName)
        }
        components.append(account.type.rawValue.capitalized)
        if let mask = account.mask, !privacyMaskEnabled {
            components.append("Ending in \(mask)")
        }

        let balance = amountText ?? rowAmountText(for: account, privacyMaskEnabled: privacyMaskEnabled)
        components.append("\(balance)\(isDebt(account) ? " owed" : "")")

        if let utilization = account.balances.utilizationPercent {
            components.append("\(PrivacyMaskPresentation.percent(utilization, decimals: 0, isEnabled: privacyMaskEnabled)) utilization")
            components.append(utilizationStatusLabel(
                for: utilization,
                threshold: utilizationThreshold
            ))
        }

        if account.type == .credit {
            components.append("\(PrivacyMaskPresentation.currency(availableBalance(for: account), isEnabled: privacyMaskEnabled)) available credit")
            components.append(creditDueMetadataText(for: account))
        }

        if let connectionLabel {
            components.append(connectionLabel)
        }

        if pendingCount > 0 {
            components.append("\(pendingCount) pending transaction\(pendingCount == 1 ? "" : "s")")
        }

        if let isSelected {
            components.append(isSelected ? "selected" : "collapsed")
        }

        return components.joined(separator: ", ")
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
