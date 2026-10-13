import Foundation

/// Availability is supplied by the explicit source coordinator. Missing data is
/// never converted into an empty calendar or a fabricated weather observation.
public enum MorningBriefingInput<Value: Sendable & Equatable>: Sendable, Equatable {
    case notConfigured
    case denied
    case unavailable
    case snapshot(Value)
}

public enum MorningBriefingSourceStatus: String, Sendable, Equatable {
    case notConfigured, denied, unavailable, fresh, stale
    /// The read worked as far as can be known and returned no record. Sleep only.
    case missing
}

public enum MorningBriefingSourceIssue: String, Sendable, Equatable {
    case notConfigured, permissionDenied, sourceUnavailable, expired
    case futureTimestamp, wrongDay, wrongTimeZone, invalidSelection, invalidSnapshot
    /// Sleep only. There is no "permission denied" among these on purpose: a health
    /// read that was not permitted looks exactly like `noRecord`.
    case unavailableOnDevice, notReadable, noRecord, olderRecord
}

public enum MorningBriefingTemperatureUnit: String, Codable, CaseIterable, Sendable, Equatable {
    case celsius, fahrenheit
}

public enum MorningBriefingError: Error, LocalizedError, Sendable, Equatable {
    case invalidDate, invalidTimeZone, unsupportedLocale, invalidPolicy

    public var errorDescription: String? {
        switch self {
        case .invalidDate: String(localized: "The briefing date could not be resolved.", bundle: .module)
        case .invalidTimeZone: String(localized: "Choose a valid time zone for this briefing.", bundle: .module)
        case .unsupportedLocale: String(localized: "Prepared briefings currently support English and French.", bundle: .module)
        case .invalidPolicy: String(localized: "The briefing freshness settings are invalid.", bundle: .module)
        }
    }
}

public struct MorningBriefingFreshnessPolicy: Sendable, Equatable {
    public let calendarMaximumAge: TimeInterval
    public let weatherMaximumAge: TimeInterval
    public let maximumCalendarEvents: Int
    /// How long one sleep read is used before it is read again. A watch can deliver the
    /// night some time after waking, so a read is not kept for the whole morning.
    public let sleepMaximumAge: TimeInterval

    public static let standard = Self(calendarMaximumAge: 300, weatherMaximumAge: 1_800,
                                      maximumCalendarEvents: 5)

    /// Invalid policies are rejected by prepare; event limits may be 1 through 5.
    public init(calendarMaximumAge: TimeInterval = 300, weatherMaximumAge: TimeInterval = 1_800,
                maximumCalendarEvents: Int = 5, sleepMaximumAge: TimeInterval = 1_800) {
        self.calendarMaximumAge = calendarMaximumAge
        self.weatherMaximumAge = weatherMaximumAge
        self.maximumCalendarEvents = maximumCalendarEvents
        self.sleepMaximumAge = sleepMaximumAge
    }
}

public struct MorningBriefingSegment: Identifiable, Sendable, Equatable {
    public enum Source: String, Sendable, Equatable { case introduction, calendar, weather, sleep }
    public let id: String
    public let source: Source
    /// This same sentence is displayed and sent to speech. There is no second
    /// generated or paraphrased version that can disagree with the visible facts.
    public let text: String
}

public struct MorningBriefingSection: Sendable, Equatable {
    public let status: MorningBriefingSourceStatus
    public let issue: MorningBriefingSourceIssue?
    public let statusText: String
    public let retrievedAt: Date?
    /// WeatherKit's conditions time, or the end of the recorded sleep window; nil for
    /// EventKit, which exposes no remote synchronization time for the local read.
    public let observationAt: Date?
    public let sourceLabels: [String]
    public let omissionCount: Int
    public let segments: [MorningBriefingSegment]
    /// A fresh section must be prepared again at this instant. This also accounts
    /// for event start/end boundaries, so "in progress" does not outlive an event.
    public let validUntil: Date?
    public var text: String { segments.map(\.text).joined(separator: " ") }
}

/// In-memory only: contains the exact prepared text and its source metadata. A
/// caller must check isCurrent before playback, and discard this value on reset.
public struct PreparedMorningBriefing: Identifiable, Sendable, Equatable {
    public let id: UUID
    public let preparedAt: Date
    public let dayStart: Date
    public let dayEnd: Date
    public let timeZoneIdentifier: String
    public let localeIdentifier: String
    public let temperatureUnit: MorningBriefingTemperatureUnit
    public let calendar: MorningBriefingSection
    public let weather: MorningBriefingSection
    /// Sleep duration, the one health observation. `notConfigured` when health is excluded.
    public let sleep: MorningBriefingSection
    /// The recorded night behind a fresh sleep section; nil in every other state.
    public let sleepObservation: SleepObservation?
    public let selectedCalendarIDs: Set<String>
    public let weatherLocation: WeatherLocation?
    public let weatherAttribution: WeatherAttributionInfo?
    public let segments: [MorningBriefingSegment]

    public var hasUsableFacts: Bool {
        calendar.status == .fresh || weather.status == .fresh || sleep.status == .fresh
    }
    public var displayText: String { segments.map(\.text).joined(separator: "\n") }
    public var spokenText: String { segments.map(\.text).joined(separator: " ") }
    public var validUntil: Date? {
        guard hasUsableFacts else { return nil }
        return ([dayEnd] + [calendar.validUntil, weather.validUntil, sleep.validUntil].compactMap { $0 }).min()
    }

    public func isCurrent(at date: Date, timeZoneIdentifier: String) -> Bool {
        guard date.timeIntervalSinceReferenceDate.isFinite,
              let preparedZone = TimeZone(identifier: self.timeZoneIdentifier),
              let currentZone = TimeZone(identifier: timeZoneIdentifier),
              preparedZone == currentZone, let validUntil else { return false }
        return date >= preparedAt && date >= dayStart && date < dayEnd && date < validUntil
    }
}

public enum MorningBriefingComposer {
    /// Deterministic English or French prose; the locale controls the language, dates,
    /// clocks and decimal formatting. This does not ask a model to summarize private data.
    public static func prepare(
        calendar inputCalendar: MorningBriefingInput<CalendarSnapshot>,
        weather inputWeather: MorningBriefingInput<WeatherObservationSnapshot>,
        sleep inputSleep: SleepBriefingInput = .excluded,
        for day: Date, at now: Date, timeZoneIdentifier: String,
        localeIdentifier: String = "en_US",
        temperatureUnit: MorningBriefingTemperatureUnit = .celsius,
        policy: MorningBriefingFreshnessPolicy = .standard
    ) throws -> PreparedMorningBriefing {
        guard day.timeIntervalSinceReferenceDate.isFinite, now.timeIntervalSinceReferenceDate.isFinite else {
            throw MorningBriefingError.invalidDate
        }
        guard let zone = TimeZone(identifier: timeZoneIdentifier) else { throw MorningBriefingError.invalidTimeZone }
        let locale = Locale(identifier: localeIdentifier)
        guard let phrases = MorningBriefingPhrases(locale: locale) else { throw MorningBriefingError.unsupportedLocale }
        guard policy.calendarMaximumAge.isFinite, policy.calendarMaximumAge > 0,
              policy.weatherMaximumAge.isFinite, policy.weatherMaximumAge > 0,
              policy.sleepMaximumAge.isFinite, policy.sleepMaximumAge > 0,
              (1...5).contains(policy.maximumCalendarEvents) else { throw MorningBriefingError.invalidPolicy }
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = zone
        let dayStart = calendar.startOfDay(for: day)
        guard let dayEnd = calendar.date(byAdding: .day, value: 1, to: dayStart), dayEnd > dayStart,
              now >= dayStart, now < dayEnd else {
            throw MorningBriefingError.invalidDate
        }
        var calendarSection = Self.calendarSection(inputCalendar, dayStart: dayStart, dayEnd: dayEnd,
            now: now, zone: zone, locale: locale, phrases: phrases, policy: policy)
        var weatherSection = Self.weatherSection(inputWeather, now: now, locale: locale, phrases: phrases,
            unit: temperatureUnit, policy: policy)
        var (sleepSection, sleepObservation) = Self.sleepSection(inputSleep, now: now, dayEnd: dayEnd,
            calendar: calendar, zone: zone, locale: locale, phrases: phrases, policy: policy)
        let hasFacts = calendarSection.status == .fresh || weatherSection.status == .fresh
            || sleepSection.status == .fresh
        // Configure sources in Settings, not in every spoken morning. A failed
        // configured source gets one short sentence only when another can help.
        calendarSection = withFailureSegment(calendarSection, source: .calendar, include: hasFacts)
        weatherSection = withFailureSegment(weatherSection, source: .weather, include: hasFacts)
        // Sleep that is excluded, not connected or impossible on this device is left out
        // of speech: it is a standing state, not news, and it must never sound like zero.
        // A missing, older or unreadable record is said in one plain sentence.
        let silentSleep: [MorningBriefingSourceIssue?] = [.notConfigured, .sourceUnavailable, .unavailableOnDevice]
        sleepSection = withFailureSegment(sleepSection, source: .sleep,
            include: hasFacts && !silentSleep.contains(sleepSection.issue))
        if sleepSection.status != .fresh { sleepObservation = nil }
        var segments: [MorningBriefingSegment] = []
        if hasFacts {
            let formatter = DateFormatter()
            formatter.locale = locale; formatter.timeZone = zone
            formatter.dateStyle = .full; formatter.timeStyle = .none
            segments.append(.init(id: "introduction", source: .introduction,
                text: phrases.introduction(formatter.string(from: day))))
            segments += calendarSection.segments + weatherSection.segments + sleepSection.segments
        }
        let weatherSnapshot: WeatherObservationSnapshot?
        if case .snapshot(let snapshot) = inputWeather { weatherSnapshot = snapshot } else { weatherSnapshot = nil }
        let selectedCalendarIDs: Set<String>
        if case .snapshot(let snapshot) = inputCalendar { selectedCalendarIDs = Set(snapshot.selectedCalendarIDs) }
        else { selectedCalendarIDs = [] }
        return .init(id: UUID(), preparedAt: now, dayStart: dayStart, dayEnd: dayEnd,
            timeZoneIdentifier: timeZoneIdentifier, localeIdentifier: localeIdentifier,
            temperatureUnit: temperatureUnit, calendar: calendarSection, weather: weatherSection,
            sleep: sleepSection, sleepObservation: sleepObservation,
            selectedCalendarIDs: selectedCalendarIDs,
            weatherLocation: weatherSnapshot?.location,
            weatherAttribution: weatherSection.status == .fresh ? weatherSnapshot?.attribution : nil,
            segments: segments)
    }

    private static func calendarSection(_ input: MorningBriefingInput<CalendarSnapshot>,
        dayStart: Date, dayEnd: Date, now: Date, zone: TimeZone, locale: Locale,
        phrases: MorningBriefingPhrases, policy: MorningBriefingFreshnessPolicy) -> MorningBriefingSection {
        guard case .snapshot(let snapshot) = input else { return missingSection(input, name: phrases.calendarName, phrases: phrases) }
        func invalid(_ issue: MorningBriefingSourceIssue, stale: Bool = false) -> MorningBriefingSection {
            section(status: stale ? .stale : .unavailable, issue: issue, name: phrases.calendarName,
                phrases: phrases, retrievedAt: snapshot.retrievedAt, sourceLabels: snapshot.sourceLabels)
        }
        guard snapshot.retrievedAt.timeIntervalSinceReferenceDate.isFinite,
              snapshot.dayStart.timeIntervalSinceReferenceDate.isFinite,
              snapshot.dayEnd.timeIntervalSinceReferenceDate.isFinite else { return invalid(.invalidSnapshot) }
        guard let snapshotZone = TimeZone(identifier: snapshot.timeZoneIdentifier), snapshotZone == zone else {
            return invalid(.wrongTimeZone)
        }
        guard snapshot.dayStart == dayStart, snapshot.dayEnd == dayEnd,
              now >= dayStart, now < dayEnd else { return invalid(.wrongDay) }
        guard snapshot.retrievedAt <= now else { return invalid(.futureTimestamp) }
        guard now.timeIntervalSince(snapshot.retrievedAt) < policy.calendarMaximumAge else {
            return invalid(.expired, stale: true)
        }
        let selectedIDs = Set(snapshot.selectedCalendarIDs)
        guard !selectedIDs.isEmpty, selectedIDs.count == snapshot.selectedCalendarIDs.count,
              !selectedIDs.contains("") else { return invalid(.invalidSelection) }
        guard Set(snapshot.events.map(\.id)).count == snapshot.events.count,
              snapshot.events.allSatisfy({ event in
            event.start.timeIntervalSinceReferenceDate.isFinite && event.end.timeIntervalSinceReferenceDate.isFinite &&
            event.end >= event.start && (!event.isAllDay || event.end > event.start) && selectedIDs.contains(event.calendarID)
        }) else { return invalid(.invalidSnapshot) }
        let remaining = snapshot.events.filter { event in
            // A zero-duration event is relevant until its start instant only.
            event.start < dayEnd && (event.end > dayStart || event.start == event.end && event.start >= dayStart) &&
                (event.isAllDay || event.end > now || event.start == event.end && event.start > now)
        }.sorted { first, second in
            func rank(_ event: CalendarEventSummary) -> Int { event.isAllDay ? 0 : (event.start <= now ? 1 : 2) }
            if rank(first) != rank(second) { return rank(first) < rank(second) }
            if first.start != second.start { return first.start < second.start }
            if first.id != second.id { return first.id < second.id }
            return first.title < second.title
        }
        let shown = Array(remaining.prefix(policy.maximumCalendarEvents))
        let formatter = DateFormatter()
        formatter.locale = locale; formatter.timeZone = zone
        formatter.dateStyle = .none; formatter.timeStyle = .short
        var texts = shown.map { event in
            let title = boundedTitle(event.title, phrases: phrases)
            if event.isAllDay { return endingSentence(phrases.allDay(title)) }
            if event.start <= now {
                let ending: String
                if event.end >= dayEnd {
                    let endFormatter = DateFormatter()
                    endFormatter.locale = locale; endFormatter.timeZone = zone
                    endFormatter.dateStyle = .medium; endFormatter.timeStyle = .short
                    ending = endFormatter.string(from: event.end)
                } else { ending = formatter.string(from: event.end) }
                return endingSentence(phrases.inProgress(ending, title))
            }
            return endingSentence(phrases.at(formatter.string(from: event.start), title))
        }
        if remaining.isEmpty { texts = [phrases.noRemainingEvents] }
        let omitted = remaining.count - shown.count
        if omitted > 0 { texts.append(phrases.more(omitted)) }
        let boundaries = remaining.flatMap { event -> [Date] in
            guard !event.isAllDay else { return [] }
            return [event.start, event.end].filter { $0 > now }
        }
        let expiry = ([snapshot.retrievedAt.addingTimeInterval(policy.calendarMaximumAge), dayEnd] + boundaries).min()
        return .init(status: .fresh, issue: nil, statusText: phrases.calendarStatus,
            retrievedAt: snapshot.retrievedAt, observationAt: nil, sourceLabels: snapshot.sourceLabels,
            omissionCount: omitted, segments: texts.enumerated().map {
                .init(id: "calendar.\($0.offset)", source: .calendar, text: $0.element)
            }, validUntil: expiry)
    }

    private static func weatherSection(_ input: MorningBriefingInput<WeatherObservationSnapshot>,
        now: Date, locale: Locale, phrases: MorningBriefingPhrases, unit: MorningBriefingTemperatureUnit,
        policy: MorningBriefingFreshnessPolicy) -> MorningBriefingSection {
        guard case .snapshot(let snapshot) = input else { return missingSection(input, name: phrases.weatherName, phrases: phrases) }
        let labels = [snapshot.attribution.serviceName, snapshot.location.displayName]
        func invalid(_ issue: MorningBriefingSourceIssue, stale: Bool = false) -> MorningBriefingSection {
            section(status: stale ? .stale : .unavailable, issue: issue, name: phrases.weatherName,
                phrases: phrases, retrievedAt: snapshot.retrievedAt, observationAt: snapshot.observationAt, sourceLabels: labels)
        }
        guard snapshot.retrievedAt.timeIntervalSinceReferenceDate.isFinite,
              snapshot.observationAt.timeIntervalSinceReferenceDate.isFinite,
              snapshot.temperatureCelsius.isFinite,
              snapshot.expiresAt?.timeIntervalSinceReferenceDate.isFinite != false else { return invalid(.invalidSnapshot) }
        guard snapshot.retrievedAt <= now, snapshot.observationAt <= now,
              snapshot.observationAt <= snapshot.retrievedAt else { return invalid(.futureTimestamp) }
        let expiry = ([snapshot.retrievedAt.addingTimeInterval(policy.weatherMaximumAge),
                       snapshot.observationAt.addingTimeInterval(policy.weatherMaximumAge)] +
                      [snapshot.expiresAt].compactMap { $0 }).min()!
        guard now < expiry else { return invalid(.expired, stale: true) }
        let temperature = unit == .celsius ? snapshot.temperatureCelsius : snapshot.temperatureCelsius * 9 / 5 + 32
        guard temperature.isFinite else { return invalid(.invalidSnapshot) }
        let number = NumberFormatter()
        number.locale = locale; number.numberStyle = .decimal
        number.minimumFractionDigits = 0; number.maximumFractionDigits = 0
        guard let formatted = number.string(from: NSNumber(value: temperature)) else { return invalid(.invalidSnapshot) }
        let text = endingSentence(phrases.weather(boundedTitle(snapshot.location.displayName, phrases: phrases),
            boundedTitle(snapshot.conditionDescription, phrases: phrases), formatted, unit))
        return .init(status: .fresh, issue: nil, statusText: phrases.weatherStatus(snapshot.attribution.serviceName),
            retrievedAt: snapshot.retrievedAt, observationAt: snapshot.observationAt, sourceLabels: labels,
            omissionCount: 0, segments: [.init(id: "weather.0", source: .weather, text: text)], validUntil: expiry)
    }

    /// The duration and its window, nothing else. The states follow the issue's list:
    /// unavailable on this device, no record, an older record, not readable.
    private static func sleepSection(_ input: SleepBriefingInput, now: Date, dayEnd: Date, calendar: Calendar,
        zone: TimeZone, locale: Locale, phrases: MorningBriefingPhrases,
        policy: MorningBriefingFreshnessPolicy) -> (MorningBriefingSection, SleepObservation?) {
        func plain(_ status: MorningBriefingSourceStatus, _ issue: MorningBriefingSourceIssue, _ text: String,
                   readAt: Date? = nil) -> (MorningBriefingSection, SleepObservation?) {
            (.init(status: status, issue: issue, statusText: text, retrievedAt: readAt, observationAt: nil,
                   sourceLabels: [], omissionCount: 0, segments: [], validUntil: nil), nil)
        }
        let snapshot: SleepSnapshot
        switch input {
        case .excluded: return plain(.notConfigured, .notConfigured, phrases.sleepExcluded)
        case .notConnected: return plain(.unavailable, .sourceUnavailable, phrases.sleepNotConnected)
        case .unavailableOnDevice: return plain(.unavailable, .unavailableOnDevice, phrases.sleepUnavailableOnDevice)
        case .notReadable: return plain(.unavailable, .notReadable, phrases.sleepNotReadable)
        case .snapshot(let value): snapshot = value
        }
        guard snapshot.readAt.timeIntervalSinceReferenceDate.isFinite else {
            return plain(.unavailable, .invalidSnapshot, phrases.sleepNotReadable)
        }
        guard snapshot.readAt <= now else {
            return plain(.unavailable, .futureTimestamp, phrases.sleepNotReadable, readAt: snapshot.readAt)
        }
        let expiry = min(snapshot.readAt.addingTimeInterval(policy.sleepMaximumAge), dayEnd)
        guard now < expiry else { return plain(.stale, .expired, phrases.sleepNeedsUpdate, readAt: snapshot.readAt) }
        let time = DateFormatter()
        time.locale = locale; time.timeZone = zone
        time.dateStyle = .none; time.timeStyle = .short
        switch SleepNight.summarize(snapshot.samples, readAt: snapshot.readAt, at: now, calendar: calendar) {
        case .noRecord:
            return plain(.missing, .noRecord, phrases.sleepNoRecord, readAt: snapshot.readAt)
        case .olderRecord(let endedAt):
            let date = DateFormatter()
            date.locale = locale; date.timeZone = zone
            date.setLocalizedDateFormatFromTemplate("dMMMM")
            return plain(.stale, .olderRecord,
                phrases.sleepOlderRecord(date.string(from: endedAt), time.string(from: endedAt)), readAt: snapshot.readAt)
        case .recorded(let observation):
            let text = phrases.sleep(phrases.duration(minutes: observation.asleepMinutes),
                from: time.string(from: observation.windowStart), to: time.string(from: observation.windowEnd))
            return (.init(status: .fresh, issue: nil, statusText: phrases.sleepStatus,
                retrievedAt: snapshot.readAt, observationAt: observation.windowEnd,
                sourceLabels: observation.sourceKinds.map(phrases.sleepSource), omissionCount: 0,
                segments: [.init(id: "sleep.0", source: .sleep, text: text)], validUntil: expiry), observation)
        }
    }

    private static func missingSection<T: Sendable & Equatable>(_ input: MorningBriefingInput<T>, name: String,
        phrases: MorningBriefingPhrases) -> MorningBriefingSection {
        switch input {
        case .notConfigured: section(status: .notConfigured, issue: .notConfigured, name: name, phrases: phrases)
        case .denied: section(status: .denied, issue: .permissionDenied, name: name, phrases: phrases)
        case .unavailable, .snapshot: section(status: .unavailable, issue: .sourceUnavailable, name: name, phrases: phrases)
        }
    }

    private static func section(status: MorningBriefingSourceStatus, issue: MorningBriefingSourceIssue,
        name: String, phrases: MorningBriefingPhrases, retrievedAt: Date? = nil, observationAt: Date? = nil,
        sourceLabels: [String] = []) -> MorningBriefingSection {
        let statusText = phrases.status(status, name: name)
        return .init(status: status, issue: issue, statusText: statusText,
            retrievedAt: retrievedAt, observationAt: observationAt, sourceLabels: sourceLabels,
            omissionCount: 0, segments: [], validUntil: nil)
    }

    private static func withFailureSegment(_ section: MorningBriefingSection,
        source: MorningBriefingSegment.Source, include: Bool) -> MorningBriefingSection {
        guard include, section.status != .fresh, section.status != .notConfigured else { return section }
        return .init(status: section.status, issue: section.issue, statusText: section.statusText,
            retrievedAt: section.retrievedAt, observationAt: section.observationAt, sourceLabels: section.sourceLabels,
            omissionCount: section.omissionCount,
            segments: [.init(id: "\(source.rawValue).status", source: source, text: section.statusText)], validUntil: nil)
    }

    private static func boundedTitle(_ text: String, phrases: MorningBriefingPhrases) -> String {
        let oneLine = text.split(whereSeparator: { $0.isWhitespace }).joined(separator: " ")
        guard !oneLine.isEmpty else { return phrases.untitledEvent }
        return oneLine.count > 160 ? String(oneLine.prefix(159)) + "…" : oneLine
    }

    private static func endingSentence(_ text: String) -> String {
        guard let last = text.last, !".!?…".contains(last) else { return text }
        return text + "."
    }
}

/// Deterministic briefing sentences for each supported language. Keeping them
/// explicit (rather than in the string catalog) keeps prepared speech testable
/// for a given locale regardless of the device language.
struct MorningBriefingPhrases {
    let french: Bool

    init?(locale: Locale) {
        switch locale.language.languageCode?.identifier {
        case "en": french = false
        case "fr": french = true
        default: return nil
        }
    }

    var calendarName: String { french ? "Le calendrier" : "Calendar" }
    var weatherName: String { french ? "La météo" : "Weather" }
    var untitledEvent: String { french ? "Événement sans titre" : "Untitled event" }
    var noRemainingEvents: String {
        french ? "Plus aucun événement aujourd’hui dans les calendriers sélectionnés."
            : "No remaining events today in your selected calendars."
    }
    var calendarStatus: String {
        french ? "Lu depuis les calendriers sélectionnés." : "Read from your selected calendars."
    }

    func introduction(_ date: String) -> String {
        french ? "Voici votre récap pour \(date)." : "Here is your briefing for \(date)."
    }
    func allDay(_ title: String) -> String { french ? "Toute la journée : \(title)" : "All day: \(title)" }
    func inProgress(_ ending: String, _ title: String) -> String {
        french ? "En cours jusqu’à \(ending) : \(title)" : "In progress until \(ending): \(title)"
    }
    func at(_ time: String, _ title: String) -> String { french ? "À \(time) : \(title)" : "At \(time): \(title)" }
    func more(_ count: Int) -> String {
        if french { return count == 1 ? "Et 1 autre événement aujourd’hui." : "Et \(count) autres événements aujourd’hui." }
        return "Plus \(count) more \(count == 1 ? "event" : "events") today."
    }
    func weather(_ place: String, _ condition: String, _ temperature: String,
                 _ unit: MorningBriefingTemperatureUnit) -> String {
        if french {
            let unitName = unit == .celsius ? "degrés Celsius" : "degrés Fahrenheit"
            return "Météo à \(place) : \(condition), \(temperature) \(unitName)"
        }
        return "Weather in \(place): \(condition), \(temperature) degrees \(unit == .celsius ? "Celsius" : "Fahrenheit")"
    }
    func weatherStatus(_ service: String) -> String {
        french ? "Conditions actuelles fournies par \(service)." : "Current conditions from \(service)."
    }

    // Sleep. A duration and its window; no score, no judgement, no advice. None of these
    // sentences says or implies that permission was refused: that cannot be known.
    var sleepStatus: String {
        french ? "Lu depuis les données Santé de cet appareil." : "Read from the Health data on this device."
    }
    var sleepExcluded: String { french ? "Le sommeil n’est pas inclus." : "Sleep is not included." }
    var sleepNotConnected: String {
        french ? "La lecture du sommeil ne fait pas partie de cette version."
            : "Sleep reading is not part of this version."
    }
    var sleepUnavailableOnDevice: String {
        french ? "Les données de santé ne sont pas disponibles sur cet appareil."
            : "Health data is not available on this device."
    }
    var sleepNotReadable: String {
        french ? "Les données de sommeil n’ont pas pu être lues." : "Sleep data could not be read."
    }
    var sleepNeedsUpdate: String {
        french ? "Les données de sommeil doivent être mises à jour." : "Sleep data needs a fresh update."
    }
    var sleepNoRecord: String {
        french ? "Aucun relevé de sommeil trouvé depuis hier soir."
            : "No sleep record was found since yesterday evening."
    }
    func sleepOlderRecord(_ date: String, _ time: String) -> String {
        french ? "Le dernier relevé de sommeil s’est terminé le \(date) à \(time)."
            : "The latest sleep record ended on \(date) at \(time)."
    }
    func sleep(_ duration: String, from start: String, to end: String) -> String {
        french ? "Sommeil enregistré : \(duration), entre \(start) et \(end)."
            : "Sleep recorded: \(duration), between \(start) and \(end)."
    }
    /// Words, not "h" and "min": the same string is read aloud.
    func duration(minutes total: Int) -> String {
        let hours = total / 60, minutes = total % 60
        var parts: [String] = []
        if french {
            // French counts zero and one as singular.
            if hours > 0 { parts.append("\(hours) \(hours < 2 ? "heure" : "heures")") }
            if minutes > 0 || hours == 0 { parts.append("\(minutes) \(minutes < 2 ? "minute" : "minutes")") }
        } else {
            if hours > 0 { parts.append("\(hours) \(hours == 1 ? "hour" : "hours")") }
            if minutes > 0 || hours == 0 { parts.append("\(minutes) \(minutes == 1 ? "minute" : "minutes")") }
        }
        return parts.joined(separator: " ")
    }
    func sleepSource(_ kind: SleepSourceKind) -> String {
        switch kind {
        case .watch: french ? "Montre" : "Watch"
        case .phone: french ? "Téléphone" : "Phone"
        case .thirdPartyApp: french ? "Autre app" : "Another app"
        case .manualEntry: french ? "Saisie manuelle" : "Manual entry"
        case .unknown: french ? "Source inconnue" : "Unknown source"
        }
    }

    func status(_ status: MorningBriefingSourceStatus, name: String) -> String {
        if french {
            let weather = name == weatherName
            switch status {
            case .notConfigured: return weather ? "La météo n’est pas configurée." : "Le calendrier n’est pas configuré."
            case .denied: return weather ? "L’accès à la météo n’est pas autorisé." : "L’accès au calendrier n’est pas autorisé."
            case .stale: return weather ? "La météo doit être mise à jour." : "Le calendrier doit être mis à jour."
            default: return weather ? "La météo n’est pas disponible pour ce récap." : "Le calendrier n’est pas disponible pour ce récap."
            }
        }
        switch status {
        case .notConfigured: return "\(name) is not configured."
        case .denied: return "\(name) access is not allowed."
        case .stale: return "\(name) needs a fresh update."
        default: return "\(name) is unavailable for this briefing."
        }
    }
}
