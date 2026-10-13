import Foundation
import Testing
import MorningCore
@testable import MorningApple

@Suite("Briefing settings persistence and city races", .timeLimit(.minutes(1)), .endsControllerWorkOnCancellation)
@MainActor
struct MorningBriefingPersistenceRaceTests {
    /// Every choice the field-by-field check accepts, at the largest size JSON gives it: each
    /// calendar ID is 1,024 bytes that are each written as two, and each of the city name's 160
    /// characters starts with a quote before combining marks use up its byte allowance.
    @Test func everyAcceptedSettingSurvivesRelaunchAtItsLargestEncodedSize() throws {
        let directory = workspace()
        defer { try? FileManager.default.removeItem(at: directory) }
        let ids = Set((0..<MorningBriefingSettings.maximumCalendarIDs).map { index in
            (0..<7).map { index & (1 << $0) == 0 ? "\\" : "\"" }.joined()
                + String(repeating: "/", count: MorningBriefingSettings.maximumCalendarIDBytes - 7)
        })
        let label = String(repeating: "\"", count: 160)
            + String(repeating: "\u{301}", count: (WeatherLocation.maximumLabelBytes - 160) / 2)
        #expect(ids.count == 100 && ids.allSatisfy { $0.utf8.count == 1_024 })
        #expect(label.count == 160 && label.utf8.count == 131_072)
        // The longest spelling of a coordinate, and `false`, which is one byte longer than `true`.
        let city = try WeatherLocation(latitude: -1.2345678901234567e-100,
                                       longitude: -1.2345678901234567e-100, displayName: label)
        let candidate = MorningBriefingSettings(calendarIDs: ids, weatherLocation: city,
                                                temperatureUnit: .fahrenheit, includesHealth: false)
        let controller = makeController(directory: directory)
        try controller.updateSettings(candidate)
        #expect(controller.settings == candidate)

        let file = directory.appendingPathComponent("briefing-settings.json")
        let byteCount = try Data(contentsOf: file).count
        // 204,800 bytes of identifiers and 131,232 of city name, plus the rest of the document.
        #expect(byteCount > 336_032, "This is far over the 131,072 bytes an earlier build read back.")
        #expect(byteCount <= MorningBriefingSettings.maximumEncodedBytes)
        let restored = makeController(directory: directory)
        #expect(restored.settingsRecoveryError == nil,
                "A controller must read its own successful save (encoded bytes: \(byteCount)).")
        let roundTripMatches = restored.settings == candidate
        #expect(roundTripMatches, "Saved choices must survive relaunch.")
        #expect(restored.settings.weatherLocation?.displayName.utf8.elementsEqual(label.utf8) == true)
        try restored.updateSettings(.init(calendarIDs: ["synthetic-after-relaunch"]))
    }

    /// The file limit is computed from this: a quote, a backslash and a slash are the only
    /// accepted characters JSON writes longer than they are, each by one byte.
    @Test func noAcceptedCharacterIsWrittenLongerThanTwiceItsSize() throws {
        var text = String()
        for codePoint: UInt32 in 0...0x10_FFFF {
            guard let scalar = Unicode.Scalar(codePoint),
                  !CharacterSet.controlCharacters.contains(scalar) else { continue }
            text.unicodeScalars.append(scalar)
        }
        let encoded = try JSONEncoder().encode(text)
        // Two surrounding quotes, and at most one more byte for each of the three.
        #expect(encoded.count <= text.utf8.count + 5)
        #expect(try JSONDecoder().decode(String.self, from: encoded).utf8.elementsEqual(text.utf8))
    }

    @Test("Finite subnormal and extreme-exponent coordinates survive settings persistence")
    func tinyFiniteCoordinatesRoundTrip() throws {
        let directory = workspace()
        defer { try? FileManager.default.removeItem(at: directory) }
        let writer = makeController(directory: directory)
        let numbers: [Double] = [Double.leastNonzeroMagnitude, -Double.leastNonzeroMagnitude,
                                Double.leastNormalMagnitude, -Double.leastNormalMagnitude,
                                -1.0000000000000004e-308, -0.00010000000000000002,
                                89.99999999999999, -89.99999999999999]
        for (index, number) in numbers.enumerated() {
            let city = try WeatherLocation(latitude: number, longitude: number,
                                           displayName: "Synthetic exponent \(index)")
            let candidate = MorningBriefingSettings(calendarIDs: ["synthetic-\(index)"], weatherLocation: city)
            try writer.updateSettings(candidate)
            let restored = makeController(directory: directory)
            #expect(restored.settingsRecoveryError == nil)
            #expect(restored.settings == candidate)
            #expect(restored.settings.weatherLocation?.latitude.bitPattern == number.bitPattern)
            #expect(restored.settings.weatherLocation?.longitude.bitPattern == number.bitPattern)
        }
    }

    @Test func aSaveLargerThanTheFileLimitIsRefusedAndKeepsTheSavedChoices() throws {
        let directory = workspace()
        defer { try? FileManager.default.removeItem(at: directory) }
        let controller = makeController(directory: directory, settingsByteLimit: 512)
        let before = MorningBriefingSettings(calendarIDs: ["synthetic-original"], includesHealth: true)
        try controller.updateSettings(before)
        let file = directory.appendingPathComponent("briefing-settings.json")
        let beforeBytes = try Data(contentsOf: file)

        // Valid one by one, too large together for this file.
        let tooMany = MorningBriefingSettings(calendarIDs: Set((0..<20).map { "synthetic-calendar-\($0)-" + String(repeating: "x", count: 40) }))
        try tooMany.validate()
        #expect(throws: MorningBriefingControllerError.settingsTooLarge) { try controller.updateSettings(tooMany) }
        #expect(controller.settings == before)
        #expect(controller.errorMessage == MorningBriefingControllerError.settingsTooLarge.localizedDescription)
        #expect(try Data(contentsOf: file) == beforeBytes)
        #expect(try FileManager.default.contentsOfDirectory(atPath: directory.path).filter { $0.hasPrefix(".morning-save") }.isEmpty)
        let restored = makeController(directory: directory, settingsByteLimit: 512)
        #expect(restored.settingsRecoveryError == nil && restored.settings == before)
        // The refusal blocks nothing: a smaller choice is saved next.
        try controller.updateSettings(.init(calendarIDs: ["synthetic-smaller"]))
        #expect(makeController(directory: directory).settings.calendarIDs == ["synthetic-smaller"])
    }

    @Test func aSettingsFileOverTheLimitIsKeptAndReportedNotReplacedByDefaults() throws {
        let directory = workspace()
        defer { try? FileManager.default.removeItem(at: directory) }
        try makeController(directory: directory).updateSettings(.init(calendarIDs: ["synthetic-original"]))
        let file = directory.appendingPathComponent("briefing-settings.json")
        var grown = try Data(contentsOf: file)
        grown.append(Data(repeating: UInt8(ascii: " "), count: MorningBriefingSettings.maximumEncodedBytes))
        try grown.write(to: file)
        let controller = makeController(directory: directory)
        #expect(controller.settingsRecoveryError != nil)
        #expect(throws: MorningBriefingControllerError.unreadableSettings) {
            try controller.updateSettings(.init(calendarIDs: ["synthetic-replacement"]))
        }
        #expect(try Data(contentsOf: file) == grown)
    }

    @Test func aCityNameIsBoundedInBytesAsWellAsInCharacters() throws {
        // One character can carry any number of combining marks.
        let heavy = "a" + String(repeating: "\u{301}", count: 65_536)
        #expect(heavy.count == 1 && heavy.utf8.count == 131_073)
        #expect(throws: WeatherObservationError.invalidLocation) {
            try WeatherLocation(latitude: 0, longitude: 0, displayName: heavy)
        }
        let allowed = "a" + String(repeating: "\u{301}", count: 65_535)
        #expect(try WeatherLocation(latitude: 0, longitude: 0, displayName: allowed).displayName.utf8.count == 131_071)
    }

    @Test func escapedIdentifiersRoundTripAtTheExactFileLimitAndAreRefusedOneByteUnder() throws {
        let root = workspace()
        defer { try? FileManager.default.removeItem(at: root) }
        let label = String(repeating: "a", count: 160) + String(repeating: "\u{301}", count: 1_968)
        #expect(label.count == 160 && label.utf8.count == 4_096)
        let city = try WeatherLocation(latitude: -89.123456789, longitude: -179.123456789, displayName: label)
        let tokens = ["\"", "\\", "/", "\u{2028}", "\u{2029}", "🙂", "e\u{301}", "\"\\/\u{2028}\u{2029}🙂e\u{301}"]
        for (index, token) in tokens.enumerated() {
            let ids = Set((0..<100).map { number -> String in
                let prefix = "synthetic-\(number)-"
                let repeated = String(repeating: token, count: (1_024 - prefix.utf8.count) / token.utf8.count)
                let head = prefix + repeated
                return head + String(repeating: "/", count: 1_024 - head.utf8.count)
            })
            let candidate = MorningBriefingSettings(calendarIDs: ids, weatherLocation: city,
                temperatureUnit: .fahrenheit, includesHealth: true)
            let directory = root.appendingPathComponent("case-\(index)")
            try makeController(directory: directory).updateSettings(candidate)
            let data = try Data(contentsOf: directory.appendingPathComponent("briefing-settings.json"))
            if index < 3 { #expect(data.count > 131_072) }
            #expect(makeController(directory: directory).settings == candidate)
            #expect(makeController(directory: directory, settingsByteLimit: data.count).settings == candidate)
            let exact = root.appendingPathComponent("exact-\(index)")
            try makeController(directory: exact, settingsByteLimit: data.count).updateSettings(candidate)
            #expect(makeController(directory: exact, settingsByteLimit: data.count).settings == candidate)
            #expect(throws: MorningBriefingControllerError.settingsTooLarge) {
                try makeController(directory: root.appendingPathComponent("short-\(index)"),
                                   settingsByteLimit: data.count - 1).updateSettings(candidate)
            }
        }
        #expect(throws: MorningBriefingControllerError.invalidSettings) {
            try makeController(directory: root.appendingPathComponent("del")).updateSettings(.init(calendarIDs: ["id\u{7f}"]))
        }
        for invalid in [String(repeating: "a", count: 161), "city\u{7f}"] {
            #expect(throws: WeatherObservationError.invalidLocation) {
                try WeatherLocation(latitude: 0, longitude: 0, displayName: invalid)
            }
        }
        // The injected limit is clamped: it can close the file, never widen it past the public cap.
        let small = MorningBriefingSettings(calendarIDs: ["synthetic"])
        #expect(throws: MorningBriefingControllerError.settingsTooLarge) {
            try makeController(directory: root.appendingPathComponent("minimum"), settingsByteLimit: .min).updateSettings(small)
        }
        let maximum = root.appendingPathComponent("maximum")
        try makeController(directory: maximum, settingsByteLimit: .max).updateSettings(small)
        #expect(makeController(directory: maximum, settingsByteLimit: .max).settings == small)
    }

    /// A file an earlier build read back keeps loading: its limits were 131,072 bytes for the
    /// file and 160 characters, of any byte length, for the city name.
    @Test func aCityNameAnEarlierBuildKeptStillLoads() throws {
        let directory = workspace()
        defer { try? FileManager.default.removeItem(at: directory) }
        let name = "a" + String(repeating: "\u{301}", count: 60_000)
        #expect(name.count == 1 && name.utf8.count == 120_001)
        let earlier = EarlierSettings(calendarIDs: ["synthetic-calendar"],
            weatherLocation: .init(latitude: 1, longitude: 2, displayName: name),
            temperatureUnit: "celsius", includesHealth: true)
        let url = directory.appendingPathComponent("briefing-settings.json")
        try AtomicJSONFile<EarlierSettings>(url: url).save(earlier)
        let originalBytes = try Data(contentsOf: url)
        #expect(originalBytes.count < 131_072)
        let restored = makeController(directory: directory)
        #expect(try Data(contentsOf: url) == originalBytes)
        #expect(restored.settingsRecoveryError == nil)
        #expect(restored.settings.weatherLocation?.displayName.utf8.elementsEqual(name.utf8) == true)
        #expect(restored.settings.calendarIDs == earlier.calendarIDs && restored.settings.includesHealth)
        // And it can be saved again with another choice changed.
        var next = restored.settings
        next.temperatureUnit = .fahrenheit
        try restored.updateSettings(next)
        #expect(makeController(directory: directory).settings == next)
    }

    @Test func leavingDuringTypingPauseRequiresANewFullPauseOnReentry() async throws {
        let directory = workspace()
        defer { try? FileManager.default.removeItem(at: directory) }
        let clock = ManualTestClock()
        var queries: [String] = []
        let suggestion = CitySuggestion(title: "Synthetic Paris", subtitle: "France")
        let controller = makeController(directory: directory, suggestions: {
            queries.append($0); return [suggestion]
        }, delay: .milliseconds(250), clock: clock)
        controller.cityQueryChanged("Pa")
        await clock.waitForSleepers()
        clock.advance(by: .milliseconds(249))
        controller.clearCitySearch()
        #expect(clock.sleeperCount == 0)
        clock.advance(by: .seconds(30))

        controller.cityQueryChanged("Pa")
        await clock.waitForSleepers()
        clock.advance(by: .milliseconds(249))
        #expect(queries.isEmpty)
        #expect(clock.sleeperCount == 1)
        clock.advance(by: .milliseconds(1))
        try await until { controller.citySuggestions == [suggestion] }
        #expect(queries == ["Pa"])
        #expect(clock.sleeperCount == 0)
    }

    @Test func timedOutFragmentCanRetryBeforeItsOldNativeReplyArrives() async throws {
        let directory = workspace()
        defer { try? FileManager.default.removeItem(at: directory) }
        let clock = ManualTestClock()
        let gate = NumberedCallGate<[CitySuggestion]>()
        defer { gate.cancelAll() }
        let controller = makeController(directory: directory,
            suggestions: { _ in try await gate.value() }, clock: clock)
        let first = Task { await controller.suggestCities("Pa") }
        try await until { gate.calls == 1 }
        await clock.waitForSleepers()
        clock.advance(by: .seconds(10))
        await first.value
        #expect(controller.citySearchOutcome == .unavailable)

        let retry = Task { await controller.suggestCities("Pa") }
        try await until { gate.calls == 2 }
        let fresh = CitySuggestion(title: "Synthetic current answer", subtitle: "France")
        gate.release(call: 1, [fresh])
        await retry.value
        #expect(controller.citySuggestions == [fresh] && controller.citySearchOutcome == nil)
        gate.release(call: 0, [CitySuggestion(title: "Synthetic expired answer", subtitle: "France")])
        try await until { gate.returnedCalls.contains(0) }
        // Queue and await another same-query result after the expired provider has returned.
        let confirm = Task { await controller.suggestCities("Pa") }
        try await until { gate.calls == 3 }
        #expect(controller.citySuggestions == [fresh] && controller.citySearchOutcome == nil)
        gate.release(call: 2, [fresh])
        await confirm.value
        #expect(clock.sleeperCount == 0)
    }

    @Test func twoChoicesResolvingInReverseOrderSaveOnlyTheNewest() async throws {
        let directory = workspace()
        defer { try? FileManager.default.removeItem(at: directory) }
        let gate = NumberedCallGate<[WeatherLocation]>()
        defer { gate.cancelAll() }
        let controller = makeController(directory: directory, resolver: { _ in try await gate.value() })
        let old = try WeatherLocation(latitude: 48.86, longitude: 2.35, displayName: "Synthetic Paris")
        let new = try WeatherLocation(latitude: 35.68, longitude: 139.69, displayName: "Synthetic Tokyo")
        let first = Task { await controller.chooseCity(.init(title: old.displayName, subtitle: "")) }
        try await until { gate.calls == 1 }
        let second = Task { await controller.chooseCity(.init(title: new.displayName, subtitle: "")) }
        try await until { gate.calls == 2 }
        gate.release(call: 1, [new])
        #expect(await second.value == new)
        gate.release(call: 0, [old])
        #expect(await first.value == nil)
        try await until { gate.returnedCalls.count == 2 }
        #expect(controller.settings.weatherLocation == new)
        #expect(!controller.isSearchingCities)
        #expect(makeController(directory: directory).settings.weatherLocation == new)
    }

    @Test func forgottenOwnersLateCityChoiceCannotRewriteNewOwnersSettings() async throws {
        let directory = workspace()
        defer { try? FileManager.default.removeItem(at: directory) }
        let gate = NumberedCallGate<[WeatherLocation]>()
        defer { gate.cancelAll() }
        var resets = 0
        let oldOwner = makeController(directory: directory, resolver: { _ in try await gate.value() },
                                      reset: { resets += 1 })
        try oldOwner.updateSettings(.init(calendarIDs: ["synthetic-forgotten"], includesHealth: true))
        let pending = Task { await oldOwner.chooseCity(.init(title: "Synthetic forgotten city", subtitle: "")) }
        try await until { gate.calls == 1 }
        let resetCount = resets
        oldOwner.cancelAndClear()
        let control = LocalDataControl(directory: directory)
        let generation = try #require(try control.beginForget().generation)
        let file = directory.appendingPathComponent("briefing-settings.json")
        try FileManager.default.removeItem(at: file)
        try control.finishForget(expectedGeneration: generation)
        let newOwner = makeController(directory: directory)
        #expect(newOwner.settings == MorningBriefingSettings())
        let new = try WeatherLocation(latitude: 51.5, longitude: -0.1, displayName: "Synthetic new city")
        try newOwner.updateSettings(.init(weatherLocation: new))
        let saved = try Data(contentsOf: file)
        let old = try WeatherLocation(latitude: 10, longitude: 20, displayName: "Synthetic forgotten city")
        gate.release(call: 0, [old])
        #expect(await pending.value == nil)
        try await until { gate.returnedCalls.contains(0) }
        #expect(try Data(contentsOf: file) == saved)
        #expect(resets == resetCount + 1)
        oldOwner.reloadSettings()
        #expect(oldOwner.settings == newOwner.settings)
        #expect(oldOwner.cityResults.isEmpty && oldOwner.citySuggestions.isEmpty)
        #expect(oldOwner.citySearchOutcome == nil && oldOwner.prepared == nil)
        #expect(!oldOwner.isSearchingCities && !oldOwner.settings.includesHealth)
    }

    private func makeController(directory: URL,
        suggestions: @escaping WeatherObservationService.CitySuggestionProvider = { _ in [] },
        resolver: @escaping WeatherObservationService.CitySuggestionResolver = { _ in [] },
        reset: @escaping WeatherObservationService.CitySuggestionReset = {},
        delay: Duration = .zero, clock: ManualTestClock = ManualTestClock(),
        settingsByteLimit: Int = MorningBriefingSettings.maximumEncodedBytes) -> MorningBriefingController {
        MorningBriefingController(directory: directory,
            calendar: CalendarObservationService(provider: UnauthorizedCalendar()),
            weather: WeatherObservationService(weatherProvider: { _ in throw WeatherObservationError.serviceUnavailable },
                citySearchProvider: { _ in [] }, citySuggestionProvider: suggestions,
                citySuggestionResolver: resolver, citySuggestionReset: reset),
            suggestionDelay: delay, clock: clock, settingsByteLimit: settingsByteLimit).watchedForHangs()
    }

    private func workspace() -> URL {
        FileManager.default.temporaryDirectory
            .appendingPathComponent("MorningBriefingPersistenceRaceTests-\(UUID().uuidString)")
    }

    // Wall time only bounds a broken test; all behavior-driving deadlines use ManualTestClock.
    private func until(_ condition: () -> Bool, sourceLocation: SourceLocation = #_sourceLocation) async throws {
        let deadline = ContinuousClock.now + .seconds(5)
        while !condition(), ContinuousClock.now < deadline, !Task.isCancelled {
            try await Task.sleep(for: .milliseconds(1))
        }
        try #require(condition(), sourceLocation: sourceLocation)
    }
}

@MainActor
private final class NumberedCallGate<Value: Sendable> {
    private var waiting: [Int: CheckedContinuation<Value, any Error>] = [:]
    private(set) var calls = 0
    private(set) var returnedCalls = Set<Int>()
    func value() async throws -> Value {
        let call = calls
        calls += 1
        defer { returnedCalls.insert(call) }
        return try await withCheckedThrowingContinuation { waiting[call] = $0 }
    }
    func release(call: Int, _ value: Value) { waiting.removeValue(forKey: call)?.resume(returning: value) }
    func cancelAll() {
        let held = waiting.values
        waiting.removeAll()
        for continuation in held { continuation.resume(throwing: CancellationError()) }
    }
}

/// The settings document as earlier builds wrote it, without today's checks.
private struct EarlierSettings: Codable, Sendable {
    struct Location: Codable, Sendable {
        let latitude: Double
        let longitude: Double
        let displayName: String
    }
    let calendarIDs: Set<String>
    let weatherLocation: Location
    let temperatureUnit: String
    let includesHealth: Bool
}

@MainActor
private final class UnauthorizedCalendar: CalendarObservationProviding {
    var isAuthorized: Bool { false }
    func requestAccess() async throws -> Bool { false }
    func calendarChoices() throws -> [CalendarChoice] { [] }
    func events(in interval: DateInterval, calendarIDs: Set<String>) throws -> [CalendarObservationEvent] { [] }
}
