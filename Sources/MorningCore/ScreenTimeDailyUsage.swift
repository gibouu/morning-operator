import Foundation

/// A local date with app-use rows the system actually returned. An absent day is
/// absent, never manufactured as zero. This is app time, not every device interaction.
public struct ScreenTimeDailyUsage: Equatable, Sendable, Identifiable {
    public var id: Date { day }
    public let day: Date
    public let summary: ScreenTimeMorningSummary

    public static func summarize(hours: [ScreenTimeHour], calendar: Calendar = .current,
                                 ownBundleIdentifiers: Set<String> = []) -> [ScreenTimeDailyUsage] {
        let returnedDays = Set(hours.filter { !$0.apps.isEmpty }.map { calendar.startOfDay(for: $0.interval.start) })
        return returnedDays.sorted(by: >).compactMap { day in
            guard let end = calendar.date(byAdding: .day, value: 1, to: day) else { return nil }
            let window = DateInterval(start: day, end: end)
            let rows = hours.filter { calendar.startOfDay(for: $0.interval.start) == day }.flatMap { hour in
                hour.apps.filter { !ScreenTimeAppCatalog.isNoise($0.bundleIdentifier, ownBundleIdentifiers: ownBundleIdentifiers) }
                    .map { app in
                        ScreenTimeUsageRow(segment: hour.interval,
                            appName: ScreenTimeAppCatalog.entry(for: app.bundleIdentifier, categoryName: app.categoryName).name,
                            bundleIdentifier: app.bundleIdentifier, seconds: app.seconds, pickups: app.pickups)
                    }
            }
            let summary = ScreenTimeMorningSummary.summarize(rows: rows, window: window,
                firstPickups: hours.compactMap(\.firstPickup), excludingBundleIdentifiers: ownBundleIdentifiers)
            guard !summary.isEmpty else { return nil }
            return ScreenTimeDailyUsage(day: day, summary: summary)
        }
    }
}
