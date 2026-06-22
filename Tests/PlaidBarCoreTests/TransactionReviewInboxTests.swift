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

    @Test("Low Plaid category confidence surfaces an otherwise-confident category for review")
    func lowConfidenceCategorySurfacesForReview() {
        // Same merchant four times so the single-occurrence newMerchant heuristic
        // never fires; a valid category so the nil/other check never fires. Only
        // Plaid's reported confidence differs.
        let low = tx(id: "low", category: .shopping, merchantName: "Acme Store", categoryConfidence: "LOW")
        let lowTwin = tx(id: "low-2", category: .shopping, merchantName: "Acme Store", categoryConfidence: "LOW")
        let high = tx(id: "high", category: .shopping, merchantName: "Acme Store", categoryConfidence: "VERY_HIGH")
        let highTwin = tx(id: "high-2", category: .shopping, merchantName: "Acme Store", categoryConfidence: "VERY_HIGH")

        let snapshot = evaluate([low, lowTwin, high, highTwin])

        // Low-confidence items surface as uncategorized; high-confidence ones,
        // having no other reason, never enter the inbox.
        #expect(snapshot.items.first(where: { $0.id == "low" })?.reasonCodes.contains(.uncategorized) == true)
        #expect(snapshot.items.contains(where: { $0.id == "high" }) == false)
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

    @Test("Clearing a category without reopening review keeps the row suppressed (the bug)")
    func clearedCategoryWhileStillReviewedStaysSuppressed() {
        // The buggy `clearReviewCategory` only nilled `userCategory`, leaving the row
        // `.reviewed`. The now-uncategorized charge SHOULD return for confirmation,
        // but `evaluate` drops a reviewed row, so it silently vanishes. This pins the
        // failure mode the fix must avoid.
        let transaction = tx(id: "cleared", category: nil, merchantName: "Needs Category")
        let stillReviewed = TransactionReviewMetadata(id: "cleared", status: .reviewed, userCategory: nil)

        let snapshot = evaluate([transaction], metadata: [stillReviewed])

        #expect(snapshot.items.contains { $0.id == "cleared" } == false)
    }

    @Test("Clearing a category AND reopening review returns the row for confirmation (the fix)")
    func clearedCategoryReopenedReappearsInInbox() {
        // `clearReviewCategory` now also resets the review metadata to needs-review
        // (status .needsReview, reviewedAt nil, reasons cleared). The uncategorized
        // charge must reappear so the user can re-confirm a category rather than have
        // it disappear from the queue.
        let transaction = tx(id: "cleared", category: nil, merchantName: "Needs Category")
        let reopened = TransactionReviewMetadata(
            id: "cleared",
            status: .needsReview,
            userCategory: nil,
            reviewedAt: nil,
            reviewReasonCodes: []
        )

        let snapshot = evaluate([transaction], metadata: [reopened])
        let item = snapshot.items.first { $0.id == "cleared" }

        #expect(item != nil)
        #expect(item?.status == .needsReview)
        #expect(item?.reasonCodes.contains(.uncategorized) == true)
    }

    @Test("Approving a high-priority (unusual-amount) charge clears it from the inbox")
    func approvingHighPriorityChargeClearsIt() {
        let transactions = [
            tx(id: "old-1", amount: 20, date: "2026-05-01", category: .foodAndDrink, merchantName: "Coffee Shop"),
            tx(id: "old-2", amount: 22, date: "2026-05-08", category: .foodAndDrink, merchantName: "Coffee Shop"),
            tx(id: "old-3", amount: 21, date: "2026-05-15", category: .foodAndDrink, merchantName: "Coffee Shop"),
            tx(id: "spike", amount: 120, date: "2026-06-01", category: .foodAndDrink, merchantName: "Coffee Shop"),
        ]

        // The spike is high-priority (unusual amount) before review.
        #expect(evaluate(transactions).items.contains { $0.id == "spike" })

        // Approving it clears it from the inbox even though the reason is
        // high-priority — the user acted, so it should not stay pinned.
        let approved = TransactionReviewMetadata(id: "spike", status: .reviewed, lastSeenAmount: 120)
        let afterApprove = evaluate(transactions, metadata: [approved])
        #expect(afterApprove.items.contains { $0.id == "spike" } == false)
    }

    @Test("A reviewed charge reopens if its amount changes afterward")
    func reviewedChargeReopensWhenAmountChanges() {
        let transactions = [
            tx(id: "old-1", amount: 20, date: "2026-05-01", category: .foodAndDrink, merchantName: "Coffee Shop"),
            tx(id: "old-2", amount: 22, date: "2026-05-08", category: .foodAndDrink, merchantName: "Coffee Shop"),
            tx(id: "old-3", amount: 21, date: "2026-05-15", category: .foodAndDrink, merchantName: "Coffee Shop"),
            tx(id: "spike", amount: 120, date: "2026-06-01", category: .foodAndDrink, merchantName: "Coffee Shop"),
        ]

        // Reviewed at $40, but the charge is now $120 — materially changed since
        // review, so it reopens as needs-review instead of staying cleared.
        let staleApproval = TransactionReviewMetadata(id: "spike", status: .reviewed, lastSeenAmount: 40)
        let snapshot = evaluate(transactions, metadata: [staleApproval])
        let spike = snapshot.items.first { $0.id == "spike" }
        #expect(spike != nil)
        #expect(spike?.status == .needsReview)
    }

    @Test("A reviewed charge reopens when its amount drifts below the unusual threshold (no other signal)")
    func reviewedChargeReopensOnSubThresholdDrift() {
        // A known, categorized merchant the inbox would not otherwise flag: several
        // similar prior charges (so it is not a new merchant), categorized (not
        // uncategorized), and a new amount close to its peers (not unusual). The
        // ONLY thing that can surface it is that it changed after review — the case
        // the empty-reasons guard used to swallow before the reopen logic ran.
        let transactions = [
            tx(id: "g-1", amount: 40, date: "2026-05-01", category: .foodAndDrink, merchantName: "Corner Grocer"),
            tx(id: "g-2", amount: 42, date: "2026-05-08", category: .foodAndDrink, merchantName: "Corner Grocer"),
            tx(id: "g-3", amount: 41, date: "2026-05-15", category: .foodAndDrink, merchantName: "Corner Grocer"),
            tx(id: "g-4", amount: 43, date: "2026-05-22", category: .foodAndDrink, merchantName: "Corner Grocer"),
            tx(id: "drift", amount: 45, date: "2026-06-01", category: .foodAndDrink, merchantName: "Corner Grocer"),
        ]

        // With no metadata the modest $45 charge trips no heuristic on its own.
        #expect(evaluate(transactions).items.contains { $0.id == "drift" } == false)

        // Reviewed when it was $41, later posted as $45 — a sub-threshold change no
        // other heuristic catches. It must still reopen as needs-review.
        let staleReview = TransactionReviewMetadata(id: "drift", status: .reviewed, lastSeenAmount: 41)
        let reopened = evaluate(transactions, metadata: [staleReview])
        let drift = reopened.items.first { $0.id == "drift" }
        #expect(drift != nil)
        #expect(drift?.status == .needsReview)
        #expect(drift?.reasonCodes.contains(.changedSinceReview) == true)

        // An unchanged reviewed charge (seen at the same $45) stays cleared.
        let cleanReview = TransactionReviewMetadata(id: "drift", status: .reviewed, lastSeenAmount: 45)
        #expect(evaluate(transactions, metadata: [cleanReview]).items.contains { $0.id == "drift" } == false)
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

    // MARK: - AND-507 on-device NL categorization precedence

    @Test("A nil-category transaction whose name resolves carries the NL suggestion but stays reviewable as uncategorized")
    func nlBackfillsResolvableMissingCategory() {
        let transaction = tx(
            id: "nl-coffee",
            name: "BLUE BOTTLE COFFEE",
            category: nil,
            merchantName: nil
        )

        let item = evaluate([transaction]).items.first(where: { $0.id == "nl-coffee" })

        // The NL tier fills `effectiveCategory` (with the "Suggested" badge), but
        // the suggestion is not yet persisted — downstream totals still group by
        // the raw `transaction.category`. So the row STAYS in the inbox flagged
        // `.uncategorized` until the user approves it (which persists it as
        // `userCategory`); otherwise the spend silently lands in "Other".
        #expect(item?.effectiveCategory == .foodAndDrink)
        #expect(item?.categorySource == .appleNaturalLanguage)
        #expect(item?.isNLSuggestedCategory == true)
        #expect(item?.reasonCodes.contains(.uncategorized) == true)
    }

    @Test("NL never wins over a user category override")
    func userOverrideBeatsNLInference() {
        let transaction = tx(
            id: "nl-user",
            name: "BLUE BOTTLE COFFEE",
            category: nil,
            merchantName: nil
        )
        let metadata = TransactionReviewMetadata(id: "nl-user", userCategory: .shopping)

        let item = evaluate([transaction], metadata: [metadata]).items.first(where: { $0.id == "nl-user" })

        // The user's choice stands; the NL tier neither overrides it nor tags
        // the row as a suggestion.
        #expect(item?.effectiveCategory == .shopping)
        #expect(item?.categorySource == nil)
        #expect(item?.isNLSuggestedCategory == false)
    }

    @Test("A LOW-confidence Plaid category with no override gets a trusted NL suggestion but stays reviewable")
    func nlBackfillsLowConfidencePlaidCategory() {
        let transaction = tx(
            id: "nl-low",
            name: "NETFLIX.COM",
            category: .other,
            merchantName: nil,
            categoryConfidence: "LOW"
        )

        let item = evaluate([transaction]).items.first(where: { $0.id == "nl-low" })

        // Same as the missing-category case: the NL suggestion is surfaced but
        // not persisted, so the item remains flagged `.uncategorized` for the
        // user to approve rather than silently dropping out of the inbox.
        #expect(item?.effectiveCategory == .entertainment)
        #expect(item?.categorySource == .appleNaturalLanguage)
        #expect(item?.reasonCodes.contains(.uncategorized) == true)
    }

    @Test("An unresolvable nil-category transaction still lands in the inbox as uncategorized")
    func unresolvableMissingCategoryStaysInInbox() {
        let transaction = tx(
            id: "nl-unknown",
            name: "SQ *KMNT LLC 9921",
            category: nil,
            merchantName: nil
        )

        let item = evaluate([transaction]).items.first(where: { $0.id == "nl-unknown" })

        #expect(item != nil)
        #expect(item?.reasonCodes.contains(.uncategorized) == true)
        #expect(item?.categorySource != .appleNaturalLanguage)
        #expect(item?.isNLSuggestedCategory == false)
    }

    @Test("A confident Plaid category is not overridden by the NL tier")
    func confidentPlaidCategoryWins() {
        let transaction = tx(
            id: "nl-plaid",
            name: "BLUE BOTTLE COFFEE",
            category: .shopping,
            merchantName: nil
        )

        let item = evaluate([transaction]).items.first(where: { $0.id == "nl-plaid" })

        #expect(item?.effectiveCategory == .shopping)
        #expect(item?.isNLSuggestedCategory == false)
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
        pendingTransactionId: String? = nil,
        categoryConfidence: String? = nil
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
            pendingTransactionId: pendingTransactionId,
            isLowConfidenceCategory: ["LOW", "UNKNOWN"].contains(categoryConfidence?.uppercased() ?? "")
        )
    }

    private func posixPermissions(at url: URL) throws -> Int {
        let attributes = try FileManager.default.attributesOfItem(atPath: url.path)
        return (attributes[.posixPermissions] as? NSNumber)?.intValue ?? -1
    }
}
