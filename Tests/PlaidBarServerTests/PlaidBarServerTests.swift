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

// Gated behind `PLAIDBAR_TEST_KEYCHAIN` and routed to an isolated, swept test
// service so the default `swift test` run never touches the login keychain.
// See `KeychainTestSupport`.
private let plaidTokenVaultKeychainAvailable = keychainTestSupportAvailable

private actor HostedLinkStubPlaidClient: PlaidClientProtocol {
    private let linkTokenGetResponse: PlaidLinkTokenGetResponse
    private let linkTokenGetError: (any Error & Sendable)?
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
        linkTokenGetError: (any Error & Sendable)? = nil,
        exchangeFailuresBeforeSuccess: Int = 0,
        exchangeFailuresByPublicToken: [String: Int] = [:],
        exchangeResponsesByPublicToken: [String: PlaidTokenExchangeResponse] = [:],
        accountsFailuresBeforeSuccess: Int = 0
    ) {
        self.linkTokenGetResponse = linkTokenGetResponse
        self.linkTokenGetError = linkTokenGetError
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
        if let linkTokenGetError {
            throw linkTokenGetError
        }
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

private actor HostedLinkCompletionResultRecorder {
    private var publicTokens: [String] = []

    func store(_ result: PlaidPublicTokenResult) -> OAuthCallbackRoute.StoreResultOutcome {
        publicTokens.append(result.publicToken)
        return .stored
    }

    func recordedPublicTokens() -> [String] {
        publicTokens
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

private actor PaginatedTransactionsPlaidClient: PlaidClientProtocol {
    enum Outcome: Sendable {
        case response(PlaidTransactionsSyncResponse)
        case error(any Error & Sendable)
    }

    private var outcomes: [Outcome]
    private var syncCalls: [(accessToken: String, cursor: String?)] = []

    init(responses: [PlaidTransactionsSyncResponse]) {
        self.outcomes = responses.map(Outcome.response)
    }

    init(outcomes: [Outcome]) {
        self.outcomes = outcomes
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

    func getAccounts(accessToken _: String) async throws -> PlaidAccountsResponse {
        throw PlaidError.invalidResponse
    }

    func getBalances(accessToken _: String) async throws -> PlaidAccountsResponse {
        throw PlaidError.invalidResponse
    }

    func syncTransactions(
        accessToken: String,
        cursor: String?
    ) async throws -> PlaidTransactionsSyncResponse {
        syncCalls.append((accessToken: accessToken, cursor: cursor))
        guard !outcomes.isEmpty else { throw PlaidError.invalidResponse }
        switch outcomes.removeFirst() {
        case let .response(response):
            return response
        case let .error(error):
            throw error
        }
    }

    func removeItem(accessToken _: String) async throws {
        throw PlaidError.invalidResponse
    }

    func recordedSyncCalls() -> [(accessToken: String, cursor: String?)] {
        syncCalls
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
                    fallbackItemId: itemId,
                    service: keychainTestService
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

    @Test func apiMiddlewareRejectsForeignBrowserOrigin() async throws {
        let middleware = APITokenMiddleware<TestRequestContext>(authToken: "local-token")
        let context = TestRequestContext(source: TestRequestContextSource())

        for request in [
            Self.makeRequest(
                path: "/api/status",
                authorization: "Bearer local-token",
                origin: "https://evil.example.com"
            ),
            Self.makeRequest(
                path: "/api/status",
                authorization: "Bearer local-token",
                referer: "https://evil.example.com/page"
            ),
            Self.makeRequest(
                path: "/api/status",
                authorization: "Bearer local-token",
                origin: "null"
            ),
        ] {
            do {
                _ = try await middleware.handle(request, context: context) { _, _ in
                    Response(status: .ok)
                }
                #expect(Bool(false), "Expected cross-origin API request to throw")
            } catch let error as HTTPError {
                #expect(error.status == .forbidden)
                #expect(error.body == "Cross-origin requests are not allowed")
            } catch {
                #expect(Bool(false), "Expected HTTPError, got \(error)")
            }
        }
    }

    @Test func apiMiddlewareAllowsNativeAppAndLoopbackOrigins() async throws {
        let middleware = APITokenMiddleware<TestRequestContext>(authToken: "local-token")
        let context = TestRequestContext(source: TestRequestContextSource())

        for request in [
            // Native app: no Origin or Referer header.
            Self.makeRequest(path: "/api/status", authorization: "Bearer local-token"),
            // Loopback origins are allowed in case a local tool calls the API.
            Self.makeRequest(
                path: "/api/status",
                authorization: "Bearer local-token",
                origin: "http://127.0.0.1:8484"
            ),
            Self.makeRequest(
                path: "/api/status",
                authorization: "Bearer local-token",
                origin: "http://localhost:8484",
                referer: "http://localhost:8484/index.html"
            ),
        ] {
            let response = try await middleware.handle(request, context: context) { _, _ in
                Response(status: .ok)
            }
            #expect(response.status == .ok)
        }
    }

    @Test func apiOriginAllowlistClassifiesHosts() {
        // Native app sends neither header.
        #expect(APITokenAuthorization.isAllowedBrowserOrigin(origin: nil, referer: nil))
        // Loopback hosts (with and without ports) are allowed.
        #expect(APITokenAuthorization.isAllowedBrowserOrigin(origin: "http://127.0.0.1:8484", referer: nil))
        #expect(APITokenAuthorization.isAllowedBrowserOrigin(origin: "http://localhost", referer: nil))
        #expect(APITokenAuthorization.isAllowedBrowserOrigin(origin: "http://[::1]:8484", referer: nil))
        // Foreign origins are rejected.
        #expect(!APITokenAuthorization.isAllowedBrowserOrigin(origin: "https://evil.example.com", referer: nil))
        #expect(!APITokenAuthorization.isAllowedBrowserOrigin(origin: nil, referer: "https://evil.example.com/p"))
        // Malformed values fail closed.
        #expect(!APITokenAuthorization.isAllowedBrowserOrigin(origin: "null", referer: nil))
        #expect(!APITokenAuthorization.isAllowedBrowserOrigin(origin: "127.0.0.1", referer: nil))
        // Lookalike hosts that merely contain a loopback substring are rejected.
        #expect(!APITokenAuthorization.isAllowedBrowserOrigin(origin: "http://localhost.evil.com", referer: nil))
    }

    @Test func oauthCallbackErrorPageEscapesDynamicMessage() {
        let html = OAuthCallbackRoute.errorPage("<script>alert('x')</script> & retry \"soon\"")

        #expect(!html.contains("<script>"))
        #expect(html.contains("&lt;script&gt;alert(&#39;x&#39;)&lt;/script&gt;"))
        #expect(html.contains("&amp; retry &quot;soon&quot;"))
    }

    private static func makeRequest(
        path: String,
        authorization: String? = nil,
        origin: String? = nil,
        referer: String? = nil
    ) -> Request {
        var headers = HTTPFields()
        if let authorization {
            headers[.authorization] = authorization
        }
        if let origin {
            headers[.origin] = origin
        }
        if let referer {
            headers[.referer] = referer
        }
        return Request(
            head: HTTPRequest(method: .get, scheme: nil, authority: nil, path: path, headerFields: headers),
            body: RequestBody(buffer: ByteBuffer())
        )
    }

    private static func makeJSONRequest(path: String, body: [String: String]) throws -> Request {
        var headers = HTTPFields()
        headers[.contentType] = "application/json"
        let data = try JSONEncoder().encode(body)
        return Request(
            head: HTTPRequest(method: .post, scheme: nil, authority: nil, path: path, headerFields: headers),
            body: RequestBody(buffer: ByteBuffer(data: data))
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
        let data = try await responseData(response)
        return try JSONDecoder().decode(T.self, from: data)
    }

    private static func decodeSyncBody(_ response: Response) async throws -> SyncResponse {
        try decodeSyncData(try await responseData(response))
    }

    private static func decodeSyncData(_ data: Data) throws -> SyncResponse {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return try decoder.decode(SyncResponse.self, from: data)
    }

    private static func responseData(_ response: Response) async throws -> Data {
        let collector = ResponseBodyCollector()
        let writer = CollectingResponseBodyWriter(collector: collector)
        try await response.body.write(writer)
        var buffer = await collector.collectedBuffer()
        return buffer.readData(length: buffer.readableBytes) ?? Data()
    }

    private static func responseString(_ response: Response) async throws -> String {
        let collector = ResponseBodyCollector()
        let writer = CollectingResponseBodyWriter(collector: collector)
        try await response.body.write(writer)
        var buffer = await collector.collectedBuffer()
        return buffer.readString(length: buffer.readableBytes) ?? ""
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
        cursor: String,
        hasMore: Bool = false
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
                    pendingTransactionId: nil,
                    isoCurrencyCode: "USD",
                    personalFinanceCategory: nil
                ),
            ],
            modified: [],
            removed: [],
            nextCursor: cursor,
            hasMore: hasMore,
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
        await fluent.migrations.add(AddOriginToItems())
        await fluent.migrations.add(CreateSyncCursors())

        var bodyError: Error?
        do {
            try await fluent.migrate()
            try await body(TokenStore(fluent: fluent, logger: logger, keychainService: keychainTestService, bypassKeychain: !keychainTestsEnabled), fluent)
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
        await fluent.migrations.add(AddOriginToItems())
        await fluent.migrations.add(CreateSyncCursors())
        await fluent.migrations.add(CreateBillingSubscriptions())

        var bodyError: Error?
        do {
            try await fluent.migrate()
            try await body(
                TokenStore(fluent: fluent, logger: logger, keychainService: keychainTestService, bypassKeychain: !keychainTestsEnabled),
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

    @Test("Account refresh maps API repair errors while preserving partial success")
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
                errorCode: "PENDING_EXPIRATION",
                errorMessage: "synthetic repair state"
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
            #expect(try await store.getItem(id: "item-b")?.status == ItemConnectionStatus.pendingExpiration.rawValue)
            #expect(try await store.getItem(id: "item-c")?.status == ItemConnectionStatus.connected.rawValue)
        }
    }

    @Test("Webhook item status mapping repairs only stale repair prompts")
    func webhookItemStatusMappingRepairsOnlyStaleRepairPrompts() {
        #expect(ItemStatusMapping.status(forWebhookCode: "ITEM_LOGIN_REQUIRED", currentStatus: .connected) == .loginRequired)
        #expect(ItemStatusMapping.status(forWebhookCode: "PENDING_DISCONNECT", currentStatus: .connected) == .pendingDisconnect)
        #expect(ItemStatusMapping.status(forWebhookCode: "USER_PERMISSION_REVOKED", currentStatus: .connected) == .permissionRevoked)
        #expect(ItemStatusMapping.status(forWebhookCode: "NEW_ACCOUNTS_AVAILABLE", currentStatus: .connected) == .newAccountsAvailable)
        #expect(ItemStatusMapping.status(forWebhookCode: "LOGIN_REPAIRED", currentStatus: .loginRequired) == .loginRepaired)
        #expect(ItemStatusMapping.status(forWebhookCode: "LOGIN_REPAIRED", currentStatus: .pendingExpiration) == .loginRepaired)
        #expect(ItemStatusMapping.status(forWebhookCode: "LOGIN_REPAIRED", currentStatus: .newAccountsAvailable) == .newAccountsAvailable)
        #expect(ItemStatusMapping.status(forWebhookCode: "LOGIN_REPAIRED", currentStatus: .error) == .error)
    }

    @Test("Provider-outage codes map to .providerOutage, login-required stays actionable")
    func itemStatusMappingRoutesProviderOutageCodes() {
        // Transient Plaid-side outages map to the non-actionable .providerOutage
        // state (AND-488), not to .error / .loginRequired.
        #expect(ItemStatusMapping.status(forWebhookCode: "INSTITUTION_DOWN", currentStatus: .connected) == .providerOutage)
        #expect(ItemStatusMapping.status(forWebhookCode: "INSTITUTION_NOT_RESPONDING", currentStatus: .connected) == .providerOutage)
        #expect(ItemStatusMapping.status(forWebhookCode: "PLANNED_MAINTENANCE", currentStatus: .connected) == .providerOutage)
        #expect(ItemStatusMapping.status(forWebhookCode: "INTERNAL_SERVER_ERROR", currentStatus: .connected) == .providerOutage)
        // ITEM_LOGIN_REQUIRED still maps to the actionable reconnect state.
        #expect(ItemStatusMapping.status(forWebhookCode: "ITEM_LOGIN_REQUIRED", currentStatus: .connected) == .loginRequired)
    }

    @Test("Token-vault/Keychain failures map to transient .providerOutage, not a hard .error")
    func itemStatusMappingTreatsTokenVaultFailuresAsTransient() {
        // A Keychain/token-vault failure while resolving an item's access token
        // is frequently transient (device locked, Keychain temporarily
        // unavailable, an ACL prompt). It must NOT permanently mark the item as
        // errored — that would surface a broken connection and trigger needless
        // reconnect/recovery UX for a recoverable hiccup (AND-669). It maps to
        // the non-actionable, auto-retried `.providerOutage` state instead.
        let tokenVaultErrors: [PlaidTokenVaultError] = [
            .keychainUnavailable,
            .keychainLoadFailed(-25300),
            .keychainSaveFailed(-34018),
            .keychainDeleteFailed(-25300),
            .invalidStoredToken
        ]
        for error in tokenVaultErrors {
            let status = ItemStatusMapping.status(forAPIError: error)
            #expect(status == .providerOutage)
            // Explicitly assert the bug is gone: never the hard error state.
            #expect(status != .error)
            // And it stays in the transient/retryable, non-reconnect lane.
            #expect(status.isProviderOutage)
            #expect(status.needsUpdateMode == false)
        }

        // A genuine Plaid item error still maps to the hard `.error` state — the
        // transient special-case must not swallow real connection failures.
        let genuineItemError = PlaidError.apiError(
            statusCode: 400,
            errorType: "ITEM_ERROR",
            errorCode: "ITEM_NOT_FOUND",
            errorMessage: "synthetic item error"
        )
        #expect(ItemStatusMapping.status(forAPIError: genuineItemError) == .error)
        // A non-Plaid, non-token-vault error remains a hard `.error` too.
        struct UnrelatedError: Error {}
        #expect(ItemStatusMapping.status(forAPIError: UnrelatedError()) == .error)
    }

    @Test("Webhook ERROR and repaired-with-new-accounts codes map correctly and preserve hard errors")
    func webhookItemStatusMappingHandlesErrorAndRepairedWithNewAccounts() {
        // A bare ITEM `ERROR` keeps the item degraded (login needed) rather than
        // dropping the signal — independent of the current status.
        #expect(ItemStatusMapping.status(forWebhookCode: "ERROR", currentStatus: .connected) == .loginRequired)
        #expect(ItemStatusMapping.status(forWebhookCode: "ERROR", currentStatus: .pendingExpiration) == .loginRequired)

        // `LOGIN_REPAIRED_WITH_NEW_ACCOUNTS` surfaces the actionable new-accounts
        // state from any non-error baseline...
        #expect(ItemStatusMapping.status(forWebhookCode: "LOGIN_REPAIRED_WITH_NEW_ACCOUNTS", currentStatus: .connected) == .newAccountsAvailable)
        #expect(ItemStatusMapping.status(forWebhookCode: "LOGIN_REPAIRED_WITH_NEW_ACCOUNTS", currentStatus: .pendingDisconnect) == .newAccountsAvailable)
        // ...but, like `LOGIN_REPAIRED`, it must not clobber a hard `.error`.
        #expect(ItemStatusMapping.status(forWebhookCode: "LOGIN_REPAIRED_WITH_NEW_ACCOUNTS", currentStatus: .error) == .error)
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

            let sync = try await Self.decodeSyncBody(response)
            #expect(sync.added.map(\.id) == ["tx-a", "tx-c"])
            #expect(sync.added.map(\.itemId) == ["item-a", "item-c"])
            #expect(sync.pendingCursors == ["item-a": "cursor-a", "item-c": "cursor-c"])
            let calls = await client.recordedCalls()
            #expect(calls.syncs.sorted() == ["token-a", "token-b", "token-c"])
            #expect(calls.maxActive == 2)
            #expect(try await store.getItem(id: "item-b")?.status == ItemConnectionStatus.error.rawValue)
        }
    }

    @Test("Paginated transaction sync advances with each page cursor")
    func paginatedTransactionSyncAdvancesWithEachPageCursor() async throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("plaidbar-paginated-sync-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }

        let databasePath = directory.appendingPathComponent("plaidbar-test.sqlite").path
        let logger = Logger(label: "com.ftchvs.plaidbar-server-tests.paginated-sync")
        let itemId = "test_item_\(UUID().uuidString)"
        let accessToken = "test-access-token-\(UUID().uuidString)"
        let client = PaginatedTransactionsPlaidClient(responses: [
            Self.syncResponse(transactionId: "tx-page-1", cursor: "cursor-1", hasMore: true),
            Self.syncResponse(transactionId: "tx-page-2", cursor: "cursor-2"),
        ])
        defer {
            try? PlaidTokenVault.delete(
                storedToken: PlaidTokenVault.reference(for: itemId),
                fallbackItemId: itemId,
                service: keychainTestService
            )
        }

        try await withTokenStore(databasePath: databasePath, logger: logger) { store in
            try await store.saveItem(
                id: itemId,
                accessToken: accessToken,
                institutionId: "ins_test",
                institutionName: "Test Bank"
            )
            try await store.saveSyncCursor(itemId: itemId, cursor: "persisted-cursor")
            let route = TransactionRoutes(plaidClient: client, tokenStore: store, maxConcurrentItemRefreshes: 2)

            let httpResponse = try await route.syncTransactions(
                request: Self.makeRequest(path: "/api/transactions/sync"),
                context: TestRequestContext(source: TestRequestContextSource())
            )
            let responseData = try await Self.responseData(httpResponse)
            let response = try Self.decodeSyncData(responseData)
            let calls = await client.recordedSyncCalls()

            #expect(calls.map(\.accessToken) == [accessToken, accessToken])
            #expect(calls.map(\.cursor) == ["persisted-cursor", "cursor-1"])
            #expect(response.added.map(\.id) == ["tx-page-1", "tx-page-2"])
            #expect(response.hasMore == false)
            #expect(response.pendingCursors == [itemId: "cursor-2"])
            let payload = try #require(try JSONSerialization.jsonObject(
                with: responseData
            ) as? [String: Any])
            let cursorUpdatedAts = try #require(payload["pendingCursorUpdatedAts"] as? [String: String])
            #expect(cursorUpdatedAts[itemId] != nil)
        }
    }

    @Test("Transaction sync restarts pagination when Plaid reports a mutation")
    func transactionSyncRestartsAfterPlaidPaginationMutation() async throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("plaidbar-paginated-mutation-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }

        let databasePath = directory.appendingPathComponent("plaidbar-test.sqlite").path
        let logger = Logger(label: "com.ftchvs.plaidbar-server-tests.paginated-mutation")
        let itemId = "test_item_\(UUID().uuidString)"
        let accessToken = "test-access-token-\(UUID().uuidString)"
        let mutation = PlaidError.apiError(
            statusCode: 400,
            errorType: "TRANSACTIONS_ERROR",
            errorCode: "TRANSACTIONS_SYNC_MUTATION_DURING_PAGINATION",
            errorMessage: "Transactions changed during pagination"
        )
        let client = PaginatedTransactionsPlaidClient(outcomes: [
            .response(Self.syncResponse(transactionId: "stale-page", cursor: "stale-cursor", hasMore: true)),
            .error(mutation),
            .response(Self.syncResponse(transactionId: "fresh-page-1", cursor: "fresh-cursor-1", hasMore: true)),
            .response(Self.syncResponse(transactionId: "fresh-page-2", cursor: "fresh-cursor-2")),
        ])
        defer {
            try? PlaidTokenVault.delete(
                storedToken: PlaidTokenVault.reference(for: itemId),
                fallbackItemId: itemId,
                service: keychainTestService
            )
        }

        try await withTokenStore(databasePath: databasePath, logger: logger) { store in
            try await store.saveItem(
                id: itemId,
                accessToken: accessToken,
                institutionId: "ins_test",
                institutionName: "Test Bank"
            )
            try await store.saveSyncCursor(itemId: itemId, cursor: "persisted-cursor")
            let route = TransactionRoutes(plaidClient: client, tokenStore: store, maxConcurrentItemRefreshes: 2)

            let httpResponse = try await route.syncTransactions(
                request: Self.makeRequest(path: "/api/transactions/sync"),
                context: TestRequestContext(source: TestRequestContextSource())
            )
            let response = try await Self.decodeSyncBody(httpResponse)
            let calls = await client.recordedSyncCalls()

            #expect(calls.map(\.cursor) == ["persisted-cursor", "stale-cursor", "persisted-cursor", "fresh-cursor-1"])
            #expect(response.added.map(\.id) == ["fresh-page-1", "fresh-page-2"])
            #expect(response.pendingCursors == [itemId: "fresh-cursor-2"])
        }
    }

    @Test("Transaction sync page-limit failure preserves other item results")
    func transactionSyncPageLimitFailurePreservesOtherItemResults() async throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("plaidbar-paginated-limit-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }

        let databasePath = directory.appendingPathComponent("plaidbar-test.sqlite").path
        let logger = Logger(label: "com.ftchvs.plaidbar-server-tests.paginated-limit")
        let client = PaginatedTransactionsPlaidClient(responses: [
            Self.syncResponse(transactionId: "ok-page", cursor: "ok-cursor"),
            Self.syncResponse(transactionId: "loop-page", cursor: "loop-cursor", hasMore: true),
        ] + (0..<PlaidBarConstants.maxTransactionSyncPages).map { index in
            Self.syncResponse(transactionId: "loop-page-\(index)", cursor: "loop-cursor-\(index)", hasMore: true)
        })
        defer {
            for itemId in ["a-item-ok", "z-item-loop"] {
                try? PlaidTokenVault.delete(
                    storedToken: PlaidTokenVault.reference(for: itemId),
                    fallbackItemId: itemId,
                    service: keychainTestService
                )
            }
        }

        try await withTokenStore(databasePath: databasePath, logger: logger) { store in
            try await store.saveItem(id: "a-item-ok", accessToken: "token-ok", institutionId: "ins_ok", institutionName: "OK Bank")
            try await store.saveItem(id: "z-item-loop", accessToken: "token-loop", institutionId: "ins_loop", institutionName: "Loop Bank")
            let route = TransactionRoutes(plaidClient: client, tokenStore: store, maxConcurrentItemRefreshes: 1)

            let httpResponse = try await route.syncTransactions(
                request: Self.makeRequest(path: "/api/transactions/sync"),
                context: TestRequestContext(source: TestRequestContextSource())
            )
            let response = try await Self.decodeSyncBody(httpResponse)

            #expect(response.added.map(\.id) == ["ok-page"])
            #expect(response.pendingCursors == ["a-item-ok": "ok-cursor"])
            #expect(try await store.getItem(id: "a-item-ok")?.status == ItemConnectionStatus.connected.rawValue)
            #expect(try await store.getItem(id: "z-item-loop")?.status == ItemConnectionStatus.error.rawValue)
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

    @Test("Conditional cursor save no-ops once the owning item is deleted")
    func conditionalCursorSaveSkipsDeletedItem() async throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("plaidbar-cursor-atomic-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }

        let databasePath = directory.appendingPathComponent("plaidbar-test.sqlite").path
        let logger = Logger(label: "com.ftchvs.plaidbar-server-tests.cursor-atomic")

        try await withTokenStore(databasePath: databasePath, logger: logger) { store, fluent in
            // Persist an item directly (no Keychain) so the test runs anywhere.
            try await ItemModel(
                id: "item-a",
                accessToken: "keychain:item-a",
                institutionId: "ins-a",
                institutionName: "Institution A"
            ).save(on: fluent.db())

            // While the item exists, the conditional save persists the cursor.
            let persisted = try await store.saveSyncCursorIfItemExists(itemId: "item-a", cursor: "cursor-1")
            #expect(persisted)
            #expect(try await store.getSyncCursor(itemId: "item-a") == "cursor-1")

            // After the item is deleted, a late cursor save must be a no-op and
            // must not resurrect a sync_cursors row for the gone item.
            try await store.deleteItem(id: "item-a")
            let skipped = try await store.saveSyncCursorIfItemExists(itemId: "item-a", cursor: "cursor-2")
            #expect(!skipped)
            #expect(try await store.getSyncCursor(itemId: "item-a") == nil)
        }
    }

    @Test("Cursor commit decodes ISO-8601 cursorUpdatedAts over the HTTP boundary")
    func cursorCommitDecodesISO8601UpdatedAts() async throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("plaidbar-cursor-commit-iso8601-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }

        let databasePath = directory.appendingPathComponent("plaidbar-test.sqlite").path
        let logger = Logger(label: "com.ftchvs.plaidbar-server-tests.cursor-commit-iso8601")
        let client = DelayedRefreshPlaidClient(syncOutcomes: [:])

        try await withTokenStore(databasePath: databasePath, logger: logger) { store, fluent in
            try await ItemModel(
                id: "item-a",
                accessToken: "keychain:item-a",
                institutionId: "ins-a",
                institutionName: "Institution A"
            ).save(on: fluent.db())
            let route = TransactionRoutes(plaidClient: client, tokenStore: store, maxConcurrentItemRefreshes: 2)

            // Mirror the real app client: ServerClient encodes the commit body —
            // including the `cursorUpdatedAts` dates — with `.iso8601`. The server
            // must decode that wire format. The router's default context decoder
            // uses `.deferredToDate` and would throw a `typeMismatch` on these
            // ISO-8601 date strings, so this drives the real HTTP decode boundary
            // (regression guard for AND-667 cursor-commit decoding).
            let cursorUpdatedAt = Date(timeIntervalSince1970: 1_800_000_000)
            let commit = SyncCursorCommitRequest(
                cursors: ["item-a": "cursor-after-sync"],
                cursorUpdatedAts: ["item-a": cursorUpdatedAt]
            )
            let encoder = JSONEncoder()
            encoder.dateEncodingStrategy = .iso8601
            let body = try encoder.encode(commit)
            var headers = HTTPFields()
            headers[.contentType] = "application/json"
            let request = Request(
                head: HTTPRequest(
                    method: .post,
                    scheme: nil,
                    authority: nil,
                    path: "/api/transactions/sync/cursors",
                    headerFields: headers
                ),
                body: RequestBody(buffer: ByteBuffer(data: body))
            )

            let status = try await route.commitSyncCursors(
                request: request,
                context: TestRequestContext(source: TestRequestContextSource())
            )

            #expect(status == .ok)
            #expect(try await store.getSyncCursor(itemId: "item-a") == "cursor-after-sync")
            // The cursor's observation time round-trips intact, so a stale cursor
            // committed after a newer sync webhook stays stale (the PR's intent).
            let updatedAts = try await store.syncCursorUpdatedAtsByItem()
            #expect(updatedAts["item-a"] == cursorUpdatedAt)
        }
    }

    @Test("Concurrent syncs for the same item coalesce onto a single Plaid pass")
    func concurrentItemSyncsCoalesce() async throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("plaidbar-sync-coalesce-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }

        let databasePath = directory.appendingPathComponent("plaidbar-test.sqlite").path
        let logger = Logger(label: "com.ftchvs.plaidbar-server-tests.sync-coalesce")
        // A deliberate delay keeps the first sync in flight long enough for the
        // second concurrent request to land on the coalescing gate.
        let client = DelayedRefreshPlaidClient(syncOutcomes: [
            "token-a": .success(
                Self.syncResponse(transactionId: "tx-a", cursor: "cursor-a"),
                delayNanoseconds: 200_000_000
            ),
        ])

        try await withTokenStore(databasePath: databasePath, logger: logger) { store, fluent in
            try await ItemModel(
                id: "item-a",
                accessToken: "token-a",
                institutionId: "ins-a",
                institutionName: "Institution A"
            ).save(on: fluent.db())
            // A single route instance shares one coalescer across both requests.
            let route = TransactionRoutes(plaidClient: client, tokenStore: store, maxConcurrentItemRefreshes: 2)

            async let first = route.syncTransactions(
                request: Self.makeRequest(path: "/api/transactions/sync?item_id=item-a"),
                context: TestRequestContext(source: TestRequestContextSource())
            )
            async let second = route.syncTransactions(
                request: Self.makeRequest(path: "/api/transactions/sync?item_id=item-a"),
                context: TestRequestContext(source: TestRequestContextSource())
            )

            let firstSync = try await Self.decodeSyncBody(try await first)
            let secondSync = try await Self.decodeSyncBody(try await second)

            // Both callers observe the same coalesced result.
            #expect(firstSync.added.map(\.id) == ["tx-a"])
            #expect(secondSync.added.map(\.id) == ["tx-a"])

            // The underlying Plaid sync ran exactly once for the item.
            let calls = await client.recordedCalls()
            #expect(calls.syncs == ["token-a"])
            #expect(calls.maxActive == 1)
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

    @Test("OAuth callback exchanges public token delivered on redirect")
    func oauthCallbackUsesRedirectPublicTokenWithoutSessionLookup() async throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("plaidbar-oauth-redirect-token-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }

        let linkToken = "redirect-link-token"
        let publicToken = "redirect-public-token"
        let plaidClient = HostedLinkStubPlaidClient(
            linkTokenGetResponse: PlaidLinkTokenGetResponse(
                linkToken: linkToken,
                linkSessions: nil,
                onSuccess: nil,
                results: nil
            ),
            exchangeResponse: PlaidTokenExchangeResponse(
                accessToken: "unused-access-token",
                itemId: "unused-item",
                requestId: nil
            ),
            accountsResponse: PlaidAccountsResponse(
                accounts: [],
                item: PlaidItem(
                    itemId: "unused-item",
                    institutionId: "ins_redirect",
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
        await pendingLinkSessions.save(state: state, linkToken: linkToken)
        let databasePath = directory.appendingPathComponent("plaidbar-test.sqlite").path
        let logger = Logger(label: "com.ftchvs.plaidbar-server-tests.oauth-redirect-token")
        let recorder = HostedLinkCompletionResultRecorder()

        try await withTokenStore(databasePath: databasePath, logger: logger) { store in
            let route = OAuthCallbackRoute(
                plaidClient: plaidClient,
                tokenStore: store,
                pendingLinkSessions: pendingLinkSessions,
                storePublicTokenResult: { result in
                    await recorder.store(result)
                }
            )
            let response = try await route.handleCallback(
                request: Self.makeRequest(path: "/oauth/callback?state=\(state)&public_token=\(publicToken)"),
                context: TestRequestContext(source: TestRequestContextSource())
            )
            let calls = await plaidClient.recordedCalls()
            let storedPublicTokens = await recorder.recordedPublicTokens()

            #expect(response.status == .ok)
            #expect(calls.linkTokens.isEmpty)
            #expect(calls.publicTokens.isEmpty)
            #expect(calls.accountAccessTokens.isEmpty)
            #expect(storedPublicTokens == [publicToken])
        }
    }

    @Test("OAuth callback ignores query-only success until Plaid confirms completion")
    func oauthCallbackDoesNotTrustQueryOnlySuccess() async throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("plaidbar-oauth-query-success-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }

        let linkToken = "query-success-link-token"
        let plaidClient = HostedLinkStubPlaidClient(
            linkTokenGetResponse: PlaidLinkTokenGetResponse(
                linkToken: linkToken,
                linkSessions: nil,
                onSuccess: nil,
                results: nil
            ),
            exchangeResponse: PlaidTokenExchangeResponse(
                accessToken: "unused-access-token",
                itemId: "unused-item",
                requestId: nil
            ),
            accountsResponse: PlaidAccountsResponse(
                accounts: [],
                item: nil,
                requestId: nil
            )
        )
        let pendingLinkSessions = PendingLinkSessionStore(
            storageURL: directory.appendingPathComponent("pending-link-sessions.json")
        )
        let state = await pendingLinkSessions.issueState()
        await pendingLinkSessions.save(state: state, linkToken: linkToken)
        let databasePath = directory.appendingPathComponent("plaidbar-test.sqlite").path
        let logger = Logger(label: "com.ftchvs.plaidbar-server-tests.oauth-query-success")
        let recorder = HostedLinkCompletionResultRecorder()

        try await withTokenStore(databasePath: databasePath, logger: logger) { store in
            let route = OAuthCallbackRoute(
                plaidClient: plaidClient,
                tokenStore: store,
                pendingLinkSessions: pendingLinkSessions,
                storePublicTokenResult: { result in
                    await recorder.store(result)
                }
            )
            let response = try await route.handleCallback(
                request: Self.makeRequest(path: "/oauth/callback?state=\(state)&error_code=SUCCESS"),
                context: TestRequestContext(source: TestRequestContextSource())
            )
            let body = try await Self.responseString(response)
            let calls = await plaidClient.recordedCalls()
            let storedPublicTokens = await recorder.recordedPublicTokens()

            #expect(response.status == .badRequest)
            #expect(body.contains("completed without a public token"))
            #expect(calls.linkTokens == [linkToken])
            #expect(calls.publicTokens.isEmpty)
            #expect(storedPublicTokens.isEmpty)
        }
    }

    @Test("Hosted Link webhook success allows callback to fetch public token from session lookup")
    func hostedLinkWebhookSuccessAllowsSessionLookup() async throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("plaidbar-webhook-session-token-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }

        let linkToken = "webhook-link-token"
        let publicToken = "webhook-public-token"
        let linkSessionId = "webhook-link-session"
        let linkTokenGetResponse = PlaidLinkTokenGetResponse(
            linkToken: linkToken,
            linkSessions: [
                PlaidLinkSession(
                    linkSessionId: linkSessionId,
                    results: PlaidLinkResults(
                        itemAddResults: [
                            PlaidLinkItemAddResult(
                                publicToken: publicToken,
                                institution: PlaidLinkInstitution(
                                    name: "Webhook Credit Union",
                                    institutionId: "ins_webhook"
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
                accessToken: "unused-access-token",
                itemId: "unused-item",
                requestId: nil
            ),
            accountsResponse: PlaidAccountsResponse(
                accounts: [],
                item: PlaidItem(
                    itemId: "unused-item",
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
        let hostedLinkCompletions = HostedLinkCompletionStore()
        let state = await pendingLinkSessions.issueState()
        await pendingLinkSessions.save(state: state, linkToken: linkToken)
        let databasePath = directory.appendingPathComponent("plaidbar-test.sqlite").path
        let logger = Logger(label: "com.ftchvs.plaidbar-server-tests.webhook-session-token")
        let recorder = HostedLinkCompletionResultRecorder()

        try await withTokenStore(databasePath: databasePath, logger: logger) { store in
            let webhook = HostedLinkWebhookRoute(hostedLinkCompletions: hostedLinkCompletions)
            let webhookResponse = try await webhook.receive(
                request: Self.makeJSONRequest(path: "/webhooks/plaid/hosted-link", body: [
                    "link_token": linkToken,
                    "link_session_id": linkSessionId,
                    "state": state,
                    "status": "success",
                ]),
                context: TestRequestContext(source: TestRequestContextSource())
            )
            let route = OAuthCallbackRoute(
                plaidClient: plaidClient,
                tokenStore: store,
                pendingLinkSessions: pendingLinkSessions,
                hostedLinkCompletions: hostedLinkCompletions,
                storePublicTokenResult: { result in
                    await recorder.store(result)
                }
            )
            let response = try await route.handleCallback(
                request: Self.makeRequest(path: "/oauth/callback?state=\(state)&link_session_id=\(linkSessionId)"),
                context: TestRequestContext(source: TestRequestContextSource())
            )
            let calls = await plaidClient.recordedCalls()
            let storedPublicTokens = await recorder.recordedPublicTokens()

            #expect(webhookResponse == .ok)
            #expect(response.status == .ok)
            #expect(calls.linkTokens == [linkToken])
            #expect(calls.publicTokens.isEmpty)
            #expect(storedPublicTokens == [publicToken])
        }
    }

    @Test("Hosted Link callback redacts provider error text from fallback HTML")
    func oauthCallbackRedactsProviderErrorText() async throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("plaidbar-oauth-provider-error-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }

        let linkToken = "provider-error-link-token"
        let providerSentinel = "sentinel provider detail from plaid raw error_message"
        let plaidClient = HostedLinkStubPlaidClient(
            linkTokenGetResponse: PlaidLinkTokenGetResponse(
                linkToken: linkToken,
                linkSessions: nil,
                onSuccess: nil,
                results: nil
            ),
            exchangeResponse: PlaidTokenExchangeResponse(
                accessToken: "unused-access-token",
                itemId: "unused-item",
                requestId: nil
            ),
            accountsResponse: PlaidAccountsResponse(
                accounts: [],
                item: PlaidItem(
                    itemId: "unused-item",
                    institutionId: "ins_unused",
                    availableProducts: nil,
                    billedProducts: nil
                ),
                requestId: nil
            ),
            linkTokenGetError: PlaidError.apiError(
                statusCode: 400,
                errorType: "INVALID_REQUEST",
                errorCode: "INVALID_FIELD",
                errorMessage: providerSentinel
            )
        )
        let pendingLinkSessions = PendingLinkSessionStore(
            storageURL: directory.appendingPathComponent("pending-link-sessions.json")
        )
        let state = await pendingLinkSessions.issueState()
        await pendingLinkSessions.save(state: state, linkToken: linkToken)
        let databasePath = directory.appendingPathComponent("plaidbar-test.sqlite").path
        let logger = Logger(label: "com.ftchvs.plaidbar-server-tests.oauth-provider-error")

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
            let body = try await Self.responseString(response)

            #expect(response.status == .internalServerError)
            #expect(body.contains("Plaid Link error (INVALID_FIELD)"))
            #expect(!body.contains(providerSentinel))
            #expect(!body.contains("raw error_message"))
            #expect(!body.contains("Plaid API error (400)"))
        }
    }

    @Test("Forged hosted-link completion keyed by link_token cannot veto a real success")
    func forgedHostedLinkCompletionCannotVetoRealSuccess() async throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("plaidbar-hosted-link-poison-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }

        let linkToken = "poison-link-token"
        let publicToken = "poison-public-token"
        let linkSessionId = "poison-link-session"
        let linkTokenGetResponse = PlaidLinkTokenGetResponse(
            linkToken: linkToken,
            linkSessions: [
                PlaidLinkSession(
                    linkSessionId: linkSessionId,
                    results: PlaidLinkResults(
                        itemAddResults: [
                            PlaidLinkItemAddResult(
                                publicToken: publicToken,
                                institution: PlaidLinkInstitution(
                                    name: "Honest Bank",
                                    institutionId: "ins_honest"
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
                accessToken: "unused-access-token",
                itemId: "unused-item",
                requestId: nil
            ),
            accountsResponse: PlaidAccountsResponse(
                accounts: [],
                item: PlaidItem(
                    itemId: "unused-item",
                    institutionId: "ins_honest",
                    availableProducts: nil,
                    billedProducts: nil
                ),
                requestId: nil
            )
        )
        let pendingLinkSessions = PendingLinkSessionStore(
            storageURL: directory.appendingPathComponent("pending-link-sessions.json")
        )
        let hostedLinkCompletions = HostedLinkCompletionStore()
        let state = await pendingLinkSessions.issueState()
        await pendingLinkSessions.save(state: state, linkToken: linkToken)

        // Attacker pre-seeds a non-success completion keyed only by the non-secret
        // link_token (no unguessable `state`), exactly as an unauthenticated POST
        // to /webhooks/plaid/hosted-link could.
        await hostedLinkCompletions.record(HostedLinkCompletionRecord(
            state: nil,
            linkToken: linkToken,
            linkSessionId: nil,
            status: .userExit
        ))

        let databasePath = directory.appendingPathComponent("plaidbar-test.sqlite").path
        let logger = Logger(label: "com.ftchvs.plaidbar-server-tests.hosted-link-poison")
        let recorder = HostedLinkCompletionResultRecorder()

        try await withTokenStore(databasePath: databasePath, logger: logger) { store in
            let route = OAuthCallbackRoute(
                plaidClient: plaidClient,
                tokenStore: store,
                pendingLinkSessions: pendingLinkSessions,
                hostedLinkCompletions: hostedLinkCompletions,
                storePublicTokenResult: { result in
                    await recorder.store(result)
                }
            )
            let response = try await route.handleCallback(
                request: Self.makeRequest(path: "/oauth/callback?state=\(state)&link_session_id=\(linkSessionId)"),
                context: TestRequestContext(source: TestRequestContextSource())
            )
            let storedPublicTokens = await recorder.recordedPublicTokens()

            // The authoritative Plaid session lookup wins; the forged failure,
            // keyed only by the non-secret link_token, cannot veto it.
            #expect(response.status == .ok)
            #expect(storedPublicTokens == [publicToken])
        }
    }

    @Test("Forged state-keyed failure cannot veto a genuine hosted-link completion")
    func forgedStateKeyedFailureCannotVetoHostedLinkCompletion() async throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("plaidbar-hosted-link-state-poison-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }

        // Genuine update-mode reconnection: Plaid's authoritative session lookup
        // returns NO public token (the legitimate empty-token success path), so
        // the callback should mark the item connected. This is the exact branch
        // that, on a non-success completion record keyed by `state`, used to throw
        // a forged failure instead of reporting the honest reconnection.
        let itemId = "synthetic_state_poison_item_\(UUID().uuidString)"
        let accessToken = "synthetic-state-poison-access-token-\(UUID().uuidString)"
        let linkToken = "state-poison-link-token"
        let plaidClient = HostedLinkStubPlaidClient(
            linkTokenGetResponse: PlaidLinkTokenGetResponse(
                linkToken: linkToken,
                linkSessions: nil,
                onSuccess: nil,
                results: nil
            ),
            exchangeResponse: PlaidTokenExchangeResponse(
                accessToken: accessToken,
                itemId: itemId,
                requestId: nil
            ),
            accountsResponse: PlaidAccountsResponse(
                accounts: [],
                item: PlaidItem(
                    itemId: itemId,
                    institutionId: "ins_state_poison",
                    availableProducts: nil,
                    billedProducts: nil
                ),
                requestId: nil
            )
        )
        let pendingLinkSessions = PendingLinkSessionStore(
            storageURL: directory.appendingPathComponent("pending-link-sessions.json")
        )
        let hostedLinkCompletions = HostedLinkCompletionStore()
        let state = await pendingLinkSessions.issueState()
        await pendingLinkSessions.save(state: state, linkToken: linkToken, updateItemId: itemId)

        // Attacker pre-seeds a non-success completion keyed by the *genuine*
        // single-use `state`, exactly as an unauthenticated POST to
        // /webhooks/plaid/hosted-link could race ahead of the real redirect.
        // The store is first-write-wins, so this is the record the empty-token
        // path used to consult and throw on.
        await hostedLinkCompletions.record(HostedLinkCompletionRecord(
            state: state,
            linkToken: nil,
            linkSessionId: nil,
            status: .providerFailure
        ))

        let databasePath = directory.appendingPathComponent("plaidbar-test.sqlite").path
        let logger = Logger(label: "com.ftchvs.plaidbar-server-tests.hosted-link-state-poison")

        try await withTokenStore(databasePath: databasePath, logger: logger) { store, fluent in
            try await ItemModel(
                id: itemId,
                accessToken: accessToken,
                institutionId: "ins_state_poison",
                institutionName: "Example Bank"
            ).save(on: fluent.db())
            try await store.updateItemStatus(id: itemId, status: ItemConnectionStatus.loginRequired.rawValue)

            let route = OAuthCallbackRoute(
                plaidClient: plaidClient,
                tokenStore: store,
                pendingLinkSessions: pendingLinkSessions,
                hostedLinkCompletions: hostedLinkCompletions
            )
            // The genuine redirect carries Plaid's own authoritative success
            // signal bound to the validated `state`; that must override an
            // unauthenticated stored failure for the same `state`.
            let response = try await route.handleCallback(
                request: Self.makeRequest(path: "/oauth/callback?state=\(state)&status=success"),
                context: TestRequestContext(source: TestRequestContextSource())
            )
            let calls = await plaidClient.recordedCalls()

            // The forged state-keyed failure must NOT veto the genuine
            // reconnection: the item is marked connected and the success page is
            // returned, not a "temporary problem"/user-exit failure.
            #expect(response.status == .ok)
            #expect(try await store.getItem(id: itemId)?.status == ItemConnectionStatus.connected.rawValue)
            #expect(calls.linkTokens == [linkToken])
            #expect(calls.publicTokens.isEmpty)
        }
    }

    @Test func hostedLinkCompletionStoreIsIdempotentByAnyIdentifier() async {
        let store = HostedLinkCompletionStore()
        let first = HostedLinkCompletionRecord(
            state: "state-one",
            linkToken: "link-token-one",
            linkSessionId: "session-one",
            status: .success,
            receivedAt: Date(timeIntervalSince1970: 1)
        )
        let duplicate = HostedLinkCompletionRecord(
            state: nil,
            linkToken: "link-token-one",
            linkSessionId: nil,
            status: .retryableProviderFailure,
            receivedAt: Date(timeIntervalSince1970: 2)
        )

        let stored = await store.record(first)
        let storedAgain = await store.record(duplicate)
        let byState = await store.completion(state: "state-one", linkToken: nil)
        let byLinkToken = await store.completion(state: nil, linkToken: "link-token-one")
        let bySession = await store.completion(state: nil, linkToken: nil, linkSessionId: "session-one")

        #expect(stored == first)
        #expect(storedAgain == first)
        #expect(byState == first)
        #expect(byLinkToken == first)
        #expect(bySession == first)
    }

    @Test func hostedLinkCompletionStoreAuthoritativeRecordOverridesUnauthenticatedFailure() async {
        let store = HostedLinkCompletionStore()

        // An unauthenticated webhook pre-seeds a failure for a known state.
        let forgedFailure = HostedLinkCompletionRecord(
            state: "state-x",
            linkToken: nil,
            linkSessionId: nil,
            status: .providerFailure,
            authoritative: false,
            receivedAt: Date(timeIntervalSince1970: 1)
        )
        // The genuine OAuth redirect, validated against the pending session,
        // records an authoritative success for the same state.
        let authoritativeSuccess = HostedLinkCompletionRecord(
            state: "state-x",
            linkToken: nil,
            linkSessionId: nil,
            status: .success,
            authoritative: true,
            receivedAt: Date(timeIntervalSince1970: 2)
        )
        // A later unauthenticated failure must NOT clobber the authoritative one.
        let lateForgedFailure = HostedLinkCompletionRecord(
            state: "state-x",
            linkToken: nil,
            linkSessionId: nil,
            status: .providerFailure,
            authoritative: false,
            receivedAt: Date(timeIntervalSince1970: 3)
        )

        await store.record(forgedFailure)
        let afterAuthoritative = await store.record(authoritativeSuccess)
        let afterLateForgery = await store.record(lateForgedFailure)
        let current = await store.completion(state: "state-x", linkToken: nil)

        // The authoritative success wins and the later forgery cannot demote it.
        #expect(afterAuthoritative == authoritativeSuccess)
        #expect(afterLateForgery == authoritativeSuccess)
        #expect(current == authoritativeSuccess)
        #expect(current?.authoritative == true)
        #expect(current?.status == .success)
    }

    @Test func oauthCallbackDistinguishesUserExitExpiredAndRetryableProviderFailure() async throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("plaidbar-oauth-outcome-copy-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }

        let databasePath = directory.appendingPathComponent("plaidbar-test.sqlite").path
        let logger = Logger(label: "com.ftchvs.plaidbar-server-tests.oauth-outcome-copy")

        try await withTokenStore(databasePath: databasePath, logger: logger) { store in
            let pendingLinkSessions = PendingLinkSessionStore()
            let exitState = await pendingLinkSessions.issueState()
            let expiredState = await pendingLinkSessions.issueState()
            let retryState = await pendingLinkSessions.issueState()
            await pendingLinkSessions.save(state: exitState, linkToken: "unused")
            await pendingLinkSessions.save(state: expiredState, linkToken: "unused")
            await pendingLinkSessions.save(state: retryState, linkToken: "unused")

            let route = OAuthCallbackRoute(
                plaidClient: HostedLinkStubPlaidClient(
                    linkTokenGetResponse: PlaidLinkTokenGetResponse(
                        linkToken: "unused",
                        linkSessions: nil,
                        onSuccess: nil,
                        results: nil
                    ),
                    exchangeResponse: PlaidTokenExchangeResponse(
                        accessToken: "unused-access-token",
                        itemId: "unused-item",
                        requestId: nil
                    ),
                    accountsResponse: PlaidAccountsResponse(accounts: [], item: nil, requestId: nil)
                ),
                tokenStore: store,
                pendingLinkSessions: pendingLinkSessions
            )
            let context = TestRequestContext(source: TestRequestContextSource())

            let userExit = try await route.handleCallback(
                request: Self.makeRequest(path: "/oauth/callback?state=\(exitState)&error_code=USER_EXIT"),
                context: context
            )
            let expired = try await route.handleCallback(
                request: Self.makeRequest(path: "/oauth/callback?state=\(expiredState)&error_code=LINK_TOKEN_EXPIRED"),
                context: context
            )
            let retryable = try await route.handleCallback(
                request: Self.makeRequest(path: "/oauth/callback?state=\(retryState)&error_code=INSTITUTION_DOWN"),
                context: context
            )

            #expect(userExit.status == .ok)
            #expect(try await Self.responseString(userExit).contains("Connection Canceled"))
            #expect(expired.status == .badRequest)
            #expect(try await Self.responseString(expired).contains("expired"))
            #expect(retryable.status == .internalServerError)
            #expect(try await Self.responseString(retryable).contains("temporary problem"))
        }
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
                fallbackItemId: itemId,
                service: keychainTestService
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
                fallbackItemId: itemId,
                service: keychainTestService
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

    @Test("OAuth update completion clears new account prompt")
    func oauthUpdateCompletionClearsNewAccountPrompt() async throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("plaidbar-oauth-update-completion-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }

        let itemId = "synthetic_update_item_\(UUID().uuidString)"
        let accessToken = "synthetic-update-access-token-\(UUID().uuidString)"

        let linkToken = "synthetic-update-link-token"
        let plaidClient = HostedLinkStubPlaidClient(
            linkTokenGetResponse: PlaidLinkTokenGetResponse(
                linkToken: linkToken,
                linkSessions: nil,
                onSuccess: nil,
                results: nil
            ),
            exchangeResponse: PlaidTokenExchangeResponse(
                accessToken: accessToken,
                itemId: itemId,
                requestId: nil
            ),
            accountsResponse: PlaidAccountsResponse(
                accounts: [],
                item: PlaidItem(
                    itemId: itemId,
                    institutionId: "ins_update",
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
        await pendingLinkSessions.save(state: state, linkToken: linkToken, updateItemId: itemId)
        let databasePath = directory.appendingPathComponent("plaidbar-test.sqlite").path
        let logger = Logger(label: "com.ftchvs.plaidbar-server-tests.oauth-update-completion")

        try await withTokenStore(databasePath: databasePath, logger: logger) { store, fluent in
            try await ItemModel(
                id: itemId,
                accessToken: accessToken,
                institutionId: "ins_update",
                institutionName: "Example Bank"
            ).save(on: fluent.db())
            try await store.updateItemStatus(id: itemId, status: ItemConnectionStatus.newAccountsAvailable.rawValue)

            let route = OAuthCallbackRoute(
                plaidClient: plaidClient,
                tokenStore: store,
                pendingLinkSessions: pendingLinkSessions
            )
            let response = try await route.handleCallback(
                request: Self.makeRequest(path: "/oauth/callback?state=\(state)"),
                context: TestRequestContext(source: TestRequestContextSource())
            )
            let calls = await plaidClient.recordedCalls()

            #expect(response.status == .ok)
            #expect(try await store.getItem(id: itemId)?.status == ItemConnectionStatus.connected.rawValue)
            #expect(calls.linkTokens == [linkToken])
            #expect(calls.publicTokens.isEmpty)
            #expect(calls.accountAccessTokens.isEmpty)
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
                fallbackItemId: firstItemId,
                service: keychainTestService
            )
            try? PlaidTokenVault.delete(
                storedToken: PlaidTokenVault.reference(for: secondItemId),
                fallbackItemId: secondItemId,
                service: keychainTestService
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
                fallbackItemId: itemId,
                service: keychainTestService
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
            itemId: itemId,
            service: keychainTestService
        )
        defer { try? PlaidTokenVault.delete(storedToken: storedToken, fallbackItemId: itemId, service: keychainTestService) }

        #expect(PlaidTokenVault.isReference(storedToken))
        #expect(try PlaidTokenVault.resolve(storedToken: storedToken, service: keychainTestService) == "access-sandbox-token")
    }

    @Test(.enabled(if: plaidTokenVaultKeychainAvailable, "macOS Keychain accepts test writes"))
    func plaidTokenVaultUpdatesExistingKeychainToken() throws {
        let itemId = "test_item_\(UUID().uuidString)"
        let firstReference = try PlaidTokenVault.store(
            accessToken: "access-sandbox-token-old",
            itemId: itemId,
            service: keychainTestService
        )
        defer { try? PlaidTokenVault.delete(storedToken: firstReference, fallbackItemId: itemId, service: keychainTestService) }

        let secondReference = try PlaidTokenVault.store(
            accessToken: "access-sandbox-token-new",
            itemId: itemId,
            service: keychainTestService
        )

        #expect(firstReference == secondReference)
        #expect(try PlaidTokenVault.resolve(storedToken: secondReference, service: keychainTestService) == "access-sandbox-token-new")
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
