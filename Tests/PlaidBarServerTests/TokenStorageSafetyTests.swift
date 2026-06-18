import FluentKit
import FluentSQLiteDriver
import Foundation
import HummingbirdFluent
import Logging
@testable import PlaidBarCore
@testable import PlaidBarServer
import Testing

/// Keychain-backed tests are gated behind `PLAIDBAR_TEST_KEYCHAIN` and write to
/// an isolated, swept test service so the default `swift test` run never touches
/// the developer's login keychain. See `KeychainTestSupport`.
private let tokenVaultKeychainAvailable = keychainTestSupportAvailable

/// Token and storage safety invariants (PR-012, T056-T060): access-token
/// bytes live only in the Keychain, SQLite rows hold only
/// `keychain:<item_id>` references, storage files stay private, and the
/// status payload never carries token-like values.
///
/// These tests only ever create Keychain entries under the isolated test
/// service (`keychainTestService`), never the production service, so a
/// developer machine with real linked items is never touched.
@Suite("Token and storage safety")
struct TokenStorageSafetyTests {
    @Test(
        "SQLite rows hold only keychain references across the item lifecycle",
        .enabled(if: tokenVaultKeychainAvailable, "macOS Keychain accepts test writes")
    )
    func sqliteRowsHoldOnlyKeychainReferences() async throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("plaidbar-token-store-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }

        let itemId = "test_item_\(UUID().uuidString)"
        let rawToken = "access-sandbox-\(UUID().uuidString)"
        defer {
            try? PlaidTokenVault.delete(
                storedToken: PlaidTokenVault.reference(for: itemId),
                fallbackItemId: itemId,
                service: keychainTestService
            )
        }
        let databasePath = directory.appendingPathComponent("plaidbar-sandbox.sqlite").path
        let logger = Logger(label: "com.ftchvs.plaidbar-server-tests.token-safety")

        // First server lifetime: link an item and verify the stored row.
        try await withTokenStore(databasePath: databasePath, logger: logger) { store in
            try await store.saveItem(
                id: itemId,
                accessToken: rawToken,
                institutionId: "ins_sandbox",
                institutionName: "Test Bank"
            )

            let row = try #require(try await store.getItem(id: itemId))
            #expect(row.accessToken == "keychain:\(itemId)")
            #expect(row.providerID == .plaid)
            #expect(row.provider == ProviderID.plaid.rawValue)
            #expect(!row.accessToken.contains(rawToken))
            // The vault still resolves the reference back to the raw token.
            #expect(try store.accessToken(for: row) == rawToken)

            // Status updates (sync error paths) must not rewrite the stored
            // reference with resolved token bytes.
            try await store.updateItemStatus(id: itemId, status: "error")
            let updated = try #require(try await store.getItem(id: itemId))
            #expect(updated.accessToken == "keychain:\(itemId)")
        }

        // With the database fully flushed and closed, the raw token bytes
        // must not appear anywhere in the SQLite store or its sidecars —
        // only the keychain reference may be persisted.
        var combinedStoreBytes = Data()
        for storePath in [databasePath, databasePath + "-wal", databasePath + "-shm", databasePath + "-journal"]
            where FileManager.default.fileExists(atPath: storePath)
        {
            let contents = try Data(contentsOf: URL(fileURLWithPath: storePath))
            #expect(
                contents.range(of: Data(rawToken.utf8)) == nil,
                "Raw access token bytes leaked into \(URL(fileURLWithPath: storePath).lastPathComponent)"
            )
            combinedStoreBytes.append(contents)
        }
        #expect(combinedStoreBytes.range(of: Data("keychain:\(itemId)".utf8)) != nil)

        // Second server lifetime: the reference survives a restart, and
        // deleting the item removes both the row and the Keychain bytes.
        try await withTokenStore(databasePath: databasePath, logger: logger) { store in
            let restored = try #require(try await store.getItem(id: itemId))
            #expect(restored.accessToken == "keychain:\(itemId)")
            #expect(restored.providerID == .plaid)

            try await store.deleteItem(id: itemId)
            #expect(try await store.getItem(id: itemId) == nil)
        }

        #expect(throws: PlaidTokenVaultError.self) {
            _ = try PlaidTokenVault.resolve(storedToken: PlaidTokenVault.reference(for: itemId), service: keychainTestService)
        }
    }

    @Test(
        "Vault delete tolerates legacy plaintext rows and missing entries",
        .enabled(if: tokenVaultKeychainAvailable, "macOS Keychain accepts test writes")
    )
    func vaultDeleteToleratesLegacyPlaintextAndMissingEntries() throws {
        let itemId = "test_item_\(UUID().uuidString)"

        // Legacy rows stored the token bytes directly in SQLite. Deleting
        // such an item must not throw even though no Keychain entry exists.
        try PlaidTokenVault.delete(
            storedToken: "access-sandbox-legacy-plaintext",
            fallbackItemId: itemId,
            service: keychainTestService
        )

        // Deleting an already-deleted reference is also a no-op.
        try PlaidTokenVault.delete(
            storedToken: PlaidTokenVault.reference(for: itemId),
            fallbackItemId: itemId,
            service: keychainTestService
        )
    }

    @Test(
        "Provider-scoped item lookup isolates stored providers",
        .enabled(if: tokenVaultKeychainAvailable, "macOS Keychain accepts test writes")
    )
    func providerScopedItemLookupIsolatesStoredProviders() async throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("plaidbar-provider-scope-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }

        let plaidItemId = "test_item_plaid_\(UUID().uuidString)"
        let fixtureItemId = "test_item_fixture_\(UUID().uuidString)"
        defer {
            for itemId in [plaidItemId, fixtureItemId] {
                try? PlaidTokenVault.delete(
                    storedToken: PlaidTokenVault.reference(for: itemId),
                    fallbackItemId: itemId,
                    service: keychainTestService
                )
            }
        }

        let databasePath = directory.appendingPathComponent("plaidbar-provider-scope.sqlite").path
        let logger = Logger(label: "com.ftchvs.plaidbar-server-tests.provider-scope")

        try await withTokenStore(databasePath: databasePath, logger: logger) { store in
            try await store.saveItem(
                id: plaidItemId,
                accessToken: "access-sandbox-\(UUID().uuidString)",
                institutionId: "ins_plaid",
                institutionName: "Plaid Test Bank"
            )
            try await store.saveItem(
                id: fixtureItemId,
                accessToken: "access-sandbox-\(UUID().uuidString)",
                institutionId: "ins_fixture",
                institutionName: "Fixture Test Bank",
                providerID: .fixture
            )

            let plaidItems = try await store.getAllItems(providerID: .plaid)
            let fixtureItems = try await store.getAllItems(providerID: .fixture)

            #expect(plaidItems.map(\.id).contains(plaidItemId))
            #expect(!plaidItems.map(\.id).contains(fixtureItemId))
            #expect(fixtureItems.map(\.id).contains(fixtureItemId))
            #expect(!fixtureItems.map(\.id).contains(plaidItemId))
        }
    }

    @Test("Missing item provider defaults to Plaid for legacy rows")
    func missingItemProviderDefaultsToPlaid() {
        let item = ItemModel(
            id: "legacy_item",
            accessToken: "keychain:legacy_item",
            institutionId: nil,
            institutionName: nil
        )
        item.provider = nil

        #expect(item.providerID == .plaid)
    }

    @Test("Server config load keeps the data directory private")
    func serverConfigLoadKeepsDataDirectoryPrivate() throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("plaidbar-config-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }

        // Pre-create the data directory with permissive permissions; load
        // must tighten it even when it already exists.
        let dataDirectory = directory.appendingPathComponent("data", isDirectory: true)
        try FileManager.default.createDirectory(
            at: dataDirectory,
            withIntermediateDirectories: true,
            attributes: [.posixPermissions: 0o755]
        )

        let configURL = directory.appendingPathComponent("plaidbar.conf")
        try """
        PLAID_CLIENT_ID=config-client
        PLAID_SECRET=config-secret
        PLAID_ENV=sandbox
        PLAIDBAR_DATA_DIR=\(dataDirectory.path)
        """.write(to: configURL, atomically: true, encoding: .utf8)

        _ = try ServerConfig.load(from: configURL.path)

        let authTokenURL = dataDirectory.appendingPathComponent(LocalDataStore.authTokenFilename)
        #expect(try posixPermissions(at: dataDirectory) == 0o700)
        #expect(try posixPermissions(at: authTokenURL) == 0o600)
    }

    @Test("Status payload carries no token-like values")
    func statusPayloadCarriesNoTokenLikeValues() throws {
        let status = ServerStatus(
            version: "0.8.0",
            environment: .sandbox,
            itemCount: 3,
            lastSync: Date(timeIntervalSince1970: 1_800_000_000),
            credentialsConfigured: true,
            storagePath: "/Users/example/.plaidbar",
            syncReady: true,
            syncedItemCount: 3
        )
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601

        let payload = try #require(String(data: encoder.encode(status), encoding: .utf8))

        // Value-level complement to the field-name checks in
        // PlaidBarServerTests: no Plaid token prefixes, no Keychain
        // references, and no bearer material may ever appear in /api/status.
        let forbiddenValueFragments = [
            "access-sandbox",
            "access-production",
            "public-sandbox",
            "public-production",
            "link-sandbox",
            "link-production",
            "keychain:",
            "Bearer ",
        ]
        for fragment in forbiddenValueFragments {
            #expect(!payload.contains(fragment), "Status payload contained \(fragment)")
        }
    }

    // MARK: - Helpers

    /// Runs `body` against a TokenStore backed by a real SQLite file, and
    /// always shuts the Fluent stack down so WAL contents are flushed into
    /// the main store before callers inspect raw bytes.
    private func withTokenStore(
        databasePath: String,
        logger: Logger,
        _ body: (TokenStore) async throws -> Void
    ) async throws {
        let fluent = Fluent(logger: logger)
        fluent.databases.use(.sqlite(.file(databasePath)), as: .sqlite)
        await fluent.migrations.add(CreateItems())
        await fluent.migrations.add(AddProviderToItems())
        await fluent.migrations.add(AddOriginToItems())
        await fluent.migrations.add(CreateSyncCursors())

        var bodyError: Error?
        do {
            try await fluent.migrate()
            try await body(TokenStore(fluent: fluent, logger: logger, keychainService: keychainTestService))
        } catch {
            bodyError = error
        }
        try await fluent.shutdown()
        if let bodyError {
            throw bodyError
        }
    }

    private func posixPermissions(at url: URL) throws -> Int {
        let attributes = try FileManager.default.attributesOfItem(atPath: url.path)
        return (attributes[.posixPermissions] as? NSNumber)?.intValue ?? -1
    }
}
