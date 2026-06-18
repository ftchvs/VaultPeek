import Foundation
@testable import PlaidBarCore
import Testing

@Suite("Privacy Mask Presentation Tests")
struct PrivacyMaskPresentationTests {
    @Test("Menu bar privacy mask replaces selected summary values and preserves icon-only")
    func menuBarPrivacyMask() {
        let accounts = [
            AccountDTO(id: "checking", itemId: "item", name: "Checking", type: .depository, balances: BalanceDTO(available: 8_200)),
        ]

        #expect(MenuBarSummary.text(
            mode: .netWorth,
            accounts: accounts,
            transactions: [],
            currencyFormat: .compact,
            privacyMaskEnabled: true
        ) == "Private")

        #expect(MenuBarSummary.text(
            mode: .iconOnly,
            accounts: accounts,
            transactions: [],
            currencyFormat: .compact,
            privacyMaskEnabled: true
        ) == "")
    }

    @Test("Account presentation masks balances, utilization, account endings, and accessibility values")
    func accountPrivacyMask() {
        let account = AccountDTO(
            id: "visa",
            itemId: "item",
            name: "Visa",
            officialName: "Rewards Visa",
            type: .credit,
            subtype: "credit card",
            mask: "1234",
            balances: BalanceDTO(available: 3_750, current: -1_250, limit: 5_000)
        )

        #expect(AccountPresentation.subtitle(for: account, privacyMaskEnabled: true) == "Credit • Credit Card ••••")
        #expect(AccountPresentation.rowAmountText(for: account, privacyMaskEnabled: true) == "••••")
        #expect(AccountPresentation.dashboardRowSubtitle(
            for: account,
            connectionLabel: "Synced",
            privacyMaskEnabled: true
        ) == "Credit •••• • Synced")
        #expect(AccountPresentation.dashboardTrailingDetailText(
            for: account,
            connectionLabel: "Synced",
            privacyMaskEnabled: true
        ) == "•••• • •••• available • due not synced")
        #expect(AccountPresentation.dashboardUtilizationDetailText(
            for: account,
            privacyMaskEnabled: true
        ) == "•••• of ••••")

        let label = AccountPresentation.rowAccessibilityLabel(
            for: account,
            amountText: "$1,250.00",
            connectionLabel: "Synced",
            privacyMaskEnabled: true
        )
        #expect(label.contains("Ending in 1234") == false)
        #expect(label.contains("$1,250.00") == false)
        #expect(label.contains("•••• owed"))
        #expect(label.contains("•••• available credit"))
        #expect(label.contains("•••• utilization"))
        #expect(label.contains("Good") == false)
        #expect(label.contains("Warning") == false)
        #expect(label.contains("High") == false)
    }

    @Test("Menu bar privacy mask preserves non-sensitive empty states")
    func menuBarPrivacyMaskPreservesEmptyStates() {
        #expect(MenuBarSummary.text(
            mode: .netWorth,
            accounts: [],
            transactions: [],
            currencyFormat: .compact,
            privacyMaskEnabled: true
        ) == PlaidBarConstants.appName)

        #expect(MenuBarSummary.text(
            mode: .creditUtilization,
            accounts: [AccountDTO(id: "checking", itemId: "item", name: "Checking", type: .depository, balances: BalanceDTO(current: 120))],
            transactions: [],
            currencyFormat: .compact,
            privacyMaskEnabled: true
        ) == "No credit")

        #expect(MenuBarSummary.text(
            mode: .recentSpend,
            accounts: [],
            transactions: [],
            currencyFormat: .compact,
            privacyMaskEnabled: true
        ) == "No spend")
    }

    @Test("Quick toggle affordance carries state by glyph shape and a verb-first label")
    func quickToggleAffordance() {
        // Masked -> struck-through eye + "reveal" verb; visible -> plain eye + "hide" verb.
        #expect(PrivacyMaskPresentation.toggleSymbolName(isMasked: true) == "eye.slash")
        #expect(PrivacyMaskPresentation.toggleSymbolName(isMasked: false) == "eye")
        #expect(PrivacyMaskPresentation.toggleActionLabel(isMasked: true) == "Show amounts")
        #expect(PrivacyMaskPresentation.toggleActionLabel(isMasked: false) == "Hide amounts")
        // The glyph must differ by state so meaning never rides on color alone.
        #expect(PrivacyMaskPresentation.toggleSymbolName(isMasked: true)
            != PrivacyMaskPresentation.toggleSymbolName(isMasked: false))
    }
}