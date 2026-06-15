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

    init(fluent: Fluent) {
        self.fluent = fluent
    }

    func record(_ signal: WebhookItemSignal) async throws -> WebhookStoreResult {
        if try await WebhookEventModel.find(signal.idempotencyHash, on: fluent.db()) != nil {
            return WebhookStoreResult(disposition: .duplicate)
        }

        let latest = try await latestEvent(itemId: signal.itemId)
        let isOutOfOrder = latest.map { $0.effectiveDate > signal.effectiveDate } ?? false
        let model = WebhookEventModel(
            itemId: signal.itemId,
            webhookType: signal.webhookType,
            webhookCode: signal.webhookCode,
            requestId: signal.requestId,
            idempotencyHash: signal.idempotencyHash,
            eventAt: signal.eventAt,
            receivedAt: signal.receivedAt
        )
        try await model.save(on: fluent.db())
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
