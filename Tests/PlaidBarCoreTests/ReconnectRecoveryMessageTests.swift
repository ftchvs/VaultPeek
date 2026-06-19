import Foundation
import Testing
@testable import PlaidBarCore

@Suite("Reconnect recovery message")
struct ReconnectRecoveryMessageTests {
    @Test("Invalid update-link copy names the institution when known")
    func invalidUpdateLinkURL() {
        let named = ReconnectRecoveryMessage.invalidUpdateLinkURL(institutionName: "Acme Bank")
        #expect(named.contains("for Acme Bank"))
        #expect(named.contains("Reconnect Acme Bank"))

        let unnamed = ReconnectRecoveryMessage.invalidUpdateLinkURL(institutionName: nil)
        #expect(!unnamed.contains("for "))
        #expect(unnamed.contains("Reconnect Item"))
    }

    @Test("Browser-open-failed copy names the institution when known")
    func browserOpenFailed() {
        #expect(ReconnectRecoveryMessage.browserOpenFailed(institutionName: "Acme Bank").contains("Acme Bank"))
        #expect(ReconnectRecoveryMessage.browserOpenFailed(institutionName: nil).contains("Reconnect Item"))
    }

    @Test("Create-failed copy appends a sanitized detail when present")
    func createFailedWithDetail() {
        let message = ReconnectRecoveryMessage.createFailed(errorMessage: "The link request timed out.", institutionName: "Acme Bank")
        #expect(message.contains("Acme Bank"))
        #expect(message.contains("timed out"))
        #expect(message.contains("Reconnect Acme Bank"))
    }

    @Test("Create-failed copy omits the detail when there is no error message")
    func createFailedWithoutDetail() {
        let message = ReconnectRecoveryMessage.createFailed(errorMessage: nil, institutionName: nil)
        #expect(message.contains("could not create a reconnect link"))
        #expect(message.contains("Reconnect Item"))
    }

    @Test("Blank institution names are treated as unknown")
    func blankInstitutionName() {
        #expect(ReconnectRecoveryMessage.invalidUpdateLinkURL(institutionName: "   ").contains("Reconnect Item"))
    }
}
