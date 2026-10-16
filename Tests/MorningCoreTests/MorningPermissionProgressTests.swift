import Foundation
import Testing
@testable import MorningCore

@Suite("Progressive permission explanations")
struct MorningPermissionProgressTests {
    @Test func firstOpeningOnlyPreparesTheTwoVoicePermissions() {
        let supported = MorningPermission.allCases
        #expect(MorningPermissionProgress().pending(supported: supported) == supported)
        #expect(MorningPermissionProgress().pendingInitial == [.speech, .microphone])
        #expect(MorningPermissionProgress(completed: [.speech, .microphone]).pendingInitial.isEmpty)
        #expect(MorningPermissionProgress(completed: [.speech]).pendingInitial == [.microphone])
    }
    @Test func handledChoicesSurviveRelaunchAndDoNotRepeat() throws {
        var progress = MorningPermissionProgress()
        progress.resolve(.location)
        progress.resolve(.speech)
        let restored = try JSONDecoder().decode(MorningPermissionProgress.self, from: JSONEncoder().encode(progress))
        #expect(restored.pending(supported: [.location, .calendar, .speech, .microphone]) == [.calendar, .microphone])
    }
    @Test func unavailableCapabilitiesAndDuplicatesDoNotAddPrompts() {
        let progress = MorningPermissionProgress(completed: [.location])
        #expect(progress.pending(supported: [.location, .calendar, .calendar, .microphone]) == [.calendar, .microphone])
    }
    @Test func newlySupportedCapabilityIsOfferedAfterAnEarlierSetup() {
        let progress = MorningPermissionProgress(completed: [.location, .calendar])
        #expect(progress.pending(supported: [.location, .calendar, .alarms]) == [.alarms])
    }
}
