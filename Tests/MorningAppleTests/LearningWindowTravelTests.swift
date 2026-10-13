import Foundation
import MorningCore
import Testing
@testable import MorningApple

/// A learning window keeps its own time zone; the phone does not. Every recording here is
/// manufactured and saved the way the app saves a native one: dated in the zone the phone
/// was in, with the start its session acknowledged. No clock or device setting is read.
@Suite("Learning windows while travelling: a morning is matched by instant")
struct LearningWindowTravelTests {
    private let paris = "Europe/Paris"
    private let london = "Europe/London"
    private let newYork = "America/New_York"
    private let tokyo = "Asia/Tokyo"

    private func at(_ day: Int, _ hour: Int, _ minute: Int = 0, _ second: Int = 0, month: Int = 10,
                    zone: String = "Europe/Paris") throws -> Date {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = try #require(TimeZone(identifier: zone))
        return try #require(calendar.date(from: DateComponents(year: 2026, month: month, day: day,
                                                                hour: hour, minute: minute, second: second)))
    }
    private func key(_ day: Int, month: Int = 10) -> String { String(format: "2026-%02d-%02d", month, day) }

    /// Five minutes from `hour`:00 in Paris, every day, started on Monday 12 October at 03:00.
    private func window(hour: Int = 7, mornings: Int = 3, startDay: Int = 12) throws -> LearningWindow {
        var value = try LearningWindow(startMinuteOfDay: hour * 60, durationSeconds: 300,
            weekdays: Set(LearningWindowWeekday.allCases), timeZoneIdentifier: paris, morningCount: mornings,
            createdAt: at(11, 20), limits: .currentCapture)
        try value.start(at: at(startDay, 3))
        return value
    }

    /// A native recording that started at `start` and lasted `seconds`, saved while the
    /// phone was in `zone`: the archive dates it on that zone's calendar.
    private func recording(_ start: Date, seconds: Double = 300, zone: String,
                           origin: ObservationAcquisitionOrigin = .human) throws -> ObservationAcquisition {
        let frames = try (0...20).map { index in
            try ObservationFrameEvidence(requestedTimeSeconds: Double(index) / 1_000,
                actualTimeSeconds: seconds * Double(index) / 20, outcome: .observed,
                text: index % 4 < 2 ? "Feed" : "Chess")
        }
        let evidence = try ObservationVideoEvidence(durationSeconds: seconds, frames: frames)
        let decisions = frames.map { frame in
            ObservationFrameIdentityDecision(sampleID: frame.id, timeSeconds: frame.timeSeconds, timeBasis: frame.timeBasis,
                evidence: .identified(app: .init(key: "visual-context:\(frame.text)", displayName: frame.text),
                                      reference: frame.evidenceReference), evidenceQuote: frame.text)
        }
        let result = ObservationContextClassification(decisions: decisions, status: .completed,
            attemptedBatchCount: 1, respondedBatchCount: 1, failedBatchCount: 0,
            diagnostics: [], modelAvailability: "Synthetic test result; no model call")
        return try .init(observedDate: .init(date: start, timeZoneIdentifier: zone, provenance: .recordingSession),
                         origin: origin, sourceKind: .video, sourceLabel: "Synthetic recording",
                         originalText: evidence.renderedText, videoEvidence: evidence, classification: result,
                         recordingContext: try ObservationRecordingContext(startedAt: start, timeZoneIdentifier: zone))
    }

    private func declare(_ entries: [ObservationAcquisition], to window: LearningWindow,
                         in archive: inout ObservationArchive) throws {
        for entry in entries {
            try archive.insert(entry)
            try archive.declareCapture(of: entry.id, to: window,
                at: entry.recordingContext!.startedAt.addingTimeInterval(entry.videoEvidence!.durationSeconds + 60))
        }
    }

    /// Every acquisition a profile places on a scheduled day, with repeats kept.
    private func placed(_ profile: ComparableMorningProfile) -> [UUID] {
        profile.acquisitionIDsByDayKey.values.flatMap { $0 } + profile.otherOriginAcquisitionIDs
    }

    // MARK: The owner's case

    @Test func aWeekInLondonDoesNotMakeAParisWindowMissEveryMorning() throws {
        var learning = try window(mornings: 4)
        var archive = ObservationArchive()
        // 07:00 in Paris is 06:00 in London, on the same date.
        let recordings = try (12...15).map { try recording(at($0, 6, zone: london), zone: london) }
        #expect(recordings.map { $0.observedDate?.dayKey } == (12...15).map { key($0) })
        try declare(recordings, to: learning, in: &archive)
        let now = try at(15, 8)
        let completed = learning.completeIfDue(at: now)
        #expect(completed)

        let report = LearningWindowReport(window: learning, archive: archive, now: now)
        #expect(report.mornings.map(\.dayKey) == (12...15).map { key($0) })
        #expect(report.mornings.map(\.status) == Array(repeating: .observedInWindow, count: 4))
        #expect(report.mornings.map(\.acquisitionIDs) == recordings.map { [$0.id] })
        #expect(report.mornings.allSatisfy { $0.coverage?.coveredSeconds == 300 && $0.countsTowardProgress })
        #expect(report.progress == .init(askedMorningCount: 4, adequateMorningCount: 4, remainingMorningCount: 0))
        #expect(report.ignoredAcquisitionIDs.isEmpty && report.reassignedAcquisitionIDs.isEmpty)

        let profile = try ComparableMorningProfile(window: learning, archive: archive, now: now, maximumSampleGapSeconds: 16)
        #expect(profile.report.includedDayKeys == (12...15).map { key($0) })
        #expect(profile.report.missingDayKeys.isEmpty && profile.report.excludedDays.isEmpty)
        #expect(profile.otherTimeZoneAcquisitionIDs.isEmpty, "A declared morning is on the window's calendar.")
        // The archive still says where the phone was.
        #expect(archive.entries.allSatisfy { $0.observedDate?.timeZoneIdentifier == london
            && $0.recordingContext?.timeZoneIdentifier == london && $0.windowCapture?.timeZoneIdentifier == paris })
    }

    // MARK: The day key

    @Test func aMorningRecordedTheEveningBeforeInNewYorkCountsOnceUnderTheWindowsDay() throws {
        // 05:00 in Paris is 23:00 the evening before in New York.
        var learning = try window(hour: 5, mornings: 3)
        var archive = ObservationArchive()
        let recordings = try (11...13).map { try recording(at($0, 23, zone: newYork), zone: newYork) }
        // The archive files them under the 11th, 12th and 13th, on the New York calendar.
        #expect(recordings.map { $0.observedDate?.dayKey } == [key(11), key(12), key(13)])
        try declare(recordings, to: learning, in: &archive)
        // The window's mornings are the 12th, 13th and 14th, and each declaration names its own.
        #expect(archive.entries.map { $0.windowCapture?.dayKey } == [key(12), key(13), key(14)])
        let now = try at(14, 6)
        let completed = learning.completeIfDue(at: now)
        #expect(completed)

        let report = LearningWindowReport(window: learning, archive: archive, now: now)
        #expect(report.mornings.map(\.dayKey) == [key(12), key(13), key(14)])
        #expect(report.mornings.map(\.status) == [.observedInWindow, .observedInWindow, .observedInWindow])
        // One recording per morning: the one filed under the 12th is not also Monday's.
        #expect(report.mornings.map(\.acquisitionIDs) == recordings.map { [$0.id] })
        #expect(report.mornings.allSatisfy { $0.notCountedReason == nil })
        #expect(report.progress.adequateMorningCount == 3)

        let profile = try ComparableMorningProfile(window: learning, archive: archive, now: now, maximumSampleGapSeconds: 16)
        #expect(profile.report.scheduledDayCount == 3)
        #expect(profile.report.includedDayKeys == [key(12), key(13), key(14)])
        #expect(profile.report.excludedDays.isEmpty && profile.report.missingDayKeys.isEmpty)
        #expect(profile.acquisitionIDsByDayKey == [key(12): [recordings[0].id], key(13): [recordings[1].id],
                                                   key(14): [recordings[2].id]])
        #expect(placed(profile).sorted { $0.uuidString < $1.uuidString } == recordings.map(\.id).sorted { $0.uuidString < $1.uuidString })
        #expect(profile.otherTimeZoneAcquisitionIDs.isEmpty)
        #expect(profile.report.observationDurationSeconds.daysWithEvidence == 3)
    }

    @Test func oneMissedMorningAwayIsNotFilledByTheNeighbouringMorningsRecording() throws {
        // Tuesday's morning is not recorded. Wednesday's recording is filed in New York under
        // Tuesday's date: it must not turn up as Tuesday's morning under either calendar.
        var learning = try window(hour: 5, mornings: 3)
        var archive = ObservationArchive()
        let monday = try recording(at(11, 23, zone: newYork), zone: newYork)
        let wednesday = try recording(at(13, 23, zone: newYork), zone: newYork)
        #expect(wednesday.observedDate?.dayKey == key(13))
        try declare([monday, wednesday], to: learning, in: &archive)
        let now = try at(14, 6)
        let completed = learning.completeIfDue(at: now)
        #expect(completed)
        let report = LearningWindowReport(window: learning, archive: archive, now: now)
        #expect(report.mornings.map(\.status) == [.observedInWindow, .missed, .observedInWindow])
        #expect(report.mornings.map(\.acquisitionIDs) == [[monday.id], [], [wednesday.id]])
        #expect(report.progress == .init(askedMorningCount: 3, adequateMorningCount: 2, remainingMorningCount: 0))
        let profile = try ComparableMorningProfile(window: learning, archive: archive, now: now, maximumSampleGapSeconds: 16)
        #expect(profile.report.includedDayKeys == [key(12), key(14)])
        #expect(profile.report.missingDayKeys == [key(13)])
        #expect(profile.acquisitionIDsByDayKey == [key(12): [monday.id], key(14): [wednesday.id]])
    }

    @Test func morningsAtHomeAndAwayShareOneCalendarAndNeverOneDay() throws {
        // Monday at home, Tuesday from Tokyo (12:00 there), Wednesday from New York (23:00 on
        // Tuesday there), Thursday from London (04:00 there).
        var learning = try window(hour: 5, mornings: 4)
        var archive = ObservationArchive()
        let home = try recording(at(12, 5), zone: paris)
        let fromTokyo = try recording(at(13, 12, zone: tokyo), zone: tokyo)
        let fromNewYork = try recording(at(13, 23, zone: newYork), zone: newYork)
        let fromLondon = try recording(at(15, 4, zone: london), zone: london)
        // Tuesday's and Wednesday's recordings are both filed under the 13th, each on its own calendar.
        #expect(fromTokyo.observedDate?.dayKey == key(13) && fromNewYork.observedDate?.dayKey == key(13))
        let all = [home, fromTokyo, fromNewYork, fromLondon]
        try declare(all, to: learning, in: &archive)
        let now = try at(15, 6)
        let completed = learning.completeIfDue(at: now)
        #expect(completed)
        let report = LearningWindowReport(window: learning, archive: archive, now: now)
        #expect(report.mornings.map(\.acquisitionIDs) == all.map { [$0.id] })
        #expect(report.mornings.allSatisfy { $0.status == .observedInWindow && $0.notCountedReason == nil })
        let profile = try ComparableMorningProfile(window: learning, archive: archive, now: now, maximumSampleGapSeconds: 16)
        #expect(profile.report.includedDayKeys == (12...15).map { key($0) })
        #expect(profile.acquisitionIDsByDayKey == [key(12): [home.id], key(13): [fromTokyo.id],
                                                   key(14): [fromNewYork.id], key(15): [fromLondon.id]])
        // Whatever order the archive lists them in.
        let reversed = try ObservationArchive(entries: archive.entries.reversed())
        #expect(try ComparableMorningProfile(window: learning, archive: reversed, now: now, maximumSampleGapSeconds: 16).report
            == profile.report)
        #expect(LearningWindowReport(window: learning, archive: reversed, now: now).mornings == report.mornings)
    }

    // MARK: Away, and not at the window's instant

    @Test func aRecordingAtSevenOnTheTravellersOwnClockIsOutsideTheWindowAndNeverMissed() throws {
        var learning = try window(mornings: 3)
        var archive = ObservationArchive()
        // Monday: 07:00 on the New York clock, 13:00 in Paris.
        let newYorkClock = try recording(at(12, 7, zone: newYork), zone: newYork)
        // Tuesday: 07:00 on the Tokyo clock, which is 00:00 in Paris, the first instant of the window's Tuesday.
        let tokyoClock = try recording(at(13, 7, zone: tokyo), zone: tokyo)
        // Wednesday: at the window's instant, 14:00 in Tokyo.
        let onTime = try recording(at(14, 14, zone: tokyo), zone: tokyo)
        try declare([newYorkClock, tokyoClock, onTime], to: learning, in: &archive)
        let now = try at(14, 20)
        let completed = learning.completeIfDue(at: now)
        #expect(completed)
        let report = LearningWindowReport(window: learning, archive: archive, now: now)
        #expect(report.mornings.map(\.status) == [.observedOutsideWindow, .observedOutsideWindow, .observedInWindow])
        #expect(report.mornings.map(\.notCountedReason) == [.observedOutsideWindow, .observedOutsideWindow, nil])
        // The person did record: the morning lists the recording and says nothing of it ran in the window.
        #expect(report.mornings.map(\.acquisitionIDs) == [[newYorkClock.id], [tokyoClock.id], [onTime.id]])
        #expect(report.mornings[0].coverage == .init(expectedSeconds: 300, coveredSeconds: 0,
                                                     startedLateSeconds: nil, endedEarlySeconds: nil))
        #expect(!report.mornings.contains { $0.status == .missed })
        #expect(report.progress.adequateMorningCount == 1 && report.progress.shortfallCount == 2)
        let profile = try ComparableMorningProfile(window: learning, archive: archive, now: now, maximumSampleGapSeconds: 16)
        #expect(profile.report.includedDayKeys == [key(14)])
        #expect(profile.report.excludedDays == [.init(dayKey: key(12), reason: .partialCapture),
                                                .init(dayKey: key(13), reason: .partialCapture)])
        #expect(profile.report.missingDayKeys.isEmpty)
    }

    @Test func aRecordingStraddlingOrClippingTheWindowIsJudgedOnItsInstantsWhereverItWasMade() throws {
        let learning = try window(mornings: 3)
        var archive = ObservationArchive()
        // 13:59:30 to 14:06:00 in Tokyo: the whole window and more.
        let straddling = try recording(at(12, 13, 59, 30, zone: tokyo), seconds: 390, zone: tokyo)
        // 06:02:30 to 06:05:00 in London: the second half.
        let lateStart = try recording(at(13, 6, 2, 30, zone: london), seconds: 150, zone: london)
        // 01:00:00 to 01:04:00 in New York: ended a minute early.
        let earlyEnd = try recording(at(14, 1, zone: newYork), seconds: 240, zone: newYork)
        try declare([straddling, lateStart, earlyEnd], to: learning, in: &archive)
        let report = LearningWindowReport(window: learning, archive: archive, now: try at(14, 8))
        #expect(report.mornings.map(\.status) == [.observedInWindow, .observedPartly, .observedPartly])
        #expect(report.mornings.map { $0.coverage?.coveredSeconds } == [300, 150, 240])
        #expect(report.mornings[1].coverage?.startedLateSeconds == 150 && report.mornings[2].coverage?.endedEarlySeconds == 60)
    }

    @Test func aRecordingMadeAwayButNeverDeclaredStaysOnItsOwnCalendar() throws {
        // Declaring is the only way into a window. Until then the morning has no recording
        // of its own, and comparable mornings list the observation as dated elsewhere.
        let learning = try window(mornings: 1)
        let entry = try recording(at(12, 14, zone: tokyo), zone: tokyo)
        var archive = try ObservationArchive(entries: [entry])
        let now = try at(12, 8)
        #expect(LearningWindowReport(window: learning, archive: archive, now: now).mornings.map(\.status) == [.missed])
        let before = try ComparableMorningProfile(window: learning, archive: archive, now: now, maximumSampleGapSeconds: 16)
        #expect(before.report.missingDayKeys == [key(12)] && before.otherTimeZoneAcquisitionIDs == [entry.id])
        try archive.declareCapture(of: entry.id, to: learning, at: now)
        #expect(LearningWindowReport(window: learning, archive: archive, now: now).mornings.map(\.status) == [.observedInWindow])
        let after = try ComparableMorningProfile(window: learning, archive: archive, now: now, maximumSampleGapSeconds: 16)
        #expect(after.report.includedDayKeys == [key(12)] && after.otherTimeZoneAcquisitionIDs.isEmpty)
    }

    // MARK: Clock changes in one zone only

    @Test func aClockChangeInTheTravellersZoneLeavesBothMorningsInTheWindow() throws {
        // New York leaves summer time on Sunday 1 November 2026, a week after Paris. 07:00 in
        // Paris is 02:00 there on Saturday and the second 01:00 on Sunday.
        var learning = try window(mornings: 2, startDay: 31)
        var archive = ObservationArchive()
        let plan = learning.schedule(asOf: try at(31, 3)).mornings
        #expect(plan.map(\.dayKey) == [key(31), key(1, month: 11)])
        let saturday = try recording(at(31, 2, zone: newYork), zone: newYork)
        let sunday = try recording(plan[1].expectedStart, zone: newYork)
        #expect(saturday.recordingContext?.startedAt == plan[0].expectedStart)
        // The first 01:00 that Sunday is an hour before the window: another recording, another instant.
        let hourEarly = try recording(plan[1].expectedStart.addingTimeInterval(-3_600), zone: newYork, origin: .synthetic)
        try declare([saturday, sunday, hourEarly], to: learning, in: &archive)
        let now = try at(1, 8, month: 11)
        let completed = learning.completeIfDue(at: now)
        #expect(completed)
        let report = LearningWindowReport(window: learning, archive: archive, now: now)
        #expect(report.mornings.map(\.status) == [.observedInWindow, .observedInWindow])
        #expect(report.mornings.map(\.notCountedReason) == [nil, nil])
        #expect(report.mornings[1].coverage?.coveredSeconds == 300)
        #expect(report.mornings.map(\.acquisitionIDs) == [[saturday.id], [sunday.id, hourEarly.id]])
        let profile = try ComparableMorningProfile(window: learning, archive: archive, now: now, maximumSampleGapSeconds: 16)
        #expect(profile.report.includedDayKeys == [key(31), key(1, month: 11)])
        #expect(profile.otherOriginAcquisitionIDs == [hourEarly.id])
    }

    @Test func aClockChangeInTheWindowsZoneOnlyMovesTheInstantTheTravellerMustRecordAt() throws {
        // Paris leaves summer time on Sunday 25 October 2026; Tokyo never changes. 07:00 in
        // Paris is 14:00 in Tokyo on Saturday and 15:00 from Sunday on.
        var learning = try window(mornings: 3, startDay: 24)
        var archive = ObservationArchive()
        let saturday = try recording(at(24, 14, zone: tokyo), zone: tokyo)
        // Still recording at 14:00 on Sunday: an hour before the window opens.
        let sundayOldHour = try recording(at(25, 14, zone: tokyo), zone: tokyo)
        let monday = try recording(at(26, 15, zone: tokyo), zone: tokyo)
        try declare([saturday, sundayOldHour, monday], to: learning, in: &archive)
        let now = try at(26, 8)
        let completed = learning.completeIfDue(at: now)
        #expect(completed)
        let report = LearningWindowReport(window: learning, archive: archive, now: now)
        #expect(report.mornings.map(\.dayKey) == [key(24), key(25), key(26)])
        #expect(report.mornings.map(\.status) == [.observedInWindow, .observedOutsideWindow, .observedInWindow])
        #expect(report.mornings.map(\.acquisitionIDs) == [[saturday.id], [sundayOldHour.id], [monday.id]])
        let profile = try ComparableMorningProfile(window: learning, archive: archive, now: now, maximumSampleGapSeconds: 16)
        #expect(profile.report.includedDayKeys == [key(24), key(26)])
        #expect(profile.report.excludedDays == [.init(dayKey: key(25), reason: .partialCapture)])
    }

    // MARK: The person's own corrections

    @Test func aRecordingMadeAwayAndMovedByThePersonNoLongerCountsAndOneConfirmedOnItsDayStillDoes() throws {
        let learning = try window(hour: 5, mornings: 2)
        var archive = ObservationArchive()
        let first = try recording(at(11, 23, zone: newYork), zone: newYork)
        let second = try recording(at(12, 23, zone: newYork), zone: newYork)
        try declare([first, second], to: learning, in: &archive)
        let now = try at(13, 6)
        // Confirmed in review on the day it was filed under, as a human recording: unchanged.
        try archive.assignObservedDate(id: first.id, value: .init(date: at(11, 12, zone: newYork),
            timeZoneIdentifier: newYork, provenance: .userAssigned), origin: .human)
        // Or re-dated on the window's own calendar, to the day the window gives it.
        try archive.assignObservedDate(id: second.id, value: .init(date: at(13, 12), timeZoneIdentifier: paris,
                                                                   provenance: .userAssigned))
        var report = LearningWindowReport(window: learning, archive: archive, now: now)
        #expect(report.mornings.map(\.status) == [.observedInWindow, .observedInWindow])
        #expect(report.reassignedAcquisitionIDs.isEmpty && report.progress.adequateMorningCount == 2)
        var profile = try ComparableMorningProfile(window: learning, archive: archive, now: now, maximumSampleGapSeconds: 16)
        #expect(profile.report.includedDayKeys == [key(12), key(13)])
        #expect(profile.acquisitionIDsByDayKey == [key(12): [first.id], key(13): [second.id]])

        // Moved to the day after on the New York calendar: the person's choice wins.
        try archive.assignObservedDate(id: first.id, value: .init(date: at(12, 12, zone: newYork),
            timeZoneIdentifier: newYork, provenance: .userAssigned))
        // Moved onto the window's calendar, to the day the phone's calendar showed: not its morning either.
        try archive.assignObservedDate(id: second.id, value: .init(date: at(12, 12), timeZoneIdentifier: paris,
                                                                   provenance: .userAssigned))
        report = LearningWindowReport(window: learning, archive: archive, now: now)
        #expect(report.mornings.map(\.status) == [.missed, .missed])
        #expect(report.reassignedAcquisitionIDs == [first.id, second.id])
        profile = try ComparableMorningProfile(window: learning, archive: archive, now: now, maximumSampleGapSeconds: 16)
        // The one moved within New York stays off this calendar. The one the person put on the
        // window's 12th is judged there, without the declaration it had for the 13th.
        #expect(profile.otherTimeZoneAcquisitionIDs == [first.id])
        #expect(profile.report.excludedDays == [.init(dayKey: key(12), reason: .unknownCapture)])
        #expect(profile.report.missingDayKeys == [key(13)])
        // With no date at all it is undated, and still not its morning.
        try archive.assignObservedDate(id: second.id, value: nil)
        report = LearningWindowReport(window: learning, archive: archive, now: now)
        #expect(report.reassignedAcquisitionIDs == [first.id, second.id])
        profile = try ComparableMorningProfile(window: learning, archive: archive, now: now, maximumSampleGapSeconds: 16)
        #expect(profile.undatedAcquisitionIDs == [second.id] && profile.report.missingDayKeys == [key(12), key(13)])
    }

    @Test func pauseStopAndTheAllowancesHoldForARecordingMadeAway() throws {
        var learning = try window(mornings: 3)
        var archive = ObservationArchive()
        // 60 s late and 30 s early are the allowances of a five-minute window.
        let withinAllowances = try recording(at(12, 14, 1, zone: tokyo), seconds: 210, zone: tokyo)
        try declare([withinAllowances], to: learning, in: &archive)
        try learning.pause(at: at(12, 12))
        let duringPause = try recording(at(13, 14, zone: tokyo), zone: tokyo)
        try archive.insert(duringPause)
        #expect(throws: LearningWindowError.recordedWhilePaused) {
            try archive.declareCapture(of: duringPause.id, to: learning, at: at(13, 8))
        }
        try learning.start(at: at(13, 12))
        let wednesday = try recording(at(14, 14, zone: tokyo), zone: tokyo)
        try archive.insert(wednesday)
        let stopped = learning.stop(at: try at(14, 7, 6))
        #expect(stopped)
        #expect(throws: LearningWindowError.windowStopped) {
            try archive.declareCapture(of: wednesday.id, to: learning, at: at(14, 7, 7))
        }
        #expect(throws: LearningWindowError.alreadyDeclared) {
            try archive.declareCapture(of: withinAllowances.id, to: learning, at: at(14, 7, 7))
        }
        let report = LearningWindowReport(window: learning, archive: archive, now: try at(14, 9))
        #expect(report.mornings.map(\.status) == [.observedInWindow, .paused, .missed])
        #expect(report.mornings[0].notCountedReason == nil)
        #expect(report.mornings[0].coverage == .init(expectedSeconds: 300, coveredSeconds: 210,
                                                     startedLateSeconds: 60, endedEarlySeconds: 30))
    }

    // MARK: Saved archives

    @Test func aDeclarationMadeAwaySurvivesSavingAndAMalformedOneIsDropped() throws {
        let learning = try window(hour: 5, mornings: 2)
        var archive = ObservationArchive()
        let away = try recording(at(11, 23, zone: newYork), zone: newYork)
        let home = try recording(at(13, 5), zone: paris)
        try declare([away, home], to: learning, in: &archive)
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        let saved = try encoder.encode(archive)
        let restored = try JSONDecoder().decode(ObservationArchive.self, from: saved)
        #expect(restored == archive)
        try #expect(encoder.encode(restored) == saved)
        let capture = try #require(restored.entry(id: away.id)?.windowCapture)
        // The window's day and zone on the declaration; the phone's on the observation and its session.
        #expect(capture.dayKey == key(12) && capture.timeZoneIdentifier == paris)
        #expect(restored.entry(id: away.id)?.observedDate?.dayKey == key(11))
        #expect(restored.entry(id: away.id)?.recordingContext?.timeZoneIdentifier == newYork)
        try #expect(capture.actualStart == (at(12, 5)) && capture.expectedStart == (at(12, 5)))
        #expect(LearningWindowReport(window: learning, archive: restored, now: try at(13, 6)).progress.adequateMorningCount == 2)

        func reload(_ change: (inout [String: Any]) -> Void) throws -> ObservationAcquisition? {
            var object = try #require(JSONSerialization.jsonObject(with: saved) as? [String: Any])
            var entries = try #require(object["entries"] as? [[String: Any]])
            let index = try #require(entries.firstIndex { ($0["id"] as? String) == away.id.uuidString })
            var declared = try #require(entries[index]["windowCapture"] as? [String: Any])
            change(&declared)
            entries[index]["windowCapture"] = declared
            object["entries"] = entries
            let loaded = try JSONDecoder().decode(ObservationArchive.self, from: JSONSerialization.data(withJSONObject: object))
            #expect(loaded.entries.count == 2 && loaded.entry(id: home.id)?.windowCapture != nil)
            return loaded.entry(id: away.id)
        }
        #expect(try reload { _ in }?.windowCapture == capture)
        // The day of the phone's calendar is not the window's morning.
        #expect(try reload { $0["dayKey"] = "2026-10-11" }?.windowCapture == nil)
        // Nor is the phone's zone the window's: 23:00 on the 11th there is not the 12th.
        #expect(try reload { $0["timeZoneIdentifier"] = "America/New_York" }?.windowCapture == nil)
        #expect(try reload { $0["timeZoneIdentifier"] = "Mars/Olympus" }?.windowCapture == nil)
        // The instants must still be the recording's own.
        #expect(try reload { $0["actualStart"] = ($0["actualStart"] as? Double ?? 0) + 1 }?.windowCapture == nil)
        #expect(try reload { $0["actualEnd"] = ($0["actualEnd"] as? Double ?? 0) + 0.001 }?.windowCapture == nil)
        #expect(try reload { $0["expectedStart"] = ($0["expectedStart"] as? Double ?? 0) - 86_400 }?.windowCapture == nil)
        // Whatever is dropped, the observation itself is kept whole.
        let kept = try #require(try reload { $0["dayKey"] = "2026-10-11" })
        #expect(kept.videoEvidence == away.videoEvidence && kept.recordingContext == away.recordingContext
            && kept.observedDate == away.observedDate)
    }

    @Test func aDeclarationWithFractionsOfASecondSurvivesSaving() throws {
        // The saved check is exact: the declared end must be the session's start plus the
        // movie's length, to the last bit. These are the awkward values: thirds, tenths,
        // a start with sub-millisecond digits, lengths a movie's time scale produces.
        let learning = try window(mornings: 1)
        let starts: [Double] = [0, 0.1, 1.0 / 3, 0.123456789, 59.999999, 2.0 / 3 + 30]
        let lengths: [Double] = [300.1, 299.9999, 180 + 1.0 / 3, 240.033366700033, 300 + 1.0 / 600, 17_999.0 / 60]
        var checked = 0
        for offset in starts {
            for seconds in lengths {
                let entry = try recording(at(12, 7).addingTimeInterval(offset), seconds: seconds, zone: london)
                var archive = try ObservationArchive(entries: [entry])
                let capture = try archive.declareCapture(of: entry.id, to: learning, at: at(12, 8))
                #expect(capture.actualEnd == capture.actualStart.addingTimeInterval(seconds))
                for formatting: JSONEncoder.OutputFormatting in [[], [.sortedKeys, .prettyPrinted]] {
                    let encoder = JSONEncoder()
                    encoder.outputFormatting = formatting
                    let saved = try encoder.encode(archive)
                    let restored = try JSONDecoder().decode(ObservationArchive.self, from: saved)
                    #expect(restored.entry(id: entry.id)?.windowCapture == capture, "start +\(offset) s, \(seconds) s long")
                    #expect(restored == archive)
                    // And through a second writing, as an archive loaded and saved again is.
                    try #expect(JSONDecoder().decode(ObservationArchive.self, from: encoder.encode(restored)) == archive)
                    checked += 1
                }
            }
        }
        #expect(checked == 72)
    }
}
