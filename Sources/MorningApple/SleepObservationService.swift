import Foundation

// Sleep duration for the morning briefing (issue #15). This file holds the values, the
// totalling rule, the reader protocol and the service. It imports no health framework
// and reads nothing by itself: a reader is injected. Without one the service says so.
// Nothing here is saved, logged or sent; samples and totals stay in memory.

/// What a sleep-analysis sample says about its span. These are the six values HealthKit's
/// sleep analysis has; there is no score or quality among them and none is derived.
public enum SleepStage: String, Sendable, Equatable, CaseIterable {
    case inBed, awake, asleepUnspecified, asleepCore, asleepDeep, asleepREM

    /// Only these add to the asleep total. In bed and awake never do.
    public var isAsleep: Bool {
        switch self {
        case .asleepUnspecified, .asleepCore, .asleepDeep, .asleepREM: true
        case .inBed, .awake: false
        }
    }
}

/// Where a sample came from, as far as its source record can say. HealthKit has no
/// "kind" field: this is worked out from three things it does expose, the source's
/// bundle identifier, the hardware model string of the source revision and the
/// "entered by the user" metadata flag. Anything else is `unknown`, never a guess.
public enum SleepSourceKind: String, Sendable, Equatable, CaseIterable, Comparable {
    case watch, phone, thirdPartyApp, manualEntry, unknown

    public static func < (lhs: Self, rhs: Self) -> Bool {
        allCases.firstIndex(of: lhs)! < allCases.firstIndex(of: rhs)!
    }

    /// - A sample flagged as entered by the user is a manual entry, whatever wrote it.
    /// - A source whose bundle identifier is not Apple's is another app. The hardware
    ///   model then names the device that app ran on, not a measuring device.
    /// - An Apple source is a watch or a phone when the hardware model string starts
    ///   with "Watch" or "iPhone". Any other or missing model is unknown.
    public static func classify(bundleIdentifier: String, productType: String?, wasUserEntered: Bool) -> Self {
        if wasUserEntered { return .manualEntry }
        guard bundleIdentifier.lowercased().hasPrefix("com.apple.") else { return .thirdPartyApp }
        guard let productType else { return .unknown }
        if productType.hasPrefix("Watch") { return .watch }
        if productType.hasPrefix("iPhone") { return .phone }
        return .unknown
    }
}

public struct SleepSample: Sendable, Equatable {
    public let stage: SleepStage
    public let start: Date
    public let end: Date
    /// The source's bundle identifier. Used only to count distinct sources; never shown or spoken.
    public let sourceID: String
    public let sourceKind: SleepSourceKind

    public init(stage: SleepStage, start: Date, end: Date, sourceID: String, sourceKind: SleepSourceKind) {
        self.stage = stage; self.start = start; self.end = end
        self.sourceID = sourceID; self.sourceKind = sourceKind
    }
}

/// One night as recorded. A duration and the window it was recorded in, with where it came
/// from and when it was read. No score, no quality label, no advice and no comparison with
/// a recommended amount: none of these is in the samples, so none is stated.
public struct SleepObservation: Sendable, Equatable {
    /// Start of the earliest counted asleep sample.
    public let windowStart: Date
    /// End of the latest counted asleep sample.
    public let windowEnd: Date
    /// Elapsed time recorded as asleep inside the window, in seconds. It can be shorter
    /// than the window: time recorded as awake, or not recorded at all, is not counted.
    public let asleepDuration: TimeInterval
    /// The kinds of source that contributed a counted sample, in a fixed order.
    public let sourceKinds: [SleepSourceKind]
    /// How many distinct sources contributed. Above one, see the overlap rule.
    public let sourceCount: Int
    public let readAt: Date

    /// Whole minutes, rounded to the nearest. This is the number that is shown and spoken.
    public var asleepMinutes: Int { Int((asleepDuration / 60).rounded()) }
}

/// What the samples say about the time since yesterday evening.
public enum SleepNightSummary: Sendable, Equatable {
    case recorded(SleepObservation)
    /// Nothing since yesterday evening, but an earlier asleep record exists in what was read.
    case olderRecord(endedAt: Date)
    /// No asleep record in what was read. This is also what a refused read looks like:
    /// HealthKit answers a read without permission with no samples and no error.
    case noRecord
}

public enum SleepNight {
    /// The hour, on the day before the briefing's day, after which an asleep sample belongs
    /// to "since yesterday evening". Chosen because a night's sleep ends after it and the
    /// previous night's sleep ends before it for nearly everyone; it is a convention, not
    /// something the samples say.
    public static let eveningHour = 18

    /// Yesterday at 18:00 on the wall clock of `calendar`'s time zone.
    public static func eveningCutoff(before now: Date, calendar: Calendar) -> Date? {
        let today = calendar.startOfDay(for: now)
        guard let yesterday = calendar.date(byAdding: .day, value: -1, to: today) else { return nil }
        return calendar.date(bySettingHour: eveningHour, minute: 0, second: 0, of: yesterday)
    }

    /// The totalling rule.
    ///
    /// 1. **What counts.** Only samples in an asleep stage (unspecified, core, deep, REM)
    ///    that ended at or before `now`. "In bed" and "awake" never add time. A night with
    ///    only "in bed" samples therefore has no asleep record: time in bed is not sleep.
    /// 2. **Which samples.** Those that ended after yesterday 18:00 local time. A sample that
    ///    started before that hour and ended after it is counted whole, as recorded.
    /// 3. **Overlap.** The spans are merged before they are added, so an hour recorded by two
    ///    sources, or as two stages, is counted once.
    /// 4. **Window.** From the start of the earliest counted sample to the end of the latest.
    /// 5. **Time.** Durations are elapsed time between instants. A night across midnight needs
    ///    no special case. Across a clock change the total differs from the difference between
    ///    the two wall-clock times by the size of the change; the elapsed total is the true one.
    ///
    /// What the samples cannot say, and so what this does not claim:
    /// - Whether it was one sleep or several. A nap after 18:00 yesterday, or this morning,
    ///   is inside the window and inside the total. The window is always given with the total
    ///   so the person can see it. No gap length is used to separate "the night" from a nap:
    ///   any threshold would drop real sleep on a broken night.
    /// - Which source is right when two disagree. A minute counts when any source recorded
    ///   it as asleep, so the total can exceed what the Health app shows: that app applies a
    ///   source priority which HealthKit does not expose. `sourceCount` says when this applies.
    /// - Why nothing was found. No samples can mean nothing was recorded, nothing has synced
    ///   yet, or the read was not permitted. These cannot be told apart.
    ///
    /// A total that rounds to zero minutes is not reported as a night: it is `noRecord`.
    public static func summarize(_ samples: [SleepSample], readAt: Date, at now: Date,
                                 calendar: Calendar) -> SleepNightSummary {
        let asleep = samples.filter {
            $0.stage.isAsleep && $0.start.timeIntervalSinceReferenceDate.isFinite &&
                $0.end.timeIntervalSinceReferenceDate.isFinite && $0.end > $0.start && $0.end <= now
        }
        guard let cutoff = eveningCutoff(before: now, calendar: calendar) else { return .noRecord }
        let recent = asleep.filter { $0.end > cutoff }.sorted { ($0.start, $0.end) < ($1.start, $1.end) }
        if let first = recent.first {
            var total: TimeInterval = 0
            var spanStart = first.start, spanEnd = first.end
            for sample in recent.dropFirst() {
                if sample.start <= spanEnd { spanEnd = max(spanEnd, sample.end); continue }
                total += spanEnd.timeIntervalSince(spanStart)
                spanStart = sample.start; spanEnd = sample.end
            }
            total += spanEnd.timeIntervalSince(spanStart)
            let observation = SleepObservation(windowStart: first.start,
                windowEnd: recent.map(\.end).max() ?? first.end, asleepDuration: total,
                sourceKinds: Set(recent.map(\.sourceKind)).sorted(),
                sourceCount: Set(recent.map(\.sourceID)).count, readAt: readAt)
            if observation.asleepMinutes > 0 { return .recorded(observation) }
        }
        if let latest = asleep.filter({ $0.end <= cutoff }).map(\.end).max() { return .olderRecord(endedAt: latest) }
        return .noRecord
    }
}

/// One completed read. Memory only: never encoded, never written to a file.
public struct SleepSnapshot: Sendable, Equatable {
    public let readAt: Date
    public let samples: [SleepSample]

    public init(readAt: Date, samples: [SleepSample]) { self.readAt = readAt; self.samples = samples }
}

/// What the briefing is given for sleep. There is deliberately no "denied" case: a read
/// that was not permitted cannot be told from a read that found nothing.
public enum SleepBriefingInput: Sendable, Equatable {
    /// The person has not included health. The reader is not called.
    case excluded
    /// This build has no reader connected. Said on screen, never spoken.
    case notConnected
    /// The device has no health data store.
    case unavailableOnDevice
    /// The read failed or did not answer in time.
    case notReadable
    case snapshot(SleepSnapshot)
}

public enum SleepReadOutcome: Sendable, Equatable {
    case unavailableOnDevice
    /// Empty means no samples were returned, for whatever reason.
    case samples([SleepSample])
}

public enum SleepObservationError: Error, Sendable, Equatable {
    case notConnected, unavailableOnDevice, missingUsageDescription
}

/// The reader boundary, shaped like `CalendarObservationProviding`: values only, no
/// framework objects and no write operation. A fixture implements it in tests.
@MainActor
public protocol SleepObservationProviding {
    /// Call only for an explicit "connect" action by the person. Reading never prompts.
    /// Returning without an error does not mean reading was allowed: HealthKit does not say.
    func requestReadAccess() async throws
    /// Every sleep-analysis sample that overlaps the interval. May return extra samples;
    /// the totalling rule decides what counts.
    func sleepSamples(in interval: DateInterval) async throws -> SleepReadOutcome
}

/// No work is performed by initialization, and none without an explicit call.
@MainActor
public final class SleepObservationService {
    /// How far back a read looks, so an older record can be told from none at all.
    public static let lookback: TimeInterval = 7 * 86_400

    private let provider: (any SleepObservationProviding)?

    /// No reader. Every read answers `notConnected`. This is what the app has today.
    public init() { provider = nil }

    /// Inject a reader; construction never calls it.
    public init(provider: any SleepObservationProviding) { self.provider = provider }

    public var isConnected: Bool { provider != nil }

    public func requestReadAccess() async throws {
        guard let provider else { throw SleepObservationError.notConnected }
        try await provider.requestReadAccess()
    }

    /// One read of the last seven days. Throws only on cancellation; every other failure
    /// is `notReadable`, with no reason attached because the reason is not known.
    public func read(at now: Date) async throws -> SleepBriefingInput {
        try Task.checkCancellation()
        guard let provider else { return .notConnected }
        guard now.timeIntervalSinceReferenceDate.isFinite else { return .notReadable }
        do {
            let outcome = try await provider.sleepSamples(in: DateInterval(start: now.addingTimeInterval(-Self.lookback), end: now))
            try Task.checkCancellation()
            switch outcome {
            case .unavailableOnDevice: return .unavailableOnDevice
            case .samples(let samples): return .snapshot(.init(readAt: now, samples: samples))
            }
        } catch {
            try Task.checkCancellation()
            if error is CancellationError { throw error }
            return .notReadable
        }
    }
}
