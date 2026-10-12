import Foundation
import MorningCore
import Observation

/// Only connection choices are durable. No event title, weather response,
/// prepared sentence or source timestamp is encoded in this document.
public struct MorningBriefingSettings: Codable, Sendable, Equatable {
    public var calendarIDs: Set<String>
    public var weatherLocation: WeatherLocation?
    public var temperatureUnit: MorningBriefingTemperatureUnit

    public init(calendarIDs: Set<String> = [], weatherLocation: WeatherLocation? = nil,
                temperatureUnit: MorningBriefingTemperatureUnit = .celsius) {
        self.calendarIDs = calendarIDs
        self.weatherLocation = weatherLocation
        self.temperatureUnit = temperatureUnit
    }

    public func validate() throws {
        guard calendarIDs.count <= 100, calendarIDs.allSatisfy({
            !$0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty && $0.utf8.count <= 1_024 &&
                !$0.unicodeScalars.contains(where: CharacterSet.controlCharacters.contains)
        }) else { throw MorningBriefingControllerError.invalidSettings }
    }

    private enum CodingKeys: String, CodingKey { case calendarIDs, weatherLocation, temperatureUnit }
    public init(from decoder: any Decoder) throws {
        let values = try decoder.container(keyedBy: CodingKeys.self)
        calendarIDs = try values.decode(Set<String>.self, forKey: .calendarIDs)
        weatherLocation = try values.decodeIfPresent(WeatherLocation.self, forKey: .weatherLocation)
        temperatureUnit = try values.decode(MorningBriefingTemperatureUnit.self, forKey: .temperatureUnit)
        try validate()
    }
}

public enum MorningBriefingControllerError: Error, LocalizedError, Sendable, Equatable {
    case invalidSettings, unreadableSettings, staleGeneration, timedOut

    public var errorDescription: String? {
        switch self {
        case .invalidSettings: "Choose valid calendars and a city for the briefing."
        case .unreadableSettings: "Saved briefing settings couldn't be read. Reset them to choose sources again."
        case .staleGeneration: "Local data changed. Reopen briefing settings before continuing."
        case .timedOut: "The source took too long to respond. Your morning can continue without it."
        }
    }
}

/// A preparation owner, not a session runner. Refreshing never starts speech,
/// advances a moment, or asks for Calendar permission. Source payloads remain in
/// memory and every asynchronous publication checks its attempt and privacy epoch.
@MainActor @Observable
public final class MorningBriefingController {
    public private(set) var settings = MorningBriefingSettings()
    public private(set) var calendarChoices: [CalendarChoice] = []
    public private(set) var cityResults: [WeatherLocation] = []
    public private(set) var prepared: PreparedMorningBriefing?
    public private(set) var isPreparing = false
    public private(set) var isConnectingCalendar = false
    public private(set) var isSearchingCities = false
    public private(set) var errorMessage: String?
    public private(set) var settingsRecoveryError: String?
    public var isCalendarAuthorized: Bool { calendar.isAuthorized }
    public var hasConfiguredSources: Bool { !settings.calendarIDs.isEmpty || settings.weatherLocation != nil }
    /// Pin beside a document; settings/reset/cancellation changes invalidate it.
    public var playbackRevision: UUID { revision }

    /// A read-only admission check for an already pinned document. It never
    /// prompts, fetches weather, rewrites text or changes the selected calendars.
    public func permitsPlayback(of document: PreparedMorningBriefing) -> Bool {
        do {
            return try withCurrentAccess {
                guard document.isCurrent(at: now(), timeZoneIdentifier: timeZone().identifier),
                      document.temperatureUnit == settings.temperatureUnit else { return false }
                if document.calendar.status == .notConfigured, !settings.calendarIDs.isEmpty { return false }
                if document.calendar.status == .fresh {
                    guard calendar.isAuthorized, !settings.calendarIDs.isEmpty,
                          document.selectedCalendarIDs == settings.calendarIDs else { return false }
                    let availableIDs = Set(try calendar.calendarChoices().map(\.id))
                    guard settings.calendarIDs.isSubset(of: availableIDs) else { return false }
                }
                if document.weather.status == .notConfigured, settings.weatherLocation != nil { return false }
                if document.weather.status == .fresh {
                    guard document.weatherLocation == settings.weatherLocation,
                          settings.weatherLocation != nil else { return false }
                }
                return true
            }
        } catch { return false }
    }

    @ObservationIgnored private let calendar: CalendarObservationService
    @ObservationIgnored private let weather: WeatherObservationService
    @ObservationIgnored private let control: LocalDataControl
    @ObservationIgnored private let file: AtomicJSONFile<MorningBriefingSettings>
    @ObservationIgnored private let now: @Sendable () -> Date
    @ObservationIgnored private let timeZone: @Sendable () -> TimeZone
    @ObservationIgnored private let localeIdentifier: String
    @ObservationIgnored private let policy: MorningBriefingFreshnessPolicy
    @ObservationIgnored private let sourceTimeout: Duration
    @ObservationIgnored private var generation: UUID?
    @ObservationIgnored private var settingsLoaded = false
    @ObservationIgnored private var revision = UUID()
    @ObservationIgnored private var refreshAttempt: UUID?
    @ObservationIgnored private var refreshTask: Task<PreparedMorningBriefing?, Never>?
    @ObservationIgnored private var accessAttempt: UUID?
    @ObservationIgnored private var accessTask: Task<Void, Never>?
    @ObservationIgnored private var searchAttempt: UUID?
    @ObservationIgnored private var searchTask: Task<Void, Never>?
    @ObservationIgnored private var calendarInput: MorningBriefingInput<CalendarSnapshot> = .notConfigured
    @ObservationIgnored private var weatherInput: MorningBriefingInput<WeatherObservationSnapshot> = .notConfigured
    @ObservationIgnored private var preparingKey: PreparationKey?

    public init(directory: URL = LocalDataControl.defaultDirectory,
                calendar: CalendarObservationService = .init(), weather: WeatherObservationService = .init(),
                now: @escaping @Sendable () -> Date = { Date() },
                timeZone: @escaping @Sendable () -> TimeZone = { .current },
                localeIdentifier: String = "en_US", policy: MorningBriefingFreshnessPolicy = .standard,
                sourceTimeout: Duration = .seconds(10)) {
        self.calendar = calendar; self.weather = weather
        control = LocalDataControl(directory: directory)
        file = AtomicJSONFile(url: directory.appendingPathComponent("briefing-settings.json"))
        self.now = now; self.timeZone = timeZone; self.localeIdentifier = localeIdentifier
        self.policy = policy
        // Test injection may shorten the deadline, never extend the public cap.
        self.sourceTimeout = min(max(sourceTimeout, .milliseconds(1)), .seconds(10))
        reloadSettings()
    }

    /// Explicitly rereads connection choices after a completed local-data reset.
    /// Corrupt/future/unsafe files remain intact and block ordinary updates.
    public func reloadSettings() {
        cancelAndClear()
        settingsLoaded = false
        do {
            let loaded = try control.withReadyAccess { state -> MorningBriefingSettings in
                let value = try loadSettingsFile()
                generation = state.generation
                return value
            }
            settings = loaded
            settingsLoaded = true
            settingsRecoveryError = nil
            errorMessage = nil
        } catch {
            settings = .init()
            settingsRecoveryError = MorningBriefingControllerError.unreadableSettings.localizedDescription
            errorMessage = settingsRecoveryError
        }
    }

    /// Save-before-publish: failure preserves both the existing file and choices.
    public func updateSettings(_ next: MorningBriefingSettings) throws {
        do {
            try next.validate()
            guard settingsRecoveryError == nil else { throw MorningBriefingControllerError.unreadableSettings }
            try withCurrentAccess {
                guard next != settings else { return }
                try file.save(next)
            }
            guard next != settings else { return }
            invalidateWork(clearChoices: false)
            settings = next
            errorMessage = nil
        } catch { errorMessage = safeMessage(error); throw error }
    }

    /// Separate explicit recovery of this small preferences document. It never
    /// clears the person's routine, observations or Calendar/Weather system data.
    public func resetSettings() throws {
        do {
            try control.withReadyAccess { state in
                try validateSettingsPath(allowCorruptRegularFile: true)
                try file.save(.init())
                generation = state.generation
            }
            cancelAndClear()
            settings = .init(); settingsLoaded = true
            settingsRecoveryError = nil; errorMessage = nil
        } catch { errorMessage = safeMessage(error); throw error }
    }

    /// Memory-only and synchronous. A noncooperative native request may finish
    /// later, but cannot publish, save settings or repopulate the cleared cache.
    public func cancelAndClear() { invalidateWork(clearChoices: true) }

    public func requestCalendarAccess() async {
        guard prepareForAccess() else { return }
        accessTask?.cancel()
        let attempt = UUID(), expectedRevision = revision
        accessAttempt = attempt; isConnectingCalendar = true; errorMessage = nil
        let task = Task { @MainActor [weak self] in
            guard let self else { return }
            defer {
                if accessAttempt == attempt { accessAttempt = nil; accessTask = nil; isConnectingCalendar = false }
            }
            do {
                try await calendar.requestAccess()
                try Task.checkCancellation()
                guard revision == expectedRevision, accessAttempt == attempt else { return }
                try withCurrentAccess { }
                calendarChoices = try calendar.calendarChoices()
                calendarInput = settings.calendarIDs.isEmpty ? .notConfigured : .unavailable
                prepared = nil
            } catch {
                guard revision == expectedRevision, accessAttempt == attempt else { return }
                calendarChoices = []
                calendarInput = settings.calendarIDs.isEmpty ? .notConfigured :
                    (error as? CalendarObservationError == .notAuthorized ? .denied : .unavailable)
                prepared = nil
                if !(error is CancellationError) { errorMessage = safeMessage(error) }
            }
        }
        accessTask = task
        await task.value
    }

    /// Explicit query only; no device-location request or inferred city.
    public func searchCities(_ query: String) async {
        guard prepareForAccess() else { return }
        searchTask?.cancel()
        let attempt = UUID(), expectedRevision = revision
        searchAttempt = attempt; isSearchingCities = true; cityResults = []; errorMessage = nil
        let service = weather, timeout = sourceTimeout
        let task = Task { @MainActor [weak self] in
            guard let self else { return }
            defer {
                if searchAttempt == attempt { searchAttempt = nil; searchTask = nil; isSearchingCities = false }
            }
            do {
                let values = try await BriefingSourceDeadline<[WeatherLocation]>().run(timeout: timeout) {
                    try await service.searchCities(query)
                }
                try Task.checkCancellation()
                guard revision == expectedRevision, searchAttempt == attempt else { return }
                try withCurrentAccess { }
                cityResults = values
            } catch {
                guard revision == expectedRevision, searchAttempt == attempt else { return }
                if !(error is CancellationError) { errorMessage = safeMessage(error) }
            }
        }
        searchTask = task
        await task.value
    }

    /// Same-context callers share one preparation, including a concurrent force
    /// request. Force refresh changes source data only; it has no session effects.
    public func refresh(at date: Date? = nil, force: Bool = false) async -> PreparedMorningBriefing? {
        guard prepareForAccess() else { return nil }
        let instant = date ?? now(), zone = timeZone()
        guard instant.timeIntervalSinceReferenceDate.isFinite else {
            cancelAndClear(); errorMessage = MorningBriefingError.invalidDate.localizedDescription; return nil
        }
        var dayCalendar = Calendar(identifier: .gregorian); dayCalendar.timeZone = zone
        let key = PreparationKey(settings: settings, dayStart: dayCalendar.startOfDay(for: instant),
                                 timeZoneIdentifier: zone.identifier)
        if let task = refreshTask, preparingKey == key {
            let result = await task.value
            return Task.isCancelled ? nil : result
        }
        refreshTask?.cancel()
        let attempt = UUID(), expectedRevision = revision
        refreshAttempt = attempt; preparingKey = key; isPreparing = true; prepared = nil; errorMessage = nil
        let task = Task { @MainActor [weak self] () -> PreparedMorningBriefing? in
            guard let self else { return nil }
            defer {
                if refreshAttempt == attempt {
                    refreshAttempt = nil; refreshTask = nil; preparingKey = nil; isPreparing = false
                }
            }
            do {
                var nextCalendar = calendarInput
                var nextWeather = weatherInput
                if key.settings.calendarIDs.isEmpty { nextCalendar = .notConfigured }
                else if !calendar.isAuthorized { nextCalendar = .denied; calendarChoices = [] }
                else {
                    let cached = try compose(calendar: nextCalendar, weather: .notConfigured, at: instant, zone: zone)
                    if force || cached.calendar.status != .fresh {
                        do {
                            calendarChoices = try calendar.calendarChoices()
                            nextCalendar = .snapshot(try calendar.snapshot(for: instant, calendar: dayCalendar,
                                calendarIDs: key.settings.calendarIDs))
                        } catch {
                            nextCalendar = calendar.isAuthorized ? .unavailable : .denied
                        }
                    }
                }
                if let location = key.settings.weatherLocation {
                    let cached = try compose(calendar: .notConfigured, weather: nextWeather, at: instant, zone: zone)
                    if force || cached.weather.status != .fresh {
                        let service = weather
                        do {
                            let value = try await BriefingSourceDeadline<WeatherObservationSnapshot>().run(timeout: sourceTimeout) {
                                try await service.currentWeather(for: location)
                            }
                            nextWeather = .snapshot(value)
                        } catch is CancellationError { throw CancellationError() }
                        catch let error as WeatherObservationError {
                            nextWeather = error == .permissionDenied ? .denied : .unavailable
                        } catch { nextWeather = .unavailable }
                    }
                } else { nextWeather = .notConfigured }
                try Task.checkCancellation()
                guard revision == expectedRevision, refreshAttempt == attempt,
                      timeZone().identifier == key.timeZoneIdentifier, settings == key.settings else { return nil }
                try withCurrentAccess { }
                // Access can be revoked while weather is suspended. Revalidate
                // selection as well so a removed calendar cannot stay cached.
                if !key.settings.calendarIDs.isEmpty {
                    if !calendar.isAuthorized { nextCalendar = .denied; calendarChoices = [] }
                    else {
                        do {
                            calendarChoices = try calendar.calendarChoices()
                            if !key.settings.calendarIDs.isSubset(of: Set(calendarChoices.map(\.id))) {
                                nextCalendar = .unavailable
                            }
                        } catch { nextCalendar = calendar.isAuthorized ? .unavailable : .denied }
                    }
                }
                let completedAt = max(instant, now())
                let document = try compose(calendar: nextCalendar, weather: nextWeather, at: completedAt, zone: zone)
                calendarInput = nextCalendar; weatherInput = nextWeather; prepared = document
                if !document.hasUsableFacts { errorMessage = "No current briefing facts are available. Review your sources or try refreshing." }
                return document
            } catch {
                guard revision == expectedRevision, refreshAttempt == attempt else { return nil }
                if !(error is CancellationError) { errorMessage = safeMessage(error) }
                return nil
            }
        }
        refreshTask = task
        let result = await task.value
        return Task.isCancelled ? nil : result
    }

    private func compose(calendar: MorningBriefingInput<CalendarSnapshot>,
        weather: MorningBriefingInput<WeatherObservationSnapshot>, at date: Date, zone: TimeZone) throws -> PreparedMorningBriefing {
        try MorningBriefingComposer.prepare(calendar: calendar, weather: weather, for: date, at: date,
            timeZoneIdentifier: zone.identifier, localeIdentifier: localeIdentifier,
            temperatureUnit: settings.temperatureUnit, policy: policy)
    }

    private func invalidateWork(clearChoices: Bool) {
        revision = UUID()
        refreshAttempt = nil; accessAttempt = nil; searchAttempt = nil
        refreshTask?.cancel(); accessTask?.cancel(); searchTask?.cancel()
        refreshTask = nil; accessTask = nil; searchTask = nil; preparingKey = nil
        isPreparing = false; isConnectingCalendar = false; isSearchingCities = false
        prepared = nil; calendarInput = .notConfigured; weatherInput = .notConfigured
        cityResults = []
        if clearChoices { calendarChoices = [] }
    }

    private func prepareForAccess() -> Bool {
        do { try withCurrentAccess { }; return true }
        catch { cancelAndClear(); errorMessage = safeMessage(error); return false }
    }

    private func withCurrentAccess<T>(_ body: () throws -> T) throws -> T {
        guard settingsLoaded, settingsRecoveryError == nil else { throw MorningBriefingControllerError.unreadableSettings }
        return try control.withReadyAccess { state in
            guard state.generation == generation else { throw MorningBriefingControllerError.staleGeneration }
            return try body()
        }
    }

    private func loadSettingsFile() throws -> MorningBriefingSettings {
        guard try validateSettingsPath(allowCorruptRegularFile: false) else { return .init() }
        let value = try file.load()
        try value.validate()
        return value
    }

    @discardableResult
    private func validateSettingsPath(allowCorruptRegularFile: Bool) throws -> Bool {
        let attributes: [FileAttributeKey: Any]
        do { attributes = try FileManager.default.attributesOfItem(atPath: file.url.path) }
        catch let error as CocoaError where error.code == .fileReadNoSuchFile { return false }
        guard attributes[.type] as? FileAttributeType == .typeRegular,
              allowCorruptRegularFile || ((attributes[.size] as? NSNumber)?.intValue ?? Int.max) <= 131_072 else {
            throw MorningBriefingControllerError.unreadableSettings
        }
        return true
    }

    private func safeMessage(_ error: any Error) -> String {
        if let error = error as? MorningBriefingControllerError { return error.localizedDescription }
        if let error = error as? MorningBriefingError { return error.localizedDescription }
        if let error = error as? CalendarObservationError { return error.localizedDescription }
        if let error = error as? WeatherObservationError { return error.localizedDescription }
        return "Briefing data is unavailable. Check your sources and local privacy settings."
    }

    private struct PreparationKey: Equatable {
        let settings: MorningBriefingSettings
        let dayStart: Date
        let timeZoneIdentifier: String
    }
}

/// An unstructured, cancellation-aware race. Unlike a task group, timeout does
/// not wait for an uncooperative framework request before returning to the caller.
/// Only the first result resumes the continuation; a late result has no recipient.
@MainActor
private final class BriefingSourceDeadline<Value: Sendable> {
    private var continuation: CheckedContinuation<Value, any Error>?
    private var operation: Task<Void, Never>?
    private var timer: Task<Void, Never>?
    private var finished = false

    func run(timeout: Duration, body: @escaping @MainActor () async throws -> Value) async throws -> Value {
        try Task.checkCancellation()
        return try await withTaskCancellationHandler {
            try await withCheckedThrowingContinuation { continuation in
                self.continuation = continuation
                operation = Task { @MainActor [self] in
                    do { finish(.success(try await body())) }
                    catch { finish(.failure(error)) }
                }
                timer = Task { @MainActor [self] in
                    do { try await Task.sleep(for: timeout) }
                    catch { return }
                    finish(.failure(MorningBriefingControllerError.timedOut))
                }
            }
        } onCancel: {
            Task { @MainActor [self] in finish(.failure(CancellationError())) }
        }
    }

    private func finish(_ result: Result<Value, any Error>) {
        guard !finished else { return }
        finished = true
        let waiting = continuation; continuation = nil
        operation?.cancel(); timer?.cancel()
        operation = nil; timer = nil
        waiting?.resume(with: result)
    }
}
