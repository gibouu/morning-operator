import Foundation

public enum ObservationTraceError: Error, Equatable, Sendable {
    case invalidDuration, invalidCoverage, invalidTimestamp, unorderedSamples, duplicateSampleID
    case invalidAppEvidence, conflictingAppIdentity, invalidPolicy, invalidDay, duplicateDay, duplicateTraceID, incompatibleTimeZone
}

/// A stable context identity supplied by an evidence adapter. A visual label is not proof of
/// an installed bundle identifier, and this value does not grant access to an application.
public struct ObservationAppIdentity: Codable, Hashable, Sendable {
    public let key: String
    public let displayName: String
    public init(key: String, displayName: String) {
        self.key = key
        self.displayName = displayName
    }
}

public enum ObservationAppEvidence: Codable, Equatable, Sendable {
    case identified(app: ObservationAppIdentity, reference: String)
    case ambiguous(reference: String)
    case unknown

    fileprivate var app: ObservationAppIdentity? {
        if case .identified(let app, _) = self { return app }
        return nil
    }
}

public enum ObservationSampleOutcome: String, Codable, Sendable {
    case observed, blank, decodeFailed, ocrFailed
}

public enum ObservationSampleTimeBasis: String, Codable, Sendable {
    case mediaPresentation, requestedSamplingTime
}

/// One ordered sample before text deduplication. References point to retained source evidence;
/// the core validates structure, not whether OCR or a model identified the screen correctly.
public struct ObservationTraceSample: Codable, Identifiable, Equatable, Sendable {
    public let id: UUID
    public let timeSeconds: Double
    public let timeBasis: ObservationSampleTimeBasis
    public let outcome: ObservationSampleOutcome
    public let appEvidence: ObservationAppEvidence

    public init(id: UUID = UUID(), timeSeconds: Double,
                timeBasis: ObservationSampleTimeBasis = .mediaPresentation,
                outcome: ObservationSampleOutcome = .observed,
                appEvidence: ObservationAppEvidence = .unknown) {
        self.id = id
        self.timeSeconds = timeSeconds
        self.timeBasis = timeBasis
        self.outcome = outcome
        self.appEvidence = appEvidence
    }
}

public struct ObservationTraceInterval: Codable, Equatable, Sendable {
    public let startSeconds: Double
    public let endSeconds: Double
    public init(startSeconds: Double, endSeconds: Double) {
        self.startSeconds = startSeconds
        self.endSeconds = endSeconds
    }
    public var durationSeconds: Double { endSeconds - startSeconds }
}

public enum ObservationTraceOrigin: String, Codable, Sendable {
    case human, synthetic, unknown
}

/// Media times are relative to this trace. No wall-clock capture start is invented.
/// `capturedIntervals == nil` means capture coverage is unknown; an empty array means no
/// supported captured interval. Even complete capture is not continuous semantic analysis.
public struct ObservationTrace: Codable, Identifiable, Equatable, Sendable {
    public let id: UUID
    public let durationSeconds: Double
    public let capturedIntervals: [ObservationTraceInterval]?
    public let origin: ObservationTraceOrigin
    public let samples: [ObservationTraceSample]

    public init(id: UUID = UUID(), durationSeconds: Double,
                capturedIntervals: [ObservationTraceInterval]?,
                origin: ObservationTraceOrigin, samples: [ObservationTraceSample]) throws {
        guard durationSeconds.isFinite, durationSeconds > 0 else { throw ObservationTraceError.invalidDuration }
        var intervalEnd = 0.0
        for interval in capturedIntervals ?? [] {
            guard interval.startSeconds.isFinite, interval.endSeconds.isFinite,
                  interval.startSeconds >= intervalEnd, interval.endSeconds > interval.startSeconds,
                  interval.endSeconds <= durationSeconds else { throw ObservationTraceError.invalidCoverage }
            intervalEnd = interval.endSeconds
        }
        var ids = Set<UUID>()
        var previousTime = 0.0
        var names: [String: String] = [:]
        for sample in samples {
            guard ids.insert(sample.id).inserted else { throw ObservationTraceError.duplicateSampleID }
            guard sample.timeSeconds.isFinite, sample.timeSeconds >= 0,
                  sample.timeSeconds <= durationSeconds else { throw ObservationTraceError.invalidTimestamp }
            guard sample.timeSeconds >= previousTime else { throw ObservationTraceError.unorderedSamples }
            previousTime = sample.timeSeconds
            switch sample.appEvidence {
            case .identified(let app, let reference):
                guard sample.outcome == .observed, !app.key.trimmed.isEmpty,
                      !app.displayName.trimmed.isEmpty, !reference.trimmed.isEmpty else {
                    throw ObservationTraceError.invalidAppEvidence
                }
                if let name = names[app.key], name != app.displayName {
                    throw ObservationTraceError.conflictingAppIdentity
                }
                names[app.key] = app.displayName
            case .ambiguous(let reference):
                guard sample.outcome == .observed, !reference.trimmed.isEmpty else {
                    throw ObservationTraceError.invalidAppEvidence
                }
            case .unknown: break
            }
        }
        self.id = id
        self.durationSeconds = durationSeconds
        self.capturedIntervals = capturedIntervals
        self.origin = origin
        self.samples = samples
    }

    private enum CodingKeys: String, CodingKey { case id, durationSeconds, capturedIntervals, origin, samples }
    public init(from decoder: any Decoder) throws {
        let values = try decoder.container(keyedBy: CodingKeys.self)
        try self.init(id: values.decode(UUID.self, forKey: .id),
                      durationSeconds: values.decode(Double.self, forKey: .durationSeconds),
                      capturedIntervals: values.decodeIfPresent([ObservationTraceInterval].self, forKey: .capturedIntervals),
                      origin: values.decode(ObservationTraceOrigin.self, forKey: .origin),
                      samples: values.decode([ObservationTraceSample].self, forKey: .samples))
    }
}

/// First/last *observations* of a visible visit, not a continuous app-use interval. Unknown
/// samples do not manufacture a departure or return. A→unknown→A remains one minimum visit.
public struct ObservationVisibleVisit: Encodable, Equatable, Sendable {
    public let app: ObservationAppIdentity
    public let firstSampleSeconds: Double
    public fileprivate(set) var lastSampleSeconds: Double
    public fileprivate(set) var sampleIDs: [UUID]
}

public struct ObservationAppTraceSummary: Encodable, Equatable, Sendable {
    public let app: ObservationAppIdentity
    /// Includes a context already visible at the start. This is NOT an OS app-open count.
    public let minimumVisibleVisitCount: Int
    public var minimumVisibleReturnCount: Int { max(0, minimumVisibleVisitCount - 1) }
    /// Sum of same-context adjacent sample spans under the explicit maximum-gap assumption.
    /// This is an estimate, never measured usage, dwell, reading or a proven duration bound.
    public let sampledVisibleSecondsEstimate: Double?
    public let durationEvidenceSampleIDs: [UUID]
}

/// A derived report is encoded for review and recomputed from its validated trace on reload.
/// It deliberately has no swipe, scroll, read, reply, pickup or exact app-open count fields.
public struct ObservationTraceReport: Encodable, Equatable, Sendable {
    public let traceID: UUID
    public let origin: ObservationTraceOrigin
    public let observationDurationSeconds: Double
    public let capturedDurationSeconds: Double?
    public let captureIsComplete: Bool
    public let sampleCount: Int
    public let distinctSampleMomentCount: Int
    public let unidentifiedMomentCount: Int
    public let hasRequestedTimeFallback: Bool
    public let maximumSampleGapSeconds: Double
    public let largestObservedSampleGapSeconds: Double
    public let visits: [ObservationVisibleVisit]
    public let apps: [ObservationAppTraceSummary]
    /// Captured time not assigned even by the estimate. Nil when capture coverage is unknown.
    public let unassignedCapturedSeconds: Double?

    public func appSummary(key: String) -> ObservationAppTraceSummary? { apps.first { $0.app.key == key } }
}

extension ObservationTrace {
    /// The gap limit is an explicit analysis assumption, not a guarantee against unseen switches.
    public func report(maximumSampleGapSeconds: Double) throws -> ObservationTraceReport {
        guard maximumSampleGapSeconds.isFinite, maximumSampleGapSeconds > 0 else {
            throw ObservationTraceError.invalidPolicy
        }
        let moments = groupedMoments
        var visits: [ObservationVisibleVisit] = []
        for moment in moments {
            guard let app = moment.app else { continue }
            if visits.last?.app == app {
                visits[visits.count - 1].lastSampleSeconds = moment.time
                visits[visits.count - 1].sampleIDs += moment.ids
            } else {
                visits.append(.init(app: app, firstSampleSeconds: moment.time,
                                    lastSampleSeconds: moment.time, sampleIDs: moment.ids))
            }
        }
        var estimatedSeconds: [String: Double] = [:]
        var timeReferences: [String: [UUID]] = [:]
        var largestGap = moments.first?.time ?? durationSeconds
        for (before, after) in zip(moments, moments.dropFirst()) {
            let gap = after.time - before.time
            largestGap = max(largestGap, gap)
            guard let app = before.app, after.app == app, before.actualTime, after.actualTime,
                  gap > 0, gap <= maximumSampleGapSeconds,
                  covers(start: before.time, end: after.time) else { continue }
            estimatedSeconds[app.key, default: 0] += gap
            timeReferences[app.key, default: []] += before.ids + after.ids
        }
        if let last = moments.last { largestGap = max(largestGap, durationSeconds - last.time) }
        let byApp = Dictionary(grouping: visits, by: { $0.app.key })
        let appSummaries = byApp.keys.sorted().compactMap { key -> ObservationAppTraceSummary? in
            guard let items = byApp[key], let app = items.first?.app else { return nil }
            var seen = Set<UUID>()
            return .init(app: app, minimumVisibleVisitCount: items.count,
                         sampledVisibleSecondsEstimate: estimatedSeconds[key],
                         durationEvidenceSampleIDs: (timeReferences[key] ?? []).filter { seen.insert($0).inserted })
        }
        let capturedSeconds = capturedIntervals.map { $0.reduce(0) { $0 + $1.durationSeconds } }
        let assignedEstimate = estimatedSeconds.values.reduce(0, +)
        return ObservationTraceReport(
            traceID: id, origin: origin, observationDurationSeconds: durationSeconds,
            capturedDurationSeconds: capturedSeconds, captureIsComplete: covers(start: 0, end: durationSeconds),
            sampleCount: samples.count, distinctSampleMomentCount: moments.count,
            unidentifiedMomentCount: moments.filter { $0.app == nil }.count,
            hasRequestedTimeFallback: samples.contains { $0.timeBasis == .requestedSamplingTime },
            maximumSampleGapSeconds: maximumSampleGapSeconds, largestObservedSampleGapSeconds: largestGap,
            visits: visits, apps: appSummaries,
            unassignedCapturedSeconds: capturedSeconds.map { max(0, $0 - assignedEstimate) })
    }

    private struct Moment {
        let time: Double
        let app: ObservationAppIdentity?
        let ids: [UUID]
        let actualTime: Bool
    }

    private var groupedMoments: [Moment] {
        var groups: [[ObservationTraceSample]] = []
        for sample in samples {
            if groups.last?.first?.timeSeconds == sample.timeSeconds {
                groups[groups.count - 1].append(sample)
            } else { groups.append([sample]) }
        }
        return groups.compactMap { group in
            guard let first = group.first else { return nil }
            let app = first.appEvidence.app
            // Conflicting or unknown claims at one time are unresolved, never an invented order.
            let agreement = app != nil && group.allSatisfy { $0.appEvidence.app == app }
            return Moment(time: first.timeSeconds, app: agreement ? app : nil,
                          ids: group.map(\.id), actualTime: group.allSatisfy { $0.timeBasis == .mediaPresentation })
        }
    }

    private func covers(start: Double, end: Double) -> Bool {
        guard let capturedIntervals else { return false }
        var coveredThrough = start
        for interval in capturedIntervals {
            if interval.endSeconds <= coveredThrough { continue }
            guard interval.startSeconds <= coveredThrough else { return false }
            coveredThrough = interval.endSeconds
            if coveredThrough >= end { return true }
        }
        return false
    }
}

private extension String {
    var trimmed: String { trimmingCharacters(in: .whitespacesAndNewlines) }
}
