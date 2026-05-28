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

    @Test func serverConfigLoadsExplicitConfigFile() throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("plaidbar-config-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }

        let dataDirectory = directory.appendingPathComponent("data", isDirectory: true)
        let configURL = directory.appendingPathComponent("plaidbar.conf")
        let configContents = [
            "# PlaidBar server config",
            "PLAID_CLIENT_ID=config-client",
            "export PLAID_SECRET=\"config-secret\"",
            "PLAID_ENV=sandbox",
            "PLAIDBAR_SERVER_PORT=9494",
            "PLAIDBAR_DATA_DIR='\(dataDirectory.path)'",
        ].joined(separator: "\r\n") + "\r\n"
        try configContents.write(to: configURL, atomically: true, encoding: .utf8)

        let config = try ServerConfig.load(from: configURL.path)

        #expect(config.plaidClientId == "config-client")
        #expect(config.plaidSecret == "config-secret")
        #expect(config.plaidEnvironment == .sandbox)
        #expect(config.port == 9494)
        #expect(config.databasePath.hasSuffix("/plaidbar-sandbox.sqlite"))
        #expect(config.databasePath.hasPrefix(dataDirectory.path))
        #expect(config.redirectUri == "http://localhost:9494/oauth/callback")
        #expect(FileManager.default.fileExists(
            atPath: dataDirectory.appendingPathComponent(LocalDataStore.authTokenFilename).path
        ))
    }

    @Test func serverConfigCliOverridesConfigFile() throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("plaidbar-config-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }

        let dataDirectory = directory.appendingPathComponent("data", isDirectory: true)
        let configURL = directory.appendingPathComponent("plaidbar.conf")
        try """
        PLAID_CLIENT_ID=config-client
        PLAID_SECRET=config-secret
        PLAID_ENV=production
        PLAIDBAR_SERVER_PORT=9494
        PLAIDBAR_DATA_DIR=\(dataDirectory.path)
        """.write(to: configURL, atomically: true, encoding: .utf8)

        let config = try ServerConfig.load(
            from: configURL.path,
            portOverride: 9595,
            sandboxOverride: true
        )

        #expect(config.plaidEnvironment == .sandbox)
        #expect(config.port == 9595)
        #expect(config.redirectUri == "http://localhost:9595/oauth/callback")
        #expect(config.databasePath.hasSuffix("/plaidbar-sandbox.sqlite"))
    }

    @Test func serverConfigCreatesPrivateAuthTokenFile() throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("plaidbar-config-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }

        let dataDirectory = directory.appendingPathComponent("data", isDirectory: true)
        let configURL = directory.appendingPathComponent("plaidbar.conf")
        try """
        PLAID_CLIENT_ID=config-client
        PLAID_SECRET=config-secret
        PLAID_ENV=sandbox
        PLAIDBAR_DATA_DIR=\(dataDirectory.path)
        """.write(to: configURL, atomically: true, encoding: .utf8)

        let config = try ServerConfig.load(from: configURL.path)
        let authTokenURL = dataDirectory.appendingPathComponent(LocalDataStore.authTokenFilename)

        #expect(try String(contentsOf: authTokenURL, encoding: .utf8) == config.authToken)
        #expect(config.authToken.count >= 43)
        #expect(try posixPermissions(at: authTokenURL) == 0o600)
    }

    @Test func serverConfigPreservesExistingAuthTokenAndTightensPermissions() throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("plaidbar-config-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }

        let dataDirectory = directory.appendingPathComponent("data", isDirectory: true)
        try FileManager.default.createDirectory(at: dataDirectory, withIntermediateDirectories: true)
        let authTokenURL = dataDirectory.appendingPathComponent(LocalDataStore.authTokenFilename)
        try "existing-token\n".write(to: authTokenURL, atomically: true, encoding: .utf8)
        try FileManager.default.setAttributes([.posixPermissions: 0o644], ofItemAtPath: authTokenURL.path)

        let configURL = directory.appendingPathComponent("plaidbar.conf")
        try """
        PLAID_CLIENT_ID=config-client
        PLAID_SECRET=config-secret
        PLAID_ENV=sandbox
        PLAIDBAR_DATA_DIR=\(dataDirectory.path)
        """.write(to: configURL, atomically: true, encoding: .utf8)

        let config = try ServerConfig.load(from: configURL.path)

        #expect(config.authToken == "existing-token")
        #expect(try String(contentsOf: authTokenURL, encoding: .utf8) == "existing-token\n")
        #expect(try posixPermissions(at: authTokenURL) == 0o600)
    }

    @Test func serverAuthTokenUsesURLSafeRandomBytes() {
        let token = ServerConfig.authTokenString(randomBytes: (0..<32).map(UInt8.init))

        #expect(token.count == 43)
        #expect(token.allSatisfy { character in
            character.isLetter || character.isNumber || character == "-" || character == "_"
        })
        #expect(!token.contains("="))
    }

    @Test func oauthCallbackErrorPageEscapesDynamicMessage() {
        let html = OAuthCallbackRoute.errorPage("<script>alert('x')</script> & retry \"soon\"")

        #expect(!html.contains("<script>"))
        #expect(html.contains("&lt;script&gt;alert(&#39;x&#39;)&lt;/script&gt;"))
        #expect(html.contains("&amp; retry &quot;soon&quot;"))
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

    @Test func serverKeepsSQLiteStoreFilesPrivate() throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("plaidbar-config-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }

        let databasePath = ServerConfig.databasePath(in: directory.path, environment: .production)
        let databaseURL = URL(fileURLWithPath: databasePath)
        let walURL = URL(fileURLWithPath: databasePath + "-wal")
        let shmURL = URL(fileURLWithPath: databasePath + "-shm")

        try Data("database".utf8).write(to: databaseURL)
        try Data("wal".utf8).write(to: walURL)
        try Data("shm".utf8).write(to: shmURL)
        try FileManager.default.setAttributes([.posixPermissions: 0o644], ofItemAtPath: databaseURL.path)
        try FileManager.default.setAttributes([.posixPermissions: 0o644], ofItemAtPath: walURL.path)
        try FileManager.default.setAttributes([.posixPermissions: 0o644], ofItemAtPath: shmURL.path)

        try ServerConfig.enforcePrivateSQLiteStorePermissions(at: databasePath)

        #expect(try posixPermissions(at: databaseURL) == 0o600)
        #expect(try posixPermissions(at: walURL) == 0o600)
        #expect(try posixPermissions(at: shmURL) == 0o600)
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

    @Test func pendingLinkSessionSurvivesStoreRecreation() async throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("plaidbar-link-session-\(UUID().uuidString)", isDirectory: true)
        let storageURL = directory.appendingPathComponent("pending-link-sessions.json")
        defer { try? FileManager.default.removeItem(at: directory) }

        let firstStore = PendingLinkSessionStore(storageURL: storageURL)
        let state = await firstStore.issueState()
        await firstStore.save(state: state, linkToken: "link-token", updateItemId: "item-1")

        let restartedStore = PendingLinkSessionStore(storageURL: storageURL)
        let restored = await restartedStore.consume(state: state)
        let replay = await restartedStore.consume(state: state)

        #expect(restored?.linkToken == "link-token")
        #expect(restored?.updateItemId == "item-1")
        #expect(replay == nil)
        #expect(try posixPermissions(at: directory) == 0o700)
        #expect(try posixPermissions(at: storageURL) == 0o600)
    }

    @Test func pendingLinkSessionLoadTightensPersistedFilePermissions() async throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("plaidbar-link-session-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(
            at: directory,
            withIntermediateDirectories: true,
            attributes: [.posixPermissions: 0o777]
        )
        defer { try? FileManager.default.removeItem(at: directory) }

        let storageURL = directory.appendingPathComponent("pending-link-sessions.json")
        let state = "state-\(UUID().uuidString)"
        let sessions = [
            state: PendingLinkSession(
                linkToken: "link-token",
                updateItemId: "item-1",
                createdAt: Date()
            )
        ]
        try JSONEncoder().encode(sessions).write(to: storageURL)
        try FileManager.default.setAttributes([.posixPermissions: 0o644], ofItemAtPath: storageURL.path)

        let restartedStore = PendingLinkSessionStore(storageURL: storageURL)
        #expect(try posixPermissions(at: directory) == 0o700)
        #expect(try posixPermissions(at: storageURL) == 0o600)

        let restored = await restartedStore.consume(state: state)

        #expect(restored?.linkToken == "link-token")
        #expect(restored?.updateItemId == "item-1")
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

    @Test func plaidClientRetriesOnlyTransientFailures() {
        #expect(!PlaidClient.isRetryableHTTPStatus(400))
        #expect(!PlaidClient.isRetryableHTTPStatus(401))
        #expect(PlaidClient.isRetryableHTTPStatus(429))
        #expect(PlaidClient.isRetryableHTTPStatus(500))
        #expect(PlaidClient.isRetryableHTTPStatus(503))

        #expect(PlaidClient.isRetryableTransportError(URLError(.timedOut)))
        #expect(PlaidClient.isRetryableTransportError(URLError(.networkConnectionLost)))
        #expect(!PlaidClient.isRetryableTransportError(URLError(.badURL)))
    }

    @Test func plaidClientRetryDelayBacksOffAndCaps() {
        #expect(PlaidClient.retryDelayNanoseconds(baseDelayNanoseconds: 100, attempt: 1) == 100)
        #expect(PlaidClient.retryDelayNanoseconds(baseDelayNanoseconds: 100, attempt: 2) == 200)
        #expect(PlaidClient.retryDelayNanoseconds(baseDelayNanoseconds: 1_000_000_000, attempt: 10) == 8_000_000_000)
    }

    @Test func plaidTokenVaultReferencesAreDistinctFromLegacyPlaintext() throws {
        let reference = PlaidTokenVault.reference(for: "item_123")

        #expect(reference == "keychain:item_123")
        #expect(PlaidTokenVault.isReference(reference))
        #expect(!PlaidTokenVault.isReference("access-sandbox-token"))
        #expect(try PlaidTokenVault.resolve(storedToken: "access-sandbox-token") == "access-sandbox-token")
    }

    @Test func plaidTokenVaultStoresAndResolvesKeychainTokens() throws {
        let itemId = "test_item_\(UUID().uuidString)"
        let storedToken = try PlaidTokenVault.store(
            accessToken: "access-sandbox-token",
            itemId: itemId
        )
        defer { try? PlaidTokenVault.delete(storedToken: storedToken, fallbackItemId: itemId) }

        #expect(PlaidTokenVault.isReference(storedToken))
        #expect(try PlaidTokenVault.resolve(storedToken: storedToken) == "access-sandbox-token")
    }

    @Test func plaidTokenVaultUpdatesExistingKeychainToken() throws {
        let itemId = "test_item_\(UUID().uuidString)"
        let firstReference = try PlaidTokenVault.store(
            accessToken: "access-sandbox-token-old",
            itemId: itemId
        )
        defer { try? PlaidTokenVault.delete(storedToken: firstReference, fallbackItemId: itemId) }

        let secondReference = try PlaidTokenVault.store(
            accessToken: "access-sandbox-token-new",
            itemId: itemId
        )

        #expect(firstReference == secondReference)
        #expect(try PlaidTokenVault.resolve(storedToken: secondReference) == "access-sandbox-token-new")
    }

    @Test func accountRefreshFailsOnlyWhenEveryLinkedItemFails() {
        #expect(!AccountRoutes.shouldFailRefresh(attemptedItemCount: 0, successfulItemCount: 0))
        #expect(AccountRoutes.shouldFailRefresh(attemptedItemCount: 2, successfulItemCount: 0))
        #expect(!AccountRoutes.shouldFailRefresh(attemptedItemCount: 2, successfulItemCount: 1))
    }

    private func posixPermissions(at url: URL) throws -> Int {
        let attributes = try FileManager.default.attributesOfItem(atPath: url.path)
        return (attributes[.posixPermissions] as? NSNumber)?.intValue ?? -1
    }
}
