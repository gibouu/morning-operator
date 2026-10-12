import Foundation
import Testing
import WeatherKit
@testable import MorningApple

@Suite("Weather observation adapter — offline providers only")
@MainActor
struct WeatherObservationServiceTests {
    @Test func constructionDoesNotRequestWeatherOrCitySearch() async throws {
        var weatherCalls = 0
        var searchCalls = 0
        let location = try place()
        let expected = try snapshot(location: location)
        let service = WeatherObservationService(weatherProvider: { requested in
            weatherCalls += 1
            #expect(requested == location)
            return expected
        }, citySearchProvider: { _ in searchCalls += 1; return [] })
        #expect(weatherCalls == 0 && searchCalls == 0)
        #expect(try await service.currentWeather(for: location) == expected)
        #expect(weatherCalls == 1 && searchCalls == 0)
        #expect(expected.temperatureCelsius == 12.5)
        #expect(expected.observationAt != expected.retrievedAt, "Retrieval must not replace the source conditions time.")
        #expect(expected.expiresAt == Date(timeIntervalSince1970: 1_800_001_000))
    }

    @Test func restoredLocationValidationRejectsInvalidCoordinatesAndLabel() throws {
        #expect(throws: WeatherObservationError.invalidLocation) {
            try WeatherLocation(latitude: .nan, longitude: 0, displayName: "Synthetic city")
        }
        #expect(throws: WeatherObservationError.invalidLocation) {
            try WeatherLocation(latitude: 91, longitude: 0, displayName: "Synthetic city")
        }
        let malformed = Data(#"{"latitude":0,"longitude":181,"displayName":"Synthetic city"}"#.utf8)
        #expect(throws: WeatherObservationError.invalidLocation) { try JSONDecoder().decode(WeatherLocation.self, from: malformed) }
        let injected = Data(#"{"latitude":0,"longitude":0,"displayName":"City\nOther text"}"#.utf8)
        #expect(throws: WeatherObservationError.invalidLocation) { try JSONDecoder().decode(WeatherLocation.self, from: injected) }
        let valid = try place()
        #expect(try JSONDecoder().decode(WeatherLocation.self, from: JSONEncoder().encode(valid)) == valid)
    }

    @Test func conditionsCannotSucceedWithoutValidRequiredAttribution() async throws {
        #expect(throws: WeatherObservationError.attributionUnavailable) {
            try WeatherAttributionInfo(legalURL: URL(string: "file:///tmp/unrelated")!,
                combinedMarkLightURL: URL(string: "https://example.invalid/light.svg")!,
                combinedMarkDarkURL: URL(string: "https://example.invalid/dark.svg")!, serviceName: "Synthetic provider")
        }
        let service = WeatherObservationService(weatherProvider: { _ in
            throw WeatherObservationError.attributionUnavailable
        }, citySearchProvider: { _ in [] })
        let location = try place()
        await #expect(throws: WeatherObservationError.attributionUnavailable) { try await service.currentWeather(for: location) }
    }

    @Test func differentLocationResponseIsRejectedInsteadOfRelabeled() async throws {
        let requested = try place()
        let different = try WeatherLocation(latitude: 20, longitude: 30, displayName: "Other synthetic city")
        let result = try snapshot(location: different)
        let service = WeatherObservationService(weatherProvider: { _ in result }, citySearchProvider: { _ in [] })
        await #expect(throws: WeatherObservationError.invalidResponse) { try await service.currentWeather(for: requested) }
    }

    @Test func setupNetworkAndUnknownFailuresStayDistinctWithoutRawErrorText() async throws {
        let location = try place()
        let denied = WeatherObservationService(weatherProvider: { _ in throw WeatherError.permissionDenied }, citySearchProvider: { _ in [] })
        await #expect(throws: WeatherObservationError.permissionDenied) { try await denied.currentWeather(for: location) }
        let offline = WeatherObservationService(weatherProvider: { _ in throw URLError(.notConnectedToInternet) }, citySearchProvider: { _ in [] })
        await #expect(throws: WeatherObservationError.networkUnavailable) { try await offline.currentWeather(for: location) }
        let unknown = WeatherObservationService(weatherProvider: { _ in
            throw NSError(domain: "Synthetic.UnspecifiedFailure", code: 9,
                          userInfo: [NSLocalizedDescriptionKey: "PRIVATE_FIXTURE_ERROR_MUST_NOT_ESCAPE"])
        }, citySearchProvider: { _ in [] })
        await #expect(throws: WeatherObservationError.serviceUnavailable) { try await unknown.currentWeather(for: location) }
        #expect(!WeatherObservationError.serviceUnavailable.localizedDescription.contains("PRIVATE_FIXTURE_ERROR"))
    }

    @Test func citySearchIsExplicitTrimmedDeduplicatedAndBounded() async throws {
        var queries: [String] = []
        var cities: [WeatherLocation] = []
        for index in 0..<12 { cities.append(try WeatherLocation(latitude: Double(index), longitude: 0, displayName: "Synthetic city \(index)")) }
        let results = [cities[0]] + cities
        let service = WeatherObservationService(weatherProvider: { _ in throw WeatherObservationError.serviceUnavailable },
            citySearchProvider: { query in queries.append(query); return results })
        #expect(queries.isEmpty)
        await #expect(throws: WeatherObservationError.invalidSearchQuery) { try await service.searchCities("  ") }
        #expect(queries.isEmpty, "Invalid input must not contact a provider.")
        let found = try await service.searchCities("  Synthetic city  ")
        #expect(queries == ["Synthetic city"])
        #expect(found.count == 8 && found == Array(cities.prefix(8)))
        let empty = WeatherObservationService(weatherProvider: { _ in throw WeatherObservationError.serviceUnavailable }, citySearchProvider: { _ in [] })
        #expect(try await empty.searchCities("Unknown synthetic place").isEmpty, "No results must not invent a default city.")
    }

    @Test func citySearchRanksTheDeviceRegionFirstWithoutDroppingOtherCountries() throws {
        let texas = try WeatherLocation(latitude: 33.66, longitude: -95.56, displayName: "Paris, TX, United States")
        let france = try WeatherLocation(latitude: 48.86, longitude: 2.35, displayName: "Paris, France")
        let ontario = try WeatherLocation(latitude: 43.2, longitude: -80.38, displayName: "Paris, ON, Canada")
        let unknown = try WeatherLocation(latitude: 1, longitude: 1, displayName: "Synthetic place")
        let candidates: [(WeatherLocation, String?)] = [(texas, "US"), (france, "FR"), (ontario, "CA"), (unknown, nil)]
        #expect(WeatherCityRanking.preferringRegion(candidates, region: "FR") == [france, texas, ontario, unknown])
        #expect(WeatherCityRanking.preferringRegion(candidates, region: "fr") == [france, texas, ontario, unknown])
        #expect(WeatherCityRanking.preferringRegion(candidates, region: nil) == [texas, france, ontario, unknown],
            "Without a device region, MapKit's relevance order is kept.")
        #expect(WeatherCityRanking.preferringRegion(candidates, region: "JP") == [texas, france, ontario, unknown])
    }

    @Test func cityLabelFallsBackWhenMapKitContextIsEmpty() {
        #expect(WeatherCityRanking.label(context: "New York, NY, United States", city: "New York", country: "United States", name: "New York")
            == "New York, NY, United States")
        #expect(WeatherCityRanking.label(context: "", city: "Lyon", country: "France", name: "Lyon") == "Lyon, France",
            "MapKit returns an empty context for Lyon; the city must not be dropped.")
        #expect(WeatherCityRanking.label(context: " ", city: "Lille", country: nil, name: "Lille") == "Lille")
        #expect(WeatherCityRanking.label(context: nil, city: nil, country: "France", name: "Marseille") == "Marseille")
        #expect(WeatherCityRanking.label(context: "", city: "", country: "", name: "") == nil)
    }

    @Test func typedSuggestionsAreTrimmedDeduplicatedAndResolvedOnlyWhenChosen() async throws {
        let lyon = try WeatherLocation(latitude: 45.76, longitude: 4.83, displayName: "Lyon, France")
        var fragments: [String] = []
        var resolved: [CitySuggestion] = []
        let suggestion = CitySuggestion(title: "Lyon", subtitle: "France")
        let service = WeatherObservationService(weatherProvider: { _ in throw WeatherObservationError.serviceUnavailable },
            citySearchProvider: { _ in [] },
            citySuggestionProvider: { fragment in fragments.append(fragment); return [suggestion, suggestion, CitySuggestion(title: "", subtitle: "x")] },
            citySuggestionResolver: { chosen in resolved.append(chosen); return [lyon] })
        await #expect(throws: WeatherObservationError.invalidSearchQuery) { try await service.suggestCities("   ") }
        #expect(try await service.suggestCities("  Ly ") == [suggestion])
        #expect(fragments == ["Ly"] && resolved.isEmpty, "Typing never resolves coordinates.")
        #expect(suggestion.label == "Lyon, France")
        #expect(try await service.resolveCity(suggestion) == lyon)
        #expect(resolved == [suggestion])
        let fallback = WeatherObservationService(weatherProvider: { _ in throw WeatherObservationError.serviceUnavailable },
            citySearchProvider: { _ in [lyon] })
        #expect(try await fallback.suggestCities("Lyon").map(\.title) == ["Lyon, France"])
    }

    @Test func cancelledLateResponseCannotProduceWeatherAndRetryIsIndependent() async throws {
        let gate = WeatherFixtureGate()
        let location = try place()
        let result = try snapshot(location: location)
        var calls = 0
        let service = WeatherObservationService(weatherProvider: { _ in
            calls += 1
            if calls == 1 { await gate.pause() }
            return result // Deliberately ignores cancellation, like a late native callback.
        }, citySearchProvider: { _ in [] })
        let pending = Task { try await service.currentWeather(for: location) }
        await gate.waitUntilPaused()
        pending.cancel()
        gate.resume()
        await #expect(throws: CancellationError.self) { try await pending.value }
        #expect(try await service.currentWeather(for: location) == result)
        #expect(calls == 2)
    }

    @Test func snapshotRejectsNonfiniteValuesButRetainsExpiredSourceForFreshnessPolicy() throws {
        let location = try place()
        let attribution = try attribution()
        #expect(throws: WeatherObservationError.invalidResponse) {
            try WeatherObservationSnapshot(location: location, retrievedAt: .now, observationAt: .now,
                temperatureCelsius: .infinity, conditionDescription: "Synthetic", symbolName: "sun.max", attribution: attribution)
        }
        let old = Date(timeIntervalSince1970: 100)
        let expired = try WeatherObservationSnapshot(location: location, retrievedAt: Date(timeIntervalSince1970: 500),
            observationAt: old, temperatureCelsius: 4, conditionDescription: "Synthetic", symbolName: "cloud",
            attribution: attribution, expiresAt: Date(timeIntervalSince1970: 200))
        #expect(expired.observationAt == old && expired.expiresAt! < expired.retrievedAt,
                "The adapter preserves source times; it never makes stale conditions fresh.")
    }

    private func place() throws -> WeatherLocation {
        try WeatherLocation(latitude: 10, longitude: 20, displayName: "Synthetic test city")
    }
    private func attribution() throws -> WeatherAttributionInfo {
        try WeatherAttributionInfo(legalURL: URL(string: "https://example.invalid/weather/legal")!,
            combinedMarkLightURL: URL(string: "https://example.invalid/weather/light.svg")!,
            combinedMarkDarkURL: URL(string: "https://example.invalid/weather/dark.svg")!, serviceName: "Synthetic provider")
    }
    private func snapshot(location: WeatherLocation) throws -> WeatherObservationSnapshot {
        try WeatherObservationSnapshot(location: location, retrievedAt: Date(timeIntervalSince1970: 1_800_000_100),
            observationAt: Date(timeIntervalSince1970: 1_800_000_000), temperatureCelsius: 12.5,
            conditionDescription: "Synthetic clouds", symbolName: "cloud", attribution: attribution(),
            expiresAt: Date(timeIntervalSince1970: 1_800_001_000))
    }
}

@MainActor
private final class WeatherFixtureGate {
    private var continuation: CheckedContinuation<Void, Never>?
    private var ready: CheckedContinuation<Void, Never>?
    func pause() async {
        await withCheckedContinuation { continuation in
            self.continuation = continuation
            ready?.resume(); ready = nil
        }
    }
    func waitUntilPaused() async {
        if continuation != nil { return }
        await withCheckedContinuation { ready = $0 }
    }
    func resume() {
        let pending = continuation
        continuation = nil
        pending?.resume()
    }
}
