import Foundation
import MorningCore

/// The time budget, the recap and the optional feedback (#10). Everything here reads the
/// routine; nothing here writes it. A target, an accepted longer plan and an answer are
/// saved beside the routine and never remove, shorten or reorder a step, and never touch
/// the preference journal.
extension MorningStore {
    /// Nil while the person has no target, which is the default.
    var timeBudgetTargetMinutes: Int? { budgetAndFeedback.targetMinutes }

    /// The report for the current routine, or nil without a target or a routine.
    var timeBudget: RoutineTimeBudget? {
        budgetAndFeedback.report(for: routine, preferences: routinePreferences)
    }

    /// True while the person's acceptance of a longer plan still describes this routine
    /// version, target and total.
    var timeBudgetLongerPlanAccepted: Bool {
        timeBudget.map(budgetAndFeedback.hasAccepted) ?? false
    }

    var canChangeTimeBudget: Bool { storageIsAvailable && !busy && !sessionActive }

    /// A first target the current plan already fits.
    var suggestedTimeBudgetTargetMinutes: Int {
        RoutineBudgetAndFeedback.suggestedTargetMinutes(forPlannedMinutes: totalMinutes)
    }

    /// Nil removes the target. The value is kept only if it was saved.
    @discardableResult
    func setTimeBudgetTarget(_ minutes: Int?) -> Bool {
        changeBudgetAndFeedback { $0.setTarget(minutes) }
    }

    /// Records that the person keeps the current plan although it is longer than the target.
    @discardableResult
    func acceptLongerPlan() -> Bool {
        guard let report = timeBudget, report.fit != .withinTarget else { return false }
        return changeBudgetAndFeedback { $0.acceptLongerPlan(report) }
    }

    /// The run that just ended, while it is still the current one.
    var endedSession: RoutineSession? {
        guard let session, session.status == .completed || session.status == .stopped else { return nil }
        return session
    }

    /// Rebuilt from the session each time. "Saved" is the store's own save result for
    /// this run: the last successful write held this exact ending.
    func recap(for session: RoutineSession) -> RoutineSessionRecap {
        RoutineSessionRecap(session: session,
                            isPersisted: Self.ending(of: session).map(savedRunEndings.contains) ?? false)
    }

    func feedback(for session: RoutineSession) -> RoutineSessionFeedback? {
        budgetAndFeedback.feedback(forSessionID: session.id)
    }

    /// Stores the person's answers for one ended run. No answer stores nothing and removes
    /// an earlier record. The answers are kept only if they were saved.
    @discardableResult
    func answerFeedback(for session: RoutineSession, wasUseful: RoutineFeedbackAnswer?,
                        wasEnjoyable: RoutineFeedbackAnswer?) -> Bool {
        guard session.status == .completed || session.status == .stopped else { return false }
        return changeBudgetAndFeedback {
            $0.setFeedback(for: session, wasUseful: wasUseful, wasEnjoyable: wasEnjoyable)
        }
    }

    /// Runs the store's ordinary save again after a failed one.
    @discardableResult
    func retrySavingMorning() -> Bool { saveBudgetAndFeedback() }

    /// The ending event of every ended run held in memory: the saved history and the current
    /// run once it ended. An ending names one stop or one completion, so a run that shares
    /// an identity with an older record is not mistaken for it.
    var runEndingsInMemory: Set<UUID> {
        var endings = Set(history.runs.compactMap { Self.ending(of: $0.session) })
        if let endedSession, let ending = Self.ending(of: endedSession) { endings.insert(ending) }
        return endings
    }

    private static func ending(of session: RoutineSession) -> UUID? {
        guard session.status == .completed || session.status == .stopped else { return nil }
        return session.events.last?.id
    }

    private func changeBudgetAndFeedback(_ change: (inout RoutineBudgetAndFeedback) -> Void) -> Bool {
        guard storageIsAvailable else { return false }
        let old = budgetAndFeedback
        var next = old
        change(&next)
        guard next != old else { return true }
        budgetAndFeedback = next
        guard saveBudgetAndFeedback() else { budgetAndFeedback = old; return false }
        return true
    }
}
