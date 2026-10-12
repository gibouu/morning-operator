import Foundation
import Testing
@testable import MorningApple

@Suite("Native recording provenance lifecycle")
struct ScreenRecordingProvenanceTests {
    @Test("Only the matching output start records a date, and duplicate callbacks keep its first instant")
    func firstMatchingStartWins() throws {
        var state = ScreenRecordingContextState()
        let session = UUID()
        let start = Date(timeIntervalSince1970: 1_728_000_000)
        state.begin(sessionID: session)
        #expect(state.context == nil, "Opening the picker is not the start of a recording.")
        state.recordingDidStart(sessionID: UUID(), startedAt: start, timeZoneIdentifier: "UTC")
        #expect(state.context == nil)
        state.recordingDidStart(sessionID: session, startedAt: start, timeZoneIdentifier: "Europe/Paris")
        let first = try #require(state.context)
        state.recordingDidStart(sessionID: session, startedAt: start.addingTimeInterval(20), timeZoneIdentifier: "UTC")
        #expect(state.context == first)
        #expect(first.id == session && first.startedAt == start && first.timeZoneIdentifier == "Europe/Paris")
    }

    @Test("Handoff/discard clearing and a new picker prevent any previous session's provenance leaking")
    func clearAndReplacementRejectLateCallbacks() {
        var state = ScreenRecordingContextState()
        let first = UUID()
        let next = UUID()
        let start = Date(timeIntervalSince1970: 1_728_000_000)
        state.begin(sessionID: first)
        state.recordingDidStart(sessionID: first, startedAt: start, timeZoneIdentifier: "UTC")
        #expect(state.context != nil)
        state.clear()
        state.recordingDidStart(sessionID: first, startedAt: start, timeZoneIdentifier: "UTC")
        #expect(state.context == nil)
        state.begin(sessionID: next)
        state.recordingDidStart(sessionID: first, startedAt: start, timeZoneIdentifier: "UTC")
        #expect(state.context == nil)
        state.recordingDidStart(sessionID: next, startedAt: start.addingTimeInterval(10), timeZoneIdentifier: "UTC")
        #expect(state.context?.id == next)
        state.begin(sessionID: UUID())
        #expect(state.context == nil)
    }
}
