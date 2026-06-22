import Foundation
import Testing
@testable import PlaidBarCore

@Suite("Performance Trace")
struct PerformanceTraceTests {
    @Test("records coarse durations and counts only")
    func recordsCoarseDurationsAndCountsOnly() {
        let clock = ManualPerformanceClock(now: 1_000_000_000)
        var trace = PerformanceTrace(clock: { @Sendable in clock.now() })

        let sample = trace.measure(.dashboardRefresh) {
            clock.advance(byNanoseconds: 12_345_678)
            return 42
        }

        #expect(sample == 42)
        #expect(trace.events == [
            PerformanceEvent(
                operation: .dashboardRefresh,
                durationMilliseconds: 12,
                counts: [:],
                outcome: .success
            )
        ])
    }

    @Test("omits unsafe private values by construction")
    func omitsUnsafePrivateValuesByConstruction() throws {
        let clock = ManualPerformanceClock(now: 0)
        var trace = PerformanceTrace(clock: { @Sendable in clock.now() })

        trace.record(
            .transactionSync,
            durationNanoseconds: 3_900_000,
            counts: [
                .pageCount: 2,
                .transactionAddedCount: 5,
                .accountCount: 3,
            ],
            outcome: .success
        )

        let data = try JSONEncoder().encode(trace.snapshot())
        let encoded = try #require(String(data: data, encoding: .utf8))

        #expect(encoded.contains("transaction_sync"))
        #expect(encoded.contains("transaction_added_count"))
        #expect(!encoded.contains("account_id"))
        #expect(!encoded.contains("item_id"))
        #expect(!encoded.contains("transaction_id"))
        #expect(!encoded.contains("merchant"))
        #expect(!encoded.contains("balance"))
        #expect(!encoded.contains("access_token"))
        #expect(!encoded.contains("public_token"))
        #expect(!encoded.contains("/Users/example/private/server.conf"))
    }

    @Test("builds synthetic smoke snapshot")
    func buildsSyntheticSmokeSnapshot() {
        let snapshot = PerformanceTrace.demoSmokeSnapshot()

        #expect(snapshot.events.map(\.operation).contains(.dashboardRefresh))
        #expect(snapshot.events.map(\.operation).contains(.statusFetch))
        #expect(snapshot.events.map(\.operation).contains(.accountsRefresh))
        #expect(snapshot.events.map(\.operation).contains(.transactionSync))
        #expect(snapshot.events.allSatisfy { $0.durationMilliseconds >= 0 })
    }

    @Test("bounds retained events as a ring buffer")
    func boundsRetainedEventsAsRingBuffer() {
        var trace = PerformanceTrace(maximumEventCount: 3)

        trace.record(.statusFetch, durationNanoseconds: 1_000_000, outcome: .success)
        trace.record(.itemsFetch, durationNanoseconds: 2_000_000, outcome: .success)
        trace.record(.accountsRefresh, durationNanoseconds: 3_000_000, outcome: .success)
        trace.record(.transactionSync, durationNanoseconds: 4_000_000, outcome: .success)

        #expect(trace.events.map(\.operation) == [.itemsFetch, .accountsRefresh, .transactionSync])
    }
}

private final class ManualPerformanceClock: @unchecked Sendable {
    private var currentNanoseconds: UInt64

    init(now: UInt64) {
        currentNanoseconds = now
    }

    func now() -> UInt64 {
        currentNanoseconds
    }

    func advance(byNanoseconds nanoseconds: UInt64) {
        currentNanoseconds += nanoseconds
    }
}
