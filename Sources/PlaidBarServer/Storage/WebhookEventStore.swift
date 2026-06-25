import FluentKit
import Foundation
import HummingbirdFluent

final class WebhookEventModel: Model, @unchecked Sendable {
    static let schema = "webhook_events"

    @ID(custom: "id", generatedBy: .user)
    var id: String?

    @Field(key: "item_id")
    var itemId: String

    @Field(key: "webhook_type")
    var webhookType: String

    @Field(key: "webhook_code")
    var webhookCode: String

    @OptionalField(key: "request_id")
    var requestId: String?

    @Field(key: "idempotency_hash")
    var idempotencyHash: String

    @Timestamp(key: "event_at", on: .none)
    var eventAt: Date?

    @Timestamp(key: "received_at", on: .none)
    var receivedAt: Date?

    init() {}

    init(
        itemId: String,
        webhookType: String,
        webhookCode: String,
        requestId: String?,
        idempotencyHash: String,
        eventAt: Date?,
        receivedAt: Date
    ) {
        self.id = idempotencyHash
        self.itemId = itemId
        self.webhookType = webhookType
        self.webhookCode = webhookCode
        self.requestId = requestId
        self.idempotencyHash = idempotencyHash
        self.eventAt = eventAt
        self.receivedAt = receivedAt
    }
}

struct CreateWebhookEvents: AsyncMigration {
    func prepare(on database: Database) async throws {
        try await database.schema(WebhookEventModel.schema)
            .field("id", .string, .identifier(auto: false))
            .field("item_id", .string, .required)
            .field("webhook_type", .string, .required)
            .field("webhook_code", .string, .required)
            .field("request_id", .string)
            .field("idempotency_hash", .string, .required)
            .field("event_at", .datetime)
            .field("received_at", .datetime)
            .unique(on: "idempotency_hash")
            .create()
    }

    func revert(on database: Database) async throws {
        try await database.schema(WebhookEventModel.schema).delete()
    }
}

struct WebhookItemSignal: Sendable {
    let itemId: String
    let webhookType: String
    let webhookCode: String
    let requestId: String?
    let idempotencyHash: String
    let eventAt: Date?
    let receivedAt: Date
    let needsSync: Bool

    var effectiveDate: Date {
        eventAt ?? receivedAt
    }
}

struct WebhookStoreResult: Sendable, Equatable {
    enum Disposition: Sendable, Equatable {
        case stored
        case duplicate
        case outOfOrder
    }

    let disposition: Disposition
}

actor WebhookEventStore {
    private let fluent: Fluent

    // Serializes `record` (existence check -> out-of-order check -> save -> the
    // caller's status RMW) per item id. The find-then-save and the downstream
    // `apply` straddle several suspending Fluent calls, so an actor method alone
    // is not atomic across them: two concurrent distinct-hash deliveries for the
    // same item could both resolve `.stored` and both apply a status mutation in
    // an interleaved, last-writer-wins fashion. A per-item in-process FIFO gate
    // (mirroring `TokenStore`'s lock idiom) fully orders deliveries for one item
    // while leaving distinct items concurrent. The companion server is a single
    // local process, so an in-process gate is sufficient.
    private var lockedItemIds: Set<String> = []
    private var itemWaiters: [String: [CheckedContinuation<Void, Never>]] = [:]

    init(fluent: Fluent) {
        self.fluent = fluent
    }

    /// Runs `body` while holding the per-item serialization lock, so the
    /// out-of-order decision, the save, and any status mutation the caller
    /// performs on `body`'s result are atomic for a single item. Distinct items
    /// never contend.
    func withItemLock<T: Sendable>(
        itemId: String,
        _ body: @Sendable () async throws -> T
    ) async rethrows -> T {
        await acquireItemLock(itemId: itemId)
        defer { releaseItemLock(itemId: itemId) }
        return try await body()
    }

    func record(_ signal: WebhookItemSignal) async throws -> WebhookStoreResult {
        if try await WebhookEventModel.find(signal.idempotencyHash, on: fluent.db()) != nil {
            return WebhookStoreResult(disposition: .duplicate)
        }

        let latest = try await latestEvent(itemId: signal.itemId)
        // Out-of-order is a statement about *event* ordering. Comparing a stored
        // `receivedAt` against a new `eventAt` (or vice versa) mixes two
        // unrelated clocks — the delivery clock and Plaid's event clock — and can
        // spuriously flag (or miss) reordering. Only decide ordering when BOTH
        // the stored latest event and the incoming signal carry an `eventAt`;
        // absent that, treat the delivery as in-order (`.stored`) and rely on the
        // status mapper to avoid regressions.
        let isOutOfOrder: Bool
        if let latestEventAt = latest?.eventAt, let signalEventAt = signal.eventAt {
            isOutOfOrder = latestEventAt > signalEventAt
        } else {
            isOutOfOrder = false
        }
        let model = WebhookEventModel(
            itemId: signal.itemId,
            webhookType: signal.webhookType,
            webhookCode: signal.webhookCode,
            requestId: signal.requestId,
            idempotencyHash: signal.idempotencyHash,
            eventAt: signal.eventAt,
            receivedAt: signal.receivedAt
        )
        do {
            try await model.save(on: fluent.db())
        } catch {
            // The find-then-save above is not atomic: two concurrent deliveries
            // of the same webhook can both pass the existence check and race to
            // insert, so one save hits the `idempotency_hash` unique constraint.
            // Re-check existence — if the row is now present, the other writer
            // won and this delivery is a duplicate (idempotent). Otherwise the
            // failure is unrelated and must propagate.
            if try await WebhookEventModel.find(signal.idempotencyHash, on: fluent.db()) != nil {
                return WebhookStoreResult(disposition: .duplicate)
            }
            throw error
        }
        return WebhookStoreResult(disposition: isOutOfOrder ? .outOfOrder : .stored)
    }

    func latestEvent(itemId: String) async throws -> WebhookItemSignal? {
        try await WebhookEventModel.query(on: fluent.db())
            .filter(\.$itemId == itemId)
            .all()
            .compactMap(Self.signal(from:))
            .max { $0.effectiveDate < $1.effectiveDate }
    }

    func latestEventsByItem() async throws -> [String: WebhookItemSignal] {
        let events = try await WebhookEventModel.query(on: fluent.db()).all()
        return events.compactMap(Self.signal(from:)).reduce(into: [:]) { result, signal in
            guard let existing = result[signal.itemId] else {
                result[signal.itemId] = signal
                return
            }
            if existing.effectiveDate < signal.effectiveDate {
                result[signal.itemId] = signal
            }
        }
    }

    /// The latest *sync-relevant* webhook per item, independent of any later
    /// non-sync delivery. `latestEventsByItem` collapses each item to its single
    /// max-`effectiveDate` event, so a later non-sync code (e.g.
    /// `PENDING_EXPIRATION`) hides an earlier still-pending
    /// `SYNC_UPDATES_AVAILABLE`, silently dropping the sync signal. Filtering to
    /// `needsSync` events *before* the max reduce keeps the sync signal sticky
    /// until the owning item's refresh advances past it (see
    /// `StatusRoutes.needsPollingSync`).
    func latestSyncEventsByItem() async throws -> [String: WebhookItemSignal] {
        let events = try await WebhookEventModel.query(on: fluent.db()).all()
        return events
            .compactMap(Self.signal(from:))
            .filter(\.needsSync)
            .reduce(into: [:]) { result, signal in
                guard let existing = result[signal.itemId] else {
                    result[signal.itemId] = signal
                    return
                }
                if existing.effectiveDate < signal.effectiveDate {
                    result[signal.itemId] = signal
                }
            }
    }

    // MARK: - Per-item serialization lock

    private func acquireItemLock(itemId: String) async {
        if !lockedItemIds.contains(itemId) {
            lockedItemIds.insert(itemId)
            return
        }
        await withCheckedContinuation { (continuation: CheckedContinuation<Void, Never>) in
            itemWaiters[itemId, default: []].append(continuation)
        }
        // Resumed: the lock was handed off to us; the id stays in `lockedItemIds`.
    }

    private func releaseItemLock(itemId: String) {
        if var waiters = itemWaiters[itemId], !waiters.isEmpty {
            let next = waiters.removeFirst()
            if waiters.isEmpty {
                itemWaiters[itemId] = nil
            } else {
                itemWaiters[itemId] = waiters
            }
            next.resume()
        } else {
            lockedItemIds.remove(itemId)
        }
    }

    /// Test seam: the number of persisted event rows for an item. Used to assert
    /// no write is lost when concurrent distinct-hash deliveries are serialized.
    func allEventCountForTest(itemId: String) async throws -> Int {
        try await WebhookEventModel.query(on: fluent.db())
            .filter(\.$itemId == itemId)
            .count()
    }

    private static func signal(from model: WebhookEventModel) -> WebhookItemSignal? {
        guard let receivedAt = model.receivedAt else { return nil }
        return WebhookItemSignal(
            itemId: model.itemId,
            webhookType: model.webhookType,
            webhookCode: model.webhookCode,
            requestId: model.requestId,
            idempotencyHash: model.idempotencyHash,
            eventAt: model.eventAt,
            receivedAt: receivedAt,
            needsSync: PlaidWebhookEvent.needsSync(webhookCode: model.webhookCode)
        )
    }
}
