import Foundation
@testable import PlaidBarCore
import Testing

/// Tests for `CancellableTimeout` (codex #6): the cancellation-aware deadline race
/// the on-device Foundation Models seams use to bound a possibly-unbounded model
/// generation. The key guarantee — over the old `withTaskGroup` race — is that a
/// timeout returns PROMPTLY even when the losing operation ignores cancellation, so
/// it can never hang past the deadline.
@Suite("Cancellable Timeout Tests")
struct CancellableTimeoutTests {
    @Test("A fast operation returns its value before the deadline")
    func fastOperationReturnsValue() async {
        let result = await CancellableTimeout.run(nanoseconds: 2_000_000_000) {
            "ok"
        }
        #expect(result == "ok")
    }

    @Test("An operation slower than the deadline times out to nil")
    func slowOperationTimesOut() async {
        let result = await CancellableTimeout.run(nanoseconds: 20_000_000) { // 20ms
            try? await Task.sleep(nanoseconds: 5_000_000_000) // 5s
            return "late"
        }
        #expect(result == nil)
    }

    @Test("A cancellation-IGNORING operation still times out promptly (the core fix)")
    func cancellationIgnoringOperationStillTimesOut() async {
        // The exact failure the fix targets: the old `withTaskGroup` would await this
        // losing child at scope exit, so it could not return until the operation
        // finished — defeating the timeout. `CancellableTimeout` resumes on the
        // deadline WITHOUT awaiting the loser, so the call returns promptly while the
        // ignoring operation is still "running".
        let started = Date()
        let result = await CancellableTimeout.run(nanoseconds: 30_000_000) { // 30ms
            // Busy-ish wait that never checks cancellation, simulating a stuck
            // `session.respond`. Use a non-cancellable continuation sleep.
            await withCheckedContinuation { (cont: CheckedContinuation<Void, Never>) in
                Thread.sleep(forTimeInterval: 1.5) // 1.5s, ignores cancellation
                cont.resume()
            }
            return "ignored-cancellation"
        }
        let elapsed = Date().timeIntervalSince(started)

        #expect(result == nil)
        // Must return well before the operation's 1.5s — proving it did not await the
        // loser. Generous bound for CI jitter; the bug would make this ~1.5s.
        #expect(elapsed < 1.0)
    }

    @Test("Outer-task cancellation resolves the race to nil")
    func outerCancellationResolvesToNil() async {
        let task = Task {
            await CancellableTimeout.run(nanoseconds: 5_000_000_000) { // 5s deadline
                try? await Task.sleep(nanoseconds: 5_000_000_000)
                return "late"
            }
        }
        // Cancel almost immediately; the cancellation handler resolves to nil.
        task.cancel()
        let result = await task.value
        #expect(result == nil)
    }

    @Test("A nil-returning operation is distinguishable from a timeout only by timing")
    func nilResultIsPropagated() async {
        // A fast operation that yields nil propagates nil (the FM seams' failure
        // contract) — and returns immediately, unlike a timeout.
        let started = Date()
        let result: String? = await CancellableTimeout.run(nanoseconds: 5_000_000_000) {
            nil
        }
        let elapsed = Date().timeIntervalSince(started)
        #expect(result == nil)
        #expect(elapsed < 1.0) // returned promptly, not after the 5s deadline
    }
}
