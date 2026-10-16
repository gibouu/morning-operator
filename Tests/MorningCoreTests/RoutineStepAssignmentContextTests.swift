import Foundation
import Testing
@testable import MorningCore

@Suite("Assign a source to the existing reviewed moment")
struct RoutineStepAssignmentContextTests {
    private var slack: RoutineStepTarget {
        .connectedAPI(service: "slack", connectionID: "synthetic-connection",
            tool: "SLACK_FETCH_CONVERSATION_HISTORY", argumentsJSON: #"{"channel":"CSYNTHETIC","limit":3}"#)
    }

    @Test("A full ten-moment plan keeps its identity, wording, position, personal choice and provenance")
    func fullRoutineAssignmentAndApprovalBoundary() throws {
        let reference = try RoutineObservationReference(acquisitionID: UUID(), revisionSHA256: String(repeating: "a", count: 64),
            quote: "SYNTHETIC reviewed source", isSynthetic: true)
        let kept = RoutineStep(title: "My team", detail: "My exact personal note 🌅", kind: .messages,
            durationMinutes: 7, isRequired: true, automation: .savedObservation,
            observationReference: reference, syntheticEvidence: true)
        var steps = (0..<10).map { RoutineStep(title: "Moment \($0)", durationMinutes: $0 + 1) }
        steps[2] = kept
        let previous = RoutineVersion(sourceLabel: "My reviewed source", steps: steps, isApproved: true)
        let generation = UUID()
        let context = RoutineStepAssignmentContext(routineVersionID: previous.id, stepID: kept.id, privacyGeneration: generation)

        let copy = try context.assigning(slack, to: kept, routine: previous, generation: generation)
        #expect(previous.steps[2] == kept && previous.isApproved)
        #expect(copy.id == kept.id && copy.title == kept.title && copy.detail == kept.detail)
        #expect(copy.kind == kept.kind && copy.durationMinutes == kept.durationMinutes && copy.isRequired)
        #expect(copy.observationReference == reference && copy.syntheticEvidence == true)
        #expect(copy.target == slack && copy.automation == nil && copy.webBehavior == nil && copy.webLikesAllowed == nil)

        var preferences = RoutinePreferenceJournal()
        try preferences.upsert(RoutinePreference(target: kept, presence: .keep, durationMinutes: kept.durationMinutes))
        try preferences.rememberOrder(of: steps)
        // Saving the edit updates the existing choice, not its identity or order.
        try preferences.upsert(RoutinePreference(target: copy, presence: .keep, durationMinutes: copy.durationMinutes))
        let revised = previous.revised(steps: try context.replacing(copy, in: previous, generation: generation))
        let restored = try JSONDecoder().decode(RoutineVersion.self, from: JSONEncoder().encode(revised))
        let restoredChoices = try JSONDecoder().decode(RoutinePreferenceJournal.self, from: JSONEncoder().encode(preferences))
        #expect(restored.steps.count == 10 && restored.steps.map(\.id) == previous.steps.map(\.id))
        #expect(restored.steps[2] == copy && restored.sourceLabel == previous.sourceLabel && restored.isSynthetic)
        #expect(!restored.isApproved && restored.id != previous.id && restored.number == previous.nextNumber)
        #expect(restoredChoices.entries.count == 1 && restoredChoices.entry(targetID: kept.id)?.retainedStep == copy)
        #expect(restoredChoices.entry(targetID: kept.id)?.durationMinutes == 7)
        #expect(restoredChoices.order?.map(\.targetID) == previous.steps.map(\.id))
        #expect(previous.steps == steps && previous.isApproved)
    }

    @Test("A revised, missing or foreign edit cannot fall back to appending a moment")
    func staleAndForeignSelectionsRefuse() throws {
        let step = RoutineStep(title: "Existing")
        let routine = RoutineVersion(sourceLabel: "Reviewed", steps: [step], isApproved: true)
        let generation = UUID()
        let context = RoutineStepAssignmentContext(routineVersionID: routine.id, stepID: step.id, privacyGeneration: generation)
        let revised = routine.revised(steps: routine.steps)
        let missing = RoutineVersion(id: routine.id, sourceLabel: routine.sourceLabel, steps: [])
        let duplicated = RoutineVersion(id: routine.id, sourceLabel: routine.sourceLabel, steps: [step, step])
        for candidate in [nil, revised, missing, duplicated] {
            #expect(throws: RoutineStepAssignmentContext.AssignmentError.self) {
                try context.assigning(slack, to: step, routine: candidate, generation: generation)
            }
            #expect(throws: RoutineStepAssignmentContext.AssignmentError.self) {
                try context.replacing(step, in: candidate, generation: generation)
            }
        }
        #expect(throws: RoutineStepAssignmentContext.AssignmentError.self) {
            try context.assigning(slack, to: step, routine: routine, generation: UUID())
        }
        let foreign = RoutineStep(title: step.title)
        #expect(throws: RoutineStepAssignmentContext.AssignmentError.self) {
            try context.replacing(foreign, in: routine, generation: generation)
        }
        #expect(throws: RoutineStepAssignmentContext.AssignmentError.self) {
            try context.assigning(slack, to: foreign, routine: routine, generation: generation)
        }
        #expect(routine.steps == [step] && routine.isApproved)
    }

    @Test("Invalid service configuration is refused before it enters the edit copy")
    func invalidTargetRefuses() {
        let step = RoutineStep(title: "Existing", detail: "Keep this note", durationMinutes: 3)
        let routine = RoutineVersion(sourceLabel: "Reviewed", steps: [step])
        let generation = UUID()
        let context = RoutineStepAssignmentContext(routineVersionID: routine.id, stepID: step.id, privacyGeneration: generation)
        let invalid = RoutineStepTarget.connectedAPI(service: "slack", connectionID: "", tool: "", argumentsJSON: "not JSON")
        #expect(throws: (any Error).self) { try context.assigning(invalid, to: step, routine: routine, generation: generation) }
        #expect(routine.steps == [step])
    }
}
