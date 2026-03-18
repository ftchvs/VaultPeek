import Foundation
import PlaidBarCore

struct ServerConfig: Sendable {
    let port: Int
    let plaidEnvironment: PlaidEnvironment
    let plaidClientId: String
    let plaidSecret: String
    let databasePath: String
    let redirectUri: String
    let authToken: String

    var plaidBaseURL: String {
        switch plaidEnvironment {
        case .sandbox: "https://sandbox.plaid.com"
        case .production: "https://production.plaid.com"
        }
    }

    static func load(
        from configPath: String? = nil,
        portOverride: Int? = nil,
        sandboxOverride: Bool? = nil
    ) throws -> ServerConfig {
        let dataDir = dataDirectory()
        try FileManager.default.createDirectory(
            atPath: dataDir,
            withIntermediateDirectories: true
        )

        let environment: PlaidEnvironment = (sandboxOverride == true)
            ? .sandbox
            : .production

        // Load credentials from environment variables
        let clientId = ProcessInfo.processInfo.environment["PLAID_CLIENT_ID"]
            ?? PlaidBarConstants.plaidSandboxClientId
        let secret = ProcessInfo.processInfo.environment["PLAID_SECRET"]
            ?? "sandbox_secret"

        // Generate or load persistent auth token for app<->server auth
        let authTokenPath = "\(dataDir)/auth-token"
        let authToken: String
        if let existing = try? String(contentsOfFile: authTokenPath, encoding: .utf8)
            .trimmingCharacters(in: .whitespacesAndNewlines),
            !existing.isEmpty
        {
            authToken = existing
        } else {
            let generated = UUID().uuidString
            try generated.write(toFile: authTokenPath, atomically: true, encoding: .utf8)
            authToken = generated
        }

        let resolvedPort = portOverride ?? PlaidBarConstants.defaultServerPort

        return ServerConfig(
            port: resolvedPort,
            plaidEnvironment: environment,
            plaidClientId: clientId,
            plaidSecret: secret,
            databasePath: "\(dataDir)/plaidbar.sqlite",
            redirectUri: "http://localhost:\(resolvedPort)/oauth/callback",
            authToken: authToken
        )
    }

    static func dataDirectory() -> String {
        let home = FileManager.default.homeDirectoryForCurrentUser.path
        return "\(home)/.plaidbar"
    }
}
