import FluentKit
import FluentSQLiteDriver
import Foundation
import Hummingbird
import HTTPTypes
import HummingbirdFluent
import Logging
import NIOCore
@testable import PlaidBarCore
@testable import PlaidBarServer
import Testing

private struct ReliabilityTestRequestContextSource: RequestContextSource {
    let logger = Logger(label: "com.ftchvs.plaidbar-server-tests.sandbox-reliability")
}

private struct ReliabilityTestRequestContext: RequestContext {
    typealias Source = ReliabilityTestRequestContextSource

    var coreContext: CoreRequestContextStorage

    init(source: ReliabilityTestRequestContextSource) {
        coreContext = CoreRequestContextStorage(source: source)
    }
}

/// Sandbox reliability and production-readiness boundaries (PR-016 T076-T078,
/// PR-017 T082): clean-directory setup, missing-credential diagnosis,
/// sync-cursor preservation across server restarts, and strict
/// sandbox-vs-production storage separation.
///
/// All credentials in this suite are synthetic test strings; nothing here
/// contacts Plaid, the network, or the macOS Keychain.
@Suite("Sandbox reliability and production boundaries")
struct SandboxReliabilityTests {
    // MARK: - T076: clean temporary data directory

    @Test("Sandbox setup succeeds from a clean temporary data directory")
    func sandboxSetupSucceedsFromCleanTemporaryDataDirectory() throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("plaidbar-clean-setup-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }

        // The data directory deliberately does not exist yet: a first
        // sandbox run must provision everything from nothing.
        let dataDirectory = directory.appendingPathComponent("fresh-data", isDirectory: true)
        #expect(!FileManager.default.fileExists(atPath: dataDirectory.path))

        let configURL = directory.appendingPathComponent("plaidbar.conf")
        try """
        PLAID_CLIENT_ID=test-sandbox-client
        PLAID_SECRET=test-sandbox-secret
        PLAID_ENV=sandbox
        PLAIDBAR_DATA_DIR=\(dataDirectory.path)
        """.write(to: configURL, atomically: true, encoding: .utf8)

        let config = try ServerConfig.load(from: configURL.path)
        try ServerConfig.preparePrivateSQLiteStoreForOpen(at: config.databasePath)

        #expect(config.plaidEnvironment == .sandbox)
        #expect(config.credentialsConfigured)
        #expect(config.credentialDiagnosis == .configured)
        #expect(config.databasePath.hasSuffix("/plaidbar-sandbox.sqlite"))
        #expect(try posixPermissions(at: dataDirectory) == 0o700)
        #expect(try posixPermissions(
            at: dataDirectory.appendingPathComponent(LocalDataStore.authTokenFilename)
        ) == 0o600)
        #expect(FileManager.default.fileExists(atPath: config.databasePath))
        #expect(try posixPermissions(at: URL(fileURLWithPath: config.databasePath)) == 0o600)
    }

    // MARK: - T077: missing-credential diagnosis

    @Test("Credential diagnosis names exactly the missing variable")
    func credentialDiagnosisNamesExactlyTheMissingVariable() {
        #expect(CredentialSetupDiagnosis.diagnose(clientId: "", secret: "") == .missingBoth)
        #expect(CredentialSetupDiagnosis.diagnose(clientId: "test-client", secret: "") == .missingSecret)
        #expect(CredentialSetupDiagnosis.diagnose(clientId: "", secret: "test-secret") == .missingClientId)
        #expect(CredentialSetupDiagnosis.diagnose(
            clientId: "test-client",
            secret: "test-secret"
        ) == .configured)

        #expect(CredentialSetupDiagnosis.missingBoth.missingVariableNames ==
            ["PLAID_CLIENT_ID", "PLAID_SECRET"])
        #expect(CredentialSetupDiagnosis.missingClientId.missingVariableNames == ["PLAID_CLIENT_ID"])
        #expect(CredentialSetupDiagnosis.missingSecret.missingVariableNames == ["PLAID_SECRET"])
        #expect(CredentialSetupDiagnosis.configured.missingVariableNames.isEmpty)
        #expect(CredentialSetupDiagnosis.configured.setupGuidance(environment: .sandbox) == nil)
        #expect(CredentialSetupDiagnosis.configured.setupGuidance(environment: .production) == nil)
    }

    @Test("Partial-credential guidance points at the single missing variable")
    func partialCredentialGuidancePointsAtSingleMissingVariable() throws {
        let guidance = try #require(
            CredentialSetupDiagnosis.missingSecret.setupGuidance(environment: .sandbox)
        )

        #expect(guidance.contains("PLAID_SECRET"))
        #expect(guidance.contains("Add PLAID_SECRET to server.conf"))
        // The one configured variable must not be re-requested.
        #expect(!guidance.contains("Add PLAID_CLIENT_ID"))

        let clientGuidance = try #require(
            CredentialSetupDiagnosis.missingClientId.setupGuidance(environment: .sandbox)
        )
        #expect(clientGuidance.contains("Add PLAID_CLIENT_ID to server.conf"))
        #expect(!clientGuidance.contains("Add PLAID_SECRET"))
    }

    @Test("Sandbox guidance never implies production readiness")
    func sandboxGuidanceNeverImpliesProductionReadiness() throws {
        let guidance = try #require(
            CredentialSetupDiagnosis.missingBoth.setupGuidance(environment: .sandbox)
        )

        #expect(guidance.contains("sandbox"))
        #expect(guidance.contains("test institutions"))
        #expect(guidance.contains("never touches real financial data"))
        #expect(!guidance.contains("production approval"))
    }

    @Test("Production guidance is explicit about Plaid approval and real data")
    func productionGuidanceIsExplicitAboutApprovalAndRealData() throws {
        let guidance = try #require(
            CredentialSetupDiagnosis.missingBoth.setupGuidance(environment: .production)
        )

        #expect(guidance.contains("production"))
        #expect(guidance.contains("real financial accounts"))
        #expect(guidance.contains("Plaid production approval"))
        #expect(guidance.contains("sandbox credentials will not work"))
    }

    @Test("Guidance carries variable names only, never credential values")
    func guidanceCarriesVariableNamesOnlyNeverCredentialValues() throws {
        let configuredValue = "test-secret-value-\(UUID().uuidString)"
        let diagnosis = CredentialSetupDiagnosis.diagnose(clientId: configuredValue, secret: "")
        let guidance = try #require(diagnosis.setupGuidance(environment: .sandbox))

        #expect(diagnosis == .missingSecret)
        #expect(!guidance.contains(configuredValue))
    }

    @Test("Setup-state 503 body names the missing credential variable")
    func setupState503BodyNamesMissingCredentialVariable() async throws {
        let middleware = SetupStateMiddleware<ReliabilityTestRequestContext>(
            credentialDiagnosis: .missingSecret,
            plaidEnvironment: .sandbox
        )
        let context = ReliabilityTestRequestContext(source: ReliabilityTestRequestContextSource())

        let response = try await middleware.handle(
            Self.makeRequest(path: "/api/accounts"),
            context: context
        ) { _, _ in
            Response(status: .ok)
        }

        #expect(response.status == .serviceUnavailable)
        let message = SetupStateMiddleware<ReliabilityTestRequestContext>.setupStateMessage(
            diagnosis: .missingSecret,
            environment: .sandbox
        )
        #expect(message.contains("PLAID_SECRET"))

        // Readiness metadata keeps flowing in the same setup state.
        let statusResponse = try await middleware.handle(
            Self.makeRequest(path: "/api/status"),
            context: context
        ) { _, _ in
            Response(status: .ok)
        }
        #expect(statusResponse.status == .ok)
    }

    // MARK: - T078: sync-cursor preservation

    @Test("Sync cursor state survives a server restart")
    func syncCursorStateSurvivesServerRestart() async throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("plaidbar-cursor-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }

        let databasePath = directory.appendingPathComponent("plaidbar-sandbox.sqlite").path
        let logger = Logger(label: "com.ftchvs.plaidbar-server-tests.cursor")
        let itemId = "test_item_\(UUID().uuidString)"

        // First server lifetime: commit an initial cursor, then advance it.
        try await withTokenStore(databasePath: databasePath, logger: logger) { store in
            try await store.saveSyncCursor(itemId: itemId, cursor: "cursor-page-1")
            #expect(try await store.getSyncCursor(itemId: itemId) == "cursor-page-1")

            try await store.saveSyncCursor(itemId: itemId, cursor: "cursor-page-2")
            #expect(try await store.getSyncCursor(itemId: itemId) == "cursor-page-2")
            #expect(try await store.syncedItemCount() == 1)
        }

        // Second server lifetime: the committed cursor must come back
        // exactly, so the next sandbox sync resumes instead of refetching
        // the item's full history.
        try await withTokenStore(databasePath: databasePath, logger: logger) { store in
            let restoredCursor = try await store.getSyncCursor(itemId: itemId)
            let syncedCount = try await store.syncedItemCount()
            let lastSync = try await store.lastSyncDate()
            #expect(restoredCursor == "cursor-page-2")
            #expect(syncedCount == 1)
            #expect(lastSync != nil)
        }
    }

    @Test("Empty cursor commits never clobber a stored cursor")
    func emptyCursorCommitsNeverClobberStoredCursor() {
        #expect(TransactionRoutes.normalizedCommittableCursor("") == nil)
        #expect(TransactionRoutes.normalizedCommittableCursor("   ") == nil)
        #expect(TransactionRoutes.normalizedCommittableCursor("\n\t") == nil)
        #expect(TransactionRoutes.normalizedCommittableCursor("cursor-page-3") == "cursor-page-3")
        #expect(TransactionRoutes.normalizedCommittableCursor("  cursor-page-3\n") == "cursor-page-3")
    }

    // MARK: - T082: sandbox/production storage separation

    @Test("Sandbox and production modes use separate stores in one data directory")
    func sandboxAndProductionModesUseSeparateStores() throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("plaidbar-env-split-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }

        let dataDirectory = directory.appendingPathComponent("data", isDirectory: true)
        let configURL = directory.appendingPathComponent("plaidbar.conf")
        try """
        PLAID_CLIENT_ID=test-client
        PLAID_SECRET=test-secret
        PLAID_ENV=sandbox
        PLAIDBAR_DATA_DIR=\(dataDirectory.path)
        """.write(to: configURL, atomically: true, encoding: .utf8)

        let sandboxConfig = try ServerConfig.load(from: configURL.path, sandboxOverride: true)
        let productionConfig = try ServerConfig.load(from: configURL.path, sandboxOverride: false)

        #expect(sandboxConfig.plaidEnvironment == .sandbox)
        #expect(productionConfig.plaidEnvironment == .production)
        #expect(sandboxConfig.databasePath != productionConfig.databasePath)
        #expect(sandboxConfig.databasePath.hasSuffix("/plaidbar-sandbox.sqlite"))
        #expect(productionConfig.databasePath.hasSuffix("/plaidbar-production.sqlite"))
        // Both stores share the data directory without sharing files.
        #expect(sandboxConfig.dataDirectoryPath == productionConfig.dataDirectoryPath)

        // Booting one environment must never create or touch the other's
        // store file.
        try ServerConfig.preparePrivateSQLiteStoreForOpen(at: sandboxConfig.databasePath)
        try Data("sandbox-store".utf8).write(to: URL(fileURLWithPath: sandboxConfig.databasePath))
        #expect(!FileManager.default.fileExists(atPath: productionConfig.databasePath))

        try ServerConfig.preparePrivateSQLiteStoreForOpen(at: productionConfig.databasePath)
        try Data("production-store".utf8).write(to: URL(fileURLWithPath: productionConfig.databasePath))

        #expect(try Data(contentsOf: URL(fileURLWithPath: sandboxConfig.databasePath)) ==
            Data("sandbox-store".utf8))
        #expect(try Data(contentsOf: URL(fileURLWithPath: productionConfig.databasePath)) ==
            Data("production-store".utf8))
    }

    @Test("Transaction caches are scoped per environment store")
    func transactionCachesAreScopedPerEnvironmentStore() throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("plaidbar-cache-split-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }

        let sandboxContext = TransactionCacheContext(
            environment: .sandbox,
            storagePath: ServerConfig.databasePath(in: directory.path, environment: .sandbox)
        )
        let productionContext = TransactionCacheContext(
            environment: .production,
            storagePath: ServerConfig.databasePath(in: directory.path, environment: .production)
        )

        try LocalDataStore.saveTransactions(
            [TransactionDTO(
                id: "tx-sandbox",
                accountId: "checking",
                amount: 12,
                date: "2026-06-01",
                name: "Coffee"
            )],
            to: directory,
            context: sandboxContext
        )

        #expect(try LocalDataStore.loadTransactions(
            from: directory,
            context: sandboxContext
        ).map(\.id) == ["tx-sandbox"])
        #expect(try LocalDataStore.loadTransactions(
            from: directory,
            context: productionContext
        ).isEmpty)
    }

    // MARK: - Helpers

    private static func makeRequest(path: String) -> Request {
        Request(
            head: HTTPRequest(
                method: .get,
                scheme: nil,
                authority: nil,
                path: path,
                headerFields: HTTPFields()
            ),
            body: RequestBody(buffer: ByteBuffer())
        )
    }

    /// Runs `body` against a TokenStore backed by a real SQLite file, and
    /// always shuts the Fluent stack down so a follow-up store sees fully
    /// persisted state — the same shape as a server restart.
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

    private func posixPermissions(at url: URL) throws -> Int {
        let attributes = try FileManager.default.attributesOfItem(atPath: url.path)
        return (attributes[.posixPermissions] as? NSNumber)?.intValue ?? -1
    }
}
