import Foundation
import Testing
@testable import MorningCore

@Suite("Routine duration target")
struct RoutineTimeBudgetTests {
    private let briefing = RoutineStep(title: "Briefing", kind: .briefing, durationMinutes: 3)
    private let messages = RoutineStep(title: "Messages", kind: .messages, durationMinutes: 5)
    private let chess = RoutineStep(title: "Chess", kind: .entertainment, durationMinutes: 8, isRequired: true)

    private func routine(_ steps: [RoutineStep]) -> RoutineVersion {
        RoutineVersion(sourceLabel: "Test", steps: steps, isApproved: true)
    }

    @Test("A plan inside the target offers no choice and reports nothing over")
    func withinTarget() {
        let budget = RoutineTimeBudget(routine: routine([briefing, messages, chess]), targetMinutes: 16)
        #expect(budget.totalMinutes == 16)
        #expect(budget.requiredMinutes == 8)
        #expect(budget.optionalMinutes == 8)
        #expect(budget.minutesOverTarget == 0)
        #expect(budget.fit == .withinTarget)
        #expect(budget.choices.isEmpty)
    }

    @Test("A plan over the target reports the excess and offers edit or a longer plan")
    func overTargetOffersExplicitChoices() throws {
        let version = routine([briefing, messages, chess])
        let budget = RoutineTimeBudget(routine: version, targetMinutes: 10)
        #expect(budget.fit == .overTarget)
        #expect(budget.minutesOverTarget == 6)
        #expect(budget.requiredMinutesOverTarget == 0)
        #expect(budget.choices == [.editRoutine, .acceptLongerPlan])
        #expect(try JSONDecoder().decode([RoutineTimeBudgetChoice].self, from: JSONEncoder().encode(budget.choices)) == budget.choices)
        #expect(budget.longerPlanMinutes == version.totalDurationMinutes)
        #expect(budget.routineVersionID == version.id)
    }

    @Test("Required rituals alone exceeding the target is reported, not trimmed")
    func requiredAloneOverTargetIsReported() {
        let version = routine([briefing, messages, chess])
        let before = version
        let budget = RoutineTimeBudget(routine: version, targetMinutes: 5)
        #expect(budget.fit == .requiredAloneOverTarget)
        #expect(budget.requiredMinutes == 8)
        #expect(budget.requiredMinutesOverTarget == 3)
        #expect(budget.minutesOverTarget == 11)
        #expect(budget.requiredStepIDs == [chess.id])
        #expect(budget.choices == [.editRoutine, .acceptLongerPlan])
        // The longer plan is the whole routine, and the routine itself is untouched.
        #expect(budget.longerPlanMinutes == 16)
        #expect(version == before)
        #expect(version.steps.contains(chess))
    }

    @Test("A journal keep protects a step that is not marked required")
    func journalKeepCountsAsRequired() throws {
        var journal = RoutinePreferenceJournal()
        try journal.upsert(RoutinePreference(target: messages, presence: .keep))
        try journal.upsert(RoutinePreference(target: briefing, durationMinutes: 3))
        let revision = journal.revision
        let budget = RoutineTimeBudget(routine: routine([briefing, messages, chess]), targetMinutes: 10,
                                       preferences: journal)
        #expect(budget.requiredStepIDs == [messages.id, chess.id])
        #expect(budget.requiredMinutes == 13)
        #expect(budget.fit == .requiredAloneOverTarget)
        #expect(journal.revision == revision)
    }

    @Test("A target below one minute is raised to one, and an empty routine fits")
    func targetFloor() {
        let budget = RoutineTimeBudget(routine: routine([briefing]), targetMinutes: 0)
        #expect(budget.targetMinutes == 1)
        #expect(budget.minutesOverTarget == 2)
        #expect(RoutineTimeBudget(routine: routine([]), targetMinutes: 10).fit == .withinTarget)
    }
}
