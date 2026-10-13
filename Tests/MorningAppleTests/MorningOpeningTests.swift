import Foundation
import Testing
@testable import MorningApple

@Suite("Morning opening — synthetic facts and clock only")
struct MorningOpeningTests {
    private let now = Date(timeIntervalSince1970: 1_791_619_200) // 08:00 UTC; never current personal data.
    private let selection = CalendarChoice(id: "selected", title: "Synthetic calendar", sourceTitle: "Synthetic local source")

    @Test func englishOpeningGreetsOnceQuotesFreshFactsAndEndsWithTheChoice() throws {
        let opening = try compose(briefing(calendar: .snapshot(calendar()), weather: .snapshot(weather())))
        #expect(opening.text == "Good morning. Weather in Synthetic city: Synthetic sunshine, 20 degrees Celsius. "
            + "No remaining events today in your selected calendars. "
            + "Would you like to hear your briefing, start your routine, or stop?")
        #expect(opening.segments.map(\.source) == [.greeting, .weather, .calendar, .choice])
        #expect(opening.choices == [.brief, .ritual, .stop])
    }

    @Test func frenchOpeningForTheSameInputHasNoEnglishFragment() throws {
        let french = try briefing(calendar: .snapshot(calendar()), weather: .snapshot(weather()), locale: "fr_FR")
        let opening = compose(french, counts: [.unreadMessages: .available(1), .unreadEmail: .available(0),
                                               .missedCalls: .available(2)],
                              precipitation: .init(chance: 0.8, windowEnd: now.addingTimeInterval(14_400),
                                                   expiresAt: now.addingTimeInterval(1_800)),
                              unknownSenders: .init(unknownSenders: 1, totalSenders: 4))
        #expect(opening.text == "Bonjour. Météo à Synthetic city : Synthetic sunshine, 20 degrés Celsius. "
            + "Il risque de pleuvoir avant 12:00. Prenez un parapluie. "
            + "Plus aucun événement aujourd’hui dans les calendriers sélectionnés. "
            + "1 message non lu. 0 e-mail non lu. 2 appels manqués. "
            + "25 % des expéditeurs ne figurent pas dans les contacts partagés avec cette app. "
            + "Voulez-vous écouter votre récap, lancer votre routine ou arrêter ?")
        // The typed result does not depend on the language.
        let english = try compose(briefing(calendar: .snapshot(calendar()), weather: .snapshot(weather())))
        #expect(opening.choices == english.choices)

        let failing = try briefing(calendar: .snapshot(calendar(retrievedAt: now.addingTimeInterval(-300))),
                                   weather: .unavailable, locale: "fr_FR")
        let degraded = compose(failing, counts: [.unreadMessages: .stale, .unreadEmail: .stale, .missedCalls: .stale])
        #expect(degraded.text == "Bonjour. La météo n’est pas disponible. Le calendrier n’est plus à jour. "
            + "Le nombre de messages non lus n’est plus à jour. Le nombre d’e-mails non lus n’est plus à jour. "
            + "Le nombre d’appels manqués n’est plus à jour. Voulez-vous lancer votre routine ou arrêter ?")
        let late = compose(french, at: now.addingTimeInterval(1_800))
        #expect(late.text.contains("La météo n’est plus à jour.") && late.text.contains("Le calendrier n’est plus à jour."))
    }

    @Test func missingProviderIsOmittedAndNeverBecomesZero() throws {
        let document = try briefing(weather: .snapshot(weather()))
        let none = compose(document)
        #expect(!none.segments.contains { $0.source == .count })
        let unavailable = compose(document, counts: [.unreadMessages: .unavailable, .unreadEmail: .unavailable,
                                                    .missedCalls: .unavailable])
        #expect(unavailable == none)
        for word in [" 0 ", "unread", "missed", "message", "email", "call"] { #expect(!none.text.contains(word)) }
        // A negative number is not a count.
        #expect(compose(document, counts: [.unreadEmail: .available(-1)]) == none)
    }

    @Test func staleAndMixedProvidersAreSaidAsTheyAre() throws {
        let document = try briefing(weather: .snapshot(weather()))
        let mixed = compose(document, counts: [.unreadEmail: .available(3), .missedCalls: .stale])
        #expect(mixed.segments.filter { $0.source == .count }.map(\.text)
            == ["3 unread emails.", "The missed call count is out of date."])
        #expect(!mixed.text.contains("message"))
        // A verified zero is a count, and is the only way a zero is ever said.
        let verified = compose(document, counts: [.unreadMessages: .available(0), .unreadEmail: .available(1),
                                                 .missedCalls: .available(1)])
        #expect(verified.segments.filter { $0.source == .count }.map(\.text)
            == ["0 unread messages.", "1 unread email.", "1 missed call."])
        let stale = compose(document, counts: [.unreadMessages: .stale, .unreadEmail: .stale])
        #expect(stale.segments.filter { $0.source == .count }.map(\.text)
            == ["The unread message count is out of date.", "The unread email count is out of date."])
    }

    @Test func briefingSectionsAreQuotedOnlyWhileFresh() throws {
        let staleCalendar = try briefing(calendar: .snapshot(calendar(retrievedAt: now.addingTimeInterval(-300))),
                                         weather: .snapshot(weather()))
        #expect(compose(staleCalendar).text == "Good morning. Weather in Synthetic city: Synthetic sunshine, 20 degrees Celsius. "
            + "The calendar is out of date. Would you like to hear your briefing, start your routine, or stop?")
        let denied = try briefing(calendar: .denied, weather: .unavailable)
        let nothing = compose(denied)
        #expect(nothing.text == "Good morning. The weather is unavailable. The calendar is unavailable. "
            + "Would you like to start your routine, or stop?")
        #expect(nothing.choices == [.ritual, .stop])
        let unconfigured = compose(try briefing())
        #expect(unconfigured.text == "Good morning. Would you like to start your routine, or stop?")

        // Prepared fresh, played too late: the facts are not repeated as if current.
        let both = try briefing(calendar: .snapshot(calendar()), weather: .snapshot(weather()))
        let calendarExpired = compose(both, at: now.addingTimeInterval(300))
        #expect(calendarExpired.segments.map(\.text).contains("The calendar is out of date."))
        #expect(calendarExpired.text.contains("20 degrees") && calendarExpired.choices.contains(.brief))
        for late in [compose(both, at: now.addingTimeInterval(1_800)), compose(both, at: now.addingTimeInterval(-1)),
                     compose(both, at: now.addingTimeInterval(86_400)), compose(both, zone: "Europe/Paris")] {
            #expect(late.text == "Good morning. The weather is out of date. The calendar is out of date. "
                + "Would you like to start your routine, or stop?")
            #expect(late.choices == [.ritual, .stop])
        }
    }

    @Test func currentConditionsAloneNeverSuggestAnUmbrella() throws {
        let raining = try briefing(weather: .snapshot(weather(condition: "Heavy rain")))
        let opening = compose(raining)
        #expect(opening.text.contains("Heavy rain"))
        #expect(!opening.segments.contains { $0.source == .umbrella } && !opening.text.contains("umbrella"))

        func umbrella(_ chance: Double, windowEnd: TimeInterval = 14_400, expiresAt: TimeInterval = 1_800,
                      at offset: TimeInterval = 0) -> [String] {
            compose(raining, at: now.addingTimeInterval(offset),
                    precipitation: .init(chance: chance, windowEnd: now.addingTimeInterval(windowEnd),
                                         expiresAt: now.addingTimeInterval(expiresAt)))
                .segments.filter { $0.source == .umbrella }.map(\.text)
        }
        let said = umbrella(0.5)
        try #require(said.count == 1)
        #expect(said[0].hasPrefix("Rain is likely before 12:00") && said[0].hasSuffix(". Take an umbrella."))
        #expect(umbrella(0.49).isEmpty && umbrella(.nan).isEmpty && umbrella(1.5).isEmpty)
        #expect(umbrella(0.9, expiresAt: 0).isEmpty, "An expired forecast is not a forecast.")
        #expect(umbrella(0.9, windowEnd: 0).isEmpty, "The window is over.")
        #expect(umbrella(0.9, windowEnd: 90_000, expiresAt: 90_000).isEmpty, "The window is not today.")
        #expect(umbrella(0.9, expiresAt: 600, at: 600).isEmpty)
        // A forecast does not need a dry sky to be believed, and does not need the weather section at all.
        let noWeather = compose(try briefing(calendar: .snapshot(calendar())),
                                precipitation: .init(chance: 1, windowEnd: now.addingTimeInterval(3_600),
                                                     expiresAt: now.addingTimeInterval(600)))
        #expect(noWeather.segments.map(\.source) == [.greeting, .umbrella, .calendar, .choice])
    }

    @Test func noPercentageWithoutADenominator() throws {
        let document = try briefing(weather: .snapshot(weather()))
        func share(_ unknown: Int, _ total: Int?) -> [String] {
            compose(document, unknownSenders: .init(unknownSenders: unknown, totalSenders: total))
                .segments.filter { $0.source == .unknownSenders }.map(\.text)
        }
        for opening in [compose(document), compose(document, unknownSenders: .init(unknownSenders: 3, totalSenders: nil))] {
            #expect(!opening.text.contains("%") && !opening.text.contains("senders"))
        }
        #expect(share(3, 0).isEmpty && share(0, 0).isEmpty && share(5, 4).isEmpty && share(-1, 4).isEmpty && share(1, -4).isEmpty)
        #expect(share(1, 4) == ["25% of senders are not in the contacts shared with this app."])
        #expect(share(0, 4) == ["0% of senders are not in the contacts shared with this app."])
        #expect(share(4, 4) == ["100% of senders are not in the contacts shared with this app."])
    }

    @Test func displayedTextIsTheSpokenText() throws {
        let document = try briefing(calendar: .snapshot(calendar()), weather: .snapshot(weather()), locale: "fr_FR")
        let opening = compose(document, counts: [.unreadEmail: .available(2)])
        #expect(opening.displayText == opening.spokenText && opening.spokenText == opening.text)
        #expect(opening.text == opening.segments.map(\.text).joined(separator: " "))
        #expect(opening.segments.filter { $0.source == .greeting }.count == 1 && opening.segments.first?.source == .greeting)
        #expect(opening.segments.last?.source == .choice)
        #expect(Set(opening.segments.map(\.id)).count == opening.segments.count)
        #expect(opening == compose(document, counts: [.unreadEmail: .available(2)]), "Same input, same script.")
    }

    @Test func oneGreetingPerSessionWhateverElseHappens() {
        let morning = UUID(), nextMorning = UUID()
        var state = MorningGreetingState()
        func plays(_ trigger: MorningOpeningTrigger, _ session: UUID) -> Bool {
            state.claimPlayback(for: trigger, sessionID: session)
        }
        let others = MorningOpeningTrigger.allCases.filter { $0 != .morningStart }
        #expect(others == [.settingsPreview, .appLaunch, .dataRefresh, .tabSwitch])
        // Nothing but an explicit morning start plays, even before any greeting.
        var played = others.map { plays($0, morning) }
        #expect(played == [false, false, false, false] && state.greetedSessionID == nil)
        played = [plays(.morningStart, morning)]
        #expect(played == [true])
        // Same session: no trigger replays it, a second morning start included.
        played = MorningOpeningTrigger.allCases.map { plays($0, morning) }
        #expect(played == [false, false, false, false, false])
        // A preview, launch, refresh or tab switch that names another session resets nothing.
        played = others.map { plays($0, nextMorning) }
        #expect(played == [false, false, false, false] && state.greetedSessionID == morning)
        // Reset 1: a morning start for a different session.
        played = [plays(.morningStart, nextMorning), plays(.morningStart, nextMorning)]
        #expect(played == [true, false])
        // Reset 2: explicit forgetting.
        state.reset()
        played = [plays(.tabSwitch, nextMorning), plays(.morningStart, nextMorning)]
        #expect(played == [false, true])
    }

    @Test func greetedStateIsSavedWithoutAnyLanguage() throws {
        let session = try #require(UUID(uuidString: "0F1E2D3C-4B5A-4978-8695-A4B3C2D1E0F9"))
        let encoder = JSONEncoder()
        encoder.outputFormatting = .sortedKeys
        var saved: [Data] = []
        for locale in ["en_US", "fr_FR"] {
            let opening = try compose(briefing(weather: .snapshot(weather()), locale: locale))
            var state = MorningGreetingState()
            let played = state.claimPlayback(for: .morningStart, sessionID: session)
            #expect(played)
            let json = String(decoding: try encoder.encode(state), as: UTF8.self)
            #expect(json == #"{"greetedSessionID":"0F1E2D3C-4B5A-4978-8695-A4B3C2D1E0F9"}"#)
            #expect(!json.contains(opening.segments[0].text))
            saved.append(Data(json.utf8))
        }
        #expect(saved[0] == saved[1])
        // Saved beside a French opening, read back whatever the language is now.
        var restored = try JSONDecoder().decode(MorningGreetingState.self, from: saved[1])
        let replayed = restored.claimPlayback(for: .morningStart, sessionID: session)
        let next = restored.claimPlayback(for: .morningStart, sessionID: UUID())
        #expect(!replayed && next)
        #expect(try JSONDecoder().decode(MorningGreetingState.self, from: Data("{}".utf8)) == MorningGreetingState())
    }

    private func compose(_ briefing: PreparedMorningBriefing, at date: Date? = nil, zone: String = "UTC",
                         counts: [MorningOpeningProvider: MorningOpeningCount] = [:],
                         precipitation: MorningPrecipitationForecast? = nil,
                         unknownSenders: MorningUnknownSenderShare? = nil) -> MorningOpening {
        MorningOpeningComposer.compose(briefing: briefing, at: date ?? now, timeZoneIdentifier: zone, counts: counts,
                                       precipitation: precipitation, unknownSenders: unknownSenders)
    }
    private func briefing(calendar: MorningBriefingInput<CalendarSnapshot> = .notConfigured,
                          weather: MorningBriefingInput<WeatherObservationSnapshot> = .notConfigured,
                          locale: String = "en_US") throws -> PreparedMorningBriefing {
        try MorningBriefingComposer.prepare(calendar: calendar, weather: weather, for: now, at: now,
            timeZoneIdentifier: "UTC", localeIdentifier: locale)
    }
    private func calendar(retrievedAt: Date? = nil) -> CalendarSnapshot {
        var value = Calendar(identifier: .gregorian)
        value.timeZone = TimeZone(identifier: "UTC")!
        let bounds = value.dateInterval(of: .day, for: now)!
        return .init(retrievedAt: retrievedAt ?? now, dayStart: bounds.start, dayEnd: bounds.end, events: [],
                     timeZoneIdentifier: "UTC", selectedCalendars: [selection])
    }
    private func weather(condition: String = "Synthetic sunshine") throws -> WeatherObservationSnapshot {
        let attribution = try WeatherAttributionInfo(legalURL: URL(string: "https://example.invalid/legal")!,
            combinedMarkLightURL: URL(string: "https://example.invalid/light.png")!,
            combinedMarkDarkURL: URL(string: "https://example.invalid/dark.png")!, serviceName: "Synthetic Weather")
        return try .init(location: WeatherLocation(latitude: 10, longitude: 20, displayName: "Synthetic city"),
            retrievedAt: now, observationAt: now, temperatureCelsius: 20, conditionDescription: condition,
            symbolName: "sun.max", attribution: attribution, expiresAt: nil)
    }
}
