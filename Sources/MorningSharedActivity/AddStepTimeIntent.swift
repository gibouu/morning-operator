import AppIntents
import Foundation
import MorningCore
import MorningApple

/// The same intent type is built into MORE and its widget. LiveActivityIntent runs
/// in MORE's process, so it edits MORE's timer without an app group or opening UI.
struct AddStepTimeIntent: LiveActivityIntent {
    static let title: LocalizedStringResource = "Add two minutes"
    static let description = IntentDescription("Add two minutes to the current morning step.")
    static let supportedModes: IntentModes = .background
    @Parameter(title: "Session") var session: String?
    @Parameter(title: "Step") var step: String?
    @Parameter(title: "Displayed end") var expectedEnd: Date?
    init() {}
    init(sessionID: UUID, stepID: UUID, expectedEnd: Date) {
        session = sessionID.uuidString; step = stepID.uuidString; self.expectedEnd = expectedEnd
    }
    @MainActor func perform() async throws -> some IntentResult & ProvidesDialog {
        let sessionID = session.flatMap(UUID.init(uuidString:))
        let stepID = step.flatMap(UUID.init(uuidString:))
        guard (session == nil) == (step == nil),
              session == nil || sessionID != nil, step == nil || stepID != nil else {
            return .result(dialog: "This step timer is unavailable.")
        }
        let result = await StepTimerExtension.addTwoMinutes(sessionID: sessionID,
            stepID: stepID, expectedEnd: expectedEnd)
        switch result {
        case .extended: return .result(dialog: "Two minutes added.")
        case .duplicate: return .result(dialog: "This timer already changed.")
        case .limitReached: return .result(dialog: "This step has reached its extension limit.")
        case nil: return .result(dialog: "There is no current step timer.")
        }
    }
}
