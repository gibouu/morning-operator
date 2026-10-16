import Foundation

/// An app the person names in a Shortcuts automation. iOS lets an automation fire for any
/// installed app but never tells this app which apps exist, so the name comes from that
/// automation (a suggested name or one the person typed). It is not a bundle identifier.
public struct ObservedApp: Codable, Sendable, Identifiable, Hashable {
    public static let maximumNameLength = 60

    /// Case, accent and spacing-insensitive, so "whatsapp" and "WhatsApp" are one app.
    public let id: String
    public let displayName: String

    public init?(name: String) {
        let trimmed = name.split(whereSeparator: \.isWhitespace).joined(separator: " ")
        guard (1...Self.maximumNameLength).contains(trimmed.count),
              trimmed.unicodeScalars.contains(where: CharacterSet.letters.union(.decimalDigits).contains),
              !trimmed.unicodeScalars.contains(where: CharacterSet.controlCharacters.contains) else { return nil }
        let key = Self.key(for: trimmed)
        id = key
        // A typed name that matches a suggestion uses the suggestion's spelling.
        displayName = Self.suggested.first { $0.id == key }?.displayName ?? trimmed
    }

    private init(known name: String) {
        id = Self.key(for: name); displayName = name
    }

    public static func key(for name: String) -> String {
        name.folding(options: [.caseInsensitive, .diacriticInsensitive], locale: Locale(identifier: "en_US_POSIX"))
            .split(whereSeparator: \.isWhitespace).joined(separator: " ")
    }

    public static let instagram = ObservedApp(known: "Instagram")
    public static let tiktok = ObservedApp(known: "TikTok")
    public static let snapchat = ObservedApp(known: "Snapchat")

    /// Suggestions only; any other name is accepted. Ordered for the Shortcuts picker.
    public static let suggested: [ObservedApp] = [
        "WhatsApp", "Messages", "Mail", "Gmail", "Outlook", "Instagram", "TikTok", "Snapchat",
        "Facebook", "Messenger", "X", "Threads", "LinkedIn", "Reddit", "YouTube", "Netflix",
        "Spotify", "Safari", "Chrome", "Google", "Calendar", "Notes", "Reminders", "Photos",
        "Camera", "Maps", "Weather", "News", "Telegram", "Signal", "Discord", "Slack",
        "Teams", "Pinterest", "BeReal", "Twitch", "Duolingo", "Chess.com", "Lichess", "Strava",
        "Music", "Podcasts", "Books", "Settings", "Shortcuts", "App Store", "Phone", "FaceTime",
        "Clock", "Files", "Wallet", "Health", "Fitness", "Amazon", "Uber", "Vinted", "Le Monde"
    ].map(ObservedApp.init(known:))

    /// Older journals stored a lowercase case name ("instagram"); a name decodes the same way.
    public init(from decoder: any Decoder) throws {
        let name = try decoder.singleValueContainer().decode(String.self)
        guard let app = ObservedApp(name: name) else {
            throw DecodingError.dataCorrupted(.init(codingPath: decoder.codingPath, debugDescription: "Invalid app name."))
        }
        self = app
    }

    public func encode(to encoder: any Encoder) throws {
        var container = encoder.singleValueContainer()
        try container.encode(displayName)
    }

    public static func == (lhs: Self, rhs: Self) -> Bool { lhs.id == rhs.id }
    public func hash(into hasher: inout Hasher) { hasher.combine(id) }
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
    public var coverageDescription: String {
        String(localized: "Observed Shortcuts events for configured apps only. These are not pickups or a complete device-usage log.", bundle: AppLanguage.bundle(for: .module), locale: AppLanguage.locale)
    }
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
        // Only apps that actually appear; no zero is asserted for apps without automations.
        var seen: [ObservedApp] = []
        for entry in entries where !seen.contains(entry.app) { seen.append(entry.app) }
        let unsorted: [ObservedAppEntryCount] = seen.map { app in
            ObservedAppEntryCount(app: app, count: entries.filter { $0.app == app }.count)
        }
        let counts = unsorted.sorted { (left: ObservedAppEntryCount, right: ObservedAppEntryCount) -> Bool in
            if left.count != right.count { return left.count > right.count }
            return left.app.displayName < right.app.displayName
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

    /// Apps whose "closed" event keeps arriving within two seconds of "opened" — usually an
    /// Is Closed automation that also has Is Opened selected. Their times cannot place the app
    /// on a recording, so the setup screen points them out.
    public func appsClosingRightAfterOpening(minimumPairs: Int = 3) -> [ObservedApp] {
        var quick: [ObservedApp: Int] = [:]
        var exits: [ObservedApp: Int] = [:]
        for (index, event) in events.enumerated() where event.kind == .exited {
            exits[event.app, default: 0] += 1
            guard index > 0 else { continue }
            let previous = events[index - 1]
            if previous.kind == .entered, previous.app == event.app,
               event.observedAt.timeIntervalSince(previous.observedAt) < 2 { quick[event.app, default: 0] += 1 }
        }
        return quick.filter { app, count in count >= minimumPairs && Double(count) >= Double(exits[app] ?? 0) * 0.8 }
            .keys.sorted { $0.displayName < $1.displayName }
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
