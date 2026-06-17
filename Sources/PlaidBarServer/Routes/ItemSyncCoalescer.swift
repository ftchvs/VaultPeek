/// Coalesces concurrent transaction syncs keyed by Plaid item id so only one
/// sync runs per item at a time. Concurrent callers for the same item await the
/// in-flight result instead of issuing a second overlapping `/transactions/sync`
/// pagination against Plaid (which races on the persisted cursor and can double
/// the work). Distinct items still run concurrently.
///
/// The companion server is a single local process, so an in-process actor fully
/// orders the per-item gate. The in-flight entry is cleared once the work
/// completes (success or failure), so the next sync re-runs normally.
actor ItemSyncCoalescer<Value: Sendable> {
    private var inFlight: [String: Task<Value, Error>] = [:]

    /// Runs `operation` for `itemId`, coalescing with any sync already in
    /// flight for the same item. The first caller starts the work; subsequent
    /// callers await the same task and observe its result (or error).
    func run(
        itemId: String,
        operation: @escaping @Sendable () async throws -> Value
    ) async throws -> Value {
        if let existing = inFlight[itemId] {
            return try await existing.value
        }

        let task = Task { try await operation() }
        inFlight[itemId] = task
        defer { inFlight[itemId] = nil }

        return try await task.value
    }
}
