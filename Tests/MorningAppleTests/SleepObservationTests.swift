import Foundation
import Testing
@testable import MorningApple

/// Synthetic samples and a fixed clock. No health data is read anywhere in this file.
@Suite("Sleep duration — the totalling rule and its sentences, synthetic samples only")
struct SleepObservationTests {
    // Saturday 10 October 2026, 08:00 UTC. "Yesterday evening" starts on 9 October at 18:00.
    private let now = SleepFixtures.date("2026-10-10T08:00:00Z")

    // MARK: Totalling

    @Test func emptyAndInBedOnlyAreNoRecordAndAwakeTimeAddsNothing() {
        #expect(summary([]) == .noRecord)
        let inBedOnly = [sample(.inBed, "2026-10-09T22:00:00Z", "2026-10-10T07:00:00Z")]
        #expect(summary(inBedOnly) == .noRecord, "Time in bed is not sleep.")
        let night = [
            sample(.inBed, "2026-10-09T22:00:00Z", "2026-10-10T07:30:00Z"),
            sample(.asleepCore, "2026-10-09T23:40:00Z", "2026-10-10T03:00:00Z"),
            sample(.awake, "2026-10-10T03:00:00Z", "2026-10-10T03:30:00Z"),
            sample(.asleepREM, "2026-10-10T03:30:00Z", "2026-10-10T07:00:00Z")
        ]
        let observation = recorded(night)
        #expect(observation?.asleepMinutes == 200 + 210)
        #expect(observation?.windowStart == SleepFixtures.date("2026-10-09T23:40:00Z"))
        #expect(observation?.windowEnd == SleepFixtures.date("2026-10-10T07:00:00Z"), "The window is the asleep span, not the in-bed span.")
        #expect(observation?.readAt == now)
    }

    @Test func twoOverlappingSourcesCountEachMinuteOnce() {
        let samples = [
            sample(.asleepCore, "2026-10-09T23:40:00Z", "2026-10-10T02:00:00Z", source: "watch", kind: .watch),
            sample(.asleepDeep, "2026-10-10T02:00:00Z", "2026-10-10T07:00:00Z", source: "watch", kind: .watch),
            sample(.asleepUnspecified, "2026-10-09T23:00:00Z", "2026-10-10T06:00:00Z", source: "other-app", kind: .thirdPartyApp),
            // The same span twice from one source is still one span.
            sample(.asleepUnspecified, "2026-10-09T23:00:00Z", "2026-10-10T06:00:00Z", source: "other-app", kind: .thirdPartyApp)
        ]
        let observation = recorded(samples.shuffled())
        #expect(observation?.asleepMinutes == 480, "23:00 to 07:00 once, not 7 h 20 plus 7 h.")
        #expect(observation?.windowStart == SleepFixtures.date("2026-10-09T23:00:00Z"))
        #expect(observation?.windowEnd == SleepFixtures.date("2026-10-10T07:00:00Z"))
        #expect(observation?.sourceCount == 2 && observation?.sourceKinds == [.watch, .thirdPartyApp])
    }

    @Test func napsAreCountedByTheStatedRuleAndTheWindowShowsThem() {
        let night = sample(.asleepCore, "2026-10-09T23:40:00Z", "2026-10-10T07:00:00Z")
        let afternoonNap = sample(.asleepCore, "2026-10-09T14:00:00Z", "2026-10-09T15:00:00Z")
        let eveningNap = sample(.asleepCore, "2026-10-09T19:00:00Z", "2026-10-09T19:30:00Z")
        #expect(recorded([afternoonNap, night])?.asleepMinutes == 440, "Before yesterday 18:00 is not counted.")
        let withEvening = recorded([eveningNap, night])
        #expect(withEvening?.asleepMinutes == 470, "After 18:00 it is counted: nothing in the samples says it was a nap.")
        #expect(withEvening?.windowStart == SleepFixtures.date("2026-10-09T19:00:00Z"), "The window starts at the nap, so the total is not mistaken for one night.")
        let straddling = sample(.asleepCore, "2026-10-09T17:30:00Z", "2026-10-09T18:30:00Z")
        #expect(recorded([straddling])?.asleepMinutes == 60, "A sample across 18:00 is counted whole, as recorded.")
    }

    @Test func aBrokenNightKeepsBothHalves() {
        let samples = [
            sample(.asleepCore, "2026-10-09T23:00:00Z", "2026-10-10T02:00:00Z"),
            sample(.asleepCore, "2026-10-10T04:30:00Z", "2026-10-10T07:00:00Z")
        ]
        #expect(recorded(samples)?.asleepMinutes == 330, "No gap length is used to drop part of a night.")
    }

    @Test func olderRecordFutureSamplesAndInvalidSpansAreNotLastNight() {
        let older = sample(.asleepCore, "2026-10-08T23:00:00Z", "2026-10-09T07:00:00Z")
        #expect(summary([older]) == .olderRecord(endedAt: SleepFixtures.date("2026-10-09T07:00:00Z")))
        let atCutoff = sample(.asleepCore, "2026-10-09T17:00:00Z", "2026-10-09T18:00:00Z")
        #expect(summary([atCutoff]) == .olderRecord(endedAt: SleepFixtures.date("2026-10-09T18:00:00Z")), "Ending at 18:00 exactly is before the evening.")
        let future = sample(.asleepCore, "2026-10-10T07:00:00Z", "2026-10-10T09:00:00Z")
        #expect(summary([future]) == .noRecord, "A span that has not ended cannot be a record of past sleep.")
        let reversed = sample(.asleepCore, "2026-10-10T07:00:00Z", "2026-10-10T06:00:00Z")
        let tiny = SleepSample(stage: .asleepCore, start: now.addingTimeInterval(-3_620), end: now.addingTimeInterval(-3_600), sourceID: "s", sourceKind: .watch)
        #expect(summary([reversed, tiny]) == .noRecord, "Under half a minute is never reported as a night of zero minutes.")
        #expect(summary([older, tiny]) == .olderRecord(endedAt: SleepFixtures.date("2026-10-09T07:00:00Z")))
    }

    @Test func aNightAcrossMidnightAndAClockChangeIsElapsedTime() throws {
        // Europe/Paris leaves summer time on 25 October 2026: 03:00 becomes 02:00.
        let autumn = SleepFixtures.date("2026-10-25T07:00:00Z") // 08:00 in Paris
        let autumnNight = [sample(.asleepCore, "2026-10-24T21:40:00Z", "2026-10-25T06:00:00Z")] // 23:40 to 07:00 in Paris
        guard case .recorded(let longer) = SleepNight.summarize(autumnNight, readAt: autumn, at: autumn,
            calendar: SleepFixtures.calendar("Europe/Paris")) else { Issue.record("No night found."); return }
        #expect(longer.asleepMinutes == 500, "23:40 to 07:00 is 8 h 20 of elapsed time on the night the clock goes back.")
        let french = try MorningBriefingComposer.prepare(calendar: .notConfigured, weather: .notConfigured,
            sleep: .snapshot(.init(readAt: autumn, samples: autumnNight)), for: autumn, at: autumn,
            timeZoneIdentifier: "Europe/Paris", localeIdentifier: "fr_FR")
        #expect(french.sleep.text == "Sommeil enregistré : 8 heures 20 minutes, entre 23:40 et 07:00.")

        // It enters summer time on 29 March 2026: 02:00 becomes 03:00.
        let spring = SleepFixtures.date("2026-03-29T06:00:00Z") // 08:00 in Paris
        let springNight = [sample(.asleepCore, "2026-03-28T22:40:00Z", "2026-03-29T05:00:00Z")] // 23:40 to 07:00 in Paris
        guard case .recorded(let shorter) = SleepNight.summarize(springNight, readAt: spring, at: spring,
            calendar: SleepFixtures.calendar("Europe/Paris")) else { Issue.record("No night found."); return }
        #expect(shorter.asleepMinutes == 380, "The same wall-clock times are 6 h 20 when the clock goes forward.")
        // Yesterday 18:00 is a wall-clock hour: 17:00 UTC in winter time, on a day of 23 hours.
        #expect(SleepNight.eveningCutoff(before: spring, calendar: SleepFixtures.calendar("Europe/Paris"))
                == SleepFixtures.date("2026-03-28T17:00:00Z"))
        #expect(SleepNight.eveningCutoff(before: autumn, calendar: SleepFixtures.calendar("Europe/Paris"))
                == SleepFixtures.date("2026-10-24T16:00:00Z"))
    }

    @Test func sourceKindUsesOnlyWhatTheSourceRecordExposes() {
        #expect(SleepSourceKind.classify(bundleIdentifier: "com.apple.health.SYNTHETIC", productType: "Watch7,1", wasUserEntered: false) == .watch)
        #expect(SleepSourceKind.classify(bundleIdentifier: "com.apple.health.SYNTHETIC", productType: "iPhone17,1", wasUserEntered: false) == .phone)
        #expect(SleepSourceKind.classify(bundleIdentifier: "com.apple.Health", productType: "iPhone17,1", wasUserEntered: true) == .manualEntry)
        #expect(SleepSourceKind.classify(bundleIdentifier: "invalid.example.sleep", productType: "iPhone17,1", wasUserEntered: false) == .thirdPartyApp,
                "Another app's hardware model is the device it ran on, not a phone measurement.")
        #expect(SleepSourceKind.classify(bundleIdentifier: "com.apple.health.SYNTHETIC", productType: nil, wasUserEntered: false) == .unknown)
        #expect(SleepSourceKind.classify(bundleIdentifier: "com.apple.health.SYNTHETIC", productType: "iPad16,1", wasUserEntered: false) == .unknown)
    }

    // MARK: Sentences

    @Test func freshNightSaysDurationAndWindowOnlyInEnglishAndFrench() throws {
        let night = [sample(.asleepCore, "2026-10-09T23:40:00Z", "2026-10-10T07:00:00Z", kind: .watch)]
        let english = try prepare(sleep: .snapshot(.init(readAt: now, samples: night)), locale: "en_GB")
        #expect(english.sleep.status == .fresh && english.sleep.issue == nil)
        #expect(english.sleep.text == "Sleep recorded: 7 hours 20 minutes, between 23:40 and 07:00.")
        #expect(english.sleep.sourceLabels == ["Watch"] && english.sleep.statusText == "Read from the Health data on this device.")
        #expect(english.sleep.retrievedAt == now && english.sleep.observationAt == SleepFixtures.date("2026-10-10T07:00:00Z"))
        #expect(english.sleepObservation?.asleepMinutes == 440)
        #expect(english.hasUsableFacts && english.segments.map(\.source) == [.introduction, .sleep])
        #expect(english.displayText.components(separatedBy: "\n") == english.segments.map(\.text))
        #expect(english.spokenText == english.segments.map(\.text).joined(separator: " "), "Displayed and spoken text are the same sentences.")

        let american = try prepare(sleep: .snapshot(.init(readAt: now, samples: night)), locale: "en_US")
        let clock = DateFormatter()
        clock.locale = Locale(identifier: "en_US"); clock.timeZone = TimeZone(identifier: "UTC")
        clock.dateStyle = .none; clock.timeStyle = .short
        #expect(american.sleep.text == "Sleep recorded: 7 hours 20 minutes, between \(clock.string(from: night[0].start)) and \(clock.string(from: night[0].end)).")
        #expect(american.sleep.text.contains("PM") && american.sleep.text.contains("AM"), "Clock times follow the briefing's locale.")

        let french = try prepare(sleep: .snapshot(.init(readAt: now, samples: night)), locale: "fr_FR")
        #expect(french.sleep.text == "Sommeil enregistré : 7 heures 20 minutes, entre 23:40 et 07:00.")
        #expect(french.sleep.sourceLabels == ["Montre"] && french.sleep.statusText == "Lu depuis les données Santé de cet appareil.")
    }

    @Test func durationsAreWordsWithTheRightPlural() throws {
        let english = try #require(MorningBriefingPhrases(locale: Locale(identifier: "en_US")))
        let french = try #require(MorningBriefingPhrases(locale: Locale(identifier: "fr_FR")))
        #expect([1, 45, 60, 61, 122, 600].map(english.duration)
                == ["1 minute", "45 minutes", "1 hour", "1 hour 1 minute", "2 hours 2 minutes", "10 hours"])
        #expect([1, 45, 60, 61, 122, 600].map(french.duration)
                == ["1 minute", "45 minutes", "1 heure", "1 heure 1 minute", "2 heures 2 minutes", "10 heures"])
    }

    @Test func excludedNotConnectedAndUnavailableAreNeverSpoken() throws {
        for input in [SleepBriefingInput.excluded, .notConnected, .unavailableOnDevice] {
            for locale in ["en_US", "fr_FR"] {
                let document = try prepare(calendar: .snapshot(calendar()), sleep: input, locale: locale)
                #expect(document.hasUsableFacts && document.sleep.segments.isEmpty)
                #expect(!document.segments.contains { $0.source == .sleep })
                #expect(document.sleepObservation == nil && document.sleep.validUntil == nil)
                // Exactly the briefing that has no sleep input at all: nothing is heard, and so no zero.
                let without = try MorningBriefingComposer.prepare(calendar: .snapshot(calendar()), weather: .notConfigured,
                    for: now, at: now, timeZoneIdentifier: "UTC", localeIdentifier: locale)
                #expect(document.spokenText == without.spokenText && document.displayText == without.displayText)
                for word in ["leep", "ommeil", "ealth", "anté", "minute", "hour", "heure"] {
                    #expect(!document.spokenText.contains(word), "\(input) must not be heard, and never as zero.")
                }
            }
        }
        let excluded = try prepare(sleep: .excluded)
        #expect(excluded.sleep.status == .notConfigured && excluded.sleep.issue == .notConfigured)
        let unavailable = try prepare(sleep: .unavailableOnDevice)
        #expect(unavailable.sleep.status == .unavailable && unavailable.sleep.issue == .unavailableOnDevice)
        #expect(unavailable.sleep.statusText == "Health data is not available on this device.")
        #expect(try prepare(sleep: .unavailableOnDevice, locale: "fr_FR").sleep.statusText
                == "Les données de santé ne sont pas disponibles sur cet appareil.")
        let notConnected = try prepare(sleep: .notConnected)
        #expect(notConnected.sleep.status == .unavailable && notConnected.sleep.issue == .sourceUnavailable)
        #expect(notConnected.sleep.statusText == "Sleep reading is not part of this version.")
        #expect(!excluded.hasUsableFacts && !unavailable.hasUsableFacts && !notConnected.hasUsableFacts)
    }

    @Test func missingOlderAndUnreadableAreSaidPlainlyBesideOtherFacts() throws {
        let older = [sample(.asleepCore, "2026-10-08T23:00:00Z", "2026-10-09T07:00:00Z")]
        let cases: [(SleepBriefingInput, MorningBriefingSourceStatus, MorningBriefingSourceIssue, String, String)] = [
            (.snapshot(.init(readAt: now, samples: [])), .missing, .noRecord,
             "No sleep record was found since yesterday evening.", "Aucun relevé de sommeil trouvé depuis hier soir."),
            (.snapshot(.init(readAt: now, samples: older)), .stale, .olderRecord,
             "The latest sleep record ended on 9 October at 07:00.", "Le dernier relevé de sommeil s’est terminé le 9 octobre à 07:00."),
            (.notReadable, .unavailable, .notReadable,
             "Sleep data could not be read.", "Les données de sommeil n’ont pas pu être lues."),
            (.snapshot(.init(readAt: now.addingTimeInterval(-1_800), samples: older)), .stale, .expired,
             "Sleep data needs a fresh update.", "Les données de sommeil doivent être mises à jour."),
            (.snapshot(.init(readAt: now.addingTimeInterval(1), samples: older)), .unavailable, .futureTimestamp,
             "Sleep data could not be read.", "Les données de sommeil n’ont pas pu être lues.")
        ]
        for (input, status, issue, english, french) in cases {
            let alone = try prepare(sleep: input, locale: "en_GB")
            #expect(alone.sleep.status == status && alone.sleep.issue == issue && alone.sleep.statusText == english)
            #expect(!alone.hasUsableFacts && alone.spokenText.isEmpty && alone.sleepObservation == nil,
                    "Without a fact there is no briefing to speak.")
            let beside = try prepare(calendar: .snapshot(calendar()), sleep: input, locale: "en_GB")
            #expect(beside.segments.last == .init(id: "sleep.status", source: .sleep, text: english))
            #expect(beside.displayText.hasSuffix(english) && beside.spokenText.hasSuffix(english))
            let besideFrench = try prepare(calendar: .snapshot(calendar()), sleep: input, locale: "fr_FR")
            #expect(besideFrench.segments.last?.text == french && besideFrench.sleep.statusText == french)
        }
    }

    /// The issue forbids a diagnosis, and the API cannot report a refused read.
    @Test func noSentenceJudgesAdvisesOrMentionsPermission() throws {
        let night = [sample(.asleepCore, "2026-10-10T03:00:00Z", "2026-10-10T05:10:00Z")] // A short night stays a number.
        let older = [sample(.asleepCore, "2026-10-08T23:00:00Z", "2026-10-09T07:00:00Z")]
        let inputs: [SleepBriefingInput] = [.excluded, .notConnected, .unavailableOnDevice, .notReadable,
            .snapshot(.init(readAt: now, samples: [])), .snapshot(.init(readAt: now, samples: older)),
            .snapshot(.init(readAt: now, samples: night)), .snapshot(.init(readAt: now.addingTimeInterval(-3_600), samples: night))]
        let forbidden = ["permission", "denied", "allow", "authoriz", "access", "refus", "autoris", "accès", "interdit",
            "only", "just ", "enough", "short", "poor", "good", "well", "bad", "quality", "score", "should", "recommend",
            "try to", "rest", "tired", "seulement", "assez", "peu", "bien", "mal ", "mauvais", "qualité", "devriez",
            "conseil", "fatigu", "repos", "insuffisant"]
        for input in inputs {
            for locale in ["en_US", "en_GB", "fr_FR", "fr_CA"] {
                let document = try prepare(calendar: .snapshot(calendar()), sleep: input, locale: locale)
                let sleepText = ([document.sleep.statusText] + document.sleep.segments.map(\.text) + document.sleep.sourceLabels)
                    .joined(separator: " ").lowercased()
                for word in forbidden { #expect(!sleepText.contains(word), "\"\(word)\" in: \(sleepText)") }
            }
        }
        let short = try prepare(sleep: .snapshot(.init(readAt: now, samples: night)), locale: "en_GB")
        #expect(short.sleep.text == "Sleep recorded: 2 hours 10 minutes, between 03:00 and 05:10.")
    }

    @Test func aReadIsUsedForHalfAnHourAndNeverPastMidnight() throws {
        let night = [sample(.asleepCore, "2026-10-09T23:40:00Z", "2026-10-10T07:00:00Z")]
        let read = now.addingTimeInterval(-1_799)
        let fresh = try prepare(sleep: .snapshot(.init(readAt: read, samples: night)))
        #expect(fresh.sleep.status == .fresh && fresh.sleep.validUntil == read.addingTimeInterval(1_800))
        #expect(fresh.validUntil == read.addingTimeInterval(1_800))
        #expect(fresh.isCurrent(at: now, timeZoneIdentifier: "UTC") && !fresh.isCurrent(at: now.addingTimeInterval(1), timeZoneIdentifier: "UTC"))
        #expect(throws: MorningBriefingError.invalidPolicy) {
            try MorningBriefingComposer.prepare(calendar: .notConfigured, weather: .notConfigured, sleep: .excluded,
                for: now, at: now, timeZoneIdentifier: "UTC", policy: .init(sleepMaximumAge: 0))
        }
    }

    @Test @MainActor func sleepIsThirdAfterCalendarAndWeatherAndStaysOutOfCalendarOnlySpeech() throws {
        let night = [sample(.asleepCore, "2026-10-09T23:40:00Z", "2026-10-10T07:00:00Z")]
        let document = try prepare(calendar: .snapshot(calendar()), weather: .snapshot(SleepFixtures.weather(at: now)),
                                   sleep: .snapshot(.init(readAt: now, samples: night)), locale: "en_GB")
        #expect(document.segments.map(\.source) == [.introduction, .calendar, .weather, .sleep])
        let full = MorningAppStepExecutor.text(for: .morningBriefing, in: document)
        #expect(full == document.spokenText && full.hasSuffix("Sleep recorded: 7 hours 20 minutes, between 23:40 and 07:00."))
        let calendarOnly = MorningAppStepExecutor.text(for: .todayCalendar, in: document)
        #expect(!calendarOnly.contains("Sleep") && !calendarOnly.contains("Weather") && calendarOnly.contains("No remaining events"))
    }

    @Test func aBriefThatHoldsOnlyACurrentNightIsStillOfferedAndTheOpeningDoesNotQuoteIt() throws {
        let night = [sample(.asleepCore, "2026-10-09T23:40:00Z", "2026-10-10T07:00:00Z")]
        let document = try prepare(sleep: .snapshot(.init(readAt: now, samples: night)))
        let opening = MorningOpeningComposer.compose(briefing: document, at: now, timeZoneIdentifier: "UTC")
        #expect(opening.choices == [.brief, .ritual, .stop])
        #expect(!opening.text.contains("Sleep") && !opening.text.contains("hours"))
        let later = MorningOpeningComposer.compose(briefing: document, at: now.addingTimeInterval(1_800), timeZoneIdentifier: "UTC")
        #expect(later.choices == [.ritual, .stop], "An expired read is not a brief.")
        let missing = try prepare(sleep: .snapshot(.init(readAt: now, samples: [])))
        #expect(MorningOpeningComposer.compose(briefing: missing, at: now, timeZoneIdentifier: "UTC").choices == [.ritual, .stop])
    }

    // MARK: Helpers

    private func summary(_ samples: [SleepSample]) -> SleepNightSummary {
        SleepNight.summarize(samples, readAt: now, at: now, calendar: SleepFixtures.calendar("UTC"))
    }
    private func recorded(_ samples: [SleepSample]) -> SleepObservation? {
        if case .recorded(let observation) = summary(samples) { return observation }
        return nil
    }
    private func sample(_ stage: SleepStage, _ start: String, _ end: String, source: String = "synthetic-source",
                        kind: SleepSourceKind = .watch) -> SleepSample {
        SleepFixtures.sample(stage, start, end, source: source, kind: kind)
    }
    private func prepare(calendar: MorningBriefingInput<CalendarSnapshot> = .notConfigured,
                         weather: MorningBriefingInput<WeatherObservationSnapshot> = .notConfigured,
                         sleep: SleepBriefingInput, locale: String = "en_US") throws -> PreparedMorningBriefing {
        try MorningBriefingComposer.prepare(calendar: calendar, weather: weather, sleep: sleep, for: now, at: now,
            timeZoneIdentifier: "UTC", localeIdentifier: locale)
    }
    private func calendar() -> CalendarSnapshot {
        let bounds = SleepFixtures.calendar("UTC").dateInterval(of: .day, for: now)!
        return .init(retrievedAt: now, dayStart: bounds.start, dayEnd: bounds.end, events: [], timeZoneIdentifier: "UTC",
            selectedCalendars: [CalendarChoice(id: "selected", title: "Synthetic calendar", sourceTitle: "Synthetic local source")])
    }
}

/// Labeled synthetic values shared by the sleep suites.
enum SleepFixtures {
    static func date(_ text: String) -> Date { ISO8601DateFormatter().date(from: text)! }
    static func calendar(_ zone: String) -> Calendar {
        var value = Calendar(identifier: .gregorian)
        value.timeZone = TimeZone(identifier: zone)!
        return value
    }
    static func sample(_ stage: SleepStage, _ start: String, _ end: String, source: String = "synthetic-source",
                       kind: SleepSourceKind = .watch) -> SleepSample {
        SleepSample(stage: stage, start: date(start), end: date(end), sourceID: source, sourceKind: kind)
    }
    static func weather(at now: Date) throws -> WeatherObservationSnapshot {
        let attribution = try WeatherAttributionInfo(legalURL: URL(string: "https://example.invalid/legal")!,
            combinedMarkLightURL: URL(string: "https://example.invalid/light.png")!,
            combinedMarkDarkURL: URL(string: "https://example.invalid/dark.png")!, serviceName: "Synthetic Weather")
        return try .init(location: WeatherLocation(latitude: 10, longitude: 20, displayName: "Synthetic city"),
            retrievedAt: now, observationAt: now, temperatureCelsius: 20, conditionDescription: "Synthetic sunshine",
            symbolName: "sun.max", attribution: attribution)
    }
}
