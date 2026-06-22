import Foundation

/// A cancellation-aware deadline race for bounding a potentially-unbounded `await`.
///
/// The on-device Foundation Models seams race a model generation against
/// `FMGenerationLimits.generationTimeout` so a stuck `session.respond` (model
/// warm-up, contention, a guardrail that ignores cancellation) can never block the
/// caller unbounded. A naive `withTaskGroup` race has a subtle hang: even after the
/// timeout child returns first, `withTaskGroup` still **awaits the remaining child
/// at scope exit**, so the group does not return until the (possibly
/// cancellation-ignoring) operation finishes — defeating the timeout.
///
/// This helper instead resolves a continuation as soon as *either* the operation or
/// the deadline completes and resumes immediately, WITHOUT awaiting the losing
/// task. The loser is cancelled (best-effort) but never awaited, so the deadline is
/// honored even when the operation ignores cancellation. `withTaskCancellationHandler`
/// propagates outer-task cancellation (e.g. a superseded categorization) into the
/// race so it resolves promptly too.
///
/// Pure, `Sendable`, and unit-tested here in `PlaidBarCore` so both FM seams and any
/// future bounded-`await` caller share one verified implementation. Mirrors the
/// private `LocalInsightModelRuntime.withTimeout`, generalized and made public.
public enum CancellableTimeout {
    /// Run `operation`, returning its result if it finishes within `nanoseconds`, or
    /// `nil` on timeout / outer-task cancellation. The losing task is cancelled but
    /// never awaited, so an operation that ignores cancellation cannot extend the
    /// deadline. The operation yields an optional and never throws, matching the FM
    /// seams' "swallow failures to nil" contract.
    public static func run<Value: Sendable>(
        nanoseconds: UInt64,
        operation: @escaping @Sendable () async -> Value?
    ) async -> Value? {
        let race = Race<Value>()

        return await withTaskCancellationHandler {
            await withCheckedContinuation { (continuation: CheckedContinuation<Value?, Never>) in
                let operationTask = Task {
                    let result = await operation()
                    race.complete(result)
                }
                let timeoutTask = Task {
                    do {
                        try await Task.sleep(nanoseconds: nanoseconds)
                        race.complete(nil) // deadline reached → degrade to fallback
                    } catch {
                        race.cancelTimeout() // race already resolved → stop waiting
                    }
                }
                race.start(
                    continuation: continuation,
                    operationTask: operationTask,
                    timeoutTask: timeoutTask
                )
            }
        } onCancel: {
            race.complete(nil)
        }
    }

    /// Lock-guarded single-resume coordinator for the operation/deadline race.
    /// Whichever side finishes first resumes the continuation and cancels the other;
    /// the loser is never awaited.
    private final class Race<Value: Sendable>: @unchecked Sendable {
        private let lock = NSLock()
        private var continuation: CheckedContinuation<Value?, Never>?
        private var operationTask: Task<Void, Never>?
        private var timeoutTask: Task<Void, Never>?
        private var completed = false
        /// Result stashed by `complete` when it wins before `start` has installed the
        /// continuation. Double-optional: the outer `.some` records "a result is
        /// pending", the inner optional is the actual `Value?` result.
        private var pendingResult: Value??

        func start(
            continuation: CheckedContinuation<Value?, Never>,
            operationTask: Task<Void, Never>,
            timeoutTask: Task<Void, Never>
        ) {
            lock.lock()
            if completed {
                // A task already finished before `start` ran; resume now with the
                // stashed result and cancel both tasks.
                let pending = pendingResult
                lock.unlock()
                operationTask.cancel()
                timeoutTask.cancel()
                continuation.resume(returning: pending ?? nil)
                return
            }
            self.continuation = continuation
            self.operationTask = operationTask
            self.timeoutTask = timeoutTask
            lock.unlock()
        }

        func complete(_ result: Value?) {
            lock.lock()
            guard !completed else {
                lock.unlock()
                return
            }
            completed = true
            let continuationToResume = continuation
            let operationToCancel = operationTask
            let timeoutToCancel = timeoutTask
            continuation = nil
            operationTask = nil
            timeoutTask = nil
            if continuationToResume == nil {
                // `start` hasn't run yet — stash the result for it to deliver.
                pendingResult = .some(result)
            }
            lock.unlock()

            operationToCancel?.cancel()
            timeoutToCancel?.cancel()
            continuationToResume?.resume(returning: result)
        }

        func cancelTimeout() {
            lock.lock()
            let timeoutToCancel = timeoutTask
            timeoutTask = nil
            lock.unlock()
            timeoutToCancel?.cancel()
        }
    }
}
