import Testing
import Foundation
@testable import PlaidBarCore
@testable import PlaidBarServer

@Suite("PlaidBarServer")
struct PlaidBarServerTests {

    @Test func accountTypes() {
        let checking = AccountDTO(id: "1", itemId: "i", name: "Checking", type: .depository, balances: BalanceDTO(current: 5000))
        let credit = AccountDTO(id: "2", itemId: "i", name: "Amex", type: .credit, balances: BalanceDTO(current: -850, limit: 10000))
        #expect(checking.type == .depository)
        #expect(credit.type == .credit)
        #expect(credit.balances.utilizationPercent! == 8.5)
    }

    @Test func environmentCodable() throws {
        let sandbox = PlaidEnvironment.sandbox
        let data = try JSONEncoder().encode(sandbox)
        let decoded = try JSONDecoder().decode(PlaidEnvironment.self, from: data)
        #expect(decoded == .sandbox)
    }

    @Test func serverStatusCodable() throws {
        let status = ServerStatus(version: "0.1.0", environment: .sandbox, itemCount: 2)
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        let data = try encoder.encode(status)
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        let decoded = try decoder.decode(ServerStatus.self, from: data)
        #expect(decoded.version == "0.1.0")
        #expect(decoded.environment == .sandbox)
        #expect(decoded.itemCount == 2)
        #expect(decoded.credentialsConfigured)
        #expect(decoded.storagePath == LocalDataStore.displayPath)
        #expect(decoded.syncReady)
    }

    @Test func serverDatabasePathIsScopedByPlaidEnvironment() {
        let dataDir = "/tmp/plaidbar-test-data"

        let sandboxPath = ServerConfig.databasePath(in: dataDir, environment: .sandbox)
        let productionPath = ServerConfig.databasePath(in: dataDir, environment: .production)

        #expect(sandboxPath.hasSuffix("/plaidbar-sandbox.sqlite"))
        #expect(productionPath.hasSuffix("/plaidbar-production.sqlite"))
        #expect(sandboxPath != productionPath)
    }

    @Test func serverCopiesLegacyDatabaseIntoFirstScopedEnvironment() throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("plaidbar-config-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }

        let legacyURL = directory.appendingPathComponent(ServerConfig.legacyDatabaseFilename)
        try Data("legacy".utf8).write(to: legacyURL)
        try Data("wal".utf8).write(to: URL(fileURLWithPath: legacyURL.path + "-wal"))
        try Data("shm".utf8).write(to: URL(fileURLWithPath: legacyURL.path + "-shm"))
        try Data("journal".utf8).write(to: URL(fileURLWithPath: legacyURL.path + "-journal"))
        let legacyCacheContext = TransactionCacheContext(
            environment: .sandbox,
            storagePath: legacyURL.path
        )
        let cachedTransactions = [
            TransactionDTO(id: "tx-old", accountId: "checking", amount: 12, date: "2026-01-01", name: "Coffee")
        ]
        try LocalDataStore.saveTransactions(
            cachedTransactions,
            to: directory,
            context: legacyCacheContext
        )

        let sandboxPath = try ServerConfig.databasePathForStartup(
            in: directory.path,
            environment: .sandbox
        )

        #expect(sandboxPath.hasSuffix("/plaidbar-sandbox.sqlite"))
        #expect(FileManager.default.fileExists(atPath: sandboxPath))
        #expect(try Data(contentsOf: URL(fileURLWithPath: sandboxPath + "-wal")) == Data("wal".utf8))
        #expect(try Data(contentsOf: URL(fileURLWithPath: sandboxPath + "-shm")) == Data("shm".utf8))
        #expect(try Data(contentsOf: URL(fileURLWithPath: sandboxPath + "-journal")) == Data("journal".utf8))
        #expect(!FileManager.default.fileExists(
            atPath: ServerConfig.databasePath(in: directory.path, environment: .production)
        ))
        let migratedCache = try LocalDataStore.loadTransactions(
            from: directory,
            context: TransactionCacheContext(environment: .sandbox, storagePath: sandboxPath)
        )
        #expect(migratedCache.map(\.id) == ["tx-old"])
    }

    @Test func serverDoesNotCopyAmbiguousLegacyDatabase() throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("plaidbar-config-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }

        let legacyURL = directory.appendingPathComponent(ServerConfig.legacyDatabaseFilename)
        try Data("legacy".utf8).write(to: legacyURL)

        let sandboxPath = try ServerConfig.databasePathForStartup(
            in: directory.path,
            environment: .sandbox
        )

        #expect(sandboxPath.hasSuffix("/plaidbar-sandbox.sqlite"))
        #expect(!FileManager.default.fileExists(atPath: sandboxPath))
    }

    @Test func serverCopiesExplicitLegacyDatabaseEnvironment() throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("plaidbar-config-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }

        let legacyURL = directory.appendingPathComponent(ServerConfig.legacyDatabaseFilename)
        try Data("legacy".utf8).write(to: legacyURL)

        let productionPath = try ServerConfig.databasePathForStartup(
            in: directory.path,
            environment: .production,
            legacyMigrationEnvironment: .production
        )

        #expect(productionPath.hasSuffix("/plaidbar-production.sqlite"))
        #expect(try Data(contentsOf: URL(fileURLWithPath: productionPath)) == Data("legacy".utf8))
    }

    @Test func serverBacksUpExistingScopedDatabaseBeforeExplicitLegacyMigration() throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("plaidbar-config-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }

        let legacyURL = directory.appendingPathComponent(ServerConfig.legacyDatabaseFilename)
        try Data("legacy".utf8).write(to: legacyURL)
        let productionPath = ServerConfig.databasePath(in: directory.path, environment: .production)
        try Data("empty-production-db".utf8).write(to: URL(fileURLWithPath: productionPath))
        let legacyCacheContext = TransactionCacheContext(
            environment: .production,
            storagePath: legacyURL.path
        )
        let scopedCacheContext = TransactionCacheContext(
            environment: .production,
            storagePath: productionPath
        )
        try LocalDataStore.saveTransactions(
            [TransactionDTO(id: "tx-legacy", accountId: "checking", amount: 12, date: "2026-01-01", name: "Coffee")],
            to: directory,
            context: legacyCacheContext
        )
        try LocalDataStore.saveTransactions(
            [TransactionDTO(id: "tx-stale", accountId: "checking", amount: 20, date: "2026-01-02", name: "Lunch")],
            to: directory,
            context: scopedCacheContext
        )

        let migratedPath = try ServerConfig.databasePathForStartup(
            in: directory.path,
            environment: .production,
            legacyMigrationEnvironment: .production
        )

        let backupFiles = try FileManager.default.contentsOfDirectory(atPath: directory.path)
            .filter { $0.hasPrefix("plaidbar-production.sqlite.backup-") }

        #expect(migratedPath == productionPath)
        #expect(try Data(contentsOf: URL(fileURLWithPath: productionPath)) == Data("legacy".utf8))
        #expect(backupFiles.count == 1)
        #expect(try Data(contentsOf: directory.appendingPathComponent(backupFiles[0])) == Data("empty-production-db".utf8))
        #expect(try LocalDataStore.loadTransactions(
            from: directory,
            context: scopedCacheContext
        ).map(\.id) == ["tx-legacy"])

        try Data("new-production-db".utf8).write(to: URL(fileURLWithPath: productionPath))
        let restartedPath = try ServerConfig.databasePathForStartup(
            in: directory.path,
            environment: .production,
            legacyMigrationEnvironment: .production
        )

        #expect(restartedPath == productionPath)
        #expect(try Data(contentsOf: URL(fileURLWithPath: productionPath)) == Data("new-production-db".utf8))
    }

    @Test func serverCanCopyLegacyDatabaseAfterWrongEnvironmentCreatedEmptyDatabase() throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("plaidbar-config-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }

        let legacyURL = directory.appendingPathComponent(ServerConfig.legacyDatabaseFilename)
        try Data("legacy".utf8).write(to: legacyURL)
        let sandboxCacheContext = TransactionCacheContext(
            environment: .sandbox,
            storagePath: legacyURL.path
        )
        try LocalDataStore.saveTransactions(
            [TransactionDTO(id: "tx-old", accountId: "checking", amount: 12, date: "2026-01-01", name: "Coffee")],
            to: directory,
            context: sandboxCacheContext
        )
        let productionPath = ServerConfig.databasePath(in: directory.path, environment: .production)
        try Data("empty-production-db".utf8).write(to: URL(fileURLWithPath: productionPath))

        let sandboxPath = try ServerConfig.databasePathForStartup(
            in: directory.path,
            environment: .sandbox
        )

        #expect(sandboxPath.hasSuffix("/plaidbar-sandbox.sqlite"))
        #expect(try Data(contentsOf: URL(fileURLWithPath: sandboxPath)) == Data("legacy".utf8))
    }

    @Test func transactionSyncFailsOnlyWhenEveryAttemptedItemFails() {
        #expect(!TransactionRoutes.shouldFailSync(attemptedItemCount: 0, successfulItemCount: 0))
        #expect(TransactionRoutes.shouldFailSync(attemptedItemCount: 1, successfulItemCount: 0))
        #expect(TransactionRoutes.shouldFailSync(attemptedItemCount: 3, successfulItemCount: 0))
        #expect(!TransactionRoutes.shouldFailSync(attemptedItemCount: 3, successfulItemCount: 1))
        #expect(!TransactionRoutes.shouldFailSync(attemptedItemCount: 3, successfulItemCount: 3))
    }

    @Test func linkResponseCodable() throws {
        let response = LinkResponse(linkToken: "token_123", linkUrl: "https://example.com/link")
        let data = try JSONEncoder().encode(response)
        let decoded = try JSONDecoder().decode(LinkResponse.self, from: data)
        #expect(decoded.linkToken == "token_123")
    }

    @Test func unknownAccountType() {
        let type = AccountType(rawValue: "brokerage") ?? .other
        #expect(type == .other)
    }

    @Test func pendingLinkSessionIsConsumedOnce() async {
        let store = PendingLinkSessionStore()
        let state = await store.issueState()
        await store.save(state: state, linkToken: "link-token")

        let first = await store.consume(state: state)
        let replay = await store.consume(state: state)

        #expect(first?.linkToken == "link-token")
        #expect(replay == nil)
    }

    @Test func pendingLinkSessionExpires() async {
        var currentDate = Date(timeIntervalSince1970: 1_000)
        let store = PendingLinkSessionStore(ttl: 60) { currentDate }
        let state = await store.issueState()
        await store.save(state: state, linkToken: "link-token")

        currentDate = currentDate.addingTimeInterval(61)

        let expired = await store.consume(state: state)
        #expect(expired == nil)
    }

    @Test func linkTokenGetResponseReadsHostedLinkSessionResults() throws {
        let json = """
        {
          "link_token": "link-sandbox-token",
          "link_sessions": [
            {
              "link_session_id": "session-one",
              "results": {
                "item_add_results": [
                  { "public_token": "public-sandbox-one" },
                  { "public_token": "public-sandbox-two" }
                ]
              }
            }
          ]
        }
        """.data(using: .utf8)!
        let decoder = JSONDecoder()
        decoder.keyDecodingStrategy = .convertFromSnakeCase

        let response = try decoder.decode(PlaidLinkTokenGetResponse.self, from: json)

        #expect(response.publicTokens == ["public-sandbox-one", "public-sandbox-two"])
    }

    @Test func linkTokenGetResponseAllowsUpdateModeWithoutPublicToken() throws {
        let json = """
        {
          "link_token": "link-sandbox-token",
          "on_success": {
            "public_token": null,
            "metadata": {}
          }
        }
        """.data(using: .utf8)!
        let decoder = JSONDecoder()
        decoder.keyDecodingStrategy = .convertFromSnakeCase

        let response = try decoder.decode(PlaidLinkTokenGetResponse.self, from: json)

        #expect(response.publicTokens.isEmpty)
    }

    @Test func localDeleteAllowedForNonRetryablePlaidRemoveErrors() {
        let invalidToken = PlaidError.apiError(
            statusCode: 400,
            errorType: "INVALID_INPUT",
            errorCode: "INVALID_ACCESS_TOKEN",
            errorMessage: "invalid access token"
        )
        let transient = PlaidError.apiError(
            statusCode: 500,
            errorType: "API_ERROR",
            errorCode: "INTERNAL_SERVER_ERROR",
            errorMessage: "temporary failure"
        )

        #expect(AccountRoutes.canDeleteLocalItemAfterPlaidRemoveError(invalidToken))
        #expect(!AccountRoutes.canDeleteLocalItemAfterPlaidRemoveError(transient))
    }

    @Test func accountRefreshFailsOnlyWhenEveryLinkedItemFails() {
        #expect(!AccountRoutes.shouldFailRefresh(attemptedItemCount: 0, successfulItemCount: 0))
        #expect(AccountRoutes.shouldFailRefresh(attemptedItemCount: 2, successfulItemCount: 0))
        #expect(!AccountRoutes.shouldFailRefresh(attemptedItemCount: 2, successfulItemCount: 1))
    }
}
