import Foundation

public enum SessionStatus: String, Codable, Sendable { case ready, running, paused, completed, stopped }
public enum SessionEventKind: String, Codable, Sendable { case started, paused, resumed, stepCompleted, stepSkipped, completed, stopped }
public struct SessionEvent: Codable, Sendable, Identifiable, Equatable {
    public let id: UUID
    public let kind: SessionEventKind
    public let stepID: UUID?
    public let occurredAt: Date
    public init(id: UUID = UUID(), kind: SessionEventKind, stepID: UUID? = nil, occurredAt: Date = Date()) {
        self.id = id; self.kind = kind; self.stepID = stepID; self.occurredAt = occurredAt
    }
}
public enum SessionError: Error, LocalizedError, Equatable, Sendable {
    case routineNeedsApproval, emptyRoutine, invalidRoutine, invalidTransition
    public var errorDescription: String? {
        switch self {
        case .routineNeedsApproval: String(localized: "Review and approve this routine before starting.", bundle: .module)
        case .emptyRoutine: String(localized: "Add at least one step before starting your routine.", bundle: .module)
        case .invalidRoutine: String(localized: "Each routine step needs a unique identity, a title and a positive duration.", bundle: .module)
        case .invalidTransition: String(localized: "That command is not available in the current session state.", bundle: .module)
        }
    }
}
/// A session pins an immutable snapshot of the approved routine version.
public struct RoutineSession: Codable, Sendable, Identifiable, Equatable {
    public let id: UUID
    public let routine: RoutineVersion
    public private(set) var status: SessionStatus
    public private(set) var currentStepIndex: Int
    public private(set) var events: [SessionEvent]
    public init(id: UUID = UUID(), routine: RoutineVersion) {
        self.id = id; self.routine = routine; status = .ready; currentStepIndex = 0; events = []
    }
    public var currentStep: RoutineStep? {
        guard status != .completed, status != .stopped, routine.steps.indices.contains(currentStepIndex) else { return nil }
        return routine.steps[currentStepIndex]
    }
    public var completedStepIDs: [UUID] { events.filter { $0.kind == .stepCompleted }.compactMap(\.stepID) }
    public var skippedStepIDs: [UUID] { events.filter { $0.kind == .stepSkipped }.compactMap(\.stepID) }
    public var progress: Double {
        guard !routine.steps.isEmpty else { return 0 }
        return Double(completedStepIDs.count + skippedStepIDs.count) / Double(routine.steps.count)
    }
    public mutating func start(at date: Date = Date()) throws {
        guard status == .ready else { throw SessionError.invalidTransition }
        guard routine.isApproved else { throw SessionError.routineNeedsApproval }
        guard !routine.steps.isEmpty else { throw SessionError.emptyRoutine }
        guard Set(routine.steps.map(\.id)).count == routine.steps.count,
              routine.steps.allSatisfy({ !$0.title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty && $0.durationMinutes > 0 })
        else { throw SessionError.invalidRoutine }
        status = .running; events.append(SessionEvent(kind: .started, occurredAt: date))
    }
    public mutating func pause(at date: Date = Date()) throws {
        guard status == .running else { throw SessionError.invalidTransition }
        status = .paused; events.append(SessionEvent(kind: .paused, stepID: currentStep?.id, occurredAt: date))
    }
    public mutating func resume(at date: Date = Date()) throws {
        guard status == .paused else { throw SessionError.invalidTransition }
        status = .running; events.append(SessionEvent(kind: .resumed, stepID: currentStep?.id, occurredAt: date))
    }
    /// Required rituals can still be explicitly skipped for today's run.
    public mutating func advance(skipping: Bool = false, commandID: UUID = UUID(), at date: Date = Date()) throws {
        // A transport may deliver the same recognized command twice. Reuse its ID to avoid skipping two steps.
        if events.contains(where: { $0.id == commandID && ($0.kind == .stepCompleted || $0.kind == .stepSkipped) }) { return }
        guard status == .running, let step = currentStep else { throw SessionError.invalidTransition }
        events.append(SessionEvent(id: commandID, kind: skipping ? .stepSkipped : .stepCompleted, stepID: step.id, occurredAt: date))
        currentStepIndex += 1
        if currentStepIndex == routine.steps.count { status = .completed; events.append(SessionEvent(kind: .completed, occurredAt: date)) }
    }
    public mutating func stop(at date: Date = Date()) throws {
        guard status == .ready || status == .running || status == .paused else { throw SessionError.invalidTransition }
        let stepID = currentStep?.id
        status = .stopped; events.append(SessionEvent(kind: .stopped, stepID: stepID, occurredAt: date))
    }
}
