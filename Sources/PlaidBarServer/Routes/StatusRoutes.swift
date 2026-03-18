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
        let itemCount = try await tokenStore.itemCount()
        let lastSync = try await tokenStore.lastSyncDate()

        let status = ServerStatus(
            version: PlaidBarConstants.appVersion,
            environment: config.plaidEnvironment,
            itemCount: itemCount,
            lastSync: lastSync
        )

        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        let data = try encoder.encode(status)
        return Response(
            status: .ok,
            headers: [.contentType: "application/json"],
            body: .init(byteBuffer: ByteBuffer(data: data))
        )
    }

    @Sendable
    func listItems(
        request: Request,
        context: some RequestContext
    ) async throws -> Response {
        let items = try await tokenStore.getAllItems()
        let dtos = items.map { item in
            ItemStatus(
                id: item.id ?? "",
                institutionName: item.institutionName,
                status: ItemConnectionStatus(rawValue: item.status) ?? .error,
                lastSync: item.updatedAt
            )
        }

        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        let data = try encoder.encode(dtos)
        return Response(
            status: .ok,
            headers: [.contentType: "application/json"],
            body: .init(byteBuffer: ByteBuffer(data: data))
        )
    }
}
