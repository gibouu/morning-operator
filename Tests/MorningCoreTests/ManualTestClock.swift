import Foundation

/// A clock that moves only when a test calls `advance(by:)`. A sleeper never
/// resumes because real time passed, so a busy machine cannot make a deadline fire.
///
/// A test that wants a deadline to fire first waits until the code under test is
/// asleep (`waitForSleepers`), then advances. Sleepers whose deadline is reached
/// are resumed in deadline order, ties in the order they fell asleep. A sleeper
/// that starts after `advance` returns counts its duration from the new time.
///
/// The same helper as `Tests/MorningAppleTests/ManualTestClock.swift`: the two test
/// targets share no code, so a change to one belongs in the other as well.
final class ManualTestClock: Clock, @unchecked Sendable {
    struct Instant: InstantProtocol {
        var offset: Duration = .zero
        func advanced(by duration: Duration) -> Instant { .init(offset: offset + duration) }
        func duration(to other: Instant) -> Duration { other.offset - offset }
        static func < (lhs: Instant, rhs: Instant) -> Bool { lhs.offset < rhs.offset }
    }

    private struct Sleeper {
        let id: UInt64
        let deadline: Instant
        let continuation: CheckedContinuation<Void, any Error>
    }
    private struct Watcher {
        let id: UInt64
        let count: Int
        let continuation: CheckedContinuation<Void, Never>
    }

    // Every field below is read and written only while `lock` is held.
    // Continuations are resumed after it is released.
    private let lock = NSLock()
    private var current = Instant()
    private var nextID: UInt64 = 0
    private var sleepers: [Sleeper] = []
    private var watchers: [Watcher] = []
    /// Sleeps and waits cancelled before their continuation was stored.
    private var cancelledEarly: Set<UInt64> = []

    var now: Instant { lock.withLock { current } }
    var minimumResolution: Duration { .zero }
    /// Sleeps that are waiting for the clock to reach their deadline.
    var sleeperCount: Int { lock.withLock { sleepers.count } }

    deinit {
        for sleeper in sleepers { sleeper.continuation.resume(throwing: CancellationError()) }
        for watcher in watchers { watcher.continuation.resume() }
    }

    func sleep(until deadline: Instant, tolerance: Duration? = nil) async throws {
        let id = lock.withLock { nextID += 1; return nextID }
        try await withTaskCancellationHandler {
            try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, any Error>) in
                var satisfied: [Watcher] = []
                let outcome: Result<Void, any Error>? = lock.withLock {
                    if cancelledEarly.remove(id) != nil { return .failure(CancellationError()) }
                    if deadline <= current { return .success(()) }
                    sleepers.append(.init(id: id, deadline: deadline, continuation: continuation))
                    satisfied = watchers.filter { $0.count <= sleepers.count }
                    watchers.removeAll { $0.count <= sleepers.count }
                    return nil
                }
                if let outcome { continuation.resume(with: outcome) }
                for watcher in satisfied { watcher.continuation.resume() }
            }
        } onCancel: {
            let sleeper: Sleeper? = lock.withLock {
                guard let index = sleepers.firstIndex(where: { $0.id == id }) else {
                    // Either not stored yet (remember the cancellation) or already
                    // resumed by `advance` (the mark is never read again).
                    cancelledEarly.insert(id)
                    return nil
                }
                return sleepers.remove(at: index)
            }
            sleeper?.continuation.resume(throwing: CancellationError())
        }
    }

    /// Moves the clock forward and resumes every sleeper whose deadline is reached.
    func advance(by duration: Duration) {
        precondition(duration >= .zero, "A test clock never goes back.")
        let due: [Sleeper] = lock.withLock {
            current = current.advanced(by: duration)
            let due = sleepers.filter { $0.deadline <= current }
            sleepers.removeAll { $0.deadline <= current }
            // `sleepers` is in arrival order and the sort is stable for equal deadlines.
            return due.sorted { ($0.deadline, $0.id) < ($1.deadline, $1.id) }
        }
        for sleeper in due { sleeper.continuation.resume() }
    }

    /// Returns once at least `count` sleeps are waiting on this clock. It does not
    /// poll and does not use real time. It also returns when the calling task is
    /// cancelled, so a test time limit can end a wait that would never finish.
    func waitForSleepers(_ count: Int = 1) async {
        let id = lock.withLock { nextID += 1; return nextID }
        await withTaskCancellationHandler {
            await withCheckedContinuation { (continuation: CheckedContinuation<Void, Never>) in
                let ready: Bool = lock.withLock {
                    if cancelledEarly.remove(id) != nil || sleepers.count >= count { return true }
                    watchers.append(.init(id: id, count: count, continuation: continuation))
                    return false
                }
                if ready { continuation.resume() }
            }
        } onCancel: {
            let watcher: Watcher? = lock.withLock {
                guard let index = watchers.firstIndex(where: { $0.id == id }) else {
                    cancelledEarly.insert(id)
                    return nil
                }
                return watchers.remove(at: index)
            }
            watcher?.continuation.resume()
        }
    }
}
