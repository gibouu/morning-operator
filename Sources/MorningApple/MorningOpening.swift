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
/// snapshot is not such a source, so the umbrella sentence needs this explicit input. It
/// carries no precipitation type, so the sentence says precipitation, not rain.
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
    /// is fresh at `now`; an expired one is announced as out of date. Pass `offersBrief:
    /// false` once the recap could not be read: the question and the choices then leave it out.
    public static func compose(briefing: PreparedMorningBriefing, at now: Date, timeZoneIdentifier: String,
                               counts: [MorningOpeningProvider: MorningOpeningCount] = [:],
                               precipitation: MorningPrecipitationForecast? = nil,
                               unknownSenders: MorningUnknownSenderShare? = nil,
                               offersBrief: Bool = true) -> MorningOpening {
        let locale = Locale(identifier: briefing.localeIdentifier)
        let phrases = MorningOpeningPhrases(french: locale.language.languageCode?.identifier == "fr")
        let zone = TimeZone(identifier: briefing.timeZoneIdentifier)
        let inWindow = now.timeIntervalSinceReferenceDate.isFinite && zone != nil
            && zone == TimeZone(identifier: timeZoneIdentifier)
            && now >= briefing.preparedAt && now >= briefing.dayStart && now < briefing.dayEnd
        func fact(_ section: MorningBriefingSection) -> SectionFact {
            switch section.status {
            case .notConfigured: return .silent
            case .denied, .unavailable, .missing: return .unavailable
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
        add("greeting", .greeting, phrases.greeting)

        let weather = fact(briefing.weather), calendar = fact(briefing.calendar)
        switch weather {
        case .fresh(let text): add("weather", .weather, text)
        case .stale: add("weather", .weather, phrases.weatherStale)
        case .unavailable: add("weather", .weather, phrases.weatherUnavailable)
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
            add("umbrella", .umbrella, phrases.umbrella(before: time))
        }
        switch calendar {
        case .fresh(let text): add("calendar", .calendar, text)
        case .stale: add("calendar", .calendar, phrases.calendarStale)
        case .unavailable: add("calendar", .calendar, phrases.calendarUnavailable)
        case .silent: break
        }

        for provider in MorningOpeningProvider.allCases {
            let text: String
            switch counts[provider] ?? .unavailable {
            case .unavailable: continue
            // A negative count is not a count: treat it as not read.
            case .available(let count) where count < 0: continue
            case .available(let count): text = phrases.count(count, provider)
            case .stale: text = phrases.staleCount(provider)
            }
            add("count.\(provider.rawValue)", .count, text)
        }

        if let share = unknownSenders, let total = share.totalSenders, total > 0,
           (0...total).contains(share.unknownSenders) {
            let percent = Int((Double(share.unknownSenders) / Double(total) * 100).rounded())
            add("unknownSenders", .unknownSenders, phrases.unknownSenders(percent: percent))
        }

        // The brief is offered only when it has something current to read. Sleep is not
        // quoted in the opening, but a brief that holds a current night is still a brief.
        let hasBrief = offersBrief
            && [weather, calendar, fact(briefing.sleep)].contains { if case .fresh = $0 { true } else { false } }
        let choices: [MorningOpeningChoice] = hasBrief ? [.brief, .ritual, .stop] : [.ritual, .stop]
        add("choice", .choice, phrases.choice(withBrief: hasBrief))
        return .init(segments: segments, choices: choices, text: segments.map(\.text).joined(separator: " "))
    }

    private enum SectionFact: Equatable {
        case fresh(String), stale, unavailable, silent
    }
}

/// Deterministic opening sentences for each supported language, explicit like
/// `MorningBriefingPhrases` and for the same reason: the script is in the briefing's
/// language whatever the device language is, and is testable on any toolchain.
private struct MorningOpeningPhrases {
    let french: Bool

    var greeting: String { french ? "Bonjour." : "Good morning." }
    var weatherStale: String { french ? "La météo n’est plus à jour." : "The weather is out of date." }
    var weatherUnavailable: String { french ? "La météo n’est pas disponible." : "The weather is unavailable." }
    var calendarStale: String { french ? "Le calendrier n’est plus à jour." : "The calendar is out of date." }
    var calendarUnavailable: String { french ? "Le calendrier n’est pas disponible." : "The calendar is unavailable." }

    func umbrella(before time: String) -> String {
        french ? "Des précipitations sont probables avant \(time). Prenez un parapluie."
            : "Precipitation is likely before \(time). Take an umbrella."
    }
    func count(_ count: Int, _ provider: MorningOpeningProvider) -> String {
        if french {
            // French counts zero as singular.
            let one = count < 2
            switch provider {
            case .unreadMessages: return one ? "\(count) message non lu." : "\(count) messages non lus."
            case .unreadEmail: return one ? "\(count) e-mail non lu." : "\(count) e-mails non lus."
            case .missedCalls: return one ? "\(count) appel manqué." : "\(count) appels manqués."
            }
        }
        let one = count == 1
        switch provider {
        case .unreadMessages: return "\(count) unread \(one ? "message" : "messages")."
        case .unreadEmail: return "\(count) unread \(one ? "email" : "emails")."
        case .missedCalls: return "\(count) missed \(one ? "call" : "calls")."
        }
    }
    func staleCount(_ provider: MorningOpeningProvider) -> String {
        switch provider {
        case .unreadMessages:
            french ? "Le nombre de messages non lus n’est plus à jour." : "The unread message count is out of date."
        case .unreadEmail:
            french ? "Le nombre d’e-mails non lus n’est plus à jour." : "The unread email count is out of date."
        case .missedCalls:
            french ? "Le nombre d’appels manqués n’est plus à jour." : "The missed call count is out of date."
        }
    }
    func unknownSenders(percent: Int) -> String {
        french ? "\(percent) % des expéditeurs ne figurent pas dans les contacts partagés avec cette app."
            : "\(percent)% of senders are not in the contacts shared with this app."
    }
    func choice(withBrief: Bool) -> String {
        if french {
            return withBrief ? "Voulez-vous écouter votre récap, lancer votre routine ou arrêter ?"
                : "Voulez-vous lancer votre routine ou arrêter ?"
        }
        return withBrief ? "Would you like to hear your briefing, start your routine, or stop?"
            : "Would you like to start your routine, or stop?"
    }
}

/// Why the opening might play. Only an explicit morning start may play it.
public enum MorningOpeningTrigger: String, Sendable, Equatable, CaseIterable {
    case morningStart, settingsPreview, appLaunch, dataRefresh, tabSwitch
}

/// Remembers which morning sessions were greeted. It holds session identifiers only, so
/// saving and reading it back does not depend on the interface language.
///
/// The greeting plays when, and only when, an explicit morning start asks for a session
/// that was never greeted. A preview, a launch, a refresh or a tab switch never plays it
/// and never changes this value. A new morning is a new session identifier; an earlier
/// session stays greeted when a later one starts. Only `reset()` forgets: it is the one
/// way a session can be greeted a second time. One identifier is kept per greeted morning.
public struct MorningGreetingState: Codable, Sendable, Equatable {
    public private(set) var greetedSessionIDs: Set<UUID> = []

    public init() {}

    /// True exactly once per session. The caller plays the opening only on true.
    public mutating func claimPlayback(for trigger: MorningOpeningTrigger, sessionID: UUID) -> Bool {
        guard trigger == .morningStart else { return false }
        return greetedSessionIDs.insert(sessionID).inserted
    }

    /// For local forgetting: the next morning start greets again.
    public mutating func reset() { greetedSessionIDs = [] }
}
