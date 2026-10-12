import Foundation
import MorningCore
import Testing
@testable import MorningApple

@Suite("App-owned morning execution")
@MainActor
struct MorningAutomationCoordinatorTests {
    @Test("Only confirmed adapter completion advances once with a stable command ID")
    func completionIsGatedAndDeduplicated() async throws {
        let executor = ControlledMorningExecutor()
        let coordinator = MorningAutomationCoordinator(executor: executor)
        let session = try runningSession()
        var completions: [MorningStepContext] = []
        #expect(coordinator.runCurrentStep(in: session) { completions.append($0) })
        #expect(!coordinator.runCurrentStep(in: session) { completions.append($0) })
        await waitFor { executor.invocations.count == 1 }
        #expect(completions.isEmpty)
        #expect(coordinator.status == .executing)
        executor.resolve(0, with: .success(.completed))
        await waitFor { completions.count == 1 }
        #expect(completions[0].commandID == session.currentStep?.id)
        #expect(completions[0].executionID.sessionID == session.id)
        #expect(completions[0].executionID.routineVersionID == session.routine.id)
        coordinator.cancel()
        #expect(!coordinator.runCurrentStep(in: session) { completions.append($0) })
        #expect(completions.count == 1)
        #expect(executor.invocations.count == 1)
    }

    @Test("Interactive work waits without claiming that speaking completed the activity")
    func interactiveWorkWaits() async throws {
        let executor = ControlledMorningExecutor()
        let coordinator = MorningAutomationCoordinator(executor: executor)
        let session = try runningSession(kind: .entertainment)
        var completions = 0
        coordinator.runCurrentStep(in: session) { _ in completions += 1 }
        await waitFor { executor.invocations.count == 1 }
        executor.resolve(0, with: .success(.needsUser("Play your chess game, then continue.")))
        await waitFor { coordinator.status == .waitingForUser }
        #expect(completions == 0)
        #expect(coordinator.message.contains("chess"))
        #expect(!coordinator.runCurrentStep(in: session) { _ in completions += 1 })
    }

    @Test("Missing adapters and execution errors do not advance")
    func missingAdapterAndErrorDoNotAdvance() async throws {
        let executor = ControlledMorningExecutor()
        let coordinator = MorningAutomationCoordinator(executor: executor)
        let session = try runningSession(kind: .messages)
        var completions = 0
        coordinator.runCurrentStep(in: session) { _ in completions += 1 }
        await waitFor { executor.invocations.count == 1 }
        executor.resolve(0, with: .success(.unavailable("No messaging adapter is connected.")))
        await waitFor { coordinator.status == .unavailable }
        #expect(completions == 0)
        coordinator.cancel()
        coordinator.runCurrentStep(in: session) { _ in completions += 1 }
        await waitFor { executor.invocations.count == 2 }
        executor.resolve(1, with: .failure(ExecutionFailure.failed))
        await waitFor { coordinator.status == .failed }
        #expect(completions == 0)
    }

    @Test("Cancelled work cannot complete a retried step even if its adapter returns late")
    func cancellationRejectsLateReturnFromSameStep() async throws {
        let executor = ControlledMorningExecutor()
        let coordinator = MorningAutomationCoordinator(executor: executor)
        let session = try runningSession()
        var completions = 0
        coordinator.runCurrentStep(in: session) { _ in completions += 1 }
        await waitFor { executor.invocations.count == 1 }
        coordinator.cancel()
        #expect(executor.cancelled.count == 1)
        coordinator.runCurrentStep(in: session) { _ in completions += 1 }
        await waitFor { executor.invocations.count == 2 }
        executor.resolve(0, with: .success(.completed))
        await settle()
        #expect(completions == 0)
        #expect(coordinator.status == .executing)
        executor.resolve(1, with: .success(.completed))
        await waitFor { completions == 1 }
    }

    @Test("Cancellation before task dispatch never invokes the adapter")
    func cancelledBeforeDispatchDoesNotExecute() async throws {
        let executor = ControlledMorningExecutor()
        let coordinator = MorningAutomationCoordinator(executor: executor)
        let session = try runningSession()
        coordinator.runCurrentStep(in: session) { _ in Issue.record("Cancelled work completed") }
        coordinator.cancel()
        await settle()
        #expect(executor.invocations.isEmpty)
        #expect(coordinator.status == .cancelled)
    }

    @Test("Manual advancement and a new run invalidate old completion callbacks")
    func replacedStepAndRunIgnoreOldCallbacks() async throws {
        let executor = ControlledMorningExecutor()
        let coordinator = MorningAutomationCoordinator(executor: executor)
        var session = try runningSession()
        var completions: [MorningStepContext] = []
        coordinator.runCurrentStep(in: session) { completions.append($0) }
        await waitFor { executor.invocations.count == 1 }
        try session.advance()
        coordinator.runCurrentStep(in: session) { completions.append($0) }
        await waitFor { executor.invocations.count == 2 }
        let newSession = try runningSession()
        coordinator.runCurrentStep(in: newSession) { completions.append($0) }
        await waitFor { executor.invocations.count == 3 }
        executor.resolve(0, with: .success(.completed))
        executor.resolve(1, with: .success(.completed))
        await settle()
        #expect(completions.isEmpty)
        executor.resolve(2, with: .success(.completed))
        await waitFor { completions.count == 1 }
        #expect(completions[0].executionID.sessionID == newSession.id)
        #expect(executor.cancelled.count == 2)
    }

    @Test("Unapproved, ready and paused sessions cannot dispatch automation")
    func sessionMustBeApprovedAndRunning() async throws {
        let executor = ControlledMorningExecutor()
        let coordinator = MorningAutomationCoordinator(executor: executor)
        let draft = RoutineSession(routine: DemoFixtures.candidateRoutine)
        #expect(!coordinator.runCurrentStep(in: draft) { _ in Issue.record("Draft completed") })
        let ready = RoutineSession(routine: DemoFixtures.routine)
        #expect(!coordinator.runCurrentStep(in: ready) { _ in Issue.record("Ready session completed") })
        var paused = try runningSession()
        try paused.pause()
        #expect(!coordinator.runCurrentStep(in: paused) { _ in Issue.record("Paused session completed") })
        await settle()
        #expect(executor.invocations.isEmpty)
    }

    @Test("Empty speech cannot report successful completion")
    func emptySpeechFailsWithoutPlayback() async {
        let speech = SpeechCoordinator()
        await #expect(throws: SpeechPlaybackError.emptyText) {
            try await speech.speakAndWait(" \n ")
        }
        #expect(speech.state == .idle)
        #expect(speech.lastError != nil)
    }

    @Test("A task cancelled before dispatch cannot begin speech")
    func alreadyCancelledSpeechDoesNotStart() async {
        let speech = SpeechCoordinator()
        let pending = Task { try await speech.speakAndWait("This must not be spoken.") }
        pending.cancel()
        await #expect(throws: CancellationError.self) { try await pending.value }
        #expect(speech.state == .idle)
    }

    private func runningSession(kind: StepKind = .briefing) throws -> RoutineSession {
        var session = RoutineSession(routine: RoutineVersion(sourceLabel: "Synthetic executor test", steps: [
            RoutineStep(title: "First", detail: "Synthetic text", kind: kind),
            RoutineStep(title: "Second", kind: .custom)
        ], isApproved: true))
        try session.start()
        return session
    }

    private func waitFor(_ condition: @MainActor () -> Bool) async {
        for _ in 0..<1_000 {
            if condition() { return }
            await Task.yield()
        }
        Issue.record("Expected asynchronous state did not arrive.")
    }

    private func settle() async {
        for _ in 0..<20 { await Task.yield() }
    }
}

private enum ExecutionFailure: Error { case failed }

/// Intentionally does not resume on cancellation, to exercise late-return protection.
@MainActor
private final class ControlledMorningExecutor: MorningStepExecuting {
    struct Invocation {
        let context: MorningStepContext
        var continuation: CheckedContinuation<MorningStepOutcome, any Error>?
    }
    var invocations: [Invocation] = []
    var cancelled: [MorningStepContext] = []

    func execute(step: RoutineStep, context: MorningStepContext) async throws -> MorningStepOutcome {
        try await withCheckedThrowingContinuation { continuation in
            invocations.append(Invocation(context: context, continuation: continuation))
        }
    }

    func cancel(context: MorningStepContext) { cancelled.append(context) }

    func resolve(_ index: Int, with result: Result<MorningStepOutcome, any Error>) {
        let continuation = invocations[index].continuation
        invocations[index].continuation = nil
        continuation?.resume(with: result)
    }
}
