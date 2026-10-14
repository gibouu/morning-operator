import Foundation
import Testing
import MorningCore
@testable import MorningApple

/// Synthetic providers only. Held reads deliberately ignore cancellation until released.
@Suite("Weather and sleep read together — interleavings of answers, cancel, health and settings", .timeLimit(.minutes(1)), .endsControllerWorkOnCancellation)
@MainActor
struct ConcurrentBriefingSourceTests {
    @Test func bothAnswerOrdersPublishOneSharedDocumentAtOneInstant() async throws {
        for sleepFirst in [false, true] {
            let rig = try ConcurrentBriefingRig()
            defer { rig.close() }
            // Enter from a non-main executor as well as from the main actor.
            let first = Task.detached { await rig.controller.refresh(at: ConcurrentBriefingRig.instant) }
            await rig.started()
            var joinedStarted = false
            let joined = Task { @MainActor in
                joinedStarted = true
                return await rig.controller.refresh(force: true)
            }
            await until { joinedStarted }
            if sleepFirst { rig.sleep.gate.answer(0, .samples(rig.night)) }
            else { rig.weather.answer(0, try rig.observation()) }
            await until { rig.clock.sleeperCount == 1 }
            #expect(rig.controller.prepared == nil && rig.controller.isPreparing,
                    "No partial composition may be published while the sibling is pending.")
            if sleepFirst { rig.weather.answer(0, try rig.observation()) }
            else { rig.sleep.gate.answer(0, .samples(rig.night)) }
            let document = try #require(await first.value)
            #expect(await joined.value == document)
            #expect(document.preparedAt == ConcurrentBriefingRig.instant)
            #expect(document.sleepObservation?.readAt == ConcurrentBriefingRig.instant)
            #expect(rig.sleep.intervals.map(\.end) == [ConcurrentBriefingRig.instant])
            #expect(document.weather.status == .fresh && document.sleep.status == .fresh)
            #expect(rig.controller.prepared == document && !rig.controller.isPreparing)
            #expect(rig.weather.calls == 1 && rig.sleep.gate.calls == 1)
            #expect(rig.clock.sleeperCount == 0)
        }
    }

    @Test func explicitCancelCancelsBothProvidersBeforeEitherLateAnswer() async throws {
        let rig = try ConcurrentBriefingRig()
        defer { rig.close() }
        let attempt = Task { await rig.controller.refresh() }
        await rig.started()
        rig.controller.cancelAndClear()
        #expect(await attempt.value == nil)
        #expect(rig.weather.cancelled.contains(0) && rig.sleep.gate.cancelled.contains(0))
        #expect(rig.clock.sleeperCount == 0)
        rig.sleep.gate.answer(0, .samples(rig.night))
        rig.weather.answer(0, try rig.observation())
        await settle()
        #expect(rig.controller.prepared == nil && !rig.controller.isPreparing)
        #expect(rig.controller.errorMessage == nil && rig.clock.sleeperCount == 0)
    }

    @Test func healthOffDuringActiveAndQueuedReadsNeverCallsAnExcludedReader() async throws {
        for queued in [false, true] {
            for _ in 0..<(queued ? 40 : 1) {
                let rig = try ConcurrentBriefingRig()
                defer { rig.close() }
                if queued {
                    // The weather operation changes settings in its own actor turn, racing
                    // the already-created sleep child and its queued provider operation.
                    rig.weather.onEnter = { [unowned rig] in
                        try rig.controller.updateSettings(.init(weatherLocation: rig.location))
                        throw CancellationError()
                    }
                }
                let attempt = Task { await rig.controller.refresh() }
                if !queued {
                    await rig.started()
                    try rig.controller.updateSettings(.init(weatherLocation: rig.location))
                }
                #expect(await attempt.value == nil)
                #expect(rig.sleep.readsWhileExcluded == 0)
                #expect(!rig.controller.settings.includesHealth && rig.controller.prepared == nil)
                #expect(rig.clock.sleeperCount == 0)
                rig.weather.onEnter = nil
                rig.weather.failAll(); rig.sleep.gate.failAll()
                let excluded = Task { await rig.controller.refresh(force: true) }
                await until { rig.weather.calls == 2 }
                rig.weather.answer(1, try rig.observation())
                let result = try #require(await excluded.value)
                #expect(result.sleep.status == .notConfigured && result.sleepObservation == nil)
                #expect(rig.sleep.readsWhileExcluded == 0 && rig.sleep.gate.calls <= 1)
                #expect(rig.clock.sleeperCount == 0)
            }
        }
    }

    @Test func settingsChangedBetweenAnswersCannotMixOldAndNewAttempts() async throws {
        for sleepFirst in [false, true] {
            let rig = try ConcurrentBriefingRig()
            defer { rig.close() }
            let old = Task { await rig.controller.refresh() }
            await rig.started()
            if sleepFirst { rig.sleep.gate.answer(0, .samples(rig.night)) }
            else { rig.weather.answer(0, try rig.observation()) }
            await until { rig.clock.sleeperCount == 1 }
            let other = try WeatherLocation(latitude: 51, longitude: 0, displayName: "SYNTHETIC_OTHER_CITY")
            try rig.controller.updateSettings(.init(weatherLocation: other, temperatureUnit: .fahrenheit, includesHealth: true))
            #expect(await old.value == nil)
            #expect(rig.clock.sleeperCount == 0)
            let replacement = Task { await rig.controller.refresh() }
            await rig.started(count: 2)
            // The old sibling answers while the new pair is still pending.
            if sleepFirst { rig.weather.answer(0, try rig.observation()) }
            else { rig.sleep.gate.answer(0, .samples(rig.night)) }
            await settle()
            #expect(rig.controller.prepared == nil)
            rig.weather.answer(1, try rig.observation(location: other, temperature: 5))
            rig.sleep.gate.answer(1, .samples([]))
            let current = try #require(await replacement.value)
            #expect(current.weatherLocation == other && current.temperatureUnit == .fahrenheit)
            #expect(current.weather.status == .fresh && current.sleep.status == .missing)
            #expect(current.sleepObservation == nil && rig.controller.prepared == current)
            #expect(rig.weather.calls == 2 && rig.sleep.gate.calls == 2 && rig.clock.sleeperCount == 0)
        }
    }

    @Test func eitherLateSourceIsDroppedWithoutPoisoningTheNextRefresh() async throws {
        for lateSleep in [false, true] {
            let rig = try ConcurrentBriefingRig()
            defer { rig.close() }
            let attempt = Task { await rig.controller.refresh() }
            await rig.started()
            if lateSleep { rig.weather.answer(0, try rig.observation()) }
            else { rig.sleep.gate.answer(0, .samples(rig.night)) }
            await until { rig.clock.sleeperCount == 1 }
            rig.clock.advance(by: .seconds(10))
            let timedOut = try #require(await attempt.value)
            #expect(timedOut.sleep.status == (lateSleep ? .unavailable : .fresh))
            #expect(timedOut.weather.status == (lateSleep ? .fresh : .unavailable))
            #expect(rig.clock.sleeperCount == 0)
            let next = Task { await rig.controller.refresh(force: true) }
            await rig.started(count: 2)
            if lateSleep { rig.sleep.gate.answer(0, .samples(rig.night)) }
            else { rig.weather.answer(0, try rig.observation(temperature: 99)) }
            await settle()
            #expect(rig.controller.prepared == nil && rig.clock.sleeperCount == 2)
            rig.sleep.gate.answer(1, .samples([]))
            rig.weather.answer(1, try rig.observation(temperature: 3))
            let fresh = try #require(await next.value)
            #expect(fresh.sleep.status == .missing && fresh.weather.status == .fresh)
            #expect(fresh.id != timedOut.id && rig.controller.prepared == fresh)
            #expect(rig.clock.sleeperCount == 0)
        }
    }

    /// Both answers arrive at the deadline instant, together with both timers.
    /// Either contender may win each tie; there is one publication and no sleeper left.
    @Test func bothAnswersAtTheDeadlineInstantPublishOnceAndLeaveNoSleepers() async throws {
        let rig = try ConcurrentBriefingRig()
        defer { rig.close() }
        let attempt = Task { await rig.controller.refresh() }
        await rig.started()
        let arrive: @MainActor () -> Void = { [unowned rig] in
            let remaining = Duration.seconds(10) - rig.clock.now.offset
            if remaining > .zero { rig.clock.advance(by: remaining) }
        }
        rig.weather.onReturn = arrive
        rig.sleep.gate.onReturn = arrive
        rig.weather.answer(0, try rig.observation())
        rig.sleep.gate.answer(0, .samples(rig.night))
        let document = try #require(await attempt.value)
        #expect([.fresh, .unavailable].contains(document.weather.status))
        #expect([.fresh, .unavailable].contains(document.sleep.status))
        #expect((document.sleepObservation != nil) == (document.sleep.status == .fresh))
        #expect(document.preparedAt == ConcurrentBriefingRig.instant && rig.clock.sleeperCount == 0)
        await settle()
        #expect(rig.controller.prepared == document && !rig.controller.isPreparing)
        #expect(rig.clock.sleeperCount == 0)
    }

    private func settle() async {
        for _ in 0..<40 { await Task.yield() }
    }

    private func until(_ predicate: @MainActor () -> Bool) async {
        while !predicate() && !Task.isCancelled { await Task.yield() }
    }
}

@MainActor
private final class ConcurrentBriefingRig {
    nonisolated static let instant = Date(timeIntervalSince1970: 1_791_619_200) // 2026-10-10 08:00 UTC
    let directory = FileManager.default.temporaryDirectory.appendingPathComponent("ConcurrentBriefing-SYNTHETIC-\(UUID())")
    let clock = ManualTestClock()
    let weather = ConcurrentHeldRead<WeatherObservationSnapshot>()
    let sleep = ConcurrentSleepReader()
    let location: WeatherLocation
    let controller: MorningBriefingController
    var night: [SleepSample] {
        [.init(stage: .asleepCore, start: Self.instant.addingTimeInterval(-8 * 3600),
               end: Self.instant.addingTimeInterval(-3600), sourceID: "SYNTHETIC_SLEEP", sourceKind: .watch)]
    }

    init() throws {
        location = try WeatherLocation(latitude: 48, longitude: 2, displayName: "SYNTHETIC_CITY")
        let weather = weather
        controller = MorningBriefingController(directory: directory,
            calendar: CalendarObservationService(provider: ConcurrentEmptyCalendar(), now: { Self.instant }),
            weather: WeatherObservationService(weatherProvider: { _ in
                MainActor.assertIsolated()
                return try await weather.read()
            }, citySearchProvider: { _ in [] }),
            sleep: SleepObservationService(provider: sleep), now: { Self.instant },
            timeZone: { TimeZone(identifier: "UTC")! }, localeIdentifier: "en_GB", clock: clock).watchedForHangs()
        sleep.isExcluded = { [weak controller] in controller?.settings.includesHealth != true }
        try controller.updateSettings(.init(weatherLocation: location, includesHealth: true))
    }

    func started(count: Int = 1) async {
        while (weather.calls < count || sleep.gate.calls < count) && !Task.isCancelled { await Task.yield() }
        await clock.waitForSleepers(2)
    }

    func observation(location: WeatherLocation? = nil, temperature: Double = 18) throws -> WeatherObservationSnapshot {
        let url = URL(string: "https://example.invalid/SYNTHETIC")!
        return try WeatherObservationSnapshot(location: location ?? self.location, retrievedAt: Self.instant,
            observationAt: Self.instant, temperatureCelsius: temperature, conditionDescription: "SYNTHETIC_WEATHER",
            symbolName: "sun.max", attribution: WeatherAttributionInfo(legalURL: url, combinedMarkLightURL: url,
                combinedMarkDarkURL: url, serviceName: "Synthetic Weather"))
    }

    func close() {
        controller.cancelAndClear()
        weather.onEnter = nil; weather.onReturn = nil
        sleep.gate.onEnter = nil; sleep.gate.onReturn = nil
        weather.failAll(); sleep.gate.failAll()
        try? FileManager.default.removeItem(at: directory)
    }
}

/// Cancellation is recorded synchronously, without an actor-hop race in the assertion.
private final class ConcurrentCancellationLog: @unchecked Sendable {
    private let lock = NSLock()
    private var values: Set<Int> = []
    func mark(_ id: Int) { lock.withLock { _ = values.insert(id) } }
    var snapshot: Set<Int> { lock.withLock { values } }
}

@MainActor
private final class ConcurrentHeldRead<Value: Sendable> {
    private var pending: [Int: CheckedContinuation<Value, any Error>] = [:]
    private let cancellations = ConcurrentCancellationLog()
    private(set) var calls = 0
    var cancelled: Set<Int> { cancellations.snapshot }
    var onEnter: (@MainActor () throws -> Void)?
    var onReturn: (@MainActor () -> Void)?

    func read() async throws -> Value {
        MainActor.assertIsolated()
        let id = calls; calls += 1
        try onEnter?()
        let log = cancellations
        let value = try await withTaskCancellationHandler {
            try await withCheckedThrowingContinuation { pending[id] = $0 }
        } onCancel: { log.mark(id) }
        MainActor.assertIsolated()
        onReturn?()
        return value
    }

    func answer(_ id: Int, _ value: Value) { pending.removeValue(forKey: id)?.resume(returning: value) }
    func failAll() {
        let held = pending; pending.removeAll()
        for continuation in held.values { continuation.resume(throwing: CancellationError()) }
    }
}

@MainActor
private final class ConcurrentSleepReader: SleepObservationProviding {
    let gate = ConcurrentHeldRead<SleepReadOutcome>()
    var isExcluded: @MainActor () -> Bool = { false }
    private(set) var readsWhileExcluded = 0
    private(set) var intervals: [DateInterval] = []
    func requestReadAccess() async throws { Issue.record("A refresh must never prompt for health access.") }
    func sleepSamples(in interval: DateInterval) async throws -> SleepReadOutcome {
        MainActor.assertIsolated()
        if isExcluded() { readsWhileExcluded += 1 }
        intervals.append(interval)
        return try await gate.read()
    }
}

@MainActor
private final class ConcurrentEmptyCalendar: CalendarObservationProviding {
    var isAuthorized: Bool { true }
    func requestAccess() async throws -> Bool { true }
    func calendarChoices() throws -> [CalendarChoice] { [] }
    func events(in interval: DateInterval, calendarIDs: Set<String>) throws -> [CalendarObservationEvent] { [] }
}
