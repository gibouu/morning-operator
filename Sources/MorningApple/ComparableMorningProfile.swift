import Foundation
import MorningCore

/// Saved observations of one origin compared over explicitly scheduled days. Derived on
/// demand from the archive and never stored: a stored copy could disagree with the
/// observations, corrections and screen reviews it describes.
///
/// A date and an origin do not make an adequate morning. Each day is still judged by the
/// comparison policy, and a day that fails is excluded with its reason, not counted as a
/// morning with no activity.
///
/// A scheduled day is included, missing or excluded exactly once, and an excluded day carries
/// one reason: the first that applies, in this order, whatever order the archive lists its
/// observations in.
/// 1. No observation of the requested origin, and one of another origin: `differentOrigin`
///    if any is human or synthetic, else `automatedOrigin`, else `unknownOrigin`. A date that
///    does have one of the requested origin is judged on it alone.
/// 2. `repeatedRecording`: one of the date's recordings is also saved on another scheduled
///    date under the requested origin. It is the reason on every such date, including a
///    date that holds two recordings: `acquisitionIDsByDayKey` still shows those, while
///    nothing else would show the repeat. The same extraction saved twice on one date and
///    on no other is two recordings on one date, not a repeat.
/// 3. `duplicateDay`, then `noSampledEvidence`, then `unreadableSamples`.
/// 4. The comparison policy's reasons, in the order `ObservationTraceWindowReport` checks them.
/// The part of one recording that a planned scope covers, from a source that knows when the
/// recording ran. Comparable mornings are then compared over that scope, not over each
/// movie's own length: the trace lasts `durationSeconds`, keeps only the samples inside the
/// scope and states which parts of the scope the recording captured.
public struct ObservationCaptureScope: Sendable, Equatable {
    /// Where the scope begins on the movie's timeline. Negative when the recording began
    /// after the scope did. Movie time zero is taken to be the acknowledged recording
    /// start; that alignment is not measured.
    public let startOffsetSeconds: Double
    public let durationSeconds: Double
    /// In seconds from the start of the scope. Empty when the recording missed it entirely.
    public let capturedIntervals: [ObservationTraceInterval]

    public init(startOffsetSeconds: Double, durationSeconds: Double,
                capturedIntervals: [ObservationTraceInterval]) throws {
        guard startOffsetSeconds.isFinite, durationSeconds.isFinite, durationSeconds > 0 else {
            throw ObservationTraceError.invalidDuration
        }
        var end = 0.0
        for interval in capturedIntervals {
            guard interval.startSeconds.isFinite, interval.endSeconds.isFinite, interval.startSeconds >= end,
                  interval.endSeconds > interval.startSeconds, interval.endSeconds <= durationSeconds else {
                throw ObservationTraceError.invalidCoverage
            }
            end = interval.endSeconds
        }
        self.startOffsetSeconds = startOffsetSeconds
        self.durationSeconds = durationSeconds
        self.capturedIntervals = capturedIntervals
    }
}

public struct ComparableMorningProfile: Sendable, Equatable {
    /// Scheduled days are exactly its included, missing and excluded days.
    public let report: ObservationTraceWindowReport
    /// Saved observations of the requested origin on each scheduled date, in archive order.
    /// More than one on a date excludes that date: recordings are never joined or chosen between.
    public let acquisitionIDsByDayKey: [String: [UUID]]
    /// Observations on a scheduled date with another origin. They never contribute.
    public let otherOriginAcquisitionIDs: [UUID]
    /// Dated in another time zone, whatever the date. Not moved onto this calendar. An
    /// observation given a day through `scheduledDayByObservation` is not listed here, nor
    /// under `undatedAcquisitionIDs`: it is on this calendar by that day, whatever zone its
    /// own date is written in.
    public let otherTimeZoneAcquisitionIDs: [UUID]
    public let undatedAcquisitionIDs: [UUID]

    /// - Parameters:
    ///   - origin: `.human` or `.synthetic`. The two never share a profile, and assistant-run
    ///     or unlabelled observations cannot be profiled at all.
    ///   - comparisonKey: the caller's name for the planned scope every scheduled day shares.
    ///   - declaredCapture: which parts of a recording were captured, by observation, from a
    ///     source that actually knows. Saved observations carry no such declaration, so a
    ///     recording without an entry here is excluded as unknown capture. Nothing is guessed
    ///     from the movie's length or its samples.
    ///   - captureScopes: for an observation declared to a planned scope such as a learning
    ///     window, the part of its movie that scope covers. It takes precedence over
    ///     `declaredCapture` for that observation. `init(window:archive:now:)` builds these
    ///     from the declarations saved on the observations themselves.
    ///   - scheduledDayByObservation: for an observation a planned scope declared to one
    ///     day, an instant of that day. The observation is then counted on that day and on
    ///     no other: its own date is not read, so it can neither be counted a second time
    ///     under the date of the calendar it was recorded on, nor be refused for being dated
    ///     in another zone. When that day is not one of `scheduledDays` (a morning still to
    ///     come), the observation is on none of them.
    public init(archive: ObservationArchive, scheduledDays: [Date], timeZoneIdentifier: String,
                origin: ObservationAcquisitionOrigin, comparisonKey: String,
                policy: ObservationComparisonPolicy,
                declaredCapture: [UUID: [ObservationTraceInterval]] = [:],
                captureScopes: [UUID: ObservationCaptureScope] = [:],
                scheduledDayByObservation: [UUID: Date] = [:]) throws {
        let traceOrigin: ObservationTraceOrigin
        switch origin {
        case .human: traceOrigin = .human
        case .synthetic: traceOrigin = .synthetic
        case .automated, .unknown: throw ObservationTraceError.invalidPolicy
        }
        func dayKey(_ day: Date) throws -> String {
            guard let value = try? ObservationObservedDate(date: day, timeZoneIdentifier: timeZoneIdentifier,
                                                           provenance: .userAssigned) else {
                throw ObservationTraceError.invalidDay
            }
            return value.dayKey
        }
        let scheduledKeys = try scheduledDays.map(dayKey)
        var matching: [String: [ObservationAcquisition]] = [:]
        var others: [String: [ObservationAcquisition]] = [:]
        var otherZone: [UUID] = []
        var undated: [UUID] = []
        // The instant that places each kept observation on this calendar.
        var dateByID: [UUID: Date] = [:]
        for entry in archive.entries {
            let key: String
            if let day = scheduledDayByObservation[entry.id] {
                // Placed by its declaration. Its own date and zone are not consulted, so it
                // has at most one day here, and that day is never the one its date names.
                key = try dayKey(day)
                guard scheduledKeys.contains(key) else { continue }
                dateByID[entry.id] = day
            } else {
                guard let observed = entry.observedDate else { undated.append(entry.id); continue }
                guard observed.timeZoneIdentifier == timeZoneIdentifier else { otherZone.append(entry.id); continue }
                guard scheduledKeys.contains(observed.dayKey) else { continue }
                key = observed.dayKey
                dateByID[entry.id] = observed.date
            }
            if entry.origin == origin { matching[key, default: []].append(entry) }
            else { others[key, default: []].append(entry) }
        }

        // One extraction saved as two observations is still one recording. Its dates are
        // excluded together: nothing says which date it belongs to. Every recording of a
        // date counts, and each date once, so a date holding two recordings neither hides
        // a repeat nor becomes one by holding the same extraction twice.
        var dateCountByEvidenceID: [UUID: Int] = [:]
        for clips in matching.values {
            for id in Set(clips.compactMap { $0.videoEvidence?.id }) { dateCountByEvidenceID[id, default: 0] += 1 }
        }
        var days: [ObservationTraceDay] = []
        var exclusions: [ObservationExcludedDay] = []
        for key in Set(scheduledKeys).sorted() {
            guard let clips = matching[key] else {
                // No observation of the requested origin. Another origin on this date is
                // stated as the reason; a date with nothing at all stays missing.
                guard let present = others[key] else { continue }
                let reason: ObservationDayExclusion
                if present.contains(where: { $0.origin == .human || $0.origin == .synthetic }) { reason = .differentOrigin }
                else if present.contains(where: { $0.origin == .automated }) { reason = .automatedOrigin }
                else { reason = .unknownOrigin }
                exclusions.append(.init(dayKey: key, reason: reason))
                continue
            }
            guard !clips.contains(where: { clip in
                clip.videoEvidence.map { dateCountByEvidenceID[$0.id, default: 0] > 1 } ?? false
            }) else {
                exclusions.append(.init(dayKey: key, reason: .repeatedRecording)); continue
            }
            guard clips.count == 1, let entry = clips.first, let date = dateByID[entry.id] else {
                exclusions.append(.init(dayKey: key, reason: .duplicateDay)); continue
            }
            guard let evidence = entry.videoEvidence else {
                exclusions.append(.init(dayKey: key, reason: .noSampledEvidence)); continue
            }
            // The review applies the person's screen reviews over the model's labels and
            // leaves conflicting or corrected samples unknown. Reuse it instead of a second
            // reading. One it cannot build, or cannot order, is a day that cannot be compared.
            guard let review = try? ObservationClipReview(acquisition: entry), review.timelineOrderIsValid else {
                exclusions.append(.init(dayKey: key, reason: .unreadableSamples)); continue
            }
            let samples = review.rows.flatMap { row in
                row.samples.map { sample in
                    ObservationTraceSample(id: sample.id, timeSeconds: sample.timeSeconds, timeBasis: sample.timeBasis,
                        outcome: sample.outcome, appEvidence: row.resolution == .recognized ? sample.context : .unknown)
                }
            }
            let trace: ObservationTrace
            if let scope = captureScopes[entry.id] {
                // Samples outside the scope are not part of what the mornings share. They
                // stay in the saved observation and are simply not compared.
                let scoped = samples.compactMap { sample -> ObservationTraceSample? in
                    let time = sample.timeSeconds - scope.startOffsetSeconds
                    guard time >= 0, time <= scope.durationSeconds else { return nil }
                    return .init(id: sample.id, timeSeconds: time, timeBasis: sample.timeBasis,
                                 outcome: sample.outcome, appEvidence: sample.appEvidence)
                }
                trace = try ObservationTrace(id: evidence.id, durationSeconds: scope.durationSeconds,
                    capturedIntervals: scope.capturedIntervals, origin: traceOrigin, samples: scoped)
            } else {
                trace = try ObservationTrace(id: evidence.id, durationSeconds: evidence.durationSeconds,
                    capturedIntervals: declaredCapture[entry.id], origin: traceOrigin, samples: samples)
            }
            days.append(try ObservationTraceDay(date: date, timeZoneIdentifier: timeZoneIdentifier,
                                                comparisonKey: comparisonKey, trace: trace))
        }
        report = try ObservationTraceWindowReport(days: days, scheduledDays: scheduledDays,
            timeZoneIdentifier: timeZoneIdentifier, comparisonKey: comparisonKey, policy: policy,
            origin: traceOrigin, excluding: exclusions)
        acquisitionIDsByDayKey = matching.mapValues { $0.map(\.id) }
        otherOriginAcquisitionIDs = archive.entries.filter { entry in
            others.values.contains { $0.contains { $0.id == entry.id } }
        }.map(\.id)
        otherTimeZoneAcquisitionIDs = otherZone
        undatedAcquisitionIDs = undated
    }
}
