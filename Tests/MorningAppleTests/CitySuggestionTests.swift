import Foundation
import Testing
import MorningCore
@testable import MorningApple

// The time limit and the trait are a safety net for a hang; see `BriefingHangRescueTrait`.
@Suite("City field lookups — injected sources only", .timeLimit(.minutes(1)), .endsControllerWorkOnCancellation)
@MainActor
struct CitySuggestionTests {
    @Test func failedOrTimedOutSuggestionsAreNotReportedAsNoMatch() async throws {
        let directory = temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        var answer: Result<[CitySuggestion], any Error> = .failure(URLError(.notConnectedToInternet))
        let controller = makeController(directory: directory, suggestions: { _ in try answer.get() })
        #expect(controller.citySearchOutcome == nil)
        await controller.suggestCities("To")
        #expect(controller.citySearchOutcome == .unavailable && controller.citySuggestions.isEmpty)
        answer = .success([])
        await controller.suggestCities("To")
        #expect(controller.citySearchOutcome == .noMatch)
        answer = .success([tokyo])
        await controller.suggestCities("To")
        #expect(controller.citySearchOutcome == nil && controller.citySuggestions == [tokyo])
        answer = .failure(URLError(.timedOut))
        await controller.suggestCities("Tok")
        #expect(controller.citySearchOutcome == .unavailable)
        #expect(controller.citySuggestions == [tokyo], "Earlier suggestions stay until newer ones arrive.")

        let gate = CityGate<[CitySuggestion]>()
        let clock = ManualTestClock()
        let slowDirectory = temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: slowDirectory) }
        let slow = makeController(directory: slowDirectory, suggestions: { _ in try await gate.value() }, clock: clock)
        let lookup = Task { await slow.suggestCities("To") }
        await clock.waitForSleepers()
        clock.advance(by: .seconds(10) - .milliseconds(1))
        #expect(clock.sleeperCount == 1 && slow.citySearchOutcome == nil, "The deadline fired before its time.")
        clock.advance(by: .milliseconds(1))
        await lookup.value
        #expect(gate.calls == 1 && slow.citySearchOutcome == .unavailable)
        gate.release([tokyo])
        await settle()
        #expect(slow.citySuggestions.isEmpty, "A result after the deadline has no recipient.")
    }

    @Test func olderSuggestionsCannotReplaceTheAnswerToNewerTyping() async throws {
        let directory = temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let gate = CityGate<[CitySuggestion]>()
        var fragments: [String] = []
        let controller = makeController(directory: directory, suggestions: { fragment in
            fragments.append(fragment); return try await gate.value()
        })
        controller.cityQueryChanged("P")
        await settle()
        #expect(fragments.isEmpty, "One character is not sent to Apple Maps.")
        controller.cityQueryChanged("Pa")
        await until { gate.calls == 1 }
        controller.cityQueryChanged(" Pa ")
        await settle()
        #expect(gate.calls == 1, "Surrounding spaces are not a new query.")
        controller.cityQueryChanged("To")
        await until { gate.calls == 2 }
        gate.release([paris])
        await settle()
        #expect(controller.citySuggestions.isEmpty)
        gate.release([tokyo])
        await until { !controller.citySuggestions.isEmpty }
        #expect(controller.citySuggestions == [tokyo] && fragments == ["Pa", "To"])
    }

    @Test func typingAfterChoosingACityCancelsThePendingChoice() async throws {
        let directory = temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let gate = CityGate<[WeatherLocation]>()
        let lyon = try WeatherLocation(latitude: 45.76, longitude: 4.83, displayName: "Lyon, France")
        let controller = makeController(directory: directory, suggestions: { _ in [] }, resolver: { _ in try await gate.value() })
        controller.cityQueryChanged("Ly")
        let choice = Task { await controller.chooseCity(CitySuggestion(title: "Lyon", subtitle: "France")) }
        await until { gate.calls == 1 }
        #expect(controller.isSearchingCities)
        controller.cityQueryChanged("Tok")
        #expect(!controller.isSearchingCities)
        gate.release([lyon])
        #expect(await choice.value == nil)
        #expect(controller.settings.weatherLocation == nil, "A late place must not be saved over newer typing.")

        let dismissed = Task { await controller.chooseCity(CitySuggestion(title: "Lyon", subtitle: "France")) }
        await until { gate.calls == 2 }
        controller.clearCitySearch()
        gate.release([lyon])
        #expect(await dismissed.value == nil)
        #expect(controller.settings.weatherLocation == nil, "Leaving the city field cancels the choice too.")

        let kept = Task { await controller.chooseCity(CitySuggestion(title: "Lyon", subtitle: "France")) }
        await until { gate.calls == 3 }
        gate.release([lyon])
        #expect(await kept.value == lyon)
        #expect(controller.settings.weatherLocation == lyon, "The choice is saved by the controller itself.")
        #expect(!controller.isSearchingCities && controller.citySuggestions.isEmpty)
        let reopened = makeController(directory: directory, suggestions: { _ in [] })
        #expect(reopened.settings.weatherLocation == lyon)
    }

    @Test func explicitResultsDoNotHideSuggestionsForNewerTyping() async throws {
        let directory = temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let place = try WeatherLocation(latitude: 48.86, longitude: 2.35, displayName: "Paris, France")
        let searchGate = CityGate<[WeatherLocation]>()
        var held = false
        let controller = makeController(directory: directory, suggestions: { _ in [self.tokyo] },
            search: { _ in held ? try await searchGate.value() : [place] })
        controller.cityQueryChanged("Paris")
        await controller.searchCities("Paris")
        #expect(controller.cityResults == [place])
        controller.cityQueryChanged("Tokyo")
        #expect(controller.cityResults.isEmpty)
        await until { controller.citySuggestions == [tokyo] }

        // An explicit search takes over the list, so an empty answer is shown as
        // no match instead of leaving suggestions for earlier typing.
        let pendingSuggestions = CityGate<[CitySuggestion]>()
        let missing = makeController(directory: temporaryDirectory(), suggestions: { fragment in
            fragment == "Pa" ? [self.paris] : try await pendingSuggestions.value()
        })
        missing.cityQueryChanged("Pa")
        await until { missing.citySuggestions == [paris] }
        missing.cityQueryChanged("Zzz")
        await until { pendingSuggestions.calls == 1 }
        await missing.searchCities("Zzz")
        #expect(missing.citySuggestions.isEmpty && missing.cityResults.isEmpty && missing.citySearchOutcome == .noMatch)
        missing.cityQueryChanged("Zzzz")
        #expect(missing.citySearchOutcome == nil, "A new query is not yet known to have no match.")
        await until { pendingSuggestions.calls == 2 }
        missing.clearCitySearch()
        pendingSuggestions.release([paris]); pendingSuggestions.release([paris])
        await settle()
        #expect(missing.citySuggestions.isEmpty)

        // A search still running when the text changes cannot publish either.
        held = true
        let search = Task { await controller.searchCities("Tokyo") }
        await until { searchGate.calls == 1 }
        controller.cityQueryChanged("Tokyo, J")
        #expect(!controller.isSearchingCities)
        searchGate.release([place])
        await search.value
        #expect(controller.cityResults.isEmpty)
    }

    @Test func leavingTheCityFieldCancelsLookupsAndClearsTheirState() async throws {
        let directory = temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let gate = CityGate<[CitySuggestion]>()
        let resolverGate = CityGate<[WeatherLocation]>()
        let controller = makeController(directory: directory, suggestions: { _ in try await gate.value() },
                                        resolver: { _ in try await resolverGate.value() })
        controller.cityQueryChanged("To")
        await until { gate.calls == 1 }
        gate.release([tokyo])
        await until { controller.citySuggestions == [tokyo] }

        // Dismissed while a suggestion lookup is active: its late answer is dropped.
        controller.cityQueryChanged("Tok")
        await until { gate.calls == 2 }
        controller.clearCitySearch()
        #expect(controller.citySuggestions.isEmpty && controller.citySearchOutcome == nil)
        gate.release([paris])
        await settle()
        #expect(controller.citySuggestions.isEmpty, "A reopened sheet starts without the earlier query's suggestions.")
        #expect(controller.citySearchOutcome == nil)

        // Dismissed while a choice is being resolved.
        let choice = Task { await controller.chooseCity(tokyo) }
        await until { resolverGate.calls == 1 }
        controller.clearCitySearch()
        #expect(!controller.isSearchingCities)
        resolverGate.release([try WeatherLocation(latitude: 35.68, longitude: 139.69, displayName: "Tokyo, Japan")])
        #expect(await choice.value == nil)
        #expect(controller.settings.weatherLocation == nil)

        controller.cityQueryChanged("Tok")
        await until { gate.calls == 3 }
        gate.release([tokyo])
        await until { controller.citySuggestions == [tokyo] }
    }

    /// The pause after typing and the lookup deadline are both counted on the injected clock.
    @Test func typingPauseAndLookupDeadlineFollowTheInjectedClock() async throws {
        let directory = temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let gate = CityGate<[CitySuggestion]>()
        let clock = ManualTestClock()
        var fragments: [String] = []
        let controller = makeController(directory: directory, suggestions: { fragment in
            fragments.append(fragment); return try await gate.value()
        }, delay: .milliseconds(250), clock: clock)
        controller.cityQueryChanged("Pa")
        await clock.waitForSleepers()
        clock.advance(by: .milliseconds(249))
        #expect(clock.sleeperCount == 1, "The pause ended before its time.")
        controller.cityQueryChanged("Par")
        #expect(clock.sleeperCount == 0, "Newer typing cancels the earlier pause.")
        await clock.waitForSleepers()
        clock.advance(by: .milliseconds(249))
        #expect(clock.sleeperCount == 1, "Newer typing starts its own full pause.")
        await settle()
        #expect(fragments.isEmpty, "Nothing is sent to Apple Maps during the pause.")
        clock.advance(by: .milliseconds(1))
        await until { gate.calls == 1 }
        #expect(fragments == ["Par"])

        await clock.waitForSleepers()
        clock.advance(by: .seconds(10) - .milliseconds(1))
        #expect(clock.sleeperCount == 1 && controller.citySearchOutcome == nil, "The deadline fired before its time.")
        clock.advance(by: .milliseconds(1))
        await until { controller.citySearchOutcome == .unavailable }
        gate.release([tokyo])
        await settle()
        #expect(controller.citySuggestions.isEmpty, "A result after the deadline has no recipient.")
    }

    @Test func forgettingResetsTheSuggestionSource() async throws {
        let directory = temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        var resets = 0
        let controller = makeController(directory: directory, suggestions: { _ in [self.tokyo] }, reset: { resets += 1 })
        await controller.suggestCities("To")
        #expect(controller.citySuggestions == [tokyo])
        let before = resets
        try controller.updateSettings(.init(temperatureUnit: .fahrenheit))
        #expect(resets == before, "Saving a choice is not forgetting.")
        await controller.suggestCities("To")
        controller.cancelAndClear()
        #expect(resets == before + 1)
        #expect(controller.citySuggestions.isEmpty && controller.citySearchOutcome == nil)
        controller.reloadSettings()
        #expect(resets == before + 2)
    }

    private var tokyo: CitySuggestion { CitySuggestion(title: "Tokyo", subtitle: "Japan") }
    private var paris: CitySuggestion { CitySuggestion(title: "Paris", subtitle: "France") }

    /// Every controller sleeps on a test clock. A test that does not advance it has
    /// no pause or deadline that can fire, however long the machine takes.
    private func makeController(directory: URL,
        suggestions: @escaping WeatherObservationService.CitySuggestionProvider,
        resolver: WeatherObservationService.CitySuggestionResolver? = nil,
        search: @escaping WeatherObservationService.CitySearchProvider = { _ in [] },
        reset: WeatherObservationService.CitySuggestionReset? = nil,
        delay: Duration = .zero, clock: ManualTestClock = ManualTestClock()) -> MorningBriefingController {
        MorningBriefingController(directory: directory,
            calendar: CalendarObservationService(provider: CitySuggestionCalendarFixture()),
            weather: WeatherObservationService(weatherProvider: { _ in throw WeatherObservationError.serviceUnavailable },
                citySearchProvider: search, citySuggestionProvider: suggestions,
                citySuggestionResolver: resolver, citySuggestionReset: reset),
            suggestionDelay: delay, clock: clock).watchedForHangs()
    }

    private func temporaryDirectory() -> URL {
        FileManager.default.temporaryDirectory.appendingPathComponent("CitySuggestionTests-\(UUID().uuidString)")
    }

    /// Waits for main-actor work that is already scheduled. Nothing it waits for needs
    /// real time to pass: the condition becomes true after a number of main-actor turns.
    private func until(_ condition: () -> Bool, sourceLocation: SourceLocation = #_sourceLocation) async {
        // The 30 seconds are a safety bound only. They end a wait whose condition can
        // never become true, so a real defect fails here and does not hang the suite.
        // A count of yields is not used: a busy machine can need more turns than any number.
        let deadline = ContinuousClock.now + .seconds(30)
        while !condition(), ContinuousClock.now < deadline {
            await Task.yield()
            try? await Task.sleep(for: .milliseconds(1))
        }
        #expect(condition(), sourceLocation: sourceLocation)
    }

    private func settle() async {
        for _ in 0..<100 { await Task.yield() }
    }
}

/// Holds each call until released, in order, and ignores cancellation like a
/// late native callback.
@MainActor
private final class CityGate<Value: Sendable> {
    private var waiting: [CheckedContinuation<Value, any Error>] = []
    private(set) var calls = 0
    func value() async throws -> Value {
        calls += 1
        return try await withCheckedThrowingContinuation { waiting.append($0) }
    }
    func release(_ value: Value) { waiting.removeFirst().resume(returning: value) }
}

@MainActor
private final class CitySuggestionCalendarFixture: CalendarObservationProviding {
    var isAuthorized: Bool { false }
    func requestAccess() async throws -> Bool { false }
    func calendarChoices() throws -> [CalendarChoice] { [] }
    func events(in interval: DateInterval, calendarIDs: Set<String>) throws -> [CalendarObservationEvent] { [] }
}
