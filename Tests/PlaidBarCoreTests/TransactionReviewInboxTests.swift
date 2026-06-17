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

    @Test("Posted transaction reconciles against pending metadata stored under the pending id")
    func postedTransactionReconcilesViaPendingTransactionId() {
        // Plaid posts a pending charge as a brand-new transaction id that points
        // back to the pending id. The pending-phase metadata lives under that old
        // id, so the change must be detected across the id boundary.
        let posted = tx(
            id: "posted-new",
            amount: 58,
            name: "MERCHANT FINAL",
            category: .shopping,
            merchantName: "Merchant",
            pendingTransactionId: "pending-old"
        )
        let pendingMetadata = TransactionReviewMetadata(
            id: "pending-old",
            lastSeenAmount: 50,
            lastSeenName: "MERCHANT PENDING",
            lastSeenPending: true
        )

        let snapshot = evaluate([posted], metadata: [pendingMetadata])

        #expect(snapshot.items.map(\.id) == ["posted-new"])
        #expect(snapshot.items.first?.reasonCodes.contains(.pendingChanged) == true)
    }

    @Test("Posted transaction that settled identically stays out of the inbox")
    func postedTransactionUnchangedStaysSettled() {
        // Same amount and name as the pending phase, which was already reviewed:
        // a benign posting should not resurface the charge.
        let posted = tx(
            id: "posted-new",
            amount: 50,
            name: "MERCHANT PENDING",
            category: .shopping,
            merchantName: "Merchant",
            pendingTransactionId: "pending-old"
        )
        let pendingMetadata = TransactionReviewMetadata(
            id: "pending-old",
            status: .reviewed,
            lastSeenAmount: 50,
            lastSeenName: "MERCHANT PENDING",
            lastSeenPending: true
        )

        let snapshot = evaluate([posted], metadata: [pendingMetadata])

        #expect(snapshot.totalCount == 0)
    }

    @Test("Approving while pending does not block a changed posted charge from reopening")
    func approvedPendingChargeReopensWhenPostedDifferently() {
        let posted = tx(
            id: "posted-new",
            amount: 58,
            name: "MERCHANT FINAL",
            category: .shopping,
            merchantName: "Merchant",
            pendingTransactionId: "pending-old"
        )
        let approvedPending = TransactionReviewMetadata(
            id: "pending-old",
            status: .reviewed,
            lastSeenAmount: 50,
            lastSeenName: "MERCHANT PENDING",
            lastSeenPending: true
        )

        let snapshot = evaluate([posted], metadata: [approvedPending])

        let item = snapshot.items.first { $0.id == "posted-new" }
        #expect(item != nil)
        #expect(item?.reasonCodes.contains(.pendingChanged) == true)
        // A reopened charge is actionable again rather than reading as settled.
        #expect(item?.status == .needsReview)
    }

    @Test("Ignoring while pending does not block a changed posted charge from reopening")
    func ignoredPendingChargeReopensWhenPostedDifferently() {
        let posted = tx(
            id: "posted-new",
            amount: 58,
            name: "MERCHANT FINAL",
            category: .shopping,
            merchantName: "Merchant",
            pendingTransactionId: "pending-old"
        )
        let ignoredPending = TransactionReviewMetadata(
            id: "pending-old",
            status: .ignored,
            lastSeenAmount: 50,
            lastSeenName: "MERCHANT PENDING",
            lastSeenPending: true
        )

        let snapshot = evaluate([posted], metadata: [ignoredPending])

        let item = snapshot.items.first { $0.id == "posted-new" }
        #expect(item != nil)
        #expect(item?.reasonCodes.contains(.pendingChanged) == true)
    }

    @Test("Posted charge with its own fresh metadata still detects the pending change")
    func postedTransactionWithSeededMetadataStillReconciles() {
        // Mirrors production: the posted charge is seeded with its own fresh
        // metadata (pending = false) while the pending-phase record survives under
        // the old id. The change must still be detected via the prior record.
        let posted = tx(
            id: "posted-new",
            amount: 58,
            name: "MERCHANT FINAL",
            category: .shopping,
            merchantName: "Merchant",
            pendingTransactionId: "pending-old"
        )
        let seededPosted = TransactionReviewMetadata(
            id: "posted-new",
            lastSeenAmount: 58,
            lastSeenName: "MERCHANT FINAL",
            lastSeenPending: false
        )
        let pendingMetadata = TransactionReviewMetadata(
            id: "pending-old",
            lastSeenAmount: 50,
            lastSeenName: "MERCHANT PENDING",
            lastSeenPending: true
        )

        let snapshot = evaluate([posted], metadata: [seededPosted, pendingMetadata])

        #expect(snapshot.items.first?.reasonCodes.contains(.pendingChanged) == true)
    }

    @Test("Posted charge that settled unchanged keeps the pending-phase review even with a seeded own record")
    func postedUnchangedWithSeededOwnRecordStaysReviewed() {
        // Production seeds a fresh `.needsReview` record under the posted id before
        // the evaluator runs. A charge the user already reviewed while pending, that
        // then posts unchanged, must stay settled — the seeded baseline must not
        // mask the carried-forward review (regression for the lost-status bug).
        let posted = tx(
            id: "posted-new",
            amount: 50,
            name: "MERCHANT PENDING",
            category: .shopping,
            merchantName: "Merchant",
            pendingTransactionId: "pending-old"
        )
        let seededPosted = TransactionReviewMetadata(
            id: "posted-new",
            lastSeenAmount: 50,
            lastSeenName: "MERCHANT PENDING",
            lastSeenPending: false
        )
        let reviewedPending = TransactionReviewMetadata(
            id: "pending-old",
            status: .reviewed,
            userCategory: .foodAndDrink,
            lastSeenAmount: 50,
            lastSeenName: "MERCHANT PENDING",
            lastSeenPending: true
        )

        let snapshot = evaluate([posted], metadata: [seededPosted, reviewedPending])

        #expect(snapshot.totalCount == 0)
    }

    @Test("Posted charge resolved under its own id does not reopen from the stale pending baseline")
    func resolvedPostedDoesNotReopenFromPendingBaseline() {
        // After a changed charge posts and the user reviews it under the posted id,
        // the old pending record (different amount, lastSeenPending) must no longer
        // drive `.pendingChanged`, or the charge reopens on every refresh forever.
        let posted = tx(
            id: "posted-new",
            amount: 58,
            name: "MERCHANT FINAL",
            category: .shopping,
            merchantName: "Merchant",
            pendingTransactionId: "pending-old"
        )
        let resolvedPosted = TransactionReviewMetadata(
            id: "posted-new",
            status: .reviewed,
            lastSeenAmount: 58,
            lastSeenName: "MERCHANT FINAL",
            lastSeenPending: false
        )
        let pendingOld = TransactionReviewMetadata(
            id: "pending-old",
            status: .reviewed,
            lastSeenAmount: 50,
            lastSeenName: "MERCHANT PENDING",
            lastSeenPending: true
        )

        let snapshot = evaluate([posted], metadata: [resolvedPosted, pendingOld])

        #expect(snapshot.items.contains { $0.id == "posted-new" } == false)
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

    @Test("A matching rule does not hide a high-priority spike")
    func ruleMatchDoesNotSuppressHighPrioritySignal() {
        let transactions = [
            tx(id: "old-1", amount: 20, date: "2026-05-01", category: .foodAndDrink, merchantName: "Coffee Shop"),
            tx(id: "old-2", amount: 22, date: "2026-05-08", category: .foodAndDrink, merchantName: "Coffee Shop"),
            tx(id: "old-3", amount: 21, date: "2026-05-15", category: .foodAndDrink, merchantName: "Coffee Shop"),
            tx(id: "spike", amount: 400, date: "2026-06-01", category: .foodAndDrink, merchantName: "Coffee Shop"),
        ]
        // A rule normalizes routine Coffee Shop charges, but a large spike must
        // still surface for review rather than being hidden by the rule.
        let rule = TransactionRule(
            matchMerchantContains: "Coffee Shop",
            category: .foodAndDrink,
            merchantName: "Coffee Shop"
        )

        let snapshot = evaluate(transactions, rules: [rule])

        let spike = snapshot.items.first { $0.id == "spike" }
        #expect(spike != nil)
        #expect(spike?.reasonCodes.contains(.unusualAmount) == true)
        // Routine same-merchant charges that only match the rule stay suppressed.
        #expect(snapshot.items.contains { $0.id == "old-1" } == false)
    }

    @Test("Review storage is scoped to the cache context")
    func reviewStorageScopedToCacheContext() throws {
        let root = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        let directory = root.appendingPathComponent(".vaultpeek", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }

        let sandboxContext = TransactionCacheContext(environment: .sandbox, storagePath: directory.path)
        let productionContext = TransactionCacheContext(environment: .production, storagePath: directory.path)

        let sandboxMetadata = [TransactionReviewMetadata(id: "sandbox-txn", status: .reviewed)]
        let sandboxRules = [
            TransactionRule(matchMerchantContains: "Sandbox Only", category: .shopping, merchantName: "Sandbox Only"),
        ]

        try LocalDataStore.saveTransactionReviewMetadata(sandboxMetadata, to: directory, context: sandboxContext)
        try LocalDataStore.saveTransactionRules(sandboxRules, to: directory, context: sandboxContext)

        // Production context must not see sandbox review state.
        #expect(try LocalDataStore.loadTransactionReviewMetadata(from: directory, context: productionContext).isEmpty)
        #expect(try LocalDataStore.loadTransactionRules(from: directory, context: productionContext).isEmpty)
        // Sandbox context reads back its own state.
        #expect(try LocalDataStore.loadTransactionReviewMetadata(from: directory, context: sandboxContext) == sandboxMetadata)
        #expect(try LocalDataStore.loadTransactionRules(from: directory, context: sandboxContext) == sandboxRules)
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
        merchantName: String?,
        pending: Bool = false,
        pendingTransactionId: String? = nil
    ) -> TransactionDTO {
        TransactionDTO(
            id: id,
            accountId: "test-account",
            amount: amount,
            date: date,
            name: name,
            merchantName: merchantName,
            category: category,
            pending: pending,
            pendingTransactionId: pendingTransactionId
        )
    }

    private func posixPermissions(at url: URL) throws -> Int {
        let attributes = try FileManager.default.attributesOfItem(atPath: url.path)
        return (attributes[.posixPermissions] as? NSNumber)?.intValue ?? -1
    }
}
