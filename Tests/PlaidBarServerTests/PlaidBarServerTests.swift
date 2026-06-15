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

private enum HostedLinkStubError: Error {
    case transientExchangeFailure
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
    private let exchangeResponsesByPublicToken: [String: PlaidTokenExchangeResponse]
    private let accountsResponse: PlaidAccountsResponse
    private var exchangeFailuresRemaining: Int
    private var exchangeFailuresByPublicToken: [String: Int]
    private var accountsFailuresRemaining: Int
    private var requestedLinkTokens: [String] = []
    private var exchangedPublicTokens: [String] = []
    private var requestedAccountAccessTokens: [String] = []

    init(
        linkTokenGetResponse: PlaidLinkTokenGetResponse,
        exchangeResponse: PlaidTokenExchangeResponse,
        accountsResponse: PlaidAccountsResponse,
        exchangeFailuresBeforeSuccess: Int = 0,
        exchangeFailuresByPublicToken: [String: Int] = [:],
        exchangeResponsesByPublicToken: [String: PlaidTokenExchangeResponse] = [:],
        accountsFailuresBeforeSuccess: Int = 0
    ) {
        self.linkTokenGetResponse = linkTokenGetResponse
        self.exchangeResponse = exchangeResponse
        self.exchangeResponsesByPublicToken = exchangeResponsesByPublicToken
        self.accountsResponse = accountsResponse
        self.exchangeFailuresRemaining = exchangeFailuresBeforeSuccess
        self.exchangeFailuresByPublicToken = exchangeFailuresByPublicToken
        self.accountsFailuresRemaining = accountsFailuresBeforeSuccess
    }

    func createLinkToken(
        clientUserId _: String,
        completionRedirectUri _: String
    ) async throws -> PlaidLinkTokenResponse {
        throw PlaidError.invalidResponse
    }

    func createUpdateLinkToken(
        clientUserId _: String,
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
        if let failuresRemaining = exchangeFailuresByPublicToken[publicToken],
           failuresRemaining > 0 {
            exchangeFailuresByPublicToken[publicToken] = failuresRemaining - 1
            throw HostedLinkStubError.transientExchangeFailure
        }
        if exchangeFailuresRemaining > 0 {
            exchangeFailuresRemaining -= 1
            throw HostedLinkStubError.transientExchangeFailure
        }
        return exchangeResponsesByPublicToken[publicToken] ?? exchangeResponse
    }

    func getAccounts(accessToken: String) async throws -> PlaidAccountsResponse {
        requestedAccountAccessTokens.append(accessToken)
        // Simulates a failure AFTER the public token was already exchanged, to
        // exercise the post-exchange handoff barrier: the spent token must not
        // be replayed on retry.
        if accountsFailuresRemaining > 0 {
            accountsFailuresRemaining -= 1
            throw HostedLinkStubError.transientExchangeFailure
        }
        return accountsResponse
    }

    func getBalances(accessToken _: String) async throws -> PlaidAccountsResponse {
        throw PlaidError.invalidResponse
    }

    func syncTransactions(
        accessToken _: String,
        cursor _: String?
    ) async throws -> PlaidTransactionsSyncResponse {
        throw PlaidError.invalidResponse
    }

    func removeItem(accessToken _: String) async throws {
        throw PlaidError.invalidResponse
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

private enum RefreshStubError: Error {
    case failed
}

private actor DelayedRefreshPlaidClient: PlaidClientProtocol {
    struct AccountOutcome: Sendable {
        var response: PlaidAccountsResponse?
        var error: (any Error & Sendable)?
        var delayNanoseconds: UInt64

        static func success(
            _ response: PlaidAccountsResponse,
            delayNanoseconds: UInt64 = 0
        ) -> AccountOutcome {
            AccountOutcome(response: response, error: nil, delayNanoseconds: delayNanoseconds)
        }

        static func failure(
            _ error: any Error & Sendable = RefreshStubError.failed,
            delayNanoseconds: UInt64 = 0
        ) -> AccountOutcome {
            AccountOutcome(response: nil, error: error, delayNanoseconds: delayNanoseconds)
        }
    }

    struct SyncOutcome: Sendable {
        var response: PlaidTransactionsSyncResponse?
        var error: (any Error & Sendable)?
        var delayNanoseconds: UInt64

        static func success(
            _ response: PlaidTransactionsSyncResponse,
            delayNanoseconds: UInt64 = 0
        ) -> SyncOutcome {
            SyncOutcome(response: response, error: nil, delayNanoseconds: delayNanoseconds)
        }

        static func failure(
            _ error: any Error & Sendable = RefreshStubError.failed,
            delayNanoseconds: UInt64 = 0
        ) -> SyncOutcome {
            SyncOutcome(response: nil, error: error, delayNanoseconds: delayNanoseconds)
        }
    }

    private let accountOutcomes: [String: AccountOutcome]
    private let balanceOutcomes: [String: AccountOutcome]
    private let syncOutcomes: [String: SyncOutcome]
    private var activeCalls = 0
    private var maxActiveCalls = 0
    private var accountAccessTokens: [String] = []
    private var balanceAccessTokens: [String] = []
    private var syncAccessTokens: [String] = []

    init(
        accountOutcomes: [String: AccountOutcome] = [:],
        balanceOutcomes: [String: AccountOutcome] = [:],
        syncOutcomes: [String: SyncOutcome] = [:]
    ) {
        self.accountOutcomes = accountOutcomes
        self.balanceOutcomes = balanceOutcomes
        self.syncOutcomes = syncOutcomes
    }

    func createLinkToken(
        clientUserId _: String,
        completionRedirectUri _: String
    ) async throws -> PlaidLinkTokenResponse {
        throw PlaidError.invalidResponse
    }

    func createUpdateLinkToken(
        clientUserId _: String,
        accessToken _: String,
        completionRedirectUri _: String
    ) async throws -> PlaidLinkTokenResponse {
        throw PlaidError.invalidResponse
    }

    func getLinkToken(_: String) async throws -> PlaidLinkTokenGetResponse {
        throw PlaidError.invalidResponse
    }

    func exchangePublicToken(_: String) async throws -> PlaidTokenExchangeResponse {
        throw PlaidError.invalidResponse
    }

    func getAccounts(accessToken: String) async throws -> PlaidAccountsResponse {
        accountAccessTokens.append(accessToken)
        return try await resolve(accountOutcomes[accessToken] ?? .failure())
    }

    func getBalances(accessToken: String) async throws -> PlaidAccountsResponse {
        balanceAccessTokens.append(accessToken)
        return try await resolve(balanceOutcomes[accessToken] ?? .failure())
    }

    func syncTransactions(
        accessToken: String,
        cursor _: String?
    ) async throws -> PlaidTransactionsSyncResponse {
        syncAccessTokens.append(accessToken)
        let outcome = syncOutcomes[accessToken] ?? .failure()
        activeCalls += 1
        maxActiveCalls = max(maxActiveCalls, activeCalls)
        let delay = outcome.delayNanoseconds
        if delay > 0 {
            try await Task.sleep(nanoseconds: delay)
        }
        activeCalls -= 1
        if let error = outcome.error {
            throw error
        }
        return outcome.response!
    }

    func removeItem(accessToken _: String) async throws {
        throw PlaidError.invalidResponse
    }

    func recordedCalls() -> (
        accounts: [String],
        balances: [String],
        syncs: [String],
        maxActive: Int
    ) {
        (accountAccessTokens, balanceAccessTokens, syncAccessTokens, maxActiveCalls)
    }

    private func resolve(_ outcome: AccountOutcome) async throws -> PlaidAccountsResponse {
        activeCalls += 1
        maxActiveCalls = max(maxActiveCalls, activeCalls)
        let delay = outcome.delayNanoseconds
        if delay > 0 {
            try await Task.sleep(nanoseconds: delay)
        }
        activeCalls -= 1
        if let error = outcome.error {
            throw error
        }
        return outcome.response!
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
            syncedItemCount: 2,
            billingSubscription: BillingSubscription(
                status: .active,
                plan: .free,
                updatedAt: Date(timeIntervalSince1970: 1_800_000_002)
            )
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
            "billingSubscription",
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
            syncedItemCount: 1,
            billingSubscription: BillingSubscription(
                status: .trialing,
                plan: .free,
                updatedAt: Date(timeIntervalSince1970: 1_800_000_002)
            )
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

    @Test(
        "Status include items returns safe item readiness snapshot",
        .enabled(if: plaidTokenVaultKeychainAvailable, "macOS Keychain accepts test writes")
    )
    func statusIncludeItemsReturnsSafeItemReadinessSnapshot() async throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("plaidbar-status-items-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }

        let loginItemId = "test_item_login_\(UUID().uuidString)"
        let errorItemId = "test_item_error_\(UUID().uuidString)"
        defer {
            for itemId in [loginItemId, errorItemId] {
                try? PlaidTokenVault.delete(
                    storedToken: PlaidTokenVault.reference(for: itemId),
                    fallbackItemId: itemId
                )
            }
        }

        let databasePath = directory.appendingPathComponent("plaidbar-status-items.sqlite").path
        let logger = Logger(label: "com.ftchvs.plaidbar-server-tests.status-items")
        let config = try setupStateConfig(in: directory)
        try await withStatusStores(databasePath: databasePath, logger: logger) { store, billingStore in
            try await store.saveItem(
                id: loginItemId,
                accessToken: "access-sandbox-\(UUID().uuidString)",
                institutionId: "ins_login",
                institutionName: "Example Bank"
            )
            try await store.saveItem(
                id: errorItemId,
                accessToken: "access-sandbox-\(UUID().uuidString)",
                institutionId: "ins_error",
                institutionName: "Credit Union"
            )
            try await store.updateItemStatus(id: loginItemId, status: ItemConnectionStatus.loginRequired.rawValue)
            try await store.updateItemStatus(id: errorItemId, status: ItemConnectionStatus.error.rawValue)

            let routes = StatusRoutes(
                tokenStore: store,
                billingStore: billingStore,
                config: config
            )
            let includeItemsRequest = Self.makeRequest(path: "/api/status?include=items")
            let status = try await routes.statusSnapshot(
                includeItems: StatusRoutes.includesItems(includeItemsRequest)
            )
            let encoder = JSONEncoder()
            encoder.dateEncodingStrategy = .iso8601
            let payload = try #require(String(data: encoder.encode(status), encoding: .utf8))

            #expect(StatusRoutes.includesItems(includeItemsRequest))
            #expect(status.credentialsConfigured == false)
            #expect(status.itemCount == 2)
            #expect(status.syncReady)
            #expect(status.itemStatuses?.count == 2)
            #expect(
                (status.itemStatuses?.map(\.status.rawValue).sorted() ?? []) ==
                    [
                        ItemConnectionStatus.error.rawValue,
                        ItemConnectionStatus.loginRequired.rawValue,
                    ]
            )
            #expect(Set(status.itemStatuses?.compactMap(\.institutionName) ?? []) == ["Example Bank", "Credit Union"])
            #expect(!payload.contains("access-sandbox-"))
            #expect(!payload.contains("access_token"))
            #expect(!payload.contains("institutionId"))
            #expect(!payload.contains("institution_id"))
            #expect(!payload.contains("transaction"))
            #expect(!payload.contains("balance"))
        }
    }

    @Test("Status omits item readiness snapshot by default")
    func statusOmitsItemReadinessSnapshotByDefault() async throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("plaidbar-status-default-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }

        let databasePath = directory.appendingPathComponent("plaidbar-status-default.sqlite").path
        let logger = Logger(label: "com.ftchvs.plaidbar-server-tests.status-default")
        let config = try setupStateConfig(in: directory)
        try await withStatusStores(databasePath: databasePath, logger: logger) { store, billingStore in
            let routes = StatusRoutes(
                tokenStore: store,
                billingStore: billingStore,
                config: config
            )
            let defaultStatusRequest = Self.makeRequest(path: "/api/status")
            let status = try await routes.statusSnapshot(
                includeItems: StatusRoutes.includesItems(defaultStatusRequest)
            )
            let object = try #require(
                JSONSerialization.jsonObject(with: JSONEncoder().encode(status)) as? [String: Any]
            )

            #expect(!StatusRoutes.includesItems(defaultStatusRequest))
            #expect(status.itemCount == 0)
            #expect(status.itemStatuses == nil)
            #expect(object["itemStatuses"] == nil)
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
                clientUserId: "test-user",
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

    private func setupStateConfig(in directory: URL) throws -> ServerConfig {
        let dataDirectory = directory.appendingPathComponent("data", isDirectory: true)
        let configURL = directory.appendingPathComponent("plaidbar.conf")
        try """
        PLAID_CLIENT_ID=
        PLAID_SECRET=
        PLAID_ENV=sandbox
        PLAIDBAR_DATA_DIR=\(dataDirectory.path)
        """.write(to: configURL, atomically: true, encoding: .utf8)
        return try ServerConfig.load(from: configURL.path)
    }

    private static func decodeBody<T: Decodable>(_ response: Response) async throws -> T {
        let collector = ResponseBodyCollector()
        let writer = CollectingResponseBodyWriter(collector: collector)
        try await response.body.write(writer)
        var buffer = await collector.collectedBuffer()
        let data = buffer.readData(length: buffer.readableBytes) ?? Data()
        return try JSONDecoder().decode(T.self, from: data)
    }

    private actor ResponseBodyCollector {
        private var buffer = ByteBuffer()

        func append(_ chunk: ByteBuffer) {
            var copy = chunk
            buffer.writeBuffer(&copy)
        }

        func collectedBuffer() -> ByteBuffer {
            buffer
        }
    }

    private struct CollectingResponseBodyWriter: ResponseBodyWriter {
        let collector: ResponseBodyCollector

        mutating func write(_ buffer: ByteBuffer) async throws {
            await collector.append(buffer)
        }

        consuming func finish(_ trailingHeaders: HTTPFields?) async throws {}
    }

    private static func saveRefreshItems(on fluent: Fluent) async throws {
        try await ItemModel(
            id: "item-a",
            accessToken: "token-a",
            institutionId: "ins-a",
            institutionName: "Institution A"
        ).save(on: fluent.db())
        try await ItemModel(
            id: "item-b",
            accessToken: "token-b",
            institutionId: "ins-b",
            institutionName: "Institution B"
        ).save(on: fluent.db())
        try await ItemModel(
            id: "item-c",
            accessToken: "token-c",
            institutionId: "ins-c",
            institutionName: "Institution C"
        ).save(on: fluent.db())
    }

    private static func accountsResponse(accountId: String) -> PlaidAccountsResponse {
        PlaidAccountsResponse(
            accounts: [
                PlaidAccount(
                    accountId: accountId,
                    balances: PlaidBalances(
                        available: 100,
                        current: 125,
                        limit: nil,
                        isoCurrencyCode: "USD",
                        unofficialCurrencyCode: nil
                    ),
                    mask: "0000",
                    name: accountId,
                    officialName: nil,
                    type: "depository",
                    subtype: "checking"
                ),
            ],
            item: nil,
            requestId: "request-\(accountId)"
        )
    }

    private static func syncResponse(
        transactionId: String,
        cursor: String
    ) -> PlaidTransactionsSyncResponse {
        PlaidTransactionsSyncResponse(
            added: [
                PlaidTransaction(
                    transactionId: transactionId,
                    accountId: "account-\(transactionId)",
                    amount: 12,
                    date: "2026-06-01",
                    name: transactionId,
                    merchantName: nil,
                    pending: false,
                    isoCurrencyCode: "USD",
                    personalFinanceCategory: nil
                ),
            ],
            modified: [],
            removed: [],
            nextCursor: cursor,
            hasMore: false,
            requestId: "request-\(transactionId)"
        )
    }

    /// Runs `body` against a TokenStore backed by a temporary SQLite file,
    /// and always shuts Fluent down so the test does not hold database files.
    private func withTokenStore(
        databasePath: String,
        logger: Logger,
        _ body: (TokenStore) async throws -> Void
    ) async throws {
        try await withTokenStore(databasePath: databasePath, logger: logger) { store, _ in
            try await body(store)
        }
    }

    private func withTokenStore(
        databasePath: String,
        logger: Logger,
        _ body: (TokenStore, Fluent) async throws -> Void
    ) async throws {
        let fluent = Fluent(logger: logger)
        fluent.databases.use(.sqlite(.file(databasePath)), as: .sqlite)
        await fluent.migrations.add(CreateItems())
        await fluent.migrations.add(AddProviderToItems())
        await fluent.migrations.add(CreateSyncCursors())

        var bodyError: Error?
        do {
            try await fluent.migrate()
            try await body(TokenStore(fluent: fluent, logger: logger), fluent)
        } catch {
            bodyError = error
        }
        try await fluent.shutdown()
        if let bodyError {
            throw bodyError
        }
    }

    private func withStatusStores(
        databasePath: String,
        logger: Logger,
        _ body: (TokenStore, BillingSubscriptionStore) async throws -> Void
    ) async throws {
        let fluent = Fluent(logger: logger)
        fluent.databases.use(.sqlite(.file(databasePath)), as: .sqlite)
        await fluent.migrations.add(CreateItems())
        await fluent.migrations.add(AddProviderToItems())
        await fluent.migrations.add(CreateSyncCursors())
        await fluent.migrations.add(CreateBillingSubscriptions())

        var bodyError: Error?
        do {
            try await fluent.migrate()
            try await body(
                TokenStore(fluent: fluent, logger: logger),
                BillingSubscriptionStore(fluent: fluent)
            )
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

    @Test("Account refresh preserves partial success and deterministic aggregation while bounded")
    func accountRefreshRunsWithBoundedConcurrencyAndStableAggregation() async throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("plaidbar-account-refresh-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }

        let databasePath = directory.appendingPathComponent("plaidbar-test.sqlite").path
        let logger = Logger(label: "com.ftchvs.plaidbar-server-tests.account-refresh")
        let client = DelayedRefreshPlaidClient(accountOutcomes: [
            "token-a": .success(Self.accountsResponse(accountId: "acct-a"), delayNanoseconds: 150_000_000),
            "token-b": .failure(PlaidError.apiError(
                statusCode: 400,
                errorType: "ITEM_ERROR",
                errorCode: "ITEM_LOGIN_REQUIRED",
                errorMessage: "login required"
            ), delayNanoseconds: 50_000_000),
            "token-c": .success(Self.accountsResponse(accountId: "acct-c"), delayNanoseconds: 10_000_000),
        ])

        try await withTokenStore(databasePath: databasePath, logger: logger) { store, fluent in
            try await Self.saveRefreshItems(on: fluent)
            let route = AccountRoutes(plaidClient: client, tokenStore: store, maxConcurrentItemRefreshes: 2)

            let response = try await route.listAccounts(
                request: Self.makeRequest(path: "/api/accounts"),
                context: TestRequestContext(source: TestRequestContextSource())
            )

            let accounts: [AccountDTO] = try await Self.decodeBody(response)
            #expect(accounts.map(\.id) == ["acct-a", "acct-c"])
            #expect(accounts.map(\.itemId) == ["item-a", "item-c"])
            let calls = await client.recordedCalls()
            #expect(calls.accounts.sorted() == ["token-a", "token-b", "token-c"])
            #expect(calls.maxActive == 2)
            #expect(try await store.getItem(id: "item-a")?.status == ItemConnectionStatus.connected.rawValue)
            #expect(try await store.getItem(id: "item-b")?.status == ItemConnectionStatus.loginRequired.rawValue)
            #expect(try await store.getItem(id: "item-c")?.status == ItemConnectionStatus.connected.rawValue)
        }
    }

    @Test("Balance refresh all-failure behavior is unchanged while bounded")
    func balanceRefreshAllFailureStillThrowsBadGateway() async throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("plaidbar-balance-refresh-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }

        let databasePath = directory.appendingPathComponent("plaidbar-test.sqlite").path
        let logger = Logger(label: "com.ftchvs.plaidbar-server-tests.balance-refresh")
        let client = DelayedRefreshPlaidClient(balanceOutcomes: [
            "token-a": .failure(delayNanoseconds: 120_000_000),
            "token-b": .failure(delayNanoseconds: 120_000_000),
            "token-c": .failure(delayNanoseconds: 10_000_000),
        ])

        try await withTokenStore(databasePath: databasePath, logger: logger) { store, fluent in
            try await Self.saveRefreshItems(on: fluent)
            let route = AccountRoutes(plaidClient: client, tokenStore: store, maxConcurrentItemRefreshes: 2)

            let error = await #expect(throws: HTTPError.self) {
                _ = try await route.getBalances(
                    request: Self.makeRequest(path: "/api/accounts/balances"),
                    context: TestRequestContext(source: TestRequestContextSource())
                )
            }

            #expect(error?.status == .badGateway)
            let calls = await client.recordedCalls()
            #expect(calls.balances.sorted() == ["token-a", "token-b", "token-c"])
            #expect(calls.maxActive == 2)
            #expect(try await store.getItem(id: "item-a")?.status == ItemConnectionStatus.error.rawValue)
            #expect(try await store.getItem(id: "item-b")?.status == ItemConnectionStatus.error.rawValue)
            #expect(try await store.getItem(id: "item-c")?.status == ItemConnectionStatus.error.rawValue)
        }
    }

    @Test("Credentials-not-configured remains a global setup error")
    func credentialsNotConfiguredDoesNotBecomePerItemFailure() async throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("plaidbar-credentials-refresh-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }

        let databasePath = directory.appendingPathComponent("plaidbar-test.sqlite").path
        let logger = Logger(label: "com.ftchvs.plaidbar-server-tests.credentials-refresh")
        let client = DelayedRefreshPlaidClient(accountOutcomes: [
            "token-a": .failure(PlaidError.credentialsNotConfigured),
            "token-b": .failure(PlaidError.credentialsNotConfigured),
            "token-c": .failure(PlaidError.credentialsNotConfigured),
        ])

        try await withTokenStore(databasePath: databasePath, logger: logger) { store, fluent in
            try await Self.saveRefreshItems(on: fluent)
            let route = AccountRoutes(plaidClient: client, tokenStore: store, maxConcurrentItemRefreshes: 2)

            let error = await #expect(throws: PlaidError.self) {
                _ = try await route.listAccounts(
                    request: Self.makeRequest(path: "/api/accounts"),
                    context: TestRequestContext(source: TestRequestContextSource())
                )
            }

            #expect(error == PlaidError.credentialsNotConfigured)
            #expect(try await store.getItem(id: "item-a")?.status == ItemConnectionStatus.connected.rawValue)
            #expect(try await store.getItem(id: "item-b")?.status == ItemConnectionStatus.connected.rawValue)
            #expect(try await store.getItem(id: "item-c")?.status == ItemConnectionStatus.connected.rawValue)
        }
    }

    @Test("Transaction sync preserves partial success and deterministic aggregation while bounded")
    func transactionSyncRunsWithBoundedConcurrencyAndStableAggregation() async throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("plaidbar-transaction-refresh-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }

        let databasePath = directory.appendingPathComponent("plaidbar-test.sqlite").path
        let logger = Logger(label: "com.ftchvs.plaidbar-server-tests.transaction-refresh")
        let client = DelayedRefreshPlaidClient(syncOutcomes: [
            "token-a": .success(Self.syncResponse(transactionId: "tx-a", cursor: "cursor-a"), delayNanoseconds: 150_000_000),
            "token-b": .failure(delayNanoseconds: 50_000_000),
            "token-c": .success(Self.syncResponse(transactionId: "tx-c", cursor: "cursor-c"), delayNanoseconds: 10_000_000),
        ])

        try await withTokenStore(databasePath: databasePath, logger: logger) { store, fluent in
            try await Self.saveRefreshItems(on: fluent)
            try await store.saveSyncCursor(itemId: "item-a", cursor: "old-a")
            try await store.saveSyncCursor(itemId: "item-c", cursor: "old-c")
            let route = TransactionRoutes(plaidClient: client, tokenStore: store, maxConcurrentItemRefreshes: 2)

            let response = try await route.syncTransactions(
                request: Self.makeRequest(path: "/api/transactions/sync"),
                context: TestRequestContext(source: TestRequestContextSource())
            )

            let sync: SyncResponse = try await Self.decodeBody(response)
            #expect(sync.added.map(\.id) == ["tx-a", "tx-c"])
            #expect(sync.added.map(\.itemId) == ["item-a", "item-c"])
            #expect(sync.nextCursor == "cursor-c")
            #expect(sync.pendingCursors == ["item-a": "cursor-a", "item-c": "cursor-c"])
            let calls = await client.recordedCalls()
            #expect(calls.syncs.sorted() == ["token-a", "token-b", "token-c"])
            #expect(calls.maxActive == 2)
            #expect(try await store.getItem(id: "item-b")?.status == ItemConnectionStatus.error.rawValue)
        }
    }

    @Test("Transaction sync rejects unknown explicit item id")
    func transactionSyncRejectsUnknownExplicitItemId() async throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("plaidbar-transaction-unknown-item-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }

        let databasePath = directory.appendingPathComponent("plaidbar-test.sqlite").path
        let logger = Logger(label: "com.ftchvs.plaidbar-server-tests.transaction-unknown-item")
        let client = DelayedRefreshPlaidClient()

        try await withTokenStore(databasePath: databasePath, logger: logger) { store in
            let route = TransactionRoutes(plaidClient: client, tokenStore: store, maxConcurrentItemRefreshes: 2)

            let error = await #expect(throws: HTTPError.self) {
                _ = try await route.syncTransactions(
                    request: Self.makeRequest(path: "/api/transactions/sync?item_id=missing-item"),
                    context: TestRequestContext(source: TestRequestContextSource())
                )
            }

            #expect(error?.status == .notFound)
            let calls = await client.recordedCalls()
            #expect(calls.syncs.isEmpty)
        }
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

    @Test("A completion lease holds single-flight even past the lease TTL until released")
    func completionLeaseHoldsUntilReleased() async {
        let clock = ManualDateClock(Date(timeIntervalSince1970: 1000))
        let store = PendingLinkSessionStore(
            ttl: 30 * 60,
            completionLeaseTTL: 60,
            now: { @Sendable in clock.now() }
        )
        let state = await store.issueState()
        await store.save(state: state, linkToken: "link-token")

        // First handler takes the lease.
        let first = await store.beginCompletion(state: state)
        #expect(first != nil)

        // A concurrent retry within the lease window is refused (single-flight).
        let concurrent = await store.beginCompletion(state: state)
        #expect(concurrent == nil)

        // The bug fix: advancing time past completionLeaseTTL while the original
        // handler is STILL running must not let purgeExpired drop the lease and
        // admit a second handler. Any intervening store call triggers a purge;
        // markResultCompleted is one such call.
        clock.advance(by: 30)
        await store.markResultCompleted(state: state, identity: "result-a")
        // Still within the 60s lease window → retry still refused even though a
        // purge just ran.
        let stillHeld = await store.beginCompletion(state: state)
        #expect(stillHeld == nil)

        // Only an explicit release returns the session to a retryable state.
        await store.releaseCompletion(state: state)
        let afterRelease = await store.beginCompletion(state: state)
        #expect(afterRelease != nil)
    }

    @Test("A held lease is never reclaimed on a timer; only release/consume frees it")
    func completionLeaseIsNotReclaimedByTimer() async {
        let clock = ManualDateClock(Date(timeIntervalSince1970: 1000))
        let store = PendingLinkSessionStore(
            ttl: 30 * 60,
            completionLeaseTTL: 60,
            now: { @Sendable in clock.now() }
        )
        let state = await store.issueState()
        await store.save(state: state, linkToken: "link-token")

        let first = await store.beginCompletion(state: state)
        #expect(first != nil)

        // Past the lease TTL with no release, a second handler must STILL be
        // refused: there is no proof the original handler is dead, and a
        // slow-but-alive handler must not be raced over the same single-use
        // tokens. (An in-memory lease for a truly crashed handler clears on
        // process restart, and the session itself expires at the session TTL.)
        clock.advance(by: 61)
        let blocked = await store.beginCompletion(state: state)
        #expect(blocked == nil)

        // Only an explicit release returns the session to a retryable state.
        await store.releaseCompletion(state: state)
        let afterRelease = await store.beginCompletion(state: state)
        #expect(afterRelease != nil)
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

    @Test(
        "OAuth callback can retry after transient completion failure",
        .enabled(if: plaidTokenVaultKeychainAvailable, "macOS Keychain accepts test writes")
    )
    func oauthCallbackCanRetryAfterTransientCompletionFailure() async throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("plaidbar-oauth-retry-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }

        let itemId = "synthetic_item_\(UUID().uuidString)"
        defer {
            try? PlaidTokenVault.delete(
                storedToken: PlaidTokenVault.reference(for: itemId),
                fallbackItemId: itemId
            )
        }

        let linkToken = "synthetic-link-token"
        let publicToken = "synthetic-public-token"
        let accessToken = "synthetic-access-token-\(UUID().uuidString)"
        let linkTokenGetResponse = PlaidLinkTokenGetResponse(
            linkToken: linkToken,
            linkSessions: [
                PlaidLinkSession(
                    linkSessionId: "synthetic-link-session",
                    results: PlaidLinkResults(
                        itemAddResults: [
                            PlaidLinkItemAddResult(
                                publicToken: publicToken,
                                institution: PlaidLinkInstitution(
                                    name: "Example Credit Union",
                                    institutionId: "ins_example_credit_union"
                                )
                            ),
                        ]
                    )
                ),
            ],
            onSuccess: nil,
            results: nil
        )
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
            ),
            exchangeFailuresBeforeSuccess: 1
        )
        let pendingLinkSessions = PendingLinkSessionStore(
            storageURL: directory.appendingPathComponent("pending-link-sessions.json")
        )
        let state = await pendingLinkSessions.issueState()
        await pendingLinkSessions.save(state: state, linkToken: linkToken)
        let databasePath = directory.appendingPathComponent("plaidbar-test.sqlite").path
        let logger = Logger(label: "com.ftchvs.plaidbar-server-tests.oauth-retry")

        try await withTokenStore(databasePath: databasePath, logger: logger) { store in
            let route = OAuthCallbackRoute(
                plaidClient: plaidClient,
                tokenStore: store,
                pendingLinkSessions: pendingLinkSessions
            )
            let request = Self.makeRequest(path: "/oauth/callback?state=\(state)")

            let failedResponse = try await route.handleCallback(
                request: request,
                context: TestRequestContext(source: TestRequestContextSource())
            )
            let retryResponse = try await route.handleCallback(
                request: request,
                context: TestRequestContext(source: TestRequestContextSource())
            )
            let replayResponse = try await route.handleCallback(
                request: request,
                context: TestRequestContext(source: TestRequestContextSource())
            )
            let savedItem = try #require(try await store.getItem(id: itemId))
            let calls = await plaidClient.recordedCalls()

            #expect(failedResponse.status == .internalServerError)
            #expect(retryResponse.status == .ok)
            #expect(replayResponse.status == .badRequest)
            #expect(savedItem.institutionName == "Example Credit Union")
            #expect(calls.linkTokens == [linkToken, linkToken])
            #expect(calls.publicTokens == [publicToken, publicToken])
            #expect(calls.accountAccessTokens == [accessToken])
        }
    }

    @Test(
        "OAuth callback retry skips completed Hosted Link results",
        .enabled(if: plaidTokenVaultKeychainAvailable, "macOS Keychain accepts test writes")
    )
    func oauthCallbackRetrySkipsCompletedHostedLinkResults() async throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("plaidbar-oauth-retry-progress-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }

        let firstItemId = "synthetic_item_one_\(UUID().uuidString)"
        let secondItemId = "synthetic_item_two_\(UUID().uuidString)"
        defer {
            try? PlaidTokenVault.delete(
                storedToken: PlaidTokenVault.reference(for: firstItemId),
                fallbackItemId: firstItemId
            )
            try? PlaidTokenVault.delete(
                storedToken: PlaidTokenVault.reference(for: secondItemId),
                fallbackItemId: secondItemId
            )
        }

        let linkToken = "synthetic-link-token"
        let firstPublicToken = "synthetic-public-token-one"
        let secondPublicToken = "synthetic-public-token-two"
        let firstAccessToken = "synthetic-access-token-one-\(UUID().uuidString)"
        let secondAccessToken = "synthetic-access-token-two-\(UUID().uuidString)"
        let linkTokenGetResponse = PlaidLinkTokenGetResponse(
            linkToken: linkToken,
            linkSessions: [
                PlaidLinkSession(
                    linkSessionId: "synthetic-link-session",
                    results: PlaidLinkResults(
                        itemAddResults: [
                            PlaidLinkItemAddResult(
                                publicToken: firstPublicToken,
                                institution: PlaidLinkInstitution(
                                    name: "Example Credit Union",
                                    institutionId: "ins_example_credit_union"
                                )
                            ),
                            PlaidLinkItemAddResult(
                                publicToken: secondPublicToken,
                                institution: PlaidLinkInstitution(
                                    name: "Example Bank",
                                    institutionId: "ins_example_bank"
                                )
                            ),
                        ]
                    )
                ),
            ],
            onSuccess: nil,
            results: nil
        )
        let plaidClient = HostedLinkStubPlaidClient(
            linkTokenGetResponse: linkTokenGetResponse,
            exchangeResponse: PlaidTokenExchangeResponse(
                accessToken: firstAccessToken,
                itemId: firstItemId,
                requestId: nil
            ),
            accountsResponse: PlaidAccountsResponse(
                accounts: [],
                item: PlaidItem(
                    itemId: firstItemId,
                    institutionId: "ins_accounts_fallback",
                    availableProducts: nil,
                    billedProducts: nil
                ),
                requestId: nil
            ),
            exchangeFailuresByPublicToken: [secondPublicToken: 1],
            exchangeResponsesByPublicToken: [
                firstPublicToken: PlaidTokenExchangeResponse(
                    accessToken: firstAccessToken,
                    itemId: firstItemId,
                    requestId: nil
                ),
                secondPublicToken: PlaidTokenExchangeResponse(
                    accessToken: secondAccessToken,
                    itemId: secondItemId,
                    requestId: nil
                ),
            ]
        )
        let pendingLinkSessions = PendingLinkSessionStore(
            storageURL: directory.appendingPathComponent("pending-link-sessions.json")
        )
        let state = await pendingLinkSessions.issueState()
        await pendingLinkSessions.save(state: state, linkToken: linkToken)
        let databasePath = directory.appendingPathComponent("plaidbar-test.sqlite").path
        let logger = Logger(label: "com.ftchvs.plaidbar-server-tests.oauth-retry-progress")

        try await withTokenStore(databasePath: databasePath, logger: logger) { store in
            let route = OAuthCallbackRoute(
                plaidClient: plaidClient,
                tokenStore: store,
                pendingLinkSessions: pendingLinkSessions
            )
            let request = Self.makeRequest(path: "/oauth/callback?state=\(state)")

            let failedResponse = try await route.handleCallback(
                request: request,
                context: TestRequestContext(source: TestRequestContextSource())
            )
            let retryResponse = try await route.handleCallback(
                request: request,
                context: TestRequestContext(source: TestRequestContextSource())
            )
            let replayResponse = try await route.handleCallback(
                request: request,
                context: TestRequestContext(source: TestRequestContextSource())
            )
            let firstSavedItem = try #require(try await store.getItem(id: firstItemId))
            let secondSavedItem = try #require(try await store.getItem(id: secondItemId))
            let calls = await plaidClient.recordedCalls()

            #expect(failedResponse.status == .internalServerError)
            #expect(retryResponse.status == .ok)
            #expect(replayResponse.status == .badRequest)
            #expect(firstSavedItem.institutionName == "Example Credit Union")
            #expect(secondSavedItem.institutionName == "Example Bank")
            #expect(calls.linkTokens == [linkToken, linkToken])
            #expect(calls.publicTokens == [
                firstPublicToken,
                secondPublicToken,
                secondPublicToken,
            ])
            #expect(calls.accountAccessTokens == [firstAccessToken, secondAccessToken])
        }
    }

    @Test(
        "A transient getAccounts failure does not lose the item; it is salvaged and stored once",
        .enabled(if: plaidTokenVaultKeychainAvailable, "macOS Keychain accepts test writes")
    )
    func oauthCallbackSalvagesItemWhenGetAccountsFails() async throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("plaidbar-oauth-postexchange-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }

        let itemId = "synthetic_item_\(UUID().uuidString)"
        defer {
            try? PlaidTokenVault.delete(
                storedToken: PlaidTokenVault.reference(for: itemId),
                fallbackItemId: itemId
            )
        }

        let linkToken = "synthetic-link-token"
        let publicToken = "synthetic-public-token"
        let accessToken = "synthetic-access-token-\(UUID().uuidString)"
        let linkTokenGetResponse = PlaidLinkTokenGetResponse(
            linkToken: linkToken,
            linkSessions: [
                PlaidLinkSession(
                    linkSessionId: "synthetic-link-session",
                    results: PlaidLinkResults(
                        itemAddResults: [
                            PlaidLinkItemAddResult(
                                publicToken: publicToken,
                                institution: PlaidLinkInstitution(
                                    name: "Example Credit Union",
                                    institutionId: "ins_example_credit_union"
                                )
                            ),
                        ]
                    )
                ),
            ],
            onSuccess: nil,
            results: nil
        )
        // Exchange SUCCEEDS; getAccounts fails. getAccounts only enriches
        // institution metadata, so a failure there must NOT lose the item — it is
        // salvaged using the result's own institution and stored on the first
        // attempt, with the public token exchanged exactly once.
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
            ),
            accountsFailuresBeforeSuccess: 1
        )
        let pendingLinkSessions = PendingLinkSessionStore(
            storageURL: directory.appendingPathComponent("pending-link-sessions.json")
        )
        let state = await pendingLinkSessions.issueState()
        await pendingLinkSessions.save(state: state, linkToken: linkToken)
        let databasePath = directory.appendingPathComponent("plaidbar-test.sqlite").path
        let logger = Logger(label: "com.ftchvs.plaidbar-server-tests.oauth-postexchange")

        try await withTokenStore(databasePath: databasePath, logger: logger) { store in
            let route = OAuthCallbackRoute(
                plaidClient: plaidClient,
                tokenStore: store,
                pendingLinkSessions: pendingLinkSessions
            )
            let request = Self.makeRequest(path: "/oauth/callback?state=\(state)")

            let response = try await route.handleCallback(
                request: request,
                context: TestRequestContext(source: TestRequestContextSource())
            )
            let savedItem = try await store.getItem(id: itemId)
            let calls = await plaidClient.recordedCalls()

            // The getAccounts failure was non-fatal: the item is stored and the
            // callback succeeds on the FIRST attempt, with no replay needed.
            #expect(response.status == .ok)
            #expect(savedItem != nil)
            #expect(savedItem?.institutionName == "Example Credit Union")
            #expect(calls.publicTokens == [publicToken]) // exchanged exactly once
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
