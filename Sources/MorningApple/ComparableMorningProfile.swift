import Foundation
import MorningCore

/// Saved observations of one origin compared over explicitly scheduled days. Derived on
/// demand from the archive and never stored: a stored copy could disagree with the
/// observations, corrections and screen reviews it describes.
///
/// A date and an origin do not make an adequate morning. Each day is still judged by the
/// comparison policy, and a day that fails is excluded with its reason, not counted as a
/// morning with no activity.
public struct ComparableMorningProfile: Sendable, Equatable {
    /// Scheduled days are exactly its included, missing and excluded days.
    public let report: ObservationTraceWindowReport
    /// Saved observations of the requested origin on each scheduled date, in archive order.
    /// More than one on a date excludes that date: recordings are never joined or chosen between.
    public let acquisitionIDsByDayKey: [String: [UUID]]
    /// Observations on a scheduled date with another origin. They never contribute.
    public let otherOriginAcquisitionIDs: [UUID]
    /// Dated in another time zone, whatever the date. Not moved onto this calendar.
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
    public init(archive: ObservationArchive, scheduledDays: [Date], timeZoneIdentifier: String,
                origin: ObservationAcquisitionOrigin, comparisonKey: String,
                policy: ObservationComparisonPolicy,
                declaredCapture: [UUID: [ObservationTraceInterval]] = [:]) throws {
        let traceOrigin: ObservationTraceOrigin
        switch origin {
        case .human: traceOrigin = .human
        case .synthetic: traceOrigin = .synthetic
        case .automated, .unknown: throw ObservationTraceError.invalidPolicy
        }
        let scheduledKeys = try scheduledDays.map { day -> String in
            guard let value = try? ObservationObservedDate(date: day, timeZoneIdentifier: timeZoneIdentifier,
                                                           provenance: .userAssigned) else {
                throw ObservationTraceError.invalidDay
            }
            return value.dayKey
        }
        var matching: [String: [ObservationAcquisition]] = [:]
        var others: [String: [ObservationAcquisition]] = [:]
        var otherZone: [UUID] = []
        var undated: [UUID] = []
        for entry in archive.entries {
            guard let observed = entry.observedDate else { undated.append(entry.id); continue }
            guard observed.timeZoneIdentifier == timeZoneIdentifier else { otherZone.append(entry.id); continue }
            guard scheduledKeys.contains(observed.dayKey) else { continue }
            if entry.origin == origin { matching[observed.dayKey, default: []].append(entry) }
            else { others[observed.dayKey, default: []].append(entry) }
        }

        // One extraction saved as two observations is still one recording. Its dates are
        // excluded together: nothing says which date it belongs to.
        var datesByEvidenceID: [UUID: Int] = [:]
        for clips in matching.values where clips.count == 1 {
            if let id = clips[0].videoEvidence?.id { datesByEvidenceID[id, default: 0] += 1 }
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
            guard clips.count == 1, let entry = clips.first, let observed = entry.observedDate else {
                exclusions.append(.init(dayKey: key, reason: .duplicateDay)); continue
            }
            guard let evidence = entry.videoEvidence else {
                exclusions.append(.init(dayKey: key, reason: .noSampledEvidence)); continue
            }
            guard datesByEvidenceID[evidence.id] == 1 else {
                exclusions.append(.init(dayKey: key, reason: .repeatedRecording)); continue
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
            let trace = try ObservationTrace(id: evidence.id, durationSeconds: evidence.durationSeconds,
                capturedIntervals: declaredCapture[entry.id], origin: traceOrigin, samples: samples)
            days.append(try ObservationTraceDay(date: observed.date, timeZoneIdentifier: timeZoneIdentifier,
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
