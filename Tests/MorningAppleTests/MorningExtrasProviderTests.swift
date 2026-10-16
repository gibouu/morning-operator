import Foundation
import MorningCore
import Testing
@testable import MorningApple

@Suite("Morning extras readers — synthetic sources only")
@MainActor
struct MorningExtrasProviderTests {
    private let paris = TimeZone(identifier: "Europe/Paris")!
    /// 08:00 in Paris on 13 October 2026.
    private let morning = Date(timeIntervalSince1970: 1_791_871_200)

    private func calendar() -> Calendar {
        var calendar = Calendar(identifier: .gregorian); calendar.timeZone = paris; return calendar
    }

    private func frame() throws -> MorningExtrasFrame { try #require(MorningExtrasFrame(now: morning, timeZone: paris)) }

    private func directory() throws -> URL {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("extras-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }

    // MARK: Facts

    @Test func theFrameUsesLocalMidnightsIncludingAClockChange() throws {
        // 26 October 2026 is the day after Paris leaves summer time: 25 October has 25 hours.
        let monday = Date(timeIntervalSince1970: 1_792_998_000) // 26 Oct 2026, 08:00 CET
        let frame = try #require(MorningExtrasFrame(now: monday, timeZone: paris))
        #expect(frame.yesterday.duration == 25 * 3_600)
        #expect(frame.previousWeek.count == 7)
        #expect(frame.previousWeek.allSatisfy { $0.duration == 24 * 3_600 })
        #expect(frame.previousWeek.first?.end == frame.yesterday.start)
        // Havana skips from midnight to 01:00 on 8 March 2026: that day starts at 01:00.
        let havana = TimeZone(identifier: "America/Havana")!
        let ninth = Date(timeIntervalSince1970: 1_773_057_600) // 9 Mar 2026, 08:00 CDT
        let havanaFrame = try #require(MorningExtrasFrame(now: ninth, timeZone: havana))
        var local = Calendar(identifier: .gregorian); local.timeZone = havana
        #expect(havanaFrame.yesterday == local.dateInterval(of: .day, for: ninth.addingTimeInterval(-86_400)))
        #expect(havanaFrame.yesterday.end == havanaFrame.todayStart)
    }

    @Test func stepsNeedYesterdayAndEnoughDaysForAnAverage() {
        #expect(MorningExtrasFacts.steps([nil, 5_000, 5_000, 5_000, 5_000, 5_000, 5_000, 5_000]) == nil)
        #expect(MorningExtrasFacts.steps([0, 5_000, 5_000, 5_000, 5_000]) == nil)
        // Missing days are left out of the mean, not counted as zero.
        #expect(MorningExtrasFacts.steps([8_000, 6_000, nil, 4_000, nil, 5_000, nil, 9_000])
            == .steps(yesterday: 8_000, weeklyAverage: 6_000))
        // Fewer than four recorded days: no comparison at all.
        #expect(MorningExtrasFacts.steps([8_000, 6_000, nil, 4_000, nil, nil, nil, 9_000])
            == .steps(yesterday: 8_000, weeklyAverage: nil))
    }

    @Test func aRecordedZeroDayCountsInTheMean() {
        // 0, 0, 0, 60, 60, 60, 60 averages 34 minutes, not 60: zero is a real day.
        #expect(MorningExtrasFacts.screenTime([60, 0, 0, 0, 60, 60, 60, 60])
            == .screenTime(yesterdayMinutes: 60, weeklyAverageMinutes: 34))
        // An all-zero week has no mean to compare with.
        #expect(MorningExtrasFacts.steps([5_000, 0, 0, 0, 0, nil, nil, nil]) == .steps(yesterday: 5_000, weeklyAverage: nil))
    }

    @Test func cityDaysAreMatchedInTheCitysOwnDays() {
        // A Tokyo day starts at 15:00 UTC the day before. "Now" is 06:00 UTC = 15:00 in Tokyo.
        let now = Date(timeIntervalSince1970: 1_791_871_200)
        let tokyoToday = now.addingTimeInterval(-15 * 3_600)
        let days = [(start: tokyoToday.addingTimeInterval(-86_400), highCelsius: 25.0),
                    (start: tokyoToday, highCelsius: 15.0),
                    (start: tokyoToday.addingTimeInterval(86_400), highCelsius: 14.0)]
        let highs = MorningExtrasFacts.cityDayHighs(days, now: now)
        #expect(highs.yesterday == 25 && highs.today == 15)
        // Data ending yesterday: at 00:30 in the city, yesterday's entry is not today's.
        let ended = MorningExtrasFacts.cityDayHighs(Array(days.prefix(2)), now: tokyoToday.addingTimeInterval(86_400 + 1_800))
        #expect(ended.today == nil)
        // A gap in the days is no record, not a comparison with an older day.
        let gap = MorningExtrasFacts.cityDayHighs([days[0], days[2], (start: tokyoToday.addingTimeInterval(2 * 86_400), highCelsius: 9)],
                                                  now: now.addingTimeInterval(86_400))
        #expect(gap.yesterday == nil && gap.today == 14)
        #expect(MorningExtrasFacts.cityDayHighs([], now: now) == (nil, nil))
        // Today's entry missing: yesterday's is 25 hours old and must not stand in for today.
        let missing = MorningExtrasFacts.cityDayHighs([days[0], days[1], (start: tokyoToday.addingTimeInterval(2 * 86_400), highCelsius: 30)],
                                                      now: tokyoToday.addingTimeInterval(86_400 + 3_600))
        #expect(missing.today == nil && missing.yesterday == nil)
    }

    @Test func screenTimeHookFollowsTheSameRules() {
        #expect(MorningExtrasFacts.screenTime([nil, 60, 60, 60, 60]) == nil)
        #expect(MorningExtrasFacts.screenTime([90, 60, 60, 60, 60, nil, nil, nil])
            == .screenTime(yesterdayMinutes: 90, weeklyAverageMinutes: 60))
    }

    private func sample(_ stage: SleepStage, _ start: TimeInterval, _ end: TimeInterval) -> SleepSample {
        SleepSample(stage: stage, start: morning.addingTimeInterval(start), end: morning.addingTimeInterval(end),
                    sourceID: "com.apple.health.synthetic", sourceKind: .phone)
    }

    @Test func sleepPrefersAsleepStagesAndFallsBackToInBedFromTheIPhone() {
        let watchNight = [sample(.asleepCore, -8 * 3_600, -3_600), sample(.inBed, -9 * 3_600, -1_800)]
        #expect(MorningExtrasFacts.sleep(.snapshot(.init(readAt: morning, samples: watchNight)), at: morning, timeZone: paris)
            == .sleptMinutes(420))
        // An iPhone with a sleep schedule and no watch: overlapping in-bed spans count once.
        let phoneNight = [sample(.inBed, -9 * 3_600, -3_600), sample(.inBed, -2 * 3_600, -1_800)]
        #expect(MorningExtrasFacts.sleep(.snapshot(.init(readAt: morning, samples: phoneNight)), at: morning, timeZone: paris)
            == .inBedMinutes(510))
        // Nothing since yesterday evening, or no reader, is silence.
        let old = [sample(.inBed, -40 * 3_600, -32 * 3_600)]
        #expect(MorningExtrasFacts.sleep(.snapshot(.init(readAt: morning, samples: old)), at: morning, timeZone: paris) == nil)
        #expect(MorningExtrasFacts.sleep(.snapshot(.init(readAt: morning, samples: [])), at: morning, timeZone: paris) == nil)
        #expect(MorningExtrasFacts.sleep(.notReadable, at: morning, timeZone: paris) == nil)
        #expect(MorningExtrasFacts.sleep(.notConnected, at: morning, timeZone: paris) == nil)
    }

    @Test func weatherSaysTheFirstLikelyHourAndTheHighChange() throws {
        let frame = try frame()
        let outlook = WeatherOutlook(yesterdayHighCelsius: 22, todayHighCelsius: 12, hours: [
            .init(start: morning.addingTimeInterval(3_600), chance: 0.3, kind: .rain),
            .init(start: morning.addingTimeInterval(8 * 3_600), chance: 0.7, kind: .rain),
            .init(start: morning.addingTimeInterval(9 * 3_600), chance: 0.9, kind: .snow)])
        let facts = MorningExtrasFacts.weather(outlook, frame: frame, unit: .fahrenheit)
        #expect(facts == [.precipitation(.rain, from: morning.addingTimeInterval(8 * 3_600)),
                          .temperatureChange(celsiusDelta: -10, unit: .fahrenheit)])
        // Rain in the current hour is "now"; rain tomorrow, a dry hour or a chance above 1 is not today's rain.
        let now = WeatherOutlook(yesterdayHighCelsius: nil, todayHighCelsius: 12, hours: [
            .init(start: morning.addingTimeInterval(-600), chance: 0.8, kind: .rain)])
        #expect(MorningExtrasFacts.weather(now, frame: frame, unit: .celsius) == [.precipitation(.rain, from: nil)])
        let none = WeatherOutlook(yesterdayHighCelsius: nil, todayHighCelsius: nil, hours: [
            .init(start: frame.todayEnd.addingTimeInterval(3_600), chance: 0.9, kind: .rain),
            .init(start: morning.addingTimeInterval(3_600), chance: 0.9, kind: nil),
            .init(start: morning.addingTimeInterval(3_600), chance: 1.5, kind: .rain)])
        #expect(MorningExtrasFacts.weather(none, frame: frame, unit: .celsius).isEmpty)
    }

    private func event(_ title: String, _ start: TimeInterval, _ end: TimeInterval, allDay: Bool = false) -> CalendarEventSummary {
        CalendarEventSummary(id: title, title: title, start: morning.addingTimeInterval(start * 60),
                             end: morning.addingTimeInterval(end * 60), isAllDay: allDay, calendarTitle: "Synthetic")
    }

    @Test func calendarFindsTheFirstOverlapOrTightGap() throws {
        let frame = try frame()
        #expect(MorningExtrasFacts.calendar([event("A", 60, 120), event("B", 90, 150)], frame: frame)
            == .calendarConflict(first: "A", second: "B", at: morning.addingTimeInterval(90 * 60)))
        #expect(MorningExtrasFacts.calendar([event("A", 60, 120), event("B", 125, 150)], frame: frame)
            == .tightGap(minutes: 5, first: "A", second: "B", at: morning.addingTimeInterval(125 * 60)))
        // All-day events, finished events and comfortable gaps are not clashes.
        #expect(MorningExtrasFacts.calendar([event("Holiday", -480, 960, allDay: true), event("A", 60, 120),
                                             event("Done", -120, -60), event("B", 180, 200)], frame: frame) == nil)
        // A clash that started before now (yesterday evening) is not announced.
        #expect(MorningExtrasFacts.calendar([event("Night A", -600, 120), event("Night B", -540, 60)], frame: frame) == nil)
        // An event nested in a long one is still a clash with the long one.
        #expect(MorningExtrasFacts.calendar([event("Long", 0, 300), event("Short", 30, 60), event("Late", 120, 150)], frame: frame)
            == .calendarConflict(first: "Long", second: "Short", at: morning.addingTimeInterval(30 * 60)))
    }

    // MARK: Provider and permissions

    @Test func readingNeverPromptsAndHealthIsNotReadBeforeItsPrompt() async throws {
        let health = SyntheticHealth(steps: [7_000, 6_000, 6_000, 6_000, 6_000, nil, nil, nil])
        let provider = MorningExtrasProvider(store: MorningExtrasPreferencesStore(directory: try directory()),
                                             health: health, clock: ManualTestClock())
        #expect(!provider.hasReadableSources(weatherLocation: nil, calendarSelected: false))
        let silent = await prepare(provider)
        #expect(silent.items.isEmpty)
        #expect(health.prompts == 0 && health.reads == 0)

        try await provider.setEnabled(.steps, true)
        #expect(health.prompts == 1)
        #expect(provider.hasReadableSources(weatherLocation: nil, calendarSelected: false))
        let spoken = await prepare(provider)
        #expect(spoken.text == "Yesterday: 7,000 steps, about 1,000 more than your 7-day average.")
        #expect(health.prompts == 1)
    }

    @Test func explicitHealthActivationRequestsOnlyItsOwnType() async throws {
        let health = SyntheticHealth(steps: [])
        let provider = MorningExtrasProvider(store: nil, health: health)
        try await provider.setEnabled(.sleep, true)
        #expect(health.requestedSleep && !health.requestedSteps)
        #expect(provider.preferences.confirmedHealthKinds == [.sleep])
        try await provider.setEnabled(.steps, true)
        #expect(!health.requestedSleep && health.requestedSteps)
        #expect(provider.preferences.confirmedHealthKinds == [.sleep, .steps])
    }

    @Test func inheritedHealthDefaultsDoNotReadUntilExplicitlyEnabled() async throws {
        let folder = try directory()
        let store = MorningExtrasPreferencesStore(directory: folder)
        let legacy = Data(#"{"enabled":["sleep","steps"],"healthAccessRequested":true,"lastSpokenDay":{}}"#.utf8)
        try store.save(JSONDecoder().decode(MorningExtrasPreferences.self, from: legacy))
        let health = SyntheticHealth(steps: [7000, 6000, 6000, 6000, 6000, nil, nil, nil])
        let provider = MorningExtrasProvider(store: store, health: health)
        #expect((await prepare(provider)).items.isEmpty)
        #expect(health.reads == 0 && health.prompts == 0)
        #expect(provider.preferences.enabled == [.sleep, .steps])
        try await provider.setEnabled(.steps, true)
        #expect(provider.preferences.confirmedHealthKinds == [.steps])
    }

    @Test func anAuthorizationReturningAfterForgetCannotRestorePreferences() async throws {
        let folder = try directory()
        let health = ControlledExtrasHealth()
        let provider = MorningExtrasProvider(store: MorningExtrasPreferencesStore(directory: folder), health: health)
        let request = Task { () -> Bool in
            do { try await provider.setEnabled(.sleep, true); return false }
            catch { return true }
        }
        while health.waiting == nil { await Task.yield() }
        let control = LocalDataControl(directory: folder)
        let generation = try #require(try control.beginForget().generation)
        try control.finishForget(expectedGeneration: generation)
        provider.reload()
        health.waiting?.resume(); health.waiting = nil
        #expect(await request.value)
        #expect(provider.preferences.enabled.isEmpty)
        #expect(!FileManager.default.fileExists(atPath: folder.appendingPathComponent(MorningExtrasPreferencesStore.fileName).path))
    }

    @Test func onlyTurningAKindOnMayPrompt() async throws {
        let health = SyntheticHealth(steps: [])
        let birthdays = SyntheticBirthdays()
        let provider = MorningExtrasProvider(store: MorningExtrasPreferencesStore(directory: try directory()),
                                             health: health, birthdays: birthdays)
        try await provider.setEnabled(.steps, false)
        try await provider.setEnabled(.weatherChange, true)
        try await provider.setEnabled(.calendar, true)
        #expect(health.prompts == 0 && birthdays.prompts == 0)
        try await provider.setEnabled(.birthday, true)
        #expect(birthdays.prompts == 1)
        try await provider.setEnabled(.steps, true)
        #expect(health.prompts == 1)
        #expect(provider.preferences.healthAccessRequested)
    }

    @Test func choicesAndRotationAreSavedButNoValue() async throws {
        let folder = try directory()
        let health = SyntheticHealth(steps: [7_000, nil, nil, nil, nil, nil, nil, nil])
        let provider = MorningExtrasProvider(store: MorningExtrasPreferencesStore(directory: folder),
                                             health: health, clock: ManualTestClock())
        try await provider.setEnabled(.steps, true)
        let selection = await prepare(provider)
        provider.recordSpoken(selection, now: morning, timeZone: paris)
        let reloaded = MorningExtrasProvider(store: MorningExtrasPreferencesStore(directory: folder))
        #expect(reloaded.preferences.healthAccessRequested)
        #expect(reloaded.preferences.lastSpokenDay["steps"] == MorningExtrasDay.number(for: morning, timeZone: paris))
        let saved = try String(contentsOf: folder.appendingPathComponent(MorningExtrasPreferencesStore.fileName), encoding: .utf8)
        #expect(!saved.contains("7000") && !saved.contains("7,000"))
    }

    @Test(.timeLimit(.minutes(1))) func aHangingSourceIsSilentAfterTheDeadline() async throws {
        let health = SyntheticHealth(steps: [7_000, nil, nil, nil, nil, nil, nil, nil], hang: true)
        defer { health.releaseRead() }
        let clock = ManualTestClock()
        let provider = MorningExtrasProvider(store: MorningExtrasPreferencesStore(directory: try directory()),
                                             health: health, timeout: .milliseconds(50), clock: clock)
        try await provider.setEnabled(.steps, true)
        var finished = false
        let attempt = Task { let selection = await prepare(provider); finished = true; return selection }
        defer { attempt.cancel() }
        await clock.waitForSleepers()
        while health.waitingRead == nil { try Task.checkCancellation(); await Task.yield() }
        clock.advance(by: .milliseconds(49))
        #expect(!finished && clock.sleeperCount == 1)
        clock.advance(by: .milliseconds(1))
        let selection = await attempt.value
        #expect(selection.items.isEmpty)
        #expect(health.waitingRead != nil, "The deadline must return before the reader is released.")
        #expect(clock.sleeperCount == 0)
        health.releaseRead()
        while !health.readFinished { try Task.checkCancellation(); await Task.yield() }
        #expect(health.readWasCancelled && selection.items.isEmpty)
    }

    @Test(.timeLimit(.minutes(1))) func cancellationReleasesTheCallerAndDeadlineBeforeTheReader() async throws {
        let health = SyntheticHealth(steps: [7_000, nil, nil, nil, nil, nil, nil, nil], hang: true)
        defer { health.releaseRead() }
        let clock = ManualTestClock()
        let provider = MorningExtrasProvider(store: MorningExtrasPreferencesStore(directory: try directory()),
                                             health: health, clock: clock)
        try await provider.setEnabled(.steps, true)
        let attempt = Task { await prepare(provider) }
        defer { attempt.cancel() }
        await clock.waitForSleepers()
        while health.waitingRead == nil { try Task.checkCancellation(); await Task.yield() }
        attempt.cancel()
        #expect(await attempt.value == .empty)
        #expect(health.waitingRead != nil && clock.sleeperCount == 0)
        health.releaseRead()
        while !health.readFinished { try Task.checkCancellation(); await Task.yield() }
        #expect(health.readWasCancelled)
    }

    @Test(.timeLimit(.minutes(1))) func anAnsweredSourceCancelsItsUnusedDeadline() async throws {
        let health = SyntheticHealth(steps: [7_000, nil, nil, nil, nil, nil, nil, nil], hang: true)
        defer { health.releaseRead() }
        let clock = ManualTestClock()
        let provider = MorningExtrasProvider(store: MorningExtrasPreferencesStore(directory: try directory()),
                                             health: health, clock: clock)
        try await provider.setEnabled(.steps, true)
        let attempt = Task { await prepare(provider) }
        defer { attempt.cancel() }
        await clock.waitForSleepers()
        while health.waitingRead == nil { try Task.checkCancellation(); await Task.yield() }
        health.releaseRead()
        #expect(await attempt.value.kinds == [.steps])
        #expect(clock.sleeperCount == 0 && health.readFinished && !health.readWasCancelled)
    }

    @Test func weatherAndCalendarReachTheSentenceAndScreenTimeIsAHook() async throws {
        let provider = MorningExtrasProvider(store: MorningExtrasPreferencesStore(directory: try directory()),
            screenTime: SyntheticScreenTime(), weatherOutlook: { _, frame in
                WeatherOutlook(yesterdayHighCelsius: 20, todayHighCelsius: 10, hours: [
                    .init(start: frame.now.addingTimeInterval(8 * 3_600), chance: 0.6, kind: .rain)])
            }, clock: ManualTestClock())
        try await provider.setEnabled(.calendar, true)
        try await provider.setEnabled(.weatherChange, true)
        let location = try WeatherLocation(latitude: 48.85, longitude: 2.35, displayName: "Synthetic city")
        let selection = await provider.prepare(now: morning, timeZone: paris, localeIdentifier: "en_GB",
            weatherLocation: location, temperatureUnit: .celsius,
            calendarEvents: { _ in [self.event("Standup", 60, 120), self.event("Dentist", 90, 150)] })
        #expect(selection.text == "Calendar: Standup and Dentist overlap at 09:30. Rain likely from 16:00.")
        // Screen time is off by default; the hook is read only once it is turned on.
        try await provider.setEnabled(.screenTime, true)
        let withScreen = await provider.prepare(now: morning, timeZone: paris, localeIdentifier: "en_GB",
            weatherLocation: nil, temperatureUnit: .celsius, calendarEvents: nil)
        #expect(withScreen.kinds == [.screenTime])
    }

    private func prepare(_ provider: MorningExtrasProvider) async -> MorningExtrasSelection {
        await provider.prepare(now: morning, timeZone: paris, localeIdentifier: "en_GB",
                               weatherLocation: nil, temperatureUnit: .celsius, calendarEvents: nil)
    }
}

@MainActor
private final class SyntheticHealth: MorningHealthExtrasProviding {
    var prompts = 0, reads = 0
    var requestedSleep = false, requestedSteps = false
    let steps: [Int?]
    let hang: Bool
    var waitingRead: CheckedContinuation<Void, Never>?
    var readFinished = false, readWasCancelled = false
    init(steps: [Int?], hang: Bool = false) { self.steps = steps; self.hang = hang }
    func requestReadAccess() async throws { prompts += 1 }
    func requestExtrasAccess() async throws { prompts += 1 }
    func requestExtrasAccess(includeSleep: Bool, includeSteps: Bool) async throws {
        prompts += 1; requestedSleep = includeSleep; requestedSteps = includeSteps
    }
    func sleepSamples(in interval: DateInterval) async throws -> SleepReadOutcome { reads += 1; return .samples([]) }
    func stepTotals(for days: [DateInterval]) async throws -> [Int?] {
        reads += 1
        if hang { await withCheckedContinuation { waitingRead = $0 } }
        readWasCancelled = Task.isCancelled
        readFinished = true
        return steps.count == days.count ? steps : days.map { _ in nil }
    }
    func releaseRead() { waitingRead?.resume(); waitingRead = nil }
}

@MainActor
private final class SyntheticBirthdays: BirthdayProviding {
    var prompts = 0
    var isAuthorized = false
    func requestAccess() async throws -> Bool { prompts += 1; isAuthorized = true; return true }
    func names(bornOn month: Int, day: Int) async throws -> [String] { ["Anna"] }
}

@MainActor
private final class SyntheticScreenTime: ScreenTimeSummaryProviding {
    func screenTimeMinutes(for days: [DateInterval]) async throws -> [Int?] { [95, 60, 60, 60, 60, nil, nil, nil] }
}

@Suite("Closing reminder answers — review suggestions only")
struct ClosingReminderParserTests {
    private func paris() -> Calendar {
        var calendar = Calendar(identifier: .gregorian); calendar.timeZone = TimeZone(identifier: "Europe/Paris")!; return calendar
    }
    /// 08:00 in Paris on 13 October 2026.
    private let morning = Date(timeIntervalSince1970: 1_791_871_200)

    @Test func remindMeAtFiveProposesTheNextFiveOClock() {
        let parsed = CaptureRequestParser.parse("Remind me at 5 to call the bank", now: morning, calendar: paris())
        #expect(parsed.destination == .reminder)
        #expect(parsed.content == "call the bank")
        // At 08:00, the next "5" is 17:00 today, not 05:00 tomorrow.
        #expect(parsed.suggestedDate == morning.addingTimeInterval(9 * 3_600))
        #expect(parsed.needsDateReview)
        // The UI test's synthetic answer resolves the same way.
        let fixture = CaptureRequestParser.parse("Remind me at 5 to call the bank. SYNTHETIC_CLOSING_REMINDER",
                                                 now: morning, calendar: paris())
        #expect(fixture.suggestedDate == morning.addingTimeInterval(9 * 3_600))
        #expect(fixture.content == "call the bank. SYNTHETIC_CLOSING_REMINDER")
    }

    @Test func explicitClockTimes() {
        let calendar = paris()
        func date(_ text: String, default destination: CaptureDestination = .reminder) -> Date? {
            CaptureRequestParser.parse(text, now: morning, calendar: calendar, defaultDestination: destination).suggestedDate
        }
        #expect(date("call the bank at 17:30") == morning.addingTimeInterval(9.5 * 3_600))
        #expect(date("call the bank at 5 pm") == morning.addingTimeInterval(9 * 3_600))
        #expect(date("call the bank at 7 am") == morning.addingTimeInterval(23 * 3_600))
        #expect(date("appeler la banque à 17h") == morning.addingTimeInterval(9 * 3_600))
        #expect(date("appeler la banque à 17 h 30") == morning.addingTimeInterval(9.5 * 3_600))
        #expect(date("call the bank at 07:30") == morning.addingTimeInterval(23.5 * 3_600))
        #expect(date("appeler la banque à 7h") == morning.addingTimeInterval(23 * 3_600))
        #expect(date("call the bank at 25") == nil)
        #expect(date("call the bank at 17:300") == nil)
        #expect(date("call the bank at 5:3") == nil)
        #expect(date("meet at 5th Avenue") == nil)
        #expect(date("call the bank at 5:75") == nil)
    }

    @Test func aDayWordLeavesTheDateToThePerson() {
        let parsed = CaptureRequestParser.parse("Remind me at 5 tomorrow to call the bank", now: morning, calendar: paris())
        #expect(parsed.destination == .reminder)
        #expect(parsed.suggestedDate == nil)
        #expect(parsed.needsDateReview)
        let link = CaptureRequestParser.parse("Remind me at 5 tomatoes", now: morning, calendar: paris())
        #expect(link.content == "tomatoes")
    }

    @Test func roundTwoParserCases() {
        let calendar = paris()
        let tomorrow = CaptureRequestParser.parse("Remind me to call Alex tomorrow at 17:30", now: morning, calendar: calendar)
        #expect(tomorrow.suggestedDate == nil)
        let french = CaptureRequestParser.parse("Rappelle-moi à 7 h de rappeler la banque", now: morning, calendar: calendar)
        #expect(french.suggestedDate == morning.addingTimeInterval(23 * 3_600))
        #expect(french.content == "rappeler la banque")
        let pm = CaptureRequestParser.parse("Remind me at 5 pm to call Alex", now: morning, calendar: calendar)
        #expect(pm.dateExplanation?.contains("17:00") == true)
        #expect(pm.content == "call Alex")
        for text in ["Remind me to call Alex on October 20 at 17:30", "Remind me this morning at 5 to call Alex",
                     "Remind me at 17 30 to call Alex", "Rappelle-moi à 7 h 5 d'appeler", "Remind me to call Alex at 5 on the 20th",
                     "Remind me to call Alex in two days at 17:30", "Rappelle-moi dans deux jours à 17h d'appeler",
                     "Remind me at 5 pm UTC to call Alex", "Remind me at 5 pm EST to call Alex",
                     "Remind me at 5 thirty to call Alex", "Remind me at 5 past 6 to call Alex",
                     "Rappelle-moi à 5 et demie d'appeler"] {
            #expect(CaptureRequestParser.parse(text, now: morning, calendar: calendar).suggestedDate == nil, "\(text)")
        }
    }

    @Test func aTimeSkippedByTheClockChangeIsNotMovedSilently() {
        // Paris springs forward at 02:00 on 28 March 2027: 02:30 does not exist that night.
        let midnight = Date(timeIntervalSince1970: 1_806_188_400) // 28 Mar 2027, 00:00 CET
        let parsed = CaptureRequestParser.parse("Remind me to call at 02:30", now: midnight, calendar: paris())
        #expect(parsed.suggestedDate == nil)
    }

    @Test func aReminderAnswerWithoutATimeHasNoAlert() {
        let parsed = CaptureRequestParser.parse("buy milk", now: morning, calendar: paris(), defaultDestination: .reminder)
        #expect(parsed.destination == .reminder)
        #expect(parsed.content == "buy milk")
        #expect(parsed.suggestedDate == nil)
    }

    @Test func theWordsStillWinOverTheQuestion() {
        let calendar = paris()
        #expect(CaptureRequestParser.parse("I dreamed of a garden at 5", now: morning, calendar: calendar,
                                           defaultDestination: .reminder).destination == .dream)
        // A thought that mentions a time stays a thought with no date.
        let thought = CaptureRequestParser.parse("The meeting at 5 went well", now: morning, calendar: calendar)
        #expect(thought.destination == .thought)
        #expect(thought.suggestedDate == nil)
    }
}

@MainActor
private final class ControlledExtrasHealth: MorningHealthExtrasProviding {
    var waiting: CheckedContinuation<Void, Never>?
    func requestReadAccess() async throws { }
    func requestExtrasAccess() async throws {
        await withCheckedContinuation { waiting = $0 }
    }
    func sleepSamples(in interval: DateInterval) async throws -> SleepReadOutcome { .samples([]) }
    func stepTotals(for days: [DateInterval]) async throws -> [Int?] { days.map { _ in nil } }
}
