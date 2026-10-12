import Foundation

public enum QuickCaptureKind: String, Codable, Sendable, CaseIterable {
    case dream, thought, reminder, calendarIdea
    public var displayName: String {
        switch self {
        case .dream: "Dream"
        case .thought: "Thought"
        case .reminder: "Reminder"
        case .calendarIdea: "Calendar idea"
        }
    }
}
public enum QuickCaptureSource: String, Codable, Sendable, CaseIterable {
    case typed, siri, voice, imported
}
public enum QuickCaptureError: Error, LocalizedError, Sendable, Equatable {
    case emptyText, invalidTimeZone, invalidDate
    public var errorDescription: String? {
        switch self {
        case .emptyText: "Add a few words before saving this capture."
        case .invalidTimeZone: "Choose a valid time zone for this request."
        case .invalidDate: "The requested date could not be understood."
        }
    }
}

/// A locally captured request. requestedDate expresses intent, not a committed calendar event,
/// a saved system reminder, or a guarantee that a notification has been scheduled.
public struct QuickCapture: Codable, Sendable, Identifiable, Equatable {
    public let id: UUID
    public let kind: QuickCaptureKind
    public let text: String
    public let createdAt: Date
    public let requestedDate: Date?
    public let timeZoneIdentifier: String
    public let source: QuickCaptureSource

    public init(id: UUID = UUID(), kind: QuickCaptureKind, text: String, createdAt: Date = Date(),
                requestedDate: Date? = nil, timeZoneIdentifier: String = TimeZone.current.identifier,
                source: QuickCaptureSource = .typed) throws {
        let text = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { throw QuickCaptureError.emptyText }
        guard TimeZone(identifier: timeZoneIdentifier) != nil else { throw QuickCaptureError.invalidTimeZone }
        guard createdAt.timeIntervalSince1970.isFinite,
              requestedDate.map({ $0.timeIntervalSince1970.isFinite }) ?? true else { throw QuickCaptureError.invalidDate }
        self.id = id
        self.kind = kind
        self.text = text
        self.createdAt = createdAt
        self.requestedDate = requestedDate
        self.timeZoneIdentifier = timeZoneIdentifier
        self.source = source
    }

    private enum CodingKeys: String, CodingKey { case id, kind, text, createdAt, requestedDate, timeZoneIdentifier, source }
    public init(from decoder: any Decoder) throws {
        let values = try decoder.container(keyedBy: CodingKeys.self)
        try self.init(id: values.decode(UUID.self, forKey: .id), kind: values.decode(QuickCaptureKind.self, forKey: .kind),
                      text: values.decode(String.self, forKey: .text), createdAt: values.decode(Date.self, forKey: .createdAt),
                      requestedDate: values.decodeIfPresent(Date.self, forKey: .requestedDate),
                      timeZoneIdentifier: values.decode(String.self, forKey: .timeZoneIdentifier),
                      source: values.decode(QuickCaptureSource.self, forKey: .source))
    }
}
