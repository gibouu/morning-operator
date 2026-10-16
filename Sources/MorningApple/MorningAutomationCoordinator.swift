import Foundation
import MorningCore
import Observation

/// Identity comes from the approved, pinned session, not a callback or elapsed timer.
public struct MorningExecutionID: Hashable, Sendable {
    public let sessionID: UUID
    public let routineVersionID: UUID
    public let stepID: UUID

    public init(sessionID: UUID, routineVersionID: UUID, stepID: UUID) {
        self.sessionID = sessionID
        self.routineVersionID = routineVersionID
        self.stepID = stepID
    }
}

public struct MorningStepContext: Equatable, Sendable {
    public let executionID: MorningExecutionID

    /// RoutineSession deduplicates commands within a run. Each pinned step has a unique ID.
    public var commandID: UUID { executionID.stepID }

    public init(executionID: MorningExecutionID) { self.executionID = executionID }
}

public enum MorningStepOutcome: Equatable, Sendable {
    /// The adapter actually finished its declared app-owned operation.
    case completed
    /// A real-world or interactive activity still needs the user's explicit continuation.
    case needsUser(String)
    /// The required permission, input or implementation is missing; no success is inferred.
    case unavailable(String)
}

/// Adapters must not interpret reading an instruction as completing its real-world action.
/// Cancellation must stop their own operation. A late return cannot advance the session.
@MainActor
public protocol MorningStepExecuting: AnyObject {
    func execute(step: RoutineStep, context: MorningStepContext) async throws -> MorningStepOutcome
    func cancel(context: MorningStepContext)
}

public enum MorningAutomationStatus: String, Sendable, Equatable {
    case idle, executing, waitingForUser, unavailable, failed, cancelled, completed
}

/// Executes one app-owned operation at a time. The store remains the owner of RoutineSession.
/// The store must cancel before a manual advance, pause, stop, or change of automatic mode.
/// Automatic advancement occurs only through onCompletion, never from a duration estimate.
@MainActor
@Observable
public final class MorningAutomationCoordinator {
    public private(set) var status: MorningAutomationStatus = .idle
    public private(set) var message = AppLanguage.localized("Ready when you start your approved routine.", bundle: .module)
    public private(set) var context: MorningStepContext?

    @ObservationIgnored private let executor: any MorningStepExecuting
    @ObservationIgnored private var task: Task<Void, Never>?
    @ObservationIgnored private var attemptID: UUID?
    @ObservationIgnored private var completed: Set<MorningExecutionID> = []
    @ObservationIgnored private var sessionID: UUID?

    public init(executor: any MorningStepExecuting) { self.executor = executor }

    deinit { task?.cancel() }

    /// Returns false for an unapproved/nonrunning session or a duplicate dispatch.
    /// After cancellation, the same interrupted step may be explicitly retried.
    @discardableResult
    public func runCurrentStep(
        in session: RoutineSession,
        onFailure: @escaping @MainActor (MorningStepContext, String) -> Void = { _, _ in },
        onCompletion: @escaping @MainActor (MorningStepContext) -> Void
    ) -> Bool {
        guard session.status == .running, session.routine.isApproved, let step = session.currentStep else {
            cancel()
            return false
        }
        let next = MorningStepContext(executionID: MorningExecutionID(
            sessionID: session.id, routineVersionID: session.routine.id, stepID: step.id
        ))
        if context == next { return false }
        cancel()
        if sessionID != session.id {
            completed.removeAll()
            sessionID = session.id
        }
        context = next
        guard !completed.contains(next.executionID) else {
            status = .completed
            message = AppLanguage.localized("This step has already finished in this run.", bundle: .module)
            return false
        }

        let attempt = UUID()
        attemptID = attempt
        status = .executing
        message = AppLanguage.localized("Working on \(step.title).", bundle: .module)
        let executor = self.executor
        task = Task { [weak self] in
            do {
                try Task.checkCancellation()
                let outcome = try await executor.execute(step: step, context: next)
                guard !Task.isCancelled, let self,
                      self.attemptID == attempt, self.context == next else { return }
                self.task = nil
                self.attemptID = nil
                switch outcome {
                case .completed:
                    // Record completion before reentering the store, which may immediately start the next step.
                    guard self.completed.insert(next.executionID).inserted else { return }
                    self.status = .completed
                    self.message = AppLanguage.localized("\(step.title) finished.", bundle: .module)
                    onCompletion(next)
                case .needsUser(let reason):
                    self.status = .waitingForUser
                    self.message = reason
                case .unavailable(let reason):
                    self.status = .unavailable
                    self.message = reason
                    onFailure(next, reason)
                }
            } catch {
                guard !Task.isCancelled, let self,
                      self.attemptID == attempt, self.context == next else { return }
                self.task = nil
                self.attemptID = nil
                if error is CancellationError {
                    self.status = .cancelled
                    self.message = AppLanguage.localized("This step stopped before completion. Continue when you are ready.", bundle: .module)
                } else {
                    self.status = .failed
                    self.message = AppLanguage.localized("This moment could not finish. You can retry or continue your morning.", bundle: .module)
                    onFailure(next, self.message)
                }
            }
        }
        return true
    }

    /// Invalidates the callback first, including when the adapter ignores Task cancellation.
    public func cancel() {
        let previous = context
        let wasExecuting = attemptID != nil
        attemptID = nil
        context = nil
        task?.cancel()
        task = nil
        if let previous, wasExecuting { executor.cancel(context: previous) }
        if previous != nil {
            status = .cancelled
            message = AppLanguage.localized("Automatic progression is stopped. Your current step is preserved.", bundle: .module)
        }
    }
}
