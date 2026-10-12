import Foundation
import Testing
@testable import MorningCore

@Suite("Configured app transition evidence")
struct AppTransitionHistoryTests {
    private let day = Date(timeIntervalSince1970: 1_800_000_000)

    @Test func entriesExitsAndObservedReturnsHaveSeparateCounts() throws {
        let events = try [
            event(.instagram, .entered, 0), event(.instagram, .exited, 10),
            event(.tiktok, .entered, 11), event(.tiktok, .exited, 20),
            event(.snapchat, .entered, 21), event(.snapchat, .exited, 30),
            event(.instagram, .entered, 31)
        ]
        let summary = try AppTransitionHistory(events: Array(events.reversed())).summary(for: day, timeZoneIdentifier: "UTC")
        #expect(summary.eventCount == 7)
        #expect(summary.foregroundEntryCount == 4)
        #expect(summary.entryCounts.first { $0.app == .instagram }?.count == 2)
        #expect(summary.observedSwitchCount == 3)
        #expect(summary.observedReturnCount == 1)
        let returned = try #require(summary.returns?.first)
        #expect(returned.app == .instagram)
        #expect(returned.interveningApps == [.tiktok, .snapchat])
        #expect(returned.startedAt == day)
        #expect(returned.returnedAt == day.addingTimeInterval(31))
    }

    @Test func noEventsDoesNotAssertZeroDeviceUse() throws {
        let summary = try AppTransitionHistory().summary(for: day, timeZoneIdentifier: "UTC")
        #expect(!summary.hasEvents)
        #expect(summary.foregroundEntryCount == 0)
        #expect(summary.coverageDescription.contains("not pickups"))
    }

    @Test func reopeningSameAppWithoutAnotherObservedAppIsNotAReturnCycle() throws {
        let history = try AppTransitionHistory(events: [event(.instagram, .entered, 0),
            event(.instagram, .exited, 10), event(.instagram, .entered, 20)])
        let summary = try history.summary(for: day, timeZoneIdentifier: "UTC")
        #expect(summary.foregroundEntryCount == 2)
        #expect(summary.observedSwitchCount == 0)
        #expect(summary.observedReturnCount == 0)
    }

    @Test func stableIDRetryIsDeduplicatedAndConflictingPayloadIsRejected() throws {
        let first = try event(.instagram, .entered, 0)
        var history = try AppTransitionHistory()
        #expect(try history.append(first))
        #expect(try !history.append(first))
        let conflicting = try AppTransitionEvent(id: first.id, app: .tiktok, kind: .entered,
            observedAt: day, timeZoneIdentifier: "UTC")
        #expect(throws: AppTransitionError.conflictingEventID) { try history.append(conflicting) }
        #expect(history.events.count == 1)
    }

    @Test func equalTimestampsDoNotInventSwitchOrder() throws {
        let history = try AppTransitionHistory(events: [event(.instagram, .entered, 0), event(.tiktok, .entered, 0)])
        let summary = try history.summary(for: day, timeZoneIdentifier: "UTC")
        #expect(summary.foregroundEntryCount == 2)
        #expect(summary.observedSwitchCount == nil)
        #expect(summary.returns == nil)
    }

    @Test func localDateAndValidatedDecodingSurviveRoundTrip() throws {
        let midnightUTC = Date(timeIntervalSince1970: 1_800_057_600)
        let event = try AppTransitionEvent(app: .snapchat, kind: .entered, observedAt: midnightUTC,
            timeZoneIdentifier: "America/Los_Angeles")
        let encoded = try JSONEncoder().encode(event)
        #expect(try JSONDecoder().decode(AppTransitionEvent.self, from: encoded) == event)
        var object = try #require(JSONSerialization.jsonObject(with: encoded) as? [String: Any])
        object["timeZoneIdentifier"] = "invalid/zone"
        let invalid = try JSONSerialization.data(withJSONObject: object)
        #expect(throws: AppTransitionError.invalidTimeZone) {
            try JSONDecoder().decode(AppTransitionEvent.self, from: invalid)
        }
        let history = try AppTransitionHistory(events: [event])
        let local = try history.summary(for: midnightUTC, timeZoneIdentifier: "America/Los_Angeles")
        #expect(local.foregroundEntryCount == 1)
        #expect(throws: AppTransitionError.invalidDate) {
            try AppTransitionEvent(app: .instagram, kind: .entered, observedAt: Date(timeIntervalSince1970: .infinity))
        }
    }

    private func event(_ app: ObservedApp, _ kind: AppTransitionKind, _ offset: TimeInterval) throws -> AppTransitionEvent {
        try AppTransitionEvent(app: app, kind: kind, observedAt: day.addingTimeInterval(offset), timeZoneIdentifier: "UTC")
    }
}
