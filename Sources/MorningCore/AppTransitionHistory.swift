import Foundation

public enum ObservedApp: String, Codable, CaseIterable, Sendable, Identifiable, Hashable {
    case instagram, tiktok, snapchat
    public var id: String { rawValue }
    public var displayName: String {
        switch self {
        case .instagram: "Instagram"
        case .tiktok: "TikTok"
        case .snapchat: "Snapchat"
        }
    }
}

public enum AppTransitionKind: String, Codable, Sendable { case entered, exited }
public enum AppTransitionSource: String, Codable, Sendable { case shortcut }

public enum AppTransitionError: LocalizedError, Sendable, Equatable {
    case invalidDate, invalidTimeZone, conflictingEventID
    public var errorDescription: String? {
        switch self {
        case .invalidDate: AppLanguage.localized("The app transition has an invalid timestamp.", bundle: .module)
        case .invalidTimeZone: AppLanguage.localized("The app transition has an invalid time zone.", bundle: .module)
        case .conflictingEventID: AppLanguage.localized("That event identifier already belongs to a different app transition.", bundle: .module)
        }
    }
}

/// A callback from a user-configured Shortcut, not an OS-wide app launch or pickup log.
public struct AppTransitionEvent: Codable, Identifiable, Sendable, Equatable {
    public let id: UUID
    public let app: ObservedApp
    public let kind: AppTransitionKind
    /// When the logging action observed the transition; delivery may lag the actual app switch.
    public let observedAt: Date
    public let timeZoneIdentifier: String
    public let source: AppTransitionSource

    public init(id: UUID = UUID(), app: ObservedApp, kind: AppTransitionKind,
                observedAt: Date = .now, timeZoneIdentifier: String = TimeZone.current.identifier,
                source: AppTransitionSource = .shortcut) throws {
        guard observedAt.timeIntervalSince1970.isFinite else { throw AppTransitionError.invalidDate }
        guard TimeZone(identifier: timeZoneIdentifier) != nil else { throw AppTransitionError.invalidTimeZone }
        self.id = id
        self.app = app
        self.kind = kind
        self.observedAt = observedAt
        self.timeZoneIdentifier = timeZoneIdentifier
        self.source = source
    }

    private enum CodingKeys: String, CodingKey { case id, app, kind, observedAt, timeZoneIdentifier, source }
    public init(from decoder: any Decoder) throws {
        let values = try decoder.container(keyedBy: CodingKeys.self)
        try self.init(id: values.decode(UUID.self, forKey: .id), app: values.decode(ObservedApp.self, forKey: .app),
                      kind: values.decode(AppTransitionKind.self, forKey: .kind),
                      observedAt: values.decode(Date.self, forKey: .observedAt),
                      timeZoneIdentifier: values.decode(String.self, forKey: .timeZoneIdentifier),
                      source: values.decode(AppTransitionSource.self, forKey: .source))
    }
}

public struct ObservedAppEntryCount: Identifiable, Sendable, Equatable {
    public let app: ObservedApp
    public let count: Int
    public var id: ObservedApp { app }
}

/// A return to an app after observing at least one other configured app.
/// Returns can overlap (A→B→A→B contains one return to A and one to B).
public struct ObservedAppReturn: Identifiable, Sendable, Equatable {
    public let id: UUID
    public let app: ObservedApp
    public let startedAt: Date
    public let returnedAt: Date
    public let interveningApps: [ObservedApp]
}

public struct AppTransitionDaySummary: Sendable, Equatable {
    public let dayKey: String
    public let eventCount: Int
    public let foregroundEntryCount: Int
    public let entryCounts: [ObservedAppEntryCount]
    /// Nil when entry timestamps tie, because their order cannot be established.
    public let observedSwitchCount: Int?
    public let returns: [ObservedAppReturn]?
    public var observedReturnCount: Int? { returns?.count }
    public var hasEvents: Bool { eventCount > 0 }
    /// Only configured automations contribute; an empty log does not prove zero device usage.
    public let coverageDescription = "Observed Shortcuts events for configured apps only. These are not pickups or a complete device-usage log."
}

public struct AppTransitionHistory: Codable, Sendable, Equatable {
    public private(set) var events: [AppTransitionEvent]

    public init(events: [AppTransitionEvent] = []) throws {
        self.events = []
        for event in events { _ = try append(event) }
    }

    /// A caller can retry the same event ID without counting it twice.
    @discardableResult
    public mutating func append(_ event: AppTransitionEvent) throws -> Bool {
        if let existing = events.first(where: { $0.id == event.id }) {
            guard existing == event else { throw AppTransitionError.conflictingEventID }
            return false
        }
        events.append(event)
        events.sort {
            $0.observedAt == $1.observedAt ? $0.id.uuidString < $1.id.uuidString : $0.observedAt < $1.observedAt
        }
        return true
    }

    public func summary(for date: Date, timeZoneIdentifier: String = TimeZone.current.identifier) throws -> AppTransitionDaySummary {
        let key = try Self.dayKey(date, timeZoneIdentifier: timeZoneIdentifier)
        // Preserve the local date captured with each event when the person travels.
        let dayEvents = try events.filter { try Self.dayKey($0.observedAt, timeZoneIdentifier: $0.timeZoneIdentifier) == key }
        let entries = dayEvents.filter { $0.kind == .entered }
        let counts = ObservedApp.allCases.map { app in
            ObservedAppEntryCount(app: app, count: entries.filter { $0.app == app }.count)
        }
        let tiedTimestamps = Set(entries.map(\.observedAt)).count != entries.count
        var switches = 0
        var returns: [ObservedAppReturn] = []
        var previousIndex: [ObservedApp: Int] = [:]
        for (index, entry) in entries.enumerated() {
            if index > 0, entries[index - 1].app != entry.app { switches += 1 }
            if let previous = previousIndex[entry.app] {
                let between = entries[(previous + 1)..<index].map(\.app).filter { $0 != entry.app }
                if !between.isEmpty {
                    returns.append(ObservedAppReturn(id: entry.id, app: entry.app,
                        startedAt: entries[previous].observedAt, returnedAt: entry.observedAt, interveningApps: between))
                }
            }
            previousIndex[entry.app] = index
        }
        return AppTransitionDaySummary(dayKey: key, eventCount: dayEvents.count,
            foregroundEntryCount: entries.count, entryCounts: counts,
            observedSwitchCount: tiedTimestamps ? nil : switches, returns: tiedTimestamps ? nil : returns)
    }

    private static func dayKey(_ date: Date, timeZoneIdentifier: String) throws -> String {
        guard date.timeIntervalSince1970.isFinite else { throw AppTransitionError.invalidDate }
        guard let zone = TimeZone(identifier: timeZoneIdentifier) else { throw AppTransitionError.invalidTimeZone }
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = zone
        let parts = calendar.dateComponents([.year, .month, .day], from: date)
        guard let year = parts.year, let month = parts.month, let day = parts.day else { throw AppTransitionError.invalidDate }
        return String(format: "%04d-%02d-%02d", year, month, day)
    }

    private enum CodingKeys: String, CodingKey { case events }
    public init(from decoder: any Decoder) throws {
        let values = try decoder.container(keyedBy: CodingKeys.self)
        try self.init(events: values.decode([AppTransitionEvent].self, forKey: .events))
    }
}
