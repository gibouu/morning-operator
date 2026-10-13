import Foundation

// The short opening of a morning (issue #28): one greeting, facts the prepared briefing
// already holds, then an explicit choice. Nothing here reads a source, calls a model or
// speaks. Counts, a precipitation forecast and a sender share are inputs: no adapter
// supplies them today, and without an input nothing is said about them.

/// What the person can do after the opening. The app renders and handles these values;
/// it never recovers the choice from the sentence.
public enum MorningOpeningChoice: String, Sendable, Equatable, CaseIterable {
    case brief, ritual, stop
}

public enum MorningOpeningProvider: String, Sendable, Equatable, CaseIterable {
    case unreadMessages, unreadEmail, missedCalls
}

/// One provider's count. A provider that was not read is `unavailable`, never `available(0)`.
public enum MorningOpeningCount: Sendable, Equatable {
    /// A verified count, zero included.
    case available(Int)
    /// A count that was read but is no longer current. It is announced as out of date, without a number.
    case stale
    /// Not connected, denied or failed. Nothing is said and nothing is shown.
    case unavailable
}

/// A forecast for the hours ahead, from a source that provides one. The current-conditions
/// snapshot is not such a source, so the umbrella sentence needs this explicit input.
public struct MorningPrecipitationForecast: Sendable, Equatable {
    /// Chance of precipitation between retrieval and `windowEnd`, from 0 to 1.
    public let chance: Double
    public let windowEnd: Date
    public let expiresAt: Date

    public init(chance: Double, windowEnd: Date, expiresAt: Date) {
        self.chance = chance; self.windowEnd = windowEnd; self.expiresAt = expiresAt
    }
}

/// Senders absent from the contacts shared with the app. A percentage needs the total.
public struct MorningUnknownSenderShare: Sendable, Equatable {
    public let unknownSenders: Int
    public let totalSenders: Int?

    public init(unknownSenders: Int, totalSenders: Int?) {
        self.unknownSenders = unknownSenders; self.totalSenders = totalSenders
    }
}

public struct MorningOpeningSegment: Identifiable, Sendable, Equatable {
    public enum Source: String, Sendable, Equatable {
        case greeting, weather, umbrella, calendar, count, unknownSenders, choice
    }
    public let id: String
    public let source: Source
    public let text: String
}

public struct MorningOpening: Sendable, Equatable {
    public let segments: [MorningOpeningSegment]
    /// The choices the closing question offers, in the order it names them.
    public let choices: [MorningOpeningChoice]
    /// The one string for both the screen and speech.
    public let text: String
    public var displayText: String { text }
    public var spokenText: String { text }
}

public enum MorningOpeningComposer {
    /// The umbrella sentence needs at least this chance of precipitation.
    public static let umbrellaMinimumChance = 0.5

    /// Deterministic. The language is the one the briefing was prepared in, so the opening
    /// and the facts it quotes cannot disagree. A briefing section is quoted only while it
    /// is fresh at `now`; an expired one is announced as out of date.
    public static func compose(briefing: PreparedMorningBriefing, at now: Date, timeZoneIdentifier: String,
                               counts: [MorningOpeningProvider: MorningOpeningCount] = [:],
                               precipitation: MorningPrecipitationForecast? = nil,
                               unknownSenders: MorningUnknownSenderShare? = nil) -> MorningOpening {
        let locale = Locale(identifier: briefing.localeIdentifier)
        let bundle = languageBundle(for: locale)
        let zone = TimeZone(identifier: briefing.timeZoneIdentifier)
        let inWindow = now.timeIntervalSinceReferenceDate.isFinite && zone != nil
            && zone == TimeZone(identifier: timeZoneIdentifier)
            && now >= briefing.preparedAt && now >= briefing.dayStart && now < briefing.dayEnd
        func fact(_ section: MorningBriefingSection) -> SectionFact {
            switch section.status {
            case .notConfigured: return .silent
            case .denied, .unavailable: return .unavailable
            case .stale: return .stale
            case .fresh:
                guard inWindow, let validUntil = section.validUntil, now < validUntil,
                      let first = section.segments.first else { return .stale }
                return .fresh(first.text)
            }
        }
        var segments: [MorningOpeningSegment] = []
        func add(_ id: String, _ source: MorningOpeningSegment.Source, _ text: String) {
            segments.append(.init(id: id, source: source, text: text))
        }
        add("greeting", .greeting, String(localized: "Good morning.", bundle: bundle, locale: locale))

        let weather = fact(briefing.weather), calendar = fact(briefing.calendar)
        switch weather {
        case .fresh(let text): add("weather", .weather, text)
        case .stale: add("weather", .weather, String(localized: "The weather is out of date.", bundle: bundle, locale: locale))
        case .unavailable: add("weather", .weather, String(localized: "The weather is unavailable.", bundle: bundle, locale: locale))
        case .silent: break
        }
        if let precipitation, let zone, inWindow,
           precipitation.chance.isFinite, (umbrellaMinimumChance...1).contains(precipitation.chance),
           precipitation.windowEnd.timeIntervalSinceReferenceDate.isFinite,
           precipitation.expiresAt.timeIntervalSinceReferenceDate.isFinite,
           now < precipitation.expiresAt, now < precipitation.windowEnd, precipitation.windowEnd <= briefing.dayEnd {
            let formatter = DateFormatter()
            formatter.locale = locale; formatter.timeZone = zone
            formatter.dateStyle = .none; formatter.timeStyle = .short
            let time = formatter.string(from: precipitation.windowEnd)
            add("umbrella", .umbrella,
                String(localized: "Rain is likely before \(time). Take an umbrella.", bundle: bundle, locale: locale))
        }
        switch calendar {
        case .fresh(let text): add("calendar", .calendar, text)
        case .stale: add("calendar", .calendar, String(localized: "The calendar is out of date.", bundle: bundle, locale: locale))
        case .unavailable: add("calendar", .calendar, String(localized: "The calendar is unavailable.", bundle: bundle, locale: locale))
        case .silent: break
        }

        for provider in MorningOpeningProvider.allCases {
            let text: String
            switch (provider, counts[provider] ?? .unavailable) {
            case (_, .unavailable): continue
            // A negative count is not a count: treat it as not read.
            case (_, .available(let count)) where count < 0: continue
            case (.unreadMessages, .available(let count)):
                text = String(localized: "\(count) unread messages.", bundle: bundle, locale: locale)
            case (.unreadEmail, .available(let count)):
                text = String(localized: "\(count) unread emails.", bundle: bundle, locale: locale)
            case (.missedCalls, .available(let count)):
                text = String(localized: "\(count) missed calls.", bundle: bundle, locale: locale)
            case (.unreadMessages, .stale):
                text = String(localized: "The unread message count is out of date.", bundle: bundle, locale: locale)
            case (.unreadEmail, .stale):
                text = String(localized: "The unread email count is out of date.", bundle: bundle, locale: locale)
            case (.missedCalls, .stale):
                text = String(localized: "The missed call count is out of date.", bundle: bundle, locale: locale)
            }
            add("count.\(provider.rawValue)", .count, text)
        }

        if let share = unknownSenders, let total = share.totalSenders, total > 0,
           (0...total).contains(share.unknownSenders) {
            let percent = Int((Double(share.unknownSenders) / Double(total) * 100).rounded())
            add("unknownSenders", .unknownSenders,
                String(localized: "\(percent)% of senders are not in the contacts shared with this app.",
                       bundle: bundle, locale: locale))
        }

        // The brief is offered only when it has something current to read.
        let hasBrief = [weather, calendar].contains { if case .fresh = $0 { true } else { false } }
        let choices: [MorningOpeningChoice] = hasBrief ? [.brief, .ritual, .stop] : [.ritual, .stop]
        add("choice", .choice, hasBrief
            ? String(localized: "Would you like to hear your briefing, start your routine, or stop?", bundle: bundle, locale: locale)
            : String(localized: "Would you like to start your routine, or stop?", bundle: bundle, locale: locale))
        return .init(segments: segments, choices: choices, text: segments.map(\.text).joined(separator: " "))
    }

    private enum SectionFact: Equatable {
        case fresh(String), stale, unavailable, silent
    }

    /// The catalog table for the briefing's language rather than the process language.
    private static func languageBundle(for locale: Locale) -> Bundle {
        let code = locale.language.languageCode?.identifier == "fr" ? "fr" : "en"
        guard let path = Bundle.module.path(forResource: code, ofType: "lproj"),
              let bundle = Bundle(path: path) else { return .module }
        return bundle
    }
}

/// Why the opening might play. Only an explicit morning start may play it.
public enum MorningOpeningTrigger: String, Sendable, Equatable, CaseIterable {
    case morningStart, settingsPreview, appLaunch, dataRefresh, tabSwitch
}

/// Remembers which morning session was greeted. It holds a session identifier only, so
/// saving and reading it back does not depend on the interface language.
///
/// The greeting plays when, and only when, an explicit morning start asks for a session
/// that was not the last one greeted. A preview, a launch, a refresh or a tab switch never
/// plays it and never changes this value. Only two things reset it: a morning start with a
/// different session identifier, or `reset()`.
public struct MorningGreetingState: Codable, Sendable, Equatable {
    public private(set) var greetedSessionID: UUID?

    public init() {}

    /// True exactly once per session. The caller plays the opening only on true.
    public mutating func claimPlayback(for trigger: MorningOpeningTrigger, sessionID: UUID) -> Bool {
        guard trigger == .morningStart, greetedSessionID != sessionID else { return false }
        greetedSessionID = sessionID
        return true
    }

    /// For local forgetting: the next morning start greets again.
    public mutating func reset() { greetedSessionID = nil }
}
