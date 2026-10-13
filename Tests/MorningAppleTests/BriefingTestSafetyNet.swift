import Foundation
import Testing
@testable import MorningApple

/// A safety net for suites whose controllers sleep on a `ManualTestClock`.
///
/// With a clock that only a test can advance, no deadline ends a wait by itself.
/// A defect that leaves controller work waiting would then hang the whole run.
/// Use this trait together with `.timeLimit`: when the limit cancels a test, the
/// trait cancels the work of every controller that test made, and keeps cancelling
/// until the test function returns, because a cancelled test can go on and start
/// more controller work. Each pending `await` then returns and the test fails
/// instead of hanging. The trait does nothing in a test that finishes, so it never
/// decides the result of working code.
struct BriefingHangRescueTrait: SuiteTrait, TestTrait, TestScoping {
    let isRecursive = true

    func provideScope(for test: Test, testCase: Test.Case?,
                      performing function: @Sendable () async throws -> Void) async throws {
        let rescue = BriefingHangRescue()
        defer { rescue.stop() }
        try await BriefingHangRescue.$current.withValue(rescue) {
            try await withTaskCancellationHandler { try await function() } onCancel: { rescue.cancelControllerWorkUntilStopped() }
        }
    }
}

extension Trait where Self == BriefingHangRescueTrait {
    /// Cancels the work of the controllers a test made when that test is cancelled.
    static var endsControllerWorkOnCancellation: Self { .init() }
}

/// The controllers made by the running test.
final class BriefingHangRescue: @unchecked Sendable {
    @TaskLocal static var current: BriefingHangRescue?

    private let lock = NSLock()
    private var controllers: [MorningBriefingController] = []
    private var stopped = false

    func watch(_ controller: MorningBriefingController) -> MorningBriefingController {
        lock.withLock { controllers.append(controller) }
        return controller
    }

    /// Runs only after the test was cancelled, so its real-time pause is never
    /// part of a test that passes.
    func cancelControllerWorkUntilStopped() {
        Task { @MainActor in
            while true {
                let (all, stopped) = lock.withLock { (controllers, self.stopped) }
                if stopped { return }
                for controller in all { controller.cancelAndClear() }
                try? await Task.sleep(for: .milliseconds(20))
            }
        }
    }

    func stop() { lock.withLock { stopped = true } }
}

extension MorningBriefingController {
    /// Registers this controller with the running test's safety net, if there is one.
    func watchedForHangs() -> MorningBriefingController { BriefingHangRescue.current?.watch(self) ?? self }
}
