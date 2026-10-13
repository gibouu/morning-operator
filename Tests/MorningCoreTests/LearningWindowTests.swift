import Foundation
import Testing
@testable import MorningCore

/// Every date here is chosen by the test. No clock, calendar setting or recorder is read.
@Suite("Learning windows: the person's choice, its controls and its schedule")
struct LearningWindowTests {
    private let paris = "Europe/Paris"
    private let limits = LearningWindowLimits(minimumDurationSeconds: 300, maximumDurationSeconds: 1_800)
    private let everyDay = Set(LearningWindowWeekday.allCases)

    private func at(_ day: Int, _ hour: Int, _ minute: Int = 0, _ second: Int = 0, year: Int = 2026,
                    month: Int = 10, zone: String = "Europe/Paris") throws -> Date {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = try #require(TimeZone(identifier: zone))
        return try #require(calendar.date(from: DateComponents(year: year, month: month, day: day,
                                                                hour: hour, minute: minute, second: second)))
    }

    private func window(start: Int = 7 * 60, duration: Int = 1_200, weekdays: Set<LearningWindowWeekday>? = nil,
                        mornings: Int = 4, zone: String = "Europe/Paris") throws -> LearningWindow {
        try LearningWindow(startMinuteOfDay: start, durationSeconds: duration, weekdays: weekdays ?? everyDay,
                           timeZoneIdentifier: zone, morningCount: mornings, createdAt: at(1, 12), limits: limits)
    }

    private func localTime(_ date: Date, zone: String = "Europe/Paris") throws -> String {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = try #require(TimeZone(identifier: zone))
        let parts = calendar.dateComponents([.hour, .minute], from: date)
        return String(format: "%02d:%02d", parts.hour ?? -1, parts.minute ?? -1)
    }

    // MARK: What the person chose

    @Test func aWindowIsRefusedWithATypedReason() throws {
        #expect(throws: LearningWindowError.durationTooShort(minimumSeconds: 300)) { try window(duration: 299) }
        #expect(throws: LearningWindowError.durationTooLong(maximumSeconds: 1_800)) { try window(duration: 1_801) }
        #expect(throws: LearningWindowError.noWeekday) { try window(weekdays: []) }
        #expect(throws: LearningWindowError.invalidMorningCount) { try window(mornings: 0) }
        #expect(throws: LearningWindowError.invalidMorningCount) { try window(mornings: 32) }
        #expect(throws: LearningWindowError.invalidTimeZone) { try window(zone: "Not/AZone") }
        #expect(throws: LearningWindowError.invalidStartTime) { try window(start: 24 * 60) }
        #expect(throws: LearningWindowError.invalidStartTime) { try window(start: -1) }
        #expect(throws: LearningWindowError.crossesMidnight) { try window(start: 23 * 60 + 50, duration: 1_200) }
        #expect(throws: LearningWindowError.invalidAllowance) {
            try LearningWindow(startMinuteOfDay: 420, durationSeconds: 600, weekdays: everyDay, timeZoneIdentifier: paris,
                               morningCount: 3, createdAt: at(1, 12), limits: limits, lateStartAllowanceSeconds: 400)
        }
        let accepted = try window(start: 23 * 60 + 40, duration: 1_200)
        #expect(accepted.state == .planned)
        // The two allowances leave most of the window to be recorded.
        #expect(accepted.lateStartAllowanceSeconds == 180 && accepted.earlyEndAllowanceSeconds == 60)
        let short = try window(duration: 300)
        #expect(short.lateStartAllowanceSeconds == 60 && short.earlyEndAllowanceSeconds == 30)
    }

    // MARK: Start, Pause, Stop

    @Test func startPauseAndStopAreTheOnlyTransitionsAndEachIsChecked() throws {
        var value = try window()
        #expect(throws: LearningWindowError.cannotPause(.planned)) { try value.pause(at: at(12, 6)) }
        try #expect(value.schedule(asOf: at(12, 6)).mornings.isEmpty, "A plan has no dates until Start.")
        try #expect(value.schedule(asOf: at(12, 6)).undatedMorningCount == 4)

        try value.start(at: at(12, 6))
        try #expect(value.state == .active && value.startedAt == (at(12, 6)))
        #expect(throws: LearningWindowError.cannotStart(.active)) { try value.start(at: at(12, 6, 1)) }
        #expect(throws: LearningWindowError.clockWentBack) { try value.pause(at: at(12, 5)) }

        try value.pause(at: at(12, 8))
        #expect(value.state == .paused)
        #expect(throws: LearningWindowError.cannotPause(.paused)) { try value.pause(at: at(12, 9)) }
        #expect(throws: LearningWindowError.clockWentBack) { try value.start(at: at(12, 7)) }
        try value.start(at: at(13, 8))
        #expect(value.state == .active)
        try #expect(value.pauses == [.init(from: at(12, 8), until: at(13, 8))])

        let outcome1 = try value.stop(at: at(14, 9))
        #expect(outcome1)
        try #expect(value.state == .stopped && value.endedAt == (at(14, 9)))
        let outcome2 = try value.stop(at: at(15, 9))
        #expect(!outcome2, "Stopping twice changes nothing.")
        try #expect(value.endedAt == (at(14, 9)))
        #expect(throws: LearningWindowError.cannotStart(.stopped)) { try value.start(at: at(15, 9)) }
        #expect(throws: LearningWindowError.cannotPause(.stopped)) { try value.pause(at: at(15, 9)) }
    }

    @Test func stopNeverFailsEvenWhenTheClockWentBackOrThePlanWasNeverStarted() throws {
        var paused = try window()
        try paused.start(at: at(12, 6))
        try paused.pause(at: at(12, 8))
        let outcome3 = try paused.stop(at: at(11, 0))
        #expect(outcome3)
        try #expect(paused.endedAt == (at(12, 8)), "It stops at the last instant the window knows.")
        try #expect(paused.pauses.last?.until == (at(12, 8)))

        var planned = try window()
        let outcome4 = try planned.stop(at: at(12, 6))
        #expect(outcome4)
        #expect(planned.state == .stopped && planned.startedAt == nil)
        try #expect(planned.schedule(asOf: at(20, 6)).mornings.isEmpty)
    }

    // MARK: Schedule

    @Test func theScheduleFollowsTheChosenWeekdaysFromTheInstantOfStart() throws {
        // Monday, Wednesday and Friday. 12 October 2026 is a Monday.
        var value = try window(weekdays: [.monday, .wednesday, .friday], mornings: 4)
        try value.start(at: at(12, 7, 2))
        let plan = value.schedule(asOf: try at(12, 7, 2))
        // Monday's window had already begun when the person pressed Start: it is not a morning of the window.
        #expect(plan.mornings.map(\.dayKey) == ["2026-10-14", "2026-10-16", "2026-10-19", "2026-10-21"])
        #expect(plan.undatedMorningCount == 0)
        try #expect(plan.mornings.allSatisfy { try localTime($0.expectedStart) == "07:00" })
        #expect(plan.mornings.allSatisfy { $0.expectedEnd.timeIntervalSince($0.expectedStart) == 1_200 })

        var early = try window(weekdays: [.monday, .wednesday, .friday], mornings: 2)
        try early.start(at: at(12, 6, 55))
        try #expect(early.schedule(asOf: at(12, 6, 55)).mornings.map(\.dayKey) == ["2026-10-12", "2026-10-14"])
        try #expect(window(mornings: 2).previewSchedule(ifStartedAt: at(12, 6)).mornings.map(\.dayKey) == ["2026-10-12", "2026-10-13"])
    }

    @Test func aWindowLaterInTheDayStillBeginsOnTheDayStartWasPressed() throws {
        // Start pressed at 20:00 for a 22:00 window: tonight counts. Pressed at 23:00: tomorrow.
        var evening = try window(start: 22 * 60, duration: 600, mornings: 2)
        try evening.start(at: at(12, 20))
        try #expect(evening.schedule(asOf: at(12, 20)).mornings.map(\.dayKey) == ["2026-10-12", "2026-10-13"])
        var late = try window(start: 22 * 60, duration: 600, mornings: 2)
        try late.start(at: at(12, 23))
        try #expect(late.schedule(asOf: at(12, 23)).mornings.map(\.dayKey) == ["2026-10-13", "2026-10-14"])
        // A start pressed at the very instant the window opens counts that morning.
        var exact = try window(mornings: 1)
        try exact.start(at: at(12, 7))
        try #expect(exact.schedule(asOf: at(12, 7)).mornings.map(\.dayKey) == ["2026-10-12"])
    }

    @Test func aSevenOClockWindowStaysAtSevenLocalOnBothDaylightSavingDays() throws {
        // Paris leaves summer time on Sunday 25 October 2026: that night lasts 25 hours.
        var autumn = try window(mornings: 3)
        try autumn.start(at: at(24, 6))
        let autumnDays = autumn.schedule(asOf: try at(24, 6)).mornings
        #expect(autumnDays.map(\.dayKey) == ["2026-10-24", "2026-10-25", "2026-10-26"])
        try #expect(autumnDays.map { try localTime($0.expectedStart) } == ["07:00", "07:00", "07:00"])
        #expect(autumnDays[1].expectedStart.timeIntervalSince(autumnDays[0].expectedStart) == 25 * 3_600)
        #expect(autumnDays[2].expectedStart.timeIntervalSince(autumnDays[1].expectedStart) == 24 * 3_600)
        #expect(autumnDays.allSatisfy { $0.expectedEnd.timeIntervalSince($0.expectedStart) == 1_200 })

        // Paris enters summer time on Sunday 28 March 2027: that night lasts 23 hours.
        var spring = try window(mornings: 3)
        try spring.start(at: at(27, 6, year: 2027, month: 3))
        let springDays = spring.schedule(asOf: try at(27, 6, year: 2027, month: 3)).mornings
        #expect(springDays.map(\.dayKey) == ["2027-03-27", "2027-03-28", "2027-03-29"])
        try #expect(springDays.map { try localTime($0.expectedStart) } == ["07:00", "07:00", "07:00"])
        #expect(springDays[1].expectedStart.timeIntervalSince(springDays[0].expectedStart) == 23 * 3_600)
    }

    @Test func aStartTimeTheClocksSkipOrRepeatIsResolvedOnceAndStated() throws {
        let utc = try #require(TimeZone(identifier: "UTC"))
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = utc
        func utcTime(_ date: Date) -> String {
            let parts = calendar.dateComponents([.hour, .minute], from: date)
            return String(format: "%02d:%02d", parts.hour ?? -1, parts.minute ?? -1)
        }
        // 02:30 does not exist on 28 March 2027: the morning begins at 03:00 summer time, 01:00 UTC.
        var spring = try window(start: 2 * 60 + 30, duration: 600, mornings: 2)
        try spring.start(at: at(27, 0, year: 2027, month: 3))
        let springDays = spring.schedule(asOf: try at(27, 0, year: 2027, month: 3)).mornings
        #expect(springDays.map(\.dayKey) == ["2027-03-27", "2027-03-28"])
        try #expect(localTime(springDays[0].expectedStart) == "02:30")
        try #expect(localTime(springDays[1].expectedStart) == "03:00")
        #expect(utcTime(springDays[1].expectedStart) == "01:00")

        // 02:30 happens twice on 25 October 2026: the first one, still in summer time, 00:30 UTC.
        var autumn = try window(start: 2 * 60 + 30, duration: 600, mornings: 2)
        try autumn.start(at: at(24, 0))
        let autumnDays = autumn.schedule(asOf: try at(24, 0)).mornings
        #expect(autumnDays.map(\.dayKey) == ["2026-10-24", "2026-10-25"])
        try #expect(localTime(autumnDays[1].expectedStart) == "02:30")
        #expect(utcTime(autumnDays[1].expectedStart) == "00:30")
        #expect(autumnDays[1].expectedEnd.timeIntervalSince(autumnDays[1].expectedStart) == 600)
    }

    @Test func aDayWhoseEndTheClocksSkipHasNoMorningAndNoInstantIsScheduledTwice() throws {
        // Nuuk enters summer time late on Saturday 28 March 2026: 23:30 does not exist that day
        // and no later instant of that day is left.
        let zone = "America/Nuuk"
        var value = try LearningWindow(startMinuteOfDay: 23 * 60 + 30, durationSeconds: 600, weekdays: everyDay,
            timeZoneIdentifier: zone, morningCount: 3, createdAt: at(26, 12, month: 3, zone: zone), limits: limits)
        try value.start(at: at(27, 12, month: 3, zone: zone))
        let days = try value.schedule(asOf: at(27, 12, month: 3, zone: zone)).mornings
        #expect(days.map(\.dayKey) == ["2026-03-27", "2026-03-29", "2026-03-30"])
        #expect(Set(days.map(\.expectedStart)).count == 3)
        #expect(try days.allSatisfy { try localTime($0.expectedStart, zone: zone) == "23:30" })
    }

    @Test func aSavedDurationTooLargeToAddIsRefusedWithoutACrash() throws {
        let json = """
        {"id":"7B0E6A53-5D0C-4B7E-9C1E-0A6B1F2D3C4E","startMinuteOfDay":420,"durationSeconds":9223372036854775807,
         "weekdays":[2],"timeZoneIdentifier":"Europe/Paris","morningCount":3,"createdAt":0,"state":"planned"}
        """
        #expect(throws: LearningWindowError.invalidRecord) { try JSONDecoder().decode(LearningWindow.self, from: Data(json.utf8)) }
        let open = LearningWindowLimits(minimumDurationSeconds: 0, maximumDurationSeconds: .max)
        #expect(throws: LearningWindowError.durationTooLong(maximumSeconds: .max)) {
            try LearningWindow(startMinuteOfDay: 420, durationSeconds: .max, weekdays: everyDay, timeZoneIdentifier: paris,
                               morningCount: 3, createdAt: at(1, 12), limits: open)
        }
    }

    @Test func theWindowKeepsItsOwnTimeZoneWhenThePersonTravels() throws {
        var value = try window(duration: 300, mornings: 2)
        try value.start(at: at(12, 6))
        let first = try #require(value.schedule(asOf: try at(12, 6)).mornings.first)
        // The same instant wherever the phone is: 07:00 in Paris is 14:00 in Tokyo.
        try #expect(localTime(first.expectedStart, zone: "Asia/Tokyo") == "14:00")
        #expect(first.dayKey == "2026-10-12")

        // A recording made under Tokyo time is refused, at 07:00 Tokyo and at the Paris instant alike.
        #expect(throws: LearningWindowError.differentTimeZone) {
            try value.capture(recordingStartedAt: at(13, 7, zone: "Asia/Tokyo"), recordingTimeZoneIdentifier: "Asia/Tokyo",
                              recordedSeconds: 300, declaredAt: at(13, 9))
        }
        #expect(throws: LearningWindowError.differentTimeZone) {
            try value.capture(recordingStartedAt: at(12, 7), recordingTimeZoneIdentifier: "Asia/Tokyo",
                              recordedSeconds: 300, declaredAt: at(12, 9))
        }
        let home = try value.capture(recordingStartedAt: at(12, 7), recordingTimeZoneIdentifier: paris,
                                     recordedSeconds: 300, declaredAt: at(12, 9))
        #expect(home.dayKey == "2026-10-12" && home.timeZoneIdentifier == paris)
    }

    @Test func morningsThatBeginDuringAPauseAreNotCountedAndAreReplaced() throws {
        var value = try window(mornings: 3)
        try value.start(at: at(12, 6))
        try value.pause(at: at(12, 7, 5))
        // Still paused on the 14th: the 13th and 14th began during the pause, what follows has no date.
        let during = value.schedule(asOf: try at(14, 12))
        #expect(during.mornings.map(\.dayKey) == ["2026-10-12", "2026-10-13", "2026-10-14"])
        #expect(during.mornings.map(\.disposition) == [.counted, .paused, .paused])
        #expect(during.undatedMorningCount == 2)

        try value.start(at: at(14, 12))
        let after = value.schedule(asOf: try at(14, 12))
        #expect(after.mornings.map(\.dayKey) == ["2026-10-12", "2026-10-13", "2026-10-14", "2026-10-15", "2026-10-16"])
        #expect(after.countedMornings.map(\.dayKey) == ["2026-10-12", "2026-10-15", "2026-10-16"])
        #expect(after.undatedMorningCount == 0)
        // The morning under way when Pause was pressed keeps its place.
        #expect(after.mornings[0].disposition == .counted)
    }

    @Test func aComingMorningCanBeSkippedAndAStartedOneCannot() throws {
        var value = try window(mornings: 2)
        #expect(throws: LearningWindowError.windowNotStarted) { try value.skip(dayKey: "2026-10-13", at: at(12, 6)) }
        try value.start(at: at(12, 6))
        try value.skip(dayKey: "2026-10-13", at: at(12, 8))
        let plan = value.schedule(asOf: try at(12, 8))
        #expect(plan.mornings.map(\.disposition) == [.counted, .skipped, .counted])
        #expect(plan.countedMornings.map(\.dayKey) == ["2026-10-12", "2026-10-14"])
        #expect(throws: LearningWindowError.morningAlreadyStarted) { try value.skip(dayKey: "2026-10-12", at: at(12, 8)) }
        // A clock set back before the last control cannot make Monday a coming morning again.
        #expect(throws: LearningWindowError.clockWentBack) { try value.skip(dayKey: "2026-10-12", at: at(12, 5)) }
        var resumed = try window(mornings: 2)
        try resumed.start(at: at(12, 6))
        try resumed.pause(at: at(12, 8))
        try resumed.start(at: at(12, 9))
        #expect(throws: LearningWindowError.clockWentBack) { try resumed.skip(dayKey: "2026-10-12", at: at(12, 6, 30)) }
        try #expect(resumed.schedule(asOf: at(12, 9)).mornings.first?.disposition == .counted)
        #expect(throws: LearningWindowError.notAScheduledMorning) { try value.skip(dayKey: "2026-10-13", at: at(12, 8)) }
        #expect(throws: LearningWindowError.notAScheduledMorning) { try value.skip(dayKey: "2026-11-30", at: at(12, 8)) }
        #expect(throws: LearningWindowError.morningSkipped) {
            try value.capture(recordingStartedAt: at(13, 7), recordingTimeZoneIdentifier: paris,
                              recordedSeconds: 600, declaredAt: at(13, 8))
        }
    }

    @Test func stopDropsTheMorningsNotReachedAndCompletionWaitsForTheLastOne() throws {
        var stopped = try window(mornings: 4)
        try stopped.start(at: at(12, 6))
        stopped.stop(at: try at(13, 12))
        let plan = stopped.schedule(asOf: try at(30, 12))
        #expect(plan.mornings.map(\.dayKey) == ["2026-10-12", "2026-10-13"])
        #expect(plan.undatedMorningCount == 2)

        var value = try window(mornings: 2)
        try value.start(at: at(12, 6))
        let outcome5 = try value.completeIfDue(at: at(13, 7, 19))
        #expect(!outcome5)
        #expect(value.state == .active)
        let outcome6 = try value.completeIfDue(at: at(13, 7, 20))
        #expect(outcome6)
        try #expect(value.state == .completed && value.endedAt == (at(13, 7, 20)))
        let outcome7 = try value.stop(at: at(13, 8))
        #expect(!outcome7, "A completed window has already ended.")
        #expect(value.state == .completed)
    }

    // MARK: Declaring a recording

    @Test func aRecordingBelongsToTheDayItStartedOnAndCarriesBothIntervals() throws {
        var value = try window(mornings: 3)
        try value.start(at: at(12, 6))
        let late = try value.capture(recordingStartedAt: at(12, 7, 8), recordingTimeZoneIdentifier: paris,
                                     recordedSeconds: 600, declaredAt: at(12, 7, 30))
        #expect(late.windowID == value.id && late.dayKey == "2026-10-12")
        try #expect(late.expectedStart == (at(12, 7)) && late.expectedEnd == (at(12, 7, 20)))
        try #expect(late.actualStart == (at(12, 7, 8)) && late.actualEnd == (at(12, 7, 18)))
        #expect(value.counts(late))

        // Outside the expected interval on a morning of the window: accepted, and it shows.
        let evening = try value.capture(recordingStartedAt: at(12, 19), recordingTimeZoneIdentifier: paris,
                                        recordedSeconds: 600, declaredAt: at(12, 20))
        #expect(evening.dayKey == "2026-10-12" && evening.actualStart > evening.expectedEnd)

        #expect(throws: LearningWindowError.recordedBeforeStart) {
            try value.capture(recordingStartedAt: at(12, 5), recordingTimeZoneIdentifier: paris, recordedSeconds: 600, declaredAt: at(12, 8))
        }
        #expect(throws: LearningWindowError.notAScheduledMorning) {
            try value.capture(recordingStartedAt: at(15, 7), recordingTimeZoneIdentifier: paris, recordedSeconds: 600, declaredAt: at(15, 8))
        }
        #expect(throws: LearningWindowError.invalidRecording) {
            try value.capture(recordingStartedAt: at(13, 7), recordingTimeZoneIdentifier: paris, recordedSeconds: 0, declaredAt: at(13, 8))
        }
        #expect(throws: LearningWindowError.invalidRecording) {
            try value.capture(recordingStartedAt: at(13, 7), recordingTimeZoneIdentifier: paris, recordedSeconds: 600, declaredAt: at(13, 6))
        }
        let planned = try window()
        #expect(throws: LearningWindowError.windowNotStarted) {
            try planned.capture(recordingStartedAt: at(12, 7), recordingTimeZoneIdentifier: paris, recordedSeconds: 600, declaredAt: at(12, 8))
        }
    }

    @Test func aWindowJustAfterMidnightDoesNotTakeARecordingBegunTheEveningBefore() throws {
        var value = try window(start: 5, duration: 600, weekdays: [.tuesday], mornings: 1)
        try value.start(at: at(12, 6))
        try #expect(value.schedule(asOf: at(12, 6)).mornings.map(\.dayKey) == ["2026-10-13"])
        // 23:58 on Monday belongs to Monday, as in the archive, and Monday is not a morning of this window.
        #expect(throws: LearningWindowError.notAScheduledMorning) {
            try value.capture(recordingStartedAt: at(12, 23, 58), recordingTimeZoneIdentifier: paris,
                              recordedSeconds: 900, declaredAt: at(13, 1))
        }
        let tuesday = try value.capture(recordingStartedAt: at(13, 0, 6), recordingTimeZoneIdentifier: paris,
                                        recordedSeconds: 540, declaredAt: at(13, 1))
        #expect(tuesday.dayKey == "2026-10-13")
    }

    @Test func aRecordingBegunDuringAPauseIsRefusedAndOneBegunBeforeItIsKept() throws {
        var value = try window(mornings: 3)
        try value.start(at: at(12, 6))
        try value.pause(at: at(12, 7, 30))
        // Recorded 07:00 to 07:20, before Pause; saved while paused.
        let before = try value.capture(recordingStartedAt: at(12, 7), recordingTimeZoneIdentifier: paris,
                                       recordedSeconds: 1_200, declaredAt: at(12, 7, 40))
        #expect(value.counts(before))
        #expect(throws: LearningWindowError.recordedWhilePaused) {
            try value.capture(recordingStartedAt: at(12, 7, 35), recordingTimeZoneIdentifier: paris, recordedSeconds: 60, declaredAt: at(12, 7, 40))
        }
        #expect(throws: LearningWindowError.recordedWhilePaused) {
            try value.capture(recordingStartedAt: at(13, 7), recordingTimeZoneIdentifier: paris, recordedSeconds: 1_200, declaredAt: at(13, 8))
        }
        try value.start(at: at(13, 12))
        #expect(throws: LearningWindowError.recordedWhilePaused) {
            try value.capture(recordingStartedAt: at(13, 7), recordingTimeZoneIdentifier: paris, recordedSeconds: 1_200, declaredAt: at(13, 13))
        }

        // A copy of the window taken before Pause would still accept a recording begun
        // during the pause. The window that was paused does not count it.
        var current = try window(mornings: 3)
        try current.start(at: at(12, 6))
        let stale = current
        try current.pause(at: at(12, 7, 0, 30))
        let during = try stale.capture(recordingStartedAt: at(12, 7, 0, 40), recordingTimeZoneIdentifier: paris,
                                       recordedSeconds: 300, declaredAt: at(12, 7, 10))
        #expect(stale.counts(during) && !current.counts(during))
        // Nor a declaration filed under a day other than the one the recording started on.
        let wrongDay = try ObservationWindowCapture(windowID: current.id, dayKey: "2026-10-12", timeZoneIdentifier: paris,
            expectedStart: at(12, 7), expectedEnd: at(12, 7, 20), actualStart: at(11, 7), actualEnd: at(11, 7, 20),
            declaredAt: at(12, 6, 30))
        #expect(!current.counts(wrongDay))
    }

    /// Issue #19: "Stop/cancel must end acquisition and prevent later stale data from being
    /// appended to the session."
    @Test func stopEndsTheWindowAndPreventsLaterStaleDataFromBeingAppendedToIt() throws {
        var value = try window(mornings: 3)
        try value.start(at: at(12, 6))
        let first = try value.capture(recordingStartedAt: at(12, 7), recordingTimeZoneIdentifier: paris,
                                      recordedSeconds: 1_200, declaredAt: at(12, 7, 25))
        // Tuesday's recording runs 07:00 to 07:20. The person presses Stop at 07:30, before it is saved.
        let outcome8 = try value.stop(at: at(13, 7, 30))
        #expect(outcome8)
        #expect(value.state == .stopped)
        try #expect(value.schedule(asOf: at(20, 12)).mornings.map(\.dayKey) == ["2026-10-12", "2026-10-13"])

        // The recording made before Stop is stale once Stop was pressed.
        #expect(throws: LearningWindowError.windowStopped) {
            try value.capture(recordingStartedAt: at(13, 7), recordingTimeZoneIdentifier: paris,
                              recordedSeconds: 1_200, declaredAt: at(13, 7, 31))
        }
        // So is anything recorded afterwards.
        #expect(throws: LearningWindowError.windowStopped) {
            try value.capture(recordingStartedAt: at(14, 7), recordingTimeZoneIdentifier: paris,
                              recordedSeconds: 1_200, declaredAt: at(14, 8))
        }
        // What was declared before Stop still counts; a declaration dated at or after Stop
        // does not, even if something wrote it without asking the window.
        #expect(value.counts(first))
        let forged = try ObservationWindowCapture(windowID: value.id, dayKey: "2026-10-13", timeZoneIdentifier: paris,
            expectedStart: at(13, 7), expectedEnd: at(13, 7, 20), actualStart: at(13, 7), actualEnd: at(13, 7, 20),
            declaredAt: at(13, 7, 30))
        #expect(!value.counts(forged))
        // Nothing restarts it.
        #expect(throws: LearningWindowError.cannotStart(.stopped)) { try value.start(at: at(14, 6)) }
        #expect(throws: LearningWindowError.notAScheduledMorning) { try value.skip(dayKey: "2026-10-14", at: at(13, 8)) }
    }

    @Test func aDeclarationForAnotherWindowOrAnAlteredIntervalDoesNotCount() throws {
        var value = try window(mornings: 2)
        try value.start(at: at(12, 6))
        var other = try window(mornings: 2)
        try other.start(at: at(12, 6))
        let capture = try other.capture(recordingStartedAt: at(12, 7), recordingTimeZoneIdentifier: paris,
                                        recordedSeconds: 1_200, declaredAt: at(12, 8))
        #expect(other.counts(capture) && !value.counts(capture))
        let shifted = try ObservationWindowCapture(windowID: value.id, dayKey: "2026-10-12", timeZoneIdentifier: paris,
            expectedStart: at(12, 9), expectedEnd: at(12, 9, 20), actualStart: at(12, 9), actualEnd: at(12, 9, 20),
            declaredAt: at(12, 10))
        #expect(!value.counts(shifted), "The expected interval must be the window's own.")
    }

    // MARK: Saved state

    @Test func everyStateSurvivesSavingAndNothingTranslatedIsStored() throws {
        var value = try window(weekdays: [.saturday, .monday, .wednesday], mornings: 5)
        var saved = [value]
        try value.start(at: at(12, 6)); saved.append(value)
        try value.skip(dayKey: "2026-10-14", at: at(12, 8)); saved.append(value)
        try value.pause(at: at(12, 9)); saved.append(value)
        try value.start(at: at(16, 9)); saved.append(value)
        value.stop(at: try at(17, 9)); saved.append(value)
        var completed = try window(mornings: 1)
        try completed.start(at: at(12, 6))
        let outcome9 = try completed.completeIfDue(at: at(12, 8))
        #expect(outcome9)
        saved.append(completed)
        #expect(saved.map(\.state) == [.planned, .active, .active, .paused, .active, .stopped, .completed])

        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        for window in saved {
            let data = try encoder.encode(window)
            try #expect(JSONDecoder().decode(LearningWindow.self, from: data) == window)
            try #expect(encoder.encode(JSONDecoder().decode(LearningWindow.self, from: data)) == data)
        }
        let text = try #require(String(data: encoder.encode(saved[3]), encoding: .utf8))
        #expect(text.contains("\"schemaVersion\":1"))
        #expect(text.contains("\"state\":\"paused\""))
        #expect(text.contains("\"weekdays\":[2,4,7]"), "Weekdays are numbers, in a stable order.")
        #expect(text.contains("\"timeZoneIdentifier\":\"Europe\\/Paris\""))
    }

    @Test func anOlderSavedWindowStillLoadsAndANewerOrContradictoryOneIsRefused() throws {
        // The smallest record a first build could have written: no version, allowances, pauses or skips.
        let started = try at(12, 6).timeIntervalSinceReferenceDate
        let old = """
        {"id":"7B0E6A53-5D0C-4B7E-9C1E-0A6B1F2D3C4E","startMinuteOfDay":420,"durationSeconds":2400,
         "weekdays":[2,3,4,5,6],"timeZoneIdentifier":"Europe/Paris","morningCount":3,
         "createdAt":\(started - 60),"state":"active","startedAt":\(started)}
        """
        let loaded = try JSONDecoder().decode(LearningWindow.self, from: Data(old.utf8))
        #expect(loaded.state == .active && loaded.morningCount == 3 && loaded.pauses.isEmpty)
        // Forty minutes is longer than today's recorder allows. It is still the person's window.
        #expect(loaded.durationSeconds == 2_400)
        #expect(loaded.lateStartAllowanceSeconds == 180 && loaded.earlyEndAllowanceSeconds == 60)
        try #expect(loaded.schedule(asOf: at(12, 6)).mornings.map(\.dayKey) == ["2026-10-12", "2026-10-13", "2026-10-14"])

        func decode(_ changes: (inout [String: Any]) -> Void) throws -> LearningWindow {
            var object = try #require(JSONSerialization.jsonObject(with: Data(old.utf8)) as? [String: Any])
            changes(&object)
            return try JSONDecoder().decode(LearningWindow.self, from: JSONSerialization.data(withJSONObject: object))
        }
        #expect(throws: LearningWindowError.unsupportedVersion(2)) { try decode { $0["schemaVersion"] = 2 } }
        #expect(throws: LearningWindowError.unsupportedVersion(0)) { try decode { $0["schemaVersion"] = 0 } }
        #expect(throws: LearningWindowError.invalidRecord) { try decode { $0["weekdays"] = [8] } }
        #expect(throws: LearningWindowError.invalidRecord) { try decode { $0["weekdays"] = [Int]() } }
        #expect(throws: LearningWindowError.invalidRecord) { try decode { $0["timeZoneIdentifier"] = "Nowhere/None" } }
        #expect(throws: LearningWindowError.invalidRecord) { try decode { $0["state"] = "planned" } }
        #expect(throws: LearningWindowError.invalidRecord) { try decode { $0["state"] = "paused" } }
        #expect(throws: LearningWindowError.invalidRecord) { try decode { $0["state"] = "stopped" } }
        #expect(throws: LearningWindowError.invalidRecord) { try decode { $0["startedAt"] = nil } }
        #expect(throws: LearningWindowError.invalidRecord) { try decode { $0["endedAt"] = started + 10 } }
        #expect(throws: LearningWindowError.invalidRecord) {
            try decode { $0["pauses"] = [["from": started + 10]] }
        }
        // A stopped window stays stopped when it is read back.
        var stopped = try decode { $0["state"] = "stopped"; $0["endedAt"] = started + 10 }
        #expect(stopped.state == .stopped)
        let outcome10 = try stopped.stop(at: at(20, 6))
        #expect(!outcome10)
        #expect(throws: (any Error).self) { try decode { $0["state"] = "running" } }
    }
}
