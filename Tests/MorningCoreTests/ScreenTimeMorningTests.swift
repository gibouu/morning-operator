import Foundation
import Testing
@testable import MorningCore

@Suite("Screen Time morning minutes")
struct ScreenTimeMorningTests {
    private var calendar: Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "Europe/Paris")!
        return calendar
    }

    private func at(_ hour: Int, _ minute: Int = 0, day: Int = 14) -> Date {
        calendar.date(from: DateComponents(year: 2026, month: 10, day: day, hour: hour, minute: minute))!
    }

    private func hour(_ h: Int) -> DateInterval { DateInterval(start: at(h), end: at(h + 1)) }

    @Test func minutesAddUpPerAppAcrossHoursAndSortLongestFirst() {
        let window = DateInterval(start: at(5), end: at(11))
        let rows = [
            ScreenTimeUsageRow(segment: hour(7), appName: "Instagram", bundleIdentifier: "com.burbn.instagram", seconds: 600, pickups: 1),
            ScreenTimeUsageRow(segment: hour(8), appName: "Instagram", bundleIdentifier: "com.burbn.instagram", seconds: 300),
            ScreenTimeUsageRow(segment: hour(7), appName: "Messages", bundleIdentifier: "com.apple.MobileSMS", seconds: 240, notifications: 3)
        ]
        let summary = ScreenTimeMorningSummary.summarize(rows: rows, window: window)
        #expect(summary.apps.map(\.name) == ["Instagram", "Messages"])
        #expect(summary.apps[0].roundedMinutes == 15)
        #expect(summary.apps[0].pickups == 1)
        #expect(summary.apps[1].notifications == 3)
        #expect(summary.totalSeconds == 1140)
        #expect(!summary.includesTimeOutsideWindow)
    }

    @Test func repeatedLiveReadOfTheSameSegmentIsCountedOnce() {
        let row = ScreenTimeUsageRow(segment: hour(7), appName: "TikTok", bundleIdentifier: "com.zhiliaoapp.musically", seconds: 120)
        let summary = ScreenTimeMorningSummary.summarize(rows: [row, row], window: DateInterval(start: at(5), end: at(11)))
        #expect(summary.apps.first?.seconds == 120)
    }

    @Test func aLaterReadOfTheSameHourReplacesTheEarlierOne() {
        let first = ScreenTimeUsageRow(segment: hour(7), appName: "Mail", bundleIdentifier: "m", seconds: 120)
        let later = ScreenTimeUsageRow(segment: hour(7), appName: "Mail", bundleIdentifier: "m", seconds: 300)
        let summary = ScreenTimeMorningSummary.summarize(rows: [first, later], window: DateInterval(start: at(5), end: at(11)))
        #expect(summary.apps.first?.seconds == 300)
    }

    @Test func aMorningSeenAsOneMomentStillCountsItsHour() {
        let rows = [ScreenTimeUsageRow(segment: hour(7), appName: "Mail", bundleIdentifier: "m", seconds: 600),
                    ScreenTimeUsageRow(segment: hour(8), appName: "News", bundleIdentifier: "n", seconds: 60)]
        let summary = ScreenTimeMorningSummary.summarize(rows: rows, window: DateInterval(start: at(7), duration: 0))
        #expect(summary.apps.map(\.name) == ["Mail"])
    }

    @Test func notificationsAloneNeitherListAnAppNorSetItsFirstHour() {
        let rows = [
            ScreenTimeUsageRow(segment: hour(5), appName: "Mail", bundleIdentifier: "m", seconds: 0, notifications: 2),
            ScreenTimeUsageRow(segment: hour(9), appName: "Mail", bundleIdentifier: "m", seconds: 600),
            ScreenTimeUsageRow(segment: hour(6), appName: "News", bundleIdentifier: "n", seconds: 0, notifications: 4)
        ]
        let summary = ScreenTimeMorningSummary.summarize(rows: rows, window: DateInterval(start: at(5), end: at(11)))
        #expect(summary.apps.map(\.name) == ["Mail"])
        #expect(summary.apps[0].firstSegmentStart == at(9))
        #expect(summary.apps[0].notifications == 2)
    }

    @Test func segmentsOutsideTheWindowAreDroppedAndPartialOnesAreFlagged() {
        let window = DateInterval(start: at(7, 30), end: at(11))
        let rows = [
            ScreenTimeUsageRow(segment: hour(4), appName: "Safari", bundleIdentifier: "com.apple.mobilesafari", seconds: 900),
            ScreenTimeUsageRow(segment: hour(7), appName: "Mail", bundleIdentifier: "com.apple.mobilemail", seconds: 60)
        ]
        let summary = ScreenTimeMorningSummary.summarize(rows: rows, window: window)
        #expect(summary.apps.map(\.name) == ["Mail"])
        #expect(summary.includesTimeOutsideWindow)
    }

    @Test func ownAppIsLeftOutAndNoRowsMeansNoDataNotZero() {
        let rows = [ScreenTimeUsageRow(segment: hour(6), appName: "MORE", bundleIdentifier: "com.gibouu.morningoperator", seconds: 400)]
        let summary = ScreenTimeMorningSummary.summarize(rows: rows, window: DateInterval(start: at(5), end: at(11)),
                                                         excludingBundleIdentifiers: ["com.gibouu.morningoperator"])
        #expect(summary.isEmpty)
        #expect(summary.firstPickup == nil)
    }

    @Test func firstUseOrderFollowsTheHourThenTheTimeSpent() {
        let rows = [
            ScreenTimeUsageRow(segment: hour(8), appName: "Reddit", bundleIdentifier: "r", seconds: 1200),
            ScreenTimeUsageRow(segment: hour(6), appName: "Calendar", bundleIdentifier: "c", seconds: 30),
            ScreenTimeUsageRow(segment: hour(6), appName: "Messages", bundleIdentifier: "m", seconds: 200)
        ]
        let summary = ScreenTimeMorningSummary.summarize(rows: rows, window: DateInterval(start: at(5), end: at(11)),
                                                         firstPickups: [at(4), at(6, 2)], lastUpdated: [at(9), at(8)])
        #expect(summary.appsInFirstUseOrder.map(\.name) == ["Messages", "Calendar", "Reddit"])
        #expect(summary.firstPickup == at(6, 2))
        #expect(summary.lastUpdated == at(8))
    }

    @Test func morningWindowKeepsLocalHoursAcrossDaylightSavingAndStopsAtNow() throws {
        // 25 October 2026 is the autumn change in Paris.
        let dst = try #require(ScreenTimeMorningSummary.morningWindow(on: at(12, day: 25), now: at(23, day: 25), calendar: calendar))
        #expect(calendar.component(.hour, from: dst.start) == 5)
        #expect(calendar.component(.hour, from: dst.end) == 11)
        let partial = try #require(ScreenTimeMorningSummary.morningWindow(on: at(7), now: at(7, 40), calendar: calendar))
        #expect(partial.end == at(7, 40))
        #expect(ScreenTimeMorningSummary.morningWindow(on: at(4), now: at(4, 30), calendar: calendar) == nil)
        #expect(ScreenTimeMorningSummary.morningWindow(on: at(4), startHour: 9, endHour: 9, calendar: calendar) == nil)
    }
}
