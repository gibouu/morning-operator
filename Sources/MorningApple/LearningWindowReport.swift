import Foundation
import MorningCore

public extension LearningWindowLimits {
    /// The bounds of the recorder this app has. Read here and nowhere else, so a window can
    /// never ask for a morning longer than one recording.
    static var currentCapture: LearningWindowLimits {
        let seconds = ScreenRecordingDuration.allCases.map(\.rawValue)
        return .init(minimumDurationSeconds: seconds.min() ?? 0, maximumDurationSeconds: seconds.max() ?? 0)
    }
}

public extension ObservationArchive {
    /// Declares one saved native recording to a learning window and writes the result on
    /// the observation. The interval comes from the recording itself: the start its
    /// recording session acknowledged, and the length of its saved movie. An imported file
    /// has neither and is refused, as is everything the window refuses (see
    /// `LearningWindow.capture`), first among them a window that was stopped.
    ///
    /// This is the only way a recording joins a window. It is called after a recording is
    /// saved; it starts nothing and changes no other field of the observation.
    @discardableResult
    mutating func declareCapture(of id: UUID, to window: LearningWindow, at now: Date) throws -> ObservationWindowCapture {
        guard let entry = entry(id: id) else { throw ObservationArchiveError.unknownAcquisition }
        guard entry.windowCapture == nil else { throw LearningWindowError.alreadyDeclared }
        guard let context = entry.recordingContext, let evidence = entry.videoEvidence else {
            throw LearningWindowError.recordingStartUnknown
        }
        let capture = try window.capture(recordingStartedAt: context.startedAt,
            recordingTimeZoneIdentifier: context.timeZoneIdentifier,
            recordedSeconds: evidence.durationSeconds, declaredAt: now)
        try attachWindowCapture(capture, to: id)
        return capture
    }
}

/// The task's seven answers for one morning, from when recordings ran. None of them is a
/// statement about what the person did.
public enum LearningWindowMorningStatus: String, Sendable, Equatable {
    /// Recorded from the start of the window to its end, within the window's allowances.
    case observedInWindow
    /// Recorded for part of the window: started late, ended early, or interrupted.
    case observedPartly
    /// A recording was made that day, entirely outside the window.
    case observedOutsideWindow
    /// The window ended with no recording declared for that morning. Not a morning without activity.
    case missed
    /// The window has not ended yet, so nothing can be said.
    case notYetDue
    case paused
    case skipped
}

public enum LearningWindowNotCountedReason: String, Sendable, Equatable {
    case observedPartly, observedOutsideWindow, missed, notYetDue, paused, skipped
    /// Several recordings that morning. Recordings are never joined into one morning.
    case severalRecordings
    /// The recording is not yet labelled as coming from the origin being learned.
    case originNotConfirmed
}

/// How much of the expected interval recordings ran through. Recorded time only.
public struct LearningWindowCoverage: Sendable, Equatable {
    public let expectedSeconds: Double
    public let coveredSeconds: Double
    /// From the window's start to the first recorded instant inside it. Nil when nothing was recorded inside it.
    public let startedLateSeconds: Double?
    public let endedEarlySeconds: Double?
    /// Whole minutes, rounded down: coverage is never rounded up.
    public var coveredMinutes: Int { Int(coveredSeconds / 60) }
    public var uncoveredSeconds: Double { max(0, expectedSeconds - coveredSeconds) }
}

public struct LearningWindowMorningReport: Sendable, Equatable, Identifiable {
    public let dayKey: String
    public let expectedStart: Date
    public let expectedEnd: Date
    public let status: LearningWindowMorningStatus
    /// Nil when no recording was declared for the morning.
    public let coverage: LearningWindowCoverage?
    public let acquisitionIDs: [UUID]
    /// Nil when the morning counts toward the number of mornings asked.
    public let notCountedReason: LearningWindowNotCountedReason?
    public var countsTowardProgress: Bool { notCountedReason == nil }
    public var id: String { dayKey }
}

public struct LearningWindowProgress: Sendable, Equatable {
    /// The number of mornings the person asked for.
    public let askedMorningCount: Int
    /// Mornings recorded through the whole window by one recording of the learned origin.
    public let adequateMorningCount: Int
    /// Mornings of this window that can still be recorded. Zero once it has ended.
    public let remainingMorningCount: Int
    public var stillNeededCount: Int { max(0, askedMorningCount - adequateMorningCount) }
    /// Mornings that will be lacking even if every remaining one is recorded.
    public var shortfallCount: Int { max(0, stillNeededCount - remainingMorningCount) }
}

/// A learning window read against the saved observations. Derived on demand and never
/// stored, like the comparable-morning profile it feeds.
///
/// A morning counts when one recording of the requested origin ran through its whole
/// window. That is adequate capture, not adequate evidence: whether its samples can be
/// compared is decided by `ComparableMorningProfile`, which may still exclude it.
public struct LearningWindowReport: Sendable, Equatable {
    public let windowID: UUID
    public let state: LearningWindowState
    public let mornings: [LearningWindowMorningReport]
    public let progress: LearningWindowProgress
    /// Declared to this window but not counted: written at or after Stop, or no longer
    /// matching a morning of the window.
    public let ignoredAcquisitionIDs: [UUID]
    /// Declared to a morning, then given another day or no day by the person in review.
    public let reassignedAcquisitionIDs: [UUID]

    public init(window: LearningWindow, archive: ObservationArchive, now: Date,
                origin: ObservationAcquisitionOrigin = .human) {
        let schedule = window.schedule(asOf: now)
        var byDay: [String: [ObservationAcquisition]] = [:]
        var ignored: [UUID] = []
        var reassigned: [UUID] = []
        for entry in archive.entries {
            guard let capture = entry.windowCapture, capture.windowID == window.id else { continue }
            guard window.counts(capture) else { ignored.append(entry.id); continue }
            guard let observed = entry.observedDate, observed.dayKey == capture.dayKey,
                  observed.timeZoneIdentifier == window.timeZoneIdentifier else { reassigned.append(entry.id); continue }
            byDay[capture.dayKey, default: []].append(entry)
        }
        mornings = schedule.mornings.map { morning in
            Self.report(morning, entries: byDay[morning.dayKey] ?? [], window: window, now: now, origin: origin)
        }
        let adequate = mornings.filter(\.countsTowardProgress).count
        let open = window.state == .planned || window.state == .active || window.state == .paused
        // Mornings without a date can still come only before Start or during a pause. Past
        // the window's longest span they will never be scheduled, paused or not.
        // During a pause they are the mornings the person would get by pressing Start now.
        var datable = window.state == .planned ? schedule.undatedMorningCount : 0
        if window.state == .paused {
            var resumed = window
            if (try? resumed.start(at: now)) != nil {
                datable = resumed.schedule(asOf: now).countedMornings.filter { $0.expectedStart > now }.count
            }
        }
        let upcoming = mornings.filter { $0.status == .notYetDue }.count + datable
        progress = .init(askedMorningCount: window.morningCount, adequateMorningCount: adequate,
                         remainingMorningCount: open ? upcoming : 0)
        windowID = window.id
        state = window.state
        ignoredAcquisitionIDs = ignored
        reassignedAcquisitionIDs = reassigned
    }

    private static func report(_ morning: LearningWindowMorning, entries: [ObservationAcquisition],
                               window: LearningWindow, now: Date,
                               origin: ObservationAcquisitionOrigin) -> LearningWindowMorningReport {
        let declaredIDs = entries.map(\.id)
        func result(_ status: LearningWindowMorningStatus, _ coverage: LearningWindowCoverage?,
                    _ reason: LearningWindowNotCountedReason?) -> LearningWindowMorningReport {
            .init(dayKey: morning.dayKey, expectedStart: morning.expectedStart, expectedEnd: morning.expectedEnd,
                  status: status, coverage: coverage, acquisitionIDs: declaredIDs, notCountedReason: reason)
        }
        switch morning.disposition {
        case .paused: return result(.paused, nil, .paused)
        case .skipped: return result(.skipped, nil, .skipped)
        case .counted: break
        }
        guard !entries.isEmpty else {
            return now < morning.expectedEnd ? result(.notYetDue, nil, .notYetDue) : result(.missed, nil, .missed)
        }
        // As comparable mornings do: a morning that has a recording of the requested origin
        // is judged on those alone. One of another origin beside it neither joins nor blocks it.
        let requested = entries.filter { $0.origin == origin }
        let entries = requested.isEmpty ? entries : requested
        // The recorded spans inside the expected interval, joined where they touch. Only the
        // total and the outer edges are read from several recordings; they are never one morning.
        let spans = entries.compactMap { entry -> (Date, Date)? in
            guard let capture = entry.windowCapture else { return nil }
            let start = max(capture.actualStart, morning.expectedStart), end = min(capture.actualEnd, morning.expectedEnd)
            return end > start ? (start, end) : nil
        }.sorted { $0.0 < $1.0 }
        var joined: [(Date, Date)] = []
        for span in spans {
            if let last = joined.last, span.0 <= last.1 { joined[joined.count - 1].1 = max(last.1, span.1) }
            else { joined.append(span) }
        }
        let expected = morning.expectedEnd.timeIntervalSince(morning.expectedStart)
        let covered = joined.reduce(0) { $0 + $1.1.timeIntervalSince($1.0) }
        let coverage = LearningWindowCoverage(expectedSeconds: expected, coveredSeconds: covered,
            startedLateSeconds: joined.first.map { $0.0.timeIntervalSince(morning.expectedStart) },
            endedEarlySeconds: joined.last.map { morning.expectedEnd.timeIntervalSince($0.1) })
        guard !joined.isEmpty else { return result(.observedOutsideWindow, coverage, .observedOutsideWindow) }
        let whole = window.comparableInterval(expectedStart: morning.expectedStart, expectedEnd: morning.expectedEnd)
            .map { core in joined.contains { $0.0 <= core.start && $0.1 >= core.end } } ?? false
        guard whole else { return result(.observedPartly, coverage, .observedPartly) }
        if entries.count > 1 { return result(.observedInWindow, coverage, .severalRecordings) }
        if requested.isEmpty { return result(.observedInWindow, coverage, .originNotConfirmed) }
        return result(.observedInWindow, coverage, nil)
    }
}

public extension ComparableMorningProfile {
    /// Comparable mornings of a learning window. The window supplies what the profile had
    /// no source for: the scheduled days, and for each declared recording the part of the
    /// window it captured.
    ///
    /// - Scheduled days are the window's counted mornings that are over. A morning still to
    ///   come, a paused one and a skipped one are not days without an observation.
    /// - Mornings are compared over the interval every adequately recorded morning shares
    ///   (`LearningWindow.comparableInterval`). A recording that ran through it is judged on
    ///   its samples; one that started late or ended early is excluded as partial capture.
    /// - A recording never declared to this window, or declared after Stop, has no known
    ///   capture and is excluded as unknown capture, as before.
    init(window: LearningWindow, archive: ObservationArchive, now: Date,
         origin: ObservationAcquisitionOrigin = .human, maximumSampleGapSeconds: Double) throws {
        let due = window.schedule(asOf: now).countedMornings.filter { $0.expectedEnd <= now }
        let coreSeconds = Double(window.durationSeconds - window.lateStartAllowanceSeconds - window.earlyEndAllowanceSeconds)
        var scopes: [UUID: ObservationCaptureScope] = [:]
        for entry in archive.entries {
            // A recording the person moved to another day in review is judged there, without
            // the declaration it was given for the morning it was recorded on.
            guard let capture = entry.windowCapture, window.counts(capture),
                  let observed = entry.observedDate, observed.dayKey == capture.dayKey,
                  observed.timeZoneIdentifier == window.timeZoneIdentifier,
                  due.contains(where: { $0.dayKey == capture.dayKey }),
                  let core = window.comparableInterval(expectedStart: capture.expectedStart,
                                                       expectedEnd: capture.expectedEnd) else { continue }
            // The two ends are exact when the recording reaches them, so a morning recorded
            // through the whole interval is complete whatever the rounding of its dates.
            let from = capture.actualStart <= core.start ? 0 : capture.actualStart.timeIntervalSince(core.start)
            let to = capture.actualEnd >= core.end ? coreSeconds : capture.actualEnd.timeIntervalSince(core.start)
            let captured = to > from && from < coreSeconds && to > 0
                ? [ObservationTraceInterval(startSeconds: max(0, from), endSeconds: min(coreSeconds, to))] : []
            scopes[entry.id] = try ObservationCaptureScope(
                startOffsetSeconds: core.start.timeIntervalSince(capture.actualStart),
                durationSeconds: coreSeconds, capturedIntervals: captured)
        }
        try self.init(archive: archive, scheduledDays: due.map(\.expectedStart),
                      timeZoneIdentifier: window.timeZoneIdentifier, origin: origin,
                      comparisonKey: "learning-window:\(window.id.uuidString)",
                      policy: .init(expectedWindowSeconds: coreSeconds, maximumSampleGapSeconds: maximumSampleGapSeconds),
                      captureScopes: scopes)
    }
}
