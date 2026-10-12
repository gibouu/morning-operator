import Foundation

public enum MorningHistoryError: Error, LocalizedError, Sendable, Equatable {
    case invalidTimeZone, invalidDate, unfinishedSession, invalidObservation
    public var errorDescription: String? {
        switch self {
        case .invalidTimeZone: String(localized: "The recorded time zone is not valid.", bundle: .module)
        case .invalidDate: String(localized: "The recorded date is not valid.", bundle: .module)
        case .unfinishedSession: String(localized: "Finish or stop the session before adding it to history.", bundle: .module)
        case .invalidObservation: String(localized: "Observation measurements must be nonnegative and match their coverage.", bundle: .module)
        }
    }
}

public enum RunTimingStatus: String, Codable, Sendable {
    case complete, notStarted, incomplete, invalid
}

private struct RunTiming: Sendable {
    var startedAt: Date?
    var endedAt: Date?
    var elapsed: TimeInterval?
    var active: TimeInterval?
    var paused: TimeInterval?
    var status: RunTimingStatus

    static func measure(_ session: RoutineSession) -> RunTiming {
        let start = session.events.first(where: { $0.kind == .started })?.occurredAt
        let end = session.events.last(where: { $0.kind == .completed || $0.kind == .stopped })?.occurredAt
        func unavailable(_ status: RunTimingStatus) -> RunTiming {
            RunTiming(startedAt: start, endedAt: end, status: status)
        }
        enum Phase { case ready, running, paused, ended }
        var phase = Phase.ready
        var activeStart: Date?
        var pauseStart: Date?
        var active = 0.0
        var paused = 0.0
        var previous: Date?
        for event in session.events {
            let date = event.occurredAt
            guard date.timeIntervalSince1970.isFinite,
                  previous.map({ date >= $0 }) ?? true else { return unavailable(.invalid) }
            previous = date
            switch event.kind {
            case .started:
                guard phase == .ready else { return unavailable(.invalid) }
                activeStart = date
                phase = .running
            case .paused:
                guard phase == .running, let began = activeStart else { return unavailable(.invalid) }
                active += date.timeIntervalSince(began)
                activeStart = nil
                pauseStart = date
                phase = .paused
            case .resumed:
                guard phase == .paused, let began = pauseStart else { return unavailable(.invalid) }
                paused += date.timeIntervalSince(began)
                pauseStart = nil
                activeStart = date
                phase = .running
            case .stepCompleted, .stepSkipped:
                guard phase == .running else { return unavailable(.invalid) }
            case .completed:
                guard phase == .running, session.status == .completed,
                      let began = activeStart else { return unavailable(.invalid) }
                active += date.timeIntervalSince(began)
                phase = .ended
            case .stopped:
                guard phase != .ended, session.status == .stopped else { return unavailable(.invalid) }
                if let began = activeStart { active += date.timeIntervalSince(began) }
                if let began = pauseStart { paused += date.timeIntervalSince(began) }
                phase = .ended
            }
        }
        guard phase == .ended, let end else { return unavailable(.incomplete) }
        guard let start else { return unavailable(.notStarted) }
        return RunTiming(startedAt: start, endedAt: end, elapsed: end.timeIntervalSince(start),
                         active: active, paused: paused, status: .complete)
    }
}

private enum HistoryCalendar {
    static func calendar(_ identifier: String) throws -> Calendar {
        guard let zone = TimeZone(identifier: identifier) else { throw MorningHistoryError.invalidTimeZone }
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = zone
        return calendar
    }
    static func dayKey(_ date: Date, timeZoneIdentifier: String) throws -> String {
        guard date.timeIntervalSince1970.isFinite else { throw MorningHistoryError.invalidDate }
        let calendar = try calendar(timeZoneIdentifier)
        let fields = calendar.dateComponents([.year, .month, .day], from: date)
        guard let year = fields.year, let month = fields.month, let day = fields.day else {
            throw MorningHistoryError.invalidDate
        }
        return String(format: "%04d-%02d-%02d", year, month, day)
    }
}

/// Archives actual app-session timing, not time spent in an external app.
/// Planned minutes remain separate from every measured duration.
public struct MorningRunRecord: Codable, Sendable, Identifiable, Equatable {
    public let session: RoutineSession
    public let timeZoneIdentifier: String
    public let recordedAt: Date
    public let isSynthetic: Bool
    /// Recovery left an unobserved timing gap; duration totals must remain unknown.
    public let timingInterrupted: Bool
    public let dayKey: String
    private let timing: RunTiming

    public init(session: RoutineSession, timeZoneIdentifier: String = TimeZone.current.identifier,
                recordedAt: Date = Date(), isSynthetic: Bool = false, timingInterrupted: Bool = false) throws {
        guard session.status == .completed || session.status == .stopped else {
            throw MorningHistoryError.unfinishedSession
        }
        guard recordedAt.timeIntervalSince1970.isFinite else { throw MorningHistoryError.invalidDate }
        var measured = RunTiming.measure(session)
        if timingInterrupted {
            measured.elapsed = nil
            measured.active = nil
            measured.paused = nil
            measured.status = .incomplete
        }
        let dayAnchor = measured.startedAt ?? measured.endedAt ?? recordedAt
        self.dayKey = try HistoryCalendar.dayKey(dayAnchor, timeZoneIdentifier: timeZoneIdentifier)
        self.session = session
        self.timeZoneIdentifier = timeZoneIdentifier
        self.recordedAt = recordedAt
        self.isSynthetic = isSynthetic
        self.timingInterrupted = timingInterrupted
        self.timing = measured
    }

    public var id: UUID { session.id }
    public var routine: RoutineVersion { session.routine }
    public var routineVersionID: UUID { routine.id }
    public var routineVersionNumber: Int { routine.number }
    public var sourceLabel: String { routine.sourceLabel }
    public var outcome: SessionStatus { session.status }
    public var startedAt: Date? { timing.startedAt }
    public var endedAt: Date? { timing.endedAt }
    public var plannedDurationMinutes: Int { routine.totalDurationMinutes }
    public var elapsedDurationSeconds: TimeInterval? { timing.elapsed }
    public var activeDurationSeconds: TimeInterval? { timing.active }
    public var pausedDurationSeconds: TimeInterval? { timing.paused }
    public var timingStatus: RunTimingStatus { timing.status }
    public var completedStepIDs: [UUID] { session.completedStepIDs }
    public var skippedStepIDs: [UUID] { session.skippedStepIDs }
    public var completedStepCount: Int { completedStepIDs.count }
    public var skippedStepCount: Int { skippedStepIDs.count }
    public var totalStepCount: Int { routine.steps.count }

    private enum CodingKeys: String, CodingKey { case session, timeZoneIdentifier, recordedAt, isSynthetic, timingInterrupted }
    public init(from decoder: any Decoder) throws {
        let values = try decoder.container(keyedBy: CodingKeys.self)
        try self.init(session: values.decode(RoutineSession.self, forKey: .session),
                      timeZoneIdentifier: values.decode(String.self, forKey: .timeZoneIdentifier),
                      recordedAt: values.decode(Date.self, forKey: .recordedAt),
                      isSynthetic: values.decodeIfPresent(Bool.self, forKey: .isSynthetic) ?? false,
                      timingInterrupted: values.decodeIfPresent(Bool.self, forKey: .timingInterrupted) ?? false)
    }
    public static func == (lhs: Self, rhs: Self) -> Bool {
        lhs.session == rhs.session && lhs.timeZoneIdentifier == rhs.timeZoneIdentifier
        && lhs.recordedAt == rhs.recordedAt && lhs.isSynthetic == rhs.isSynthetic
        && lhs.timingInterrupted == rhs.timingInterrupted
    }
}

public struct ObservedAppCounts: Codable, Sendable, Equatable {
    public let reelsViewed: Int?
    public let likes: Int?
    public let emailsRead: Int?
    public let emailsReplied: Int?
    public let emailsDiscarded: Int?
    public init(reelsViewed: Int? = nil, likes: Int? = nil, emailsRead: Int? = nil,
                emailsReplied: Int? = nil, emailsDiscarded: Int? = nil) {
        self.reelsViewed = reelsViewed
        self.likes = likes
        self.emailsRead = emailsRead
        self.emailsReplied = emailsReplied
        self.emailsDiscarded = emailsDiscarded
    }
    fileprivate var isValid: Bool {
        [reelsViewed, likes, emailsRead, emailsReplied, emailsDiscarded].allSatisfy { $0.map { $0 >= 0 } ?? true }
    }
}

public enum ObservationCoverage: String, Codable, Sendable {
    /// Complete only for the declared observation window, not necessarily the whole day.
    case completeWindow, partialWindow, unknown
}
public enum AppObservationProvenance: String, Codable, Sendable {
    case userReported, importedRecording, deviceCapture, providerRecord, syntheticDemo
}

/// One authoritative app/day snapshot. Repeated imports update the snapshot rather than sum it.
/// Collectors consolidate overlapping windows before constructing this daily record.
/// Counts require evidence; nil is unknown and zero means an explicitly observed zero.
public struct DailyAppObservation: Codable, Sendable, Identifiable, Equatable {
    public let id: UUID
    public let date: Date
    public let timeZoneIdentifier: String
    public let dayKey: String
    public let appName: String
    public let bundleIdentifier: String?
    public let counts: ObservedAppCounts
    public let observedDurationSeconds: TimeInterval?
    public let coveredSeconds: TimeInterval?
    public let expectedWindowSeconds: TimeInterval?
    public let coverage: ObservationCoverage
    public let provenance: AppObservationProvenance
    public let evidenceReferences: [String]
    public let updatedAt: Date

    public init(id: UUID = UUID(), date: Date, timeZoneIdentifier: String = TimeZone.current.identifier,
                appName: String, bundleIdentifier: String? = nil, counts: ObservedAppCounts = .init(),
                observedDurationSeconds: TimeInterval? = nil, coveredSeconds: TimeInterval? = nil,
                expectedWindowSeconds: TimeInterval? = nil, coverage: ObservationCoverage = .unknown,
                provenance: AppObservationProvenance, evidenceReferences: [String], updatedAt: Date = Date()) throws {
        let name = appName.trimmingCharacters(in: .whitespacesAndNewlines)
        let references = evidenceReferences.map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }.filter { !$0.isEmpty }
        let durations = [observedDurationSeconds, coveredSeconds, expectedWindowSeconds]
        guard !name.isEmpty, !references.isEmpty, counts.isValid,
              durations.allSatisfy({ $0.map { $0.isFinite && $0 >= 0 } ?? true }),
              updatedAt.timeIntervalSince1970.isFinite else { throw MorningHistoryError.invalidObservation }
        if let coveredSeconds, let expectedWindowSeconds, coveredSeconds > expectedWindowSeconds {
            throw MorningHistoryError.invalidObservation
        }
        if let observedDurationSeconds, let coveredSeconds, observedDurationSeconds > coveredSeconds {
            throw MorningHistoryError.invalidObservation
        }
        self.dayKey = try HistoryCalendar.dayKey(date, timeZoneIdentifier: timeZoneIdentifier)
        self.id = id
        self.date = date
        self.timeZoneIdentifier = timeZoneIdentifier
        self.appName = name
        let trimmedIdentifier = bundleIdentifier?.trimmingCharacters(in: .whitespacesAndNewlines)
        self.bundleIdentifier = trimmedIdentifier.nilIfEmpty
        self.counts = counts
        self.observedDurationSeconds = observedDurationSeconds
        self.coveredSeconds = coveredSeconds
        self.expectedWindowSeconds = expectedWindowSeconds
        self.coverage = coverage
        self.provenance = provenance
        self.evidenceReferences = references
        self.updatedAt = updatedAt
    }
    public var isSynthetic: Bool { provenance == .syntheticDemo }
    public var appIdentifier: String { bundleIdentifier ?? appName.lowercased() }
    fileprivate var snapshotKey: String { "\(dayKey)|\(appIdentifier)|\(isSynthetic)" }

    private enum CodingKeys: String, CodingKey {
        case id, date, timeZoneIdentifier, appName, bundleIdentifier, counts, observedDurationSeconds
        case coveredSeconds, expectedWindowSeconds, coverage, provenance, evidenceReferences, updatedAt
    }
    public init(from decoder: any Decoder) throws {
        let values = try decoder.container(keyedBy: CodingKeys.self)
        try self.init(id: values.decode(UUID.self, forKey: .id), date: values.decode(Date.self, forKey: .date),
                      timeZoneIdentifier: values.decode(String.self, forKey: .timeZoneIdentifier),
                      appName: values.decode(String.self, forKey: .appName),
                      bundleIdentifier: values.decodeIfPresent(String.self, forKey: .bundleIdentifier),
                      counts: values.decode(ObservedAppCounts.self, forKey: .counts),
                      observedDurationSeconds: values.decodeIfPresent(Double.self, forKey: .observedDurationSeconds),
                      coveredSeconds: values.decodeIfPresent(Double.self, forKey: .coveredSeconds),
                      expectedWindowSeconds: values.decodeIfPresent(Double.self, forKey: .expectedWindowSeconds),
                      coverage: values.decode(ObservationCoverage.self, forKey: .coverage),
                      provenance: values.decode(AppObservationProvenance.self, forKey: .provenance),
                      evidenceReferences: values.decode([String].self, forKey: .evidenceReferences),
                      updatedAt: values.decode(Date.self, forKey: .updatedAt))
    }
}

private extension Optional where Wrapped == String {
    var nilIfEmpty: String? { flatMap { $0.isEmpty ? nil : $0 } }
}

public struct CountSummary: Codable, Sendable, Equatable {
    public let total: Int?
    public let daysWithEvidence: Int
    public let windowDayCount: Int
    public var daysMissingEvidence: Int { max(0, windowDayCount - daysWithEvidence) }
    public var averagePerEvidenceDay: Double? {
        guard let total, daysWithEvidence > 0 else { return nil }
        return Double(total) / Double(daysWithEvidence)
    }
    fileprivate init(values: [Int?], windowDayCount: Int) {
        let known = values.compactMap { $0 }
        // Refuse an unrepresentable sum instead of overflowing or inventing a count.
        var sum = 0
        var valid = true
        for value in known {
            let result = sum.addingReportingOverflow(value)
            if result.overflow { valid = false; break }
            sum = result.partialValue
        }
        total = known.isEmpty || !valid ? nil : sum
        daysWithEvidence = known.count
        self.windowDayCount = windowDayCount
    }
}

public struct AppUsageSummary: Codable, Sendable, Identifiable, Equatable {
    public let appIdentifier: String
    public let appName: String
    public let observedDayCount: Int
    public let completeWindowDayCount: Int
    public let partialWindowDayCount: Int
    public let unknownCoverageDayCount: Int
    public let daysWithDurationEvidence: Int
    public let totalObservedDurationSeconds: TimeInterval?
    public let reelsViewed: CountSummary
    public let likes: CountSummary
    public let emailsRead: CountSummary
    public let emailsReplied: CountSummary
    public let emailsDiscarded: CountSummary
    public let provenances: [AppObservationProvenance]
    public var id: String { appIdentifier }
    public var averageObservedDurationSeconds: TimeInterval? {
        guard let totalObservedDurationSeconds, daysWithDurationEvidence > 0 else { return nil }
        return totalObservedDurationSeconds / Double(daysWithDurationEvidence)
    }
    fileprivate init(observations: [DailyAppObservation], windowDayCount: Int) {
        appIdentifier = observations[0].appIdentifier
        appName = observations[0].appName
        observedDayCount = observations.count
        completeWindowDayCount = observations.filter { $0.coverage == .completeWindow }.count
        partialWindowDayCount = observations.filter { $0.coverage == .partialWindow }.count
        unknownCoverageDayCount = observations.filter { $0.coverage == .unknown }.count
        let durations = observations.compactMap(\.observedDurationSeconds)
        daysWithDurationEvidence = durations.count
        totalObservedDurationSeconds = durations.isEmpty ? nil : durations.reduce(0, +)
        reelsViewed = CountSummary(values: observations.map(\.counts.reelsViewed), windowDayCount: windowDayCount)
        likes = CountSummary(values: observations.map(\.counts.likes), windowDayCount: windowDayCount)
        emailsRead = CountSummary(values: observations.map(\.counts.emailsRead), windowDayCount: windowDayCount)
        emailsReplied = CountSummary(values: observations.map(\.counts.emailsReplied), windowDayCount: windowDayCount)
        emailsDiscarded = CountSummary(values: observations.map(\.counts.emailsDiscarded), windowDayCount: windowDayCount)
        provenances = Array(Set(observations.map(\.provenance))).sorted { $0.rawValue < $1.rawValue }
    }
}

public struct MorningDaySummary: Codable, Sendable, Identifiable, Equatable {
    public let dayKey: String
    public let date: Date
    public let timeZoneIdentifier: String
    public let runs: [MorningRunRecord]
    public let appObservations: [DailyAppObservation]
    public var id: String { dayKey }
    public var runCount: Int { runs.count }
    public var timedRunCount: Int { runs.filter { $0.activeDurationSeconds != nil }.count }
    public var hasEvidence: Bool { !runs.isEmpty || !appObservations.isEmpty }
    public var totalActiveDurationSeconds: TimeInterval? {
        let durations = runs.compactMap(\.activeDurationSeconds)
        return durations.isEmpty ? nil : durations.reduce(0, +)
    }
    public var averageActiveDurationSeconds: TimeInterval? {
        guard let totalActiveDurationSeconds, timedRunCount > 0 else { return nil }
        return totalActiveDurationSeconds / Double(timedRunCount)
    }
}

public struct SevenDaySummary: Codable, Sendable, Equatable {
    public let days: [MorningDaySummary]
    public let timeZoneIdentifier: String
    public let apps: [AppUsageSummary]
    public let includesSyntheticData: Bool
    public var windowDayCount: Int { days.count }
    public var recordedDayCount: Int { days.filter(\.hasEvidence).count }
    public var missingDayCount: Int { windowDayCount - recordedDayCount }
    public var runCount: Int { days.reduce(0) { $0 + $1.runCount } }
    public var timedRunCount: Int { days.reduce(0) { $0 + $1.timedRunCount } }
    public var completedRunCount: Int { days.flatMap(\.runs).filter { $0.outcome == .completed }.count }
    public var stoppedRunCount: Int { days.flatMap(\.runs).filter { $0.outcome == .stopped }.count }
    public var sourceTimeZoneIdentifiers: [String] {
        Array(Set(days.flatMap { $0.runs.map(\.timeZoneIdentifier) + $0.appObservations.map(\.timeZoneIdentifier) })).sorted()
    }
    public var totalActiveDurationSeconds: TimeInterval? {
        let known = days.compactMap(\.totalActiveDurationSeconds)
        return known.isEmpty ? nil : known.reduce(0, +)
    }
    /// Denominator is timedRunCount, never seven missing-data-filled calendar days.
    public var averageActiveDurationSeconds: TimeInterval? {
        guard let totalActiveDurationSeconds, timedRunCount > 0 else { return nil }
        return totalActiveDurationSeconds / Double(timedRunCount)
    }
    public var averagePlannedDurationMinutes: Double? {
        let planned = days.flatMap(\.runs).map { Double($0.plannedDurationMinutes) }
        return planned.isEmpty ? nil : planned.reduce(0, +) / Double(planned.count)
    }
}

/// Pure value storage; the application remains the only persistence writer.
/// Dates are grouped by each record's captured local day, preserving a travel diary's original dates.
public struct MorningHistory: Codable, Sendable, Equatable {
    public private(set) var runs: [MorningRunRecord]
    public private(set) var appObservations: [DailyAppObservation]
    public init(runs: [MorningRunRecord] = [], appObservations: [DailyAppObservation] = []) {
        self.runs = []
        self.appObservations = []
        for run in runs { upsert(run) }
        for observation in appObservations { upsert(observation) }
    }
    public mutating func upsert(_ run: MorningRunRecord) {
        if let index = runs.firstIndex(where: { $0.id == run.id }) { runs[index] = run }
        else { runs.append(run) }
        runs.sort { ($0.startedAt ?? $0.endedAt ?? $0.recordedAt) < ($1.startedAt ?? $1.endedAt ?? $1.recordedAt) }
    }
    public mutating func upsert(_ observation: DailyAppObservation) {
        if let index = appObservations.firstIndex(where: { $0.snapshotKey == observation.snapshotKey }) {
            guard observation.updatedAt >= appObservations[index].updatedAt else { return }
            appObservations[index] = observation
        } else { appObservations.append(observation) }
        appObservations.sort { $0.dayKey == $1.dayKey ? $0.appIdentifier < $1.appIdentifier : $0.dayKey < $1.dayKey }
    }
    public func day(containing date: Date, timeZoneIdentifier: String = TimeZone.current.identifier,
                    includingSynthetic: Bool = false) throws -> MorningDaySummary {
        let key = try HistoryCalendar.dayKey(date, timeZoneIdentifier: timeZoneIdentifier)
        let calendar = try HistoryCalendar.calendar(timeZoneIdentifier)
        return MorningDaySummary(dayKey: key, date: calendar.startOfDay(for: date), timeZoneIdentifier: timeZoneIdentifier,
                                 runs: runs.filter { $0.dayKey == key && (includingSynthetic || !$0.isSynthetic) },
                                 appObservations: appObservations.filter { $0.dayKey == key && (includingSynthetic || !$0.isSynthetic) })
    }
    public func sevenDaySummary(endingOn date: Date, timeZoneIdentifier: String = TimeZone.current.identifier,
                                includingSynthetic: Bool = false) throws -> SevenDaySummary {
        let calendar = try HistoryCalendar.calendar(timeZoneIdentifier)
        guard date.timeIntervalSince1970.isFinite else { throw MorningHistoryError.invalidDate }
        let end = calendar.startOfDay(for: date)
        let days = try (-6...0).map { offset in
            guard let date = calendar.date(byAdding: .day, value: offset, to: end) else { throw MorningHistoryError.invalidDate }
            return try day(containing: date, timeZoneIdentifier: timeZoneIdentifier, includingSynthetic: includingSynthetic)
        }
        let observations = days.flatMap(\.appObservations)
        // In demo-inclusive views, prefer the real daily snapshot when both exist.
        var unique: [String: DailyAppObservation] = [:]
        for observation in observations {
            let key = "\(observation.dayKey)|\(observation.appIdentifier)"
            if let prior = unique[key], !prior.isSynthetic && observation.isSynthetic { continue }
            unique[key] = observation
        }
        let grouped = Dictionary(grouping: Array(unique.values), by: \.appIdentifier)
        let apps = grouped.values.map { AppUsageSummary(observations: $0.sorted { $0.dayKey < $1.dayKey }, windowDayCount: 7) }
            .sorted { $0.appName.localizedCaseInsensitiveCompare($1.appName) == .orderedAscending }
        return SevenDaySummary(days: days, timeZoneIdentifier: timeZoneIdentifier, apps: apps,
                               includesSyntheticData: days.contains { $0.runs.contains(where: \.isSynthetic) || $0.appObservations.contains(where: \.isSynthetic) })
    }
    private enum CodingKeys: String, CodingKey { case runs, appObservations }
    public init(from decoder: any Decoder) throws {
        let values = try decoder.container(keyedBy: CodingKeys.self)
        self.init(runs: try values.decodeIfPresent([MorningRunRecord].self, forKey: .runs) ?? [],
                  appObservations: try values.decodeIfPresent([DailyAppObservation].self, forKey: .appObservations) ?? [])
    }
}
