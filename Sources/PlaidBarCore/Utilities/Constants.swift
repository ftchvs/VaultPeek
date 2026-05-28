import Foundation

public enum PlaidBarConstants {
    public static let defaultServerPort: Int = 8484
    public static let defaultServerHost: String = "127.0.0.1"
    public static let serverPortEnvironmentVariable: String = "PLAIDBAR_SERVER_PORT"

    public static var serverBaseURL: String {
        serverBaseURL(environment: ProcessInfo.processInfo.environment)
    }

    public static var serverPort: Int {
        serverPort(environment: ProcessInfo.processInfo.environment)
    }

    public static func serverBaseURL(environment: [String: String]) -> String {
        "http://\(defaultServerHost):\(serverPort(environment: environment))"
    }

    public static func serverPort(environment: [String: String]) -> Int {
        guard let rawPort = environment[serverPortEnvironmentVariable]?.trimmedNonEmpty,
              let port = Int(rawPort),
              (1...65_535).contains(port) else {
            return defaultServerPort
        }
        return port
    }

    // Refresh intervals
    public static let backgroundRefreshInterval: TimeInterval = 15 * 60  // 15 minutes
    public static let transactionSyncInterval: TimeInterval = 30 * 60    // 30 minutes
    public static let minimumBackgroundRefreshInterval: TimeInterval = 5 * 60

    public static func normalizedBackgroundRefreshInterval(_ interval: TimeInterval) -> TimeInterval {
        guard interval.isFinite,
              interval >= minimumBackgroundRefreshInterval else {
            return backgroundRefreshInterval
        }
        return interval
    }

    // Display
    public static let creditUtilizationWarningThreshold: Double = 30.0
    public static let maxRecentTransactions: Int = 50
    public static let initialSyncDays: Int = 90
    public static let maxTransactionSyncPages: Int = 100

    // Keychain
    public static let keychainServiceName: String = "com.ftchvs.PlaidBar"
    public static let keychainServerTokenKey: String = "server-auth-token"

    // App Info
    public static let appVersion: String = "0.3.0"
    public static let appName: String = "PlaidBar"

    // Plaid
    public static var plaidSandboxRedirectUri: String {
        "http://localhost:\(serverPort)/oauth/callback"
    }
}

private extension String {
    var trimmedNonEmpty: String? {
        let value = trimmingCharacters(in: .whitespacesAndNewlines)
        return value.isEmpty ? nil : value
    }
}
