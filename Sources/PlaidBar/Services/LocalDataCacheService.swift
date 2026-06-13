import Foundation
import PlaidBarCore

actor LocalDataCacheService {
    func loadAccounts(
        from directory: URL,
        context: TransactionCacheContext?
    ) throws -> [AccountDTO] {
        try LocalDataStore.loadAccounts(from: directory, context: context)
    }

    func saveAccounts(
        _ accounts: [AccountDTO],
        to directory: URL,
        context: TransactionCacheContext?
    ) throws {
        try LocalDataStore.saveAccounts(accounts, to: directory, context: context)
    }

    func loadTransactions(
        from directory: URL,
        context: TransactionCacheContext?
    ) throws -> [TransactionDTO] {
        try LocalDataStore.loadTransactions(from: directory, context: context)
    }

    func saveTransactions(
        _ transactions: [TransactionDTO],
        to directory: URL,
        context: TransactionCacheContext?
    ) throws {
        try LocalDataStore.saveTransactions(transactions, to: directory, context: context)
    }

    func resetLocalData(at directory: URL) throws -> LocalDataResetResult {
        try LocalDataStore.resetLocalData(at: directory)
    }
}
