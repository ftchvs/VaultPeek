import ArgumentParser
import CryptoKit
import FluentSQLiteDriver
import Foundation
import Hummingbird
import HummingbirdFluent
import Logging
import PlaidBarCore

@main
struct PlaidBarServer: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "plaidbar-server",
        abstract: "Run the local VaultPeek companion server.",
        version: PlaidBarConstants.appVersion
    )

    @Option(name: .long, help: "Server port")
    var port: Int?

    @Flag(name: .long, help: "Use Plaid sandbox environment")
    var sandbox = false

    @Option(name: .long, help: "Path to config file")
    var config: String?

    @Option(name: .long, help: "Exit when the process with this PID exits (used by app-managed launches)")
    var exitWithParent: Int32?

    func run() async throws {
        let logger = Logger(label: "com.ftchvs.plaidbar-server")

        if let parentPid = exitWithParent {
            startParentWatchdog(parentPid: parentPid, logger: logger)
        }

        let serverConfig = try ServerConfig.load(
            from: config,
            portOverride: port,
            sandboxOverride: sandbox ? true : nil
        )

        // Set up Fluent with SQLite
        try ServerConfig.preparePrivateSQLiteStoreForOpen(at: serverConfig.databasePath)
        let fluent = Fluent(logger: logger)
        fluent.databases.use(.sqlite(.file(serverConfig.databasePath)), as: .sqlite)

        // Register migrations
        await fluent.migrations.add(CreateItems())
        await fluent.migrations.add(AddProviderToItems())
        await fluent.migrations.add(AddOriginToItems())
        await fluent.migrations.add(CreateSyncCursors())
        await fluent.migrations.add(CreateCategoryBudgets())
        await fluent.migrations.add(CreateBillingSubscriptions())
        await fluent.migrations.add(CreateWebhookEvents())
        await fluent.migrations.add(CreateReviewState())
        try await fluent.migrate()
        try ServerConfig.enforcePrivateSQLiteStorePermissions(at: serverConfig.databasePath)

        let plaidClient = PlaidClient(config: serverConfig)
        let tokenStore = TokenStore(fluent: fluent, logger: logger)
        let budgetStore = BudgetStore(fluent: fluent)
        let reviewStateStore = ReviewStateStore(fluent: fluent)
        let billingStore = BillingSubscriptionStore(fluent: fluent)
        let webhookEventStore = WebhookEventStore(fluent: fluent)
        do {
            try await tokenStore.pruneOrphanedKeychainTokens()
        } catch {
            logger.warning(
                "Failed to prune orphaned Plaid Keychain tokens: \(String(describing: error))"
            )
        }
        let pendingLinkSessions = PendingLinkSessionStore(
            storageURL: URL(fileURLWithPath: serverConfig.pendingLinkSessionsPath)
        )
        let hostedLinkCompletions = HostedLinkCompletionStore()

        // Build router
        let router = Router()

        // Health check
        router.get("health") { _, _ -> HTTPResponse.Status in
            .ok
        }

        // API routes
        let api = router.group("api")
        api.add(middleware: APITokenMiddleware(authToken: serverConfig.authToken))
        // Entitlement seam: remains store-free and route-agnostic here. Managed
        // Link creation enforces plan limits in `LinkRoutes`, where billing and
        // item-count state are available, while BYO/local paths stay ungated.
        api.add(middleware: EntitlementMiddleware(deployment: serverConfig.deployment))
        api.add(middleware: SetupStateMiddleware(
            credentialDiagnosis: serverConfig.credentialDiagnosis,
            plaidEnvironment: serverConfig.plaidEnvironment
        ))
        LinkRoutes(
            plaidClient: plaidClient,
            tokenStore: tokenStore,
            pendingLinkSessions: pendingLinkSessions,
            billingStore: billingStore,
            config: serverConfig
        )
        .register(with: api)
        AccountRoutes(plaidClient: plaidClient, tokenStore: tokenStore)
            .register(with: api)
        InvestmentRoutes(plaidClient: plaidClient, tokenStore: tokenStore)
            .register(with: api)
        MerchantLogoRoutes(
            cacheDirectory: URL(fileURLWithPath: serverConfig.dataDirectoryPath, isDirectory: true)
                .appendingPathComponent("logo-cache", isDirectory: true)
        )
        .register(with: api)
        TransactionRoutes(plaidClient: plaidClient, tokenStore: tokenStore)
            .register(with: api)
        StatusRoutes(
            tokenStore: tokenStore,
            billingStore: billingStore,
            webhookEventStore: webhookEventStore,
            config: serverConfig
        )
            .register(with: api)
        BudgetRoutes(budgetStore: budgetStore)
            .register(with: api)
        // Opt-in server-synced review state (AND-552). The route is always wired,
        // but only an app that has enabled `ServerSyncedReviewFeatureFlag`
        // (default OFF) ever calls it, so the synced tables stay empty otherwise.
        ReviewRoutes(reviewStateStore: reviewStateStore)
            .register(with: api)
        BillingRoutes(
            billingStore: billingStore,
            tokenStore: tokenStore,
            deployment: serverConfig.deployment
        )
            .register(with: api)

        // OAuth callback (top-level, not under /api)
        OAuthCallbackRoute(
            plaidClient: plaidClient,
            tokenStore: tokenStore,
            pendingLinkSessions: pendingLinkSessions,
            hostedLinkCompletions: hostedLinkCompletions,
            entitlementService: ManagedLinkEntitlementService(
                deployment: serverConfig.deployment,
                billingStore: billingStore,
                tokenStore: tokenStore
            )
        )
        .register(with: router)
        WebhookRoutes(
            verifier: Self.webhookVerifier(config: serverConfig, logger: logger),
            tokenStore: tokenStore,
            eventStore: webhookEventStore
        )
        .register(with: router)
        HostedLinkWebhookRoute(hostedLinkCompletions: hostedLinkCompletions)
            .register(with: router)

        // Build and run application
        var app = Application(
            router: router,
            configuration: .init(
                address: .hostname("127.0.0.1", port: serverConfig.port)
            ),
            logger: logger
        )
        app.addServices(fluent)

        logger.info("VaultPeek companion server starting on http://127.0.0.1:\(serverConfig.port)")
        logger.info("Environment: \(serverConfig.plaidEnvironment.rawValue)")
        if let setupGuidance = serverConfig.credentialDiagnosis.setupGuidance(
            environment: serverConfig.plaidEnvironment
        ) {
            logger.warning(
                """
                Starting in setup state: \(setupGuidance) \
                /health and /api/status stay available; Plaid-backed routes return 503.
                """
            )
        }

        try await app.runService()
    }

    /// App-managed launches pass the app's PID so a crashed or force-killed
    /// app never leaves an orphaned server holding token access. Reparenting
    /// (getppid change) is the death signal: it cannot race PID reuse.
    private func startParentWatchdog(parentPid: Int32, logger: Logger) {
        Task.detached {
            while true {
                try? await Task.sleep(for: .seconds(2))
                if getppid() != parentPid {
                    logger.info("Parent app exited; shutting down app-managed server.")
                    kill(getpid(), SIGTERM)
                    break
                }
            }
        }
    }

    /// Selects the webhook JWT verifier (AND-646). GATED: by default
    /// (`webhookVerification.enabled == false`) this returns the exact same
    /// `StrictPlaidWebhookVerifier()` the server has always wired — its default
    /// `UnconfiguredPlaidWebhookSignatureValidator` always throws, so the
    /// receiver stays dormant and shipped behavior is byte-for-byte unchanged.
    /// The real ES256 validator is only constructed when the operator explicitly
    /// opts in; if the opt-in is present but supplies no parseable signing key,
    /// the validator is still wired but trusts no key (it rejects every
    /// delivery), so processing remains inert from the user's perspective.
    static func webhookVerifier(
        config: ServerConfig,
        logger: Logger
    ) -> any PlaidWebhookVerifier {
        guard config.webhookVerification.enabled else {
            return StrictPlaidWebhookVerifier()
        }
        let keySource = StaticPlaidWebhookKeySource(
            keysByID: pinnedWebhookKeys(config: config, logger: logger)
        )
        logger.info("Plaid webhook signature verification ENABLED (opt-in).")
        return StrictPlaidWebhookVerifier(
            signatureValidator: ES256PlaidWebhookSignatureValidator(keySource: keySource)
        )
    }

    /// Parses the optional operator-pinned signing key (JWK JSON) into a
    /// `kid`-indexed key set. Returns an empty set (verifier rejects everything)
    /// if absent or unparseable, never crashing the server boot.
    private static func pinnedWebhookKeys(
        config: ServerConfig,
        logger: Logger
    ) -> [String: P256.Signing.PublicKey] {
        guard let json = config.webhookVerification.signingKeyJWKJSON,
              let data = json.data(using: .utf8)
        else {
            logger.warning("Webhook verification enabled but no signing key configured; all deliveries will be rejected.")
            return [:]
        }
        do {
            let jwk = try JSONDecoder().decode(PlaidWebhookJWK.self, from: data)
            guard let kid = jwk.kid, !kid.isEmpty else {
                logger.warning("Configured webhook signing JWK has no `kid`; all deliveries will be rejected.")
                return [:]
            }
            return [kid: try jwk.publicKey()]
        } catch {
            logger.warning("Failed to parse configured webhook signing JWK: \(String(describing: error)); all deliveries will be rejected.")
            return [:]
        }
    }
}
