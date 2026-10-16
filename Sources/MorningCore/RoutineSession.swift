import Foundation

public enum SessionStatus: String, Codable, Sendable {
    case ready, running, paused, completed, stopped
    public var displayName: String {
        switch self {
        case .ready: String(localized: "Ready", bundle: AppLanguage.bundle(for: .module), locale: AppLanguage.locale)
        case .running: String(localized: "In progress", bundle: AppLanguage.bundle(for: .module), locale: AppLanguage.locale)
        case .paused: String(localized: "Paused", bundle: AppLanguage.bundle(for: .module), locale: AppLanguage.locale)
        case .completed: String(localized: "Complete", bundle: AppLanguage.bundle(for: .module), locale: AppLanguage.locale)
        case .stopped: String(localized: "Stopped", bundle: AppLanguage.bundle(for: .module), locale: AppLanguage.locale)
        }
    }
}
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
        case .routineNeedsApproval: AppLanguage.localized("Review and approve this routine before starting.", bundle: .module)
        case .emptyRoutine: AppLanguage.localized("Add at least one step before starting your routine.", bundle: .module)
        case .invalidRoutine: AppLanguage.localized("Each routine step needs a unique identity, a title and a positive duration.", bundle: .module)
        case .invalidTransition: AppLanguage.localized("That command is not available in the current session state.", bundle: .module)
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
        if let refusal = Self.startRefusal(for: routine) { throw refusal }
        status = .running; events.append(SessionEvent(kind: .started, occurredAt: date))
    }
    /// Why this routine cannot be run, or nil. The same rule admits a start and a saved start.
    private static func startRefusal(for routine: RoutineVersion) -> SessionError? {
        guard routine.isApproved else { return .routineNeedsApproval }
        guard !routine.steps.isEmpty else { return .emptyRoutine }
        guard Set(routine.steps.map(\.id)).count == routine.steps.count,
              routine.steps.allSatisfy({ !$0.title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty && $0.durationMinutes > 0 })
        else { return .invalidRoutine }
        return nil
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

    private enum CodingKeys: String, CodingKey { case id, routine, status, currentStepIndex, events }

    /// A saved session is read only if the commands above could have recorded its events over
    /// its pinned routine, ending in its saved status and position. Every session this type has
    /// written passes. Anything else is damage and is refused here, so that progress, history,
    /// timing and the recap never report a step the routine does not hold, a step counted twice,
    /// or an ending that did not happen.
    public init(from decoder: any Decoder) throws {
        let values = try decoder.container(keyedBy: CodingKeys.self)
        id = try values.decode(UUID.self, forKey: .id)
        routine = try values.decode(RoutineVersion.self, forKey: .routine)
        status = try values.decode(SessionStatus.self, forKey: .status)
        currentStepIndex = try values.decode(Int.self, forKey: .currentStepIndex)
        events = try values.decode([SessionEvent].self, forKey: .events)
        guard let replayed = Self.replay(events, over: routine),
              replayed.status == status, replayed.index == currentStepIndex else {
            throw DecodingError.dataCorruptedError(forKey: .events, in: values,
                debugDescription: "The saved events do not describe a run of the pinned routine.")
        }
    }

    /// Where recording exactly these events leaves a new session, or nil when no sequence of
    /// commands records them. A start is admitted by the rule `start` applies: the pinned
    /// routine never changes, so a run that was started still satisfies it, and a saved run
    /// of an unapproved routine was never started by this type.
    private static func replay(_ events: [SessionEvent], over routine: RoutineVersion) -> (status: SessionStatus, index: Int)? {
        let steps = routine.steps
        var status = SessionStatus.ready
        var index = 0
        var current: UUID? { steps.indices.contains(index) ? steps[index].id : nil }
        // A command ID that already recorded a step records nothing more.
        var stepCommandIDs = Set<UUID>()
        // The last step and the end of the run are recorded by one command, at one instant.
        var lastStepRecordedAt: Date?
        for event in events {
            if let instant = lastStepRecordedAt {
                guard event.kind == .completed, event.stepID == nil, event.occurredAt == instant else { return nil }
                status = .completed; lastStepRecordedAt = nil
                continue
            }
            switch (event.kind, status) {
            case (.started, .ready):
                guard event.stepID == nil, startRefusal(for: routine) == nil else { return nil }
                status = .running
            case (.paused, .running):
                guard event.stepID == current else { return nil }
                status = .paused
            case (.resumed, .paused):
                guard event.stepID == current else { return nil }
                status = .running
            case (.stepCompleted, .running), (.stepSkipped, .running):
                guard let expected = current, event.stepID == expected,
                      stepCommandIDs.insert(event.id).inserted else { return nil }
                index += 1
                if index == steps.count { lastStepRecordedAt = event.occurredAt }
            case (.stopped, .ready), (.stopped, .running), (.stopped, .paused):
                guard event.stepID == current else { return nil }
                status = .stopped
            default: return nil
            }
        }
        return lastStepRecordedAt == nil ? (status, index) : nil
    }
}
