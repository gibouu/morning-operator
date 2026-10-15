import Foundation

/// One app's Screen Time usage inside one system-reported segment (hourly on iOS).
///
/// This is the shape of `DeviceActivityData.ApplicationActivity` after the app reads it
/// with the App and Website Usage data access. It is aggregate, system-reported time:
/// no order inside the segment, no screen content and no taps.
public struct ScreenTimeUsageRow: Equatable, Sendable {
    public let segment: DateInterval
    public let appName: String
    public let bundleIdentifier: String?
    public let seconds: TimeInterval
    public let pickups: Int
    public let notifications: Int

    public init(segment: DateInterval, appName: String, bundleIdentifier: String?,
                seconds: TimeInterval, pickups: Int = 0, notifications: Int = 0) {
        self.segment = segment
        self.appName = appName
        self.bundleIdentifier = bundleIdentifier
        self.seconds = seconds
        self.pickups = pickups
        self.notifications = notifications
    }
}

/// Minutes per app for one morning window, built only from rows the system returned.
public struct ScreenTimeMorningSummary: Equatable, Sendable {
    public struct App: Equatable, Sendable, Identifiable {
        public var id: String { bundleIdentifier ?? "name:" + name }
        public let name: String
        public let bundleIdentifier: String?
        public let seconds: TimeInterval
        public let pickups: Int
        public let notifications: Int
        /// Start of the earliest segment with use. Hourly data gives a coarse order only.
        public let firstSegmentStart: Date

        /// Whole minutes, rounded to nearest; a few seconds of use shows as under a minute.
        public var roundedMinutes: Int { Int((seconds / 60).rounded()) }
    }

    public let window: DateInterval
    /// Apps sorted by time spent, longest first.
    public let apps: [App]
    public let totalSeconds: TimeInterval
    /// Earliest system-reported first pickup inside the window, if any segment returned one.
    public let firstPickup: Date?
    /// Oldest `lastUpdatedDate` among the returned results; data after it may be missing.
    public let lastUpdated: Date?
    /// True when a counted segment starts before or ends after the window, so the
    /// minutes may include use just outside it. Hourly segments cannot be split.
    public let includesTimeOutsideWindow: Bool
    /// True when no row was returned. This is "no data", never "zero use".
    public var isEmpty: Bool { apps.isEmpty }

    /// Apps ordered by the hour they were first used, then by time spent (coarse order).
    public var appsInFirstUseOrder: [App] {
        apps.sorted { lhs, rhs in
            lhs.firstSegmentStart != rhs.firstSegmentStart
                ? lhs.firstSegmentStart < rhs.firstSegmentStart
                : lhs.seconds > rhs.seconds
        }
    }

    /// Builds the summary. Rows whose segment does not overlap the window are dropped,
    /// rows for `excludingBundleIdentifiers` (MORE itself) are dropped, and the same app
    /// in the same segment returned twice (a repeated live read) counts once, using the
    /// latest row. Only time on screen makes an app appear or sets its first-use hour;
    /// notifications are added to an app that was used, never on their own.
    public static func summarize(rows: [ScreenTimeUsageRow], window: DateInterval,
                                 firstPickups: [Date] = [], lastUpdated: [Date] = [],
                                 excludingBundleIdentifiers excluded: Set<String> = []) -> ScreenTimeMorningSummary {
        var latest: [String: ScreenTimeUsageRow] = [:]
        var order: [String] = []
        for row in rows {
            let key = row.bundleIdentifier ?? "name:" + row.appName
            let rowKey = "\(key)|\(row.segment.start.timeIntervalSinceReferenceDate)|\(row.segment.end.timeIntervalSinceReferenceDate)"
            if latest.updateValue(row, forKey: rowKey) == nil { order.append(rowKey) }
        }
        let unique = order.compactMap { latest[$0] }
        var notificationsByApp: [String: Int] = [:]
        var byApp: [String: (name: String, bundle: String?, seconds: TimeInterval, pickups: Int, notifications: Int, first: Date)] = [:]
        var outside = false
        for row in unique {
            // A zero-length window (a morning seen only as one moment) still owns the hour holding it.
            let overlaps = window.duration > 0
                ? row.segment.end > window.start && row.segment.start < window.end
                : row.segment.start <= window.start && window.start < row.segment.end
            guard overlaps else { continue }
            if let bundle = row.bundleIdentifier, excluded.contains(bundle) { continue }
            let key = row.bundleIdentifier ?? "name:" + row.appName
            notificationsByApp[key, default: 0] += max(0, row.notifications)
            guard row.seconds > 0 else { continue }
            if row.segment.start < window.start || row.segment.end > window.end { outside = true }
            if var current = byApp[key] {
                current.seconds += row.seconds
                current.pickups += max(0, row.pickups)
                current.first = min(current.first, row.segment.start)
                byApp[key] = current
            } else {
                byApp[key] = (row.appName, row.bundleIdentifier, row.seconds, max(0, row.pickups), 0, row.segment.start)
            }
        }
        let apps = byApp
            .map { key, value in
                App(name: value.name, bundleIdentifier: value.bundle, seconds: value.seconds, pickups: value.pickups,
                    notifications: notificationsByApp[key] ?? 0, firstSegmentStart: value.first) }
            .sorted { $0.seconds != $1.seconds ? $0.seconds > $1.seconds : $0.name < $1.name }
        return ScreenTimeMorningSummary(
            window: window, apps: apps, totalSeconds: apps.reduce(0) { $0 + $1.seconds },
            firstPickup: firstPickups.filter { window.contains($0) }.min(),
            lastUpdated: lastUpdated.min(), includesTimeOutsideWindow: outside)
    }

    /// The morning window on `day`'s local date, from `startHour` to `endHour`, cut at `now`.
    /// Returns nil when the window has not started yet or the hours are invalid.
    public static func morningWindow(on day: Date, startHour: Int = 5, endHour: Int = 11,
                                     now: Date = .now, calendar: Calendar = .current) -> DateInterval? {
        guard (0...23).contains(startHour), (1...24).contains(endHour), startHour < endHour else { return nil }
        let midnight = calendar.startOfDay(for: day)
        // Wall-clock hours, so a daylight-saving morning keeps 05:00–11:00 local.
        guard let start = calendar.date(bySettingHour: startHour, minute: 0, second: 0, of: midnight),
              let end = endHour == 24
                ? calendar.date(byAdding: .day, value: 1, to: midnight)
                : calendar.date(bySettingHour: endHour, minute: 0, second: 0, of: midnight) else { return nil }
        let cut = min(end, now)
        guard cut > start else { return nil }
        return DateInterval(start: start, end: cut)
    }
}
