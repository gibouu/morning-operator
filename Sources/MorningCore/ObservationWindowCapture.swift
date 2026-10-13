import Foundation

public enum ObservationWindowCaptureError: Error, Equatable, Sendable { case invalid }

/// What one native recording captured of one scheduled morning of a learning window: the
/// interval the window expected and the interval the recording actually ran. A learning
/// window writes it once, when the saved recording is declared to it.
///
/// The actual interval is when a recording was running, from the start the recording output
/// acknowledged to that start plus the length of the finalized movie. It says nothing about
/// what the person did: a locked phone, a blank screen or an unread page inside it is still
/// only recorded time, and time outside it is unknown, never a morning without activity.
public struct ObservationWindowCapture: Codable, Equatable, Sendable {
    public let windowID: UUID
    /// The scheduled morning, as a day in the window's time zone.
    public let dayKey: String
    public let timeZoneIdentifier: String
    public let expectedStart: Date
    public let expectedEnd: Date
    public let actualStart: Date
    public let actualEnd: Date
    /// When the window accepted the recording, never before the recording ended. A window that was stopped at or before this
    /// instant does not count it, whatever else this value says.
    public let declaredAt: Date

    public init(windowID: UUID, dayKey: String, timeZoneIdentifier: String, expectedStart: Date,
                expectedEnd: Date, actualStart: Date, actualEnd: Date, declaredAt: Date) throws {
        let instants = [expectedStart, expectedEnd, actualStart, actualEnd, declaredAt]
        guard instants.allSatisfy({ $0.timeIntervalSinceReferenceDate.isFinite }),
              expectedEnd > expectedStart, actualEnd > actualStart, declaredAt >= actualEnd,
              expectedEnd.timeIntervalSince(expectedStart) <= 24 * 60 * 60,
              actualEnd.timeIntervalSince(actualStart) <= 24 * 60 * 60,
              dayKey.utf8.count == 10, TimeZone(identifier: timeZoneIdentifier) != nil else {
            throw ObservationWindowCaptureError.invalid
        }
        self.windowID = windowID
        self.dayKey = dayKey
        self.timeZoneIdentifier = timeZoneIdentifier
        self.expectedStart = expectedStart
        self.expectedEnd = expectedEnd
        self.actualStart = actualStart
        self.actualEnd = actualEnd
        self.declaredAt = declaredAt
    }

    private enum CodingKeys: String, CodingKey {
        case windowID, dayKey, timeZoneIdentifier, expectedStart, expectedEnd, actualStart, actualEnd, declaredAt
    }
    public init(from decoder: any Decoder) throws {
        let values = try decoder.container(keyedBy: CodingKeys.self)
        try self.init(windowID: values.decode(UUID.self, forKey: .windowID),
                      dayKey: values.decode(String.self, forKey: .dayKey),
                      timeZoneIdentifier: values.decode(String.self, forKey: .timeZoneIdentifier),
                      expectedStart: values.decode(Date.self, forKey: .expectedStart),
                      expectedEnd: values.decode(Date.self, forKey: .expectedEnd),
                      actualStart: values.decode(Date.self, forKey: .actualStart),
                      actualEnd: values.decode(Date.self, forKey: .actualEnd),
                      declaredAt: values.decode(Date.self, forKey: .declaredAt))
    }
}
