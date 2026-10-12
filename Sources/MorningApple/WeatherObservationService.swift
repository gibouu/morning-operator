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
        case .invalidLocation: String(localized: "Choose a valid city for the weather.", bundle: .module)
        case .invalidSearchQuery: String(localized: "Enter a city name of up to 200 characters.", bundle: .module)
        case .permissionDenied: String(localized: "Apple Weather denied access. This build's WeatherKit capability and developer setup need checking.", bundle: .module)
        case .networkUnavailable: String(localized: "Weather couldn't connect to Apple. Try again when a connection is available.", bundle: .module)
        case .serviceUnavailable: String(localized: "Apple Weather is unavailable right now. Your morning can continue without it.", bundle: .module)
        case .searchUnavailable: String(localized: "Apple Maps couldn't search for cities right now. Try again later.", bundle: .module)
        case .attributionUnavailable: String(localized: "Apple Weather's required source information couldn't be loaded. Try refreshing the weather.", bundle: .module)
        case .invalidResponse: String(localized: "Apple Weather returned incomplete current conditions. Try refreshing the weather.", bundle: .module)
        }
    }
}

/// No work is performed by initialization. Search/refresh only when explicitly
/// requested by the app; there is no location manager, automatic refresh, cache,
/// telemetry, cloud-model fallback, or dependency on calendar availability.
@MainActor
public final class WeatherObservationService {
    public typealias WeatherProvider = @MainActor (WeatherLocation) async throws -> WeatherObservationSnapshot
    public typealias CitySearchProvider = @MainActor (String) async throws -> [WeatherLocation]
    private let weatherProvider: WeatherProvider
    private let citySearchProvider: CitySearchProvider

    public convenience init() {
        self.init(weatherProvider: Self.nativeWeather, citySearchProvider: Self.nativeCitySearch)
    }

    /// Inject providers for deterministic tests; construction never calls them.
    public init(weatherProvider: @escaping WeatherProvider, citySearchProvider: @escaping CitySearchProvider) {
        self.weatherProvider = weatherProvider
        self.citySearchProvider = citySearchProvider
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
private final class NativeWeatherCitySearch {
    private let search: MKLocalSearch

    init(query: String) {
        let request = MKLocalSearch.Request()
        request.naturalLanguageQuery = query
        request.resultTypes = .address
        request.addressFilter = MKAddressFilter(including: .locality)
        search = MKLocalSearch(request: request)
    }

    func results() async throws -> [WeatherLocation] {
        try await withTaskCancellationHandler {
            try Task.checkCancellation()
            let values: [WeatherLocation] = try await withCheckedThrowingContinuation { continuation in
                search.start { response, error in
                    if let error { continuation.resume(throwing: error); return }
                    guard let response else {
                        continuation.resume(throwing: WeatherObservationError.searchUnavailable); return
                    }
                    let values = response.mapItems.compactMap { item -> WeatherLocation? in
                        let coordinate = item.location.coordinate
                        guard let label = item.addressRepresentations?.cityWithContext(.full) ?? item.name else { return nil }
                        return try? WeatherLocation(latitude: coordinate.latitude, longitude: coordinate.longitude, displayName: label)
                    }
                    continuation.resume(returning: values)
                }
            }
            try Task.checkCancellation()
            return values
        } onCancel: {
            Task { @MainActor [self] in search.cancel() }
        }
    }
}
