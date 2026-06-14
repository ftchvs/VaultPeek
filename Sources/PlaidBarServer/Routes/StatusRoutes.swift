import Hummingbird
import Foundation
import NIOCore
import PlaidBarCore

struct StatusRoutes: Sendable {
    let tokenStore: TokenStore
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
            itemStatuses: itemStatuses
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
        return items.map(Self.safeItemStatus)
    }

    private static func safeItemStatus(from item: ItemModel) -> ItemStatus {
        ItemStatus(
            id: item.id ?? "",
            institutionName: item.institutionName,
            status: ItemConnectionStatus(rawValue: item.status) ?? .error,
            lastSync: item.updatedAt
        )
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
