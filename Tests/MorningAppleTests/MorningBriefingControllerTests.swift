import Foundation
import Testing
import MorningCore
@testable import MorningApple

@Suite("Prepared briefing ownership and settings")
@MainActor
struct MorningBriefingControllerTests {
    @Test func settingsSurviveRelaunchWithoutSavingPreparedFacts() async throws {
        let directory = temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let calendar = BriefingCalendarFixture()
        let location = try syntheticLocation()
        let weather = try syntheticWeather(location: location)
        let controller = makeController(directory: directory, calendar: calendar, weather: { _ in weather })
        let settings = MorningBriefingSettings(calendarIDs: [calendar.choice.id], weatherLocation: location, temperatureUnit: .fahrenheit)
        try controller.updateSettings(settings)
        let result = try #require(await controller.refresh())
        #expect(result.calendar.status == .fresh)
        #expect(result.weather.status == .fresh)
        #expect(result.temperatureUnit == .fahrenheit)
        let restored = makeController(directory: directory, calendar: BriefingCalendarFixture(), weather: { _ in weather })
        #expect(restored.settings == settings)
        #expect(restored.prepared == nil)
        let files = try FileManager.default.contentsOfDirectory(at: directory, includingPropertiesForKeys: nil)
        for url in files where url.pathExtension == "json" {
            let text = String(decoding: try Data(contentsOf: url), as: UTF8.self)
            #expect(!text.contains("SYNTHETIC_PRIVATE_EVENT_TITLE"))
            #expect(!text.contains("SYNTHETIC_CONDITIONS"))
        }
    }

    @Test func corruptSettingsRemainIntactUntilExplicitReset() async throws {
        let directory = temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let calendar = BriefingCalendarFixture()
        let unavailable: WeatherObservationService.WeatherProvider = { _ in throw WeatherObservationError.serviceUnavailable }
        let initial = makeController(directory: directory, calendar: calendar, weather: unavailable)
        try initial.updateSettings(.init(calendarIDs: [calendar.choice.id]))
        let file = directory.appendingPathComponent("briefing-settings.json")
        let corrupt = Data("{synthetic malformed settings}".utf8)
        try corrupt.write(to: file)
        let restored = makeController(directory: directory, calendar: calendar, weather: unavailable)
        #expect(restored.settingsRecoveryError != nil)
        #expect(throws: MorningBriefingControllerError.unreadableSettings) {
            try restored.updateSettings(.init(calendarIDs: [calendar.choice.id]))
        }
        let unavailableResult = await restored.refresh()
        #expect(unavailableResult == nil)
        #expect(calendar.reads == 0)
        #expect(try Data(contentsOf: file) == corrupt)
        try restored.resetSettings()
        #expect(restored.settingsRecoveryError == nil)
        #expect(restored.settings == MorningBriefingSettings())
        let afterReset = makeController(directory: directory, calendar: calendar, weather: unavailable)
        #expect(afterReset.settingsRecoveryError == nil)
        #expect(afterReset.settings == MorningBriefingSettings())
    }

    @Test func unconfiguredRefreshDoesNotReadOrPromptEitherSource() async throws {
        let directory = temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let calendar = BriefingCalendarFixture()
        let weatherCalls = BriefingCallCounter()
        let controller = makeController(directory: directory, calendar: calendar, weather: { _ in
            weatherCalls.count += 1
            throw WeatherObservationError.serviceUnavailable
        })
        let result = try #require(await controller.refresh())
        #expect(result.calendar.status == .notConfigured)
        #expect(result.weather.status == .notConfigured)
        #expect(!result.hasUsableFacts)
        #expect(calendar.reads == 0)
        #expect(calendar.permissionRequests == 0)
        #expect(weatherCalls.count == 0)
    }

    @Test func revokedSelectionDoesNotWidenCalendarReadOrBlockWeather() async throws {
        let directory = temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let calendar = BriefingCalendarFixture()
        let location = try syntheticLocation()
        let weather = try syntheticWeather(location: location)
        let controller = makeController(directory: directory, calendar: calendar, weather: { _ in weather })
        try controller.updateSettings(.init(calendarIDs: ["no-longer-present"], weatherLocation: location))
        let unavailable = try #require(await controller.refresh())
        #expect(unavailable.calendar.status == .unavailable)
        #expect(unavailable.weather.status == .fresh)
        #expect(calendar.reads == 0)
        #expect(calendar.permissionRequests == 0)
        calendar.authorized = false
        try controller.updateSettings(.init(calendarIDs: [calendar.choice.id], weatherLocation: location))
        let denied = try #require(await controller.refresh())
        #expect(denied.calendar.status == .denied)
        #expect(denied.weather.status == .fresh)
        #expect(calendar.reads == 0)
        #expect(calendar.permissionRequests == 0)
    }

    @Test func freshPinnedCalendarRequiresCurrentPermissionAndStillAvailableSelection() async throws {
        let directory = temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let calendar = BriefingCalendarFixture()
        let controller = makeController(directory: directory, calendar: calendar, weather: { _ in
            throw WeatherObservationError.serviceUnavailable
        })
        try controller.updateSettings(.init(calendarIDs: [calendar.choice.id]))
        let document = try #require(await controller.refresh())
        #expect(document.isCurrent(at: referenceDate, timeZoneIdentifier: "UTC"))
        #expect(controller.permitsPlayback(of: document))
        calendar.authorized = false
        #expect(!controller.permitsPlayback(of: document), "Fresh timestamps do not retain revoked calendar permission.")
        calendar.authorized = true
        #expect(controller.permitsPlayback(of: document))
        calendar.isAvailable = false
        #expect(!controller.permitsPlayback(of: document), "A removed calendar invalidates pinned text before its TTL.")
        #expect(calendar.reads == 1, "Playback admission must not fetch replacement event content.")
        #expect(calendar.permissionRequests == 0)
    }

    @Test func weatherFailureStillPreparesCalendarWithoutInventingWeather() async throws {
        let directory = temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let calendar = BriefingCalendarFixture()
        let controller = makeController(directory: directory, calendar: calendar, weather: { _ in
            throw WeatherObservationError.networkUnavailable
        })
        try controller.updateSettings(.init(calendarIDs: [calendar.choice.id], weatherLocation: try syntheticLocation()))
        let result = try #require(await controller.refresh())
        #expect(result.calendar.status == .fresh)
        #expect(result.weather.status == .unavailable)
        #expect(result.hasUsableFacts)
        #expect(result.spokenText.contains("SYNTHETIC_PRIVATE_EVENT_TITLE"))
        #expect(!result.spokenText.contains("degrees"))
        #expect(result.weatherAttribution == nil)
    }

    @Test func concurrentRefreshesShareOneSourceReadAndFreshPreparation() async throws {
        let directory = temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let calendar = BriefingCalendarFixture()
        let gate = BriefingWeatherGate()
        let location = try syntheticLocation()
        let weather = try syntheticWeather(location: location)
        let controller = makeController(directory: directory, calendar: calendar, weather: { _ in try await gate.value() })
        try controller.updateSettings(.init(calendarIDs: [calendar.choice.id], weatherLocation: location))
        let first = Task { await controller.refresh() }
        await gate.waitUntilCalled()
        let entered = BriefingAsyncSignal()
        let second = Task { entered.signal(); return await controller.refresh(force: true) }
        await entered.wait()
        #expect(controller.isPreparing)
        #expect(gate.calls == 1)
        gate.release(weather)
        let firstValue = try #require(await first.value)
        let secondValue = try #require(await second.value)
        #expect(firstValue.id == secondValue.id)
        #expect(calendar.reads == 1)
        #expect(gate.calls == 1)
        let cached = try #require(await controller.refresh())
        #expect(cached.spokenText == firstValue.spokenText)
        #expect(cached.calendar.retrievedAt == firstValue.calendar.retrievedAt)
        #expect(gate.calls == 1)
        #expect(!controller.isPreparing)
    }

    @Test func cancelledRefreshRejectsAnUncooperativeLateSource() async throws {
        let directory = temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let gate = BriefingWeatherGate()
        let location = try syntheticLocation()
        let weather = try syntheticWeather(location: location)
        let controller = makeController(directory: directory, calendar: BriefingCalendarFixture(), weather: { _ in try await gate.value() })
        try controller.updateSettings(.init(weatherLocation: location))
        let attempt = Task { await controller.refresh() }
        await gate.waitUntilCalled()
        controller.cancelAndClear()
        gate.release(weather)
        let result = await attempt.value
        #expect(result == nil)
        #expect(controller.prepared == nil)
        #expect(!controller.isPreparing)
    }

    @Test func changedSelectionCannotReceiveThePriorLocationsLateResult() async throws {
        let directory = temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let gate = BriefingWeatherGate()
        let location = try syntheticLocation()
        let weather = try syntheticWeather(location: location)
        let controller = makeController(directory: directory, calendar: BriefingCalendarFixture(), weather: { _ in try await gate.value() })
        try controller.updateSettings(.init(weatherLocation: location))
        let attempt = Task { await controller.refresh() }
        await gate.waitUntilCalled()
        try controller.updateSettings(.init())
        gate.release(weather)
        let oldResult = await attempt.value
        #expect(oldResult == nil)
        #expect(controller.prepared == nil)
        let current = try #require(await controller.refresh())
        #expect(current.weather.status == .notConfigured)
        #expect(gate.calls == 1)
    }

    @Test func pendingForgetRejectsLatePreparationAndSettingsWrites() async throws {
        let directory = temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let gate = BriefingWeatherGate()
        let location = try syntheticLocation()
        let weather = try syntheticWeather(location: location)
        let controller = makeController(directory: directory, calendar: BriefingCalendarFixture(), weather: { _ in try await gate.value() })
        try controller.updateSettings(.init(weatherLocation: location))
        let attempt = Task { await controller.refresh() }
        await gate.waitUntilCalled()
        _ = try LocalDataControl(directory: directory).beginForget()
        gate.release(weather)
        let result = await attempt.value
        #expect(result == nil)
        #expect(controller.prepared == nil)
        #expect(throws: (any Error).self) { try controller.updateSettings(.init()) }
        let retry = await controller.refresh()
        #expect(retry == nil)
        #expect(gate.calls == 1)
    }

    @Test func completedForgetEpochStillRejectsTheOldOwnersLateResult() async throws {
        let directory = temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let gate = BriefingWeatherGate()
        let location = try syntheticLocation()
        let weather = try syntheticWeather(location: location)
        let controller = makeController(directory: directory, calendar: BriefingCalendarFixture(), weather: { _ in try await gate.value() })
        try controller.updateSettings(.init(weatherLocation: location))
        let attempt = Task { await controller.refresh() }
        await gate.waitUntilCalled()
        let control = LocalDataControl(directory: directory)
        let reset = try control.beginForget()
        let generation = try #require(reset.generation)
        // This tests epoch ownership; the app's complete payload sweep has separate coverage.
        try control.finishForget(expectedGeneration: generation)
        gate.release(weather)
        let result = await attempt.value
        #expect(result == nil)
        #expect(controller.prepared == nil)
        #expect(throws: MorningBriefingControllerError.staleGeneration) {
            try controller.updateSettings(.init())
        }
        #expect(gate.calls == 1)
    }

    @Test func weatherDeadlineReturnsUsefulCalendarBeforeUncooperativeProviderFinishes() async throws {
        let directory = temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let gate = BriefingWeatherGate()
        let calendar = BriefingCalendarFixture()
        let location = try syntheticLocation()
        let weather = try syntheticWeather(location: location)
        let controller = makeController(directory: directory, calendar: calendar,
            weather: { _ in try await gate.value() }, timeout: .milliseconds(30))
        try controller.updateSettings(.init(calendarIDs: [calendar.choice.id], weatherLocation: location))
        // Prevent a broken timeout implementation from leaving a continuation live forever.
        // The margin is wide so a busy machine cannot release the gate before a working
        // 30 ms deadline has been scheduled; a broken deadline still fails, only later.
        let fallback = Task {
            do { try await Task.sleep(for: .seconds(30)) } catch { return }
            gate.release(weather)
        }
        let result = await controller.refresh()
        let returnedBeforeRelease = !gate.wasReleased
        fallback.cancel()
        gate.release(weather)
        let prepared = try #require(result)
        #expect(returnedBeforeRelease, "A timeout must not wait for an uncooperative provider to return.")
        #expect(prepared.calendar.status == .fresh)
        #expect(prepared.weather.status == .unavailable)
        let preparedID = prepared.id
        await Task.yield()
        #expect(controller.prepared?.id == preparedID)
        #expect(controller.prepared?.weather.status == .unavailable)
    }

    private func makeController(directory: URL, calendar: BriefingCalendarFixture,
        weather: @escaping WeatherObservationService.WeatherProvider,
        timeout: Duration = .seconds(10)) -> MorningBriefingController {
        let date = referenceDate
        return MorningBriefingController(directory: directory,
            calendar: CalendarObservationService(provider: calendar, now: { date }),
            weather: WeatherObservationService(weatherProvider: weather, citySearchProvider: { _ in [] }),
            now: { date }, timeZone: { TimeZone(identifier: "UTC")! }, localeIdentifier: "en_US",
            sourceTimeout: timeout)
    }

    private var referenceDate: Date { Date(timeIntervalSince1970: 1_791_619_200) }
    private func temporaryDirectory() -> URL {
        FileManager.default.temporaryDirectory.appendingPathComponent("MorningBriefingTests-\(UUID().uuidString)")
    }
    private func syntheticLocation() throws -> WeatherLocation {
        try WeatherLocation(latitude: 48, longitude: 2, displayName: "Synthetic town")
    }
    private func syntheticWeather(location: WeatherLocation) throws -> WeatherObservationSnapshot {
        let attribution = try WeatherAttributionInfo(legalURL: URL(string: "https://example.invalid/legal")!,
            combinedMarkLightURL: URL(string: "https://example.invalid/light")!,
            combinedMarkDarkURL: URL(string: "https://example.invalid/dark")!, serviceName: "Synthetic Weather")
        return try WeatherObservationSnapshot(location: location, retrievedAt: referenceDate,
            observationAt: referenceDate, temperatureCelsius: 18,
            conditionDescription: "SYNTHETIC_CONDITIONS", symbolName: "sun.max", attribution: attribution)
    }
}

@MainActor
private final class BriefingCalendarFixture: CalendarObservationProviding {
    let choice = CalendarChoice(id: "synthetic-briefing-calendar", title: "Synthetic calendar", sourceTitle: "Synthetic source")
    var authorized = true
    var isAvailable = true
    var reads = 0
    var permissionRequests = 0
    var isAuthorized: Bool { authorized }
    func requestAccess() async throws -> Bool { permissionRequests += 1; return authorized }
    func calendarChoices() throws -> [CalendarChoice] { isAvailable ? [choice] : [] }
    func events(in interval: DateInterval, calendarIDs: Set<String>) throws -> [CalendarObservationEvent] {
        reads += 1
        return [CalendarObservationEvent(id: "synthetic-all-day", calendarID: choice.id,
            title: "SYNTHETIC_PRIVATE_EVENT_TITLE", start: interval.start, end: interval.end, isAllDay: true)]
    }
}

@MainActor
private final class BriefingCallCounter { var count = 0 }

@MainActor
private final class BriefingAsyncSignal {
    private var signalled = false
    private var continuation: CheckedContinuation<Void, Never>?
    func signal() { signalled = true; continuation?.resume(); continuation = nil }
    func wait() async {
        if signalled { return }
        await withCheckedContinuation { continuation = $0 }
    }
}

@MainActor
private final class BriefingWeatherGate {
    private let entered = BriefingAsyncSignal()
    private var continuations: [CheckedContinuation<WeatherObservationSnapshot, any Error>] = []
    private(set) var calls = 0
    private(set) var wasReleased = false
    func value() async throws -> WeatherObservationSnapshot {
        calls += 1
        return try await withCheckedThrowingContinuation { continuation in
            self.continuations.append(continuation)
            entered.signal()
        }
    }
    func waitUntilCalled() async { await entered.wait() }
    func release(_ value: WeatherObservationSnapshot) {
        guard !continuations.isEmpty else { return }
        wasReleased = true
        let waiting = continuations
        continuations = []
        for continuation in waiting { continuation.resume(returning: value) }
    }
}
