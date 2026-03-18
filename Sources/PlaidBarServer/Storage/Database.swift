import FluentKit
import Foundation

// MARK: - Item Model (Fluent)

final class ItemModel: Model, @unchecked Sendable {
    static let schema = "items"

    @ID(custom: "id", generatedBy: .user)
    var id: String?

    @Field(key: "access_token")
    var accessToken: String

    @Field(key: "institution_id")
    var institutionId: String?

    @Field(key: "institution_name")
    var institutionName: String?

    @Field(key: "status")
    var status: String

    @Timestamp(key: "created_at", on: .create)
    var createdAt: Date?

    @Timestamp(key: "updated_at", on: .update)
    var updatedAt: Date?

    init() {}

    init(
        id: String,
        accessToken: String,
        institutionId: String? = nil,
        institutionName: String? = nil
    ) {
        self.id = id
        self.accessToken = accessToken
        self.institutionId = institutionId
        self.institutionName = institutionName
        self.status = "connected"
    }
}

// MARK: - Sync Cursor Model

final class SyncCursorModel: Model, @unchecked Sendable {
    static let schema = "sync_cursors"

    @ID(custom: "item_id", generatedBy: .user)
    var id: String?

    @Field(key: "cursor")
    var cursor: String

    @Timestamp(key: "updated_at", on: .update)
    var updatedAt: Date?

    init() {}

    init(itemId: String, cursor: String) {
        self.id = itemId
        self.cursor = cursor
    }
}

// MARK: - Migrations

struct CreateItems: AsyncMigration {
    func prepare(on database: Database) async throws {
        try await database.schema("items")
            .field("id", .string, .identifier(auto: false))
            .field("access_token", .string, .required)
            .field("institution_id", .string)
            .field("institution_name", .string)
            .field("status", .string, .required)
            .field("created_at", .datetime)
            .field("updated_at", .datetime)
            .create()
    }

    func revert(on database: Database) async throws {
        try await database.schema("items").delete()
    }
}

struct CreateSyncCursors: AsyncMigration {
    func prepare(on database: Database) async throws {
        try await database.schema("sync_cursors")
            .field("item_id", .string, .identifier(auto: false))
            .field("cursor", .string, .required)
            .field("updated_at", .datetime)
            .create()
    }

    func revert(on database: Database) async throws {
        try await database.schema("sync_cursors").delete()
    }
}
