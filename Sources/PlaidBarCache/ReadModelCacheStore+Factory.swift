import Foundation

public extension ReadModelCacheStore {
    /// Opens the disposable on-disk cache store under `directory` (the local
    /// private data dir). Throwing initializer: AppState wraps construction in
    /// `try?` so a store failure leaves the app on its existing cold path.
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
