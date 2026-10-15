import Foundation
import Testing
@testable import MorningCore

@Suite("Step timer intent tokens")
struct StepTimerIntentTokenTests {
    private let now = Date(timeIntervalSinceReferenceDate: 813_456_789.876543)

    @Test("A fractional deadline survives the intent's string transport and persisted timer reload")
    func firstTapAfterSerialization() throws {
        let original = StepTimer(sessionID: UUID(), stepID: UUID(), minutes: 3, at: now)
        let token = StepTimer.extensionToken(for: original.endsAt)
        let transported = try JSONDecoder().decode(String.self, from: JSONEncoder().encode(token))
        let expected = try #require(StepTimer.deadline(fromExtensionToken: transported))
        #expect(expected == original.endsAt)
        var restored = try JSONDecoder().decode(StepTimer.self, from: JSONEncoder().encode(original))
        #expect(restored.extend(expectedEnd: expected, at: now.addingTimeInterval(30))
            == .extended(original.endsAt.addingTimeInterval(120)))
        #expect(restored.extensionCount == 1)
    }

    @Test("A calendar-normalized Date can falsely reject a first tap; the opaque token preserves the deadline")
    func precisionLossDoesNotEnterTokenPath() throws {
        let original = StepTimer(sessionID: UUID(), stepID: UUID(), minutes: 3, at: now)
        // Reproduce the failure mode with a seconds-truncated calendar value.
        // This does not claim to inspect Apple's private intent serializer.
        let truncated = Date(timeIntervalSinceReferenceDate: original.endsAt.timeIntervalSinceReferenceDate.rounded(.down))
        var oldPath = original
        #expect(oldPath.extend(expectedEnd: truncated, at: now) == .duplicate)
        #expect(oldPath.extensionCount == 0)
        var tokenPath = original
        let expected = try #require(StepTimer.deadline(fromExtensionToken: StepTimer.extensionToken(for: original.endsAt)))
        #expect(tokenPath.extend(expectedEnd: expected, at: now) == .extended(original.endsAt.addingTimeInterval(120)))
    }

    @Test("Replaying a transported token after save and reload cannot extend the next deadline")
    func replayRemainsIdempotent() throws {
        var timer = StepTimer(sessionID: UUID(), stepID: UUID(), minutes: 3, at: now)
        let stale = try #require(StepTimer.deadline(fromExtensionToken: StepTimer.extensionToken(for: timer.endsAt)))
        _ = timer.extend(expectedEnd: stale, at: now)
        let once = timer.endsAt
        var reloaded = try JSONDecoder().decode(StepTimer.self, from: JSONEncoder().encode(timer))
        #expect(reloaded.extend(expectedEnd: stale, at: now.addingTimeInterval(1)) == .duplicate)
        #expect(reloaded.endsAt == once)
        #expect(reloaded.extensionCount == 1)
        let fresh = try #require(StepTimer.deadline(fromExtensionToken: StepTimer.extensionToken(for: reloaded.endsAt)))
        #expect(reloaded.extend(expectedEnd: fresh, at: now.addingTimeInterval(2)) == .extended(once.addingTimeInterval(120)))
    }

    @Test("A token rendered before pause and resume cannot extend a changed deadline")
    func resumeInvalidatesOldToken() throws {
        var timer = StepTimer(sessionID: UUID(), stepID: UUID(), minutes: 3, at: now)
        let stale = try #require(StepTimer.deadline(fromExtensionToken: StepTimer.extensionToken(for: timer.endsAt)))
        timer.pause(at: now.addingTimeInterval(10))
        timer.resume(at: now.addingTimeInterval(40))
        let resumedEnd = timer.endsAt
        #expect(timer.extend(expectedEnd: stale, at: now.addingTimeInterval(41)) == .duplicate)
        #expect(timer.endsAt == resumedEnd)
        #expect(timer.extensionCount == 0)
    }

    @Test("Malformed, future-version and nonfinite tokens fail closed")
    func invalidTokens() {
        for token in ["", "end1:", "end1:xyz", "end2:41c83df730000000", "end1:10000000000000000",
                      "end1:7ff0000000000000", "end1:fff0000000000000", "end1:7ff8000000000000"] {
            #expect(StepTimer.deadline(fromExtensionToken: token) == nil)
        }
    }
}
