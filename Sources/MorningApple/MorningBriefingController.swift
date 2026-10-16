import Foundation
import MorningCore
import Observation

/// Only connection choices are durable. No event title, weather response, sleep
/// sample, prepared sentence or source timestamp is encoded in this document.
public struct MorningBriefingSettings: Codable, Sendable, Equatable {
    public var calendarIDs: Set<String>
    public var weatherLocation: WeatherLocation?
    /// Device coordinates remain transient; weatherLocation retains only a chosen fallback city.
    public var usesCurrentLocation: Bool
    public var temperatureUnit: MorningBriefingTemperatureUnit
    /// The person's choice to include sleep in the briefing,
    /// independent of calendar and weather. Off until they turn it on; while it is off
    /// the health reader is never called. A settings file saved before this choice
    /// existed has no such key and loads as off.
    public var includesHealth: Bool
    /// Expanded read scope, separately confirmed for people who enabled sleep before it existed.
    public var includesHealthMetrics: Bool

    public init(calendarIDs: Set<String> = [], weatherLocation: WeatherLocation? = nil,
                temperatureUnit: MorningBriefingTemperatureUnit = .celsius, includesHealth: Bool = false,
                usesCurrentLocation: Bool? = nil, includesHealthMetrics: Bool = false) {
        self.calendarIDs = calendarIDs
        self.weatherLocation = weatherLocation
        self.usesCurrentLocation = usesCurrentLocation ?? (weatherLocation == nil)
        self.temperatureUnit = temperatureUnit
        self.includesHealth = includesHealth
        self.includesHealthMetrics = includesHealth && includesHealthMetrics
    }

    public static let maximumCalendarIDs = 100
    public static let maximumCalendarIDBytes = 1_024
    /// The one size limit of the settings file, applied when it is written and when it is read.
    /// It holds every value `validate()` accepts: JSON writes a quote, a backslash or a slash as
    /// two bytes and nothing else longer (control characters are refused), so 100 calendar IDs
    /// take at most 100 × (2 × 1,024 + 10) = 205,800 bytes with their quotes, comma and
    /// indentation, the city name at most 2 × `WeatherLocation.maximumLabelBytes` = 262,144,
    /// and the remaining fields under 1,024: 468,968 in all. Earlier builds read back at most
    /// 131,072 bytes, so every file they could read is still read.
    public static let maximumEncodedBytes = 512 * 1_024

    public func validate() throws {
        guard (!includesHealthMetrics || includesHealth), calendarIDs.count <= Self.maximumCalendarIDs, calendarIDs.allSatisfy({
            !$0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty && $0.utf8.count <= Self.maximumCalendarIDBytes &&
                !$0.unicodeScalars.contains(where: CharacterSet.controlCharacters.contains)
        }) else { throw MorningBriefingControllerError.invalidSettings }
    }

    private enum CodingKeys: String, CodingKey { case calendarIDs, weatherLocation, temperatureUnit, includesHealth, usesCurrentLocation, includesHealthMetrics }
    public init(from decoder: any Decoder) throws {
        let values = try decoder.container(keyedBy: CodingKeys.self)
        calendarIDs = try values.decode(Set<String>.self, forKey: .calendarIDs)
        weatherLocation = try values.decodeIfPresent(WeatherLocation.self, forKey: .weatherLocation)
        usesCurrentLocation = try values.decodeIfPresent(Bool.self, forKey: .usesCurrentLocation) ?? (weatherLocation == nil)
        temperatureUnit = try values.decode(MorningBriefingTemperatureUnit.self, forKey: .temperatureUnit)
        includesHealth = try values.decodeIfPresent(Bool.self, forKey: .includesHealth) ?? false
        includesHealthMetrics = try values.decodeIfPresent(Bool.self, forKey: .includesHealthMetrics) ?? false
        if !includesHealth { includesHealthMetrics = false }
        try validate()
    }
}

public enum MorningBriefingControllerError: Error, LocalizedError, Sendable, Equatable {
    case invalidSettings, unreadableSettings, staleGeneration, timedOut
    /// The choices are valid one by one but their saved form would exceed the settings file's
    /// limit. Nothing was written and the choices in effect are unchanged.
    case settingsTooLarge

    public var errorDescription: String? { message(locale: AppLanguage.locale) }

    func message(locale: Locale) -> String {
        let bundle = AppLanguage.bundle(for: .module, languageCode: locale.language.languageCode?.identifier)
        return switch self {
        case .invalidSettings: AppLanguage.localized("Choose valid calendars and a city for the briefing.", bundle: bundle, locale: locale)
        case .unreadableSettings: AppLanguage.localized("Saved briefing settings couldn't be read. Reset them to choose sources again.", bundle: bundle, locale: locale)
        case .staleGeneration: AppLanguage.localized("Local data changed. Reopen briefing settings before continuing.", bundle: bundle, locale: locale)
        case .timedOut: AppLanguage.localized("The source took too long to respond. Your morning can continue without it.", bundle: bundle, locale: locale)
        case .settingsTooLarge: AppLanguage.localized("These briefing choices are too large to save. Your previous choices are unchanged. Choose fewer calendars.", bundle: bundle, locale: locale)
        }
    }
}

/// Why the city field has nothing to offer: Apple Maps answered with no city,
/// or the typed-ahead lookup failed or timed out.
public enum CitySearchOutcome: Sendable, Equatable { case noMatch, unavailable }

/// A preparation owner, not a session runner. Refreshing never starts speech,
/// advances a moment, or asks for Calendar permission. Source payloads remain in
/// memory and every asynchronous publication checks its attempt and privacy epoch.
@MainActor @Observable
public final class MorningBriefingController {
    public private(set) var settings = MorningBriefingSettings()
    public private(set) var calendarChoices: [CalendarChoice] = []
    public private(set) var cityResults: [WeatherLocation] = []
    public private(set) var citySuggestions: [CitySuggestion] = []
    public private(set) var citySearchOutcome: CitySearchOutcome?
    public private(set) var prepared: PreparedMorningBriefing?
    public private(set) var isPreparing = false
    public private(set) var isConnectingCalendar = false
    public private(set) var isConnectingHealth = false
    /// A connection error is not a read-permission verdict. HealthKit keeps that private.
    public var healthConnectionIssue: String? { healthConnectionError.map { healthMessage($0) } }
    public var isHealthReaderConnected: Bool { sleep.isConnected }
    public private(set) var isSearchingCities = false
    public private(set) var errorMessage: String?
    public private(set) var settingsRecoveryError: String?
    public var isCalendarAuthorized: Bool { calendar.isAuthorized }
    public var hasConfiguredSources: Bool {
        !settings.calendarIDs.isEmpty || currentWeatherLocation != nil || settings.includesHealth
    }
    public var currentWeatherLocation: WeatherLocation? {
        settings.usesCurrentLocation ? (deviceLocation.authorization == .authorized ? resolvedLocation : nil) : settings.weatherLocation
    }
    public var locationAuthorization: WeatherLocationAuthorization { deviceLocation.authorization }
    public var locationIssue: String? {
        if let error = locationError as? WeatherDeviceLocationError {
            return error.message(locale: Locale(identifier: localeIdentifier))
        }
        return locationError?.moreDescription
    }
    /// The same memory-only observation used by the briefing, admitted for the
    /// currently selected city. Reading it never contacts the provider.
    public var currentWeatherSnapshot: WeatherObservationSnapshot? {
        currentWeather(at: now())
    }
    /// Pin beside a document; settings/reset/cancellation changes invalidate it.
    public var playbackRevision: UUID { revision }

    /// Questions in other moments can reuse admitted weather without another read
    /// or adding Health data. A pinned/opening weather passage takes precedence.
    public func conversationWeatherText(excluding documents: [PreparedMorningBriefing] = []) -> String? {
        guard !documents.contains(where: { $0.weather.status == .fresh }),
              let document = prepared, document.weather.status == .fresh,
              permitsPlayback(of: document), !document.weather.text.isEmpty else { return nil }
        return document.weather.text
    }

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
                          document.selectedCalendarIDs == settings.calendarIDs,
                          calendarPlaybackAdmissions[document.id]?.changeRevision == calendar.changeRevision
                    else { return false }
                    let availableIDs = Set(try calendar.calendarChoices().map(\.id))
                    guard settings.calendarIDs.isSubset(of: availableIDs),
                          calendarPlaybackAdmissions[document.id]?.changeRevision == calendar.changeRevision
                    else { return false }
                }
                if document.weather.status == .notConfigured, currentWeatherLocation != nil { return false }
                if document.weather.status == .fresh {
                    guard document.weatherLocation == currentWeatherLocation,
                          currentWeatherLocation != nil else { return false }
                }
                // A document prepared with health must not play once health is excluded,
                // and one prepared without it is out of date once health is included.
                guard (document.sleep.status != .notConfigured) == settings.includesHealth else { return false }
                guard document.healthMetrics.contains(where: { $0.section.status != .notConfigured }) == settings.includesHealthMetrics else { return false }
                if settings.includesHealth {
                    guard sleepPlaybackAdmissions[document.id]?.revision == sleepPlaybackRevision else { return false }
                }
                return true
            }
        } catch { return false }
    }

    @ObservationIgnored private let calendar: CalendarObservationService
    @ObservationIgnored private let deviceLocation: any WeatherDeviceLocationProviding
    private var resolvedLocation: WeatherLocation?
    private var locationError: (any Error)?
    private var healthConnectionError: (any Error)?
    @ObservationIgnored private var locationResolvedAt: Date?
    @ObservationIgnored private var locationTask: Task<Void, Never>?
    @ObservationIgnored private var locationAttempt: UUID?
    @ObservationIgnored private let weather: WeatherObservationService
    @ObservationIgnored private let sleep: SleepObservationService
    @ObservationIgnored private let healthMetrics: HealthMetricsObservationService
    @ObservationIgnored private let control: LocalDataControl
    @ObservationIgnored private let file: AtomicJSONFile<MorningBriefingSettings>
    @ObservationIgnored private let now: @Sendable () -> Date
    @ObservationIgnored private let timeZone: @Sendable () -> TimeZone
    private var localeIdentifier: String
    @ObservationIgnored private let policy: MorningBriefingFreshnessPolicy
    @ObservationIgnored private let sourceTimeout: Duration
    @ObservationIgnored private let suggestionDelay: Duration
    @ObservationIgnored private let clock: any Clock<Duration>
    @ObservationIgnored private var generation: UUID?
    @ObservationIgnored private var settingsLoaded = false
    @ObservationIgnored private var revision = UUID()
    @ObservationIgnored private var refreshAttempt: UUID?
    @ObservationIgnored private var refreshTask: Task<PreparedMorningBriefing?, Never>?
    @ObservationIgnored private var accessAttempt: UUID?
    @ObservationIgnored private var accessTask: Task<Void, Never>?
    @ObservationIgnored private var healthAccessAttempt: UUID?
    @ObservationIgnored private var healthAccessTask: Task<Bool, Never>?
    @ObservationIgnored private var searchAttempt: UUID?
    @ObservationIgnored private var searchTask: Task<WeatherLocation?, Never>?
    @ObservationIgnored private var cityQuery = ""
    @ObservationIgnored private var suggestionAttempt: UUID?
    @ObservationIgnored private var suggestionTask: Task<Void, Never>?
    @ObservationIgnored private var calendarInput: MorningBriefingInput<CalendarSnapshot> = .notConfigured
    /// Metadata only for still-current pinned documents. A refreshed document must
    /// never reauthorize older text that predates a known Calendar change.
    @ObservationIgnored private var calendarPlaybackAdmissions: [UUID: CalendarPlaybackAdmission] = [:]
    @ObservationIgnored private var weatherInput: MorningBriefingInput<WeatherObservationSnapshot> = .notConfigured
    @ObservationIgnored private var lastWeatherAttemptAt: Date?
    @ObservationIgnored private var sleepInput: SleepBriefingInput = .excluded
    @ObservationIgnored private var healthMetricsInput: [HealthMetric: HealthMetricBriefingInput] = [:]
    /// An empty/failed reread or a return from Settings must not reauthorize older sleep text.
    @ObservationIgnored private var sleepPlaybackRevision = UUID()
    @ObservationIgnored private var sleepPlaybackAdmissions: [UUID: SleepPlaybackAdmission] = [:]
    @ObservationIgnored private var preparingKey: PreparationKey?

    public init(directory: URL = LocalDataControl.defaultDirectory,
                calendar: CalendarObservationService = .init(), weather: WeatherObservationService = .init(),
                sleep: SleepObservationService = .init(), healthMetrics: HealthMetricsObservationService = .init(),
                deviceLocation: (any WeatherDeviceLocationProviding)? = nil,
                now: @escaping @Sendable () -> Date = { Date() },
                timeZone: @escaping @Sendable () -> TimeZone = { .current },
                localeIdentifier: String = AppLanguage.localeIdentifier, policy: MorningBriefingFreshnessPolicy = .standard,
                sourceTimeout: Duration = .seconds(10), suggestionDelay: Duration = .milliseconds(250),
                clock: any Clock<Duration> = ContinuousClock(),
                settingsByteLimit: Int = MorningBriefingSettings.maximumEncodedBytes) {
        self.calendar = calendar; self.weather = weather
        self.deviceLocation = deviceLocation ?? WeatherDeviceLocation()
        // The default has no reader: until one is passed in, sleep is "not part of this version".
        self.sleep = sleep
        self.healthMetrics = healthMetrics
        control = LocalDataControl(directory: directory)
        // Test injection may lower the limit, never raise it. Writer and reader share it.
        file = AtomicJSONFile(url: directory.appendingPathComponent("briefing-settings.json"),
            maximumBytes: min(max(settingsByteLimit, 1), MorningBriefingSettings.maximumEncodedBytes))
        self.now = now; self.timeZone = timeZone; self.localeIdentifier = localeIdentifier
        self.policy = policy
        // Test injection may shorten the deadline, never extend the public cap.
        self.sourceTimeout = min(max(sourceTimeout, .milliseconds(1)), .seconds(10))
        self.suggestionDelay = suggestionDelay
        // The source deadline and the typing pause both sleep on this clock. The app
        // keeps the continuous clock; tests pass one they advance by hand.
        self.clock = clock
        reloadSettings()
    }

    /// Invalidates only prepared prose and local read work; source choices remain saved.
    public func appLanguageDidChange(locale: Locale = AppLanguage.locale) {
        localeIdentifier = locale.identifier
        // Only the native provider creates this app-owned label; city/provider names stay exact.
        if deviceLocation is WeatherDeviceLocation, let location = resolvedLocation {
            resolvedLocation = try? WeatherLocation(latitude: location.latitude, longitude: location.longitude,
                displayName: WeatherDeviceLocation.currentLocationName(locale: locale))
        }
        let healthFailure = healthConnectionError
        invalidateWork(clearChoices: false)
        healthConnectionError = healthFailure
        if settingsRecoveryError != nil {
            settingsRecoveryError = MorningBriefingControllerError.unreadableSettings.moreDescription
            errorMessage = settingsRecoveryError
        } else { errorMessage = nil }
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
            settingsRecoveryError = MorningBriefingControllerError.unreadableSettings.moreDescription
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
                do { try file.save(next) }
                catch PersistenceError.fileTooLarge { throw MorningBriefingControllerError.settingsTooLarge }
            }
            guard next != settings else { return }
            cancelLocationRequest()
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
    /// The suggestion source forgets its earlier typing as well.
    public func cancelAndClear() {
        cancelLocationRequest()
        resolvedLocation = nil; locationResolvedAt = nil; locationError = nil
        invalidateWork(clearChoices: true)
    }

    /// Cancels a foreground fix or authorization wait without erasing a usable
    /// weather observation. Inactive system permission sheets are not background.
    public func cancelLocationRequest() {
        locationAttempt = nil; locationTask?.cancel(); locationTask = nil
        deviceLocation.cancel()
    }

    /// Permission is requested only from an explained, explicit action.
    @discardableResult public func enableCurrentLocation(requestPermission: Bool = true, resolveLocation: Bool = true) async -> Bool {
        guard prepareForAccess() else { return false }
        do {
            if requestPermission, deviceLocation.authorization == .notDetermined {
                guard try await deviceLocation.requestAuthorization() else { throw WeatherDeviceLocationError.denied }
            }
            try Task.checkCancellation()
            var next = settings; next.usesCurrentLocation = true
            try updateSettings(next)
            if resolveLocation { await resolveCurrentLocationIfNeeded(force: true) }
            return resolveLocation ? currentWeatherLocation != nil : deviceLocation.authorization == .authorized
        } catch {
            if !(error is CancellationError) { locationError = error }
            return false
        }
    }

    /// Passive foreground refresh: never requests a system permission.
    public func resolveCurrentLocationIfNeeded(force: Bool = false) async {
        guard prepareForAccess(), settings.usesCurrentLocation else { return }
        guard deviceLocation.authorization == .authorized else {
            if resolvedLocation != nil { invalidateWork(clearChoices: false) }
            resolvedLocation = nil; locationResolvedAt = nil
            if deviceLocation.authorization == .denied { locationError = WeatherDeviceLocationError.denied }
            return
        }
        if let task = locationTask { await task.value; return }
        let instant = now()
        if !force, let locationResolvedAt, instant >= locationResolvedAt,
           instant.timeIntervalSince(locationResolvedAt) < 300 { return }
        let id = UUID(), expectedRevision = revision
        locationAttempt = id
        let task = Task { @MainActor [weak self] in
            guard let self else { return }
            defer { if locationAttempt == id { locationAttempt = nil; locationTask = nil } }
            do {
                let location = try await deviceLocation.currentLocation()
                try Task.checkCancellation()
                guard locationAttempt == id, revision == expectedRevision, settings.usesCurrentLocation else { return }
                try withCurrentAccess { }
                // Avoid throwing away a fresh observation for normal GPS jitter.
                let moved = resolvedLocation.map { old in
                    let latitudeMeters = (location.latitude - old.latitude) * 111_000
                    let longitudeMeters = (location.longitude - old.longitude) * 111_000 * cos(location.latitude * .pi / 180)
                    return hypot(latitudeMeters, longitudeMeters) >= 1_000
                } ?? true
                if moved { invalidateWork(clearChoices: false); resolvedLocation = location }
                locationResolvedAt = now(); locationError = nil
            } catch {
                guard locationAttempt == id, revision == expectedRevision else { return }
                if !(error is CancellationError) {
                    locationError = error
                    // A failed new fix must not masquerade as a current position.
                    resolvedLocation = nil; locationResolvedAt = now()
                    invalidateWork(clearChoices: false)
                }
            }
        }
        locationTask = task; await task.value
    }

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

    /// The explicit Health action, after its purpose has been explained in the UI.
    /// A handled prompt saves the person's inclusion choice; it never claims that
    /// HealthKit allowed the read. Only a later sample can establish a recorded night.
    @discardableResult public func enableHealth(includeMetrics: Bool = false) async -> Bool {
        guard prepareForAccess() else { return false }
        if let task = healthAccessTask { return await task.value }
        let attempt = UUID(), expectedRevision = revision
        healthAccessAttempt = attempt; isConnectingHealth = true; healthConnectionError = nil
        let task = Task { @MainActor [weak self] () -> Bool in
            guard let self else { return false }
            defer {
                if healthAccessAttempt == attempt {
                    healthAccessAttempt = nil; healthAccessTask = nil; isConnectingHealth = false
                }
            }
            do {
                try Task.checkCancellation()
                guard healthAccessAttempt == attempt, revision == expectedRevision else { return false }
                if includeMetrics { try await healthMetrics.requestReadAccess() }
                else { try await sleep.requestReadAccess() }
                try Task.checkCancellation()
                guard healthAccessAttempt == attempt, revision == expectedRevision else { return false }
                try withCurrentAccess { }
                // No suspension between privacy/revision validation and the save.
                var next = settings; next.includesHealth = true
                next.includesHealthMetrics = settings.includesHealthMetrics || includeMetrics
                try updateSettings(next)
                return true
            } catch {
                guard healthAccessAttempt == attempt, revision == expectedRevision else { return false }
                if !(error is CancellationError) { healthConnectionError = error }
                return false
            }
        }
        healthAccessTask = task
        return await task.value
    }

    /// Cancels an outstanding prompt even when the saved choice was already off.
    /// A late native completion can neither save a choice nor restore cleared data.
    public func disableHealth() throws {
        cancelHealthConnection()
        var next = settings; next.includesHealth = false
        next.includesHealthMetrics = false
        try updateSettings(next)
    }

    /// Call on background/foreground transitions, never for an inactive permission
    /// sheet. Apple exposes no read-permission status: discard sleep while away and
    /// require a new read before any previous Health text can play again.
    public func invalidateHealthForForeground() {
        if isConnectingHealth { cancelHealthConnection() }
        guard settings.includesHealth else { return }
        refreshAttempt = nil; refreshTask?.cancel(); refreshTask = nil; preparingKey = nil; isPreparing = false
        prepared = nil; sleepInput = .excluded; healthMetricsInput = [:]
        sleepPlaybackRevision = UUID(); sleepPlaybackAdmissions = [:]
    }

    private func cancelHealthConnection() {
        healthAccessAttempt = nil; healthAccessTask?.cancel(); healthAccessTask = nil
        isConnectingHealth = false; healthConnectionError = nil
    }

    /// Explicit query only; no device-location request or inferred city.
    public func searchCities(_ query: String) async {
        guard prepareForAccess() else { return }
        cancelCityLookups()
        let attempt = UUID(), expectedRevision = revision
        // The explicit search owns the list now; suggestions for earlier typing go.
        searchAttempt = attempt; isSearchingCities = true; cityResults = []; citySuggestions = []
        citySearchOutcome = nil; errorMessage = nil
        let service = weather, timeout = sourceTimeout, clock = clock
        let task = Task { @MainActor [weak self] () -> WeatherLocation? in
            guard let self else { return nil }
            defer {
                if searchAttempt == attempt { searchAttempt = nil; searchTask = nil; isSearchingCities = false }
            }
            do {
                let values = try await BriefingSourceDeadline<[WeatherLocation]>(clock: clock).run(timeout: timeout) {
                    try await service.searchCities(query)
                }
                try Task.checkCancellation()
                guard revision == expectedRevision, searchAttempt == attempt else { return nil }
                try withCurrentAccess { }
                cityResults = values
                if values.isEmpty { citySearchOutcome = .noMatch }
            } catch {
                guard revision == expectedRevision, searchAttempt == attempt else { return nil }
                if !(error is CancellationError) { errorMessage = safeMessage(error) }
            }
            return nil
        }
        searchTask = task
        _ = await task.value
    }

    /// The city field's text changed. Results of an explicit search and a pending
    /// search or choice belonged to the earlier text, so they are dropped and can
    /// no longer publish. Suggestions follow after two characters and a short
    /// pause, so each keystroke doesn't become an Apple Maps request.
    public func cityQueryChanged(_ text: String) {
        let query = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard query != cityQuery else { return }
        guard query.count >= 2 else { clearCitySearch(); cityQuery = query; return }
        cancelCityLookups()
        cityResults = []; citySearchOutcome = nil
        cityQuery = query
        startSuggestions(query, after: suggestionDelay)
    }

    /// Suggestions while typing. Earlier suggestions stay visible until newer ones
    /// arrive. A superseded request is silent; a failed or timed-out one is
    /// reported as unavailable, never as "no match".
    public func suggestCities(_ query: String) async {
        await startSuggestions(query, after: .zero)?.value
    }

    @discardableResult
    private func startSuggestions(_ query: String, after delay: Duration) -> Task<Void, Never>? {
        guard prepareForAccess() else { return nil }
        suggestionTask?.cancel()
        let attempt = UUID(), expectedRevision = revision
        suggestionAttempt = attempt
        let service = weather, timeout = sourceTimeout, clock = clock
        let task = Task { @MainActor [weak self] in
            if delay > .zero { try? await clock.sleep(for: delay) }
            guard let self, !Task.isCancelled else { return }
            defer { if suggestionAttempt == attempt { suggestionAttempt = nil; suggestionTask = nil } }
            do {
                let values = try await BriefingSourceDeadline<[CitySuggestion]>(clock: clock).run(timeout: timeout) {
                    try await service.suggestCities(query)
                }
                guard !Task.isCancelled, revision == expectedRevision, suggestionAttempt == attempt,
                      (try? withCurrentAccess { }) != nil else { return }
                citySuggestions = values
                citySearchOutcome = values.isEmpty ? .noMatch : nil
            } catch {
                guard !(error is CancellationError), !Task.isCancelled,
                      revision == expectedRevision, suggestionAttempt == attempt else { return }
                citySearchOutcome = .unavailable
            }
        }
        suggestionTask = task
        return task
    }

    /// Resolves the chosen suggestion to a place and saves it as the weather city.
    /// The last check and the save are one step, so newer typing, a new search or
    /// leaving the city field either cancels the choice (nil, nothing saved) or
    /// comes after a completed save.
    public func chooseCity(_ suggestion: CitySuggestion) async -> WeatherLocation? {
        guard prepareForAccess() else { return nil }
        cancelCityLookups()
        let attempt = UUID(), expectedRevision = revision
        searchAttempt = attempt; isSearchingCities = true; errorMessage = nil
        let service = weather, timeout = sourceTimeout, clock = clock
        let task = Task { @MainActor [weak self] () -> WeatherLocation? in
            guard let self else { return nil }
            defer {
                if searchAttempt == attempt { searchAttempt = nil; searchTask = nil; isSearchingCities = false }
            }
            do {
                let location = try await BriefingSourceDeadline<WeatherLocation?>(clock: clock).run(timeout: timeout) {
                    try await service.resolveCity(suggestion)
                }
                try Task.checkCancellation()
                guard revision == expectedRevision, searchAttempt == attempt else { return nil }
                try withCurrentAccess { }
                guard let location else {
                    errorMessage = WeatherObservationError.searchUnavailable.moreDescription
                    return nil
                }
                searchAttempt = nil; searchTask = nil; isSearchingCities = false
                var next = settings; next.weatherLocation = location; next.usesCurrentLocation = false
                try updateSettings(next)
                return location
            } catch {
                guard revision == expectedRevision, searchAttempt == attempt else { return nil }
                if !(error is CancellationError) { errorMessage = safeMessage(error) }
                return nil
            }
        }
        searchTask = task
        return await task.value
    }

    /// Ends city searching: when the query is emptied or too short, and when the
    /// city field goes away. Pending lookups are cancelled and cannot publish.
    public func clearCitySearch() {
        cancelCityLookups()
        cityQuery = ""; cityResults = []; citySuggestions = []; citySearchOutcome = nil
    }

    private func cancelCityLookups() {
        suggestionTask?.cancel(); suggestionTask = nil; suggestionAttempt = nil
        searchTask?.cancel(); searchTask = nil; searchAttempt = nil
        isSearchingCities = false
    }

    /// A quiet Home can stay open all day. Reuse the preparation/cache owner and
    /// retry unavailable weather at most every five minutes while foregrounded.
    public func refreshForHome(at date: Date? = nil) async {
        guard prepareForAccess() else { return }
        await resolveCurrentLocationIfNeeded()
        guard currentWeatherLocation != nil else { return }
        let instant = date ?? now()
        guard instant.timeIntervalSinceReferenceDate.isFinite, currentWeather(at: instant) == nil else { return }
        if let lastWeatherAttemptAt, instant >= lastWeatherAttemptAt,
           instant.timeIntervalSince(lastWeatherAttemptAt) < 300 { return }
        _ = await refresh(at: instant)
    }

    private func currentWeather(at instant: Date) -> WeatherObservationSnapshot? {
        guard (try? withCurrentAccess { }) != nil, let location = currentWeatherLocation,
              case .snapshot(let snapshot) = weatherInput,
              snapshot.isCurrent(for: location, at: instant, maximumAge: policy.weatherMaximumAge) else { return nil }
        return snapshot
    }

    /// Today's events in the selected calendars, for the calendar extra. Never prompts and
    /// never changes the cached briefing. Nil when no calendar is selected, access is
    /// missing or the read fails: no events is never assumed.
    public func selectedEvents(on day: Date, timeZone: TimeZone) -> [CalendarEventSummary]? {
        guard !settings.calendarIDs.isEmpty, calendar.isAuthorized else { return nil }
        var dayCalendar = Calendar(identifier: .gregorian); dayCalendar.timeZone = timeZone
        return try? withCurrentAccess {
            try calendar.snapshot(for: day, calendar: dayCalendar, calendarIDs: settings.calendarIDs).events
        }
    }

    /// Same-context callers share one preparation, including a concurrent force
    /// request. Force refresh changes source data only; it has no session effects.
    public func refresh(at date: Date? = nil, force: Bool = false) async -> PreparedMorningBriefing? {
        guard prepareForAccess() else { return nil }
        await resolveCurrentLocationIfNeeded(force: force)
        guard prepareForAccess(), !Task.isCancelled else { return nil }
        let instant = date ?? now(), zone = timeZone()
        guard instant.timeIntervalSinceReferenceDate.isFinite else {
            cancelAndClear(); errorMessage = MorningBriefingError.invalidDate.moreDescription; return nil
        }
        var dayCalendar = Calendar(identifier: .gregorian); dayCalendar.timeZone = zone
        let key = PreparationKey(settings: settings, weatherLocation: currentWeatherLocation, dayStart: dayCalendar.startOfDay(for: instant),
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
                var nextSleep = sleepInput
                var nextMetrics = healthMetricsInput
                if key.settings.calendarIDs.isEmpty { nextCalendar = .notConfigured }
                else if !calendar.isAuthorized { nextCalendar = .denied; calendarChoices = [] }
                else {
                    let cached = try compose(calendar: nextCalendar, weather: .notConfigured, at: instant, zone: zone)
                    if force || cached.calendar.status != .fresh || !calendarRevisionMatches(nextCalendar) {
                        do {
                            calendarChoices = try calendar.calendarChoices()
                            nextCalendar = .snapshot(try calendar.snapshot(for: instant, calendar: dayCalendar,
                                calendarIDs: key.settings.calendarIDs))
                        } catch {
                            nextCalendar = calendar.isAuthorized ? .unavailable : .denied
                        }
                    }
                }
                // Weather and sleep do not depend on each other, so they are read at the same
                // time: when both hang, the refresh ends at one deadline, not after two (#85).
                // `async let` keeps both reads child tasks of this refresh: cancelling it
                // cancels both, and leaving this scope early (one read cancelled) cancels and
                // awaits the other. Both still finish here, before the one composition below.
                let cachedWeather = nextWeather, cachedSleep = nextSleep, cachedMetrics = nextMetrics
                async let weatherRead = readWeather(cached: cachedWeather, location: key.weatherLocation, force: force,
                                                    at: instant, zone: zone)
                async let sleepRead = readSleep(cached: cachedSleep, settings: key.settings, force: force,
                                                at: instant, zone: zone, attempt: attempt, revision: expectedRevision)
                async let metricsRead = readHealthMetrics(cached: cachedMetrics, settings: key.settings, force: force,
                    at: instant, zone: zone, attempt: attempt, revision: expectedRevision)
                nextWeather = try await weatherRead
                nextSleep = try await sleepRead
                nextMetrics = try await metricsRead
                try Task.checkCancellation()
                guard revision == expectedRevision, refreshAttempt == attempt,
                      timeZone().identifier == key.timeZoneIdentifier, settings == key.settings,
                      currentWeatherLocation == key.weatherLocation else { return nil }
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
                            } else if !calendarRevisionMatches(nextCalendar) {
                                // EventKit can change while weather/sleep is suspended.
                                // Re-read this date range before publishing fresh facts.
                                nextCalendar = .snapshot(try calendar.snapshot(for: instant, calendar: dayCalendar,
                                    calendarIDs: key.settings.calendarIDs))
                            }
                        } catch { nextCalendar = calendar.isAuthorized ? .unavailable : .denied }
                    }
                }
                let completedAt = max(instant, now())
                let document = try compose(calendar: nextCalendar, weather: nextWeather, sleep: nextSleep,
                    healthMetrics: nextMetrics, at: completedAt, zone: zone)
                calendarPlaybackAdmissions = calendarPlaybackAdmissions.filter {
                    $0.value.changeRevision == calendar.changeRevision && $0.value.validUntil > completedAt
                }
                if document.calendar.status == .fresh,
                   case .snapshot(let snapshot) = nextCalendar, let validUntil = document.calendar.validUntil {
                    calendarPlaybackAdmissions[document.id] = .init(changeRevision: snapshot.changeRevision,
                        validUntil: validUntil)
                }
                if !sameSleepRead(sleepInput, nextSleep) || !sameMetricsRead(healthMetricsInput, nextMetrics) {
                    sleepPlaybackRevision = UUID(); sleepPlaybackAdmissions = [:]
                }
                sleepPlaybackAdmissions = sleepPlaybackAdmissions.filter { $0.value.validUntil > completedAt }
                if key.settings.includesHealth, let validUntil = document.validUntil {
                    sleepPlaybackAdmissions[document.id] = .init(revision: sleepPlaybackRevision, validUntil: validUntil)
                }
                calendarInput = nextCalendar; weatherInput = nextWeather; sleepInput = nextSleep; prepared = document
                healthMetricsInput = nextMetrics
                if !document.hasUsableFacts { errorMessage = AppLanguage.localized("No current briefing facts are available. Review your sources or try refreshing.", bundle: .module) }
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

    /// The weather part of one refresh. Returns the cached input when it is still fresh.
    private func readWeather(cached: MorningBriefingInput<WeatherObservationSnapshot>, location: WeatherLocation?,
                             force: Bool, at instant: Date, zone: TimeZone) async throws -> MorningBriefingInput<WeatherObservationSnapshot> {
        guard let location else {
            return settings.usesCurrentLocation && deviceLocation.authorization == .denied ? .denied : .notConfigured
        }
        let current = try compose(calendar: .notConfigured, weather: cached, at: instant, zone: zone)
        guard force || current.weather.status != .fresh else { return cached }
        let service = weather
        lastWeatherAttemptAt = instant
        do {
            return .snapshot(try await BriefingSourceDeadline<WeatherObservationSnapshot>(clock: clock).run(timeout: sourceTimeout) {
                try await service.currentWeather(for: location)
            })
        } catch is CancellationError { throw CancellationError() }
        catch let error as WeatherObservationError { return error == .permissionDenied ? .denied : .unavailable }
        catch { return .unavailable }
    }

    /// Reuses the person's Health choice for morning learning, without asking for access.
    /// Samples stay in memory; missing/unreadable sleep leaves Screen Time's own rule in use.
    public func morningSleepWindows(at instant: Date, calendar: Calendar) async throws -> [DateInterval] {
        guard settings.includesHealth else { return [] }
        let expectedRevision = revision, service = sleep
        let input: SleepBriefingInput
        do {
            input = try await BriefingSourceDeadline<SleepBriefingInput>(clock: clock).run(timeout: sourceTimeout) { [weak self] in
                guard let self, self.revision == expectedRevision, self.settings.includesHealth else {
                    throw CancellationError()
                }
                return try await service.read(at: instant)
            }
        } catch is CancellationError { throw CancellationError() }
        catch { return [] }
        try Task.checkCancellation()
        guard revision == expectedRevision, settings.includesHealth else { throw CancellationError() }
        guard case .snapshot(let snapshot) = input else { return [] }
        let asleep = snapshot.samples.filter {
            $0.stage.isAsleep && $0.start.timeIntervalSinceReferenceDate.isFinite
                && $0.end.timeIntervalSinceReferenceDate.isFinite && $0.end > $0.start
                && $0.end <= instant && $0.end.timeIntervalSince($0.start) <= SleepNight.maximumSampleSpan
        }.sorted { ($0.start, $0.end) < ($1.start, $1.end) }
        var episodes: [(window: DateInterval, asleepSeconds: TimeInterval)] = []
        for sample in asleep {
            // Keep short overnight interruptions together; a later nap is a separate episode.
            if let previous = episodes.last, sample.start.timeIntervalSince(previous.window.end) <= 3_600 {
                let added = max(0, sample.end.timeIntervalSince(max(sample.start, previous.window.end)))
                episodes[episodes.count - 1] = (DateInterval(start: previous.window.start,
                    end: max(previous.window.end, sample.end)), previous.asleepSeconds + added)
            } else {
                episodes.append((DateInterval(start: sample.start, end: sample.end), sample.end.timeIntervalSince(sample.start)))
            }
        }
        var windows: [DateInterval] = []
        var day = calendar.startOfDay(for: instant.addingTimeInterval(-SleepObservationService.lookback))
        let lastDay = calendar.startOfDay(for: instant)
        while day <= lastDay {
            // Compare recorded asleep time, never duplicated source totals or awake gaps.
            let candidates = episodes.filter {
                calendar.isDate($0.window.end, inSameDayAs: day)
                    && calendar.component(.hour, from: $0.window.end) < 14
                    && $0.window.duration <= SleepNight.maximumSampleSpan && $0.asleepSeconds >= 30
            }
            if let longest = candidates.max(by: {
                $0.asleepSeconds != $1.asleepSeconds ? $0.asleepSeconds < $1.asleepSeconds : $0.window.end < $1.window.end
            }) { windows.append(longest.window) }
            guard let next = calendar.date(byAdding: .day, value: 1, to: day), next > day else { break }
            day = next
        }
        return windows
    }

    /// The sleep part of one refresh. Excluded means the reader is not called at all.
    private func readSleep(cached: SleepBriefingInput, settings: MorningBriefingSettings, force: Bool,
                           at instant: Date, zone: TimeZone, attempt: UUID, revision expectedRevision: UUID) async throws -> SleepBriefingInput {
        guard settings.includesHealth else { return .excluded }
        let current = try compose(calendar: .notConfigured, weather: .notConfigured, sleep: cached, at: instant, zone: zone)
        // A read that found no night is read again: the night can arrive later.
        guard force || current.sleep.status != .fresh else { return cached }
        let service = sleep
        do {
            return try await BriefingSourceDeadline<SleepBriefingInput>(clock: clock).run(timeout: sourceTimeout) { [weak self] in
                // This closure runs in its own queued task. Health can be turned
                // off, or this attempt cancelled, before it gets its turn: check
                // again here, or the reader would be called while excluded.
                guard let self, self.revision == expectedRevision, self.refreshAttempt == attempt,
                      self.settings.includesHealth else { throw CancellationError() }
                return try await service.read(at: instant)
            }
        } catch is CancellationError { throw CancellationError() }
        catch { return .notReadable }
    }

    private func readHealthMetrics(cached: [HealthMetric: HealthMetricBriefingInput], settings: MorningBriefingSettings,
        force: Bool, at instant: Date, zone: TimeZone, attempt: UUID, revision expectedRevision: UUID) async throws -> [HealthMetric: HealthMetricBriefingInput] {
        guard settings.includesHealth && settings.includesHealthMetrics else { return [:] }
        async let hrv = readMetric(.heartRateVariabilitySDNN)
        async let heart = readMetric(.restingHeartRate)
        async let breathing = readMetric(.respiratoryRate)
        return try await [.heartRateVariabilitySDNN: hrv, .restingHeartRate: heart, .respiratoryRate: breathing]

        func readMetric(_ metric: HealthMetric) async throws -> HealthMetricBriefingInput {
            let previous = cached[metric] ?? .excluded
            let document = try compose(calendar: .notConfigured, weather: .notConfigured,
                healthMetrics: [metric: previous], at: instant, zone: zone)
            if !force, document.healthMetrics.first(where: { $0.metric == metric })?.section.status == .fresh { return previous }
            let service = healthMetrics
            do {
                return try await BriefingSourceDeadline<HealthMetricBriefingInput>(clock: clock).run(timeout: sourceTimeout) { [weak self] in
                    guard let self, self.revision == expectedRevision, self.refreshAttempt == attempt,
                          self.settings.includesHealth, self.settings.includesHealthMetrics else { throw CancellationError() }
                    return try await service.read(metric, at: instant)
                }
            } catch is CancellationError { throw CancellationError() }
            catch { return .notReadable }
        }
    }

    private func compose(calendar: MorningBriefingInput<CalendarSnapshot>,
        weather: MorningBriefingInput<WeatherObservationSnapshot>, sleep: SleepBriefingInput = .excluded,
        healthMetrics: [HealthMetric: HealthMetricBriefingInput] = [:],
        at date: Date, zone: TimeZone) throws -> PreparedMorningBriefing {
        try MorningBriefingComposer.prepare(calendar: calendar, weather: weather, sleep: sleep, healthMetrics: healthMetrics, for: date, at: date,
            timeZoneIdentifier: zone.identifier, localeIdentifier: localeIdentifier,
            temperatureUnit: settings.temperatureUnit, policy: policy)
    }

    private func calendarRevisionMatches(_ input: MorningBriefingInput<CalendarSnapshot>) -> Bool {
        guard case .snapshot(let snapshot) = input else { return true }
        return snapshot.changeRevision == calendar.changeRevision
    }

    /// Reading the same sample values again preserves still-current pinned prose.
    /// A read that is now empty or failed invalidates the earlier observation.
    private func sameSleepRead(_ first: SleepBriefingInput, _ second: SleepBriefingInput) -> Bool {
        if case .snapshot(let lhs) = first, case .snapshot(let rhs) = second { return lhs.samples == rhs.samples }
        return first == second
    }

    private func sameMetricsRead(_ first: [HealthMetric: HealthMetricBriefingInput], _ second: [HealthMetric: HealthMetricBriefingInput]) -> Bool {
        HealthMetric.allCases.allSatisfy { metric in
            if case .snapshot(let lhs) = first[metric], case .snapshot(let rhs) = second[metric] {
                return lhs.samples == rhs.samples
            }
            return first[metric] == second[metric]
        }
    }

    private func invalidateWork(clearChoices: Bool) {
        revision = UUID()
        cancelHealthConnection()
        refreshAttempt = nil; accessAttempt = nil; searchAttempt = nil; suggestionAttempt = nil
        refreshTask?.cancel(); accessTask?.cancel(); searchTask?.cancel(); suggestionTask?.cancel()
        refreshTask = nil; accessTask = nil; searchTask = nil; suggestionTask = nil; preparingKey = nil
        isPreparing = false; isConnectingCalendar = false; isSearchingCities = false
        prepared = nil; calendarInput = .notConfigured; weatherInput = .notConfigured; sleepInput = .excluded
        healthMetricsInput = [:]
        lastWeatherAttemptAt = nil
        calendarPlaybackAdmissions = [:]
        sleepPlaybackRevision = UUID(); sleepPlaybackAdmissions = [:]
        cityQuery = ""; cityResults = []; citySuggestions = []; citySearchOutcome = nil
        if clearChoices { calendarChoices = []; weather.forgetCitySuggestions() }
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
              allowCorruptRegularFile || ((attributes[.size] as? NSNumber)?.intValue ?? Int.max) <= (file.maximumBytes ?? MorningBriefingSettings.maximumEncodedBytes) else {
            throw MorningBriefingControllerError.unreadableSettings
        }
        return true
    }

    private func safeMessage(_ error: any Error) -> String {
        if let error = error as? MorningBriefingControllerError { return error.moreDescription }
        if let error = error as? MorningBriefingError { return error.moreDescription }
        if let error = error as? CalendarObservationError { return error.moreDescription }
        if let error = error as? WeatherObservationError { return error.moreDescription }
        return AppLanguage.localized("Briefing data is unavailable. Check your sources and local privacy settings.", bundle: .module)
    }

    private func healthMessage(_ error: any Error) -> String {
        let locale = Locale(identifier: localeIdentifier)
        let bundle = AppLanguage.bundle(for: .module, languageCode: locale.language.languageCode?.identifier)
        if let error = error as? MorningBriefingControllerError { return error.message(locale: locale) }
        return switch error as? SleepObservationError {
        case .unavailableOnDevice:
            AppLanguage.localized("Health data is not available on this device.", bundle: bundle, locale: locale)
        case .notConnected, .missingUsageDescription:
            AppLanguage.localized("Sleep reading is not available in this version.", bundle: bundle, locale: locale)
        case nil:
            AppLanguage.localized("Health access could not be prepared. Try again in Settings.", bundle: bundle, locale: locale)
        }
    }

    private struct PreparationKey: Equatable {
        let settings: MorningBriefingSettings
        let weatherLocation: WeatherLocation?
        let dayStart: Date
        let timeZoneIdentifier: String
    }

    private struct CalendarPlaybackAdmission {
        let changeRevision: UInt64
        let validUntil: Date
    }

    private struct SleepPlaybackAdmission {
        let revision: UUID
        let validUntil: Date
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
    private let clock: any Clock<Duration>

    init(clock: any Clock<Duration>) { self.clock = clock }

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
                    do { try await clock.sleep(for: timeout) }
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
