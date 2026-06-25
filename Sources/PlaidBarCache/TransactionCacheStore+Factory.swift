import Foundation

public extension TransactionCacheStore {
    /// Opens the disposable on-disk per-transaction cache under `directory` (the
    /// local private data dir). Opening performs **no** disk I/O: the (potentially
    /// large) backing file is read and decoded lazily on first access, so this never
    /// blocks the caller with a full-history decode (AND-656 finding 3). An
    /// incompatible/corrupt file is self-healed into a clean miss on that first read
    /// rather than disabling the cache.
    init(onDiskIn directory: URL, fileManager: FileManager = .default) {
        let storeURL = directory.appendingPathComponent(Self.storeFilename)
        self.init(storeURL: storeURL, fileManager: fileManager)
    }

    /// Opens an in-memory store (tests and non-persisting fallback).
    init(inMemory: Bool) {
        precondition(inMemory, "Use init(onDiskIn:) for the persistent store")
        self.init(storeURL: nil)
    }
}
