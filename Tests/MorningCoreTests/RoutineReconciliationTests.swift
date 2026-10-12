import Foundation
import Testing
@testable import MorningCore

@Suite("Kept rituals survive inferred proposals")
struct RoutineReconciliationTests {
    @Test("Sample rituals do not become personal preferences when learning a real observation")
    func sampleRitualsStaySynthetic() {
        let candidate = RoutineVersion(sourceLabel: "Your observation", steps: [
            RoutineStep(title: "Water", kind: .wellbeing, durationMinutes: 1)
        ])
        let draft = RoutineVersion.inferredDraft(from: candidate, preserving: DemoFixtures.routine)
        #expect(draft.steps == candidate.steps)
        #expect(!draft.isApproved)
    }

    @Test("Missing kept ritual retains its complete user-owned value and requires fresh approval")
    func missingRitualSurvives() {
        let kept = ritual()
        let old = RoutineVersion(number: 4, sourceLabel: "Reviewed by you", steps: [kept], isApproved: true)
        let suggestion = RoutineStep(title: "Review messages", kind: .messages, durationMinutes: 2)
        let candidate = RoutineVersion(number: 99, sourceLabel: "New observation", steps: [suggestion], isApproved: true)
        let date = Date(timeIntervalSince1970: 123)
        let draft = RoutineVersion.inferredDraft(from: candidate, preserving: old, at: date)
        #expect(draft.steps == [suggestion, kept])
        #expect(draft.number == 5)
        #expect(draft.createdAt == date)
        #expect(draft.sourceLabel == candidate.sourceLabel)
        #expect(!draft.isApproved)
        #expect(draft.id != old.id && draft.id != candidate.id)
        #expect(old.steps == [kept] && old.isApproved)
    }

    @Test("A single normalized title and kind match keeps the ritual without duplication")
    func uniqueSemanticMatchPreservesCorrections() {
        let kept = ritual()
        let old = RoutineVersion(sourceLabel: "User choices", steps: [kept])
        let inferred = RoutineStep(title: "  TIME   FOR\nCHESS ", detail: "Model's new advice", kind: .entertainment,
            durationMinutes: 1, automation: .todayCalendar)
        let draft = RoutineVersion.inferredDraft(from: .init(sourceLabel: "Observation", steps: [inferred]), preserving: old)
        #expect(draft.steps == [kept])
        #expect(draft.steps[0].id != inferred.id)
    }

    @Test("Ambiguous suggested matches retain alternatives and the unchanged kept ritual")
    func ambiguousSuggestedRowsCannotOverwrite() {
        let kept = ritual()
        let alternatives = [
            RoutineStep(title: kept.title, detail: "First guess", kind: kept.kind, durationMinutes: 1, automation: .todayCalendar),
            RoutineStep(title: kept.title, detail: "Second guess", kind: kept.kind, durationMinutes: 2, isRequired: true)
        ]
        let draft = RoutineVersion.inferredDraft(from: .init(sourceLabel: "Observation", steps: alternatives),
            preserving: .init(sourceLabel: "User choices", steps: [kept]))
        #expect(draft.steps.count == 3)
        #expect(draft.steps.last == kept)
        #expect(draft.steps.prefix(2).allSatisfy { !$0.isRequired && $0.automation == nil })
    }

    @Test("A shared prior title or a different kind is not an unambiguous match")
    func ambiguousPriorAndDifferentKindRemainSeparate() {
        let kept = ritual()
        let old = RoutineVersion(sourceLabel: "User choices", steps: [kept,
            RoutineStep(title: kept.title, kind: kept.kind)])
        let inferred = RoutineStep(title: kept.title, kind: kept.kind, durationMinutes: 1)
        let draft = RoutineVersion.inferredDraft(from: .init(sourceLabel: "Observation", steps: [inferred]), preserving: old)
        #expect(draft.steps == [inferred, kept])
        let otherKind = RoutineStep(title: kept.title, kind: .calendar)
        let otherDraft = RoutineVersion.inferredDraft(from: .init(sourceLabel: "Observation", steps: [otherKind]),
            preserving: .init(sourceLabel: "User choices", steps: [kept]))
        #expect(otherDraft.steps == [otherKind, kept])
    }

    @Test("Stable identity preserves the full kept step; explicit preferences can amend it")
    func stableIdentityAndExplicitPreferences() {
        let kept = ritual()
        let proposed = RoutineStep(id: kept.id, title: "Different model title", detail: "Wrong detail", kind: .custom, durationMinutes: 1)
        let old = RoutineVersion(sourceLabel: "User choices", steps: [kept])
        let draft = RoutineVersion.inferredDraft(from: .init(sourceLabel: "Observation", steps: [proposed]), preserving: old,
            preferences: [.init(stepID: kept.id, isRequired: false, durationMinutes: 17)])
        var expected = kept
        expected.isRequired = false
        expected.durationMinutes = 17
        #expect(draft.steps == [expected])
        #expect(!draft.isApproved)
    }

    @Test("Explicit preferences preserve a nonrequired corrected step, without guessing other corrections")
    func explicitPreferenceTargetSurvives() {
        var corrected = ritual()
        corrected.isRequired = false
        let old = RoutineVersion(sourceLabel: "User choices", steps: [corrected])
        let candidate = RoutineVersion(sourceLabel: "Observation", steps: [])
        let draft = RoutineVersion.inferredDraft(from: candidate, preserving: old,
            preferences: [.init(stepID: corrected.id, durationMinutes: 15)])
        var expected = corrected
        expected.durationMinutes = 15
        #expect(draft.steps == [expected])
        #expect(RoutineVersion.inferredDraft(from: candidate, preserving: old).steps.isEmpty)
        #expect(old.revised(steps: []).steps.isEmpty)
    }

    @Test("New model output cannot assign operations, required flags or approval")
    func modelClaimsAreStrippedButTrustedProposalsRemainCompatible() {
        let claimed = RoutineStep(title: "Calendar", kind: .calendar, isRequired: true, automation: .todayCalendar)
        let candidate = RoutineVersion(sourceLabel: "Model", steps: [claimed], isApproved: true)
        let first = RoutineVersion.inferredDraft(from: candidate, preserving: nil)
        #expect(first.number == 1)
        #expect(!first.isApproved)
        #expect(first.steps[0].automation == nil && !first.steps[0].isRequired)
        let trusted = RoutineVersion(sourceLabel: "User", steps: []).proposing(steps: [claimed])
        #expect(trusted.steps == [claimed])
        #expect(!trusted.isApproved)
    }

    private func ritual() -> RoutineStep {
        RoutineStep(title: "Time for chess", detail: "Enjoy one quiet game; keep this time for myself.",
            kind: .entertainment, durationMinutes: 12, isRequired: true, automation: .spokenNote)
    }
}
