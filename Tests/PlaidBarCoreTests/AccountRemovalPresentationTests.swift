import Testing
@testable import PlaidBarCore

@Suite("Account removal presentation")
struct AccountRemovalPresentationTests {
    @Test("Unmasked removal dialog names the institution and exact local removal counts")
    func unmaskedCopyPreservesExplicitWarning() {
        #expect(
            AccountPresentation.removalDialogTitle(
                institutionName: "Acme Bank",
                privacyMaskEnabled: false
            ) == "Remove Acme Bank?"
        )

        #expect(
            AccountPresentation.removalDialogMessage(
                linkedAccountCount: 2,
                cachedTransactionCount: 47,
                privacyMaskEnabled: false
            ) == "This disconnects the linked Plaid institution and removes 2 linked accounts plus 47 cached local transactions from VaultPeek. It does not close any bank account."
        )
    }

    @Test("Masked removal dialog withholds institution names and exact counts")
    func maskedCopyWithholdsPrivateDetails() {
        let title = AccountPresentation.removalDialogTitle(
            institutionName: "Acme Bank",
            privacyMaskEnabled: true
        )
        let message = AccountPresentation.removalDialogMessage(
            linkedAccountCount: 2,
            cachedTransactionCount: 47,
            privacyMaskEnabled: true
        )

        #expect(title == "Remove linked institution?")
        #expect(!title.contains("Acme Bank"))
        #expect(!message.contains("Acme Bank"))
        #expect(!message.contains("2 linked accounts"))
        #expect(!message.contains("47 cached local transactions"))
        #expect(message.contains("linked accounts"))
        #expect(message.contains("cached local transactions"))
    }

    @Test("Unmasked removal dialog clamps linked account count to one")
    func unmaskedCopyClampsMissingAccountCount() {
        #expect(
            AccountPresentation.removalDialogMessage(
                linkedAccountCount: 0,
                cachedTransactionCount: 1,
                privacyMaskEnabled: false
            ).contains("1 linked account plus 1 cached local transaction")
        )
    }
}
