import Foundation

/// One app inside one hourly Screen Time segment, as the system reported it.
public struct ScreenTimeAppHour: Equatable, Sendable {
    public let bundleIdentifier: String
    public let seconds: TimeInterval
    /// Pickups that went straight into this app.
    public let pickups: Int
    /// Screen Time's localized category name, when the row carried one.
    public let categoryName: String?

    public init(bundleIdentifier: String, seconds: TimeInterval, pickups: Int = 0, categoryName: String? = nil) {
        self.bundleIdentifier = bundleIdentifier
        self.seconds = seconds
        self.pickups = pickups
        self.categoryName = categoryName
    }
}

/// One hourly segment: the finest grain the API offers. Hours without use are not returned.
public struct ScreenTimeHour: Equatable, Sendable {
    public let interval: DateInterval
    public let firstPickup: Date?
    public let longestActivity: DateInterval?
    public let apps: [ScreenTimeAppHour]

    public init(interval: DateInterval, firstPickup: Date? = nil, longestActivity: DateInterval? = nil, apps: [ScreenTimeAppHour]) {
        self.interval = interval
        self.firstPickup = firstPickup
        self.longestActivity = longestActivity
        self.apps = apps
    }
}

/// One morning found in Screen Time data, with the minutes each app took inside it.
public struct ScreenTimeMorning: Equatable, Sendable {
    public struct AppUse: Equatable, Sendable {
        public let bundleIdentifier: String
        public let seconds: TimeInterval
        /// False when an hour only partly inside the morning contributed: its minutes were
        /// shared out in proportion and may include use just after the morning.
        public let secondsMeasured: Bool
        /// Whole hours between the morning's first hour and the first hour this app was used.
        public let firstHourIndex: Int
        /// True for the app the first hour's pickups point to (opened straight from the Lock Screen).
        public let isFirstPickupApp: Bool
        public let categoryName: String?
    }

    public let start: Date
    public let end: Date
    public let endReason: DetectedMorning.EndReason
    public let timeZone: TimeZone
    /// In likely order: the first-pickup app, then by hour of first use, then by minutes.
    public let apps: [AppUse]

    /// Local minutes after midnight of the start, in the morning's own time zone.
    public var startMinuteOfDay: Int {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = timeZone
        let parts = calendar.dateComponents([.hour, .minute], from: start)
        return (parts.hour ?? 0) * 60 + (parts.minute ?? 0)
    }
}

/// What one read of Screen Time produced.
public struct ScreenTimeLearning: Equatable, Sendable {
    public let mornings: [ScreenTimeMorning]
    /// Start of the earliest hour the API returned, nil when it returned nothing.
    public let earliestData: Date?
    /// Local days from the earliest returned hour to `now`, both included: how far back the data went.
    public let daysOfData: Int
    /// Local days whose morning could not be found (no use, or no 3-hour gap before it on record).
    public let daysWithoutMorning: Int
}

/// A saved day of system-returned hourly aggregates. A missing detected window
/// keeps the day unknown; it does not turn all-day use into a morning routine.
public struct ScreenTimeObservationEvidence: Codable, Equatable, Sendable {
    public struct App: Codable, Equatable, Sendable {
        public let bundleIdentifier: String
        /// Presentation only, retained in the source's language. Identity always
        /// comes from the exact bundle identifier, never from this name.
        public let displayName: String
        public let seconds: TimeInterval
        public let secondsMeasured: Bool
        public let firstHourIndex: Int
        public init(bundleIdentifier: String, displayName: String? = nil, seconds: TimeInterval, secondsMeasured: Bool, firstHourIndex: Int) {
            self.bundleIdentifier = bundleIdentifier; self.seconds = seconds
            self.displayName = displayName ?? ScreenTimeAppCatalog.entry(for: bundleIdentifier).name
            self.secondsMeasured = secondsMeasured; self.firstHourIndex = firstHourIndex
        }
    }
    public let day: Date
    public let timeZoneIdentifier: String
    public let requestedWindow: DateInterval
    public let retrievedAt: Date
    public let returnedIntervals: [DateInterval]
    public let morningWindow: DateInterval?
    public let apps: [App]
    public var sourceKey: String { "this-iPhone|\(timeZoneIdentifier)|\(day.timeIntervalSince1970)" }
    public var hasMorningEvidence: Bool { morningWindow != nil && !apps.isEmpty }

    public init(day: Date, timeZoneIdentifier: String, requestedWindow: DateInterval, retrievedAt: Date,
                returnedIntervals: [DateInterval], morningWindow: DateInterval?, apps: [App]) throws {
        self.day = day; self.timeZoneIdentifier = timeZoneIdentifier; self.requestedWindow = requestedWindow
        self.retrievedAt = retrievedAt; self.returnedIntervals = returnedIntervals
        self.morningWindow = morningWindow; self.apps = apps
        try validate()
    }

    public func validate() throws {
        guard let zone = TimeZone(identifier: timeZoneIdentifier), day.timeIntervalSince1970.isFinite,
              retrievedAt.timeIntervalSince1970.isFinite, requestedWindow.start.timeIntervalSince1970.isFinite,
              requestedWindow.duration > 0, requestedWindow.duration <= 9 * 86_400,
              requestedWindow.end <= retrievedAt, (1...26).contains(returnedIntervals.count), apps.count <= 128,
              Set(apps.map(\.bundleIdentifier)).count == apps.count else { throw ScreenTimeObservationError.invalidEvidence }
        var calendar = Calendar(identifier: .gregorian); calendar.timeZone = zone
        guard let localDay = calendar.dateInterval(of: .day, for: day), localDay.start == day,
              localDay.end > requestedWindow.start, localDay.start < requestedWindow.end,
              returnedIntervals.allSatisfy({ interval in
                  interval.start.timeIntervalSince1970.isFinite && interval.duration > 0 && interval.duration <= 3_600 &&
                  interval.start >= max(localDay.start, requestedWindow.start) && interval.end <= min(localDay.end, requestedWindow.end)
              }) else { throw ScreenTimeObservationError.invalidEvidence }
        guard zip(returnedIntervals, returnedIntervals.dropFirst()).allSatisfy({ $0.end <= $1.start }) else {
            throw ScreenTimeObservationError.invalidEvidence
        }
        if let morningWindow {
            guard !returnedIntervals.isEmpty, morningWindow.duration > 0, morningWindow.start >= max(localDay.start, requestedWindow.start),
                  morningWindow.end <= min(localDay.end, requestedWindow.end),
                  apps.allSatisfy({ app in
                      !app.bundleIdentifier.isEmpty && app.bundleIdentifier.count <= 255 &&
                      !app.displayName.isEmpty && app.displayName.count <= 60 && !app.displayName.contains(where: \.isNewline) &&
                      app.bundleIdentifier.allSatisfy({ $0.isASCII && ($0.isLetter || $0.isNumber || ".-_".contains($0)) }) &&
                      app.seconds.isFinite && app.seconds > 0 && app.seconds <= morningWindow.duration &&
                      (0...25).contains(app.firstHourIndex)
                  }) else { throw ScreenTimeObservationError.invalidEvidence }
        } else if !apps.isEmpty { throw ScreenTimeObservationError.invalidEvidence }
    }

    public static func make(hours: [ScreenTimeHour], queryStart: Date, now: Date, calendar: Calendar,
                            ownBundleIdentifiers: Set<String> = []) throws -> [Self] {
        guard hours.count <= 208, queryStart.timeIntervalSince1970.isFinite, now.timeIntervalSince1970.isFinite,
              queryStart < now, now.timeIntervalSince(queryStart) <= 9 * 86_400,
              hours.allSatisfy({ hour in
                  hour.interval.start.timeIntervalSince1970.isFinite && hour.interval.duration > 0 &&
                  hour.interval.duration <= 3_600 && hour.apps.count <= 128 && hour.apps.allSatisfy {
                      $0.seconds.isFinite && $0.seconds >= 0 && $0.seconds <= hour.interval.duration && $0.pickups >= 0
                  }
              }) else {
            throw ScreenTimeObservationError.invalidEvidence
        }
        let relevant = hours.filter { $0.interval.end > queryStart && $0.interval.start < now }
        let learning = ScreenTimeMorningLearner.learn(hours: relevant, queryStart: queryStart, now: now,
            calendar: calendar, ownBundleIdentifiers: ownBundleIdentifiers)
        // Only dates with an actually returned interval become saved sources.
        // Requested but unanswered days are unknown, not new observations.
        var days = Set<Date>()
        for hour in relevant {
            var day = calendar.startOfDay(for: max(queryStart, hour.interval.start))
            let stop = min(now, hour.interval.end)
            while day < stop {
                days.insert(day)
                guard let following = calendar.date(byAdding: .day, value: 1, to: day), following > day else {
                    throw ScreenTimeObservationError.invalidEvidence
                }
                day = following
            }
        }
        return try days.sorted().map { day in
            let end = calendar.date(byAdding: .day, value: 1, to: day)!
            let intervals = relevant.compactMap { hour -> DateInterval? in
                    let start = max(day, queryStart, hour.interval.start), stop = min(end, now, hour.interval.end)
                    return stop > start ? DateInterval(start: start, end: stop) : nil
                }
                .reduce(into: [DateInterval]()) { if !$0.contains($1) { $0.append($1) } }
                .sorted { $0.start < $1.start }
            let morning = learning.mornings.first { calendar.isDate($0.start, inSameDayAs: day) }
            let window = morning.flatMap { value -> DateInterval? in
                guard value.end > value.start, value.start >= queryStart, value.end <= now,
                      value.end <= end else { return nil }
                return DateInterval(start: value.start, end: value.end)
            }
            let apps = window == nil ? [] : (morning?.apps ?? []).map {
                App(bundleIdentifier: $0.bundleIdentifier, seconds: $0.seconds,
                    secondsMeasured: $0.secondsMeasured, firstHourIndex: $0.firstHourIndex)
            }
            return try Self(day: day, timeZoneIdentifier: calendar.timeZone.identifier,
                requestedWindow: DateInterval(start: queryStart, end: now), retrievedAt: now,
                returnedIntervals: intervals, morningWindow: window, apps: apps)
        }
    }

    public func appText(at index: Int, french: Bool = AppLanguage.isFrench) -> String {
        let app = apps[index], name = app.displayName
        let measure = app.secondsMeasured ? (french ? "mesurées" : "measured") : (french ? "estimées sur heures partielles" : "estimated from partial hours")
        return french ? "\(name) : \(Int(app.seconds.rounded())) s \(measure) dans la fenêtre matinale retenue. Ordre estimé ; aucun geste ni contenu établi."
            : "\(name): \(Int(app.seconds.rounded())) s \(measure) in the retained morning window. Estimated order; no gesture or content established."
    }
    public func renderedText(french: Bool = AppLanguage.isFrench) -> String {
        let interval = morningWindow.map { "\($0.start.ISO8601Format()) – \($0.end.ISO8601Format())" }
        let header = french
            ? "Screen Time — agrégats horaires renvoyés pour \(day.ISO8601Format()), \(timeZoneIdentifier). \(returnedIntervals.count) intervalles renvoyés ; aucune couverture continue n’est établie. Fenêtre du matin : \(interval ?? "inconnue"). Les périodes absentes restent inconnues."
            : "Screen Time — returned hourly aggregates for \(day.ISO8601Format()), \(timeZoneIdentifier). \(returnedIntervals.count) returned intervals; continuous coverage is not established. Morning window: \(interval ?? "unknown"). Missing periods remain unknown."
        return ([header] + apps.indices.map { appText(at: $0, french: french) }).joined(separator: "\n")
    }
    private enum CodingKeys: String, CodingKey { case day, timeZoneIdentifier, requestedWindow, retrievedAt, returnedIntervals, morningWindow, apps }
    public init(from decoder: any Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        try self.init(day: c.decode(Date.self, forKey: .day), timeZoneIdentifier: c.decode(String.self, forKey: .timeZoneIdentifier),
            requestedWindow: c.decode(DateInterval.self, forKey: .requestedWindow), retrievedAt: c.decode(Date.self, forKey: .retrievedAt),
            returnedIntervals: c.decode([DateInterval].self, forKey: .returnedIntervals), morningWindow: c.decodeIfPresent(DateInterval.self, forKey: .morningWindow),
            apps: c.decode([App].self, forKey: .apps))
    }
}

public enum ScreenTimeObservationError: Error, LocalizedError {
    case invalidEvidence
    public var errorDescription: String? { AppLanguage.isFrench ? "Les agrégats Screen Time ne peuvent pas être conservés avec une couverture vérifiable." : "The Screen Time aggregates could not be saved with verifiable coverage." }
}

public enum ScreenTimeMorningLearner {
    /// Splits hourly data into local days and finds each day's morning with the owner's rule
    /// (`MorningStartDetector`). Rows from MORE itself, test runners and system sheets are
    /// left out of both the minutes and the use evidence; a morning still running (`ongoing`)
    /// is left out because its minutes are not final.
    /// - Parameters:
    ///   - queryStart: the start of the interval that was asked for. Coverage begins at the
    ///     later of this and the earliest returned hour: before that, silence is unknown, not sleep.
    ///   - latestStartHour: a first use at or after this local hour is not a morning (a day
    ///     with no morning use would otherwise make its evening the "morning").
    public static func learn(hours rawHours: [ScreenTimeHour], queryStart: Date, now: Date,
                             calendar: Calendar = .current, ownBundleIdentifiers: Set<String> = [],
                             latestStartHour: Int = 14,
                             policy: MorningDetectionPolicy = MorningDetectionPolicy()) -> ScreenTimeLearning {
        let hours = cleaned(rawHours, ownBundleIdentifiers: ownBundleIdentifiers, now: now)
        // Coverage comes from what the API returned, even hours later filtered as noise.
        guard !hours.isEmpty, let earliest = rawHours.filter({ $0.interval.start <= now }).map(\.interval.start).min() else {
            return ScreenTimeLearning(mornings: [], earliestData: nil, daysOfData: 0, daysWithoutMorning: 0)
        }
        let coveredFrom = max(queryStart, earliest)
        var uses: [PhoneUse] = []
        for hour in hours {
            let seconds = hour.apps.reduce(0) { $0 + $1.seconds }
            uses += PhoneUse.fromScreenTimeSegment(hour: hour.interval, totalSeconds: seconds,
                firstPickup: hour.firstPickup, longestActivity: hour.longestActivity, sessionGap: policy.sessionGap)
            // All of an hour's use comes after its first pickup (or its start), so its use ends no
            // earlier than that moment plus the hour's total. Without this bound, untimed minutes
            // would vanish: a 30-minute hour would look like its 10-minute longest session,
            // inventing a sleep gap after it or a short "night check". It is added only when it
            // lies past the hour's timed evidence, and minutes it bridges stay estimated.
            if seconds > 0 {
                let from = hour.firstPickup.flatMap { hour.interval.contains($0) ? $0 : nil } ?? hour.interval.start
                let bound = min(hour.interval.end, from.addingTimeInterval(seconds))
                let hourEvidence = PhoneUse.fromScreenTimeSegment(hour: hour.interval, totalSeconds: seconds,
                    firstPickup: hour.firstPickup, longestActivity: hour.longestActivity, sessionGap: policy.sessionGap)
                if let latest = hourEvidence.map(\.interval.end).max(), bound > latest {
                    uses.append(PhoneUse(at: bound, source: .screenTimeBound))
                }
                // Without a first pickup, the hour's use must also have begun by its end minus
                // its total: the late longest session cannot be the first use.
                let startBound = max(hour.interval.start, hour.interval.end.addingTimeInterval(-seconds))
                if hour.firstPickup == nil, let earliest = hourEvidence.map(\.interval.start).min(), startBound < earliest {
                    uses.append(PhoneUse(at: startBound, source: .screenTimeBound))
                }
            }
        }
        // A night check whose hours hold more use than a check may last is not one, wherever
        // in the hour that use fell: either the session was longer, or another came too soon.
        // Use that is not one unbroken stretch has gaps, so it spans more than its total:
        // one second is added then, which matters only at exactly the maximum.
        let useInside = { (session: DateInterval) -> TimeInterval in
            let overlapping = hours.filter { $0.interval.end > session.start && $0.interval.start <= session.end }
            let total = overlapping.reduce(0) { $0 + $1.apps.reduce(0) { $0 + $1.seconds } }
            // Unbroken: each hour's use is its longest stretch, and stretches meet at the hour.
            let stretches = overlapping.map { hour in
                hour.longestActivity.flatMap { $0.duration >= hour.apps.reduce(0) { $0 + $1.seconds } ? $0 : nil }
            }
            let unbroken = !stretches.isEmpty && stretches.allSatisfy { $0 != nil }
                && zip(stretches, stretches.dropFirst()).allSatisfy { $0!.end == $1!.start }
            return unbroken ? total : total + 1
        }
        var mornings: [ScreenTimeMorning] = []
        var missing = 0
        var days = 0
        var day = calendar.startOfDay(for: earliest)
        let lastDay = calendar.startOfDay(for: now)
        while day <= lastDay, days < 60 {
            days += 1
            let result = MorningStartDetector.detect(uses: uses, on: day, coveredFrom: coveredFrom, now: now,
                                                     policy: policy, calendar: calendar, useInside: useInside)
            switch result {
            case .found(let found) where calendar.component(.hour, from: found.start) >= latestStartHour
                || calendar.startOfDay(for: found.start) != day:
                // An evening, or use at midnight that belongs to the day before: not this day's morning.
                missing += 1
            case .found(let found):
                let detected = extended(found, hours: hours, uses: uses, coveredFrom: coveredFrom, policy: policy)
                // Hourly data for the last hour is not final: a pause seen in it may not be real.
                guard detected.endReason != .ongoing, now.timeIntervalSince(detected.end) >= 3600 + policy.sessionGap else { break }
                // Minutes count as measured only up to the end that timed evidence alone proves.
                let timedOnly = uses.filter { $0.source != .screenTimeBound }
                var measuredUntil = found.start
                if case .found(let timed) = MorningStartDetector.detect(uses: timedOnly, on: day, coveredFrom: coveredFrom,
                                                                        now: now, policy: policy, calendar: calendar, useInside: useInside),
                   timed.start == found.start {
                    measuredUntil = min(timed.end, found.end)
                }
                mornings.append(morning(detected, hours: hours, calendar: calendar, measuredUntil: measuredUntil))
            case .noData, .noSleepGapCovered: missing += 1
            }
            guard let next = calendar.date(byAdding: .day, value: 1, to: day) else { break }
            day = next
        }
        return ScreenTimeLearning(mornings: mornings, earliestData: earliest, daysOfData: days, daysWithoutMorning: missing)
    }

    /// A light hour gives only its first pickup and longest session, so the rest of its use
    /// has no time. When the hour holding the end of the morning has such unplaced use, and
    /// the next use starts less than a pause after that hour ends, the pause may not be real:
    /// the morning runs on through that next session (up to the cap). Its minutes are then
    /// shared out and marked estimated, never counted as measured.
    static func extended(_ detected: DetectedMorning, hours: [ScreenTimeHour], uses: [PhoneUse],
                         coveredFrom: Date, policy: MorningDetectionPolicy) -> DetectedMorning {
        guard detected.endReason == .pause else { return detected }
        let sessions = MorningStartDetector.sessionsOf(uses, gap: policy.sessionGap, coveredFrom: coveredFrom)
        // Time the evidence itself covers, without the idle gaps merged into a session.
        let evidence = MorningStartDetector.sessionsOf(uses, gap: 0, coveredFrom: coveredFrom)
        let cap = detected.start.addingTimeInterval(policy.maximumLength)
        var end = detected.end
        var reason = DetectedMorning.EndReason.pause
        // The hour the use ends in: an end exactly on the hour belongs to the hour before.
        while let hour = hours.first(where: { $0.interval.start < end && end <= $0.interval.end }) {
            let used = hour.apps.reduce(0) { $0 + $1.seconds }
            let placed = evidence.reduce(0) { total, session in
                let lower = max(session.start, hour.interval.start), upper = min(session.end, hour.interval.end)
                return total + max(0, upper.timeIntervalSince(lower))
            }
            guard used - placed > 60,
                  let next = sessions.first(where: { $0.start > end }),
                  next.start.timeIntervalSince(hour.interval.end) < policy.sessionGap else { break }
            end = min(next.end, cap)
            if end >= cap { reason = .cap; break }
        }
        guard end != detected.end else { return detected }
        return DetectedMorning(start: detected.start, end: end, endReason: reason,
                               skippedSessions: detected.skippedSessions, usedSleepHint: detected.usedSleepHint)
    }

    /// Drops noise rows and rows without time, merges hours returned twice (a repeated live
    /// read: the later copy wins) and sorts by start. An hour left with no app keeps no
    /// pickup or longest-session evidence when all of its rows were MORE or a test runner:
    /// that use was driven by tests, not by the owner.
    static func cleaned(_ hours: [ScreenTimeHour], ownBundleIdentifiers: Set<String>, now: Date) -> [ScreenTimeHour] {
        var byStart: [Date: ScreenTimeHour] = [:]
        for hour in hours where hour.interval.start <= now && hour.interval.duration > 0 { byStart[hour.interval.start] = hour }
        return byStart.values.sorted { $0.interval.start < $1.interval.start }.compactMap { hour in
            var seen = Set<String>()
            var apps: [ScreenTimeAppHour] = []
            for app in hour.apps where app.seconds.isFinite && app.seconds > 0 {
                guard !ScreenTimeAppCatalog.isNoise(app.bundleIdentifier, ownBundleIdentifiers: ownBundleIdentifiers) else { continue }
                // One app is listed once per hour; a duplicate keeps its larger figure, never a sum.
                if seen.insert(app.bundleIdentifier).inserted { apps.append(app) }
                else if let index = apps.firstIndex(where: { $0.bundleIdentifier == app.bundleIdentifier }), apps[index].seconds < app.seconds {
                    apps[index] = app
                }
            }
            let clipped = apps.map { app in
                ScreenTimeAppHour(bundleIdentifier: app.bundleIdentifier, seconds: min(app.seconds, hour.interval.duration),
                                  pickups: max(0, app.pickups), categoryName: app.categoryName)
            }
            // System sheets (Face ID) appear alongside test-driven use too, so they do not
            // make an hour of MORE or test-runner use count as the owner's.
            let onlyOwnUse = clipped.isEmpty && hour.apps.contains {
                $0.seconds > 0 && ScreenTimeAppCatalog.isOwnOrTest($0.bundleIdentifier, ownBundleIdentifiers: ownBundleIdentifiers)
            }
            if onlyOwnUse { return nil }
            // An hour of MORE or test-runner use with under two minutes in other apps is taken
            // as a test run: its pickup and longest session may be the test's. With more real
            // use, the hour is the owner's (he may well open MORE in his morning).
            let hasOwnUse = hour.apps.contains { $0.seconds > 0 && ScreenTimeAppCatalog.isOwnOrTest($0.bundleIdentifier, ownBundleIdentifiers: ownBundleIdentifiers) }
            if hasOwnUse, clipped.reduce(0, { $0 + $1.seconds }) < 120 { return nil }
            guard !clipped.isEmpty || hour.firstPickup != nil || hour.longestActivity != nil else { return nil }
            return ScreenTimeHour(interval: hour.interval, firstPickup: hour.firstPickup, longestActivity: hour.longestActivity, apps: clipped)
        }
    }

    /// Minutes per app inside one detected morning.
    ///
    /// An hour wholly inside the morning counts in full and is measured. So is the part of the
    /// first hour before the start when that hour has a first pickup: nothing came before it.
    /// An hour that runs past the end of the morning is shared out: its apps keep at most
    /// the minutes the morning spent in that hour, in proportion, and are marked estimated.
    /// - Parameter measuredUntil: minutes after this (an end moved by `extended`) are never measured.
    static func morning(_ detected: DetectedMorning, hours: [ScreenTimeHour], calendar: Calendar,
                        measuredUntil: Date? = nil) -> ScreenTimeMorning {
        let start = detected.start, end = detected.end
        let inside = hours.filter { hour in
            end > start ? hour.interval.end > start && hour.interval.start < end
                : hour.interval.start <= start && start < hour.interval.end
        }
        guard let firstHour = inside.first else {
            return ScreenTimeMorning(start: start, end: end, endReason: detected.endReason, timeZone: calendar.timeZone, apps: [])
        }
        struct Total { var seconds: TimeInterval = 0; var measured = true; var firstHour: Date; var category: String? }
        var totals: [String: Total] = [:]
        for hour in inside {
            let leadKnown = hour.interval.start >= start || hour.firstPickup != nil
            let tailKnown = hour.interval.end <= min(end, measuredUntil ?? end)
            let overlap = max(0, min(hour.interval.end, end).timeIntervalSince(max(hour.interval.start, start)))
            let sum = hour.apps.reduce(0) { $0 + $1.seconds }
            let whole = leadKnown && tailKnown
            // A zero-length morning still owns its hour's use, estimated.
            let share = whole ? 1 : (sum > 0 ? min(1, (end > start ? overlap : hour.interval.duration) / sum) : 0)
            for app in hour.apps {
                let seconds = app.seconds * share
                guard seconds > 0 else { continue }
                var total = totals[app.bundleIdentifier] ?? Total(firstHour: hour.interval.start, category: app.categoryName)
                total.seconds += seconds
                total.measured = total.measured && whole
                total.firstHour = min(total.firstHour, hour.interval.start)
                total.category = total.category ?? app.categoryName
                totals[app.bundleIdentifier] = total
            }
        }
        // The first hour's pickups name the app opened straight from the Lock Screen.
        let firstApp = firstHour.apps.filter { $0.pickups > 0 && totals[$0.bundleIdentifier] != nil }
            .max { $0.pickups != $1.pickups ? $0.pickups < $1.pickups : $0.seconds < $1.seconds }?.bundleIdentifier
        let apps = totals.map { id, total in
            ScreenTimeMorning.AppUse(bundleIdentifier: id, seconds: total.seconds, secondsMeasured: total.measured,
                firstHourIndex: max(0, Int((total.firstHour.timeIntervalSince(firstHour.interval.start) / 3600).rounded(.down))),
                isFirstPickupApp: id == firstApp, categoryName: total.category)
        }.sorted(by: likelyOrder)
        return ScreenTimeMorning(start: start, end: end, endReason: detected.endReason, timeZone: calendar.timeZone, apps: apps)
    }

    private static func likelyOrder(_ lhs: ScreenTimeMorning.AppUse, _ rhs: ScreenTimeMorning.AppUse) -> Bool {
        if lhs.isFirstPickupApp != rhs.isFirstPickupApp { return lhs.isFirstPickupApp }
        if lhs.firstHourIndex != rhs.firstHourIndex { return lhs.firstHourIndex < rhs.firstHourIndex }
        if lhs.seconds != rhs.seconds { return lhs.seconds > rhs.seconds }
        return lhs.bundleIdentifier < rhs.bundleIdentifier
    }
}

public extension ScreenTimeAppCatalog {
    /// MORE itself (any build) or an XCTest runner: use driven by tests, never the owner's routine.
    static func isOwnOrTest(_ bundleIdentifier: String, ownBundleIdentifiers: Set<String> = []) -> Bool {
        let lower = bundleIdentifier.lowercased()
        return ownBundleIdentifiers.contains(bundleIdentifier) || lower == "com.gibouu.morningoperator"
            || lower.hasPrefix("com.gibouu.morningoperator.") || lower.hasPrefix("com.apple.test.")
            || lower.hasSuffix(".xctrunner") || lower.contains("xctest")
    }
}

/// A routine suggested from several mornings of Screen Time. It is saved apart from the
/// routine and changes nothing until the owner approves it; he can leave steps out and
/// change minutes first.
public struct ScreenTimeRoutineProposal: Codable, Equatable, Sendable, Identifiable {
    public static let maximumSteps = ScreenTimeRoutineSelection.maximumSuggestedApps
    public static let minutesRange = ScreenTimeRoutineSelection.plannedMinutesRange
    /// Minutes from which a social, video or game app gets a long-use budget prompt.
    /// Duration does not establish scrolling, scroll speed or what was viewed.
    public static let attentionSinkMinutes = 15

    public struct Step: Codable, Equatable, Sendable, Identifiable {
        public let id: UUID
        public let bundleIdentifier: String
        public let title: String
        public let kind: ScreenTimeAppCatalog.Kind
        /// Median minutes over the mornings the app was used.
        public let medianMinutes: Int
        public let morningsSeen: Int
        /// True when every contributing hour lay wholly inside its morning.
        public let minutesMeasured: Bool
        /// Always false today: pickups per app are counts without times, so even the first
        /// app is a likely guess. Kept so a timed source (app-transition log) can set it.
        public let orderMeasured: Bool
        /// Social, video or games with typical use of `attentionSinkMinutes` or more.
        public let isAttentionSink: Bool
        /// Owner's edits before approval.
        public var included: Bool
        public var minutes: Int
        /// A complete explicit Keep, shown in this proposal before approval.
        public fileprivate(set) var retainedStep: RoutineStep? = nil

        public var isMeasured: Bool { minutesMeasured }
        public var allowedMinutesRange: ClosedRange<Int> {
            retainedStep == nil ? ScreenTimeRoutineProposal.minutesRange : RoutineStep.durationMinutesRange
        }
        public var suggestedStep: RoutineStep {
            if var retainedStep { retainedStep.durationMinutes = minutes; return retainedStep }
            var candidate = RoutineExecutionSuggestion.applying(to: RoutineStep(id: id, title: title,
                kind: kind.stepKind, durationMinutes: minutes), bundleIdentifier: bundleIdentifier)
            if candidate.automation == nil, candidate.target == nil {
                candidate.target = ScreenTimeAppCatalog.routineTarget(for: bundleIdentifier)
            }
            return candidate
        }
        public var suggestedTarget: RoutineStepTarget? { suggestedStep.target }
        public var executionExplanation: String? {
            retainedStep == nil ? RoutineExecutionSuggestion.explanation(bundleIdentifier: bundleIdentifier) : nil
        }
    }

    public let id: UUID
    public let createdAt: Date
    /// The routine this suggestion was made against; approving needs the same one.
    public let baseRoutineID: UUID?
    public let typicalStartMinuteOfDay: Int
    public let timeZoneIdentifier: String
    /// Comparable mornings used, and all the mornings found.
    public let morningsUsed: Int
    public let morningsFound: Int
    /// How far back Screen Time returned data, in local days.
    public let daysOfData: Int
    public private(set) var steps: [Step]
    public private(set) var preferenceSnapshot: RoutinePreferenceJournal?

    /// A changed standing choice requires a fresh, visibly reviewed proposal.
    public func isCurrent(preferences: RoutinePreferenceJournal) -> Bool {
        preferenceSnapshot.map { $0 == preferences } ?? preferences.entries.isEmpty
    }

    public var includedSteps: [Step] { steps.filter(\.included) }

    /// Builds the suggestion from mornings of the same kind as `nextMorning` (weekday or
    /// weekend) when at least two exist, otherwise from all of them. Apps used on at least
    /// half of those mornings qualify after a 30-second per-window filter; their
    /// median minutes are rounded to the nearest minute.
    /// Returns nil when no morning or no app qualifies.
    public static func make(from learning: ScreenTimeLearning, nextMorning: Date, baseRoutineID: UUID?,
                            calendar: Calendar = .current, now: Date = .now) -> ScreenTimeRoutineProposal? {
        let selection = ScreenTimeRoutineSelection.from(mornings: learning.mornings, nextMorning: nextMorning, calendar: calendar)
        guard !selection.candidates.isEmpty else { return nil }
        let steps = selection.candidates.prefix(maximumSteps).map { candidate in
            let entry = ScreenTimeAppCatalog.entry(for: candidate.bundleIdentifier, categoryName: candidate.categoryName)
            return Step(id: UUID(), bundleIdentifier: candidate.bundleIdentifier, title: entry.name, kind: entry.kind,
                        medianMinutes: candidate.minutes, morningsSeen: candidate.morningsSeen,
                        minutesMeasured: candidate.minutesMeasured, orderMeasured: false,
                        isAttentionSink: entry.kind.isAttentionSink && candidate.minutes >= attentionSinkMinutes,
                        included: true, minutes: candidate.minutes)
        }
        return ScreenTimeRoutineProposal(id: UUID(), createdAt: now, baseRoutineID: baseRoutineID,
            typicalStartMinuteOfDay: selection.typicalStartMinuteOfDay,
            timeZoneIdentifier: calendar.timeZone.identifier, morningsUsed: selection.morningsUsed,
            morningsFound: selection.morningsFound, daysOfData: learning.daysOfData, steps: Array(steps))
    }

    /// Reconcile before review. Kept moments remain complete and visible; exclusions
    /// and timing choices are never applied as hidden changes at approval time.
    public mutating func applyPreferences(_ journal: RoutinePreferenceJournal) -> Bool {
        do {
            try journal.validate()
            var next: [Step] = [], matched = Set<UUID>()
            for var item in steps where !item.bundleIdentifier.isEmpty {
                item.retainedStep = nil
                if let preference = try journal.matchingPreference(for: item.suggestedStep) {
                    if preference.presence == .keep, matched.contains(preference.id) { return false }
                    matched.insert(preference.id)
                    if preference.presence == .exclude { continue }
                    if let retained = preference.retainedStep {
                        item.retainedStep = retained
                        item.minutes = preference.durationMinutes ?? retained.durationMinutes
                    } else if let minutes = preference.durationMinutes { item.minutes = minutes }
                }
                next.append(item)
            }
            for preference in journal.entries where preference.presence == .keep && !matched.contains(preference.id) {
                guard let retained = preference.retainedStep else { return false }
                var item = Step(id: retained.id, bundleIdentifier: "", title: retained.title,
                    kind: .other, medianMinutes: retained.durationMinutes, morningsSeen: 0,
                    minutesMeasured: false, orderMeasured: false, isAttentionSink: false,
                    included: true, minutes: preference.durationMinutes ?? retained.durationMinutes)
                item.retainedStep = retained
                next.append(item)
            }
            guard !next.isEmpty, next.count <= Self.maximumSteps + RoutinePreferenceJournal.maximumEntries else { return false }
            steps = next; preferenceSnapshot = journal
            return true
        } catch { return false }
    }

    public mutating func setIncluded(_ included: Bool, stepID: UUID) {
        guard let index = steps.firstIndex(where: { $0.id == stepID }) else { return }
        steps[index].included = included
    }

    public mutating func setMinutes(_ minutes: Int, stepID: UUID) {
        guard let index = steps.firstIndex(where: { $0.id == stepID }) else { return }
        let range = steps[index].allowedMinutesRange
        steps[index].minutes = min(max(minutes, range.lowerBound), range.upperBound)
    }

    /// The draft routine: exactly the included steps, in order, with the reviewed minutes.
    /// What the owner approves is what he saw; nothing is added, removed or retimed after review.
    public func draft(preserving base: RoutineVersion?, at date: Date = .now) throws -> RoutineVersion {
        let steps = includedSteps.map { step in
            var candidate = step.suggestedStep
            if step.retainedStep == nil {
                candidate.detail = Self.detail(for: step, of: morningsUsed)
                if let explanation = step.executionExplanation { candidate.detail += " " + explanation }
            }
            return candidate
        }
        guard !steps.isEmpty else { throw ScreenTimeProposalError.nothingIncluded }
        return RoutineVersion(number: base?.nextNumber ?? 1, createdAt: date,
                              sourceLabel: AppLanguage.localized("From Screen Time", bundle: .module), steps: steps)
    }

    static func detail(for step: Step, of mornings: Int) -> String {
        let usual = AppLanguage.localized("Usually \(step.medianMinutes) min, on \(step.morningsSeen) of \(mornings) mornings.", bundle: .module)
        let label = step.minutesMeasured
            ? AppLanguage.localized("Measured by Screen Time.", bundle: .module)
            : AppLanguage.localized("Estimated from hourly Screen Time.", bundle: .module)
        return usual + " " + label
    }

    /// Bounds checked when a saved suggestion is read back.
    public init(from decoder: any Decoder) throws {
        let values = try decoder.container(keyedBy: CodingKeys.self)
        id = try values.decode(UUID.self, forKey: .id)
        createdAt = try values.decode(Date.self, forKey: .createdAt)
        baseRoutineID = try values.decodeIfPresent(UUID.self, forKey: .baseRoutineID)
        typicalStartMinuteOfDay = try values.decode(Int.self, forKey: .typicalStartMinuteOfDay)
        timeZoneIdentifier = try values.decode(String.self, forKey: .timeZoneIdentifier)
        morningsUsed = try values.decode(Int.self, forKey: .morningsUsed)
        morningsFound = try values.decode(Int.self, forKey: .morningsFound)
        daysOfData = try values.decode(Int.self, forKey: .daysOfData)
        steps = try values.decode([Step].self, forKey: .steps)
        preferenceSnapshot = try values.decodeIfPresent(RoutinePreferenceJournal.self, forKey: .preferenceSnapshot)
        try preferenceSnapshot?.validate()
        guard (0..<(24 * 60)).contains(typicalStartMinuteOfDay), (1...60).contains(morningsUsed),
              (morningsUsed...60).contains(morningsFound), (0...60).contains(daysOfData),
              (1...(Self.maximumSteps + RoutinePreferenceJournal.maximumEntries)).contains(steps.count),
              steps.filter({ !$0.bundleIdentifier.isEmpty }).count <= Self.maximumSteps,
              Set(steps.map(\.id)).count == steps.count,
              Set(steps.map { $0.suggestedStep.id }).count == steps.count,
              steps.allSatisfy({ step in
                  let retained = step.retainedStep
                  let savedKeep = preferenceSnapshot?.entries.first { $0.retainedStep == retained && $0.presence == .keep }
                  return !step.title.isEmpty && step.title.count <= (retained == nil ? 120 : 2_000)
                      && step.bundleIdentifier.count <= 255 && step.allowedMinutesRange.contains(step.minutes)
                      && step.allowedMinutesRange.contains(step.medianMinutes)
                      && (retained == nil ? (1...morningsUsed).contains(step.morningsSeen) : savedKeep != nil)
                      && (!step.bundleIdentifier.isEmpty || retained != nil)
              }) else { throw ScreenTimeProposalError.invalidProposal }
    }

    private init(id: UUID, createdAt: Date, baseRoutineID: UUID?, typicalStartMinuteOfDay: Int, timeZoneIdentifier: String,
                 morningsUsed: Int, morningsFound: Int, daysOfData: Int, steps: [Step]) {
        self.id = id; self.createdAt = createdAt; self.baseRoutineID = baseRoutineID
        self.typicalStartMinuteOfDay = typicalStartMinuteOfDay; self.timeZoneIdentifier = timeZoneIdentifier
        self.morningsUsed = morningsUsed; self.morningsFound = morningsFound; self.daysOfData = daysOfData; self.steps = steps
        preferenceSnapshot = nil
    }
}

public enum ScreenTimeProposalError: Error, Equatable, Sendable {
    case nothingIncluded, invalidProposal
}

private func median(_ values: [Double]) -> Double {
    guard !values.isEmpty else { return 0 }
    let sorted = values.sorted()
    let middle = sorted.count / 2
    return sorted.count % 2 == 1 ? sorted[middle] : (sorted[middle - 1] + sorted[middle]) / 2
}
