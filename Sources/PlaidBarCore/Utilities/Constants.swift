import Foundation

public enum PlaidBarConstants {
    public static let defaultServerPort: Int = 8484
    public static let defaultServerHost: String = "127.0.0.1"

    public static var serverBaseURL: String {
        "http://\(defaultServerHost):\(defaultServerPort)"
    }

    // Refresh intervals
    public static let backgroundRefreshInterval: TimeInterval = 15 * 60  // 15 minutes
    public static let transactionSyncInterval: TimeInterval = 30 * 60    // 30 minutes

    // Display
    public static let creditUtilizationWarningThreshold: Double = 30.0
    public static let maxRecentTransactions: Int = 50
    public static let initialSyncDays: Int = 90

    // Keychain
    public static let keychainServiceName: String = "com.ftchvs.PlaidBar"
    public static let keychainServerTokenKey: String = "server-auth-token"

    // App Info
    public static let appVersion: String = "0.3.0"
    public static let appName: String = "PlaidBar"

    // Plaid
    public static let plaidSandboxClientId: String = "SANDBOX_CLIENT_ID"
    public static let plaidSandboxRedirectUri: String = "http://localhost:8484/oauth/callback"
}
