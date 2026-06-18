import Foundation

public struct LocalTrustReceipt: Equatable, Sendable {
    public struct Row: Equatable, Sendable, Identifiable {
        public let id: String
        public let title: String
        public let detail: String
        public let systemImage: String

        public init(id: String, title: String, detail: String, systemImage: String) {
            self.id = id
            self.title = title
            self.detail = detail
            self.systemImage = systemImage
        }
    }

    /// Optional trailing call-to-action rendered as a `Link` under the rows
    /// (e.g. a Plaid scope/deletion deep link). Kept as data, not view-embedded,
    /// so the URL stays Sendable and unit-testable.
    public struct DeepLink: Equatable, Sendable {
        public let title: String
        public let urlString: String
        public let systemImage: String

        public init(title: String, urlString: String, systemImage: String) {
            self.title = title
            self.urlString = urlString
            self.systemImage = systemImage
        }
    }

    public let title: String
    public let subtitle: String
    public let rows: [Row]
    public let footer: String
    public let deepLink: DeepLink?

    public init(
        title: String,
        subtitle: String,
        rows: [Row],
        footer: String,
        deepLink: DeepLink? = nil
    ) {
        self.title = title
        self.subtitle = subtitle
        self.rows = rows
        self.footer = footer
        self.deepLink = deepLink
    }

    public static func settingsReceipt(storagePath: String) -> LocalTrustReceipt {
        let trimmedStoragePath = storagePath.trimmingCharacters(in: .whitespacesAndNewlines)
        let displayStoragePath = trimmedStoragePath.isEmpty ? LocalDataStore.displayPath : trimmedStoragePath

        return LocalTrustReceipt(
            title: "Local Trust Receipt",
            subtitle: "VaultPeek keeps its control plane on this Mac.",
            rows: [
                Row(
                    id: "storage",
                    title: "Local storage",
                    detail: "Active data directory: \(displayStoragePath)",
                    systemImage: "externaldrive"
                ),
                Row(
                    id: "network",
                    title: "Network boundary",
                    detail: "No VaultPeek-hosted backend, analytics, telemetry, cloud sync, or cloud dashboard.",
                    systemImage: "network.slash"
                ),
                Row(
                    id: "plaid",
                    title: "Plaid access",
                    detail: "Plaid calls happen only when you choose sandbox or production mode; demo mode stays local.",
                    systemImage: "building.columns"
                ),
                Row(
                    id: "reset",
                    title: "Reset boundary",
                    detail: "Reset clears VaultPeek data caches and stored access-token entries when present, but preserves server.conf and app/server auth.",
                    systemImage: "arrow.counterclockwise"
                ),
            ],
            footer: "Reset does not revoke bank permissions or remove items from Plaid Dashboard; review those accounts separately when you want full revocation."
        )
    }

    /// "Where Your Data Lives" trust/transparency panel (AND-491). Names the
    /// SQLite store and Keychain explicitly, calls out the 127.0.0.1 loopback
    /// boundary as a dedicated row, and exposes a Plaid scope/deletion deep link.
    public static func whereYourDataLives(storagePath: String) -> LocalTrustReceipt {
        let trimmedStoragePath = storagePath.trimmingCharacters(in: .whitespacesAndNewlines)
        let displayStoragePath = trimmedStoragePath.isEmpty ? LocalDataStore.displayPath : trimmedStoragePath

        return LocalTrustReceipt(
            title: "Where Your Data Lives",
            subtitle: "Every byte VaultPeek stores stays on this Mac.",
            rows: [
                Row(
                    id: "sqlite",
                    title: "Local SQLite store",
                    detail: "Accounts, transactions, and sync cursors live in a local SQLite database at \(displayStoragePath).",
                    systemImage: "externaldrive"
                ),
                Row(
                    id: "keychain",
                    title: "macOS Keychain",
                    detail: "Plaid access tokens are stored as bytes in the macOS Keychain; SQLite holds only keychain:<item_id> references.",
                    systemImage: "key.fill"
                ),
                Row(
                    id: "loopback",
                    title: "Loopback boundary",
                    detail: "Network reaches only 127.0.0.1 — no VaultPeek backend, analytics, telemetry, or cloud sync. The local VaultPeek server is the only thing that talks to Plaid over HTTPS.",
                    systemImage: "network.slash"
                ),
                Row(
                    id: "plaid-scope",
                    title: "Plaid scope & deletion",
                    detail: "Bank connections are managed in your Plaid account; revoke or delete them there to fully cut off access.",
                    systemImage: "building.columns"
                ),
            ],
            footer: "VaultPeek never sends your financial data off this machine. Removing items from Plaid is a separate step you control.",
            deepLink: DeepLink(
                title: "Manage or delete data at Plaid",
                urlString: PlaidBarConstants.plaidDataDeletionURL,
                systemImage: "arrow.up.forward.square"
            )
        )
    }
}
