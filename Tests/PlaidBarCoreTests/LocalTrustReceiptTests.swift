@testable import PlaidBarCore
import Testing

@Suite("Local Trust Receipt Tests")
struct LocalTrustReceiptTests {
    @Test("Settings receipt explains storage and local-first boundaries")
    func settingsReceiptExplainsStorageAndPrivacyBoundaries() {
        let receipt = LocalTrustReceipt.settingsReceipt(storagePath: "~/.plaidbar")

        #expect(receipt.title == "Local Trust Receipt")
        #expect(receipt.subtitle.contains("on this Mac"))
        #expect(receipt.rows.map(\.id) == ["storage", "network", "plaid", "reset"])
        #expect(receipt.rows[0].detail.contains("~/.plaidbar"))
        #expect(receipt.rows[1].detail.contains("No VaultPeek-hosted backend"))
        #expect(receipt.rows[1].detail.contains("analytics"))
        #expect(receipt.rows[1].detail.contains("telemetry"))
        #expect(receipt.rows[1].detail.contains("cloud sync"))
        #expect(receipt.rows[2].detail.contains("sandbox or production"))
        #expect(receipt.rows[2].detail.contains("demo mode stays local"))
        #expect(receipt.rows[3].detail.contains("preserves server.conf and app/server auth"))
        #expect(receipt.footer.contains("does not revoke bank permissions"))
        #expect(receipt.footer.contains("Plaid Dashboard"))
    }

    @Test("Settings receipt falls back to default storage label for blank path")
    func settingsReceiptFallsBackForBlankStoragePath() {
        let receipt = LocalTrustReceipt.settingsReceipt(storagePath: "   ")

        #expect(receipt.rows.first?.detail.contains(LocalDataStore.displayPath) == true)
    }
}
