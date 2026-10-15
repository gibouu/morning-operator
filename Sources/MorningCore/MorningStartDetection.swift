import Foundation

/// Evidence that the phone was in use during an interval (a point is a zero-length interval).
public struct PhoneUse: Equatable, Sendable {
    public enum Source: String, Sendable {
        case screenTimePickup, screenTimeLongestActivity, screenTimeHour, appTransition, recording
        /// A moment the hour's totals force: its use cannot end before the first pickup plus
        /// the hour's total, nor (without a first pickup) start after the hour's end minus it.
        /// It is a bound, not a timed use: gaps it closes are real, but continuity it adds is
        /// not proven, so minutes it bridges are never called measured.
        case screenTimeBound
    }
    public let interval: DateInterval
    public let source: Source

    public init(_ interval: DateInterval, source: Source) {
        self.interval = interval
        self.source = source
    }

    public init(at date: Date, source: Source) {
        self.init(DateInterval(start: date, duration: 0), source: source)
    }
}

/// The owner's rule (14 October 2026): the morning starts at the first phone use after at
/// least three hours without use, and ends when use stops for a while or at a cap.
public struct MorningDetectionPolicy: Equatable, Sendable {
    /// No use for at least this long counts as sleep.
    public var sleepGap: TimeInterval = 3 * 3600
    /// Use separated by less than this is one session; a longer pause ends the morning.
    public var sessionGap: TimeInterval = 20 * 60
    /// The morning never runs longer than this.
    public var maximumLength: TimeInterval = 3 * 3600
    /// A short session that starts before this local hour, and is followed by another
    /// sleep-length gap, is a night-time check, not the morning.
    public var nightCheckLatestHour = 5
    public var nightCheckMaximumLength: TimeInterval = 15 * 60
    /// A sleep end from HealthKit moves the start to the first session at or after it, minus this.
    public var sleepEndTolerance: TimeInterval = 30 * 60

    public init() {}
}

public struct DetectedMorning: Equatable, Sendable {
    public enum EndReason: String, Sendable {
        /// Use stopped for at least `sessionGap`.
        case pause
        /// The morning reached `maximumLength`.
        case cap
        /// The last use is less than `sessionGap` before now: the morning may still be going.
        case ongoing
    }

    public let start: Date
    public let end: Date
    public let endReason: EndReason
    /// Sessions skipped because they look like night-time checks (or came before the sleep hint).
    public let skippedSessions: [DateInterval]
    public let usedSleepHint: Bool
    public var interval: DateInterval { DateInterval(start: start, end: end) }
}

public enum MorningDetectionResult: Equatable, Sendable {
    case found(DetectedMorning)
    /// No phone use evidence on that local day.
    case noData
    /// Use was found, but the evidence does not cover a full sleep gap before it, so the
    /// start cannot be told apart from the middle of a session.
    case noSleepGapCovered
}

public enum MorningStartDetector {
    /// Finds the morning on the local date of `day` (in `calendar`'s time zone).
    /// - Parameters:
    ///   - uses: phone-use evidence, any order. Absence of evidence is read as no use only
    ///     from `coveredFrom` onward; before it nothing is known.
    ///   - coveredFrom: start of the evidence's coverage (for example the earliest hour queried).
    ///   - sleepEnd: optional HealthKit sleep end, used only as a hint.
    ///   - useInside: total known use during a session, when the evidence knows more than the
    ///     session's span (hourly totals). A night check must also fit within its maximum length.
    public static func detect(uses: [PhoneUse], on day: Date, coveredFrom: Date, now: Date = .now,
                              sleepEnd: Date? = nil, policy: MorningDetectionPolicy = MorningDetectionPolicy(),
                              calendar: Calendar = .current,
                              useInside: ((DateInterval) -> TimeInterval)? = nil) -> MorningDetectionResult {
        guard let dayInterval = calendar.dateInterval(of: .day, for: day) else { return .noData }
        let sessions = sessionsOf(uses.filter { $0.interval.end >= coveredFrom && $0.interval.start <= now },
                                  gap: policy.sessionGap, coveredFrom: coveredFrom)
        guard sessions.contains(where: { dayInterval.contains($0.start) }) else { return .noData }

        // A candidate is a session that starts on that day after a sleep-length gap.
        var candidates: [(index: Int, session: DateInterval)] = []
        for (index, session) in sessions.enumerated() where dayInterval.contains(session.start) {
            let previousEnd = index > 0 ? sessions[index - 1].end : coveredFrom
            if session.start.timeIntervalSince(previousEnd) >= policy.sleepGap { candidates.append((index, session)) }
        }
        guard !candidates.isEmpty else { return .noSleepGapCovered }

        var skipped: [DateInterval] = []
        var chosen: (index: Int, session: DateInterval)?
        var usedHint = false
        if let sleepEnd, dayInterval.contains(sleepEnd) {
            let earliest = sleepEnd.addingTimeInterval(-policy.sleepEndTolerance)
            if let match = candidates.first(where: { $0.session.start >= earliest }) {
                chosen = match
                usedHint = true
                skipped = candidates.filter { $0.session.start < earliest }.map(\.session)
            }
        }
        if chosen == nil {
            for (position, candidate) in candidates.enumerated() {
                let hour = calendar.component(.hour, from: candidate.session.start)
                let isNightCheck = hour < policy.nightCheckLatestHour
                    && candidate.session.duration <= policy.nightCheckMaximumLength
                    && (useInside?(candidate.session) ?? 0) <= policy.nightCheckMaximumLength
                    && position + 1 < candidates.count
                    // Only when he really went back to sleep: the next use is a sleep gap later.
                    && sessions[candidate.index + 1].start.timeIntervalSince(candidate.session.end) >= policy.sleepGap
                if isNightCheck { skipped.append(candidate.session) } else { chosen = candidate; break }
            }
        }
        guard let chosen else { return .noSleepGapCovered }

        let start = chosen.session.start
        let cap = start.addingTimeInterval(policy.maximumLength)
        let sessionEnd = chosen.session.end
        let end: Date
        let reason: DetectedMorning.EndReason
        if sessionEnd >= cap {
            end = cap; reason = .cap
        } else if now.timeIntervalSince(sessionEnd) < policy.sessionGap {
            end = min(now, cap); reason = .ongoing
        } else {
            end = sessionEnd; reason = .pause
        }
        return .found(DetectedMorning(start: start, end: max(end, start), endReason: reason,
                                      skippedSessions: skipped, usedSleepHint: usedHint))
    }

    /// Merges uses whose gap is under `gap` into sessions, sorted by start.
    static func sessionsOf(_ uses: [PhoneUse], gap: TimeInterval, coveredFrom: Date) -> [DateInterval] {
        let sorted = uses.sorted { $0.interval.start < $1.interval.start }
        var sessions: [DateInterval] = []
        for use in sorted {
            let interval = use.interval
            let clipped = DateInterval(start: max(interval.start, coveredFrom), end: max(interval.end, coveredFrom))
            if let last = sessions.last, clipped.start.timeIntervalSince(last.end) < gap {
                sessions[sessions.count - 1] = DateInterval(start: last.start, end: max(last.end, clipped.end))
            } else {
                sessions.append(clipped)
            }
        }
        return sessions
    }
}

public extension PhoneUse {
    /// Use evidence from one hourly Screen Time segment. Hourly totals cannot place use
    /// inside the hour, so the first pickup and the longest activity become timed evidence.
    /// One exception is exact: when the hour's use leaves less idle time than `sessionGap`,
    /// no pause that long fits inside it. Use then began within `idle` of the hour's start
    /// and lasted until within `idle` of its end, so [start + idle, end − idle] is one
    /// session. Two busy hours merge only when their idle time adds up to less than a pause.
    /// An hour with use but none of these adds its start as a coarse point.
    static func fromScreenTimeSegment(hour: DateInterval, totalSeconds: TimeInterval,
                                      firstPickup: Date?, longestActivity: DateInterval?,
                                      sessionGap: TimeInterval = MorningDetectionPolicy().sessionGap) -> [PhoneUse] {
        var uses: [PhoneUse] = []
        if totalSeconds > 0, hour.duration - totalSeconds < sessionGap {
            let idle = hour.duration - totalSeconds
            // The first pickup, when inside the hour, is the exact start of use; the idle time
            // before it is known, so less idle can remain at the end of the hour.
            let pickup = firstPickup.flatMap { hour.contains($0) && $0 > hour.start ? $0 : nil }
            let start = pickup ?? hour.start.addingTimeInterval(idle)
            let trailingIdle = pickup.map { max(0, idle - $0.timeIntervalSince(hour.start)) } ?? idle
            let end = max(start, hour.end.addingTimeInterval(-trailingIdle))
            uses.append(PhoneUse(DateInterval(start: start, end: end), source: .screenTimeHour))
        }
        if let firstPickup { uses.append(PhoneUse(at: firstPickup, source: .screenTimePickup)) }
        if let longestActivity, longestActivity.duration > 0 { uses.append(PhoneUse(longestActivity, source: .screenTimeLongestActivity)) }
        if uses.isEmpty, totalSeconds > 0 { uses.append(PhoneUse(at: hour.start, source: .screenTimeHour)) }
        return uses
    }
}
