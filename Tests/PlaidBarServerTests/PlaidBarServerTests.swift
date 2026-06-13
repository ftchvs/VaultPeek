import Foundation
import FluentKit
import FluentSQLiteDriver
import Hummingbird
import HummingbirdFluent
import HTTPTypes
import Logging
import NIOCore
@testable import PlaidBarCore
@testable import PlaidBarServer
import Testing

private struct TestRequestContextSource: RequestContextSource {
    let logger = Logger(label: "com.ftchvs.plaidbar-server-tests")
}

private struct TestRequestContext: RequestContext {
    typealias Source = TestRequestContextSource

    var coreContext: CoreRequestContextStorage

    init(source: TestRequestContextSource) {
        coreContext = CoreRequestContextStorage(source: source)
    }
}

private final class ManualDateClock: @unchecked Sendable {
    private let lock = NSLock()
    private var value: Date

    init(_ value: Date) {
        self.value = value
    }

    func now() -> Date {
        lock.lock()
        defer { lock.unlock() }
        return value
    }

    func advance(by interval: TimeInterval) {
        lock.lock()
        value = value.addingTimeInterval(interval)
        lock.unlock()
    }
}

private let plaidTokenVaultKeychainAvailable: Bool = {
    let itemId = "test_keychain_probe_\(UUID().uuidString)"
    do {
        let storedToken = try PlaidTokenVault.store(accessToken: "probe-token", itemId: itemId)
        try PlaidTokenVault.delete(storedToken: storedToken, fallbackItemId: itemId)
        return true
    } catch {
        return false
    }
}()

private actor HostedLinkStubPlaidClient: PlaidClientProtocol {
    private let linkTokenGetResponse: PlaidLinkTokenGetResponse
    private let exchangeResponse: PlaidTokenExchangeResponse
    private let accountsResponse: PlaidAccountsResponse
    private var requestedLinkTokens: [String] = []
    private var exchangedPublicTokens: [String] = []
    private var requestedAccountAccessTokens: [String] = []

    init(
        linkTokenGetResponse: PlaidLinkTokenGetResponse,
        exchangeResponse: PlaidTokenExchangeResponse,
        accountsResponse: PlaidAccountsResponse
    ) {
        self.linkTokenGetResponse = linkTokenGetResponse
        self.exchangeResponse = exchangeResponse
        self.accountsResponse = accountsResponse
    }

    func createLinkToken(
        userId _: String,
        completionRedirectUri _: String
    ) async throws -> PlaidLinkTokenResponse {
        throw PlaidError.invalidResponse
    }

    func createUpdateLinkToken(
        userId _: String,
        accessToken _: String,
        completionRedirectUri _: String
    ) async throws -> PlaidLinkTokenResponse {
        throw PlaidError.invalidResponse
    }

    func getLinkToken(_ linkToken: String) async throws -> PlaidLinkTokenGetResponse {
        requestedLinkTokens.append(linkToken)
        return linkTokenGetResponse
    }

    func exchangePublicToken(_ publicToken: String) async throws -> PlaidTokenExchangeResponse {
        exchangedPublicTokens.append(publicToken)
        return exchangeResponse
    }

    func getAccounts(accessToken: String) async throws -> PlaidAccountsResponse {
        requestedAccountAccessTokens.append(accessToken)
        return accountsResponse
    }

    func recordedCalls() -> (
        linkTokens: [String],
        publicTokens: [String],
        accountAccessTokens: [String]
    ) {
        (
            requestedLinkTokens,
            exchangedPublicTokens,
            requestedAccountAccessTokens
        )
    }
}

@Suite("PlaidBarServer")
struct PlaidBarServerTests {
    @Test func accountTypes() {
        let checking = AccountDTO(
            id: "1",
            itemId: "i",
            name: "Checking",
            type: .depository,
            balances: BalanceDTO(current: 5000)
        )
        let credit = AccountDTO(
            id: "2",
            itemId: "i",
            name: "Amex",
            type: .credit,
            balances: BalanceDTO(current: -850, limit: 10000)
        )
        #expect(checking.type == .depository)
        #expect(credit.type == .credit)
        #expect(credit.balances.utilizationPercent == 8.5)
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

    @Test func serverStatusPayloadIsLimitedToReadinessMetadata() throws {
        let status = ServerStatus(
            version: "0.8.0",
            environment: .production,
            itemCount: 2,
            lastSync: Date(timeIntervalSince1970: 1_800_000_000),
            credentialsConfigured: true,
            storagePath: "/Users/example/.plaidbar",
            syncReady: true,
            syncedItemCount: 2
        )
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601

        let data = try encoder.encode(status)
        let object = try #require(JSONSerialization.jsonObject(with: data) as? [String: Any])
        let keys = Set(object.keys)
        let payload = try #require(String(data: data, encoding: .utf8))
        let allowedReadinessKeys: Set<String> = [
            "version",
            "environment",
            "itemCount",
            "lastSync",
            "credentialsConfigured",
            "storagePath",
            "syncReady",
            "syncedItemCount",
        ]
        let forbiddenFragments = [
            "account",
            "access",
            "balance",
            "client",
            "institution",
            "item_id",
            "itemId",
            "payload",
            "plaid",
            "public",
            "raw",
            "secret",
            "token",
            "transaction",
        ]

        #expect(keys == allowedReadinessKeys)
        #expect(keys.allSatisfy { key in
            forbiddenFragments.allSatisfy { !key.localizedCaseInsensitiveContains($0) }
        })
        #expect(!payload.contains("\"accountId\""))
        #expect(!payload.contains("\"account_id\""))
        #expect(!payload.contains("\"access_token\""))
        #expect(!payload.contains("\"balance\""))
        #expect(!payload.contains("\"balances\""))
        #expect(!payload.contains("\"clientSecret\""))
        #expect(!payload.contains("\"client_secret\""))
        #expect(!payload.contains("\"plaidToken\""))
        #expect(!payload.contains("\"publicToken\""))
        #expect(!payload.contains("\"rawPayload\""))
        #expect(!payload.contains("\"transactions\""))
    }

    @Test func serverStatusPayloadDoesNotExposeSecretBearingFieldNames() throws {
        let status = ServerStatus(
            version: "0.8.0",
            environment: .sandbox,
            itemCount: 1,
            lastSync: Date(timeIntervalSince1970: 1_800_000_001),
            credentialsConfigured: true,
            storagePath: "/Users/example/.plaidbar",
            syncReady: true,
            syncedItemCount: 1
        )
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601

        let data = try encoder.encode(status)
        let payload = try #require(String(data: data, encoding: .utf8))
        let forbiddenFieldNames = [
            "accessToken",
            "access_token",
            "accountId",
            "account_id",
            "balance",
            "balances",
            "clientId",
            "client_id",
            "clientSecret",
            "client_secret",
            "institutionId",
            "institution_id",
            "itemId",
            "item_id",
            "linkToken",
            "link_token",
            "plaidPayload",
            "publicToken",
            "public_token",
            "rawPayload",
            "secret",
            "token",
            "transactionId",
            "transaction_id",
            "transactions",
        ]

        for fieldName in forbiddenFieldNames {
            #expect(!payload.contains("\"\(fieldName)\""))
        }
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
        #expect(config.dataDirectoryPath == dataDirectory.path)
        #expect(config.port == 9494)
        #expect(config.databasePath.hasSuffix("/plaidbar-sandbox.sqlite"))
        #expect(config.databasePath.hasPrefix(dataDirectory.path))
        #expect(config.redirectUri == "http://localhost:9494/oauth/callback")
        #expect(FileManager.default.fileExists(
            atPath: dataDirectory.appendingPathComponent(LocalDataStore.authTokenFilename).path
        ))
    }

    @Test func serverConfigLoadsCredentialLessIntoSetupState() throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("plaidbar-config-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }

        let dataDirectory = directory.appendingPathComponent("data", isDirectory: true)
        let configURL = directory.appendingPathComponent("plaidbar.conf")
        // Blank values override any PLAID_* variables exported in the test
        // host's environment, making this deterministic everywhere.
        try """
        PLAID_CLIENT_ID=
        PLAID_SECRET=
        PLAID_ENV=sandbox
        PLAIDBAR_DATA_DIR=\(dataDirectory.path)
        """.write(to: configURL, atomically: true, encoding: .utf8)

        let config = try ServerConfig.load(from: configURL.path)

        #expect(!config.credentialsConfigured)
        #expect(config.plaidClientId.isEmpty)
        #expect(config.plaidSecret.isEmpty)
        #expect(config.plaidEnvironment == .sandbox)
        // Setup state still provisions everything the degraded server needs:
        // data directory, database path, and the local API auth token.
        #expect(config.databasePath.hasPrefix(dataDirectory.path))
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

    @Test func serverConfigTightensLooseConfigFilePermissions() throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("plaidbar-config-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }

        let dataDirectory = directory.appendingPathComponent("data", isDirectory: true)
        let configURL = directory.appendingPathComponent("server.conf")
        try """
        PLAID_CLIENT_ID=config-client
        PLAID_SECRET=config-secret
        PLAID_ENV=sandbox
        PLAIDBAR_DATA_DIR=\(dataDirectory.path)
        """.write(to: configURL, atomically: true, encoding: .utf8)
        try FileManager.default.setAttributes([.posixPermissions: 0o644], ofItemAtPath: configURL.path)

        _ = try ServerConfig.load(from: configURL.path)

        #expect(try posixPermissions(at: configURL) == 0o600)
    }

    @Test func serverConfigRejectsOutOfRangePortOverride() throws {
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

        for badPort in [0, 70_000, -1] {
            #expect(throws: ServerConfigError.self) {
                _ = try ServerConfig.load(from: configURL.path, portOverride: badPort)
            }
        }

        // Validation runs before any side effects, so a bad port never creates the data dir.
        #expect(!FileManager.default.fileExists(atPath: dataDirectory.path))
    }

    @Test func serverAuthTokenUsesURLSafeRandomBytes() {
        let token = ServerConfig.authTokenString(randomBytes: (0 ..< 32).map(UInt8.init))

        #expect(token.count == 43)
        #expect(token.allSatisfy { character in
            character.isLetter || character.isNumber || character == "-" || character == "_"
        })
        #expect(!token.contains("="))
    }

    @Test func plaidClientRefusesRequestsInSetupState() async throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("plaidbar-config-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }

        let configURL = directory.appendingPathComponent("plaidbar.conf")
        try """
        PLAID_CLIENT_ID=
        PLAID_SECRET=
        PLAID_ENV=sandbox
        PLAIDBAR_DATA_DIR=\(directory.appendingPathComponent("data").path)
        """.write(to: configURL, atomically: true, encoding: .utf8)

        let config = try ServerConfig.load(from: configURL.path)
        let client = PlaidClient(config: config)

        // The guard fires before any network request, so this fails fast and
        // deterministically with the setup-state error.
        await #expect(throws: PlaidError.credentialsNotConfigured) {
            _ = try await client.createLinkToken(
                userId: "test-user",
                completionRedirectUri: "http://localhost:8484/oauth/callback"
            )
        }
    }

    @Test func setupStateMiddlewareClassifiesPlaidBackedPaths() {
        typealias Middleware = SetupStateMiddleware<BasicRequestContext>

        // Blocked in setup state: nothing on these routes works without
        // Plaid credentials, even when no items are linked.
        #expect(Middleware.isPlaidBackedPath("/api/link/create"))
        #expect(Middleware.isPlaidBackedPath("/api/link/update/item-1"))
        #expect(Middleware.isPlaidBackedPath("/api/accounts"))
        #expect(Middleware.isPlaidBackedPath("/api/accounts/balances"))
        #expect(Middleware.isPlaidBackedPath("/api/accounts/item-1"))
        #expect(Middleware.isPlaidBackedPath("/api/transactions/sync"))
        #expect(Middleware.isPlaidBackedPath("/api/transactions/sync/cursors"))

        // Readiness metadata stays available so setup guidance can render.
        #expect(!Middleware.isPlaidBackedPath("/api/status"))
        #expect(!Middleware.isPlaidBackedPath("/api/items"))
        #expect(!Middleware.isPlaidBackedPath("/health"))
        #expect(!Middleware.isPlaidBackedPath("/oauth/callback"))

        // Prefix matching respects path-segment boundaries.
        #expect(!Middleware.isPlaidBackedPath("/api/accountsmetadata"))
    }

    @Test func apiTokenComparisonAcceptsOnlyExactBearerToken() {
        #expect(APITokenAuthorization.constantTimeEquals("Bearer token-123", "Bearer token-123"))
        #expect(!APITokenAuthorization.constantTimeEquals("Bearer token-123", "Bearer token-124"))
        #expect(!APITokenAuthorization.constantTimeEquals("Bearer token-123", "token-123"))
        #expect(!APITokenAuthorization.constantTimeEquals("Bearer token-123", "Bearer token-123-extra"))
    }

    @Test func apiMiddlewareRejectsMissingAndInvalidBearerTokens() async throws {
        let middleware = APITokenMiddleware<TestRequestContext>(authToken: "local-token")
        let context = TestRequestContext(source: TestRequestContextSource())

        for request in [
            Self.makeRequest(path: "/api/status"),
            Self.makeRequest(path: "/api/status", authorization: "local-token"),
            Self.makeRequest(path: "/api/status", authorization: "Bearer wrong-token"),
            Self.makeRequest(path: "/api/accounts", authorization: "Bearer local-token-extra"),
        ] {
            do {
                _ = try await middleware.handle(request, context: context) { _, _ in
                    Response(status: .ok)
                }
                #expect(Bool(false), "Expected unauthorized API request to throw")
            } catch let error as HTTPError {
                #expect(error.status == .unauthorized)
                #expect(error.body == "Missing or invalid authorization token")
            } catch {
                #expect(Bool(false), "Expected HTTPError, got \(error)")
            }
        }
    }

    @Test func apiMiddlewareAcceptsExactBearerTokenOnly() async throws {
        let middleware = APITokenMiddleware<TestRequestContext>(authToken: "local-token")
        let context = TestRequestContext(source: TestRequestContextSource())

        let response = try await middleware.handle(
            Self.makeRequest(path: "/api/status", authorization: "Bearer local-token"),
            context: context
        ) { _, _ in
            Response(status: .ok)
        }

        #expect(response.status == .ok)
    }

    @Test func oauthCallbackErrorPageEscapesDynamicMessage() {
        let html = OAuthCallbackRoute.errorPage("<script>alert('x')</script> & retry \"soon\"")

        #expect(!html.contains("<script>"))
        #expect(html.contains("&lt;script&gt;alert(&#39;x&#39;)&lt;/script&gt;"))
        #expect(html.contains("&amp; retry &quot;soon&quot;"))
    }

    private static func makeRequest(path: String, authorization: String? = nil) -> Request {
        var headers = HTTPFields()
        if let authorization {
            headers[.authorization] = authorization
        }
        return Request(
            head: HTTPRequest(method: .get, scheme: nil, authority: nil, path: path, headerFields: headers),
            body: RequestBody(buffer: ByteBuffer())
        )
    }

    /// Runs `body` against a TokenStore backed by a temporary SQLite file,
    /// and always shuts Fluent down so the test does not hold database files.
    private func withTokenStore(
        databasePath: String,
        logger: Logger,
        _ body: (TokenStore) async throws -> Void
    ) async throws {
        let fluent = Fluent(logger: logger)
        fluent.databases.use(.sqlite(.file(databasePath)), as: .sqlite)
        await fluent.migrations.add(CreateItems())
        await fluent.migrations.add(AddProviderToItems())
        await fluent.migrations.add(CreateSyncCursors())

        var bodyError: Error?
        do {
            try await fluent.migrate()
            try await body(TokenStore(fluent: fluent, logger: logger))
        } catch {
            bodyError = error
        }
        try await fluent.shutdown()
        if let bodyError {
            throw bodyError
        }
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
            TransactionDTO(id: "tx-old", accountId: "checking", amount: 12, date: "2026-01-01", name: "Coffee"),
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
        #expect(try Data(contentsOf: directory.appendingPathComponent(backupFiles[0])) ==
            Data("empty-production-db".utf8))
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

    @Test func accountCacheIsScopedByEnvironmentAndStoragePath() throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("plaidbar-account-cache-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }

        let productionContext = TransactionCacheContext(
            environment: .production,
            storagePath: directory.appendingPathComponent("plaidbar-production.sqlite").path
        )
        let sandboxContext = TransactionCacheContext(
            environment: .sandbox,
            storagePath: directory.appendingPathComponent("plaidbar-sandbox.sqlite").path
        )
        let account = AccountDTO(
            id: "checking",
            itemId: "item-production",
            name: "Everyday Checking",
            type: .depository,
            balances: BalanceDTO(current: 1_250)
        )

        try LocalDataStore.saveAccounts([account], to: directory, context: productionContext)

        #expect(try LocalDataStore.loadAccounts(from: directory, context: productionContext).map(\.id) == ["checking"])
        #expect(try LocalDataStore.loadAccounts(from: directory, context: sandboxContext).isEmpty)
    }

    @Test func accountCacheIsRemovedDuringLocalDataReset() throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("plaidbar-account-cache-reset-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }

        let account = AccountDTO(
            id: "checking",
            itemId: "item-production",
            name: "Everyday Checking",
            type: .depository,
            balances: BalanceDTO(current: 1_250)
        )
        let context = TransactionCacheContext(
            environment: .sandbox,
            storagePath: directory.appendingPathComponent("plaidbar-sandbox.sqlite").path
        )
        let unrelatedExport = directory.appendingPathComponent("accounts-2026.json")
        try Data("user export".utf8).write(to: unrelatedExport)
        try LocalDataStore.saveAccounts([account], to: directory, context: nil)
        try LocalDataStore.saveAccounts([account], to: directory, context: context)

        let result = try LocalDataStore.resetLocalData(
            at: directory,
            resetKeychainTokens: false
        )

        #expect(try LocalDataStore.loadAccounts(from: directory).isEmpty)
        #expect(try LocalDataStore.loadAccounts(from: directory, context: context).isEmpty)
        #expect(FileManager.default.fileExists(atPath: unrelatedExport.path))
        #expect(result.preservedEntries.contains("accounts-2026.json"))
    }

    @Test func transactionCacheIsRemovedButUnrelatedExportPreservedDuringLocalDataReset() throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("plaidbar-transaction-cache-reset-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }

        let context = TransactionCacheContext(
            environment: .sandbox,
            storagePath: directory.appendingPathComponent("plaidbar-sandbox.sqlite").path
        )
        // A user/export file that merely looks transaction-shaped must survive
        // reset, just like the unrelated accounts-2026.json export above.
        let unrelatedExport = directory.appendingPathComponent("transactions-2026.json")
        try Data("user export".utf8).write(to: unrelatedExport)
        try LocalDataStore.saveTransactions(
            [TransactionDTO(id: "tx-old", accountId: "checking", amount: 12, date: "2026-01-01", name: "Coffee")],
            to: directory,
            context: context
        )

        let result = try LocalDataStore.resetLocalData(
            at: directory,
            resetKeychainTokens: false
        )

        #expect(try LocalDataStore.loadTransactions(from: directory, context: context).isEmpty)
        #expect(FileManager.default.fileExists(atPath: unrelatedExport.path))
        #expect(result.preservedEntries.contains("transactions-2026.json"))
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

    @Test func serverPreparesPrivateSQLiteStoreBeforeOpen() throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("plaidbar-config-\(UUID().uuidString)", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: directory) }

        let databasePath = ServerConfig.databasePath(in: directory.path, environment: .production)
        let databaseURL = URL(fileURLWithPath: databasePath)

        try ServerConfig.preparePrivateSQLiteStoreForOpen(at: databasePath)

        #expect(FileManager.default.fileExists(atPath: databasePath))
        #expect(try posixPermissions(at: directory) == 0o700)
        #expect(try posixPermissions(at: databaseURL) == 0o600)
    }

    @Test func serverTightensSQLiteStorePermissionsBeforeOpen() throws {
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
        try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: directory.path)
        try FileManager.default.setAttributes([.posixPermissions: 0o644], ofItemAtPath: databaseURL.path)
        try FileManager.default.setAttributes([.posixPermissions: 0o644], ofItemAtPath: walURL.path)
        try FileManager.default.setAttributes([.posixPermissions: 0o644], ofItemAtPath: shmURL.path)

        try ServerConfig.preparePrivateSQLiteStoreForOpen(at: databasePath)

        #expect(try posixPermissions(at: directory) == 0o700)
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
        let clock = ManualDateClock(Date(timeIntervalSince1970: 1000))
        let store = PendingLinkSessionStore(ttl: 60, now: { @Sendable in clock.now() })
        let state = await store.issueState()
        await store.save(state: state, linkToken: "link-token")

        clock.advance(by: 61)

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
            ),
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
                  {
                    "public_token": "public-sandbox-one",
                    "institution": {
                      "name": "Example Credit Union",
                      "institution_id": "ins_example_credit_union"
                    }
                  },
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
        #expect(response.publicTokenResults.first?.institution?.name == "Example Credit Union")
        #expect(response.publicTokenResults.first?.institution?.institutionId == "ins_example_credit_union")
    }

    @Test(
        "OAuth callback stores Hosted Link institution names",
        .enabled(if: plaidTokenVaultKeychainAvailable, "macOS Keychain accepts test writes")
    )
    func oauthCallbackStoresHostedLinkInstitutionName() async throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("plaidbar-oauth-callback-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }

        let itemId = "test_item_\(UUID().uuidString)"
        defer {
            try? PlaidTokenVault.delete(
                storedToken: PlaidTokenVault.reference(for: itemId),
                fallbackItemId: itemId
            )
        }

        let linkTokenJSON = """
        {
          "link_token": "test-link-token",
          "link_sessions": [
            {
              "link_session_id": "test-link-session",
              "results": {
                "item_add_results": [
                  {
                    "public_token": "test-public-token",
                    "institution": {
                      "name": "Example Credit Union",
                      "institution_id": "ins_example_credit_union"
                    }
                  }
                ]
              }
            }
          ]
        }
        """.data(using: .utf8)!
        let decoder = JSONDecoder()
        decoder.keyDecodingStrategy = .convertFromSnakeCase
        let linkTokenGetResponse = try decoder.decode(PlaidLinkTokenGetResponse.self, from: linkTokenJSON)
        let accessToken = "test-access-token-\(UUID().uuidString)"
        let plaidClient = HostedLinkStubPlaidClient(
            linkTokenGetResponse: linkTokenGetResponse,
            exchangeResponse: PlaidTokenExchangeResponse(
                accessToken: accessToken,
                itemId: itemId,
                requestId: nil
            ),
            accountsResponse: PlaidAccountsResponse(
                accounts: [],
                item: PlaidItem(
                    itemId: itemId,
                    institutionId: "ins_accounts_fallback",
                    availableProducts: nil,
                    billedProducts: nil
                ),
                requestId: nil
            )
        )
        let pendingLinkSessions = PendingLinkSessionStore(
            storageURL: directory.appendingPathComponent("pending-link-sessions.json")
        )
        let state = await pendingLinkSessions.issueState()
        await pendingLinkSessions.save(state: state, linkToken: "test-link-token")
        let databasePath = directory.appendingPathComponent("plaidbar-test.sqlite").path
        let logger = Logger(label: "com.ftchvs.plaidbar-server-tests.oauth-callback")

        try await withTokenStore(databasePath: databasePath, logger: logger) { store in
            let route = OAuthCallbackRoute(
                plaidClient: plaidClient,
                tokenStore: store,
                pendingLinkSessions: pendingLinkSessions
            )
            let response = try await route.handleCallback(
                request: Self.makeRequest(path: "/oauth/callback?state=\(state)"),
                context: TestRequestContext(source: TestRequestContextSource())
            )
            let savedItem = try #require(try await store.getItem(id: itemId))
            let calls = await plaidClient.recordedCalls()

            #expect(response.status == .ok)
            #expect(savedItem.institutionName == "Example Credit Union")
            #expect(savedItem.institutionId == "ins_example_credit_union")
            #expect(calls.linkTokens == ["test-link-token"])
            #expect(calls.publicTokens == ["test-public-token"])
            #expect(calls.accountAccessTokens == [accessToken])
        }
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

    @Test func plaidClientUsesSingleAttemptForNonIdempotentOperations() {
        #expect(PlaidClient.allowedAttempts(maxAttempts: 3, retryPolicy: .singleAttempt) == 1)
        #expect(PlaidClient.allowedAttempts(maxAttempts: 0, retryPolicy: .singleAttempt) == 1)
        #expect(PlaidClient.allowedAttempts(maxAttempts: 3, retryPolicy: .transient) == 3)
        #expect(PlaidClient.allowedAttempts(maxAttempts: 0, retryPolicy: .transient) == 1)
    }

    @Test func plaidTokenVaultReferencesAreDistinctFromLegacyPlaintext() throws {
        let reference = PlaidTokenVault.reference(for: "item_123")

        #expect(reference == "keychain:item_123")
        #expect(PlaidTokenVault.isReference(reference))
        #expect(!PlaidTokenVault.isReference("access-sandbox-token"))
        #expect(try PlaidTokenVault.resolve(storedToken: "access-sandbox-token") == "access-sandbox-token")
    }

    @Test(.enabled(if: plaidTokenVaultKeychainAvailable, "macOS Keychain accepts test writes"))
    func plaidTokenVaultStoresAndResolvesKeychainTokens() throws {
        let itemId = "test_item_\(UUID().uuidString)"
        let storedToken = try PlaidTokenVault.store(
            accessToken: "access-sandbox-token",
            itemId: itemId
        )
        defer { try? PlaidTokenVault.delete(storedToken: storedToken, fallbackItemId: itemId) }

        #expect(PlaidTokenVault.isReference(storedToken))
        #expect(try PlaidTokenVault.resolve(storedToken: storedToken) == "access-sandbox-token")
    }

    @Test(.enabled(if: plaidTokenVaultKeychainAvailable, "macOS Keychain accepts test writes"))
    func plaidTokenVaultUpdatesExistingKeychainToken() throws {
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
