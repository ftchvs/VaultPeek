import Foundation
import SwiftData

public extension TransactionCacheStore {
    /// Opens the disposable on-disk per-transaction cache under `directory` (the
    /// local private data dir). Throwing initializer: AppState wraps construction
    /// in `try?` so a SwiftData failure leaves the app on its existing in-memory
    /// rendering path.
    init(onDiskIn directory: URL, fileManager: FileManager = .default) throws {
        let container = try TransactionCacheStore.makeOnDiskContainer(in: directory, fileManager: fileManager)
        self.init(modelContainer: container)
    }

    /// Opens an in-memory store (tests and non-persisting fallback).
    init(inMemory: Bool) throws {
        precondition(inMemory, "Use init(onDiskIn:) for the persistent store")
        let container = try TransactionCacheStore.makeInMemoryContainer()
        self.init(modelContainer: container)
    }
}
