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

    @Test("Cached peer aggregates match the per-row scan on a mixed fixture")
    func unusualAmountMatchesBruteForceScan() {
        let transactions = unusualFixture()

        let snapshot = evaluate(transactions)
        let optimized = Set(
            snapshot.items
                .filter { $0.reasonCodes.contains(.unusualAmount) }
                .map(\.id)
        )

        // `.unusualAmount` is high priority, so any transaction the heuristic
        // flags surfaces an item carrying that reason — no suppression hides it.
        // Comparing against a frozen brute-force replica of the original
        // per-row scan proves the O(1) aggregate lookup is semantics-preserving.
        let bruteForce = Set(
            transactions
                .filter { referenceIsUnusual($0, in: transactions) }
                .map(\.id)
        )

        #expect(optimized == bruteForce)
        // Guard the fixture itself stays meaningful: it must exercise both the
        // flagged and unflagged paths so the equivalence check is not vacuous.
        #expect(!bruteForce.isEmpty)
        #expect(bruteForce.count < transactions.count)
    }

    /// Frozen replica of the original O(n^2) `isUnusual` decision, used only as
    /// a test oracle for the cached-aggregate implementation.
    private func referenceIsUnusual(
        _ transaction: TransactionDTO,
        in allTransactions: [TransactionDTO]
    ) -> Bool {
        guard transaction.amount > 0 else { return false }
        let spend = allTransactions.filter { !$0.isIncome }
        let category = transaction.category
        let merchantKey = (transaction.merchantName ?? transaction.name)
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .lowercased()
        var peers = spend.filter {
            let key = ($0.merchantName ?? $0.name)
                .trimmingCharacters(in: .whitespacesAndNewlines)
                .lowercased()
            return $0.id != transaction.id && key == merchantKey && abs($0.amount) > 0
        }
        if peers.count < 3, let category {
            peers = spend.filter {
                $0.id != transaction.id && $0.category == category && abs($0.amount) > 0
            }
        }
        guard peers.count >= 3 else { return false }
        let average = peers.map { abs($0.amount) }.reduce(0, +) / Double(peers.count)
        return transaction.displayAmount >= max(average * 1.75, average + 50)
    }

    private func unusualFixture() -> [TransactionDTO] {
        var fixture: [TransactionDTO] = []

        // Stable same-merchant cluster plus a spike (merchant-peer path).
        fixture += [
            tx(id: "coffee-1", amount: 20, date: "2026-05-01", category: .foodAndDrink, merchantName: "Coffee Shop"),
            tx(id: "coffee-2", amount: 22, date: "2026-05-08", category: .foodAndDrink, merchantName: "Coffee Shop"),
            tx(id: "coffee-3", amount: 21, date: "2026-05-15", category: .foodAndDrink, merchantName: "Coffee Shop"),
            tx(id: "coffee-spike", amount: 120, date: "2026-06-01", category: .foodAndDrink, merchantName: "Coffee Shop"),
        ]

        // Distinct merchants sharing a category force the category-fallback path
        // (each merchant has < 3 peers on its own).
        fixture += [
            tx(id: "shop-a", amount: 30, date: "2026-05-02", category: .shopping, merchantName: "Store A"),
            tx(id: "shop-b", amount: 35, date: "2026-05-09", category: .shopping, merchantName: "Store B"),
            tx(id: "shop-c", amount: 28, date: "2026-05-16", category: .shopping, merchantName: "Store C"),
            tx(id: "shop-spike", amount: 400, date: "2026-06-02", category: .shopping, merchantName: "Store D"),
        ]

        // A near-threshold charge that must NOT trip the heuristic.
        fixture += [
            tx(id: "gym-1", amount: 50, date: "2026-05-03", category: .entertainment, merchantName: "Gym"),
            tx(id: "gym-2", amount: 50, date: "2026-05-10", category: .entertainment, merchantName: "Gym"),
            tx(id: "gym-3", amount: 50, date: "2026-05-17", category: .entertainment, merchantName: "Gym"),
            tx(id: "gym-normal", amount: 60, date: "2026-06-03", category: .entertainment, merchantName: "Gym"),
        ]

        // Income rows (negative amount) that the spend filter must drop entirely.
        fixture += [
            tx(id: "paycheck-1", amount: -2_000, date: "2026-05-15", category: .other, merchantName: "Employer"),
            tx(id: "paycheck-2", amount: -2_000, date: "2026-06-15", category: .other, merchantName: "Employer"),
        ]

        // Lone transaction with no peers — never unusual.
        fixture.append(tx(id: "solo", amount: 75, date: "2026-06-04", category: .travel, merchantName: "One Off"))

        return fixture
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
