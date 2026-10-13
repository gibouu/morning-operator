import Foundation

public enum LearningWindowState: String, Codable, Sendable, Equatable {
    case planned, active, paused, stopped, completed
}

/// Numbered as the Gregorian calendar numbers them: Sunday is 1.
public enum LearningWindowWeekday: Int, Codable, Sendable, CaseIterable {
    case sunday = 1, monday, tuesday, wednesday, thursday, friday, saturday
}

/// The bounds a window's duration must respect. The app passes the bounds of the recorder it
/// actually has, so a window is never longer than one recording can be.
public struct LearningWindowLimits: Sendable, Equatable {
    public let minimumDurationSeconds: Int
    public let maximumDurationSeconds: Int
    public init(minimumDurationSeconds: Int, maximumDurationSeconds: Int) {
        self.minimumDurationSeconds = minimumDurationSeconds
        self.maximumDurationSeconds = maximumDurationSeconds
    }
}

public enum LearningWindowError: Error, Equatable, Sendable {
    // What the person chose.
    case invalidStartTime, durationTooShort(minimumSeconds: Int), durationTooLong(maximumSeconds: Int)
    case noWeekday, invalidMorningCount, invalidTimeZone, invalidDate, crossesMidnight, invalidAllowance
    // Saved state.
    case unsupportedVersion(Int), invalidRecord
    // Controls.
    case cannotStart(LearningWindowState), cannotPause(LearningWindowState), clockWentBack
    case notAScheduledMorning, morningAlreadyStarted
    // Declaring a recording to the window.
    case windowNotStarted, windowStopped, differentTimeZone, recordedBeforeStart, recordedAfterEnd
    case recordedWhilePaused, morningSkipped, recordingStartUnknown, alreadyDeclared, invalidRecording
}

public struct LearningWindowPause: Codable, Sendable, Equatable {
    public let from: Date
    /// Nil while the window is still paused.
    public let until: Date?
}

/// One morning of a window. `counted` mornings are the ones the person asked to learn over;
/// a morning that began during a pause, or that the person skipped beforehand, is listed
/// with its reason and replaced by a later one.
public struct LearningWindowMorning: Sendable, Equatable, Identifiable {
    public enum Disposition: String, Sendable, Equatable { case counted, paused, skipped }
    public let dayKey: String
    public let expectedStart: Date
    public let expectedEnd: Date
    public let disposition: Disposition
    public var id: String { dayKey }
}

public struct LearningWindowSchedule: Sendable, Equatable {
    public let windowID: UUID
    public let timeZoneIdentifier: String
    /// In date order, from the day the person pressed Start.
    public let mornings: [LearningWindowMorning]
    /// Asked mornings that have no date: the window is not started, is paused now, was
    /// stopped before reaching them, or they lie beyond `LearningWindow.maximumSpanDays`.
    public let undatedMorningCount: Int
    public var countedMornings: [LearningWindowMorning] { mornings.filter { $0.disposition == .counted } }
}

/// A person's choice of when MORE may learn their morning: a start time of day, a duration,
/// weekdays and a number of mornings. It is a plan and a record of the three controls the
/// person has (Start, Pause, Stop). It starts and stops no recording: the OS requires the
/// person to start each one, and this type has no access to the recorder.
///
/// Time zone. The window keeps the zone it was created in. Its mornings are that zone's
/// local days, exactly as the archive dates an observation by a day in the zone recorded
/// with it and never moves it onto another calendar. A person who travels still sees the
/// window at the same instants (07:00 in Paris is 14:00 in Tokyo), and a recording made
/// under another zone is refused rather than counted as a comparable morning.
///
/// Daylight saving. A morning starts at the chosen wall-clock time of its local day, so a
/// 07:00 window stays at 07:00 on both transition days, 23 or 25 hours after the previous
/// one. A start time the clocks skip (02:30 on the spring day) begins at the first instant
/// that exists after it (03:00), and a day on which no such instant is left (the clocks
/// skip the end of the day) has no morning; a start time that occurs twice (02:30 on the autumn day)
/// uses the first occurrence. The duration is elapsed time in every case.
///
/// Nothing translated is stored: states, weekdays and reasons are fixed identifiers.
public struct LearningWindow: Codable, Sendable, Equatable, Identifiable {
    public static let currentSchemaVersion = 1
    public static let maximumMorningCount = 31
    /// A window never schedules a morning later than this many days after Start.
    public static let maximumSpanDays = 366

    public let id: UUID
    /// Minutes after local midnight, 0 to 1439.
    public let startMinuteOfDay: Int
    public let durationSeconds: Int
    public let weekdays: Set<LearningWindowWeekday>
    public let timeZoneIdentifier: String
    /// How many mornings the person asked to learn over.
    public let morningCount: Int
    public let createdAt: Date
    /// A recording that starts at most this long after the window does still covers the
    /// morning: the person has to answer a reminder and Apple's sharing choice first.
    public let lateStartAllowanceSeconds: Int
    public let earlyEndAllowanceSeconds: Int

    public private(set) var state: LearningWindowState
    public private(set) var startedAt: Date?
    public private(set) var endedAt: Date?
    public private(set) var pauses: [LearningWindowPause]
    public private(set) var skippedDayKeys: [String]

    public init(id: UUID = UUID(), startMinuteOfDay: Int, durationSeconds: Int,
                weekdays: Set<LearningWindowWeekday>, timeZoneIdentifier: String, morningCount: Int,
                createdAt: Date, limits: LearningWindowLimits,
                lateStartAllowanceSeconds: Int? = nil, earlyEndAllowanceSeconds: Int? = nil) throws {
        guard (0..<24 * 60).contains(startMinuteOfDay) else { throw LearningWindowError.invalidStartTime }
        guard durationSeconds >= limits.minimumDurationSeconds, durationSeconds > 0 else {
            throw LearningWindowError.durationTooShort(minimumSeconds: limits.minimumDurationSeconds)
        }
        guard durationSeconds <= limits.maximumDurationSeconds, durationSeconds <= 24 * 60 * 60 else {
            throw LearningWindowError.durationTooLong(maximumSeconds: limits.maximumDurationSeconds)
        }
        guard !weekdays.isEmpty else { throw LearningWindowError.noWeekday }
        guard (1...Self.maximumMorningCount).contains(morningCount) else { throw LearningWindowError.invalidMorningCount }
        guard Self.calendar(timeZoneIdentifier) != nil else { throw LearningWindowError.invalidTimeZone }
        guard createdAt.timeIntervalSinceReferenceDate.isFinite else { throw LearningWindowError.invalidDate }
        // A morning is one local day. A recording is dated by the day it started, so a
        // window that ran past midnight would put a late start on the following day.
        guard startMinuteOfDay * 60 + durationSeconds <= 24 * 60 * 60 else { throw LearningWindowError.crossesMidnight }
        let late = lateStartAllowanceSeconds ?? min(180, durationSeconds / 5)
        let early = earlyEndAllowanceSeconds ?? min(60, durationSeconds / 10)
        guard Self.allowancesAreValid(late: late, early: early, durationSeconds: durationSeconds) else {
            throw LearningWindowError.invalidAllowance
        }
        self.id = id
        self.startMinuteOfDay = startMinuteOfDay
        self.durationSeconds = durationSeconds
        self.weekdays = weekdays
        self.timeZoneIdentifier = timeZoneIdentifier
        self.morningCount = morningCount
        self.createdAt = createdAt
        self.lateStartAllowanceSeconds = late
        self.earlyEndAllowanceSeconds = early
        state = .planned
        startedAt = nil
        endedAt = nil
        pauses = []
        skippedDayKeys = []
    }

    // MARK: The three controls

    /// Start, and Start again after a pause. Starting a window starts no recording.
    public mutating func start(at now: Date) throws {
        guard now.timeIntervalSinceReferenceDate.isFinite else { throw LearningWindowError.invalidDate }
        switch state {
        case .planned:
            startedAt = now
        case .paused:
            guard let open = pauses.last, open.until == nil else { throw LearningWindowError.invalidRecord }
            guard now >= open.from else { throw LearningWindowError.clockWentBack }
            pauses[pauses.count - 1] = .init(from: open.from, until: now)
        case .active, .stopped, .completed:
            throw LearningWindowError.cannotStart(state)
        }
        state = .active
    }

    /// Mornings that begin while the window is paused are not learned and not counted as
    /// missed. A morning already under way keeps its place.
    public mutating func pause(at now: Date) throws {
        guard state == .active else { throw LearningWindowError.cannotPause(state) }
        guard now.timeIntervalSinceReferenceDate.isFinite else { throw LearningWindowError.invalidDate }
        guard now >= lastTransitionAt else { throw LearningWindowError.clockWentBack }
        pauses.append(.init(from: now, until: nil))
        state = .paused
    }

    /// Ends the window for good. Mornings it had not reached are dropped, and no recording
    /// can be declared to it afterwards, including one that was made before Stop and is
    /// only now ready. Stopping never fails: a clock that went back stops at the last
    /// instant the window knows. Returns false when the window had already ended.
    @discardableResult
    public mutating func stop(at now: Date) -> Bool {
        guard state != .stopped, state != .completed else { return false }
        let instant = now.timeIntervalSinceReferenceDate.isFinite ? max(now, lastTransitionAt) : lastTransitionAt
        if let open = pauses.last, open.until == nil {
            pauses[pauses.count - 1] = .init(from: open.from, until: instant)
        }
        endedAt = instant
        state = .stopped
        return true
    }

    /// Marks the window completed once every asked morning has a date and is over. This
    /// says the window ran its course, not that every morning was observed.
    @discardableResult
    public mutating func completeIfDue(at now: Date) -> Bool {
        guard state == .active, now.timeIntervalSinceReferenceDate.isFinite, now >= lastTransitionAt else { return false }
        let plan = schedule(asOf: now)
        let counted = plan.countedMornings
        guard plan.undatedMorningCount == 0, counted.count == morningCount,
              counted.allSatisfy({ $0.expectedEnd <= now }) else { return false }
        endedAt = now
        state = .completed
        return true
    }

    /// Takes one coming morning out of the window before it starts. Another morning
    /// replaces it. A morning that has started cannot be skipped: it was observed or missed.
    public mutating func skip(dayKey: String, at now: Date) throws {
        guard state == .active else {
            throw state == .planned ? LearningWindowError.windowNotStarted : LearningWindowError.notAScheduledMorning
        }
        guard let morning = schedule(asOf: now).mornings.first(where: { $0.dayKey == dayKey }),
              morning.disposition == .counted else { throw LearningWindowError.notAScheduledMorning }
        // A clock that went back cannot make a morning that has begun look like a coming one.
        guard now.timeIntervalSinceReferenceDate.isFinite, now >= lastTransitionAt else { throw LearningWindowError.clockWentBack }
        guard morning.expectedStart > now else { throw LearningWindowError.morningAlreadyStarted }
        skippedDayKeys = (skippedDayKeys + [dayKey]).sorted()
    }

    // MARK: Schedule

    /// The mornings of this window. Only an open pause makes the answer depend on `now`:
    /// what follows the present is not dated until the person presses Start again.
    public func schedule(asOf now: Date) -> LearningWindowSchedule {
        var mornings: [LearningWindowMorning] = []
        var counted = 0
        if let startedAt, let calendar = Self.calendar(timeZoneIdentifier),
           let firstNoon = calendar.date(bySettingHour: 12, minute: 0, second: 0, of: startedAt) {
            let openPauseFrom = pauses.last.flatMap { $0.until == nil ? $0.from : nil }
            for offset in 0..<Self.maximumSpanDays {
                if counted == morningCount { break }
                // Noon exists on every local day, including the two daylight-saving ones.
                guard let noon = calendar.date(byAdding: .day, value: offset, to: firstNoon),
                      let weekday = LearningWindowWeekday(rawValue: calendar.component(.weekday, from: noon)),
                      weekdays.contains(weekday),
                      let start = calendar.date(bySettingHour: startMinuteOfDay / 60, minute: startMinuteOfDay % 60,
                                                second: 0, of: noon, matchingPolicy: .nextTime,
                                                repeatedTimePolicy: .first, direction: .forward),
                      start >= startedAt else { continue }
                let key = Self.dayKey(noon, calendar: calendar)
                // Where the clocks skip the end of a day, the chosen time has no instant left
                // on that day and the search lands on the next one. That day has no morning.
                guard Self.dayKey(start, calendar: calendar) == key else { continue }
                if let endedAt, start >= endedAt { break }
                if let openPauseFrom, start >= openPauseFrom, start > now { break }
                let disposition: LearningWindowMorning.Disposition
                if skippedDayKeys.contains(key) { disposition = .skipped }
                else if pauses.contains(where: { pause in start >= pause.from && (pause.until.map { start < $0 } ?? true) }) {
                    disposition = .paused
                } else {
                    disposition = .counted
                    counted += 1
                }
                mornings.append(.init(dayKey: key, expectedStart: start,
                                      expectedEnd: start.addingTimeInterval(Double(durationSeconds)),
                                      disposition: disposition))
            }
        }
        return .init(windowID: id, timeZoneIdentifier: timeZoneIdentifier, mornings: mornings,
                     undatedMorningCount: morningCount - counted)
    }

    /// The schedule the person would get by pressing Start at `date`. Changes nothing.
    public func previewSchedule(ifStartedAt date: Date) throws -> LearningWindowSchedule {
        var copy = self
        try copy.start(at: date)
        return copy.schedule(asOf: date)
    }

    // MARK: Declaring a recording

    /// Declares one finished native recording to this window, or says why it does not
    /// belong. The recording belongs to the local day it started on, the same day the
    /// archive gives it. A recording on a scheduled morning is accepted even when it ran
    /// outside the expected interval; the capture then shows that it did.
    ///
    /// Refused: before Start, after Stop, a start during a pause, a skipped morning, a day
    /// that is not a morning of this window, and a recording made under another time zone.
    public func capture(recordingStartedAt start: Date, recordingTimeZoneIdentifier: String,
                        recordedSeconds: Double, declaredAt now: Date) throws -> ObservationWindowCapture {
        switch state {
        case .planned: throw LearningWindowError.windowNotStarted
        case .stopped: throw LearningWindowError.windowStopped
        case .active, .paused, .completed: break
        }
        guard let startedAt, let calendar = Self.calendar(timeZoneIdentifier) else { throw LearningWindowError.invalidRecord }
        guard start.timeIntervalSinceReferenceDate.isFinite, now.timeIntervalSinceReferenceDate.isFinite,
              recordedSeconds.isFinite, recordedSeconds > 0, recordedSeconds <= 24 * 60 * 60,
              start <= now else { throw LearningWindowError.invalidRecording }
        guard recordingTimeZoneIdentifier == timeZoneIdentifier else { throw LearningWindowError.differentTimeZone }
        guard start >= startedAt else { throw LearningWindowError.recordedBeforeStart }
        if let endedAt, start >= endedAt { throw LearningWindowError.recordedAfterEnd }
        guard !startsDuringPause(start) else { throw LearningWindowError.recordedWhilePaused }
        let key = Self.dayKey(start, calendar: calendar)
        guard let morning = schedule(asOf: now).mornings.first(where: { $0.dayKey == key }) else {
            throw LearningWindowError.notAScheduledMorning
        }
        switch morning.disposition {
        case .paused: throw LearningWindowError.recordedWhilePaused
        case .skipped: throw LearningWindowError.morningSkipped
        case .counted: break
        }
        do {
            return try ObservationWindowCapture(windowID: id, dayKey: key, timeZoneIdentifier: timeZoneIdentifier,
                expectedStart: morning.expectedStart, expectedEnd: morning.expectedEnd, actualStart: start,
                actualEnd: start.addingTimeInterval(recordedSeconds), declaredAt: now)
        } catch { throw LearningWindowError.invalidRecording }
    }

    /// Whether a saved declaration still counts for this window. Every rule of `capture`
    /// that can be read from the saved value is checked again on every reading, so a
    /// declaration written at or after Stop, for a recording begun during a pause, or for
    /// a day other than the one the recording started on counts for nothing, whatever wrote it.
    public func counts(_ capture: ObservationWindowCapture) -> Bool {
        guard capture.windowID == id, capture.timeZoneIdentifier == timeZoneIdentifier,
              let calendar = Self.calendar(timeZoneIdentifier),
              Self.dayKey(capture.actualStart, calendar: calendar) == capture.dayKey,
              let startedAt, capture.actualStart >= startedAt, capture.declaredAt >= capture.actualStart,
              !startsDuringPause(capture.actualStart) else { return false }
        if let endedAt {
            guard capture.actualStart < endedAt else { return false }
            if state == .stopped, capture.declaredAt >= endedAt { return false }
        }
        return schedule(asOf: max(capture.declaredAt, endedAt ?? capture.declaredAt)).mornings.contains { morning in
            morning.disposition == .counted && morning.dayKey == capture.dayKey &&
                morning.expectedStart == capture.expectedStart && morning.expectedEnd == capture.expectedEnd
        }
    }

    /// The part of a morning every adequately recorded morning has in common: the expected
    /// interval without the two allowances. Comparable mornings are compared over it.
    public func comparableInterval(expectedStart: Date, expectedEnd: Date) -> DateInterval? {
        let start = expectedStart.addingTimeInterval(Double(lateStartAllowanceSeconds))
        let end = expectedEnd.addingTimeInterval(-Double(earlyEndAllowanceSeconds))
        return end > start ? DateInterval(start: start, end: end) : nil
    }

    // MARK: Internals

    private func startsDuringPause(_ instant: Date) -> Bool {
        pauses.contains { pause in instant >= pause.from && (pause.until.map { instant < $0 } ?? true) }
    }

    private var lastTransitionAt: Date {
        ([createdAt, startedAt, endedAt] + pauses.flatMap { [$0.from, $0.until] }).compactMap { $0 }.max() ?? createdAt
    }

    private static func allowancesAreValid(late: Int, early: Int, durationSeconds: Int) -> Bool {
        late >= 0 && early >= 0 && late <= durationSeconds && early <= durationSeconds &&
            (late + early) * 2 <= durationSeconds
    }

    static func calendar(_ timeZoneIdentifier: String) -> Calendar? {
        guard !timeZoneIdentifier.isEmpty, timeZoneIdentifier.count <= 128,
              let zone = TimeZone(identifier: timeZoneIdentifier) else { return nil }
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = zone
        return calendar
    }

    /// The same key the archive gives a day: its date in this zone.
    static func dayKey(_ date: Date, calendar: Calendar) -> String {
        let parts = calendar.dateComponents([.year, .month, .day], from: date)
        return String(format: "%04d-%02d-%02d", parts.year ?? 0, parts.month ?? 0, parts.day ?? 0)
    }

    // MARK: Saved state

    private enum CodingKeys: String, CodingKey {
        case schemaVersion, id, startMinuteOfDay, durationSeconds, weekdays, timeZoneIdentifier, morningCount
        case createdAt, lateStartAllowanceSeconds, earlyEndAllowanceSeconds, state, startedAt, endedAt, pauses, skippedDayKeys
    }

    public func encode(to encoder: any Encoder) throws {
        var values = encoder.container(keyedBy: CodingKeys.self)
        try values.encode(Self.currentSchemaVersion, forKey: .schemaVersion)
        try values.encode(id, forKey: .id)
        try values.encode(startMinuteOfDay, forKey: .startMinuteOfDay)
        try values.encode(durationSeconds, forKey: .durationSeconds)
        try values.encode(weekdays.map(\.rawValue).sorted(), forKey: .weekdays)
        try values.encode(timeZoneIdentifier, forKey: .timeZoneIdentifier)
        try values.encode(morningCount, forKey: .morningCount)
        try values.encode(createdAt, forKey: .createdAt)
        try values.encode(lateStartAllowanceSeconds, forKey: .lateStartAllowanceSeconds)
        try values.encode(earlyEndAllowanceSeconds, forKey: .earlyEndAllowanceSeconds)
        try values.encode(state, forKey: .state)
        try values.encodeIfPresent(startedAt, forKey: .startedAt)
        try values.encodeIfPresent(endedAt, forKey: .endedAt)
        try values.encode(pauses, forKey: .pauses)
        try values.encode(skippedDayKeys, forKey: .skippedDayKeys)
    }

    /// Reads any version up to the current one. The duration is not checked against
    /// today's recorder limits: a window saved under other limits is still the person's
    /// window. A record whose state contradicts its dates is refused, never repaired.
    public init(from decoder: any Decoder) throws {
        let values = try decoder.container(keyedBy: CodingKeys.self)
        let version = try values.decodeIfPresent(Int.self, forKey: .schemaVersion) ?? 1
        guard (1...Self.currentSchemaVersion).contains(version) else { throw LearningWindowError.unsupportedVersion(version) }
        id = try values.decode(UUID.self, forKey: .id)
        startMinuteOfDay = try values.decode(Int.self, forKey: .startMinuteOfDay)
        durationSeconds = try values.decode(Int.self, forKey: .durationSeconds)
        let days = try values.decode([Int].self, forKey: .weekdays).map { raw -> LearningWindowWeekday in
            guard let day = LearningWindowWeekday(rawValue: raw) else { throw LearningWindowError.invalidRecord }
            return day
        }
        weekdays = Set(days)
        timeZoneIdentifier = try values.decode(String.self, forKey: .timeZoneIdentifier)
        morningCount = try values.decode(Int.self, forKey: .morningCount)
        createdAt = try values.decode(Date.self, forKey: .createdAt)
        let late = try values.decodeIfPresent(Int.self, forKey: .lateStartAllowanceSeconds)
        let early = try values.decodeIfPresent(Int.self, forKey: .earlyEndAllowanceSeconds)
        state = try values.decode(LearningWindowState.self, forKey: .state)
        startedAt = try values.decodeIfPresent(Date.self, forKey: .startedAt)
        endedAt = try values.decodeIfPresent(Date.self, forKey: .endedAt)
        pauses = try values.decodeIfPresent([LearningWindowPause].self, forKey: .pauses) ?? []
        skippedDayKeys = try values.decodeIfPresent([String].self, forKey: .skippedDayKeys) ?? []
        guard (0..<24 * 60).contains(startMinuteOfDay), durationSeconds > 0, durationSeconds <= 24 * 60 * 60,
              startMinuteOfDay * 60 + durationSeconds <= 24 * 60 * 60, !weekdays.isEmpty,
              (1...Self.maximumMorningCount).contains(morningCount),
              Self.calendar(timeZoneIdentifier) != nil else { throw LearningWindowError.invalidRecord }
        lateStartAllowanceSeconds = late ?? min(180, durationSeconds / 5)
        earlyEndAllowanceSeconds = early ?? min(60, durationSeconds / 10)
        guard Self.allowancesAreValid(late: lateStartAllowanceSeconds, early: earlyEndAllowanceSeconds,
                                      durationSeconds: durationSeconds),
              stateIsConsistent else { throw LearningWindowError.invalidRecord }
    }

    private var stateIsConsistent: Bool {
        let instants = [createdAt, startedAt, endedAt].compactMap { $0 } + pauses.flatMap { [$0.from, $0.until].compactMap { $0 } }
        guard instants.allSatisfy({ $0.timeIntervalSinceReferenceDate.isFinite }),
              pauses.count <= 4 * Self.maximumSpanDays, skippedDayKeys.count <= Self.maximumSpanDays,
              skippedDayKeys.allSatisfy({ $0.utf8.count == 10 }) else { return false }
        // Pauses are in order, closed except possibly the last, inside the window's life.
        var previous = startedAt
        for (index, pause) in pauses.enumerated() {
            guard let floor = previous, pause.from >= floor else { return false }
            if let until = pause.until {
                guard until >= pause.from else { return false }
                previous = until
            } else {
                guard index == pauses.count - 1 else { return false }
                previous = pause.from
            }
        }
        let openPause = pauses.last.map { $0.until == nil } ?? false
        if let startedAt, let endedAt, endedAt < max(startedAt, previous ?? startedAt) { return false }
        switch state {
        case .planned: return startedAt == nil && endedAt == nil && pauses.isEmpty && skippedDayKeys.isEmpty
        case .active: return startedAt != nil && endedAt == nil && !openPause
        case .paused: return startedAt != nil && endedAt == nil && openPause
        case .stopped: return endedAt != nil && !openPause && (startedAt != nil || pauses.isEmpty)
        case .completed: return startedAt != nil && endedAt != nil && !openPause
        }
    }
}
