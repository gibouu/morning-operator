import Foundation

/// Provenance of an archived observation. Only a human source contributes to the
/// personal day summary; test automation, demos and unmarked sources stay excluded.
public enum MorningInlineDayEvidenceOrigin: String, Sendable, Equatable {
    case human, synthetic, automated, unknown
}

/// Date metadata only: no source text and no ability to start or change a routine.
/// An absent observed date stays undated, regardless of when a file was imported.
public struct MorningInlineDayEvidence: Sendable, Equatable, Identifiable {
    public let id: UUID
    public let observedAt: Date?
    public let timeZoneIdentifier: String?
    public let dayKey: String?
    public let origin: MorningInlineDayEvidenceOrigin

    public init(id: UUID, observedAt: Date?, timeZoneIdentifier: String?,
                origin: MorningInlineDayEvidenceOrigin) throws {
        if let observedAt {
            guard let timeZoneIdentifier else { throw MorningHistoryError.invalidTimeZone }
            self.dayKey = try InlineDayDate.key(observedAt, timeZoneIdentifier: timeZoneIdentifier)
            self.timeZoneIdentifier = timeZoneIdentifier
        } else {
            self.dayKey = nil
            self.timeZoneIdentifier = nil
        }
        self.id = id
        self.observedAt = observedAt
        self.origin = origin
    }
}

/// Calendar arithmetic for a browsable strip. It has no oldest-day cutoff and never
/// yields a future day. A seven-day page shifts earlier when it reaches today.
public struct MorningInlineDayCalendar: Sendable {
    public let calendar: Calendar
    public let today: Date

    public init(today: Date = Date(), calendar: Calendar = .current) throws {
        try InlineDayDate.validate(today)
        self.calendar = calendar
        self.today = calendar.startOfDay(for: today)
    }

    public func clamped(_ date: Date) throws -> Date {
        try InlineDayDate.validate(date)
        return min(calendar.startOfDay(for: date), today)
    }

    public func day(offset: Int, from date: Date) throws -> Date {
        let start = try clamped(date)
        guard let result = calendar.date(byAdding: .day, value: offset, to: start) else {
            throw MorningHistoryError.invalidDate
        }
        return try clamped(result)
    }

    /// Keep a browsed civil date stable when the display zone changes. A selection
    /// that was today follows actual today in the new zone instead. The caller passes
    /// the same current instant used to construct this value, not a midnight anchor.
    public func rebasedSelection(_ selection: Date, from previousCalendar: Calendar,
                                 at now: Date) throws -> Date {
        try InlineDayDate.validate(selection)
        try InlineDayDate.validate(now)
        if previousCalendar.isDate(selection, inSameDayAs: now) {
            return try clamped(now)
        }
        let fields: Set<Calendar.Component> = [.era, .year, .month, .day]
        let components = previousCalendar.dateComponents(fields, from: selection)
        guard let rebased = calendar.date(from: components),
              calendar.dateComponents(fields, from: rebased) == components else {
            // A whole civil day can be absent when a zone crosses the date line.
            // Refuse that date rather than silently select a different saved day.
            throw MorningHistoryError.invalidDate
        }
        return try clamped(rebased)
    }

    public func days(around date: Date) throws -> [Date] {
        let end = try day(offset: 3, from: date)
        return try (-6...0).map { try day(offset: $0, from: end) }
    }
}

public enum MorningInlineDayState: Sendable, Equatable {
    /// At least one real archived session reached its completed outcome.
    case completed
    /// A real archived session was stopped. It may have stopped before any step.
    case partial
    /// Saved observations exist, without an archived completed or stopped run.
    case evidenceOnly
    /// No dated personal run or observation is saved for this day.
    case noSavedEvidence
}

/// A read-only projection of the selected local date, preserving each source's saved
/// Gregorian day key and zone when the person travels. Observations never establish
/// that a routine ran, nor establish full-day coverage. No routine version is selected.
public struct MorningInlineDaySnapshot: Sendable, Equatable {
    public let date: Date
    public let dayKey: String
    public let isToday: Bool
    public let state: MorningInlineDayState
    public let completedRuns: [MorningRunRecord]
    public let stoppedRuns: [MorningRunRecord]
    public let appObservations: [DailyAppObservation]
    public let observations: [MorningInlineDayEvidence]
    /// Personal observations with no assigned observed day, across the whole archive.
    /// This is not evidence for the selected day and must be labelled as unassigned.
    public let undatedObservationCount: Int
    public let sourceTimeZoneIdentifiers: [String]

    public init(selectedDate: Date, today: Date = Date(), calendar: Calendar = .current,
                history: MorningHistory = .init(), observations: [MorningInlineDayEvidence] = []) throws {
        let navigation = try MorningInlineDayCalendar(today: today, calendar: calendar)
        let date = try navigation.clamped(selectedDate)
        let key = try InlineDayDate.key(date, timeZoneIdentifier: calendar.timeZone.identifier)
        let runs = history.runs.filter { !$0.isSynthetic && !$0.routine.isSynthetic && $0.dayKey == key }
        self.date = date
        self.dayKey = key
        self.isToday = date == navigation.today
        self.completedRuns = runs.filter { $0.outcome == .completed }
        self.stoppedRuns = runs.filter { $0.outcome == .stopped }
        self.appObservations = history.appObservations.filter { !$0.isSynthetic && $0.dayKey == key }
        self.observations = observations.filter { $0.origin == .human && $0.dayKey == key }
        self.undatedObservationCount = observations.filter { $0.origin == .human && $0.dayKey == nil }.count
        self.sourceTimeZoneIdentifiers = Array(Set(
            runs.map(\.timeZoneIdentifier) + self.appObservations.map(\.timeZoneIdentifier)
                + self.observations.compactMap(\.timeZoneIdentifier)
        )).sorted()
        if !completedRuns.isEmpty { state = .completed }
        else if !stoppedRuns.isEmpty { state = .partial }
        else if !appObservations.isEmpty || !self.observations.isEmpty { state = .evidenceOnly }
        else { state = .noSavedEvidence }
    }
}

private enum InlineDayDate {
    static func validate(_ date: Date) throws {
        guard date.timeIntervalSince1970.isFinite else { throw MorningHistoryError.invalidDate }
    }

    static func key(_ date: Date, timeZoneIdentifier: String) throws -> String {
        try validate(date)
        guard let zone = TimeZone(identifier: timeZoneIdentifier) else { throw MorningHistoryError.invalidTimeZone }
        // History and ObservationArchive persist Gregorian keys independently of the
        // display calendar. Changing a display calendar must not regroup old evidence.
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = zone
        let values = calendar.dateComponents([.era, .year, .month, .day], from: date)
        guard values.era == 1, let year = values.year, (1...9999).contains(year),
              let month = values.month, let day = values.day else { throw MorningHistoryError.invalidDate }
        return String(format: "%04d-%02d-%02d", year, month, day)
    }
}
