import Foundation

public enum PerformanceOperation: String, Codable, CaseIterable, Sendable {
    case dashboardRefresh = "dashboard_refresh"
    case statusFetch = "status_fetch"
    case itemsFetch = "items_fetch"
    case accountsRefresh = "accounts_refresh"
    case balancesRefresh = "balances_refresh"
    case transactionSync = "transaction_sync"
    case localCacheLoad = "local_cache_load"
    case localCacheSave = "local_cache_save"
    case derivedSummaryRecompute = "derived_summary_recompute"
}

public enum PerformanceCountKey: String, Codable, CaseIterable, Sendable {
    case accountCount = "account_count"
    case itemCount = "item_count"
    case pageCount = "page_count"
    case transactionAddedCount = "transaction_added_count"
    case transactionModifiedCount = "transaction_modified_count"
    case transactionRemovedCount = "transaction_removed_count"
    case transactionTotalCount = "transaction_total_count"
    case recurringCount = "recurring_count"
    case activitySummaryCount = "activity_summary_count"
    case cacheRecordCount = "cache_record_count"
}

public enum PerformanceOutcome: String, Codable, Sendable {
    case success
    case failure
    case skipped
}

public struct PerformanceEvent: Codable, Equatable, Sendable {
    public let operation: PerformanceOperation
    public let durationMilliseconds: UInt64
    public let counts: [PerformanceCountKey: Int]
    public let outcome: PerformanceOutcome

    public init(
        operation: PerformanceOperation,
        durationMilliseconds: UInt64,
        counts: [PerformanceCountKey: Int] = [:],
        outcome: PerformanceOutcome
    ) {
        self.operation = operation
        self.durationMilliseconds = durationMilliseconds
        self.counts = counts
        self.outcome = outcome
    }

    private enum CodingKeys: String, CodingKey {
        case operation
        case durationMilliseconds
        case counts
        case outcome
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        operation = try container.decode(PerformanceOperation.self, forKey: .operation)
        durationMilliseconds = try container.decode(UInt64.self, forKey: .durationMilliseconds)
        outcome = try container.decode(PerformanceOutcome.self, forKey: .outcome)

        let rawCounts = try container.decode([String: Int].self, forKey: .counts)
        counts = Dictionary(
            uniqueKeysWithValues: rawCounts.compactMap { key, value in
                guard let countKey = PerformanceCountKey(rawValue: key) else { return nil }
                return (countKey, value)
            }
        )
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(operation, forKey: .operation)
        try container.encode(durationMilliseconds, forKey: .durationMilliseconds)
        try container.encode(
            Dictionary(uniqueKeysWithValues: counts.map { ($0.key.rawValue, $0.value) }),
            forKey: .counts
        )
        try container.encode(outcome, forKey: .outcome)
    }
}

public struct PerformanceSnapshot: Codable, Equatable, Sendable {
    public let events: [PerformanceEvent]

    public init(events: [PerformanceEvent]) {
        self.events = events
    }
}

public struct PerformanceTrace: Sendable {
    public typealias Clock = @Sendable () -> UInt64

    private var clock: Clock
    private var recordedEvents: [PerformanceEvent]

    public init(clock: @escaping Clock = { DispatchTime.now().uptimeNanoseconds }) {
        self.clock = clock
        recordedEvents = []
    }

    public var events: [PerformanceEvent] {
        recordedEvents
    }

    public func snapshot() -> PerformanceSnapshot {
        PerformanceSnapshot(events: recordedEvents)
    }

    @discardableResult
    public mutating func measure<T>(
        _ operation: PerformanceOperation,
        counts: [PerformanceCountKey: Int] = [:],
        _ work: () throws -> T
    ) rethrows -> T {
        let start = clock()
        do {
            let result = try work()
            record(operation, durationNanoseconds: elapsedSince(start), counts: counts, outcome: .success)
            return result
        } catch {
            record(operation, durationNanoseconds: elapsedSince(start), counts: counts, outcome: .failure)
            throw error
        }
    }

    public mutating func record(
        _ operation: PerformanceOperation,
        durationNanoseconds: UInt64,
        counts: [PerformanceCountKey: Int] = [:],
        outcome: PerformanceOutcome
    ) {
        recordedEvents.append(
            PerformanceEvent(
                operation: operation,
                durationMilliseconds: durationNanoseconds / 1_000_000,
                counts: counts.filter { $0.value >= 0 },
                outcome: outcome
            )
        )
    }

    public mutating func clear() {
        recordedEvents.removeAll()
    }

    private func elapsedSince(_ start: UInt64) -> UInt64 {
        let end = clock()
        return end >= start ? end - start : 0
    }

    public static func demoSmokeSnapshot() -> PerformanceSnapshot {
        var trace = PerformanceTrace(clock: {
            0
        })
        trace.record(.dashboardRefresh, durationNanoseconds: 115_000_000, counts: [.accountCount: 3], outcome: .success)
        trace.record(.statusFetch, durationNanoseconds: 8_000_000, counts: [.itemCount: 2], outcome: .success)
        trace.record(.accountsRefresh, durationNanoseconds: 41_000_000, counts: [.accountCount: 3], outcome: .success)
        trace.record(
            .transactionSync,
            durationNanoseconds: 72_000_000,
            counts: [
                .pageCount: 2,
                .transactionAddedCount: 12,
                .transactionModifiedCount: 1,
                .transactionRemovedCount: 0,
                .transactionTotalCount: 220,
            ],
            outcome: .success
        )
        return trace.snapshot()
    }
}
