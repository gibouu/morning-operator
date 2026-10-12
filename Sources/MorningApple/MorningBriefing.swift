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
}

public enum MorningBriefingSourceIssue: String, Sendable, Equatable {
    case notConfigured, permissionDenied, sourceUnavailable, expired
    case futureTimestamp, wrongDay, wrongTimeZone, invalidSelection, invalidSnapshot
}

public enum MorningBriefingTemperatureUnit: String, Codable, CaseIterable, Sendable, Equatable {
    case celsius, fahrenheit
}

public enum MorningBriefingError: Error, LocalizedError, Sendable, Equatable {
    case invalidDate, invalidTimeZone, unsupportedLocale, invalidPolicy

    public var errorDescription: String? {
        switch self {
        case .invalidDate: "The briefing date could not be resolved."
        case .invalidTimeZone: "Choose a valid time zone for this briefing."
        case .unsupportedLocale: "Prepared briefings currently support English."
        case .invalidPolicy: "The briefing freshness settings are invalid."
        }
    }
}

public struct MorningBriefingFreshnessPolicy: Sendable, Equatable {
    public let calendarMaximumAge: TimeInterval
    public let weatherMaximumAge: TimeInterval
    public let maximumCalendarEvents: Int

    public static let standard = Self(calendarMaximumAge: 300, weatherMaximumAge: 1_800,
                                      maximumCalendarEvents: 5)

    /// Invalid policies are rejected by prepare; event limits may be 1 through 5.
    public init(calendarMaximumAge: TimeInterval = 300, weatherMaximumAge: TimeInterval = 1_800,
                maximumCalendarEvents: Int = 5) {
        self.calendarMaximumAge = calendarMaximumAge
        self.weatherMaximumAge = weatherMaximumAge
        self.maximumCalendarEvents = maximumCalendarEvents
    }
}

public struct MorningBriefingSegment: Identifiable, Sendable, Equatable {
    public enum Source: String, Sendable, Equatable { case introduction, calendar, weather }
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
    /// WeatherKit's conditions time; nil for EventKit, which exposes no remote
    /// synchronization time for the local read.
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
    public let selectedCalendarIDs: Set<String>
    public let weatherLocation: WeatherLocation?
    public let weatherAttribution: WeatherAttributionInfo?
    public let segments: [MorningBriefingSegment]

    public var hasUsableFacts: Bool { calendar.status == .fresh || weather.status == .fresh }
    public var displayText: String { segments.map(\.text).joined(separator: "\n") }
    public var spokenText: String { segments.map(\.text).joined(separator: " ") }
    public var validUntil: Date? {
        guard hasUsableFacts else { return nil }
        return ([dayEnd] + [calendar.validUntil, weather.validUntil].compactMap { $0 }).min()
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
    /// Deterministic English prose; English locale variants control dates, clocks
    /// and decimal formatting. This does not ask a model to summarize private data.
    public static func prepare(
        calendar inputCalendar: MorningBriefingInput<CalendarSnapshot>,
        weather inputWeather: MorningBriefingInput<WeatherObservationSnapshot>,
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
        guard locale.language.languageCode?.identifier == "en" else { throw MorningBriefingError.unsupportedLocale }
        guard policy.calendarMaximumAge.isFinite, policy.calendarMaximumAge > 0,
              policy.weatherMaximumAge.isFinite, policy.weatherMaximumAge > 0,
              (1...5).contains(policy.maximumCalendarEvents) else { throw MorningBriefingError.invalidPolicy }
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = zone
        let dayStart = calendar.startOfDay(for: day)
        guard let dayEnd = calendar.date(byAdding: .day, value: 1, to: dayStart), dayEnd > dayStart,
              now >= dayStart, now < dayEnd else {
            throw MorningBriefingError.invalidDate
        }
        var calendarSection = Self.calendarSection(inputCalendar, dayStart: dayStart, dayEnd: dayEnd,
            now: now, zone: zone, locale: locale, policy: policy)
        var weatherSection = Self.weatherSection(inputWeather, now: now, locale: locale,
            unit: temperatureUnit, policy: policy)
        let hasFacts = calendarSection.status == .fresh || weatherSection.status == .fresh
        // Configure sources in Settings, not in every spoken morning. A failed
        // configured source gets one short sentence only when another can help.
        calendarSection = withFailureSegment(calendarSection, source: .calendar, include: hasFacts)
        weatherSection = withFailureSegment(weatherSection, source: .weather, include: hasFacts)
        var segments: [MorningBriefingSegment] = []
        if hasFacts {
            let formatter = DateFormatter()
            formatter.locale = locale; formatter.timeZone = zone
            formatter.dateStyle = .full; formatter.timeStyle = .none
            segments.append(.init(id: "introduction", source: .introduction,
                text: "Here is your briefing for \(formatter.string(from: day))."))
            segments += calendarSection.segments + weatherSection.segments
        }
        let weatherSnapshot: WeatherObservationSnapshot?
        if case .snapshot(let snapshot) = inputWeather { weatherSnapshot = snapshot } else { weatherSnapshot = nil }
        let selectedCalendarIDs: Set<String>
        if case .snapshot(let snapshot) = inputCalendar { selectedCalendarIDs = Set(snapshot.selectedCalendarIDs) }
        else { selectedCalendarIDs = [] }
        return .init(id: UUID(), preparedAt: now, dayStart: dayStart, dayEnd: dayEnd,
            timeZoneIdentifier: timeZoneIdentifier, localeIdentifier: localeIdentifier,
            temperatureUnit: temperatureUnit, calendar: calendarSection, weather: weatherSection,
            selectedCalendarIDs: selectedCalendarIDs,
            weatherLocation: weatherSnapshot?.location,
            weatherAttribution: weatherSection.status == .fresh ? weatherSnapshot?.attribution : nil,
            segments: segments)
    }

    private static func calendarSection(_ input: MorningBriefingInput<CalendarSnapshot>,
        dayStart: Date, dayEnd: Date, now: Date, zone: TimeZone, locale: Locale,
        policy: MorningBriefingFreshnessPolicy) -> MorningBriefingSection {
        guard case .snapshot(let snapshot) = input else { return missingSection(input, name: "Calendar") }
        func invalid(_ issue: MorningBriefingSourceIssue, stale: Bool = false) -> MorningBriefingSection {
            section(status: stale ? .stale : .unavailable, issue: issue, name: "Calendar",
                retrievedAt: snapshot.retrievedAt, sourceLabels: snapshot.sourceLabels)
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
            let title = boundedTitle(event.title)
            if event.isAllDay { return endingSentence("All day: \(title)") }
            if event.start <= now {
                let ending: String
                if event.end >= dayEnd {
                    let endFormatter = DateFormatter()
                    endFormatter.locale = locale; endFormatter.timeZone = zone
                    endFormatter.dateStyle = .medium; endFormatter.timeStyle = .short
                    ending = endFormatter.string(from: event.end)
                } else { ending = formatter.string(from: event.end) }
                return endingSentence("In progress until \(ending): \(title)")
            }
            return endingSentence("At \(formatter.string(from: event.start)): \(title)")
        }
        if remaining.isEmpty { texts = ["No remaining events today in your selected calendars."] }
        let omitted = remaining.count - shown.count
        if omitted > 0 { texts.append("Plus \(omitted) more \(omitted == 1 ? "event" : "events") today.") }
        let boundaries = remaining.flatMap { event -> [Date] in
            guard !event.isAllDay else { return [] }
            return [event.start, event.end].filter { $0 > now }
        }
        let expiry = ([snapshot.retrievedAt.addingTimeInterval(policy.calendarMaximumAge), dayEnd] + boundaries).min()
        return .init(status: .fresh, issue: nil, statusText: "Read from your selected calendars.",
            retrievedAt: snapshot.retrievedAt, observationAt: nil, sourceLabels: snapshot.sourceLabels,
            omissionCount: omitted, segments: texts.enumerated().map {
                .init(id: "calendar.\($0.offset)", source: .calendar, text: $0.element)
            }, validUntil: expiry)
    }

    private static func weatherSection(_ input: MorningBriefingInput<WeatherObservationSnapshot>,
        now: Date, locale: Locale, unit: MorningBriefingTemperatureUnit,
        policy: MorningBriefingFreshnessPolicy) -> MorningBriefingSection {
        guard case .snapshot(let snapshot) = input else { return missingSection(input, name: "Weather") }
        let labels = [snapshot.attribution.serviceName, snapshot.location.displayName]
        func invalid(_ issue: MorningBriefingSourceIssue, stale: Bool = false) -> MorningBriefingSection {
            section(status: stale ? .stale : .unavailable, issue: issue, name: "Weather",
                retrievedAt: snapshot.retrievedAt, observationAt: snapshot.observationAt, sourceLabels: labels)
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
        let unitName = unit == .celsius ? "Celsius" : "Fahrenheit"
        let text = endingSentence("Weather in \(boundedTitle(snapshot.location.displayName)): \(boundedTitle(snapshot.conditionDescription)), \(formatted) degrees \(unitName)")
        return .init(status: .fresh, issue: nil, statusText: "Current conditions from \(snapshot.attribution.serviceName).",
            retrievedAt: snapshot.retrievedAt, observationAt: snapshot.observationAt, sourceLabels: labels,
            omissionCount: 0, segments: [.init(id: "weather.0", source: .weather, text: text)], validUntil: expiry)
    }

    private static func missingSection<T: Sendable & Equatable>(_ input: MorningBriefingInput<T>, name: String) -> MorningBriefingSection {
        switch input {
        case .notConfigured: section(status: .notConfigured, issue: .notConfigured, name: name)
        case .denied: section(status: .denied, issue: .permissionDenied, name: name)
        case .unavailable, .snapshot: section(status: .unavailable, issue: .sourceUnavailable, name: name)
        }
    }

    private static func section(status: MorningBriefingSourceStatus, issue: MorningBriefingSourceIssue,
        name: String, retrievedAt: Date? = nil, observationAt: Date? = nil,
        sourceLabels: [String] = []) -> MorningBriefingSection {
        let statusText: String
        switch status {
        case .notConfigured: statusText = "\(name) is not configured."
        case .denied: statusText = "\(name) access is not allowed."
        case .stale: statusText = "\(name) needs a fresh update."
        default: statusText = "\(name) is unavailable for this briefing."
        }
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

    private static func boundedTitle(_ text: String) -> String {
        let oneLine = text.split(whereSeparator: { $0.isWhitespace }).joined(separator: " ")
        guard !oneLine.isEmpty else { return "Untitled event" }
        return oneLine.count > 160 ? String(oneLine.prefix(159)) + "…" : oneLine
    }

    private static func endingSentence(_ text: String) -> String {
        guard let last = text.last, !".!?…".contains(last) else { return text }
        return text + "."
    }
}
