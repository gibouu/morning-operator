import Foundation

/// The person's decision to keep a plan that is longer than their target. It names one
/// routine version, one target and one total, so it stops applying as soon as any of the
/// three changes. It records a decision; it never alters a step.
public struct RoutineTimeBudgetAcceptance: Codable, Sendable, Equatable {
    public let routineVersionID: UUID
    public let targetMinutes: Int
    public let totalMinutes: Int

    /// Nil when the plan fits: there is nothing longer to accept.
    public init?(budget: RoutineTimeBudget) {
        guard budget.fit != .withinTarget else { return nil }
        routineVersionID = budget.routineVersionID
        targetMinutes = budget.targetMinutes
        totalMinutes = budget.totalMinutes
    }

    public func covers(_ budget: RoutineTimeBudget) -> Bool {
        budget.fit != .withinTarget && routineVersionID == budget.routineVersionID
            && targetMinutes == budget.targetMinutes && totalMinutes == budget.totalMinutes
    }
}

/// What the workspace keeps for the time budget and the recap: an optional target length,
/// the longer plan the person accepted, and the feedback they chose to give. No target is
/// the default. Nothing here holds a step, so no change to it can remove, shorten or
/// reorder one, and none touches the preference journal.
public struct RoutineBudgetAndFeedback: Codable, Sendable, Equatable {
    /// The targets the editor offers. A saved value outside them is not read as a target.
    public static let targetMinutesRange = 5...240
    public static let targetMinutesStep = 5

    public private(set) var targetMinutes: Int?
    public private(set) var acceptedLongerPlan: RoutineTimeBudgetAcceptance?
    /// At most one record per run, oldest first.
    public private(set) var feedback: [RoutineSessionFeedback]

    public init() { targetMinutes = nil; acceptedLongerPlan = nil; feedback = [] }

    /// A first target that the current plan already fits: the plan's own length, raised to
    /// the next offered value, so that choosing to have a target never opens with a gap.
    public static func suggestedTargetMinutes(forPlannedMinutes planned: Int) -> Int {
        let step = targetMinutesStep
        let bounded = min(max(planned, targetMinutesRange.lowerBound), targetMinutesRange.upperBound)
        return min(targetMinutesRange.upperBound, (bounded + step - 1) / step * step)
    }

    /// Nil removes the target. A value outside the offered range becomes its nearest bound.
    /// An acceptance made for another target is dropped with it.
    public mutating func setTarget(_ minutes: Int?) {
        targetMinutes = minutes.map {
            min(max($0, Self.targetMinutesRange.lowerBound), Self.targetMinutesRange.upperBound)
        }
        if acceptedLongerPlan?.targetMinutes != targetMinutes { acceptedLongerPlan = nil }
    }

    /// Nil without a target or a routine: there is nothing to compare.
    public func report(for routine: RoutineVersion?,
                       preferences: RoutinePreferenceJournal = RoutinePreferenceJournal()) -> RoutineTimeBudget? {
        guard let targetMinutes, let routine else { return nil }
        return RoutineTimeBudget(routine: routine, targetMinutes: targetMinutes, preferences: preferences)
    }

    /// True while the person's acceptance still describes this exact report.
    public func hasAccepted(_ budget: RoutineTimeBudget) -> Bool {
        acceptedLongerPlan?.covers(budget) == true
    }

    /// Records the acceptance of this report's total. Returns false, changing nothing, when
    /// the report is not for the current target or the plan already fits.
    @discardableResult
    public mutating func acceptLongerPlan(_ budget: RoutineTimeBudget) -> Bool {
        guard budget.targetMinutes == targetMinutes,
              let acceptance = RoutineTimeBudgetAcceptance(budget: budget) else { return false }
        acceptedLongerPlan = acceptance
        return true
    }

    public func feedback(forSessionID id: UUID) -> RoutineSessionFeedback? {
        feedback.first { $0.sessionID == id }
    }

    /// Stores the person's answers for one run, replacing an earlier record for it.
    /// With no answer at all, nothing is stored and an earlier record is removed.
    public mutating func setFeedback(for session: RoutineSession, wasUseful: RoutineFeedbackAnswer?,
                                     wasEnjoyable: RoutineFeedbackAnswer?, at date: Date = Date()) {
        let existing = feedback.firstIndex { $0.sessionID == session.id }
        guard let record = RoutineSessionFeedback(id: existing.map { feedback[$0].id } ?? UUID(), session: session,
                                                  wasUseful: wasUseful, wasEnjoyable: wasEnjoyable, at: date) else {
            if let existing { feedback.remove(at: existing) }
            return
        }
        if let existing { feedback[existing] = record } else { feedback.append(record) }
    }

    private enum CodingKeys: String, CodingKey { case targetMinutes, acceptedLongerPlan, feedback }

    /// Reading never fails. These are optional notes beside the routine, so a damaged value
    /// here must not make the routine, its history or its saved choices unreadable: a part
    /// that cannot be read is left out, and the rest is kept.
    public init(from decoder: any Decoder) throws {
        self.init()
        guard let values = try? decoder.container(keyedBy: CodingKeys.self) else { return }
        if let minutes = try? values.decodeIfPresent(Int.self, forKey: .targetMinutes),
           Self.targetMinutesRange.contains(minutes) {
            targetMinutes = minutes
        }
        if let acceptance = try? values.decodeIfPresent(RoutineTimeBudgetAcceptance.self, forKey: .acceptedLongerPlan),
           acceptance.targetMinutes == targetMinutes {
            acceptedLongerPlan = acceptance
        }
        let records = (try? values.decodeIfPresent([Recoverable<RoutineSessionFeedback>].self, forKey: .feedback)) ?? []
        for record in records.compactMap(\.value) where feedback(forSessionID: record.sessionID) == nil {
            feedback.append(record)
        }
    }

    private struct Recoverable<Value: Decodable>: Decodable {
        let value: Value?
        init(from decoder: any Decoder) throws { value = try? Value(from: decoder) }
    }
}
