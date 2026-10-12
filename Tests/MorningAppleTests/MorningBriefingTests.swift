import Foundation
import Testing
@testable import MorningApple

@Suite("Prepared briefing — synthetic facts and clock only")
struct MorningBriefingTests {
    private let now = Date(timeIntervalSince1970: 1_791_619_200) // Fixed instant; never current personal data.
    private let selection = CalendarChoice(id: "selected", title: "Synthetic calendar", sourceTitle: "Synthetic local source")

    @Test func calendarFreshnessIsStrictAndSourceTimesRemainDistinct() throws {
        let fresh = try prepare(calendar: .snapshot(calendar(retrievedAt: now.addingTimeInterval(-299))))
        #expect(fresh.calendar.status == .fresh)
        #expect(fresh.calendar.observationAt == nil, "EventKit has no remote synchronization timestamp.")
        #expect(fresh.calendar.retrievedAt == now.addingTimeInterval(-299))
        #expect(fresh.calendar.text == "No remaining events today in your selected calendars.")
        let expired = try prepare(calendar: .snapshot(calendar(retrievedAt: now.addingTimeInterval(-300))))
        #expect(expired.calendar.status == .stale && expired.calendar.issue == .expired)
        #expect(expired.spokenText.isEmpty)
        let future = try prepare(calendar: .snapshot(calendar(retrievedAt: now.addingTimeInterval(1))))
        #expect(future.calendar.status == .unavailable && future.calendar.issue == .futureTimestamp)
    }

    @Test func wrongDayZoneOrSelectionCannotBecomeAnEmptyCalendar() throws {
        let bounds = dayBounds(now, zone: "UTC")
        let wrongDay = CalendarSnapshot(retrievedAt: now, dayStart: bounds.start.addingTimeInterval(-86_400),
            dayEnd: bounds.start, events: [], timeZoneIdentifier: "UTC", selectedCalendars: [selection])
        #expect(try prepare(calendar: .snapshot(wrongDay)).calendar.issue == .wrongDay)
        let wrongZone = CalendarSnapshot(retrievedAt: now, dayStart: bounds.start, dayEnd: bounds.end,
            events: [], timeZoneIdentifier: "Europe/Paris", selectedCalendars: [selection])
        #expect(try prepare(calendar: .snapshot(wrongZone)).calendar.issue == .wrongTimeZone)
        let noSelection = CalendarSnapshot(retrievedAt: now, dayStart: bounds.start, dayEnd: bounds.end,
            events: [], timeZoneIdentifier: "UTC", selectedCalendars: [])
        #expect(try prepare(calendar: .snapshot(noSelection)).calendar.issue == .invalidSelection)
        let outsideSelection = event("other", start: now.addingTimeInterval(30), end: now.addingTimeInterval(60), calendarID: "unselected")
        let invalid = try prepare(calendar: .snapshot(calendar(events: [outsideSelection])))
        #expect(invalid.calendar.issue == .invalidSnapshot && !invalid.hasUsableFacts)
    }

    @Test func allDayOngoingAndUpcomingAreOrderedCappedAndPastEventsExcluded() throws {
        let bounds = dayBounds(now, zone: "UTC")
        var events = [
            event("past", start: now.addingTimeInterval(-600), end: now.addingTimeInterval(-300)),
            event("ongoing", start: now.addingTimeInterval(-60), end: now.addingTimeInterval(120)),
            event("all-day", start: bounds.start, end: bounds.end, allDay: true)
        ]
        for index in 1...6 {
            events.append(event("upcoming-\(index)", start: now.addingTimeInterval(Double(index * 600)),
                                end: now.addingTimeInterval(Double(index * 600 + 300))))
        }
        let briefing = try prepare(calendar: .snapshot(calendar(events: Array(events.reversed()))))
        let lines = briefing.calendar.segments.map(\.text)
        try #require(lines.count == 6, "Five events plus one explicit omission sentence.")
        #expect(lines[0].hasPrefix("All day:") && lines[0].contains("all-day"))
        #expect(lines[1].hasPrefix("In progress until") && lines[1].contains("ongoing"))
        #expect(lines[2].contains("upcoming-1") && lines[4].contains("upcoming-3"))
        #expect(briefing.calendar.omissionCount == 3 && lines[5] == "Plus 3 more events today.")
        #expect(!briefing.spokenText.contains("past") && !briefing.spokenText.contains("upcoming-6"))
    }

    @Test func missingSourcesAreIndependentAndDeniedNeverMeansNoEvents() throws {
        let weatherOnly = try prepare(calendar: .denied, weather: .snapshot(weather()))
        #expect(weatherOnly.weather.status == .fresh && weatherOnly.calendar.status == .denied)
        #expect(weatherOnly.spokenText.contains("Calendar access is not allowed."))
        #expect(!weatherOnly.spokenText.contains("No remaining events"))
        let calendarOnly = try prepare(calendar: .snapshot(calendar()), weather: .unavailable)
        #expect(calendarOnly.calendar.status == .fresh && calendarOnly.weather.status == .unavailable)
        #expect(calendarOnly.spokenText.contains("No remaining events") && calendarOnly.spokenText.contains("Weather is unavailable"))
        let missingInputs: [MorningBriefingInput<CalendarSnapshot>] = [.notConfigured, .denied, .unavailable]
        for input in missingInputs {
            let missing = try prepare(calendar: input, weather: .unavailable)
            #expect(!missing.hasUsableFacts && missing.spokenText.isEmpty && missing.displayText.isEmpty)
            #expect(missing.validUntil == nil && !missing.isCurrent(at: now, timeZoneIdentifier: "UTC"))
        }
    }

    @Test func weatherAgeExpiryFutureDatesAndUnitsAreEnforced() throws {
        let fresh = try prepare(weather: .snapshot(weather(observationAt: now.addingTimeInterval(-1_799))))
        #expect(fresh.weather.status == .fresh)
        let old = try prepare(weather: .snapshot(weather(observationAt: now.addingTimeInterval(-1_800))))
        #expect(old.weather.status == .stale && old.weather.issue == .expired && old.weatherAttribution == nil)
        let expired = try prepare(weather: .snapshot(weather(expiresAt: now)))
        #expect(expired.weather.status == .stale)
        let future = try prepare(weather: .snapshot(weather(observationAt: now.addingTimeInterval(1))))
        #expect(future.weather.issue == .futureTimestamp)
        let lateSource = try prepare(weather: .snapshot(weather(retrievedAt: now.addingTimeInterval(-10), observationAt: now.addingTimeInterval(-5))))
        #expect(lateSource.weather.issue == .futureTimestamp, "Source time after retrieval is inconsistent even when both are in the past.")
        let celsius = try prepare(weather: .snapshot(weather()), unit: .celsius)
        let fahrenheit = try prepare(weather: .snapshot(weather()), unit: .fahrenheit)
        #expect(celsius.weather.text.contains("20 degrees Celsius"))
        #expect(fahrenheit.weather.text.contains("68 degrees Fahrenheit"))
        #expect(celsius.weatherAttribution == fahrenheit.weatherAttribution && celsius.weatherLocation == fahrenheit.weatherLocation)
    }

    @Test func visibleAndSpokenFactsUseTheIdenticalOrderedSegments() throws {
        let document = try prepare(calendar: .snapshot(calendar(events: [event("Synthetic meeting",
            start: now.addingTimeInterval(60), end: now.addingTimeInterval(120))])), weather: .snapshot(weather()))
        #expect(document.displayText.components(separatedBy: "\n") == document.segments.map(\.text))
        #expect(document.spokenText == document.segments.map(\.text).joined(separator: " "))
        #expect(document.segments.map(\.source) == [.introduction, .calendar, .weather])
        #expect(document.weatherAttribution != nil && document.weather.sourceLabels.contains("Synthetic Weather"))
    }

    @Test func eventBoundariesInvalidateAnOtherwiseFreshRecap() throws {
        let start = now.addingTimeInterval(30)
        let document = try prepare(calendar: .snapshot(calendar(events: [event("Upcoming synthetic event", start: start, end: start.addingTimeInterval(60))])))
        #expect(document.validUntil == start)
        #expect(document.isCurrent(at: start.addingTimeInterval(-0.01), timeZoneIdentifier: "UTC"))
        #expect(document.isCurrent(at: now, timeZoneIdentifier: "GMT"), "Equivalent UTC aliases must remain current.")
        #expect(!document.isCurrent(at: now, timeZoneIdentifier: "Not/A_Time_Zone"))
        #expect(!document.isCurrent(at: start, timeZoneIdentifier: "UTC"))
        #expect(!document.isCurrent(at: now.addingTimeInterval(-1), timeZoneIdentifier: "UTC"))
        #expect(!document.isCurrent(at: now, timeZoneIdentifier: "Europe/Paris"))
    }

    @Test func daylightSavingDayUsesActualLocalBoundaryAndExpiresAtMidnight() throws {
        let parser = ISO8601DateFormatter()
        let noon = try #require(parser.date(from: "2026-03-29T10:00:00Z"))
        let bounds = dayBounds(noon, zone: "Europe/Paris")
        #expect(bounds.duration == 23 * 3_600)
        let nearEnd = bounds.end.addingTimeInterval(-10)
        let snapshot = CalendarSnapshot(retrievedAt: nearEnd, dayStart: bounds.start, dayEnd: bounds.end,
            events: [], timeZoneIdentifier: "Europe/Paris", selectedCalendars: [selection])
        let document = try MorningBriefingComposer.prepare(calendar: .snapshot(snapshot), weather: .notConfigured,
            for: nearEnd, at: nearEnd, timeZoneIdentifier: "Europe/Paris")
        #expect(document.dayStart == bounds.start && document.dayEnd == bounds.end && document.validUntil == bounds.end)
        #expect(document.isCurrent(at: bounds.end.addingTimeInterval(-0.01), timeZoneIdentifier: "Europe/Paris"))
        #expect(!document.isCurrent(at: bounds.end, timeZoneIdentifier: "Europe/Paris"))
    }

    @Test func EnglishVariantsWorkAndUnsupportedLocaleOrInvalidPolicyFailExplicitly() throws {
        for locale in ["en_US", "en_GB", "en_AU"] {
            let document = try prepare(calendar: .snapshot(calendar()), locale: locale)
            #expect(document.hasUsableFacts && document.localeIdentifier == locale)
        }
        #expect(throws: MorningBriefingError.unsupportedLocale) { try prepare(calendar: .snapshot(calendar()), locale: "fr_FR") }
        #expect(throws: MorningBriefingError.invalidPolicy) {
            try MorningBriefingComposer.prepare(calendar: .notConfigured, weather: .notConfigured,
                for: now, at: now, timeZoneIdentifier: "UTC", policy: .init(maximumCalendarEvents: 6))
        }
    }

    private func prepare(calendar: MorningBriefingInput<CalendarSnapshot> = .notConfigured,
                         weather: MorningBriefingInput<WeatherObservationSnapshot> = .notConfigured,
                         unit: MorningBriefingTemperatureUnit = .celsius, locale: String = "en_US") throws -> PreparedMorningBriefing {
        try MorningBriefingComposer.prepare(calendar: calendar, weather: weather, for: now, at: now,
            timeZoneIdentifier: "UTC", localeIdentifier: locale, temperatureUnit: unit)
    }
    private func calendar(retrievedAt: Date? = nil, events: [CalendarEventSummary] = []) -> CalendarSnapshot {
        let bounds = dayBounds(now, zone: "UTC")
        return .init(retrievedAt: retrievedAt ?? now, dayStart: bounds.start, dayEnd: bounds.end, events: events,
                     timeZoneIdentifier: "UTC", selectedCalendars: [selection])
    }
    private func event(_ title: String, start: Date, end: Date, allDay: Bool = false, calendarID: String = "selected") -> CalendarEventSummary {
        .init(id: title, title: title, start: start, end: end, isAllDay: allDay,
              calendarTitle: "Synthetic calendar", calendarID: calendarID, sourceTitle: "Synthetic local source")
    }
    private func dayBounds(_ date: Date, zone: String) -> DateInterval {
        var value = Calendar(identifier: .gregorian)
        value.timeZone = TimeZone(identifier: zone)!
        return value.dateInterval(of: .day, for: date)!
    }
    private func weather(retrievedAt: Date? = nil, observationAt: Date? = nil, expiresAt: Date? = nil) throws -> WeatherObservationSnapshot {
        let attribution = try WeatherAttributionInfo(legalURL: URL(string: "https://example.invalid/legal")!,
            combinedMarkLightURL: URL(string: "https://example.invalid/light.png")!,
            combinedMarkDarkURL: URL(string: "https://example.invalid/dark.png")!, serviceName: "Synthetic Weather")
        return try .init(location: WeatherLocation(latitude: 10, longitude: 20, displayName: "Synthetic city"),
            retrievedAt: retrievedAt ?? now, observationAt: observationAt ?? now,
            temperatureCelsius: 20, conditionDescription: "Synthetic sunshine", symbolName: "sun.max",
            attribution: attribution, expiresAt: expiresAt)
    }
}
