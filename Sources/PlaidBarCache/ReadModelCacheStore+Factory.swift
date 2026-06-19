import Foundation
import SwiftData

public extension ReadModelCacheStore {
    /// Opens the disposable on-disk cache store under `directory` (the local
    /// private data dir). Throwing initializer: AppState wraps construction in
    /// `try?` so a SwiftData failure leaves the app on its existing cold path.
    init(onDiskIn directory: URL, fileManager: FileManager = .default) throws {
        let container = try ReadModelCacheStore.makeOnDiskContainer(in: directory, fileManager: fileManager)
        self.init(modelContainer: container)
    }

    /// Opens an in-memory store (tests and non-persisting fallback).
    init(inMemory: Bool) throws {
        precondition(inMemory, "Use init(onDiskIn:) for the persistent store")
        let container = try ReadModelCacheStore.makeInMemoryContainer()
        self.init(modelContainer: container)
    }
}
