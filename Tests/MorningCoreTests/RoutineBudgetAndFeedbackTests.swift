import Foundation
import Testing
@testable import MorningCore

@Suite("Saved time budget, accepted longer plan and feedback")
struct RoutineBudgetAndFeedbackTests {
    private let briefing = RoutineStep(title: "Briefing", kind: .briefing, durationMinutes: 3)
    private let messages = RoutineStep(title: "Messages", kind: .messages, durationMinutes: 5)
    private let chess = RoutineStep(title: "Chess", kind: .entertainment, durationMinutes: 8, isRequired: true)

    private func routine(_ steps: [RoutineStep]) -> RoutineVersion {
        RoutineVersion(sourceLabel: "Test", steps: steps, isApproved: true)
    }
    private func decoded(_ json: String) throws -> RoutineBudgetAndFeedback {
        try JSONDecoder().decode(RoutineBudgetAndFeedback.self, from: Data(json.utf8))
    }

    @Test("No target is the default and produces no report")
    func noTargetIsTheDefault() {
        let state = RoutineBudgetAndFeedback()
        #expect(state.targetMinutes == nil)
        #expect(state.report(for: routine([briefing, messages, chess])) == nil)
        var withTarget = state
        withTarget.setTarget(10)
        #expect(withTarget.report(for: nil) == nil)
    }

    @Test("A target is held inside the offered range and can be removed")
    func targetIsBoundedAndRemovable() {
        var state = RoutineBudgetAndFeedback()
        state.setTarget(1)
        #expect(state.targetMinutes == 5)
        state.setTarget(10_000)
        #expect(state.targetMinutes == 240)
        state.setTarget(nil)
        #expect(state.targetMinutes == nil)
    }

    @Test("The first suggested target is one the current plan already fits")
    func suggestedTargetFitsThePlan() {
        #expect(RoutineBudgetAndFeedback.suggestedTargetMinutes(forPlannedMinutes: 19) == 20)
        #expect(RoutineBudgetAndFeedback.suggestedTargetMinutes(forPlannedMinutes: 20) == 20)
        #expect(RoutineBudgetAndFeedback.suggestedTargetMinutes(forPlannedMinutes: 0) == 5)
        #expect(RoutineBudgetAndFeedback.suggestedTargetMinutes(forPlannedMinutes: 100_000) == 240)
    }

    @Test("Accepting a longer plan quiets the note for that version, target and total only")
    func acceptanceLastsUntilTheRoutineChanges() throws {
        let version = routine([briefing, messages, chess])
        var state = RoutineBudgetAndFeedback()
        state.setTarget(10)
        let report = try #require(state.report(for: version))
        #expect(!state.hasAccepted(report))
        let accepted = state.acceptLongerPlan(report)
        #expect(accepted)
        #expect(state.hasAccepted(report))
        // Approving keeps the version, so the note stays quiet.
        #expect(state.hasAccepted(try #require(state.report(for: version.approved()))))

        // Any edit is a new version: the note returns, even with the same total.
        let reordered = version.revised(steps: [chess, messages, briefing])
        #expect(reordered.totalDurationMinutes == version.totalDurationMinutes)
        #expect(!state.hasAccepted(try #require(state.report(for: reordered))))
        var longer = messages
        longer.durationMinutes = 9
        #expect(!state.hasAccepted(try #require(state.report(for: version.revised(steps: [briefing, longer, chess])))))

        // A new target drops the acceptance; returning to the old target does not restore it.
        state.setTarget(15)
        #expect(state.acceptedLongerPlan == nil)
        state.setTarget(10)
        #expect(!state.hasAccepted(try #require(state.report(for: version))))
    }

    @Test("An acceptance does not survive a change of routine, even when the earlier routine is restored")
    func acceptanceEndsWhenTheRoutineChanges() throws {
        let version = routine([briefing, messages, chess])
        var state = RoutineBudgetAndFeedback()
        state.setTarget(10)
        state.acceptLongerPlan(try #require(state.report(for: version)))

        // Saved again with the same version, approved or not: kept.
        #expect(state.droppingAcceptance(unlessFor: version) == state)
        #expect(state.droppingAcceptance(unlessFor: version.approved()) == state)

        // Saved with an edited version, or with no routine: dropped, and only the acceptance.
        let edited = version.revised(steps: [chess, messages, briefing])
        let afterEdit = state.droppingAcceptance(unlessFor: edited)
        #expect(afterEdit.acceptedLongerPlan == nil)
        #expect(afterEdit.targetMinutes == 10)
        #expect(state.droppingAcceptance(unlessFor: nil).acceptedLongerPlan == nil)

        // Restoring the earlier routine afterwards brings the note back.
        let afterRestore = afterEdit.droppingAcceptance(unlessFor: version)
        #expect(!afterRestore.hasAccepted(try #require(afterRestore.report(for: version))))

        // With nothing accepted there is nothing to drop.
        let plain = RoutineBudgetAndFeedback()
        #expect(plain.droppingAcceptance(unlessFor: edited) == plain)
    }

    @Test("A plan that fits, or a report for another target, cannot be accepted")
    func acceptanceNeedsAnOverTargetReportForTheCurrentTarget() throws {
        let version = routine([briefing, messages, chess])
        var state = RoutineBudgetAndFeedback()
        state.setTarget(20)
        let fitting = state.acceptLongerPlan(try #require(state.report(for: version)))
        #expect(!fitting)
        #expect(state.acceptedLongerPlan == nil)
        #expect(RoutineTimeBudgetAcceptance(budget: RoutineTimeBudget(routine: version, targetMinutes: 20)) == nil)
        let otherTarget = state.acceptLongerPlan(RoutineTimeBudget(routine: version, targetMinutes: 10))
        #expect(!otherTarget)
        #expect(state.acceptedLongerPlan == nil)
        state.setTarget(nil)
        let withoutTarget = state.acceptLongerPlan(RoutineTimeBudget(routine: version, targetMinutes: 10))
        #expect(!withoutTarget)
        #expect(state.acceptedLongerPlan == nil)
    }

    @Test("Setting, accepting and answering never change the routine or the journal")
    func nothingHereTouchesTheRoutineOrTheJournal() throws {
        let version = routine([briefing, messages, chess])
        let before = version
        var journal = RoutinePreferenceJournal()
        try journal.upsert(RoutinePreference(target: messages, presence: .keep))
        let journalBefore = journal
        var state = RoutineBudgetAndFeedback()
        state.setTarget(5)
        let report = try #require(state.report(for: version, preferences: journal))
        #expect(report.fit == .requiredAloneOverTarget)
        state.acceptLongerPlan(report)
        var session = RoutineSession(routine: version)
        try session.start()
        try session.advance(skipping: true)
        try session.stop()
        state.setFeedback(for: session, wasUseful: .no, wasEnjoyable: nil)
        #expect(version == before)
        #expect(session.routine == before)
        #expect(journal == journalBefore)
    }

    @Test("Feedback is stored only with an answer, one record per run")
    func feedbackNeedsAnAnswer() throws {
        var session = RoutineSession(routine: routine([briefing]))
        try session.start()
        try session.advance()
        var state = RoutineBudgetAndFeedback()
        state.setFeedback(for: session, wasUseful: nil, wasEnjoyable: nil)
        #expect(state.feedback.isEmpty)
        #expect(state.feedback(forSessionID: session.id) == nil)

        state.setFeedback(for: session, wasUseful: .yes, wasEnjoyable: nil)
        let first = try #require(state.feedback(forSessionID: session.id))
        #expect(first.wasUseful == .yes)
        #expect(first.wasEnjoyable == nil)
        state.setFeedback(for: session, wasUseful: .yes, wasEnjoyable: .somewhat)
        #expect(state.feedback.count == 1)
        let second = try #require(state.feedback(forSessionID: session.id))
        #expect(second.id == first.id)
        #expect(second.wasEnjoyable == .somewhat)

        // Clearing both answers removes the record; nothing is left behind.
        state.setFeedback(for: session, wasUseful: nil, wasEnjoyable: nil)
        #expect(state.feedback.isEmpty)
    }

    @Test("The saved form round-trips")
    func roundTrip() throws {
        let version = routine([briefing, messages, chess])
        var session = RoutineSession(routine: version)
        try session.start()
        try session.stop()
        var state = RoutineBudgetAndFeedback()
        state.setTarget(10)
        state.acceptLongerPlan(try #require(state.report(for: version)))
        state.setFeedback(for: session, wasUseful: .somewhat, wasEnjoyable: .no,
                          at: Date(timeIntervalSince1970: 1_800_000_000))
        let copy = try JSONDecoder().decode(RoutineBudgetAndFeedback.self, from: JSONEncoder().encode(state))
        #expect(copy == state)
        #expect(copy.hasAccepted(try #require(copy.report(for: version))))
        let empty = try JSONDecoder().decode(RoutineBudgetAndFeedback.self,
                                             from: JSONEncoder().encode(RoutineBudgetAndFeedback()))
        #expect(empty == RoutineBudgetAndFeedback())
    }

    @Test("A damaged part is left out and the rest is kept; reading never fails")
    func damagedPartsAreLeftOut() throws {
        #expect(try decoded("{}") == RoutineBudgetAndFeedback())
        #expect(try decoded("\"not an object\"") == RoutineBudgetAndFeedback())
        #expect(try decoded("[1, 2]") == RoutineBudgetAndFeedback())
        #expect(try decoded(#"{"targetMinutes": "soon"}"#).targetMinutes == nil)
        #expect(try decoded(#"{"targetMinutes": 0}"#).targetMinutes == nil)
        #expect(try decoded(#"{"targetMinutes": -30}"#).targetMinutes == nil)
        #expect(try decoded(#"{"targetMinutes": 100000}"#).targetMinutes == nil)
        #expect(try decoded(#"{"targetMinutes": 25, "feedback": "none"}"#).targetMinutes == 25)

        let session = UUID(), version = UUID()
        let good = #"{"id":"\#(UUID())","sessionID":"\#(session)","routineVersionID":"\#(version)","wasUseful":"yes","recordedAt":0}"#
        let unanswered = #"{"id":"\#(UUID())","sessionID":"\#(UUID())","routineVersionID":"\#(version)","recordedAt":0}"#
        let duplicate = #"{"id":"\#(UUID())","sessionID":"\#(session)","routineVersionID":"\#(version)","wasEnjoyable":"no","recordedAt":1}"#
        let state = try decoded(#"{"targetMinutes": 30, "feedback": [\#(good), 7, \#(unanswered), \#(duplicate)]}"#)
        #expect(state.targetMinutes == 30)
        #expect(state.feedback.count == 1)
        #expect(state.feedback(forSessionID: session)?.wasUseful == .yes)

        // An acceptance for a target that is no longer the saved one is not restored.
        let stale = #"{"targetMinutes": 30, "acceptedLongerPlan": {"routineVersionID":"\#(version)","targetMinutes":10,"totalMinutes":16}}"#
        #expect(try decoded(stale).acceptedLongerPlan == nil)
        let orphan = #"{"acceptedLongerPlan": {"routineVersionID":"\#(version)","targetMinutes":10,"totalMinutes":16}}"#
        #expect(try decoded(orphan).acceptedLongerPlan == nil)
        let broken = #"{"targetMinutes": 10, "acceptedLongerPlan": {"routineVersionID": 4}}"#
        #expect(try decoded(broken).targetMinutes == 10)
        #expect(try decoded(broken).acceptedLongerPlan == nil)
    }
}

@Suite("Routine duration target: kept choices matched by title")
struct RoutineTimeBudgetKeepMatchingTests {
    private func routine(_ steps: [RoutineStep]) -> RoutineVersion {
        RoutineVersion(sourceLabel: "Test", steps: steps, isApproved: true)
    }

    @Test("A keep saved for an earlier identity protects the single step with its category and title")
    func keepMatchedByTitleProtectsTheStep() throws {
        let saved = RoutineStep(title: "Chess", kind: .entertainment, durationMinutes: 8)
        let relearned = RoutineStep(title: "  chess ", kind: .entertainment, durationMinutes: 8)
        let other = RoutineStep(title: "Messages", kind: .messages, durationMinutes: 5)
        var journal = RoutinePreferenceJournal()
        try journal.upsert(RoutinePreference(target: saved, presence: .keep))
        #expect(try journal.matchingPreference(for: relearned)?.targetID == saved.id)
        let budget = RoutineTimeBudget(routine: routine([other, relearned]), targetMinutes: 5, preferences: journal)
        #expect(budget.requiredStepIDs == [relearned.id])
        #expect(budget.requiredMinutes == 8)
        #expect(budget.fit == .requiredAloneOverTarget)
    }

    @Test("A title match never reaches a second step, another category, or a step with its own choice")
    func titleMatchStaysConservative() throws {
        let saved = RoutineStep(title: "Chess", kind: .entertainment, durationMinutes: 8)
        var journal = RoutinePreferenceJournal()
        try journal.upsert(RoutinePreference(target: saved, presence: .keep))

        // Two steps share the title: the journal cannot tell which one, so neither is protected.
        let first = RoutineStep(title: "Chess", kind: .entertainment, durationMinutes: 4)
        let second = RoutineStep(title: "Chess", kind: .entertainment, durationMinutes: 6)
        #expect(RoutineTimeBudget(routine: routine([first, second]), targetMinutes: 5,
                                  preferences: journal).requiredStepIDs.isEmpty)

        // The kept step itself is present: its namesake is not protected as well.
        let both = RoutineTimeBudget(routine: routine([first, saved]), targetMinutes: 5, preferences: journal)
        #expect(both.requiredStepIDs == [saved.id])

        // Another category is another activity.
        let custom = RoutineStep(title: "Chess", kind: .custom, durationMinutes: 4)
        #expect(RoutineTimeBudget(routine: routine([custom]), targetMinutes: 5,
                                  preferences: journal).requiredStepIDs.isEmpty)

        // A step with its own timing-only choice keeps that choice; the keep does not move onto it.
        try journal.upsert(RoutinePreference(target: first, durationMinutes: 4))
        #expect(RoutineTimeBudget(routine: routine([first]), targetMinutes: 5,
                                  preferences: journal).requiredStepIDs.isEmpty)
    }

    @Test("A keep reaches its step by title although another choice shares that title")
    func keepIsResolvedPerChoiceAsTheJournalDoes() throws {
        // A's choice keeps its identity after A is renamed; B's keep then reaches the new C by title.
        let a = RoutineStep(title: "Chess", kind: .entertainment, durationMinutes: 2)
        let b = RoutineStep(title: "Chess", kind: .entertainment, durationMinutes: 8)
        var journal = RoutinePreferenceJournal()
        try journal.upsert(RoutinePreference(target: a, durationMinutes: 2))
        try journal.upsert(RoutinePreference(target: b, presence: .keep))
        var renamed = a
        renamed.title = "Other"
        let c = RoutineStep(title: "Chess", kind: .entertainment, durationMinutes: 8)
        let steps = [renamed, c]
        // The journal applies B's keep to C without refusing.
        #expect(try journal.reconcile(steps: steps).retainedStepIDs == [b.id])
        let budget = RoutineTimeBudget(routine: routine(steps), targetMinutes: 5, preferences: journal)
        #expect(budget.requiredStepIDs == [c.id])
        #expect(budget.requiredMinutes == 8)
        #expect(budget.fit == .requiredAloneOverTarget)
    }

    @Test("Where the journal refuses two choices for one step, the budget protects nothing")
    func conflictingChoicesProtectNothing() throws {
        let saved = RoutineStep(title: "Chess", kind: .entertainment, durationMinutes: 8)
        let current = RoutineStep(title: "Chess", kind: .entertainment, durationMinutes: 4)
        var journal = RoutinePreferenceJournal()
        try journal.upsert(RoutinePreference(target: saved, presence: .keep))
        try journal.upsert(RoutinePreference(target: current, durationMinutes: 4))
        #expect(throws: RoutinePreferenceError.conflictingMatch(current.id)) { try journal.reconcile(steps: [current]) }
        #expect(RoutineTimeBudget(routine: routine([current]), targetMinutes: 2,
                                  preferences: journal).requiredStepIDs.isEmpty)

        // Two keeps for the same title cannot both belong to the one step that has it.
        let other = RoutineStep(title: "chess", kind: .entertainment, durationMinutes: 6)
        var twoKeeps = RoutinePreferenceJournal()
        try twoKeeps.upsert(RoutinePreference(target: saved, presence: .keep))
        try twoKeeps.upsert(RoutinePreference(target: other, presence: .keep))
        let fresh = RoutineStep(title: "Chess", kind: .entertainment, durationMinutes: 5)
        #expect(throws: RoutinePreferenceError.self) { try twoKeeps.reconcile(steps: [fresh]) }
        #expect(RoutineTimeBudget(routine: routine([fresh]), targetMinutes: 2,
                                  preferences: twoKeeps).requiredStepIDs.isEmpty)
    }

    @Test("Exclusions and timing-only choices matched by title protect nothing")
    func onlyKeepProtects() throws {
        let excluded = RoutineStep(title: "News", kind: .briefing, durationMinutes: 6)
        let timed = RoutineStep(title: "Stretch", kind: .wellbeing, durationMinutes: 4)
        var journal = RoutinePreferenceJournal()
        try journal.upsert(RoutinePreference(target: excluded, presence: .exclude))
        try journal.upsert(RoutinePreference(target: timed, durationMinutes: 4))
        let steps = [RoutineStep(title: "News", kind: .briefing, durationMinutes: 6),
                     RoutineStep(title: "Stretch", kind: .wellbeing, durationMinutes: 4)]
        let before = journal
        let budget = RoutineTimeBudget(routine: routine(steps), targetMinutes: 5, preferences: journal)
        #expect(budget.requiredStepIDs.isEmpty)
        #expect(budget.fit == .overTarget)
        #expect(journal == before)
    }
}
