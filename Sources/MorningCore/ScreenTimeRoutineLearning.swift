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
    public static let maximumSteps = 8
    public static let minutesRange = 1...240
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

        public var isMeasured: Bool { minutesMeasured }
        public var suggestedTarget: RoutineStepTarget? { ScreenTimeAppCatalog.routineTarget(for: bundleIdentifier) }
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

    public var includedSteps: [Step] { steps.filter(\.included) }

    /// Builds the suggestion from mornings of the same kind as `nextMorning` (weekday or
    /// weekend) when at least two exist, otherwise from all of them. Apps used on at least
    /// half of those mornings are kept, with their median minutes; apps under a minute are dropped.
    /// Returns nil when no morning or no app qualifies.
    public static func make(from learning: ScreenTimeLearning, nextMorning: Date, baseRoutineID: UUID?,
                            calendar: Calendar = .current, now: Date = .now) -> ScreenTimeRoutineProposal? {
        let all = learning.mornings.filter { !$0.apps.isEmpty }
        guard !all.isEmpty else { return nil }
        let weekend = calendar.isDateInWeekend(nextMorning)
        let sameKind = all.filter { morning in
            var local = calendar
            local.timeZone = morning.timeZone
            return local.isDateInWeekend(morning.start) == weekend
        }
        let mornings = sameKind.count >= 2 ? sameKind : all
        let needed = max(1, (mornings.count + 1) / 2)

        struct Seen { var seconds: [TimeInterval] = []; var hours: [Int] = []; var first = 0; var measured = true; var category: String? }
        var seen: [String: Seen] = [:]
        for morning in mornings {
            for app in morning.apps where app.seconds >= 30 {
                var item = seen[app.bundleIdentifier] ?? Seen()
                item.seconds.append(app.seconds)
                item.hours.append(app.firstHourIndex)
                if app.isFirstPickupApp { item.first += 1 }
                item.measured = item.measured && app.secondsMeasured
                item.category = item.category ?? app.categoryName
                seen[app.bundleIdentifier] = item
            }
        }
        struct Candidate { let id: String; let minutes: Int; let hour: Double; let first: Int; let item: Seen }
        let candidates = seen.compactMap { id, item -> Candidate? in
            guard item.seconds.count >= needed else { return nil }
            let minutes = Int((median(item.seconds) / 60).rounded())
            guard minutes >= 1 else { return nil }
            return Candidate(id: id, minutes: min(minutes, minutesRange.upperBound), hour: median(item.hours.map(Double.init)), first: item.first, item: item)
        }
        guard !candidates.isEmpty else { return nil }
        // The app opened first on the most mornings leads; ties keep hourly order.
        let leader = candidates.filter { $0.first > 0 }.max { $0.first != $1.first ? $0.first < $1.first : $0.hour > $1.hour }?.id
        let ordered = candidates.sorted { lhs, rhs in
            if (lhs.id == leader) != (rhs.id == leader) { return lhs.id == leader }
            if lhs.hour != rhs.hour { return lhs.hour < rhs.hour }
            if lhs.minutes != rhs.minutes { return lhs.minutes > rhs.minutes }
            return lhs.id < rhs.id
        }.prefix(maximumSteps)
        let steps = ordered.map { candidate in
            let entry = ScreenTimeAppCatalog.entry(for: candidate.id, categoryName: candidate.item.category)
            return Step(id: UUID(), bundleIdentifier: candidate.id, title: entry.name, kind: entry.kind,
                        medianMinutes: candidate.minutes, morningsSeen: candidate.item.seconds.count,
                        minutesMeasured: candidate.item.measured,
                        orderMeasured: false,
                        isAttentionSink: entry.kind.isAttentionSink && candidate.minutes >= attentionSinkMinutes,
                        included: true, minutes: candidate.minutes)
        }
        let starts = mornings.map { Double($0.startMinuteOfDay) }
        return ScreenTimeRoutineProposal(id: UUID(), createdAt: now, baseRoutineID: baseRoutineID,
            typicalStartMinuteOfDay: Int(median(starts).rounded()) % (24 * 60),
            timeZoneIdentifier: calendar.timeZone.identifier, morningsUsed: mornings.count,
            morningsFound: all.count, daysOfData: learning.daysOfData, steps: Array(steps))
    }

    /// Applies the owner's saved choices: an app he excluded from suggestions is removed and
    /// a saved duration becomes the starting minutes. Matching is by title and kind, as the
    /// journal matches, and every step that matches gets the choice. Keep choices add nothing:
    /// the review shows only what Screen Time found. Returns false when nothing is left.
    public mutating func applyPreferences(_ journal: RoutinePreferenceJournal) -> Bool {
        for entry in journal.entries {
            let matches = { (step: Step) in
                step.kind.stepKind == entry.targetKind && preferenceTitleKey(step.title) == entry.normalizedTitle
            }
            if entry.presence == .exclude { steps.removeAll(where: matches); continue }
            guard let minutes = entry.durationMinutes else { continue }
            for index in steps.indices where matches(steps[index]) {
                steps[index].minutes = min(max(minutes, Self.minutesRange.lowerBound), Self.minutesRange.upperBound)
            }
        }
        return !steps.isEmpty
    }

    public mutating func setIncluded(_ included: Bool, stepID: UUID) {
        guard let index = steps.firstIndex(where: { $0.id == stepID }) else { return }
        steps[index].included = included
    }

    public mutating func setMinutes(_ minutes: Int, stepID: UUID) {
        guard let index = steps.firstIndex(where: { $0.id == stepID }) else { return }
        steps[index].minutes = min(max(minutes, Self.minutesRange.lowerBound), Self.minutesRange.upperBound)
    }

    /// The draft routine: exactly the included steps, in order, with the reviewed minutes.
    /// What the owner approves is what he saw; nothing is added, removed or retimed after review.
    public func draft(preserving base: RoutineVersion?, at date: Date = .now) throws -> RoutineVersion {
        let steps = includedSteps.map { step in
            RoutineStep(title: step.title, detail: Self.detail(for: step, of: morningsUsed), kind: step.kind.stepKind,
                        durationMinutes: step.minutes, target: step.suggestedTarget)
        }
        guard !steps.isEmpty else { throw ScreenTimeProposalError.nothingIncluded }
        return RoutineVersion(number: base?.nextNumber ?? 1, createdAt: date,
                              sourceLabel: String(localized: "From Screen Time", bundle: .module), steps: steps)
    }

    static func detail(for step: Step, of mornings: Int) -> String {
        let usual = String(localized: "Usually \(step.medianMinutes) min, on \(step.morningsSeen) of \(mornings) mornings.", bundle: .module)
        let label = step.minutesMeasured
            ? String(localized: "Measured by Screen Time.", bundle: .module)
            : String(localized: "Estimated from hourly Screen Time.", bundle: .module)
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
        guard (0..<(24 * 60)).contains(typicalStartMinuteOfDay), (1...60).contains(morningsUsed),
              (morningsUsed...60).contains(morningsFound), (0...60).contains(daysOfData),
              (1...Self.maximumSteps).contains(steps.count), Set(steps.map(\.id)).count == steps.count,
              steps.allSatisfy({ step in
                  !step.title.isEmpty && step.title.count <= 120 && step.bundleIdentifier.count <= 255
                      && Self.minutesRange.contains(step.minutes) && Self.minutesRange.contains(step.medianMinutes)
                      && (1...morningsUsed).contains(step.morningsSeen)
              }) else { throw ScreenTimeProposalError.invalidProposal }
    }

    private init(id: UUID, createdAt: Date, baseRoutineID: UUID?, typicalStartMinuteOfDay: Int, timeZoneIdentifier: String,
                 morningsUsed: Int, morningsFound: Int, daysOfData: Int, steps: [Step]) {
        self.id = id; self.createdAt = createdAt; self.baseRoutineID = baseRoutineID
        self.typicalStartMinuteOfDay = typicalStartMinuteOfDay; self.timeZoneIdentifier = timeZoneIdentifier
        self.morningsUsed = morningsUsed; self.morningsFound = morningsFound; self.daysOfData = daysOfData; self.steps = steps
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
