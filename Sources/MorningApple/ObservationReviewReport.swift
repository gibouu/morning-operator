import Foundation
import MorningCore

public enum ObservationReviewError: Error, Sendable, Equatable {
    case invalidPeriod
}

public enum ObservationReviewInterpretationState: String, Sendable, Equatable {
    // available means an attached result exists, not that inference succeeded.
    // Inspect classificationStatus and the actual recognized/unknown rows.
    case noVideo, unclassified, corrected, available, invalid
}

public enum ObservationReviewResolution: String, Sendable, Equatable {
    case recognized, ambiguous, unknown, conflicting
}

/// Who supplied the effective context; user review does not imply model success.
public enum ObservationReviewContextProvenance: String, Codable, Sendable, Equatable {
    case userReviewed, model, none
}

/// A source frame and its separately quoted interpretation, retained only in this
/// derived value. A visual label never establishes an installed app or an action.
public struct ObservationReviewSample: Identifiable, Sendable, Equatable {
    public let frame: ObservationFrameEvidence
    public let context: ObservationAppEvidence
    public let quote: String?
    public let frameReview: ObservationFrameReview?
    public let provenance: ObservationReviewContextProvenance
    public var id: UUID { frame.id }
    public var sampleID: UUID { frame.id }
    public var timeSeconds: Double { frame.timeSeconds }
    public var timeBasis: ObservationSampleTimeBasis { frame.timeBasis }
    public var outcome: ObservationSampleOutcome { frame.outcome }
    public var evidenceReference: String { frame.evidenceReference }
}

/// Equal effective timestamps form one moment. Individual source requests remain
/// inspectable; conflicting or incomplete claims never invent their ordering.
public struct ObservationReviewMoment: Identifiable, Sendable, Equatable {
    public let timeSeconds: Double
    public let samples: [ObservationReviewSample]
    public let resolvedContext: ObservationAppIdentity?
    public let resolution: ObservationReviewResolution
    public var id: UUID { samples[0].id }
    public var hasRequestedTimeFallback: Bool { samples.contains { $0.timeBasis == .requestedSamplingTime } }
}

/// Recomputed from one acquisition, never persisted or joined to a second movie.
/// `traceReport` always has unknown continuous coverage and no duration estimates.
public struct ObservationClipReview: Identifiable, Sendable, Equatable {
    public let acquisitionID: UUID
    public let observedDate: ObservationObservedDate?
    public let origin: ObservationAcquisitionOrigin
    public let sourceLabel: String
    public let durationSeconds: Double?
    public let classificationStatus: ObservationContextInferenceStatus?
    public let interpretationState: ObservationReviewInterpretationState
    public let hasCorrection: Bool
    /// False preserves source request order with unknown contexts; it must not be
    /// presented as a chronological activity sequence or used for visit arithmetic.
    public let timelineOrderIsValid: Bool
    public let rows: [ObservationReviewMoment]
    public let traceReport: ObservationTraceReport?
    public var id: UUID { acquisitionID }
    public var sampleCount: Int { rows.reduce(0) { $0 + $1.samples.count } }
    public var recognizedMomentCount: Int { rows.filter { $0.resolution == .recognized }.count }
    public var unknownMomentCount: Int { rows.count - recognizedMomentCount }

    public init(acquisition: ObservationAcquisition) throws {
        acquisitionID = acquisition.id; observedDate = acquisition.observedDate
        origin = acquisition.origin; sourceLabel = acquisition.sourceLabel
        durationSeconds = acquisition.videoEvidence?.durationSeconds
        classificationStatus = acquisition.classification?.status
        hasCorrection = acquisition.correctedText != nil
        guard let evidence = acquisition.videoEvidence else {
            interpretationState = .noVideo; timelineOrderIsValid = true; rows = []; traceReport = nil; return
        }
        timelineOrderIsValid = zip(evidence.frames, evidence.frames.dropFirst()).allSatisfy { $1.timeSeconds >= $0.timeSeconds }
        let state: ObservationReviewInterpretationState
        if !timelineOrderIsValid { state = .invalid }
        else if acquisition.correctedText != nil { state = .corrected }
        else if acquisition.classification != nil { state = .available }
        else if acquisition.warnings.contains(.invalidClassificationRemoved) || acquisition.warnings.contains(.invalidFrameReviewsRemoved) { state = .invalid }
        else { state = .unclassified }
        interpretationState = state
        let decisions = state == .available ? (acquisition.classification?.decisions ?? []) : []
        let byID = Dictionary(uniqueKeysWithValues: decisions.map { ($0.sampleID, $0) })
        let reviews = Dictionary(uniqueKeysWithValues: acquisition.frameReviews.map { ($0.sampleID, $0) })
        var effectiveDecisions: [ObservationFrameIdentityDecision] = []
        var groups: [[ObservationReviewSample]] = []
        for frame in evidence.frames {
            let decision = byID[frame.id]
            let review = reviews[frame.id]
            let context: ObservationAppEvidence
            let quote: String?
            let provenance: ObservationReviewContextProvenance
            if timelineOrderIsValid, acquisition.correctedText == nil, let review {
                context = review.contextIdentity.map { .identified(app: $0, reference: frame.evidenceReference) } ?? .unknown
                quote = review.evidenceQuote
                provenance = .userReviewed
            } else {
                context = decision?.evidence ?? .unknown
                quote = decision?.evidenceQuote
                provenance = decision == nil ? .none : .model
            }
            effectiveDecisions.append(.init(sampleID: frame.id, timeSeconds: frame.timeSeconds,
                timeBasis: frame.timeBasis, evidence: context, evidenceQuote: quote))
            let sample = ObservationReviewSample(frame: frame, context: context, quote: quote,
                                                frameReview: review, provenance: provenance)
            if groups.last?.first?.timeSeconds == frame.timeSeconds { groups[groups.count - 1].append(sample) }
            else { groups.append([sample]) }
        }
        let moments = groups.map { samples -> ObservationReviewMoment in
            let identities = samples.compactMap { Self.identity($0.context) }
            let signatures = Set(identities.map(ReviewIdentitySignature.init))
            let hasAmbiguous = samples.contains { if case .ambiguous = $0.context { true } else { false } }
            let resolution: ObservationReviewResolution
            if signatures.count == 1 && identities.count == samples.count { resolution = .recognized }
            else if !identities.isEmpty { resolution = .conflicting }
            else { resolution = hasAmbiguous ? .ambiguous : .unknown }
            return .init(timeSeconds: samples[0].timeSeconds, samples: samples,
                         resolvedContext: resolution == .recognized ? identities.first : nil, resolution: resolution)
        }
        rows = moments
        // Recheck exact citations for the effective model/user overlay. Original
        // acquisition classification remains unchanged and separately inspectable.
        guard timelineOrderIsValid else { traceReport = nil; return }
        let trace = try evidence.makeTrace(decisions: effectiveDecisions, origin: Self.traceOrigin(acquisition.origin))
        // Swift String equality permits canonical equivalence. Treat differing exact
        // label bytes at one timestamp as conflicting before asking the existing trace
        // algorithm for minimum visits. Never display a visit rejected by the rows.
        let resolvedIDs = Set(moments.filter { $0.resolution == .recognized }.flatMap { $0.samples.map(\.id) })
        let conservative = try ObservationTrace(id: trace.id, durationSeconds: trace.durationSeconds,
            capturedIntervals: nil, origin: trace.origin, samples: trace.samples.map { sample in
                .init(id: sample.id, timeSeconds: sample.timeSeconds, timeBasis: sample.timeBasis,
                      outcome: sample.outcome, appEvidence: resolvedIDs.contains(sample.id) ? sample.appEvidence : .unknown)
            })
        traceReport = try conservative.report(maximumSampleGapSeconds: 5)
    }

    private static func traceOrigin(_ origin: ObservationAcquisitionOrigin) -> ObservationTraceOrigin {
        switch origin { case .human: .human; case .synthetic: .synthetic; case .automated, .unknown: .unknown }
    }
    fileprivate static func identity(_ evidence: ObservationAppEvidence) -> ObservationAppIdentity? {
        if case .identified(let identity, _) = evidence { identity } else { nil }
    }
}

public struct ObservationReviewCitation: Identifiable, Sendable, Equatable {
    public let acquisitionID: UUID
    public let sampleID: UUID
    public let dayKey: String
    public let timeZoneIdentifier: String
    public let quote: String
    public let evidenceReference: String
    public let provenance: ObservationReviewContextProvenance
    public var id: String { "\(acquisitionID.uuidString)|\(sampleID.uuidString)" }
}

/// Positive appearances only. No absent day is converted to zero use, and a
/// context's presence in several recordings on one day still counts as one day.
public struct ObservationContextRecurrence: Identifiable, Sendable, Equatable {
    public let context: ObservationAppIdentity
    public let seenDayKeys: [String]
    public let citations: [ObservationReviewCitation]
    public var id: String { ReviewIdentitySignature(context).stableID }
    public var seenDayCount: Int { seenDayKeys.count }
}

public struct ObservationReviewDay: Identifiable, Sendable, Equatable {
    public let dayKey: String
    public let timeZoneIdentifier: String
    public let origin: ObservationAcquisitionOrigin
    public let clips: [ObservationClipReview]
    public var id: String { "\(timeZoneIdentifier)|\(origin.rawValue)|\(dayKey)" }
    public var hasRecognizedContext: Bool { clips.contains { $0.recognizedMomentCount > 0 } }
    public var hasUnknownMoments: Bool { clips.contains { $0.unknownMomentCount > 0 } }
    public var hasCorrection: Bool { clips.contains(where: \.hasCorrection) }
}

/// Each zone/origin is an independent evidence set. Seven date labels are a
/// diary range, not seven complete measurement windows or an average denominator.
public struct ObservationReviewPartition: Identifiable, Sendable, Equatable {
    public let timeZoneIdentifier: String
    public let origin: ObservationAcquisitionOrigin
    public let days: [ObservationReviewDay]
    public let recurrence: [ObservationContextRecurrence]
    public let conflictingContextKeys: [String]
    public var id: String { "\(timeZoneIdentifier)|\(origin.rawValue)" }
    public var observedDayCount: Int { days.filter { !$0.clips.isEmpty }.count }
    public var recognizedDayCount: Int { days.filter(\.hasRecognizedContext).count }
    public var missingDayKeys: [String] { days.filter { $0.clips.isEmpty }.map(\.dayKey) }
    /// Observed days with no recognized moment, including notes-only and failed/unavailable inference.
    public var unclassifiedDayKeys: [String] { days.filter { !$0.clips.isEmpty && !$0.hasRecognizedContext }.map(\.dayKey) }
    public var correctedDayKeys: [String] { days.filter(\.hasCorrection).map(\.dayKey) }
    public var daysWithUnknownMoments: [String] { days.filter(\.hasUnknownMoments).map(\.dayKey) }
    public var scheduledDayCount: Int { days.count }

    fileprivate init(zone: String, origin: ObservationAcquisitionOrigin,
                     dayKeys: [String], entries: [ObservationAcquisition]) throws {
        timeZoneIdentifier = zone; self.origin = origin
        days = try dayKeys.map { day in
            let clips = try entries.filter { $0.observedDate?.dayKey == day }
                .sorted { $0.id.uuidString < $1.id.uuidString }
                .map { try ObservationClipReview(acquisition: $0) }
            return .init(dayKey: day, timeZoneIdentifier: zone, origin: origin, clips: clips)
        }
        var identities: [ReviewIdentitySignature: ObservationAppIdentity] = [:]
        var namesByKey: [Data: Set<Data>] = [:]
        var citations: [ReviewIdentitySignature: [ObservationReviewCitation]] = [:]
        for day in days {
            for clip in day.clips {
                for row in clip.rows {
                    guard let identity = row.resolvedContext else { continue }
                    let signature = ReviewIdentitySignature(identity)
                    identities[signature] = identity
                    namesByKey[signature.key, default: []].insert(signature.label)
                    for sample in row.samples {
                        guard let quote = sample.quote else { continue }
                        citations[signature, default: []].append(.init(acquisitionID: clip.id, sampleID: sample.id,
                            dayKey: day.dayKey, timeZoneIdentifier: zone, quote: quote,
                            evidenceReference: sample.evidenceReference, provenance: sample.provenance))
                    }
                }
            }
        }
        let conflicting = Set(namesByKey.filter { $0.value.count > 1 }.map(\.key))
        conflictingContextKeys = conflicting.compactMap { String(data: $0, encoding: .utf8) }.sorted()
        recurrence = identities.keys.filter { !conflicting.contains($0.key) }.sorted { $0.stableID < $1.stableID }.map { signature in
            let references = (citations[signature] ?? []).sorted {
                $0.dayKey == $1.dayKey ? $0.id < $1.id : $0.dayKey < $1.dayKey
            }
            return .init(context: identities[signature]!, seenDayKeys: Array(Set(references.map(\.dayKey))).sorted(),
                         citations: references)
        }
    }
}

/// Pure, nonpersisted projection. Uses saved local date labels and exact saved
/// zones; never guesses a recording date from import time, PTS or a filename.
public struct ObservationReviewPeriod: Sendable, Equatable {
    public let dayKeys: [String]
    public let calendarTimeZoneIdentifier: String
    public let partitions: [ObservationReviewPartition]
    public let undatedAcquisitionIDs: [UUID]
    public var personalPartitions: [ObservationReviewPartition] { partitions.filter { $0.origin == .human } }

    public init(archive: ObservationArchive, endingOn date: Date,
                calendarTimeZoneIdentifier: String) throws {
        guard date.timeIntervalSince1970.isFinite,
              let zone = TimeZone(identifier: calendarTimeZoneIdentifier) else { throw ObservationReviewError.invalidPeriod }
        var calendar = Calendar(identifier: .gregorian); calendar.timeZone = zone
        let end = calendar.startOfDay(for: date)
        let keys = try (-6...0).map { offset -> String in
            guard let instant = calendar.date(byAdding: .day, value: offset, to: end) else { throw ObservationReviewError.invalidPeriod }
            let parts = calendar.dateComponents([.era, .year, .month, .day], from: instant)
            guard parts.era == 1, let year = parts.year, (1...9999).contains(year),
                  let month = parts.month, let day = parts.day else { throw ObservationReviewError.invalidPeriod }
            return String(format: "%04d-%02d-%02d", year, month, day)
        }
        dayKeys = keys; self.calendarTimeZoneIdentifier = calendarTimeZoneIdentifier
        undatedAcquisitionIDs = archive.entries.filter { $0.observedDate == nil }.map(\.id).sorted { $0.uuidString < $1.uuidString }
        let included = archive.entries.filter { $0.observedDate.map { keys.contains($0.dayKey) } ?? false }
        let groups = Dictionary(grouping: included) { "\($0.observedDate!.timeZoneIdentifier)|\($0.origin.rawValue)" }
        partitions = try groups.keys.sorted().map { key in
            let entries = groups[key]!
            return try ObservationReviewPartition(zone: entries[0].observedDate!.timeZoneIdentifier,
                origin: entries[0].origin, dayKeys: keys, entries: entries)
        }
    }
}

/// Byte identity avoids silently merging canonically equivalent but different
/// visible labels. It never normalizes a generic label into a known application.
private struct ReviewIdentitySignature: Hashable {
    let key: Data
    let label: Data
    init(_ identity: ObservationAppIdentity) { key = Data(identity.key.utf8); label = Data(identity.displayName.utf8) }
    var stableID: String { key.base64EncodedString() + ":" + label.base64EncodedString() }
}
