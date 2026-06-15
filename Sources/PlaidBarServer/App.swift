import ArgumentParser
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
        try await fluent.migrate()
        try ServerConfig.enforcePrivateSQLiteStorePermissions(at: serverConfig.databasePath)

        let plaidClient = PlaidClient(config: serverConfig)
        let tokenStore = TokenStore(fluent: fluent, logger: logger)
        let budgetStore = BudgetStore(fluent: fluent)
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
        BillingRoutes(billingStore: billingStore)
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
            verifier: StrictPlaidWebhookVerifier(),
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
}
