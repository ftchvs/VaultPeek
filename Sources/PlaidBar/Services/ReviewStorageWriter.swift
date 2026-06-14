import Foundation

/// Serializes transaction-review storage writes so the most recent in-memory
/// state always wins on disk.
///
/// Every review action (approve / ignore / rule edit / undo) hands the writer a
/// closure that persists a *complete* snapshot of the review metadata and rules.
/// A single consumer applies those closures strictly in the order they were
/// enqueued, so a slow earlier write can never land after a newer one and
/// resurrect stale JSON. Because each write carries the full state, rapid bursts
/// are coalesced to the newest snapshot — intermediate ones are dropped rather
/// than queued, which is both correct and cheaper than writing every keystroke.
///
/// `enqueue` is synchronous and `Sendable`, so it can be called directly from the
/// `@MainActor` without spawning an unstructured `Task` per action (the previous
/// approach, where independent tasks could finish out of order and race).
final class ReviewStorageWriter: Sendable {
    typealias Write = @Sendable () async -> Void

    private let continuation: AsyncStream<Write>.Continuation
    private let consumer: Task<Void, Never>

    init() {
        let (stream, continuation) = AsyncStream<Write>.makeStream(
            bufferingPolicy: .bufferingNewest(1)
        )
        self.continuation = continuation
        self.consumer = Task {
            for await write in stream {
                await write()
            }
        }
    }

    deinit {
        continuation.finish()
        consumer.cancel()
    }

    /// Enqueue a snapshot write. Returns immediately; the write runs on the serial
    /// consumer. If newer snapshots are enqueued before this one starts, it is
    /// superseded and skipped — the latest snapshot is what reaches disk.
    func enqueue(_ write: @escaping Write) {
        continuation.yield(write)
    }
}
