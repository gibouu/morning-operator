import Foundation
import Testing
@testable import MorningCore

@Suite("Return from an external app")
struct ExternalAppReturnTests {
    private func running(_ target: RoutineStepTarget?) throws -> RoutineSession {
        var session = RoutineSession(routine: RoutineVersion(sourceLabel: "Test", steps: [
            RoutineStep(title: "App moment", durationMinutes: 5, target: target),
            RoutineStep(title: "Back in MORE", durationMinutes: 1)
        ], isApproved: true))
        try session.start()
        return session
    }

    @Test("Only the exact running native app moment can advance on return")
    func exactRunningApp() throws {
        var session = try running(.externalApp(.mail, detail: nil))
        let sessionID = session.id, stepID = try #require(session.currentStep?.id)
        #expect(StepNavigation.mayAdvanceAfterExternalAppReturn(session: session, sessionID: sessionID, stepID: stepID))
        #expect(!StepNavigation.mayAdvanceAfterExternalAppReturn(session: session, sessionID: UUID(), stepID: stepID))
        #expect(!StepNavigation.mayAdvanceAfterExternalAppReturn(session: session, sessionID: sessionID, stepID: UUID()))
        try session.pause()
        #expect(!StepNavigation.mayAdvanceAfterExternalAppReturn(session: session, sessionID: sessionID, stepID: stepID))
        try session.resume()
        try session.advance()
        #expect(!StepNavigation.mayAdvanceAfterExternalAppReturn(session: session, sessionID: sessionID, stepID: stepID))
        #expect(!StepNavigation.mayAdvanceAfterExternalAppReturn(session: nil, sessionID: sessionID, stepID: stepID))
    }

    @Test("Browser, API, shortcut and ordinary MORE moments keep their own progression")
    func excludesOtherRoutes() throws {
        let targets: [RoutineStepTarget?] = [
            .externalApp(.instagram, detail: nil),
            .inAppWeb(site: URL(string: "https://www.lemonde.fr")!),
            .connectedAPI(service: "GMAIL", connectionID: "test", tool: "GMAIL_FETCH_EMAILS", argumentsJSON: "{}"),
            .shortcut(name: "Test", input: ""), nil
        ]
        for target in targets {
            let session = try running(target)
            #expect(!StepNavigation.mayAdvanceAfterExternalAppReturn(session: session,
                sessionID: session.id, stepID: try #require(session.currentStep?.id)))
        }
    }
}
