import Foundation
import Testing
@testable import MorningCore

@Suite("One-time morning invitations")
struct MorningInvitationTests {
    private let origin = Date(timeIntervalSince1970: 1_800_000_000)

    @Test func validatesFutureInstantAndTimeZone() throws {
        #expect(throws: MorningInvitationError.futureDateRequired) {
            try MorningInvitation(scheduledAt: origin, timeZoneIdentifier: "UTC", now: origin)
        }
        #expect(throws: MorningInvitationError.futureDateRequired) {
            try MorningInvitation(scheduledAt: Date(timeIntervalSince1970: .infinity), timeZoneIdentifier: "UTC", now: origin)
        }
        #expect(throws: MorningInvitationError.invalidTimeZone) {
            try MorningInvitation(scheduledAt: origin.addingTimeInterval(10), timeZoneIdentifier: "Not/AZone", now: origin)
        }
        let invitation = try MorningInvitation(scheduledAt: origin.addingTimeInterval(10.2), timeZoneIdentifier: "UTC", now: origin)
        #expect(invitation.scheduledAt == origin.addingTimeInterval(11))
    }

    @Test func rejectsStaleEarlyExpiredAndRepeatedResponses() throws {
        var invitation = try MorningInvitation(scheduledAt: origin.addingTimeInterval(60), timeZoneIdentifier: "Europe/Paris", now: origin)
        let payload = invitation.payload
        let early = invitation.consume(payload, at: origin)
        #expect(!early)
        let stale = invitation.consume(.init(occurrenceID: UUID()), at: invitation.scheduledAt)
        #expect(!stale)
        let wrongSchema = invitation.consume(.init(occurrenceID: invitation.id, schemaVersion: 2), at: invitation.scheduledAt)
        #expect(!wrongSchema)
        let expired = invitation.consume(payload, at: invitation.expiresAt)
        #expect(!expired)
        let accepted = invitation.consume(payload, at: invitation.scheduledAt)
        #expect(accepted)
        let repeated = invitation.consume(payload, at: invitation.scheduledAt.addingTimeInterval(1))
        #expect(!repeated)
        #expect(invitation.consumedAt == invitation.scheduledAt)
        #expect(try JSONDecoder().decode(MorningInvitation.self, from: JSONEncoder().encode(invitation)) == invitation)
    }

    @Test func cancellationAndExpiryCannotBeRevivedByClockRollback() throws {
        var invitation = try MorningInvitation(scheduledAt: origin.addingTimeInterval(60), timeZoneIdentifier: "UTC", now: origin)
        let expired = invitation.expire(at: invitation.expiresAt)
        #expect(expired)
        #expect(!invitation.isEligible(for: invitation.payload, at: invitation.scheduledAt))
        invitation.cancel()
        #expect(!invitation.isEligible(for: invitation.payload, at: invitation.scheduledAt))
    }

    @Test func absoluteInstantSurvivesDSTAndTravelWithoutWallClockReinterpretation() throws {
        let iso = ISO8601DateFormatter()
        // These are the two different 02:30 instants when Paris leaves daylight saving.
        let first = try #require(iso.date(from: "2026-10-25T00:30:00Z"))
        let second = try #require(iso.date(from: "2026-10-25T01:30:00Z"))
        let before = first.addingTimeInterval(-86_400)
        let early = try MorningInvitation(scheduledAt: first, timeZoneIdentifier: "Europe/Paris", now: before)
        let late = try MorningInvitation(scheduledAt: second, timeZoneIdentifier: "Europe/Paris", now: before)
        #expect(late.scheduledAt.timeIntervalSince(early.scheduledAt) == 3_600)
        let restored = try JSONDecoder().decode(MorningInvitation.self, from: JSONEncoder().encode(late))
        var overseas = Calendar(identifier: .gregorian)
        overseas.timeZone = try #require(TimeZone(identifier: "America/New_York"))
        #expect(overseas.component(.hour, from: restored.scheduledAt) == 21)
        #expect(restored.scheduledAt == second)
        #expect(restored.timeZoneIdentifier == "Europe/Paris")
    }

    @Test func malformedPayloadAndInvalidDecodedRecordAreRejected() throws {
        let invitation = try MorningInvitation(scheduledAt: origin.addingTimeInterval(60), timeZoneIdentifier: "UTC", now: origin)
        #expect(MorningInvitationPayload(dictionary: invitation.payload.dictionary) == invitation.payload)
        #expect(MorningInvitationPayload(dictionary: [MorningInvitationPayload.occurrenceKey: invitation.id.uuidString]) == nil)
        var object = try #require(JSONSerialization.jsonObject(with: JSONEncoder().encode(invitation)) as? [String: Any])
        object["expiresAt"] = invitation.scheduledAt.timeIntervalSinceReferenceDate - 1
        let corrupt = try JSONSerialization.data(withJSONObject: object)
        #expect(throws: MorningInvitationError.invalidRecord) {
            try JSONDecoder().decode(MorningInvitation.self, from: corrupt)
        }
    }
}
