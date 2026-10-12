import Foundation

public enum ObservationRecordingContextError: Error, LocalizedError, Sendable, Equatable {
    case invalidStartDate, invalidTimeZone

    public var errorDescription: String? {
        switch self {
        case .invalidStartDate: "The recording start date is invalid."
        case .invalidTimeZone: "The recording time zone is invalid."
        }
    }
}

/// Local acquisition metadata captured when the native recording output acknowledges its
/// start. It is not a file creation date, import date, physical pickup, or a guarantee that
/// media PTS zero aligns exactly with this wall-clock instant. Imported/legacy media has no
/// recording context unless the caller actually retained this native session metadata.
public struct ObservationRecordingContext: Codable, Identifiable, Equatable, Sendable {
    public let id: UUID
    public let startedAt: Date
    public let timeZoneIdentifier: String

    public init(id: UUID = UUID(), startedAt: Date, timeZoneIdentifier: String) throws {
        guard startedAt.timeIntervalSinceReferenceDate.isFinite else {
            throw ObservationRecordingContextError.invalidStartDate
        }
        guard !timeZoneIdentifier.isEmpty, TimeZone(identifier: timeZoneIdentifier) != nil else {
            throw ObservationRecordingContextError.invalidTimeZone
        }
        self.id = id
        self.startedAt = startedAt
        self.timeZoneIdentifier = timeZoneIdentifier
    }

    private enum CodingKeys: String, CodingKey { case id, startedAt, timeZoneIdentifier }
    public init(from decoder: any Decoder) throws {
        let values = try decoder.container(keyedBy: CodingKeys.self)
        try self.init(id: values.decode(UUID.self, forKey: .id),
                      startedAt: values.decode(Date.self, forKey: .startedAt),
                      timeZoneIdentifier: values.decode(String.self, forKey: .timeZoneIdentifier))
    }
}
