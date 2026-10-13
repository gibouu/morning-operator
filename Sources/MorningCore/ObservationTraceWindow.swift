import Foundation

/// Assigning an imported trace to a day is a caller's explicit assertion, not a date inferred
/// from the movie's relative timestamps. A comparison key identifies the same planned scope.
public struct ObservationTraceDay: Sendable, Equatable {
    public let date: Date
    public let timeZoneIdentifier: String
    public let comparisonKey: String
    public let trace: ObservationTrace

    public init(date: Date, timeZoneIdentifier: String, comparisonKey: String, trace: ObservationTrace) throws {
        guard date.timeIntervalSince1970.isFinite, TimeZone(identifier: timeZoneIdentifier) != nil,
              !comparisonKey.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            throw ObservationTraceError.invalidDay
        }
        self.date = date
        self.timeZoneIdentifier = timeZoneIdentifier
        self.comparisonKey = comparisonKey
        self.trace = trace
    }
}

public struct ObservationComparisonPolicy: Encodable, Sendable, Equatable {
    public let expectedWindowSeconds: Double
    public let durationToleranceSeconds: Double
    public let maximumSampleGapSeconds: Double
    public init(expectedWindowSeconds: Double, durationToleranceSeconds: Double = 0,
                maximumSampleGapSeconds: Double) throws {
        guard expectedWindowSeconds.isFinite, expectedWindowSeconds > 0,
              durationToleranceSeconds.isFinite, durationToleranceSeconds >= 0,
              maximumSampleGapSeconds.isFinite, maximumSampleGapSeconds > 0 else {
            throw ObservationTraceError.invalidPolicy
        }
        self.expectedWindowSeconds = expectedWindowSeconds
        self.durationToleranceSeconds = durationToleranceSeconds
        self.maximumSampleGapSeconds = maximumSampleGapSeconds
    }
}

public enum ObservationDayExclusion: String, Encodable, Sendable {
    case differentComparison, differentOrigin, unknownOrigin, unknownCapture, partialCapture
    case differentDuration, insufficientSamples, unresolvedSamples, requestedTimestamps, sparseSamples
    /// The day shows a context key that another comparable day names differently.
    case conflictingContext
    /// Decided by the adapter that assigns saved evidence to days, before a trace exists:
    /// several recordings on one date, one recording saved on several dates, an assistant-run
    /// recording, a day with no sampled recording, or samples that cannot be read as one sequence.
    case duplicateDay, repeatedRecording, automatedOrigin, noSampledEvidence, unreadableSamples
}

public struct ObservationExcludedDay: Encodable, Equatable, Sendable {
    public let dayKey: String
    public let reason: ObservationDayExclusion
    public init(dayKey: String, reason: ObservationDayExclusion) {
        self.dayKey = dayKey
        self.reason = reason
    }
}

public struct ObservationMetricAverage: Encodable, Equatable, Sendable {
    public let mean: Double?
    public let minimum: Double?
    public let maximum: Double?
    public let daysWithEvidence: Int
    public let scheduledDayCount: Int
    public var daysWithoutEvidence: Int { max(0, scheduledDayCount - daysWithEvidence) }

    fileprivate init(values: [Double], scheduledDayCount: Int) {
        let total = values.reduce(0, +)
        self.mean = values.isEmpty || !total.isFinite ? nil : total / Double(values.count)
        self.minimum = values.min()
        self.maximum = values.max()
        self.daysWithEvidence = values.count
        self.scheduledDayCount = scheduledDayCount
    }
}

/// On how many comparable days something was seen. Days outside `daysWithEvidence` are
/// unknown, never days on which it did not happen.
public struct ObservationDayFrequency: Encodable, Equatable, Sendable {
    /// Comparable days on which it was seen, in date order.
    public let seenDayKeys: [String]
    /// Comparable days in the window: the sample size.
    public let daysWithEvidence: Int
    public let scheduledDayCount: Int
    public var seenDayCount: Int { seenDayKeys.count }
    public var daysWithoutEvidence: Int { max(0, scheduledDayCount - daysWithEvidence) }
}

/// The first context visible in the samples of a morning, not the first thing the person did.
public struct ObservationFirstContextSummary: Encodable, Equatable, Sendable {
    public let app: ObservationAppIdentity
    public let frequency: ObservationDayFrequency
}

/// One visible context followed by another in adjacent samples. A switch between two
/// samples is never seen, so this is not a complete app-switch history.
public struct ObservationContextTransitionSummary: Encodable, Equatable, Sendable {
    public let from: ObservationAppIdentity
    public let to: ObservationAppIdentity
    public let frequency: ObservationDayFrequency
}

public struct ObservationAppWindowSummary: Encodable, Equatable, Sendable {
    public let app: ObservationAppIdentity
    /// Mean of lower bounds on visible visits, not a measured mean of OS app openings.
    public let minimumVisibleVisits: ObservationMetricAverage
    /// Same-context sampled-span estimates only; not actual app-use or reading duration.
    public let sampledVisibleSecondsEstimate: ObservationMetricAverage
}

/// This small comparator deliberately refuses partial/unknown or incompatible windows.
/// It cannot turn four scripted sessions into a claim about four human mornings.
public struct ObservationTraceWindowReport: Encodable, Equatable, Sendable {
    public let comparisonKey: String
    public let timeZoneIdentifier: String
    public let policy: ObservationComparisonPolicy
    public let origin: ObservationTraceOrigin
    public let scheduledDayCount: Int
    public let missingDayKeys: [String]
    public let excludedDays: [ObservationExcludedDay]
    public let includedDayKeys: [String]
    public let includesSynthetic: Bool
    public let observationDurationSeconds: ObservationMetricAverage
    public let apps: [ObservationAppWindowSummary]
    /// Most frequent first; ties in context-key order.
    public let firstContexts: [ObservationFirstContextSummary]
    public let transitions: [ObservationContextTransitionSummary]

    /// `excluding` names scheduled days the caller already knows cannot be compared. They are
    /// reported as excluded, never as missing, and a day cannot be both supplied and excluded.
    public init(days: [ObservationTraceDay], scheduledDays: [Date], timeZoneIdentifier: String,
                comparisonKey: String, policy: ObservationComparisonPolicy,
                origin: ObservationTraceOrigin = .human,
                excluding knownExclusions: [ObservationExcludedDay] = []) throws {
        guard !comparisonKey.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
              origin != .unknown else {
            throw ObservationTraceError.invalidPolicy
        }
        guard TimeZone(identifier: timeZoneIdentifier) != nil else { throw ObservationTraceError.invalidDay }
        let scheduled = try scheduledDays.map { try Self.dayKey($0, timeZoneIdentifier: timeZoneIdentifier) }
        guard Set(scheduled).count == scheduled.count else { throw ObservationTraceError.duplicateDay }
        var records: [String: ObservationTraceDay] = [:]
        var traceIDs = Set<UUID>()
        for day in days {
            // Comparable mornings share an explicit calendar zone. Do not silently move a
            // travel record to another date or combine differently defined local mornings.
            guard day.timeZoneIdentifier == timeZoneIdentifier else { throw ObservationTraceError.incompatibleTimeZone }
            let key = try Self.dayKey(day.date, timeZoneIdentifier: day.timeZoneIdentifier)
            guard scheduled.contains(key) else { continue }
            // A caller must consolidate overlapping recordings, not silently double-count them.
            guard records[key] == nil else { throw ObservationTraceError.duplicateDay }
            // Reassigning the same clip to a second date does not create a second morning.
            guard traceIDs.insert(day.trace.id).inserted else { throw ObservationTraceError.duplicateTraceID }
            records[key] = day
        }
        var known: [String: ObservationDayExclusion] = [:]
        for exclusion in knownExclusions where scheduled.contains(exclusion.dayKey) {
            guard known[exclusion.dayKey] == nil, records[exclusion.dayKey] == nil else {
                throw ObservationTraceError.duplicateDay
            }
            known[exclusion.dayKey] = exclusion.reason
        }
        var included: [(String, ObservationTraceReport)] = []
        var missing: [String] = []
        var excluded: [ObservationExcludedDay] = []
        for key in scheduled.sorted() {
            if let reason = known[key] { excluded.append(.init(dayKey: key, reason: reason)); continue }
            guard let day = records[key] else { missing.append(key); continue }
            let report = try day.trace.report(maximumSampleGapSeconds: policy.maximumSampleGapSeconds)
            let reason: ObservationDayExclusion?
            if day.comparisonKey != comparisonKey { reason = .differentComparison }
            else if report.origin == .unknown { reason = .unknownOrigin }
            else if report.origin != origin { reason = .differentOrigin }
            else if report.capturedDurationSeconds == nil { reason = .unknownCapture }
            else if !report.captureIsComplete { reason = .partialCapture }
            else if abs(report.observationDurationSeconds - policy.expectedWindowSeconds) > policy.durationToleranceSeconds {
                reason = .differentDuration
            } else if report.distinctSampleMomentCount < 2 { reason = .insufficientSamples }
            else if report.unidentifiedMomentCount > 0 { reason = .unresolvedSamples }
            else if report.hasRequestedTimeFallback { reason = .requestedTimestamps }
            else if report.largestObservedSampleGapSeconds > policy.maximumSampleGapSeconds { reason = .sparseSamples }
            else { reason = nil }
            if let reason { excluded.append(.init(dayKey: key, reason: reason)) }
            else { included.append((key, report)) }
        }
        // One context key under two names cannot be averaged as one context, and nothing says
        // which day is right. Every day showing such a key is excluded, not the whole window.
        var names: [String: Set<String>] = [:]
        for (_, report) in included {
            for summary in report.apps { names[summary.app.key, default: []].insert(summary.app.displayName) }
        }
        let conflicting = Set(names.filter { $0.value.count > 1 }.keys)
        if !conflicting.isEmpty {
            let showsConflict = { (report: ObservationTraceReport) in report.apps.contains { conflicting.contains($0.app.key) } }
            excluded += included.filter { showsConflict($0.1) }.map { .init(dayKey: $0.0, reason: .conflictingContext) }
            excluded.sort { $0.dayKey < $1.dayKey }
            included.removeAll { showsConflict($0.1) }
        }
        var identities: [String: ObservationAppIdentity] = [:]
        for (_, report) in included {
            for summary in report.apps { identities[summary.app.key] = summary.app }
        }
        self.comparisonKey = comparisonKey
        self.timeZoneIdentifier = timeZoneIdentifier
        self.policy = policy
        self.origin = origin
        self.scheduledDayCount = scheduled.count
        self.missingDayKeys = missing
        self.excludedDays = excluded
        self.includedDayKeys = included.map { $0.0 }
        self.includesSynthetic = included.contains { $0.1.origin == .synthetic }
        self.observationDurationSeconds = .init(values: included.map { $0.1.observationDurationSeconds }, scheduledDayCount: scheduled.count)
        self.apps = identities.keys.sorted().compactMap { key in
            guard let identity = identities[key] else { return nil }
            // An absent app has a supported zero *minimum* visible visit count in an eligible
            // sampled window. That zero never asserts zero actual use between samples.
            let counts = included.map { Double($0.1.appSummary(key: key)?.minimumVisibleVisitCount ?? 0) }
            let durations = included.compactMap { $0.1.appSummary(key: key)?.sampledVisibleSecondsEstimate }
            return .init(app: identity,
                         minimumVisibleVisits: .init(values: counts, scheduledDayCount: scheduled.count),
                         sampledVisibleSecondsEstimate: .init(values: durations, scheduledDayCount: scheduled.count))
        }
        // A day counts once per first context or transition, however often it repeats that day.
        var firstDays: [String: [String]] = [:]
        var transitionDays: [[String]: [String]] = [:]
        for (key, report) in included {
            if let first = report.visits.first { firstDays[first.app.key, default: []].append(key) }
            let pairs = zip(report.visits, report.visits.dropFirst()).map { [$0.app.key, $1.app.key] }
            for pair in Set(pairs) { transitionDays[pair, default: []].append(key) }
        }
        func frequency(_ dayKeys: [String]) -> ObservationDayFrequency {
            .init(seenDayKeys: dayKeys, daysWithEvidence: included.count, scheduledDayCount: scheduled.count)
        }
        self.firstContexts = firstDays.sorted { ($1.value.count, $0.key) < ($0.value.count, $1.key) }.compactMap { entry in
            identities[entry.key].map { .init(app: $0, frequency: frequency(entry.value)) }
        }
        self.transitions = transitionDays.sorted {
            ($1.value.count, $0.key[0], $0.key[1]) < ($0.value.count, $1.key[0], $1.key[1])
        }.compactMap { entry in
            guard let from = identities[entry.key[0]], let to = identities[entry.key[1]] else { return nil }
            return .init(from: from, to: to, frequency: frequency(entry.value))
        }
    }

    private static func dayKey(_ date: Date, timeZoneIdentifier: String) throws -> String {
        guard date.timeIntervalSince1970.isFinite, let zone = TimeZone(identifier: timeZoneIdentifier) else {
            throw ObservationTraceError.invalidDay
        }
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = zone
        let parts = calendar.dateComponents([.year, .month, .day], from: date)
        guard let year = parts.year, let month = parts.month, let day = parts.day else {
            throw ObservationTraceError.invalidDay
        }
        return String(format: "%04d-%02d-%02d", year, month, day)
    }
}
