import Foundation

public enum ObservationRecordingContextError: Error, LocalizedError, Sendable, Equatable {
    case invalidStartDate, invalidTimeZone

    public var errorDescription: String? {
        switch self {
        case .invalidStartDate: String(localized: "The recording start date is invalid.", bundle: .module)
        case .invalidTimeZone: String(localized: "The recording time zone is invalid.", bundle: .module)
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
    /// When MORE's own scene was in front during this recording, if the app established it.
    /// Nil for recordings saved before this was recorded and whenever it stayed unknown.
    public let ownInterfaceIntervals: OwnInterfaceIntervals?

    public init(id: UUID = UUID(), startedAt: Date, timeZoneIdentifier: String,
                ownInterfaceIntervals: OwnInterfaceIntervals? = nil) throws {
        guard startedAt.timeIntervalSinceReferenceDate.isFinite else {
            throw ObservationRecordingContextError.invalidStartDate
        }
        guard !timeZoneIdentifier.isEmpty, TimeZone(identifier: timeZoneIdentifier) != nil else {
            throw ObservationRecordingContextError.invalidTimeZone
        }
        self.id = id
        self.startedAt = startedAt
        self.timeZoneIdentifier = timeZoneIdentifier
        self.ownInterfaceIntervals = ownInterfaceIntervals
    }

    /// The same session with its own-interface spans set. The start instant is unchanged.
    public func withOwnInterfaceIntervals(_ intervals: OwnInterfaceIntervals?) -> Self {
        // The stored fields were validated when this value was created.
        (try? Self(id: id, startedAt: startedAt, timeZoneIdentifier: timeZoneIdentifier,
                   ownInterfaceIntervals: intervals)) ?? self
    }

    private enum CodingKeys: String, CodingKey { case id, startedAt, timeZoneIdentifier, ownInterfaceIntervals }
    public init(from decoder: any Decoder) throws {
        let values = try decoder.container(keyedBy: CodingKeys.self)
        // Spans that cannot be read are treated as unknown. They must not cost the recording
        // its start date or strand it in recovery; the text rule still guards its frames.
        try self.init(id: values.decode(UUID.self, forKey: .id),
                      startedAt: values.decode(Date.self, forKey: .startedAt),
                      timeZoneIdentifier: values.decode(String.self, forKey: .timeZoneIdentifier),
                      ownInterfaceIntervals: try? values.decodeIfPresent(OwnInterfaceIntervals.self,
                                                                         forKey: .ownInterfaceIntervals))
    }
}
