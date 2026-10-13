import Foundation

public enum RoutineSessionEnding: String, Codable, Sendable {
    case completed, stopped, stoppedWhilePaused
    /// Ready, or stopped before any start: nothing ran.
    case neverStarted
    case inProgress
}

public enum RoutineSessionRecapSaveState: String, Codable, Sendable {
    case saved, notSaved
    public var displayName: String {
        switch self {
        case .saved: "Saved"
        case .notSaved: "Not saved"
        }
    }
}

/// What happened in one run, derived only from the session's pinned routine and recorded
/// events. It reads today's run; it changes neither the routine nor standing preferences.
/// Store the session, not the recap: a recap is rebuilt from it and is not decodable.
public struct RoutineSessionRecap: Sendable, Equatable {
    public let sessionID: UUID
    public let routineVersionID: UUID
    public let ending: RoutineSessionEnding
    /// Each list is in routine order. Every pinned step is in exactly one list.
    public let completedSteps: [RoutineStep]
    public let skippedSteps: [RoutineStep]
    public let unfinishedSteps: [RoutineStep]
    /// The step that was current when the run was stopped, if it had started.
    public let stoppedAtStepID: UUID?
    public let saveState: RoutineSessionRecapSaveState

    /// `isPersisted` is the caller's confirmed storage result for this run and any change
    /// made with it. The recap cannot observe storage, so it never assumes a save.
    public init(session: RoutineSession, isPersisted: Bool) {
        let started = session.events.contains { $0.kind == .started }
        let completed = Set(session.completedStepIDs)
        let skipped = Set(session.skippedStepIDs)
        let steps = session.routine.steps
        sessionID = session.id
        routineVersionID = session.routine.id
        completedSteps = steps.filter { completed.contains($0.id) }
        skippedSteps = steps.filter { !completed.contains($0.id) && skipped.contains($0.id) }
        unfinishedSteps = steps.filter { !completed.contains($0.id) && !skipped.contains($0.id) }
        saveState = isPersisted ? .saved : .notSaved
        switch session.status {
        case .completed: ending = .completed
        case .ready: ending = .neverStarted
        case .running, .paused: ending = .inProgress
        case .stopped:
            if !started { ending = .neverStarted }
            else if session.events.dropLast().last?.kind == .paused { ending = .stoppedWhilePaused }
            else { ending = .stopped }
        }
        stoppedAtStepID = started ? session.events.last { $0.kind == .stopped }?.stepID : nil
    }

    public var plannedMinutesCompleted: Int { completedSteps.reduce(0) { $0 + $1.durationMinutes } }
}

public enum RoutineFeedbackAnswer: String, Codable, CaseIterable, Sendable {
    case yes, somewhat, no
}

/// Optional feedback the person chose to give about one run. It is its own record:
/// creating or storing it changes neither the routine nor the preference journal.
/// A later reviewed proposal may read it; nothing is adapted from it automatically.
public struct RoutineSessionFeedback: Codable, Sendable, Equatable, Identifiable {
    public let id: UUID
    public let sessionID: UUID
    public let routineVersionID: UUID
    public let wasUseful: RoutineFeedbackAnswer?
    public let wasEnjoyable: RoutineFeedbackAnswer?
    public let recordedAt: Date

    /// Nil when the person answered neither question: declining leaves no record.
    public init?(id: UUID = UUID(), session: RoutineSession, wasUseful: RoutineFeedbackAnswer? = nil,
                 wasEnjoyable: RoutineFeedbackAnswer? = nil, at date: Date = Date()) {
        guard wasUseful != nil || wasEnjoyable != nil else { return nil }
        self.id = id; sessionID = session.id; routineVersionID = session.routine.id
        self.wasUseful = wasUseful; self.wasEnjoyable = wasEnjoyable; recordedAt = date
    }

    private enum CodingKeys: String, CodingKey {
        case id, sessionID, routineVersionID, wasUseful, wasEnjoyable, recordedAt
    }
    public init(from decoder: any Decoder) throws {
        let values = try decoder.container(keyedBy: CodingKeys.self)
        id = try values.decode(UUID.self, forKey: .id)
        sessionID = try values.decode(UUID.self, forKey: .sessionID)
        routineVersionID = try values.decode(UUID.self, forKey: .routineVersionID)
        wasUseful = try values.decodeIfPresent(RoutineFeedbackAnswer.self, forKey: .wasUseful)
        wasEnjoyable = try values.decodeIfPresent(RoutineFeedbackAnswer.self, forKey: .wasEnjoyable)
        recordedAt = try values.decode(Date.self, forKey: .recordedAt)
        guard wasUseful != nil || wasEnjoyable != nil else {
            throw DecodingError.dataCorrupted(.init(codingPath: decoder.codingPath,
                debugDescription: "A feedback record needs at least one answer."))
        }
    }
}

/// Where a habit's starting level comes from. Only a measured baseline carries a
/// measured number; an unknown baseline carries no number at all.
public enum HabitBaseline: Codable, Sendable, Equatable {
    case measured(dailyMinutes: Int, observedDays: Int)
    case userReported(dailyMinutes: Int)
    case unknown

    public var measuredDailyMinutes: Int? {
        if case .measured(let minutes, _) = self { return minutes }
        return nil
    }
    public var userReportedDailyMinutes: Int? {
        if case .userReported(let minutes) = self { return minutes }
        return nil
    }
}

public enum HabitReductionTarget: Codable, Sendable, Equatable {
    /// The person prefers the habit as it is.
    case noReduction
    case dailyMinutes(Int)
}

public enum HabitReductionGoalState: String, Codable, Sendable { case active, cancelled, expired }

public enum HabitReductionGoalError: Error, LocalizedError, Equatable, Sendable {
    case invalidGoal, notActive
    public var errorDescription: String? {
        switch self {
        case .invalidGoal: "Choose an activity, an end on or after the start, and a daily target between 0 minutes and 24 hours."
        case .notActive: "This period has ended or was cancelled. Start a new one to change it."
        }
    }
}

/// Neutral description of one day. No score, streak or count of days is kept.
public enum HabitReductionDayStatus: String, Codable, Sendable {
    case noTarget, outsidePeriod, notRecorded, withinTarget, aboveTarget
    public var displayName: String {
        switch self {
        case .noTarget: "No target chosen"
        case .outsidePeriod: "Outside the chosen period"
        case .notRecorded: "Nothing recorded for this day"
        case .withinTarget: "Within the target you chose"
        case .aboveTarget: "Above the target you chose"
        }
    }
}

/// An optional, explicit preference about one activity over a chosen period. It holds
/// only the activity's identity, so adjusting, cancelling or expiring it cannot change
/// the routine, a required ritual or the preference journal. It enforces nothing.
public struct HabitReductionGoal: Codable, Sendable, Equatable, Identifiable {
    public let id: UUID
    public let activityStepID: UUID
    public let activityTitle: String
    public let activityKind: StepKind
    public let baseline: HabitBaseline
    public private(set) var target: HabitReductionTarget
    public private(set) var startDate: Date
    public private(set) var endDate: Date
    public private(set) var state: HabitReductionGoalState

    public init(id: UUID = UUID(), activity: RoutineStep, target: HabitReductionTarget,
                startDate: Date, endDate: Date, baseline: HabitBaseline = .unknown) throws {
        self.id = id; activityStepID = activity.id; activityTitle = activity.title
        activityKind = activity.kind; self.baseline = baseline; self.target = target
        self.startDate = startDate; self.endDate = endDate; state = .active
        try validate()
    }

    public func validate() throws {
        let day = 0...1_440
        var valid = !activityTitle.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty && startDate <= endDate
        if case .dailyMinutes(let minutes) = target { valid = valid && day.contains(minutes) }
        switch baseline {
        case .measured(let minutes, let days): valid = valid && day.contains(minutes) && days >= 1
        case .userReported(let minutes): valid = valid && day.contains(minutes)
        case .unknown: break
        }
        guard valid else { throw HabitReductionGoalError.invalidGoal }
    }

    /// Nil keeps the current value. A rejected adjustment leaves the goal as it was.
    public mutating func adjust(target: HabitReductionTarget? = nil, startDate: Date? = nil,
                                endDate: Date? = nil) throws {
        guard state == .active else { throw HabitReductionGoalError.notActive }
        var next = self
        if let target { next.target = target }
        if let startDate { next.startDate = startDate }
        if let endDate { next.endDate = endDate }
        try next.validate()
        self = next
    }

    public mutating func cancel() throws {
        guard state == .active else { throw HabitReductionGoalError.notActive }
        state = .cancelled
    }

    /// Returns true when the period has passed and the goal became expired.
    @discardableResult
    public mutating func expireIfDue(asOf date: Date = Date()) -> Bool {
        guard state == .active, date > endDate else { return false }
        state = .expired
        return true
    }

    /// `recordedMinutes` is whatever the caller measured or the person reported for that
    /// day; nil means nothing was recorded, which is not the same as zero.
    public func status(on date: Date, recordedMinutes: Int?) -> HabitReductionDayStatus {
        guard state == .active, (startDate...endDate).contains(date) else { return .outsidePeriod }
        guard case .dailyMinutes(let targetMinutes) = target else { return .noTarget }
        guard let recordedMinutes else { return .notRecorded }
        return recordedMinutes <= targetMinutes ? .withinTarget : .aboveTarget
    }

    private enum CodingKeys: String, CodingKey {
        case id, activityStepID, activityTitle, activityKind, baseline, target, startDate, endDate, state
    }
    public init(from decoder: any Decoder) throws {
        let values = try decoder.container(keyedBy: CodingKeys.self)
        id = try values.decode(UUID.self, forKey: .id)
        activityStepID = try values.decode(UUID.self, forKey: .activityStepID)
        activityTitle = try values.decode(String.self, forKey: .activityTitle)
        activityKind = try values.decode(StepKind.self, forKey: .activityKind)
        baseline = try values.decode(HabitBaseline.self, forKey: .baseline)
        target = try values.decode(HabitReductionTarget.self, forKey: .target)
        startDate = try values.decode(Date.self, forKey: .startDate)
        endDate = try values.decode(Date.self, forKey: .endDate)
        state = try values.decode(HabitReductionGoalState.self, forKey: .state)
        try validate()
    }
}
