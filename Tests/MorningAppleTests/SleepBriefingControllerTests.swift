import Foundation
import Testing
import MorningCore
@testable import MorningApple

/// A fixture reader stands in for health data. Nothing here touches HealthKit.
@Suite("Sleep in the prepared briefing — setting, reads and forgetting, fixture reader only",
       .timeLimit(.minutes(1)), .endsControllerWorkOnCancellation)
@MainActor
struct SleepBriefingControllerTests {
    private let now = SleepFixtures.date("2026-10-10T08:00:00Z")
    private var night: [SleepSample] {
        [SleepFixtures.sample(.asleepCore, "2026-10-09T23:40:00Z", "2026-10-10T07:00:00Z", source: "SYNTHETIC_SLEEP_SOURCE")]
    }

    @Test func morningLearningReadsOnlyChosenHealthAndKeepsEachLocalNightSeparate() async throws {
        let directory = temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let samples = night + [
            SleepFixtures.sample(.asleepREM, "2026-10-08T23:30:00Z", "2026-10-09T06:30:00Z"),
            SleepFixtures.sample(.inBed, "2026-10-09T23:00:00Z", "2026-10-10T07:30:00Z"),
            SleepFixtures.sample(.awake, "2026-10-10T07:00:00Z", "2026-10-10T07:40:00Z")]
        let reader = SleepReaderFixture(.samples(samples))
        let controller = makeController(directory: directory, reader: reader)
        var calendar = Calendar(identifier: .gregorian); calendar.timeZone = TimeZone(identifier: "UTC")!
        #expect(try await controller.morningSleepWindows(at: now, calendar: calendar).isEmpty)
        #expect(reader.reads == 0 && reader.prompts == 0)
        try controller.updateSettings(.init(includesHealth: true))
        let windows = try await controller.morningSleepWindows(at: now, calendar: calendar)
        #expect(windows == [
            DateInterval(start: SleepFixtures.date("2026-10-08T23:30:00Z"), end: SleepFixtures.date("2026-10-09T06:30:00Z")),
            DateInterval(start: SleepFixtures.date("2026-10-09T23:40:00Z"), end: SleepFixtures.date("2026-10-10T07:00:00Z"))])
        #expect(reader.reads == 1 && reader.prompts == 0)
        #expect(controller.prepared == nil, "Learning hints do not prepare speech or a running session.")
        reader.answer = .samples([])
        #expect(try await controller.morningSleepWindows(at: now, calendar: calendar).isEmpty)
    }

    @Test func withdrawingHealthDuringLearningDropsTheReturnedSleep() async throws {
        let directory = temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let reader = SleepReaderFixture(.held)
        let controller = makeController(directory: directory, reader: reader)
        try controller.updateSettings(.init(includesHealth: true))
        var calendar = Calendar(identifier: .gregorian); calendar.timeZone = TimeZone(identifier: "UTC")!
        let attempt = Task { try await controller.morningSleepWindows(at: now, calendar: calendar) }
        await reader.waitUntilCalled()
        try controller.disableHealth()
        reader.release(.samples(night))
        await #expect(throws: CancellationError.self) { try await attempt.value }
        #expect(reader.prompts == 0 && controller.prepared == nil)
    }

    @Test func healthIsOffByDefaultAndTheReaderIsNeverCalledWhileItIsOff() async throws {
        let directory = temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let reader = SleepReaderFixture(.samples(night))
        let controller = makeController(directory: directory, reader: reader)
        #expect(!controller.settings.includesHealth && !MorningBriefingSettings().includesHealth)
        #expect(!controller.hasConfiguredSources)
        for force in [false, true] {
            let document = try #require(await controller.refresh(force: force))
            #expect(document.sleep.status == .notConfigured && document.sleepObservation == nil)
        }
        #expect(reader.reads == 0 && reader.prompts == 0)

        try controller.updateSettings(.init(includesHealth: true))
        #expect(controller.hasConfiguredSources, "Health alone is a configured source, independent of calendar and weather.")
        let included = try #require(await controller.refresh())
        #expect(included.sleep.status == .fresh && reader.reads == 1)
        #expect(included.calendar.status == .notConfigured && included.weather.status == .notConfigured)
        #expect(controller.permitsPlayback(of: included))

        try controller.updateSettings(.init(includesHealth: false))
        #expect(controller.prepared == nil, "Turning health off drops the prepared text that held it.")
        #expect(!controller.permitsPlayback(of: included), "A pinned recap that holds sleep cannot play once health is excluded.")
        let excluded = try #require(await controller.refresh(force: true))
        #expect(excluded.sleep.status == .notConfigured && !excluded.spokenText.contains("Sleep"))
        #expect(reader.reads == 1 && reader.prompts == 0)
    }

    @Test func readingNeverPromptsAndAFreshNightIsReusedWhileItIsCurrent() async throws {
        let directory = temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let reader = SleepReaderFixture(.samples(night))
        let controller = makeController(directory: directory, reader: reader)
        try controller.updateSettings(.init(includesHealth: true))
        let first = try #require(await controller.refresh())
        #expect(first.sleep.text == "Sleep recorded: 7 hours 20 minutes, between 23:40 and 07:00.")
        #expect(first.sleepObservation?.readAt == now)
        #expect(reader.intervals == [DateInterval(start: now.addingTimeInterval(-7 * 86_400), end: now)])
        let second = try #require(await controller.refresh())
        #expect(second.sleep.text == first.sleep.text && reader.reads == 1)
        _ = await controller.refresh(force: true)
        #expect(reader.reads == 2 && reader.prompts == 0)
    }

    @Test func emptyOlderUnavailableAndUnreadableReadsBecomeTheirOwnStates() async throws {
        let older = [SleepFixtures.sample(.asleepCore, "2026-10-08T23:00:00Z", "2026-10-09T07:00:00Z")]
        let cases: [(SleepReaderFixture.Answer, MorningBriefingSourceStatus, MorningBriefingSourceIssue)] = [
            (.samples([]), .missing, .noRecord), (.samples(older), .stale, .olderRecord),
            (.unavailableOnDevice, .unavailable, .unavailableOnDevice), (.failure, .unavailable, .notReadable)
        ]
        for (answer, status, issue) in cases {
            let directory = temporaryDirectory()
            defer { try? FileManager.default.removeItem(at: directory) }
            let reader = SleepReaderFixture(answer)
            let controller = makeController(directory: directory, reader: reader)
            try controller.updateSettings(.init(includesHealth: true))
            let document = try #require(await controller.refresh())
            #expect(document.sleep.status == status && document.sleep.issue == issue)
            #expect(!document.hasUsableFacts && document.spokenText.isEmpty && document.sleepObservation == nil)
            // A read that found no current night is tried again, because the night can arrive later.
            reader.answer = .samples(night)
            let next = try #require(await controller.refresh())
            #expect(next.sleep.status == .fresh && reader.reads == 2)
        }
    }

    @Test func aControllerWithoutAReaderSaysSleepIsNotPartOfThisVersion() async throws {
        let directory = temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let date = now
        let controller = MorningBriefingController(directory: directory,
            calendar: CalendarObservationService(provider: SleepSuiteCalendar(), now: { date }),
            weather: WeatherObservationService(weatherProvider: { _ in throw WeatherObservationError.serviceUnavailable },
                                               citySearchProvider: { _ in [] }),
            now: { date }, timeZone: { TimeZone(identifier: "UTC")! }, localeIdentifier: "en_US",
            clock: ManualTestClock()).watchedForHangs()
        try controller.updateSettings(.init(includesHealth: true))
        let document = try #require(await controller.refresh())
        #expect(document.sleep.status == .unavailable && document.sleep.issue == .sourceUnavailable)
        #expect(document.sleep.statusText == "Sleep reading is not part of this version.")
        #expect(!document.hasUsableFacts)
        await #expect(throws: SleepObservationError.notConnected) { try await SleepObservationService().requestReadAccess() }
    }

    @Test func settingsSavedBeforeHealthExistedStillLoadAndTheChoiceSurvivesRelaunch() async throws {
        let directory = temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        // The exact shape written before this choice existed: no "includesHealth" key.
        let old = #"{"schemaVersion":1,"value":{"calendarIDs":["old-calendar"],"temperatureUnit":"fahrenheit","weatherLocation":{"displayName":"Synthetic town","latitude":48,"longitude":2}}}"#
        let file = directory.appendingPathComponent("briefing-settings.json")
        try Data(old.utf8).write(to: file)
        let reader = SleepReaderFixture(.samples(night))
        let controller = makeController(directory: directory, reader: reader)
        #expect(controller.settingsRecoveryError == nil && controller.errorMessage == nil)
        #expect(controller.settings == MorningBriefingSettings(calendarIDs: ["old-calendar"],
            weatherLocation: try WeatherLocation(latitude: 48, longitude: 2, displayName: "Synthetic town"),
            temperatureUnit: .fahrenheit, includesHealth: false))
        _ = await controller.refresh()
        #expect(reader.reads == 0)

        var next = controller.settings
        next.includesHealth = true
        try controller.updateSettings(next)
        let restored = makeController(directory: directory, reader: reader)
        #expect(restored.settings == next && restored.settings.includesHealth)
        let saved = String(decoding: try Data(contentsOf: file), as: UTF8.self)
        #expect(saved.contains("\"includesHealth\" : true"))
    }

    @Test func forgettingClearsTheNightAndTurnsHealthOffAndNothingOfItWasOnDisk() async throws {
        let directory = temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let reader = SleepReaderFixture(.samples(night))
        let controller = makeController(directory: directory, reader: reader)
        try controller.updateSettings(.init(includesHealth: true))
        let document = try #require(await controller.refresh())
        #expect(document.sleep.status == .fresh && controller.prepared?.sleepObservation != nil)
        for url in try FileManager.default.contentsOfDirectory(at: directory, includingPropertiesForKeys: nil) {
            guard let data = try? Data(contentsOf: url) else { continue }
            let text = String(decoding: data, as: UTF8.self)
            for marker in ["SYNTHETIC_SLEEP_SOURCE", "asleep", "7 hours", "windowStart", "23:40"] {
                #expect(!text.contains(marker), "\(url.lastPathComponent) holds sleep data.")
            }
        }

        controller.cancelAndClear()
        #expect(controller.prepared == nil, "The memory-only clear drops the prepared night.")

        // The app's full forget: mark, remove the owned settings file, finish, reload.
        let control = LocalDataControl(directory: directory)
        let generation = try #require(try control.beginForget().generation)
        #expect(await controller.refresh() == nil, "No read is prepared while removal is pending.")
        try FileManager.default.removeItem(at: directory.appendingPathComponent("briefing-settings.json"))
        try control.finishForget(expectedGeneration: generation)
        controller.reloadSettings()
        #expect(controller.settings == MorningBriefingSettings() && !controller.settings.includesHealth)
        #expect(controller.prepared == nil)
        let after = try #require(await controller.refresh(force: true))
        #expect(after.sleep.status == .notConfigured && after.sleepObservation == nil)
        #expect(reader.reads == 1, "After forgetting, health is off again and the reader is not called.")
    }

    @Test func aLateNightCannotAttachAfterClearOrAfterHealthIsTurnedOff() async throws {
        for turnOff in [false, true] {
            let directory = temporaryDirectory()
            defer { try? FileManager.default.removeItem(at: directory) }
            let reader = SleepReaderFixture(.held)
            let controller = makeController(directory: directory, reader: reader)
            try controller.updateSettings(.init(includesHealth: true))
            let attempt = Task { await controller.refresh() }
            await reader.waitUntilCalled()
            if turnOff { try controller.updateSettings(.init()) } else { controller.cancelAndClear() }
            reader.release(.samples(night))
            #expect(await attempt.value == nil)
            #expect(controller.prepared == nil && !controller.isPreparing)
            if turnOff {
                let current = try #require(await controller.refresh())
                #expect(current.sleep.status == .notConfigured && reader.reads == 1)
            }
        }
    }

    /// Weather and sleep are read at the same time (#85), so the sleep read starts while
    /// health is still on. Turning health off while weather is still being read must drop
    /// the whole refresh, and the reader must never be called at a moment health is off.
    @Test func healthTurnedOffWhileWeatherIsReadDropsTheRefreshAndNeverReadsWhileExcluded() async throws {
        let directory = temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let reader = SleepReaderFixture(.samples(night))
        let weather = SleepSuiteWeatherGate()
        let controller = makeController(directory: directory, reader: reader, weather: { _ in try await weather.value() })
        reader.isExcludedNow = { [weak controller] in controller?.settings.includesHealth == false }
        let location = try WeatherLocation(latitude: 48, longitude: 2, displayName: "Synthetic town")
        try controller.updateSettings(.init(weatherLocation: location, includesHealth: true))
        let attempt = Task { @MainActor in await controller.refresh() }
        await weather.waitUntilCalled()
        #expect(controller.isPreparing)
        try controller.updateSettings(.init(weatherLocation: location))
        weather.fail()
        #expect(await attempt.value == nil)
        #expect(reader.readsWhileExcluded == 0, "Excluded means the reader is not called.")
        #expect(controller.prepared == nil && !controller.settings.includesHealth)
    }

    /// The narrow case: the read itself is already queued when health is turned off. Which
    /// of the two gets its turn first is the scheduler's choice, so the test asserts what
    /// must hold either way: the reader is never called at a moment when health is excluded.
    /// Repeated, because only one of the two orders can expose a missing check.
    @Test func aQueuedReadNeverReachesTheReaderWhileHealthIsExcluded() async throws {
        for _ in 0..<50 {
            let directory = temporaryDirectory()
            defer { try? FileManager.default.removeItem(at: directory) }
            let reader = SleepReaderFixture(.samples(night))
            let controller = makeController(directory: directory, reader: reader)
            reader.isExcludedNow = { [weak controller] in controller?.settings.includesHealth == false }
            try controller.updateSettings(.init(includesHealth: true))
            let attempt = Task { @MainActor in await controller.refresh() }
            await Task.yield()
            let change = Task { @MainActor in try controller.updateSettings(.init()) }
            _ = await attempt.value
            try await change.value
            for _ in 0..<20 { await Task.yield() }
            #expect(reader.readsWhileExcluded == 0, "The reader was called while health was excluded.")
            #expect(!controller.settings.includesHealth)
        }
    }

    @Test func aReaderThatDoesNotAnswerIsDroppedAtTheDeadlineOnTheInjectedClock() async throws {
        let directory = temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let reader = SleepReaderFixture(.held)
        let clock = ManualTestClock()
        let calendar = SleepSuiteCalendar()
        let controller = makeController(directory: directory, reader: reader, calendar: calendar, clock: clock)
        try controller.updateSettings(.init(calendarIDs: [calendar.choice.id], includesHealth: true))
        let attempt = Task { await controller.refresh() }
        await reader.waitUntilCalled()
        await clock.waitForSleepers()
        clock.advance(by: .seconds(10) - .milliseconds(1))
        #expect(clock.sleeperCount == 1 && controller.isPreparing, "The deadline fired before its time.")
        clock.advance(by: .milliseconds(1))
        let prepared = try #require(await attempt.value)
        #expect(prepared.calendar.status == .fresh)
        #expect(prepared.sleep.status == .unavailable && prepared.sleep.issue == .notReadable)
        #expect(prepared.spokenText.hasSuffix("Sleep data could not be read."))
        reader.release(.samples(night))
        await Task.yield()
        #expect(controller.prepared?.id == prepared.id && controller.prepared?.sleepObservation == nil,
                "A night that arrives after the deadline is dropped.")
    }

    /// Weather and sleep wait at the same time, so when neither answers the refresh
    /// ends at one deadline, not after one deadline each (#85).
    @Test func whenWeatherAndSleepBothHangTheRefreshEndsAfterOneDeadline() async throws {
        let directory = temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let reader = SleepReaderFixture(.held)
        let weather = SleepSuiteWeatherGate()
        let clock = ManualTestClock()
        let calendar = SleepSuiteCalendar()
        let controller = makeController(directory: directory, reader: reader, calendar: calendar, clock: clock,
                                        weather: { _ in try await weather.value() })
        try controller.updateSettings(.init(calendarIDs: [calendar.choice.id], weatherLocation: try syntheticLocation(),
                                           includesHealth: true))
        let attempt = Task { await controller.refresh() }
        await weather.waitUntilCalled()
        // Read one after the other, only weather's deadline would be waiting here.
        await clock.waitForSleepers(2)
        try #require(clock.sleeperCount == 2, "Weather and sleep must wait at the same time.")
        await reader.waitUntilCalled()
        clock.advance(by: .seconds(10) - .milliseconds(1))
        #expect(clock.sleeperCount == 2 && controller.isPreparing, "A deadline fired before its time.")
        clock.advance(by: .milliseconds(1))
        #expect(clock.sleeperCount == 0, "Both deadlines end at the same instant.")
        let prepared = try #require(await attempt.value)
        #expect(prepared.calendar.status == .fresh)
        #expect(prepared.weather.status == .unavailable)
        #expect(prepared.sleep.status == .unavailable && prepared.sleep.issue == .notReadable)
        // Answers that arrive after the deadline have no recipient.
        weather.release(try syntheticWeather())
        reader.release(.samples(night))
        await Task.yield()
        #expect(controller.prepared?.id == prepared.id && controller.prepared?.sleepObservation == nil)
        #expect(controller.prepared?.weather.status == .unavailable)
    }

    /// The source that answers in time is used; the one that does not is unavailable at the deadline.
    @Test(arguments: [true, false])
    func theSourceThatAnswersIsUsedAndTheOtherIsUnavailableAtTheDeadline(sleepAnswers: Bool) async throws {
        let directory = temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let reader = SleepReaderFixture(.held)
        let weather = SleepSuiteWeatherGate()
        let clock = ManualTestClock()
        let controller = makeController(directory: directory, reader: reader, clock: clock,
                                        weather: { _ in try await weather.value() })
        try controller.updateSettings(.init(weatherLocation: try syntheticLocation(), includesHealth: true))
        let attempt = Task { await controller.refresh() }
        await weather.waitUntilCalled()
        // Read one after the other, only weather's deadline would be waiting here.
        await clock.waitForSleepers(2)
        try #require(clock.sleeperCount == 2, "Weather and sleep must wait at the same time.")
        await reader.waitUntilCalled()
        if sleepAnswers { reader.release(.samples(night)) } else { weather.release(try syntheticWeather()) }
        // The answered source cancels its own deadline; only the other one is left.
        while clock.sleeperCount > 1 { await Task.yield() }
        #expect(controller.isPreparing, "The refresh waits for the source that has not answered.")
        clock.advance(by: .seconds(10))
        let prepared = try #require(await attempt.value)
        #expect(clock.sleeperCount == 0)
        if sleepAnswers {
            #expect(prepared.sleep.status == .fresh && prepared.weather.status == .unavailable)
            weather.release(try syntheticWeather())
        } else {
            #expect(prepared.weather.status == .fresh)
            #expect(prepared.sleep.status == .unavailable && prepared.sleep.issue == .notReadable)
            reader.release(.samples(night))
        }
        await Task.yield()
        #expect(controller.prepared?.id == prepared.id, "A late answer does not replace the composed recap.")
    }

    /// Cancelling a refresh while both sources are being read ends both reads and publishes nothing.
    @Test func cancellingDuringBothReadsEndsBothAndPublishesNothing() async throws {
        let directory = temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let reader = SleepReaderFixture(.held)
        let weather = SleepSuiteWeatherGate()
        let clock = ManualTestClock()
        let controller = makeController(directory: directory, reader: reader, clock: clock,
                                        weather: { _ in try await weather.value() })
        try controller.updateSettings(.init(weatherLocation: try syntheticLocation(), includesHealth: true))
        let attempt = Task { await controller.refresh() }
        await weather.waitUntilCalled()
        // Read one after the other, only weather's deadline would be waiting here.
        await clock.waitForSleepers(2)
        try #require(clock.sleeperCount == 2, "Weather and sleep must wait at the same time.")
        await reader.waitUntilCalled()
        controller.cancelAndClear()
        #expect(await attempt.value == nil)
        #expect(clock.sleeperCount == 0, "Both deadlines were cancelled with the refresh.")
        weather.release(try syntheticWeather())
        reader.release(.samples(night))
        await Task.yield()
        #expect(controller.prepared == nil && !controller.isPreparing && controller.errorMessage == nil)
    }

    private func makeController(directory: URL, reader: SleepReaderFixture, calendar: SleepSuiteCalendar = .init(),
                                clock: ManualTestClock = ManualTestClock(),
                                weather: @escaping WeatherObservationService.WeatherProvider = { _ in
                                    throw WeatherObservationError.serviceUnavailable
                                }) -> MorningBriefingController {
        let date = now
        return MorningBriefingController(directory: directory,
            calendar: CalendarObservationService(provider: calendar, now: { date }),
            weather: WeatherObservationService(weatherProvider: weather, citySearchProvider: { _ in [] }),
            sleep: SleepObservationService(provider: reader),
            now: { date }, timeZone: { TimeZone(identifier: "UTC")! }, localeIdentifier: "en_GB",
            clock: clock).watchedForHangs()
    }
    private func syntheticLocation() throws -> WeatherLocation {
        try WeatherLocation(latitude: 48, longitude: 2, displayName: "Synthetic town")
    }
    private func syntheticWeather() throws -> WeatherObservationSnapshot {
        let attribution = try WeatherAttributionInfo(legalURL: URL(string: "https://example.invalid/legal")!,
            combinedMarkLightURL: URL(string: "https://example.invalid/light")!,
            combinedMarkDarkURL: URL(string: "https://example.invalid/dark")!, serviceName: "Synthetic Weather")
        return try WeatherObservationSnapshot(location: try syntheticLocation(), retrievedAt: now,
            observationAt: now, temperatureCelsius: 18,
            conditionDescription: "SYNTHETIC_CONDITIONS", symbolName: "sun.max", attribution: attribution)
    }
    private func temporaryDirectory() -> URL {
        FileManager.default.temporaryDirectory.appendingPathComponent("SleepBriefingTests-\(UUID().uuidString)")
    }
}

/// A labeled synthetic reader. It counts every call so "never called" can be asserted.
@MainActor
private final class SleepReaderFixture: SleepObservationProviding {
    enum Answer { case samples([SleepSample]), unavailableOnDevice, failure, held }
    struct Failure: Error {}

    var answer: Answer
    /// Asked at the moment of each read: was health excluded just then?
    var isExcludedNow: () -> Bool = { false }
    private(set) var readsWhileExcluded = 0
    private(set) var reads = 0
    private(set) var prompts = 0
    private(set) var intervals: [DateInterval] = []
    private var waiting: [CheckedContinuation<SleepReadOutcome, any Error>] = []
    private var callers: [CheckedContinuation<Void, Never>] = []

    init(_ answer: Answer) { self.answer = answer }

    func requestReadAccess() async throws { prompts += 1 }

    func sleepSamples(in interval: DateInterval) async throws -> SleepReadOutcome {
        reads += 1; intervals.append(interval)
        if isExcludedNow() { readsWhileExcluded += 1 }
        switch answer {
        case .samples(let samples): return .samples(samples)
        case .unavailableOnDevice: return .unavailableOnDevice
        case .failure: throw Failure()
        case .held:
            return try await withCheckedThrowingContinuation { continuation in
                waiting.append(continuation)
                for caller in callers { caller.resume() }
                callers = []
            }
        }
    }

    func waitUntilCalled() async {
        if !waiting.isEmpty { return }
        await withCheckedContinuation { callers.append($0) }
    }

    func release(_ outcome: SleepReadOutcome) {
        let held = waiting
        waiting = []
        for continuation in held { continuation.resume(returning: outcome) }
    }
}

@MainActor
private final class SleepSuiteCalendar: CalendarObservationProviding {
    let choice = CalendarChoice(id: "synthetic-sleep-suite-calendar", title: "Synthetic calendar", sourceTitle: "Synthetic source")
    var isAuthorized: Bool { true }
    func requestAccess() async throws -> Bool { true }
    func calendarChoices() throws -> [CalendarChoice] { [choice] }
    func events(in interval: DateInterval, calendarIDs: Set<String>) throws -> [CalendarObservationEvent] { [] }
}

/// Holds the weather read until the test lets it fail or answer, so a test can act while a refresh
/// is suspended at a known point.
@MainActor
private final class SleepSuiteWeatherGate {
    private var waiting: [CheckedContinuation<WeatherObservationSnapshot, any Error>] = []
    private var watchers: [CheckedContinuation<Void, Never>] = []
    func value() async throws -> WeatherObservationSnapshot {
        try await withCheckedThrowingContinuation { continuation in
            waiting.append(continuation)
            let called = watchers; watchers = []
            for watcher in called { watcher.resume() }
        }
    }
    func waitUntilCalled() async {
        guard waiting.isEmpty else { return }
        await withCheckedContinuation { watchers.append($0) }
    }
    func fail() {
        let held = waiting; waiting = []
        for continuation in held { continuation.resume(throwing: WeatherObservationError.serviceUnavailable) }
    }
    func release(_ value: WeatherObservationSnapshot) {
        let held = waiting; waiting = []
        for continuation in held { continuation.resume(returning: value) }
    }
}
