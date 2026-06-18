import Foundation
@testable import PlaidBarCore
import Testing

@Suite("Where Your Data Lives Receipt Tests")
struct WhereYourDataLivesReceiptTests {
    @Test("Receipt names the 127.0.0.1 loopback boundary as a dedicated row")
    func receiptIncludesLoopbackRow() {
        let receipt = LocalTrustReceipt.whereYourDataLives(storagePath: "~/.vaultpeek/")
        let loopback = receipt.rows.first { $0.id == "loopback" }
        #expect(loopback != nil)
        #expect(loopback?.detail.contains("127.0.0.1") == true)
    }

    @Test("Receipt names both SQLite and Keychain")
    func receiptNamesSQLiteAndKeychain() {
        let receipt = LocalTrustReceipt.whereYourDataLives(storagePath: "~/.vaultpeek/")
        let joined = receipt.rows.map(\.detail).joined(separator: " ")
        #expect(joined.contains("SQLite"))
        #expect(joined.contains("Keychain"))
    }

    @Test("Loopback row asserts no telemetry, analytics, or cloud sync")
    func loopbackRowAssertsNoTelemetry() {
        let receipt = LocalTrustReceipt.whereYourDataLives(storagePath: "~/.vaultpeek/")
        let loopbackDetail = receipt.rows.first { $0.id == "loopback" }?.detail ?? ""
        #expect(loopbackDetail.contains("telemetry"))
        #expect(loopbackDetail.contains("analytics"))
        #expect(loopbackDetail.contains("cloud sync"))
    }

    @Test("Blank storage path falls back to LocalDataStore.displayPath")
    func blankStoragePathFallsBack() {
        let receipt = LocalTrustReceipt.whereYourDataLives(storagePath: "   ")
        let sqliteRow = receipt.rows.first { $0.id == "sqlite" }
        #expect(sqliteRow?.detail.contains(LocalDataStore.displayPath) == true)
    }

    @Test("Storage path renders in the SQLite row")
    func storagePathRendersInSQLiteRow() {
        let receipt = LocalTrustReceipt.whereYourDataLives(storagePath: "~/.vaultpeek/")
        let sqliteRow = receipt.rows.first { $0.id == "sqlite" }
        #expect(sqliteRow?.detail.contains("~/.vaultpeek/") == true)
    }

    @Test("Plaid deletion deep link is non-nil and matches the constant")
    func plaidDeletionDeepLinkPresent() {
        let receipt = LocalTrustReceipt.whereYourDataLives(storagePath: "~/.vaultpeek/")
        #expect(receipt.deepLink != nil)
        #expect(receipt.deepLink?.urlString == PlaidBarConstants.plaidDataDeletionURL)
    }

    @Test("Rows preserve a stable id order for snapshot stability")
    func rowsPreserveStableOrder() {
        let receipt = LocalTrustReceipt.whereYourDataLives(storagePath: "~/.vaultpeek/")
        #expect(receipt.rows.map(\.id) == ["sqlite", "keychain", "loopback", "plaid-scope"])
    }

    @Test("Every row pairs an SF Symbol with text (never color-alone)")
    func everyRowPairsSymbolWithText() {
        let receipt = LocalTrustReceipt.whereYourDataLives(storagePath: "~/.vaultpeek/")
        for row in receipt.rows {
            #expect(!row.systemImage.isEmpty)
            #expect(!row.title.isEmpty)
            #expect(!row.detail.isEmpty)
        }
    }

    @Test("Plaid privacy and deletion URLs are well-formed https URLs")
    func plaidURLsAreWellFormed() {
        for raw in [PlaidBarConstants.plaidPrivacyURL, PlaidBarConstants.plaidDataDeletionURL] {
            let url = URL(string: raw)
            #expect(url != nil)
            #expect(url?.scheme == "https")
        }
    }
}
