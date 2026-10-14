import Foundation
import MorningCore
import Testing
@testable import MorningApple

@Suite("Evidence retention plan — byte-exact edits and every retained copy")
struct EvidenceRetentionCopyTests {
    private let now = Date(timeIntervalSince1970: 1_791_417_600)

    private func observation(_ text: String) throws -> ObservationAcquisition {
        try ObservationAcquisition(importedAt: now.addingTimeInterval(-30 * 86_400),
            observedDate: .init(date: now, timeZoneIdentifier: "Europe/Paris", provenance: .userAssigned),
            origin: .human, sourceKind: .text, sourceLabel: "Synthetic retention fixture", originalText: text)
    }

    private func moment(_ source: ObservationAcquisition) throws -> RoutineStep {
        let candidate = try #require(ObservationNarrationComposer.candidates(for: source).first)
        let prepared = try ObservationNarrationComposer.prepare(acquisition: source, candidate: candidate,
                                                                 language: .english)
        return RoutineStep(title: "Saved test moment", detail: prepared.spokenText, kind: .briefing,
            durationMinutes: 1, automation: .savedObservation, observationReference: prepared.reference)
    }

    private func plan(_ archive: ObservationArchive, current: RoutineVersion,
                      preferences: RoutinePreferenceJournal = .init()) -> EvidenceRetentionPlan {
        EvidenceRetentionPlan(archive: archive, currentRoutine: current, previousRoutine: nil,
            session: nil, pendingProposal: nil, preferences: preferences, history: .init(),
            now: now, maximumAge: 7 * 86_400)
    }

    @Test func canonicallyEquivalentUserEditIsStillAnEditAndCannotBeRemoved() throws {
        let source = try observation("I drink caf\u{00E9} before reviewing my calendar.")
        let untouched = try moment(source)
        var edited = untouched
        edited.detail = edited.detail.replacingOccurrences(of: "caf\u{00E9}", with: "cafe\u{0301}")
        // String equality is deliberately not enough to establish untouched text.
        #expect(edited.detail == untouched.detail)
        #expect(Array(edited.detail.utf8) != Array(untouched.detail.utf8))
        let archive = try ObservationArchive(entries: [source])
        let draft = RoutineVersion(sourceLabel: "Retention fixture", steps: [edited])
        let copies = plan(archive, current: draft).dependents(of: source.id)
        #expect(copies.count == 1)
        #expect(copies.first?.reason == .reworkedStep)
        #expect(!copies.contains { $0.disposition == .removed })
        #expect(Array(draft.steps[0].detail.utf8) == Array(edited.detail.utf8))
    }

    @Test func decodedDuplicateStepIdentityDoesNotHideEitherStoredReference() throws {
        let first = try observation("I read the calendar before breakfast.")
        let second = try observation("I stretch after breakfast.")
        var firstStep = try moment(first)
        firstStep.isRequired = true
        let secondMoment = try moment(second)
        // A malformed saved routine can contain two rows with one ID. The planner
        // still owes the person an inventory of both physical source references.
        let secondStep = RoutineStep(id: firstStep.id, title: secondMoment.title, detail: secondMoment.detail,
            kind: secondMoment.kind, durationMinutes: 1, isRequired: true,
            automation: .savedObservation, observationReference: secondMoment.observationReference)
        let encoded = try JSONEncoder().encode(RoutineVersion(sourceLabel: "Retention fixture", steps: [firstStep, secondStep]))
        let restored = try JSONDecoder().decode(RoutineVersion.self, from: encoded)
        #expect(restored.steps[0].id == restored.steps[1].id)
        let result = plan(try ObservationArchive(entries: [first, second]), current: restored)
        #expect(result.dependentCopies.count == 2)
        #expect(Set(result.dependentCopies.map(\.acquisitionID)) == Set([first.id, second.id]))
        #expect(result.dependentCopies.allSatisfy { $0.reason == .markedRequired && $0.disposition == .separatelyRetained })
    }

    @Test func identicalWordsInDifferentObservationsRemainTwoDependentsAfterReordering() throws {
        let text = "I review my calendar and then read the mail."
        let first = try observation(text)
        let second = try observation(text)
        let quote = "review my calendar and then read"
        // This is neither a whole source line nor linked to either observation;
        // both saved languages must identify both possible retained copies.
        let step = RoutineStep(title: "Test note", detail: "Source : “\(quote)”\nEvidence: “\(quote)”",
            automation: .spokenNote)
        let routine = RoutineVersion(sourceLabel: "Retention fixture", steps: [step])
        for entries in [[first, second], [second, first]] {
            let result = plan(try ObservationArchive(entries: entries), current: routine)
            #expect(result.dependentCopies.count == 2)
            #expect(result.dependentCopies.map(\.acquisitionID) == entries.map(\.id))
            #expect(result.dependentCopies.allSatisfy {
                $0.kind == .unlinkedStepText && $0.quote == quote && $0.disposition == .separatelyRetained
            })
        }
    }

    @Test func reloadedKeepSnapshotProtectsAReferenceCarriedByANewStepIdentity() throws {
        let source = try observation("I spend a few minutes reading before breakfast.")
        let original = try moment(source)
        var journal = RoutinePreferenceJournal()
        try journal.upsert(RoutinePreference(target: original, presence: .keep))
        let restoredJournal = try JSONDecoder().decode(RoutinePreferenceJournal.self,
            from: JSONEncoder().encode(journal))
        let restoredArchive = try JSONDecoder().decode(ObservationArchive.self,
            from: JSONEncoder().encode(ObservationArchive(entries: [source])))
        let copied = RoutineStep(title: "A copied saved moment", detail: original.detail,
            automation: .savedObservation, observationReference: original.observationReference)
        #expect(copied.id != original.id)
        let routine = RoutineVersion(sourceLabel: "Retention fixture", steps: [copied])
        let first = plan(restoredArchive, current: routine, preferences: restoredJournal)
        let second = plan(restoredArchive, current: routine, preferences: restoredJournal)
        #expect(first == second)
        #expect(first.expiredAcquisitionIDs == [source.id])
        let copies = first.dependents(of: source.id)
        #expect(copies.map(\.store) == [.currentRoutine, .preferenceJournal])
        #expect(copies.map(\.stepID) == [copied.id, original.id])
        #expect(copies.allSatisfy { $0.reason == .keptChoice && $0.disposition == .separatelyRetained })
        #expect(restoredArchive.entries.count == 1)
        #expect(restoredJournal == journal)
    }
}
