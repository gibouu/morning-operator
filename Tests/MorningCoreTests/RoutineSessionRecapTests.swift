import Foundation
import Testing
@testable import MorningCore

@Suite("Session recap, feedback and habit-reduction period")
struct RoutineSessionRecapTests {
    private let briefing = RoutineStep(title: "Briefing", kind: .briefing, durationMinutes: 3)
    private let messages = RoutineStep(title: "Messages", kind: .messages, durationMinutes: 5)
    private let chess = RoutineStep(title: "Chess", kind: .entertainment, durationMinutes: 8, isRequired: true)
    private let start = Date(timeIntervalSince1970: 1_000_000)
    private var end: Date { start.addingTimeInterval(7 * 86_400) }

    private var routine: RoutineVersion {
        RoutineVersion(sourceLabel: "Test", steps: [briefing, messages, chess], isApproved: true)
    }

    private func coded<Value: Codable>(_ value: Value) throws -> Value {
        try JSONDecoder().decode(Value.self, from: JSONEncoder().encode(value))
    }

    @Test("A finished run separates completed and skipped steps")
    func completedRun() throws {
        var session = RoutineSession(routine: routine)
        try session.start()
        try session.advance()
        try session.advance(skipping: true)
        try session.advance()
        let recap = RoutineSessionRecap(session: session, isPersisted: true)
        #expect(recap.ending == .completed)
        #expect(recap.completedSteps == [briefing, chess])
        #expect(recap.skippedSteps == [messages])
        #expect(recap.unfinishedSteps.isEmpty)
        #expect(recap.stoppedAtStepID == nil)
        #expect(recap.plannedMinutesCompleted == 11)
        #expect(recap.saveState == .saved)
        #expect(try coded(recap.ending) == .completed)
    }

    @Test("Active time leaves pauses out and ends at completion")
    func activeDurationExcludesPauses() throws {
        var session = RoutineSession(routine: routine)
        #expect(session.activeDuration(until: start) == nil)
        try session.start(at: start)
        try session.advance(at: start.addingTimeInterval(120))
        try session.pause(at: start.addingTimeInterval(180))
        try session.resume(at: start.addingTimeInterval(900))
        #expect(session.activeDuration(until: start.addingTimeInterval(960)) == 240)
        #expect(session.completedAt == nil)
        try session.advance(at: start.addingTimeInterval(1_000))
        try session.advance(at: start.addingTimeInterval(1_500))
        #expect(session.completedAt == start.addingTimeInterval(1_500))
        // 180 s before the pause, 600 s after it; later time does not count.
        #expect(session.activeDuration(until: start.addingTimeInterval(9_000)) == 780)
    }

    @Test("A stopped run has no completion time")
    func stoppedRunHasNoCompletion() throws {
        var session = RoutineSession(routine: routine)
        try session.start(at: start)
        try session.stop(at: start.addingTimeInterval(60))
        #expect(session.completedAt == nil)
        #expect(session.activeDuration(until: start.addingTimeInterval(600)) == 60)
    }

    @Test("Skipping a required ritual today leaves the routine and the preference journal as they were")
    func skipTodayDoesNotAlterStandingPreference() throws {
        var journal = RoutinePreferenceJournal()
        try journal.upsert(RoutinePreference(target: chess, presence: .keep))
        let journalBefore = journal
        let routineBefore = routine

        var session = RoutineSession(routine: routine)
        try session.start()
        try session.advance()
        try session.advance()
        try session.advance(skipping: true)
        let recap = RoutineSessionRecap(session: session, isPersisted: true)

        #expect(recap.skippedSteps == [chess])
        #expect(recap.skippedSteps.first?.isRequired == true)
        #expect(journal == journalBefore)
        #expect(journal.entry(targetID: chess.id)?.presence == .keep)
        #expect(session.routine.steps == routineBefore.steps)
        #expect(try journal.reconcile(steps: [briefing]).steps == [briefing, chess])
    }

    @Test("A run stopped while paused reports the paused step and the rest as unfinished")
    func stoppedWhilePaused() throws {
        var session = RoutineSession(routine: routine)
        try session.start()
        try session.advance()
        try session.pause()
        try session.stop()
        let recap = RoutineSessionRecap(session: session, isPersisted: true)
        #expect(recap.ending == .stoppedWhilePaused)
        #expect(recap.completedSteps == [briefing])
        #expect(recap.skippedSteps.isEmpty)
        #expect(recap.unfinishedSteps == [messages, chess])
        #expect(recap.stoppedAtStepID == messages.id)
    }

    @Test("A run stopped after resuming is a plain stop")
    func stoppedWhileRunning() throws {
        var session = RoutineSession(routine: routine)
        try session.start()
        try session.pause()
        try session.resume()
        try session.stop()
        let recap = RoutineSessionRecap(session: session, isPersisted: true)
        #expect(recap.ending == .stopped)
        #expect(recap.unfinishedSteps == [briefing, messages, chess])
        #expect(recap.stoppedAtStepID == briefing.id)
    }

    @Test("A session that never started reports every step as unfinished")
    func neverStarted() throws {
        let ready = RoutineSession(routine: routine)
        var dismissed = ready
        try dismissed.stop()
        for session in [ready, dismissed] {
            let recap = RoutineSessionRecap(session: session, isPersisted: false)
            #expect(recap.ending == .neverStarted)
            #expect(recap.completedSteps.isEmpty && recap.skippedSteps.isEmpty)
            #expect(recap.unfinishedSteps == [briefing, messages, chess])
            #expect(recap.stoppedAtStepID == nil)
            #expect(recap.plannedMinutesCompleted == 0)
        }
    }

    @Test("A run still in progress is not described as ended")
    func inProgress() throws {
        var session = RoutineSession(routine: routine)
        try session.start()
        try session.advance()
        #expect(RoutineSessionRecap(session: session, isPersisted: false).ending == .inProgress)
        try session.pause()
        let recap = RoutineSessionRecap(session: session, isPersisted: false)
        #expect(recap.ending == .inProgress)
        #expect(recap.unfinishedSteps == [messages, chess])
    }

    @Test("An unsaved change is never reported as saved")
    func unsavedIsNotReportedAsSaved() throws {
        var session = RoutineSession(routine: routine)
        try session.start()
        try session.stop()
        let unsaved = RoutineSessionRecap(session: session, isPersisted: false)
        #expect(unsaved.saveState == .notSaved)
        #expect(RoutineSessionRecap(session: session, isPersisted: true).saveState == .saved)
        #expect(try coded(unsaved.saveState) == .notSaved)
    }

    @Test("Saved and unsaved labels follow the primary device language")
    func persistenceLabelsStayDistinctInTheDeviceLanguage() {
        let saved = AppLanguage.isFrench ? "Enregistré" : "Saved"
        let notSaved = AppLanguage.isFrench ? "Non enregistré" : "Not saved"
        #expect(RoutineSessionRecapSaveState.saved.displayName == saved)
        #expect(RoutineSessionRecapSaveState.notSaved.displayName == notSaved)
    }

    @Test("Feedback is optional and is its own record")
    func feedbackDoesNotMutateRoutineOrJournal() throws {
        var journal = RoutinePreferenceJournal()
        try journal.upsert(RoutinePreference(target: chess, presence: .keep))
        let journalBefore = journal
        var session = RoutineSession(routine: routine)
        try session.start()
        try session.stop()
        let sessionBefore = session

        #expect(RoutineSessionFeedback(session: session) == nil)
        let feedback = try #require(RoutineSessionFeedback(session: session, wasEnjoyable: .no, at: start))
        #expect(feedback.sessionID == session.id)
        #expect(feedback.routineVersionID == session.routine.id)
        #expect(feedback.wasUseful == nil)
        #expect(feedback.wasEnjoyable == .no)
        #expect(try coded(feedback) == feedback)
        // A stored record with no answer is rejected, as the initializer would decline it.
        let empty = String(decoding: try JSONEncoder().encode(feedback), as: UTF8.self)
            .replacingOccurrences(of: "\"wasEnjoyable\":\"no\"", with: "\"wasEnjoyable\":null")
        #expect(empty.contains("null"))
        #expect(throws: DecodingError.self) {
            try JSONDecoder().decode(RoutineSessionFeedback.self, from: Data(empty.utf8))
        }
        #expect(session == sessionBefore)
        #expect(journal == journalBefore)
    }

    @Test("Adjusting, cancelling and expiring a goal leave the routine and journal untouched")
    func goalTransitionsLeaveRoutineUntouched() throws {
        let version = routine
        let routineBefore = version
        var journal = RoutinePreferenceJournal()
        try journal.upsert(RoutinePreference(target: chess, presence: .keep))
        let journalBefore = journal

        var goal = try HabitReductionGoal(activity: chess, target: .dailyMinutes(6),
            startDate: start, endDate: end, baseline: .userReported(dailyMinutes: 10))
        #expect(goal.activityStepID == chess.id && goal.activityKind == .entertainment)
        try goal.adjust(target: .dailyMinutes(7), endDate: end.addingTimeInterval(86_400))
        #expect(goal.target == .dailyMinutes(7))
        #expect(goal.startDate == start)
        #expect(goal.endDate == end.addingTimeInterval(86_400))
        #expect(try coded(goal) == goal)

        var cancelled = goal
        try cancelled.cancel()
        #expect(cancelled.state == .cancelled)
        #expect(throws: HabitReductionGoalError.notActive) { try cancelled.adjust(target: .noReduction) }
        #expect(throws: HabitReductionGoalError.notActive) { try cancelled.cancel() }
        let cancelledExpired = cancelled.expireIfDue(asOf: .distantFuture)
        #expect(!cancelledExpired)
        #expect(cancelled.state == .cancelled)

        let expiredOnLastDay = goal.expireIfDue(asOf: goal.endDate)
        #expect(!expiredOnLastDay)
        #expect(goal.state == .active)
        let expiredAfterEnd = goal.expireIfDue(asOf: goal.endDate.addingTimeInterval(1))
        #expect(expiredAfterEnd)
        #expect(goal.state == .expired)
        #expect(goal.status(on: start, recordedMinutes: 99) == .outsidePeriod)
        #expect(throws: HabitReductionGoalError.notActive) { try goal.adjust(target: .dailyMinutes(1)) }

        #expect(version == routineBefore)
        #expect(version.steps.contains(chess) && chess.isRequired)
        #expect(journal == journalBefore)
    }

    @Test("An invalid goal or adjustment is rejected and changes nothing")
    func invalidGoalIsRejected() throws {
        #expect(throws: HabitReductionGoalError.invalidGoal) {
            try HabitReductionGoal(activity: chess, target: .noReduction, startDate: end, endDate: start)
        }
        #expect(throws: HabitReductionGoalError.invalidGoal) {
            try HabitReductionGoal(activity: chess, target: .dailyMinutes(-1), startDate: start, endDate: end)
        }
        #expect(throws: HabitReductionGoalError.invalidGoal) {
            try HabitReductionGoal(activity: chess, target: .noReduction, startDate: start, endDate: end,
                                   baseline: .measured(dailyMinutes: 10, observedDays: 0))
        }
        var goal = try HabitReductionGoal(activity: chess, target: .dailyMinutes(6), startDate: start, endDate: end)
        let before = goal
        #expect(throws: HabitReductionGoalError.invalidGoal) {
            try goal.adjust(endDate: start.addingTimeInterval(-1))
        }
        #expect(goal == before)

        let stored = String(decoding: try JSONEncoder().encode(goal), as: UTF8.self)
            .replacingOccurrences(of: "\"dailyMinutes\":{\"_0\":6}", with: "\"dailyMinutes\":{\"_0\":5000}")
        #expect(stored.contains("5000"))
        #expect(throws: HabitReductionGoalError.invalidGoal) {
            try JSONDecoder().decode(HabitReductionGoal.self, from: Data(stored.utf8))
        }
    }

    @Test("A day above the target has a neutral status, and no reduction is a real choice")
    func dayStatusIsNeutral() throws {
        let goal = try HabitReductionGoal(activity: chess, target: .dailyMinutes(6), startDate: start, endDate: end)
        let day = start.addingTimeInterval(86_400)
        #expect(goal.status(on: day, recordedMinutes: 6) == .withinTarget)
        #expect(goal.status(on: day, recordedMinutes: 20) == .aboveTarget)
        #expect(goal.status(on: day, recordedMinutes: nil) == .notRecorded)
        #expect(goal.status(on: start.addingTimeInterval(-1), recordedMinutes: 20) == .outsidePeriod)
        #expect(goal.status(on: end.addingTimeInterval(1), recordedMinutes: 20) == .outsidePeriod)

        let unchanged = try HabitReductionGoal(activity: chess, target: .noReduction, startDate: start, endDate: end)
        #expect(unchanged.status(on: day, recordedMinutes: 500) == .noTarget)

        let punitive = ["fail", "miss", "streak", "broke", "bad", "should", "too much", "exceed"]
        for status in [HabitReductionDayStatus.noTarget, .outsidePeriod, .notRecorded, .withinTarget, .aboveTarget] {
            let text = status.displayName.lowercased()
            #expect(!text.isEmpty)
            for word in punitive { #expect(!text.contains(word), "\(status) uses \"\(word)\"") }
        }
    }

    @Test("An unknown or user-reported baseline is never presented as a measured number")
    func unknownBaselineHasNoMeasuredNumber() throws {
        let unknown = try HabitReductionGoal(activity: chess, target: .dailyMinutes(6), startDate: start, endDate: end)
        #expect(unknown.baseline == .unknown)
        #expect(unknown.baseline.measuredDailyMinutes == nil)
        #expect(unknown.baseline.userReportedDailyMinutes == nil)
        #expect(try coded(unknown).baseline == .unknown)
        let stored = String(decoding: try JSONEncoder().encode(unknown.baseline), as: UTF8.self)
        let storedHasDigit = stored.contains { $0.isNumber }
        #expect(!storedHasDigit)

        let reported = HabitBaseline.userReported(dailyMinutes: 40)
        #expect(reported.measuredDailyMinutes == nil)
        #expect(reported.userReportedDailyMinutes == 40)
        let measured = HabitBaseline.measured(dailyMinutes: 35, observedDays: 4)
        #expect(measured.measuredDailyMinutes == 35)
        #expect(measured.userReportedDailyMinutes == nil)
        #expect(try coded(measured) == measured)
    }
}
