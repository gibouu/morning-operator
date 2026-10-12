#if DEBUG
import Foundation
import MorningApple

/// Explicit UI-test injection only. Never used as a fallback for an unavailable source.
@MainActor
enum MorningBriefingFixture {
    static let calendarID = "synthetic-day-calendar"
    static let cityName = "Synthetic City"
    static let marker = "Synthetic briefing test — no Calendar, Maps or Weather requests"

    static func isEnabled(arguments: [String] = ProcessInfo.processInfo.arguments) -> Bool {
        arguments.contains("--ui-testing") && arguments.contains("--ui-testing-briefing-fixture") &&
            workspaceID(arguments: arguments) != nil
    }

    static func makeController(directory: URL, arguments: [String] = ProcessInfo.processInfo.arguments) -> MorningBriefingController? {
        guard isEnabled(arguments: arguments), let workspaceID = workspaceID(arguments: arguments) else { return nil }
        let expectedDirectory = FileManager.default.temporaryDirectory
            .appendingPathComponent("MorningOperatorUITests-\(workspaceID.uuidString)", isDirectory: true)
        guard directory.standardizedFileURL.resolvingSymlinksInPath() == expectedDirectory.standardizedFileURL.resolvingSymlinksInPath() else {
            return nil
        }
        let source = SyntheticBriefingCalendar()
        let calendar = CalendarObservationService(provider: source)
        let weather = WeatherObservationService(weatherProvider: { location in
            let now = Date()
            // The DEBUG UI must display the synthetic service label without fetching these URLs.
            let attribution = try WeatherAttributionInfo(
                legalURL: URL(string: "https://example.invalid/synthetic-weather/legal")!,
                combinedMarkLightURL: URL(string: "https://example.invalid/synthetic-weather/light")!,
                combinedMarkDarkURL: URL(string: "https://example.invalid/synthetic-weather/dark")!,
                serviceName: "Synthetic Weather")
            return try WeatherObservationSnapshot(location: location, retrievedAt: now, observationAt: now,
                temperatureCelsius: 18, conditionDescription: "Synthetic clear skies", symbolName: "sun.max",
                attribution: attribution, expiresAt: now.addingTimeInterval(1_800))
        }, citySearchProvider: { query in
            guard !query.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return [] }
            return [try WeatherLocation(latitude: 48, longitude: 2, displayName: cityName)]
        })
        return MorningBriefingController(directory: directory, calendar: calendar, weather: weather,
            localeIdentifier: "en_US")
    }

    private static func workspaceID(arguments: [String]) -> UUID? {
        let prefix = "--ui-testing-workspace="
        return arguments.first { $0.hasPrefix(prefix) }
            .flatMap { UUID(uuidString: String($0.dropFirst(prefix.count))) }
    }
}

@MainActor
private final class SyntheticBriefingCalendar: CalendarObservationProviding {
    var isAuthorized: Bool { true }
    func requestAccess() async throws -> Bool { true }
    func calendarChoices() throws -> [CalendarChoice] {
        [CalendarChoice(id: MorningBriefingFixture.calendarID, title: "Synthetic calendar", sourceTitle: "Synthetic Calendar source")]
    }
    func events(in interval: DateInterval, calendarIDs: Set<String>) throws -> [CalendarObservationEvent] {
        guard calendarIDs == [MorningBriefingFixture.calendarID] else {
            throw CalendarObservationError.selectedCalendarsUnavailable
        }
        return [CalendarObservationEvent(id: "synthetic-day-event", calendarID: MorningBriefingFixture.calendarID,
            title: "Synthetic quiet reading", start: interval.start, end: interval.end, isAllDay: true)]
    }
}
#endif
