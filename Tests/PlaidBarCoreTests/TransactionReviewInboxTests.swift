import Foundation
@testable import PlaidBarCore
import Testing

@Suite("Transaction Review Inbox Tests")
struct TransactionReviewInboxTests {
    private let now = Date(timeIntervalSince1970: 1_800_000_000)

    @Test("Uncategorized transactions enter the inbox")
    func uncategorizedTransactionEntersInbox() {
        let transaction = tx(id: "uncategorized", category: nil, merchantName: "Corner Store")

        let snapshot = evaluate([transaction])

        #expect(snapshot.items.map(\.id) == ["uncategorized"])
        #expect(snapshot.items.first?.reasonCodes.contains(.uncategorized) == true)
    }

    @Test("New merchant is reviewed without exposing provider identifiers")
    func newMerchantReason() {
        let transaction = tx(id: "new-merchant", category: .shopping, merchantName: "Desk Supply")

        let snapshot = evaluate([transaction])

        #expect(snapshot.totalCount == 1)
        #expect(snapshot.items.first?.reasonCodes == [.newMerchant])
    }

    @Test("Unusual merchant amount is high priority")
    func unusualAmountReason() {
        let transactions = [
            tx(id: "old-1", amount: 20, date: "2026-05-01", category: .foodAndDrink, merchantName: "Coffee Shop"),
            tx(id: "old-2", amount: 22, date: "2026-05-08", category: .foodAndDrink, merchantName: "Coffee Shop"),
            tx(id: "old-3", amount: 21, date: "2026-05-15", category: .foodAndDrink, merchantName: "Coffee Shop"),
            tx(id: "spike", amount: 120, date: "2026-06-01", category: .foodAndDrink, merchantName: "Coffee Shop"),
        ]

        let snapshot = evaluate(transactions)

        #expect(snapshot.items.first(where: { $0.id == "spike" })?.reasonCodes.contains(.unusualAmount) == true)
        #expect(snapshot.highPriorityCount >= 1)
    }

    @Test("Possible transfer is flagged until marked transfer")
    func possibleTransferReason() {
        let transaction = tx(
            id: "transfer",
            amount: 1_250,
            name: "CHASE CREDIT CARD PAYMENT",
            category: .other,
            merchantName: "Chase Credit Card"
        )

        let snapshot = evaluate([transaction])
        let reviewed = evaluate(
            [transaction],
            metadata: [
                TransactionReviewMetadata(
                    id: "transfer",
                    isTransferOverride: true,
                    excludedFromBudgets: true
                ),
            ]
        )

        #expect(snapshot.items.first?.reasonCodes.contains(.possibleTransfer) == true)
        #expect(reviewed.items.first?.reasonCodes.contains(.possibleTransfer) == false)
    }

    @Test("Recurring price increase is flagged")
    func recurringChangedReason() {
        let transaction = tx(id: "stream-latest", amount: 18, date: "2026-06-01", category: .entertainment, merchantName: "StreamCo")
        let recurring = RecurringTransaction(
            merchantName: "StreamCo",
            frequency: .monthly,
            averageAmount: 14,
            latestAmount: 18,
            trailingAverageAmount: 12,
            lastDate: "2026-06-01",
            nextExpectedDate: "2026-07-01",
            category: .entertainment,
            transactionCount: 4,
            confidence: 0.9
        )

        let snapshot = evaluate([transaction], recurring: [recurring])

        #expect(snapshot.items.first?.reasonCodes.contains(.recurringChanged) == true)
    }

    @Test("Posted transaction with changed pending signature is flagged")
    func pendingChangedReason() {
        let transaction = tx(id: "posted", amount: 42, name: "MERCHANT FINAL", category: .shopping, merchantName: "Merchant")
        let metadata = TransactionReviewMetadata(
            id: "posted",
            lastSeenAmount: 40,
            lastSeenName: "MERCHANT PENDING",
            lastSeenPending: true
        )

        let snapshot = evaluate([transaction], metadata: [metadata])

        #expect(snapshot.items.first?.reasonCodes.contains(.pendingChanged) == true)
    }

    @Test("Reviewed and ignored transactions stay out of inbox")
    func reviewedAndIgnoredAreSuppressed() {
        let reviewed = tx(id: "reviewed", category: nil, merchantName: "Needs Category")
        let ignored = tx(id: "ignored", category: nil, merchantName: "Ignored")

        let snapshot = evaluate(
            [reviewed, ignored],
            metadata: [
                TransactionReviewMetadata(id: "reviewed", status: .reviewed),
                TransactionReviewMetadata(id: "ignored", status: .ignored),
            ]
        )

        #expect(snapshot.totalCount == 0)
    }

    @Test("Rule-matched transactions stay out of inbox")
    func ruleMatchedTransactionsAreTrusted() {
        let transaction = tx(id: "rule-match", category: nil, merchantName: "Known Merchant")
        let rule = TransactionRule(
            matchMerchantContains: "Known Merchant",
            category: .shopping,
            merchantName: "Known Merchant"
        )

        let snapshot = evaluate([transaction], rules: [rule])

        #expect(snapshot.totalCount == 0)
    }

    @Test("Review metadata and rules persist as private local files")
    func reviewStoragePersistsPrivately() throws {
        let root = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        let directory = root.appendingPathComponent(".vaultpeek", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: root) }

        let metadata = [
            TransactionReviewMetadata(
                id: "synthetic-txn",
                status: .reviewed,
                userCategory: .shopping,
                userMerchantName: "Synthetic Merchant",
                reviewedAt: now
            ),
        ]
        let rules = [
            TransactionRule(
                id: UUID(uuidString: "11111111-1111-1111-1111-111111111111")!,
                matchMerchantContains: "Synthetic Merchant",
                category: .shopping,
                merchantName: "Synthetic Merchant",
                createdAt: now
            ),
        ]

        try LocalDataStore.saveTransactionReviewMetadata(metadata, to: directory)
        try LocalDataStore.saveTransactionRules(rules, to: directory)

        #expect(try LocalDataStore.loadTransactionReviewMetadata(from: directory) == metadata)
        #expect(try LocalDataStore.loadTransactionRules(from: directory) == rules)
        #expect(try posixPermissions(at: directory) == 0o700)
        #expect(try posixPermissions(at: LocalDataStore.transactionReviewMetadataURL(in: directory)) == 0o600)
        #expect(try posixPermissions(at: LocalDataStore.transactionRulesURL(in: directory)) == 0o600)

        _ = try LocalDataStore.resetLocalData(at: directory, resetKeychainTokens: false)

        #expect(try LocalDataStore.loadTransactionReviewMetadata(from: directory).isEmpty)
        #expect(try LocalDataStore.loadTransactionRules(from: directory).isEmpty)
    }

    private func evaluate(
        _ transactions: [TransactionDTO],
        metadata: [TransactionReviewMetadata] = [],
        rules: [TransactionRule] = [],
        recurring: [RecurringTransaction] = []
    ) -> TransactionReviewInboxSnapshot {
        TransactionReviewInbox.evaluate(
            transactions: transactions,
            metadata: metadata,
            rules: rules,
            recurring: recurring,
            now: now
        )
    }

    private func tx(
        id: String,
        amount: Double = 12,
        date: String = "2026-06-01",
        name: String = "MERCHANT",
        category: SpendingCategory?,
        merchantName: String?
    ) -> TransactionDTO {
        TransactionDTO(
            id: id,
            accountId: "test-account",
            amount: amount,
            date: date,
            name: name,
            merchantName: merchantName,
            category: category
        )
    }

    private func posixPermissions(at url: URL) throws -> Int {
        let attributes = try FileManager.default.attributesOfItem(atPath: url.path)
        return (attributes[.posixPermissions] as? NSNumber)?.intValue ?? -1
    }
}
