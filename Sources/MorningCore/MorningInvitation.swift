import Foundation

public enum MorningInvitationError: LocalizedError, Sendable, Equatable {
    case futureDateRequired, invalidTimeZone, invalidRecord

    public var errorDescription: String? {
        switch self {
        case .futureDateRequired: String(localized: "Choose a time in the future for your invitation.", bundle: .module)
        case .invalidTimeZone: String(localized: "Choose a valid time zone for your invitation.", bundle: .module)
        case .invalidRecord: String(localized: "The saved invitation could not be read safely. Cancel it before creating another.", bundle: .module)
        }
    }
}

/// A single absolute occurrence. Its ID also versions a replacement schedule.
/// The time zone is a display label, not a rule that moves the instant when travelling.
public struct MorningInvitation: Codable, Sendable, Equatable, Identifiable {
    public enum Disposition: String, Codable, Sendable, Equatable { case enabled, cancelled, consumed, expired }

    public let id: UUID
    public let scheduledAt: Date
    public let timeZoneIdentifier: String
    public let expiresAt: Date
    public private(set) var disposition: Disposition
    public private(set) var consumedAt: Date?

    public var payload: MorningInvitationPayload { .init(occurrenceID: id) }

    public init(id: UUID = UUID(), scheduledAt: Date, timeZoneIdentifier: String,
                now: Date = Date()) throws {
        guard scheduledAt.timeIntervalSince1970.isFinite, now.timeIntervalSince1970.isFinite,
              scheduledAt > now else { throw MorningInvitationError.futureDateRequired }
        guard TimeZone(identifier: timeZoneIdentifier) != nil else { throw MorningInvitationError.invalidTimeZone }
        self.id = id
        // Calendar notification triggers use whole seconds. Never round an occurrence earlier.
        self.scheduledAt = Date(timeIntervalSince1970: ceil(scheduledAt.timeIntervalSince1970))
        self.timeZoneIdentifier = timeZoneIdentifier
        expiresAt = self.scheduledAt.addingTimeInterval(2 * 60 * 60)
        guard expiresAt.timeIntervalSince1970.isFinite,
              expiresAt.timeIntervalSince(self.scheduledAt) == 2 * 60 * 60 else {
            throw MorningInvitationError.futureDateRequired
        }
        disposition = .enabled
        consumedAt = nil
    }

    public func isEligible(for payload: MorningInvitationPayload, at date: Date) -> Bool {
        payload.schemaVersion == MorningInvitationPayload.currentSchemaVersion && payload.occurrenceID == id &&
        disposition == .enabled && date.timeIntervalSince1970.isFinite && date >= scheduledAt && date < expiresAt
    }

    @discardableResult
    public mutating func consume(_ payload: MorningInvitationPayload, at date: Date) -> Bool {
        guard isEligible(for: payload, at: date) else { return false }
        disposition = .consumed
        consumedAt = date
        return true
    }

    public mutating func cancel() {
        disposition = .cancelled
        consumedAt = nil
    }

    @discardableResult
    public mutating func expire(at date: Date) -> Bool {
        guard disposition == .enabled, date >= expiresAt else { return false }
        disposition = .expired
        return true
    }

    private enum CodingKeys: String, CodingKey {
        case id, scheduledAt, timeZoneIdentifier, expiresAt, disposition, consumedAt
    }

    public init(from decoder: any Decoder) throws {
        let values = try decoder.container(keyedBy: CodingKeys.self)
        id = try values.decode(UUID.self, forKey: .id)
        scheduledAt = try values.decode(Date.self, forKey: .scheduledAt)
        timeZoneIdentifier = try values.decode(String.self, forKey: .timeZoneIdentifier)
        expiresAt = try values.decode(Date.self, forKey: .expiresAt)
        disposition = try values.decode(Disposition.self, forKey: .disposition)
        consumedAt = try values.decodeIfPresent(Date.self, forKey: .consumedAt)
        guard scheduledAt.timeIntervalSince1970.isFinite, expiresAt.timeIntervalSince1970.isFinite,
              expiresAt.timeIntervalSince(scheduledAt) == 2 * 60 * 60,
              TimeZone(identifier: timeZoneIdentifier) != nil else { throw MorningInvitationError.invalidRecord }
        if disposition == .consumed {
            guard let consumedAt, consumedAt >= scheduledAt, consumedAt < expiresAt else {
                throw MorningInvitationError.invalidRecord
            }
        } else if consumedAt != nil { throw MorningInvitationError.invalidRecord }
    }
}

/// Contains no routine, calendar or personal text. The occurrence ID changes on every edit.
public struct MorningInvitationPayload: Codable, Sendable, Equatable {
    public static let currentSchemaVersion = 1
    public static let occurrenceKey = "moreInvitationOccurrenceID"
    public static let schemaKey = "moreInvitationSchemaVersion"

    public let occurrenceID: UUID
    public let schemaVersion: Int

    public init(occurrenceID: UUID, schemaVersion: Int = currentSchemaVersion) {
        self.occurrenceID = occurrenceID
        self.schemaVersion = schemaVersion
    }

    public var dictionary: [String: String] {
        [Self.occurrenceKey: occurrenceID.uuidString, Self.schemaKey: String(schemaVersion)]
    }

    public init?(dictionary: [String: String]) {
        guard dictionary[Self.schemaKey] == String(Self.currentSchemaVersion),
              let raw = dictionary[Self.occurrenceKey], let id = UUID(uuidString: raw) else { return nil }
        self.init(occurrenceID: id)
    }
}
