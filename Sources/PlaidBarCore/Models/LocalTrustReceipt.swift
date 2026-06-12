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

    public let title: String
    public let subtitle: String
    public let rows: [Row]
    public let footer: String

    public init(
        title: String,
        subtitle: String,
        rows: [Row],
        footer: String
    ) {
        self.title = title
        self.subtitle = subtitle
        self.rows = rows
        self.footer = footer
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
}
