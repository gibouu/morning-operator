import Foundation
import CoreLocation
import WeatherKit
@preconcurrency import MapKit

/// A deliberately selected place, never a request for the device's current location.
public struct WeatherLocation: Codable, Sendable, Equatable, Identifiable {
    public let latitude: Double
    public let longitude: Double
    public let displayName: String
    public var id: String { "\(latitude),\(longitude)" }

    public init(latitude: Double, longitude: Double, displayName: String) throws {
        guard latitude.isFinite, longitude.isFinite, (-90...90).contains(latitude),
              (-180...180).contains(longitude), Self.validLabel(displayName, maximum: 160) else {
            throw WeatherObservationError.invalidLocation
        }
        self.latitude = latitude
        self.longitude = longitude
        self.displayName = displayName
    }

    private enum CodingKeys: String, CodingKey { case latitude, longitude, displayName }
    public init(from decoder: any Decoder) throws {
        let values = try decoder.container(keyedBy: CodingKeys.self)
        try self.init(latitude: values.decode(Double.self, forKey: .latitude),
                      longitude: values.decode(Double.self, forKey: .longitude),
                      displayName: values.decode(String.self, forKey: .displayName))
    }

    fileprivate static func validLabel(_ value: String, maximum: Int) -> Bool {
        !value.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty && value.count <= maximum &&
            !value.unicodeScalars.contains { CharacterSet.controlCharacters.contains($0) }
    }
}

/// Display the appropriate Apple Weather mark together with the legal link.
/// These URLs come from WeatherService.attribution, not invented asset locations.
public struct WeatherAttributionInfo: Sendable, Equatable {
    public let legalURL: URL
    public let combinedMarkLightURL: URL
    public let combinedMarkDarkURL: URL
    public let serviceName: String

    public init(legalURL: URL, combinedMarkLightURL: URL, combinedMarkDarkURL: URL, serviceName: String) throws {
        guard [legalURL, combinedMarkLightURL, combinedMarkDarkURL].allSatisfy({
            $0.scheme?.lowercased() == "https" && $0.host?.isEmpty == false && $0.user == nil && $0.password == nil
        }), WeatherLocation.validLabel(serviceName, maximum: 160) else {
            throw WeatherObservationError.attributionUnavailable
        }
        self.legalURL = legalURL
        self.combinedMarkLightURL = combinedMarkLightURL
        self.combinedMarkDarkURL = combinedMarkDarkURL
        self.serviceName = serviceName
    }
}

/// Transient current conditions. Do not persist this in observation/routine history.
/// `observationAt` is CurrentWeather.date: Apple may model these conditions rather
/// than provide a literal instrument observation. `retrievedAt` is local retrieval
/// completion. Expiry is Apple's metadata, not a promise of refresh or availability.
public struct WeatherObservationSnapshot: Sendable, Equatable {
    public let location: WeatherLocation
    public let retrievedAt: Date
    public let observationAt: Date
    public let temperatureCelsius: Double
    public let conditionDescription: String
    public let symbolName: String
    public let attribution: WeatherAttributionInfo
    public let expiresAt: Date?

    public init(location: WeatherLocation, retrievedAt: Date, observationAt: Date,
                temperatureCelsius: Double, conditionDescription: String, symbolName: String,
                attribution: WeatherAttributionInfo, expiresAt: Date? = nil) throws {
        guard retrievedAt.timeIntervalSince1970.isFinite, observationAt.timeIntervalSince1970.isFinite,
              expiresAt?.timeIntervalSince1970.isFinite != false,
              temperatureCelsius.isFinite, temperatureCelsius >= -273.15,
              WeatherLocation.validLabel(conditionDescription, maximum: 240),
              WeatherLocation.validLabel(symbolName, maximum: 120) else {
            throw WeatherObservationError.invalidResponse
        }
        self.location = location
        self.retrievedAt = retrievedAt
        self.observationAt = observationAt
        self.temperatureCelsius = temperatureCelsius
        self.conditionDescription = conditionDescription
        self.symbolName = symbolName
        self.attribution = attribution
        self.expiresAt = expiresAt
    }
}

public enum WeatherObservationError: LocalizedError, Sendable, Equatable {
    case invalidLocation
    case invalidSearchQuery
    case permissionDenied
    case networkUnavailable
    case serviceUnavailable
    case searchUnavailable
    case attributionUnavailable
    case invalidResponse

    public var errorDescription: String? {
        switch self {
        case .invalidLocation: "Choose a valid city for the weather."
        case .invalidSearchQuery: "Enter a city name of up to 200 characters."
        case .permissionDenied: "Apple Weather denied access. This build's WeatherKit capability and developer setup need checking."
        case .networkUnavailable: "Weather couldn't connect to Apple. Try again when a connection is available."
        case .serviceUnavailable: "Apple Weather is unavailable right now. Your morning can continue without it."
        case .searchUnavailable: "Apple Maps couldn't search for cities right now. Try again later."
        case .attributionUnavailable: "Apple Weather's required source information couldn't be loaded. Try refreshing the weather."
        case .invalidResponse: "Apple Weather returned incomplete current conditions. Try refreshing the weather."
        }
    }
}

/// A city name suggested by Apple Maps while a person types. It carries no
/// coordinates; it is resolved to a `WeatherLocation` only when chosen.
public struct CitySuggestion: Sendable, Equatable, Identifiable {
    public let id: String
    public let title: String
    public let subtitle: String
    public var label: String { subtitle.isEmpty ? title : "\(title), \(subtitle)" }

    public init(title: String, subtitle: String) {
        self.title = title; self.subtitle = subtitle
        id = "\(title)\u{1F}\(subtitle)"
    }
}

/// No work is performed by initialization. Search/refresh only when explicitly
/// requested by the app; there is no location manager, automatic refresh, cache,
/// telemetry, cloud-model fallback, or dependency on calendar availability.
@MainActor
public final class WeatherObservationService {
    public typealias WeatherProvider = @MainActor (WeatherLocation) async throws -> WeatherObservationSnapshot
    public typealias CitySearchProvider = @MainActor (String) async throws -> [WeatherLocation]
    public typealias CitySuggestionProvider = @MainActor (String) async throws -> [CitySuggestion]
    public typealias CitySuggestionResolver = @MainActor (CitySuggestion) async throws -> [WeatherLocation]
    private let weatherProvider: WeatherProvider
    private let citySearchProvider: CitySearchProvider
    private let citySuggestionProvider: CitySuggestionProvider
    private let citySuggestionResolver: CitySuggestionResolver

    public convenience init() {
        self.init(weatherProvider: Self.nativeWeather, citySearchProvider: Self.nativeCitySearch,
                  citySuggestionProvider: { try await NativeCitySuggestions.shared.suggest($0) },
                  citySuggestionResolver: { try await NativeCitySuggestions.shared.resolve($0) })
    }

    /// Inject providers for deterministic tests; construction never calls them.
    /// Without suggestion providers, typed suggestions reuse the city search.
    public init(weatherProvider: @escaping WeatherProvider, citySearchProvider: @escaping CitySearchProvider,
                citySuggestionProvider: CitySuggestionProvider? = nil,
                citySuggestionResolver: CitySuggestionResolver? = nil) {
        self.weatherProvider = weatherProvider
        self.citySearchProvider = citySearchProvider
        self.citySuggestionProvider = citySuggestionProvider ?? { query in
            try await citySearchProvider(query).map { CitySuggestion(title: $0.displayName, subtitle: "") }
        }
        self.citySuggestionResolver = citySuggestionResolver ?? { try await citySearchProvider($0.label) }
    }

    public func currentWeather(for location: WeatherLocation) async throws -> WeatherObservationSnapshot {
        try Task.checkCancellation()
        do {
            let snapshot = try await weatherProvider(location)
            try Task.checkCancellation()
            guard snapshot.location == location else { throw WeatherObservationError.invalidResponse }
            return snapshot
        } catch {
            try Task.checkCancellation()
            throw Self.classifiedError(error)
        }
    }

    /// The query is sent to Apple Maps, only on this explicit call. Results are
    /// locality-filtered and still need a person to select one; no city is inferred.
    public func searchCities(_ query: String) async throws -> [WeatherLocation] {
        try Task.checkCancellation()
        let query = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard WeatherLocation.validLabel(query, maximum: 200) else {
            throw WeatherObservationError.invalidSearchQuery
        }
        do {
            let values = try await citySearchProvider(query)
            try Task.checkCancellation()
            var seen = Set<String>()
            return Array(values.filter { seen.insert($0.id).inserted }.prefix(8))
        } catch {
            try Task.checkCancellation()
            throw Self.classifiedError(error, searching: true)
        }
    }

    /// Typed-ahead city names from Apple Maps, sent only while the person types
    /// in the city field. No coordinates and no device location are involved.
    public func suggestCities(_ query: String) async throws -> [CitySuggestion] {
        try Task.checkCancellation()
        let query = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard WeatherLocation.validLabel(query, maximum: 200) else {
            throw WeatherObservationError.invalidSearchQuery
        }
        do {
            let values = try await citySuggestionProvider(query)
            try Task.checkCancellation()
            var seen = Set<String>()
            return Array(values.filter { !$0.title.isEmpty && seen.insert($0.id).inserted }.prefix(8))
        } catch {
            try Task.checkCancellation()
            throw Self.classifiedError(error, searching: true)
        }
    }

    /// Resolves the suggestion the person chose into one place for the weather.
    public func resolveCity(_ suggestion: CitySuggestion) async throws -> WeatherLocation? {
        try Task.checkCancellation()
        do {
            let values = try await citySuggestionResolver(suggestion)
            try Task.checkCancellation()
            return values.first
        } catch {
            try Task.checkCancellation()
            throw Self.classifiedError(error, searching: true)
        }
    }

    /// Do not infer a missing entitlement from arbitrary daemon/network errors.
    /// Only WeatherKit's documented permissionDenied maps to the setup guidance.
    static func classifiedError(_ error: any Error, searching: Bool = false) -> any Error {
        if error is CancellationError { return CancellationError() }
        if let known = error as? WeatherObservationError { return known }
        if let weather = error as? WeatherError, weather == .permissionDenied {
            return WeatherObservationError.permissionDenied
        }
        let native = error as NSError
        if native.domain == NSURLErrorDomain {
            if native.code == NSURLErrorCancelled { return CancellationError() }
            return WeatherObservationError.networkUnavailable
        }
        // MKError.serverFailure is a service failure, not proof of an offline device.
        return searching ? WeatherObservationError.searchUnavailable : WeatherObservationError.serviceUnavailable
    }

    private static func nativeWeather(_ location: WeatherLocation) async throws -> WeatherObservationSnapshot {
        let service = WeatherService.shared
        let nativeLocation = CLLocation(latitude: location.latitude, longitude: location.longitude)
        let current: CurrentWeather = try await service.weather(for: nativeLocation, including: .current)
        try Task.checkCancellation()
        let nativeAttribution: WeatherAttribution
        do { nativeAttribution = try await service.attribution }
        catch {
            try Task.checkCancellation()
            let mapped = classifiedError(error)
            if mapped is CancellationError { throw mapped }
            if let known = mapped as? WeatherObservationError,
               known == .permissionDenied || known == .networkUnavailable { throw known }
            throw WeatherObservationError.attributionUnavailable
        }
        try Task.checkCancellation()
        let attribution = try WeatherAttributionInfo(legalURL: nativeAttribution.legalPageURL,
            combinedMarkLightURL: nativeAttribution.combinedMarkLightURL,
            combinedMarkDarkURL: nativeAttribution.combinedMarkDarkURL, serviceName: nativeAttribution.serviceName)
        return try WeatherObservationSnapshot(location: location, retrievedAt: Date(), observationAt: current.date,
            temperatureCelsius: current.temperature.converted(to: .celsius).value,
            conditionDescription: current.condition.description, symbolName: current.symbolName,
            attribution: attribution, expiresAt: current.metadata.expirationDate)
    }

    private static func nativeCitySearch(_ query: String) async throws -> [WeatherLocation] {
        try await NativeWeatherCitySearch(query: query).results()
    }
}

/// One owner per search prevents an old cancellation from cancelling a newer
/// request. Convert framework objects to Sendable values on the main queue.
@MainActor
final class NativeWeatherCitySearch {
    private let query: String
    private var search: MKLocalSearch?

    init(query: String) { self.query = query }

    static func candidates(_ response: MKLocalSearch.Response) -> [(WeatherLocation, String?)] {
        response.mapItems.compactMap { item -> (WeatherLocation, String?)? in
            let coordinate = item.location.coordinate
            let address = item.addressRepresentations
            guard let label = WeatherCityRanking.label(context: address?.cityWithContext(.full),
                      city: address?.cityName, country: address?.regionName, name: item.name),
                  let location = try? WeatherLocation(latitude: coordinate.latitude,
                      longitude: coordinate.longitude, displayName: label) else { return nil }
            return (location, address?.region?.identifier)
        }
    }

    /// Cities first; if MapKit finds none with the place filter (it rejects
    /// "London", for example), retry once without it.
    func results() async throws -> [WeatherLocation] {
        do {
            let filtered = try await run(filter: MKAddressFilter(including: [.locality, .administrativeArea]))
            if !filtered.isEmpty { return filtered }
        } catch {
            if error is CancellationError { throw error }
        }
        return try await run(filter: nil)
    }

    private func run(filter: MKAddressFilter?) async throws -> [WeatherLocation] {
        let request = MKLocalSearch.Request()
        request.naturalLanguageQuery = query
        request.resultTypes = .address
        if let filter { request.addressFilter = filter }
        // Without location access MapKit otherwise biases an unregioned query
        // toward a default map region. Search the whole world; the device's
        // region is ranked first below.
        request.region = MKCoordinateRegion(.world)
        request.regionPriority = .default
        let search = MKLocalSearch(request: request)
        self.search = search
        return try await withTaskCancellationHandler {
            try Task.checkCancellation()
            let values: [WeatherLocation] = try await withCheckedThrowingContinuation { continuation in
                search.start { response, error in
                    if let error { continuation.resume(throwing: error); return }
                    guard let response else {
                        continuation.resume(throwing: WeatherObservationError.searchUnavailable); return
                    }
                    continuation.resume(returning: WeatherCityRanking.preferringRegion(Self.candidates(response),
                        region: Locale.current.region?.identifier))
                }
            }
            try Task.checkCancellation()
            return values
        } onCancel: {
            Task { @MainActor [search] in search.cancel() }
        }
    }
}

/// Apple Maps' completer is built for typing: "Ly" suggests Lyon, "Tok" Tokyo,
/// where a full search would match unrelated names. One completer is reused;
/// a newer fragment supersedes the pending one.
@MainActor
final class NativeCitySuggestions: NSObject, MKLocalSearchCompleterDelegate {
    static let shared = NativeCitySuggestions()
    private let completer = MKLocalSearchCompleter()
    private var pending: (id: UUID, continuation: CheckedContinuation<Void, any Error>)?
    private var completions: [String: MKLocalSearchCompletion] = [:]

    override private init() {
        super.init()
        completer.delegate = self
        completer.resultTypes = .address
        completer.addressFilter = MKAddressFilter(including: [.locality, .administrativeArea])
        completer.region = MKCoordinateRegion(.world)
        completer.regionPriority = .default
    }

    func suggest(_ query: String) async throws -> [CitySuggestion] {
        // The completer does not call back for an unchanged fragment.
        if completer.queryFragment != query || pending != nil {
            let id = UUID()
            try await withTaskCancellationHandler {
                try await withCheckedThrowingContinuation { continuation in
                    finish(throwing: CancellationError())
                    pending = (id, continuation)
                    completer.queryFragment = query
                }
            } onCancel: {
                Task { @MainActor [weak self] in
                    guard let self, pending?.id == id else { return }
                    finish(throwing: CancellationError())
                }
            }
        }
        var suggestions: [CitySuggestion] = []
        for completion in completer.results {
            let suggestion = CitySuggestion(title: completion.title, subtitle: completion.subtitle)
            completions[suggestion.id] = completion
            suggestions.append(suggestion)
        }
        return suggestions
    }

    func resolve(_ suggestion: CitySuggestion) async throws -> [WeatherLocation] {
        guard let completion = completions[suggestion.id] else {
            return try await NativeWeatherCitySearch(query: suggestion.label).results()
        }
        let response = try await MKLocalSearch(request: MKLocalSearch.Request(completion: completion)).start()
        try Task.checkCancellation()
        return NativeWeatherCitySearch.candidates(response).map(\.0)
    }

    private func finish(throwing error: (any Error)? = nil) {
        guard let pending else { return }
        self.pending = nil
        if let error { pending.continuation.resume(throwing: error) } else { pending.continuation.resume() }
    }

    /// MapKit calls back on the main queue; results are read from the owned completer.
    nonisolated func completerDidUpdateResults(_ completer: MKLocalSearchCompleter) {
        MainActor.assumeIsolated { finish() }
    }

    nonisolated func completer(_ completer: MKLocalSearchCompleter, didFailWithError error: any Error) {
        MainActor.assumeIsolated { finish(throwing: error) }
    }
}

/// Keeps MapKit's relevance order but lists cities in the person's own region
/// first, so a worldwide search still favors the expected "Paris" or "Lyon".
enum WeatherCityRanking {
    /// MapKit returns an empty `cityWithContext` for many places outside the
    /// US (Lyon, Marseille…); those results were dropped. Fall back to the city
    /// and country names, then the item name.
    static func label(context: String?, city: String?, country: String?, name: String?) -> String? {
        func value(_ text: String?) -> String? {
            guard let text = text?.trimmingCharacters(in: .whitespacesAndNewlines), !text.isEmpty else { return nil }
            return text
        }
        if let context = value(context) { return context }
        if let city = value(city) { return value(country).map { "\(city), \($0)" } ?? city }
        return value(name)
    }

    static func preferringRegion(_ candidates: [(WeatherLocation, String?)], region: String?) -> [WeatherLocation] {
        guard let region = region?.uppercased() else { return candidates.map(\.0) }
        let local = candidates.filter { $0.1?.uppercased() == region }
        let other = candidates.filter { $0.1?.uppercased() != region }
        return (local + other).map(\.0)
    }
}
