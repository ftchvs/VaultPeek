import Hummingbird
import Foundation
import NIOCore
import PlaidBarCore

struct StatusRoutes: Sendable {
    let tokenStore: TokenStore
    let billingStore: BillingSubscriptionStore
    var webhookEventStore: WebhookEventStore? = nil
    let config: ServerConfig

    func register(with group: RouterGroup<some RequestContext>) {
        group.get("status", use: getStatus)
        group.get("items", use: listItems)
    }

    @Sendable
    func getStatus(
        request: Request,
        context: some RequestContext
    ) async throws -> Response {
        let status = try await statusSnapshot(includeItems: Self.includesItems(request))

        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        let data = try encoder.encode(status)
        return Response(
            status: .ok,
            headers: [.contentType: "application/json"],
            body: .init(byteBuffer: ByteBuffer(data: data))
        )
    }

    func statusSnapshot(includeItems: Bool) async throws -> ServerStatus {
        let itemCount = try await tokenStore.itemCount()
        let lastSync = try await tokenStore.lastSyncDate()
        let syncedItemCount = try await tokenStore.syncedItemCount()
        let billingSubscription = try await billingStore.currentSubscription()
        let itemStatuses = includeItems ? try await safeItemStatuses() : nil

        return ServerStatus(
            version: PlaidBarConstants.appVersion,
            environment: config.plaidEnvironment,
            itemCount: itemCount,
            lastSync: lastSync,
            credentialsConfigured: config.credentialsConfigured,
            storagePath: config.dataDirectoryPath,
            syncReady: itemCount > 0,
            syncedItemCount: syncedItemCount,
            itemStatuses: itemStatuses,
            billingSubscription: billingSubscription
        )
    }

    @Sendable
    func listItems(
        request: Request,
        context: some RequestContext
    ) async throws -> Response {
        let dtos = try await safeItemStatuses()

        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        let data = try encoder.encode(dtos)
        return Response(
            status: .ok,
            headers: [.contentType: "application/json"],
            body: .init(byteBuffer: ByteBuffer(data: data))
        )
    }

    private func safeItemStatuses() async throws -> [ItemStatus] {
        let items = try await tokenStore.getAllItems()
        let webhookEvents = try await webhookEventStore?.latestEventsByItem() ?? [:]
        let syncCursorUpdatedAts = try await tokenStore.syncCursorUpdatedAtsByItem()
        // The sync signal is read from a *separate*, sync-only projection so a
        // later non-sync webhook (e.g. PENDING_EXPIRATION) cannot mask an earlier
        // still-pending SYNC_UPDATES_AVAILABLE. The latest-overall event still
        // drives the display fields (`lastWebhookAt`, `lastWebhookEvent`).
        let syncEvents = try await webhookEventStore?.latestSyncEventsByItem() ?? [:]
        return items.map {
            Self.safeItemStatus(
                from: $0,
                webhookEvent: webhookEvents[$0.id ?? ""],
                syncEvent: syncEvents[$0.id ?? ""],
                syncCursorUpdatedAt: syncCursorUpdatedAts[$0.id ?? ""]
            )
        }
    }

    private static func safeItemStatus(
        from item: ItemModel,
        webhookEvent: WebhookItemSignal? = nil,
        syncEvent: WebhookItemSignal? = nil,
        syncCursorUpdatedAt: Date? = nil
    ) -> ItemStatus {
        ItemStatus(
            id: item.id ?? "",
            institutionName: item.institutionName,
            status: ItemConnectionStatus(rawValue: item.status) ?? .error,
            lastSync: item.updatedAt,
            lastWebhookAt: webhookEvent?.effectiveDate,
            lastWebhookEvent: webhookEvent.map { "\($0.webhookType).\($0.webhookCode)" },
            needsSync: Self.needsPollingSync(syncEvent: syncEvent, syncCursorUpdatedAt: syncCursorUpdatedAt)
        )
    }

    /// Whether the item still has unconsumed sync work pending. Driven by the
    /// item's latest *sync-relevant* webhook (sticky — see
    /// `WebhookEventStore.latestSyncEventsByItem`), cleared once the committed
    /// transaction sync cursor advances past the sync event. Item status-only
    /// writes also update `items.updated_at`, so using the item row timestamp
    /// here would incorrectly clear a pending transaction sync when a later
    /// non-sync webhook such as `PENDING_EXPIRATION` only changed connection
    /// status.
    private static func needsPollingSync(syncEvent: WebhookItemSignal?, syncCursorUpdatedAt: Date?) -> Bool {
        guard let syncEvent else { return false }
        guard let syncCursorUpdatedAt else { return true }
        return syncCursorUpdatedAt < syncEvent.effectiveDate
    }

    static func includesItems(_ request: Request) -> Bool {
        guard let include = request.uri.queryParameters.get("include") else {
            return false
        }
        return include
            .split(separator: ",")
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() }
            .contains("items")
    }
}
