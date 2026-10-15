import Foundation
import Testing
import MorningCore
@testable import MorningApple

// The time limit and the trait are a safety net for a hang; see `BriefingHangRescueTrait`.
@Suite("Prepared briefing ownership and settings", .timeLimit(.minutes(1)), .endsControllerWorkOnCancellation)
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

    @Test func knownCalendarChangeInvalidatesPinnedTextAndBypassesTheFreshCache() async throws {
        let directory = temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let calendar = BriefingCalendarFixture()
        let controller = makeController(directory: directory, calendar: calendar, weather: { _ in
            throw WeatherObservationError.serviceUnavailable
        })
        try controller.updateSettings(.init(calendarIDs: [calendar.choice.id]))
        let original = try #require(await controller.refresh())
        let sameRevision = try #require(await controller.refresh())
        #expect(calendar.reads == 1)
        #expect(controller.permitsPlayback(of: original), "An ordinary preview refresh preserves still-current pinned text.")
        #expect(controller.permitsPlayback(of: sameRevision))
        calendar.eventTitle = "SYNTHETIC_UPDATED_EVENT"
        calendar.changeRevision += 1
        #expect(original.isCurrent(at: referenceDate, timeZoneIdentifier: "UTC"), "The TTL has not expired.")
        #expect(!controller.permitsPlayback(of: original))
        #expect(!controller.permitsPlayback(of: sameRevision))
        #expect(calendar.reads == 1, "Admission must never fetch or replace pinned text.")

        let updated = try #require(await controller.refresh())
        #expect(calendar.reads == 2, "A known change bypasses the fresh timestamp cache.")
        #expect(updated.spokenText.contains("SYNTHETIC_UPDATED_EVENT"))
        #expect(!updated.spokenText.contains("SYNTHETIC_PRIVATE_EVENT_TITLE"))
        #expect(controller.permitsPlayback(of: updated))
        #expect(!controller.permitsPlayback(of: original), "Refreshing the same local instant cannot reauthorize old prose.")
        #expect(calendar.permissionRequests == 0)
    }

    @Test func calendarChangeWhileWeatherIsSuspendedIsRereadBeforePublication() async throws {
        let directory = temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let calendar = BriefingCalendarFixture()
        let gate = BriefingWeatherGate()
        let location = try syntheticLocation()
        let weather = try syntheticWeather(location: location)
        let controller = makeController(directory: directory, calendar: calendar, weather: { _ in try await gate.value() })
        try controller.updateSettings(.init(calendarIDs: [calendar.choice.id], weatherLocation: location))
        let refresh = Task { await controller.refresh() }
        await gate.waitUntilCalled()
        #expect(calendar.reads == 1)
        calendar.eventTitle = "SYNTHETIC_CHANGED_DURING_WEATHER"
        calendar.changeRevision += 1
        gate.release(weather)
        let result = try #require(await refresh.value)
        #expect(calendar.reads == 2)
        #expect(result.calendar.status == .fresh && result.weather.status == .fresh)
        #expect(result.spokenText.contains("SYNTHETIC_CHANGED_DURING_WEATHER"))
        #expect(!result.spokenText.contains("SYNTHETIC_PRIVATE_EVENT_TITLE"))
        #expect(controller.permitsPlayback(of: result))
        #expect(calendar.permissionRequests == 0)
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

    /// The deadline is counted on the injected clock, so only `advance` can make it fire.
    @Test(arguments: [
        BriefingDeadlineExample(requested: .seconds(10), effective: .seconds(10)),
        BriefingDeadlineExample(requested: .milliseconds(30), effective: .milliseconds(30)),
        BriefingDeadlineExample(requested: .seconds(60), effective: .seconds(10)),
        BriefingDeadlineExample(requested: .zero, effective: .milliseconds(1))
    ])
    func weatherDeadlineReturnsUsefulCalendarBeforeUncooperativeProviderFinishes(_ example: BriefingDeadlineExample) async throws {
        let directory = temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let gate = BriefingWeatherGate()
        let calendar = BriefingCalendarFixture()
        let clock = ManualTestClock()
        let location = try syntheticLocation()
        let weather = try syntheticWeather(location: location)
        let controller = makeController(directory: directory, calendar: calendar,
            weather: { _ in try await gate.value() }, timeout: example.requested, clock: clock)
        try controller.updateSettings(.init(calendarIDs: [calendar.choice.id], weatherLocation: location))
        let attempt = Task { await controller.refresh() }
        await gate.waitUntilCalled()
        await clock.waitForSleepers()
        clock.advance(by: example.effective - .milliseconds(1))
        #expect(clock.sleeperCount == 1 && controller.isPreparing, "The deadline fired before its time.")
        clock.advance(by: .milliseconds(1))
        #expect(clock.sleeperCount == 0, "The deadline is longer than the cap allows.")
        let result = await attempt.value
        let returnedBeforeRelease = !gate.wasReleased
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

    @Test func answeredSourceLeavesNoDeadlineBehind() async throws {
        let directory = temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let gate = BriefingWeatherGate()
        let clock = ManualTestClock()
        let location = try syntheticLocation()
        let weather = try syntheticWeather(location: location)
        let controller = makeController(directory: directory, calendar: BriefingCalendarFixture(),
            weather: { _ in try await gate.value() }, clock: clock)
        try controller.updateSettings(.init(weatherLocation: location))
        let attempt = Task { await controller.refresh() }
        await gate.waitUntilCalled()
        await clock.waitForSleepers()
        gate.release(weather)
        let prepared = try #require(await attempt.value)
        #expect(prepared.weather.status == .fresh)
        #expect(clock.sleeperCount == 0, "An answer in time cancels its deadline.")
        clock.advance(by: .seconds(10))
        await Task.yield()
        #expect(controller.prepared?.id == prepared.id && controller.errorMessage == nil)
    }

    /// Every controller sleeps on a test clock. A test that does not advance it has
    /// no deadline that can fire, however long the machine takes.
    private func makeController(directory: URL, calendar: BriefingCalendarFixture,
        weather: @escaping WeatherObservationService.WeatherProvider,
        timeout: Duration = .seconds(10), clock: ManualTestClock = ManualTestClock()) -> MorningBriefingController {
        let date = referenceDate
        return MorningBriefingController(directory: directory,
            calendar: CalendarObservationService(provider: calendar, now: { date }),
            weather: WeatherObservationService(weatherProvider: weather, citySearchProvider: { _ in [] }),
            now: { date }, timeZone: { TimeZone(identifier: "UTC")! }, localeIdentifier: "en_US",
            sourceTimeout: timeout, clock: clock).watchedForHangs()
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
    var changeRevision: UInt64 = 0
    var eventTitle = "SYNTHETIC_PRIVATE_EVENT_TITLE"
    var permissionRequests = 0
    var isAuthorized: Bool { authorized }
    func requestAccess() async throws -> Bool { permissionRequests += 1; return authorized }
    func calendarChoices() throws -> [CalendarChoice] { isAvailable ? [choice] : [] }
    func events(in interval: DateInterval, calendarIDs: Set<String>) throws -> [CalendarObservationEvent] {
        reads += 1
        return [CalendarObservationEvent(id: "synthetic-all-day", calendarID: choice.id,
            title: eventTitle, start: interval.start, end: interval.end, isAllDay: true)]
    }
}

@MainActor
private final class BriefingCallCounter { var count = 0 }

/// The timeout a test asks for, and the one the controller must apply.
struct BriefingDeadlineExample: Sendable, CustomTestStringConvertible {
    let requested: Duration
    let effective: Duration
    var testDescription: String { "asked \(requested), applied \(effective)" }
}

@MainActor
private final class BriefingAsyncSignal {
    private var signalled = false
    private var continuation: CheckedContinuation<Void, Never>?
    func signal() { signalled = true; continuation?.resume(); continuation = nil }
    /// Also returns when the calling task is cancelled, so a test time limit can
    /// end a wait for a signal that never comes.
    func wait() async {
        if signalled { return }
        await withTaskCancellationHandler {
            await withCheckedContinuation { waiting in
                if signalled || Task.isCancelled { waiting.resume() } else { continuation = waiting }
            }
        } onCancel: {
            Task { @MainActor in self.continuation?.resume(); self.continuation = nil }
        }
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
