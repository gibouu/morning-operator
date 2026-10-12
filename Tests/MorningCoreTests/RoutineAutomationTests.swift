import Foundation
import Testing
@testable import MorningCore

@Suite("Explicit routine operations")
struct RoutineAutomationTests {
    @Test func inferredAndLegacyActivityCategoriesStayManual() throws {
        for kind in StepKind.allCases {
            let inferred = RoutineStep(title: "An observed activity", kind: kind)
            #expect(inferred.automation == nil)
        }
        let automatic = RoutineStep(title: "A note", kind: .briefing, automation: .spokenNote)
        let data = try JSONEncoder().encode(automatic)
        var legacy = try #require(JSONSerialization.jsonObject(with: data) as? [String: Any])
        legacy.removeValue(forKey: "automation")
        let restored = try JSONDecoder().decode(RoutineStep.self, from: JSONSerialization.data(withJSONObject: legacy))
        #expect(restored.kind == .briefing)
        #expect(restored.automation == nil)
    }

    @Test(arguments: RoutineStepAutomation.allCases) func approvedOperationsRoundTripAndRemainPinnedDuringEdits(_ automation: RoutineStepAutomation) throws {
        let operation = RoutineStep(title: "Read today's schedule", kind: .calendar, automation: automation)
        let approved = RoutineVersion(sourceLabel: "Chosen explicitly", steps: [operation], isApproved: true)
        var session = RoutineSession(routine: approved)
        try session.start()
        var edited = operation
        edited.automation = nil
        let draft = approved.revised(steps: [edited])
        #expect(!draft.isApproved)
        #expect(draft.steps[0].automation == nil)
        #expect(session.routine.steps[0].automation == automation)
        let restored = try JSONDecoder().decode(RoutineSession.self, from: JSONEncoder().encode(session))
        #expect(restored.routine.steps[0].automation == automation)
        #expect(restored == session)
    }
}
