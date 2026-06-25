import Foundation

public extension BudgetingV2Store {
    /// Opens the opt-in v2 schema store under `directory` (the local private data
    /// dir). Throwing initializer: callers wrap construction in `try?` so a store
    /// failure leaves the app on v1 budgeting.
    init(onDiskIn directory: URL, fileManager: FileManager = .default) throws {
        let storeURL = directory.appendingPathComponent(Self.storeFilename)
        try self.init(storeURL: storeURL, fileManager: fileManager)
    }

    /// Opens an in-memory store (tests and non-persisting fallback).
    init(inMemory: Bool) throws {
        precondition(inMemory, "Use init(onDiskIn:) for the persistent store")
        try self.init(storeURL: nil)
    }
}
