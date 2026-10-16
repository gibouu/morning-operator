import Foundation
import Testing
@testable import MorningCore

@Suite("Quick capture intent")
struct QuickCaptureTests {
    @Test func requestedDateAndSourceRoundTripWithoutBecomingAnExternalCommit() throws {
        let created = Date(timeIntervalSince1970: 1_800_000_000)
        let requested = created.addingTimeInterval(3_600)
        let capture = try QuickCapture(kind: .calendarIdea, text: "  Talk about the morning prototype  ",
                                       createdAt: created, requestedDate: requested,
                                       timeZoneIdentifier: "Europe/Paris", source: .siri)
        let restored = try JSONDecoder().decode(QuickCapture.self, from: JSONEncoder().encode(capture))
        #expect(restored == capture)
        #expect(restored.text == "Talk about the morning prototype")
        #expect(restored.requestedDate == requested)
        #expect(restored.createdAt == created)
        #expect(restored.source == .siri)
        #expect(restored.kind == .calendarIdea)
    }

    @Test func unspecifiedDatesStayUnspecifiedForDreamsAndReminders() throws {
        let dream = try QuickCapture(kind: .dream, text: "A train across the ocean", timeZoneIdentifier: "UTC")
        let reminder = try QuickCapture(kind: .reminder, text: "Call later", timeZoneIdentifier: "UTC", source: .voice)
        #expect(dream.requestedDate == nil)
        #expect(reminder.requestedDate == nil)
        #expect(dream.kind == .dream)
    }

    @Test func invalidInputAndDecodedInvalidRequestsAreRejected() throws {
        #expect(throws: QuickCaptureError.emptyText) {
            _ = try QuickCapture(kind: .thought, text: " \n  ", timeZoneIdentifier: "UTC")
        }
        #expect(throws: QuickCaptureError.invalidTimeZone) {
            _ = try QuickCapture(kind: .thought, text: "An idea", timeZoneIdentifier: "invalid/time-zone")
        }
        #expect(throws: QuickCaptureError.invalidDate) {
            _ = try QuickCapture(kind: .reminder, text: "An idea", requestedDate: Date(timeIntervalSince1970: .infinity), timeZoneIdentifier: "UTC")
        }
        let valid = try QuickCapture(kind: .thought, text: "Keep this idea", timeZoneIdentifier: "UTC")
        let encoded = try JSONEncoder().encode(valid)
        var object = try #require(JSONSerialization.jsonObject(with: encoded) as? [String: Any])
        object["text"] = "   "
        let invalid = try JSONSerialization.data(withJSONObject: object)
        #expect(throws: QuickCaptureError.emptyText) {
            _ = try JSONDecoder().decode(QuickCapture.self, from: invalid)
        }
    }
}
