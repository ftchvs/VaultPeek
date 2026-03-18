import ArgumentParser
import Foundation
import Hummingbird
import HummingbirdFluent
import FluentSQLiteDriver
import Logging

@main
struct PlaidBarServer: AsyncParsableCommand {
    @Option(name: .long, help: "Server port")
    var port: Int = 8484

    @Flag(name: .long, help: "Use Plaid sandbox environment")
    var sandbox: Bool = false

    @Option(name: .long, help: "Path to config file")
    var config: String?

    func run() async throws {
        let logger = Logger(label: "com.ftchvs.plaidbar-server")

        let serverConfig = try ServerConfig.load(
            from: config,
            portOverride: port,
            sandboxOverride: sandbox
        )

        // Set up Fluent with SQLite
        let fluent = Fluent(logger: logger)
        fluent.databases.use(.sqlite(.file(serverConfig.databasePath)), as: .sqlite)

        // Register migrations
        await fluent.migrations.add(CreateItems())
        await fluent.migrations.add(CreateSyncCursors())
        try await fluent.migrate()

        let plaidClient = PlaidClient(config: serverConfig)
        let tokenStore = TokenStore(fluent: fluent)

        // Build router
        let router = Router()

        // Health check
        router.get("health") { _, _ -> HTTPResponse.Status in
            .ok
        }

        // API routes
        LinkRoutes(plaidClient: plaidClient, tokenStore: tokenStore, config: serverConfig)
            .register(with: router.group("api"))
        AccountRoutes(plaidClient: plaidClient, tokenStore: tokenStore)
            .register(with: router.group("api"))
        TransactionRoutes(plaidClient: plaidClient, tokenStore: tokenStore)
            .register(with: router.group("api"))
        StatusRoutes(tokenStore: tokenStore, config: serverConfig)
            .register(with: router.group("api"))

        // OAuth callback (top-level, not under /api)
        OAuthCallbackRoute(plaidClient: plaidClient, tokenStore: tokenStore)
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

        logger.info("PlaidBar server starting on http://127.0.0.1:\(serverConfig.port)")
        logger.info("Environment: \(serverConfig.plaidEnvironment.rawValue)")

        try await app.runService()
    }
}
