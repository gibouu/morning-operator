import Foundation
import Testing
@testable import MorningCore

@Suite("Live Activity artwork retains known timer dates")
struct MorningActivityArtworkTests {
    private let start = Date(timeIntervalSinceReferenceDate: 1_000)
    private func timer(startedAt: Date?, pausedRemaining: TimeInterval? = nil) -> MorningActivityStepTimer {
        MorningActivityStepTimer(stepID: UUID(), destination: .app(.maps), endsAt: start.addingTimeInterval(600),
            nextDestination: nil, hasNextStep: false, pausedRemaining: pausedRemaining, startedAt: startedAt)
    }

    @Test func olderPayloadsDecodeWithUnknownStartInsteadOfInventingOne() throws {
        let encoded = try JSONEncoder().encode(timer(startedAt: start))
        var object = try #require(JSONSerialization.jsonObject(with: encoded) as? [String: Any])
        object.removeValue(forKey: "startedAt")
        let legacy = try JSONDecoder().decode(MorningActivityStepTimer.self,
            from: JSONSerialization.data(withJSONObject: object))
        #expect(legacy.startedAt == nil)
        #expect(legacy.elapsedFraction(at: start.addingTimeInterval(300)) == nil)
    }

    @Test func progressIsBoundedAndPausedTimeDoesNotAdvanceTheArtwork() {
        let live = timer(startedAt: start)
        #expect(live.elapsedFraction(at: start.addingTimeInterval(-30)) == 0)
        #expect(live.elapsedFraction(at: start.addingTimeInterval(300)) == 0.5)
        #expect(live.elapsedFraction(at: start.addingTimeInterval(900)) == 1)
        let paused = timer(startedAt: start, pausedRemaining: 300)
        #expect(paused.elapsedFraction(at: start.addingTimeInterval(300)) == 0.5)
        #expect(paused.elapsedFraction(at: start.addingTimeInterval(9_000)) == 0.5)
        #expect(timer(startedAt: nil).elapsedFraction(at: start) == nil)
    }

    @Test func knownStartSurvivesRoundTripAndInvalidIntervalsStayUnknown() throws {
        let source = timer(startedAt: start)
        let restored = try JSONDecoder().decode(MorningActivityStepTimer.self, from: JSONEncoder().encode(source))
        #expect(restored.startedAt == start)
        #expect(timer(startedAt: start.addingTimeInterval(700)).elapsedFraction(at: start) == nil)
    }
}
