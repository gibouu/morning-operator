import Testing
@testable import MorningApple

@Suite("Recovery follows actual listening availability")
struct MorningInteractionGuidanceTests {
    @Test(arguments: [false, true])
    func inactiveListeningPointsToExistingSettingsCommands(french: Bool) {
        let next = MorningInteractionGuidance.next(canHearCommands: false, french: french)
        let paused = MorningInteractionGuidance.pausedRequest(canHearCommands: false, french: french)
        #expect(next.contains(french ? "Suivant dans les réglages" : "Next in Settings"))
        #expect(paused.contains(french ? "Continuer ou Suivant dans les réglages" : "Continue or Next in Settings"))
        #expect(paused.contains(french ? "Fermez cette demande et ce moment" : "Close this request and this moment"))
        for message in [next, paused] {
            #expect(!message.lowercased().contains("say "))
            #expect(!message.lowercased().contains("dites "))
        }
    }

    @Test(arguments: [false, true])
    func activeListeningKeepsTheSpokenControls(french: Bool) {
        #expect(MorningInteractionGuidance.next(canHearCommands: true, french: french)
            .contains(french ? "Dites suivant" : "Say next"))
        #expect(MorningInteractionGuidance.pausedRequest(canHearCommands: true, french: french)
            .contains(french ? "Dites reprends" : "Say resume"))
    }

    @Test func contextFreeNarratorErrorsNeverAssumeAMicrophone() {
        for error in [ConnectedResultError.tooLarge, .modelUnavailable, .invalidSummary] {
            let message = error.errorDescription?.lowercased() ?? ""
            #expect(!message.isEmpty)
            #expect(!message.contains("say ") && !message.contains("dites "))
        }
    }
}
