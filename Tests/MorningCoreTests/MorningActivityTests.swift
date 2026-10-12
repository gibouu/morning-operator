import Foundation
import Testing
@testable import MorningCore

@Suite("Privacy-safe Live Activity projection")
struct MorningActivityTests {
    private let now = Date(timeIntervalSince1970: 1_800_000_000)

    @Test func projectionNeverContainsRoutineContentOrPlannedTime() throws {
        let secret = "SYNTHETIC_PRIVATE_TEXT_DO_NOT_DISPLAY"
        let routine = RoutineVersion(sourceLabel: secret, steps: [
            .init(title: secret, detail: secret, kind: .calendar, durationMinutes: 91)
        ], isApproved: true)
        var session = RoutineSession(routine: routine)
        try session.start(at: now)
        let snapshot = try #require(MorningActivityProjection.snapshot(session: session, at: now))
        #expect(snapshot.state.category == .calendar && snapshot.state.status == .running)
        #expect(snapshot.state.completedSteps == 0 && snapshot.state.totalSteps == 1)
        let encoded = try JSONEncoder().encode(snapshot)
        let json = try #require(String(data: encoded, encoding: .utf8))
        #expect(!json.contains(secret) && !json.contains("durationMinutes") && !json.contains("routine"))
        #expect(encoded.count < 1_024)
    }

    @Test func skippedPositionPausedAndAttentionAreExplicit() throws {
        var session = RoutineSession(routine: DemoFixtures.routine)
        try session.start(at: now)
        try session.advance(skipping: true, at: now)
        try session.pause(at: now)
        let paused = try #require(MorningActivityProjection.snapshot(session: session, at: now))
        #expect(paused.state.currentStepNumber == 2 && paused.state.completedSteps == 1)
        #expect(paused.state.status == .paused && paused.state.category == .messages)
        #expect(MorningActivityProjection.snapshot(session: session, needsAttention: true, at: now)?.state.status == .paused)
        try session.resume(at: now)
        #expect(MorningActivityProjection.snapshot(session: session, needsAttention: true, at: now)?.state.status == .needsAttention)
    }

    @Test func readyStoppedCompletedAndInvalidTimeHaveNoProjection() throws {
        var session = RoutineSession(routine: DemoFixtures.routine)
        #expect(MorningActivityProjection.snapshot(session: session) == nil)
        try session.start(at: now)
        #expect(MorningActivityProjection.snapshot(session: session, at: Date(timeIntervalSince1970: .infinity)) == nil)
        var stopped = session
        try stopped.stop(at: now)
        #expect(MorningActivityProjection.snapshot(session: stopped) == nil)
        while session.status == .running { try session.advance(at: now) }
        #expect(MorningActivityProjection.snapshot(session: session) == nil)
        #expect(MorningActivityProjection.snapshot(session: nil) == nil)
    }

    @Test func decodedProgressRejectsOverflowAndUnknownVocabulary() throws {
        let state = try MorningActivityContentState(category: .custom, status: .running,
            completedSteps: 0, totalSteps: 1, updatedAt: now)
        let data = try JSONEncoder().encode(state)
        var json = try #require(JSONSerialization.jsonObject(with: data) as? [String: Any])
        for invalid in [-1, Int.max] {
            json["completedSteps"] = invalid
            let malformed = try JSONSerialization.data(withJSONObject: json)
            #expect(throws: (any Error).self) { try JSONDecoder().decode(MorningActivityContentState.self, from: malformed) }
        }
        json["completedSteps"] = 0; json["category"] = "Private custom category"
        let malformed = try JSONSerialization.data(withJSONObject: json)
        #expect(throws: (any Error).self) { try JSONDecoder().decode(MorningActivityContentState.self, from: malformed) }
    }

    @Test func timestampAloneIsNotFreshProgressAndNamespacesCannotCollide() throws {
        let first = try MorningActivityContentState(category: .custom, status: .paused, completedSteps: 0, totalSteps: 2, updatedAt: now)
        let later = try MorningActivityContentState(category: .custom, status: .paused, completedSteps: 0, totalSteps: 2, updatedAt: now.addingTimeInterval(30))
        #expect(first.hasSameProgress(as: later) && first != later)
        #expect(MorningActivityNamespace.production != .testing(workspaceID: UUID(uuidString: "00000000-0000-0000-0000-000000000000")!))
        let namespace = MorningActivityNamespace.testing(workspaceID: UUID())
        #expect(try JSONDecoder().decode(MorningActivityNamespace.self, from: JSONEncoder().encode(namespace)) == namespace)
    }
}
