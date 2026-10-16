import Foundation
import Testing
@testable import MorningCore

@Suite("Single-page permission setup progress")
struct MorningPermissionProgressTests {
    @Test func firstOpeningOffersTheAvailableAccessesInOrder() {
        let progress = MorningPermissionProgress()
        let supported: [MorningPermission] = [.location, .calendar, .reminders, .screenTime, .speech, .notifications, .alarms]
        #expect(!progress.initialSetupCompleted)
        #expect(progress.pending(supported: supported) == supported)
        #expect(progress.pendingInitial == [.speech, .microphone])
    }

    @Test func interruptedSetupRetainsHandledChoicesAndOnlyQueuesTheRest() throws {
        var progress = MorningPermissionProgress()
        progress.resolve(.location)
        progress.resolve(.calendar)
        let restored = try roundTrip(progress)
        #expect(!restored.initialSetupCompleted)
        #expect(restored.pending(supported: [.location, .calendar, .speech, .notifications]) == [.speech, .notifications])
    }

    @Test func completedOrSkippedSetupStaysFinishedWithoutFabricatingSystemGrants() throws {
        var progress = MorningPermissionProgress()
        progress.completeInitialSetup()
        let restored = try roundTrip(progress)
        #expect(restored.initialSetupCompleted)
        #expect(restored.completed.isEmpty)
        #expect(restored.pending(supported: [.location, .calendar, .speech]) == [.location, .calendar, .speech],
                "Finishing setup leaves every access available for an independent later choice.")
    }

    @Test func completedLegacyVoiceSetupDoesNotReopenOnboarding() throws {
        let restored = try JSONDecoder().decode(MorningPermissionProgress.self,
            from: Data(#"{"completed":["speech","microphone"]}"#.utf8))
        #expect(restored.initialSetupCompleted)
        #expect(restored.pending(supported: [.location, .speech, .calendar]) == [.location, .calendar])
    }

    @Test func partialLegacyChoicesStillNeedInitialSetup() throws {
        for completed in [#"[]"#, #"["location","calendar"]"#, #"["speech"]"#] {
            let restored = try JSONDecoder().decode(MorningPermissionProgress.self,
                from: Data("{\"completed\":\(completed)}".utf8))
            #expect(!restored.initialSetupCompleted)
        }
    }

    @Test func explicitIncompleteFlagTakesPrecedenceOverLegacyVoiceMigration() throws {
        let progress = MorningPermissionProgress(completed: [.speech, .microphone])
        let restored = try roundTrip(progress)
        #expect(!restored.initialSetupCompleted)
        #expect(restored.pendingInitial.isEmpty)
    }

    @Test func unavailableCapabilitiesAndDuplicatesDoNotAddPrompts() {
        let progress = MorningPermissionProgress(completed: [.location])
        #expect(progress.pending(supported: [.location, .calendar, .calendar, .microphone]) == [.calendar, .microphone])
    }
    @Test func newlySupportedCapabilityRemainsAvailableWithoutRepeatingSetup() {
        let progress = MorningPermissionProgress(completed: [.location, .calendar], initialSetupCompleted: true)
        #expect(progress.initialSetupCompleted)
        #expect(progress.pending(supported: [.location, .calendar, .alarms]) == [.alarms])
    }

    private func roundTrip(_ progress: MorningPermissionProgress) throws -> MorningPermissionProgress {
        try JSONDecoder().decode(MorningPermissionProgress.self, from: JSONEncoder().encode(progress))
    }
}
