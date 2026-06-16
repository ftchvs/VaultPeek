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

        let label = AccountPresentation.rowAccessibilityLabel(
            for: account,
            connectionLabel: "Synced",
            privacyMaskEnabled: true
        )
        #expect(label.contains("Ending in 1234") == false)
        #expect(label.contains("•••• owed"))
        #expect(label.contains("•••• available credit"))
        #expect(label.contains("•••• utilization"))
    }
}