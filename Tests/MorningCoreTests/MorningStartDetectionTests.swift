import Foundation
import Testing
@testable import MorningCore

@Suite("Morning starts after three hours without use")
struct MorningStartDetectionTests {
    private var calendar: Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "Europe/Paris")!
        return calendar
    }

    private func at(_ hour: Int, _ minute: Int = 0, day: Int = 14) -> Date {
        calendar.date(from: DateComponents(year: 2026, month: 10, day: day, hour: hour, minute: minute))!
    }

    private func use(_ from: Date, _ to: Date) -> PhoneUse { PhoneUse(DateInterval(start: from, end: to), source: .appTransition) }

    private func detect(_ uses: [PhoneUse], now: Date? = nil, sleepEnd: Date? = nil,
                        coveredFrom: Date? = nil) -> MorningDetectionResult {
        MorningStartDetector.detect(uses: uses, on: at(12), coveredFrom: coveredFrom ?? at(18, day: 13),
                                    now: now ?? at(14), sleepEnd: sleepEnd, calendar: calendar)
    }

    @Test func firstUseAfterSleepStartsTheMorningAndAPauseEndsIt() throws {
        let result = detect([use(at(22, day: 13), at(23, day: 13)), use(at(7, 12), at(7, 30)),
                             use(at(7, 40), at(8, 5)), use(at(9, 0), at(9, 10))])
        guard case .found(let morning) = result else { Issue.record("\(result)"); return }
        #expect(morning.start == at(7, 12))
        #expect(morning.end == at(8, 5))
        #expect(morning.endReason == .pause)
        #expect(morning.skippedSessions.isEmpty)
    }

    @Test func aShortNightCheckAtThreeIsSkipped() throws {
        let result = detect([use(at(23, day: 13), at(23, 30, day: 13)), use(at(3, 0), at(3, 4)),
                             use(at(7, 0), at(7, 45))])
        guard case .found(let morning) = result else { Issue.record("\(result)"); return }
        #expect(morning.start == at(7, 0))
        #expect(morning.skippedSessions == [DateInterval(start: at(3, 0), end: at(3, 4))])
    }

    @Test func aNightCheckWithoutAnotherSleepAfterItIsTheMorning() throws {
        // Up at 04:30 and stayed on: there is no later sleep-length gap, so this is the morning.
        let result = detect([use(at(23, day: 13), at(23, 30, day: 13)), use(at(4, 30), at(4, 40)), use(at(4, 50), at(5, 30))])
        guard case .found(let morning) = result else { Issue.record("\(result)"); return }
        #expect(morning.start == at(4, 30))
    }

    @Test func aNightCheckFollowedSoonByMoreUseIsTheMorning() throws {
        // 04:30 then 05:30: no sleep gap after 04:30, so a later 10:00 session must not win.
        let result = detect([use(at(23, day: 13), at(23, 30, day: 13)), use(at(4, 30), at(4, 40)),
                             use(at(5, 30), at(6, 0)), use(at(10, 0), at(10, 30))])
        guard case .found(let morning) = result else { Issue.record("\(result)"); return }
        #expect(morning.start == at(4, 30))
    }

    @Test func twoBusyHoursDoNotHideAPauseAcrossTheirBoundary() throws {
        // Real use 07:00–07:41 and 08:19–09:00: each hour is busy, but the pause is 38 minutes.
        let uses = PhoneUse.fromScreenTimeSegment(hour: DateInterval(start: at(7), end: at(8)), totalSeconds: 41 * 60,
                                                  firstPickup: nil, longestActivity: nil)
            + PhoneUse.fromScreenTimeSegment(hour: DateInterval(start: at(8), end: at(9)), totalSeconds: 41 * 60,
                                             firstPickup: nil, longestActivity: nil)
        guard case .found(let morning) = detect(uses, now: at(14)) else { Issue.record("no morning"); return }
        #expect(morning.end <= at(7, 41))
        #expect(morning.endReason == .pause)
    }

    @Test func idleBeforeAKnownPickupIsNotCountedTwice() throws {
        // 41 minutes from a 07:10 pickup means use until at least 07:51; 08:05 is within the pause rule.
        let uses = PhoneUse.fromScreenTimeSegment(hour: DateInterval(start: at(7), end: at(8)), totalSeconds: 41 * 60,
                                                  firstPickup: at(7, 10), longestActivity: DateInterval(start: at(7, 10), end: at(7, 30)))
            + [use(at(8, 5), at(8, 10))]
        guard case .found(let morning) = detect(uses, now: at(14)) else { Issue.record("no morning"); return }
        #expect(morning.start == at(7, 10))
        #expect(morning.end == at(8, 10))
    }

    @Test func longUseIsCappedAndRecentUseIsOngoing() throws {
        guard case .found(let capped) = detect([use(at(6, 0), at(10, 0))]) else { Issue.record("no morning"); return }
        #expect(capped.end == at(9, 0))
        #expect(capped.endReason == .cap)
        guard case .found(let live) = detect([use(at(6, 0), at(6, 50))], now: at(7, 0)) else { Issue.record("no morning"); return }
        #expect(live.endReason == .ongoing)
        #expect(live.end == at(7, 0))
    }

    @Test func sleepEndHintChoosesTheSessionAfterWaking() throws {
        // 02:00 is long and would count as the morning without the hint.
        let result = detect([use(at(2, 0), at(2, 40)), use(at(7, 5), at(7, 30))], sleepEnd: at(7, 0))
        guard case .found(let morning) = result else { Issue.record("\(result)"); return }
        #expect(morning.start == at(7, 5))
        #expect(morning.usedSleepHint)
        #expect(morning.skippedSessions.count == 1)
    }

    @Test func recordedSleepDoesNotFallBackToANightCheckWhenWakingUseIsMissing() {
        #expect(detect([use(at(2), at(2, 40))], sleepEnd: at(7)) == .noData)
        // A hint on a different day cannot establish this day's wake-up.
        #expect(detect([use(at(7), at(7, 30))], sleepEnd: at(7, day: 13), coveredFrom: at(7)) == .noSleepGapCovered)
    }

    @Test func noDataAndUncoveredGapsAreNotGuessed() {
        #expect(detect([]) == .noData)
        // Coverage starts at 06:00: the 06:30 use cannot be shown to follow three idle hours.
        #expect(detect([use(at(6, 30), at(7, 0))], coveredFrom: at(6)) == .noSleepGapCovered)
        // Use only on another day.
        #expect(detect([use(at(8, day: 13), at(9, day: 13))]) == .noData)
    }

    @Test func dayFollowsTheCalendarTimeZone() throws {
        // 23:30 UTC on the 13th is 01:30 on the 14th in Paris; it belongs to the 14th there.
        let uses = [use(at(1, 30), at(1, 50))]
        guard case .found(let morning) = detect(uses) else { Issue.record("no morning"); return }
        #expect(calendar.component(.day, from: morning.start) == 14)
        var utc = Calendar(identifier: .gregorian); utc.timeZone = TimeZone(identifier: "UTC")!
        let inUTC = MorningStartDetector.detect(uses: uses, on: at(12), coveredFrom: at(18, day: 13),
                                                now: at(14), calendar: utc)
        // In UTC that use is on the 13th, so the 14th (UTC) has none.
        #expect(inUTC == .noData)
    }

    @Test func screenTimeHourBecomesTimedEvidenceOnlyWhereTheSystemGaveATime() {
        let hour = DateInterval(start: at(7), end: at(8))
        let pickup = PhoneUse.fromScreenTimeSegment(hour: hour, totalSeconds: 600, firstPickup: at(7, 12), longestActivity: nil)
        #expect(pickup == [PhoneUse(at: at(7, 12), source: .screenTimePickup)])
        let coarse = PhoneUse.fromScreenTimeSegment(hour: hour, totalSeconds: 600, firstPickup: nil, longestActivity: nil)
        #expect(coarse.first?.source == .screenTimeHour)
        #expect(PhoneUse.fromScreenTimeSegment(hour: hour, totalSeconds: 0, firstPickup: nil, longestActivity: nil).isEmpty)
    }

    @Test func aBusyHourHasNoRoomForAPauseSoItIsContinuous() throws {
        // Phone pattern of 14 October: first pickup 05:55, then 59 and 56 minutes of use, then light use.
        let hours = [(5, 281.0, at(5, 55)), (6, 3568.0, at(6)), (7, 3381.0, at(7)), (8, 973.0, at(8))]
        var uses: [PhoneUse] = []
        for (h, seconds, pickup) in hours {
            uses += PhoneUse.fromScreenTimeSegment(hour: DateInterval(start: at(h), end: at(h + 1)), totalSeconds: seconds,
                                                   firstPickup: pickup, longestActivity: nil)
        }
        let result = detect(uses, now: at(14))
        guard case .found(let morning) = result else { Issue.record("\(result)"); return }
        #expect(morning.start == at(5, 55))
        #expect(morning.end == at(8, 0))
        #expect(morning.endReason == .pause)
    }
}
