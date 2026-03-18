import Foundation
import PlaidBarCore

/// Handles syncing server data to local cache
@MainActor
final class SyncService {
    private let serverClient = ServerClient()

    /// Full sync: fetch accounts + transactions
    func performFullSync() async throws -> (accounts: [AccountDTO], transactions: [TransactionDTO]) {
        async let accounts = serverClient.getAccounts()
        async let syncResponse = serverClient.syncTransactions()

        let fetchedAccounts = try await accounts
        let response = try await syncResponse

        return (fetchedAccounts, response.added)
    }

    /// Incremental transaction sync
    func syncTransactions() async throws -> SyncResponse {
        try await serverClient.syncTransactions()
    }
}
