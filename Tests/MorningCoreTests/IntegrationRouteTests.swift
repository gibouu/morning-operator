import Foundation
import Testing
@testable import MorningCore

@Suite("Integration routes")
struct IntegrationRouteTests {
    @Test func routesDescribeOperationsRatherThanNativeAppSessions() {
        #expect(RoutineStepTarget.inAppWeb(site: WebMorningSite.instagram.table.startURL).integrationRoute == .browser)
        #expect(RoutineStepTarget.externalApp(.instagram, detail: nil).integrationRoute == .browser)
        #expect(RoutineStepTarget.shortcut(name: "Read Messages", input: "today").integrationRoute == .nativeIOS)
        #expect(RoutineStepTarget.connectedAPI(service: "gmail", connectionID: "ca_123", tool: "GMAIL_FETCH_EMAILS", argumentsJSON: "{}").integrationRoute == .api)
    }

    @Test func targetsRoundTripAndRejectUntrustedParameters() throws {
        let target = RoutineStepTarget.connectedAPI(service: "gmail", connectionID: "ca_123", tool: "GMAIL_FETCH_EMAILS", argumentsJSON: "{\"query\":\"is:unread\"}")
        #expect(try JSONDecoder().decode(RoutineStepTarget.self, from: JSONEncoder().encode(target)) == target)
        #expect(throws: IntegrationTargetError.invalidArguments) {
            try RoutineStepTarget.connectedAPI(service: "gmail", connectionID: "ca_123", tool: "GMAIL_FETCH_EMAILS", argumentsJSON: "[]").validateIntegration()
        }
        #expect(throws: IntegrationTargetError.invalidAPIAction) {
            try RoutineStepTarget.connectedAPI(service: "../gmail", connectionID: "ca_123", tool: "READ", argumentsJSON: "{}").validateIntegration()
        }
        #expect(throws: IntegrationTargetError.invalidShortcut) {
            try RoutineStepTarget.shortcut(name: " ", input: "").validateIntegration()
        }
        let bad = Data("{\"kind\":\"connectedAPI\",\"service\":\"gmail\",\"connectionID\":\"ca_123\",\"tool\":\"READ\",\"argumentsJSON\":\"null\"}".utf8)
        #expect(throws: (any Error).self) { try JSONDecoder().decode(RoutineStepTarget.self, from: bad) }
    }

    @Test func effectsHaveStablePerRunIdentityAndPrivateLockScreenLabels() {
        let session = UUID(), step = UUID()
        let request = IntegrationRequestID.make(sessionID: session, stepID: step)
        #expect(request == IntegrationRequestID.make(sessionID: session, stepID: step))
        #expect(request != IntegrationRequestID.make(sessionID: UUID(), stepID: step))
        #expect(request != IntegrationRequestID.make(sessionID: session, stepID: UUID()))
        #expect(RoutineStepTarget.shortcut(name: "Private person's messages", input: "secret").destination == .nativeAction)
        #expect(RoutineStepTarget.connectedAPI(service: "gmail", connectionID: "private_account", tool: "SEND", argumentsJSON: "{}").destination == .connectedService)
    }

    @Test func portablePlansNeverTransferExecutableConnections() throws {
        let routine = RoutineVersion(sourceLabel: "My routine", steps: [RoutineStep(title: "Inbox", target:
            .connectedAPI(service: "gmail", connectionID: "ca_123", tool: "READ", argumentsJSON: "{}"))])
        let restored = try PortableRoutineDocument(routine: routine, detail: .includeDetails).importedDraft(replacing: nil)
        #expect(restored.steps[0].target == nil)
        #expect(!restored.isApproved)
    }
}
