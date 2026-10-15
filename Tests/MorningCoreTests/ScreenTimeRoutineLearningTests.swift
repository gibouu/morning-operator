import Foundation
import Testing
@testable import MorningCore

@Suite("Learning a routine from hourly Screen Time")
struct ScreenTimeRoutineLearningTests {
    private func calendar(_ zone: String = "Europe/Paris") -> Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: zone)!
        return calendar
    }

    private func at(_ hour: Int, _ minute: Int = 0, day: Int = 14, month: Int = 10, zone: String = "Europe/Paris") -> Date {
        calendar(zone).date(from: DateComponents(year: 2026, month: month, day: day, hour: hour, minute: minute))!
    }

    private func app(_ id: String, _ minutes: Double, pickups: Int = 0, category: String? = nil) -> ScreenTimeAppHour {
        ScreenTimeAppHour(bundleIdentifier: id, seconds: minutes * 60, pickups: pickups, categoryName: category)
    }

    private func hour(_ start: Date, pickup: Date? = nil, longest: (Date, Date)? = nil, _ apps: [ScreenTimeAppHour]) -> ScreenTimeHour {
        ScreenTimeHour(interval: DateInterval(start: start, duration: 3600), firstPickup: pickup,
                       longestActivity: longest.map { DateInterval(start: $0.0, end: $0.1) }, apps: apps)
    }

    /// An evening, then a morning from 07:12: a busy hour, a busy hour, and a light one.
    private func ordinaryDay(_ day: Int, startMinute: Int = 12, safari: Double = 40, zone: String = "Europe/Paris",
                             extra: [ScreenTimeAppHour] = []) -> [ScreenTimeHour] {
        let at = { (h: Int, m: Int, d: Int) in self.at(h, m, day: d, zone: zone) }
        return [
            hour(at(22, 0, day - 1), pickup: at(22, 5, day - 1), [app("com.apple.mobilemail", 10)]),
            hour(at(7, 0, day), pickup: at(7, startMinute, day), [
                app("net.whatsapp.WhatsApp", 3, pickups: 2), app("com.apple.mobilesafari", safari, pickups: 1),
                app("com.gibouu.morningoperator", 5), app("com.apple.LocalAuthenticationUIService", 1)] + extra),
            hour(at(8, 0, day), pickup: at(8, 0, day), [app("com.google.ios.youtube", 30, category: "Entertainment"), app("com.chess.iphone", 25)]),
            hour(at(9, 0, day), pickup: at(9, 0, day), longest: (at(9, 0, day), at(9, 4, day)), [app("com.apple.mobilemail", 4)])
        ]
    }

    private func learn(_ hours: [ScreenTimeHour], now: Date? = nil, queryStart: Date? = nil, zone: String = "Europe/Paris") -> ScreenTimeLearning {
        ScreenTimeMorningLearner.learn(hours: hours, queryStart: queryStart ?? at(0, day: 7, zone: zone),
                                       now: now ?? at(14, zone: zone), calendar: calendar(zone))
    }

    // MARK: Names and filtering

    @Test func commonAppsHaveNamesAndUnknownOnesGetAReadableFallback() {
        #expect(ScreenTimeAppCatalog.entry(for: "com.apple.MobileSMS").kind == .messaging)
        #expect(ScreenTimeAppCatalog.entry(for: "net.whatsapp.WhatsApp").name == "WhatsApp")
        #expect(ScreenTimeAppCatalog.entry(for: "com.burbn.instagram").kind == .social)
        #expect(ScreenTimeAppCatalog.entry(for: "com.zhiliaoapp.musically").name == "TikTok")
        #expect(ScreenTimeAppCatalog.entry(for: "com.chess.iphone").name == "Chess.com")
        #expect(ScreenTimeAppCatalog.entry(for: "com.hammerandchisel.discord").name == "Discord")
        #expect(ScreenTimeAppCatalog.entry(for: "ph.telegra.Telegraph").name == "Telegram")
        #expect(ScreenTimeAppCatalog.fallbackName(for: "com.example.MorningNews") == "Morning News")
        #expect(ScreenTimeAppCatalog.fallbackName(for: "com.acme.iphone") == "Acme")
        #expect(ScreenTimeAppCatalog.fallbackName(for: "io.some-tool.app") == "Some Tool")
        #expect(ScreenTimeAppCatalog.entry(for: "com.example.feed", categoryName: "Réseaux sociaux").kind == .social)
        #expect(ScreenTimeAppCatalog.entry(for: "com.example.feed", categoryName: nil).kind == .other)
    }

    @Test func systemHelpersMoreAndTestRunnersAreNoise() {
        for id in ["com.apple.LocalAuthenticationUIService", "com.apple.ScreenshotServicesService", "com.apple.AuthKitUIService",
                   "com.apple.ServicesPaymentAngel", "com.apple.springboard", "com.gibouu.morningoperator",
                   "com.gibouu.morningoperator.screentime", "com.gibouu.morningoperator.uitests.xctrunner",
                   "com.apple.test.MorningOperatorUITests-Runner", ""] {
            #expect(ScreenTimeAppCatalog.isNoise(id), "\(id)")
        }
        for id in ["com.apple.MobileSMS", "com.apple.mobilesafari", "net.whatsapp.WhatsApp", "com.apple.Preferences", "com.chess.iphone"] {
            #expect(!ScreenTimeAppCatalog.isNoise(id), "\(id)")
        }
        #expect(ScreenTimeAppCatalog.isNoise("org.example.more", ownBundleIdentifiers: ["org.example.more"]))
    }

    // MARK: One morning

    @Test func aSingleMorningKeepsMeasuredMinutesAndLikelyOrder() throws {
        let learning = learn(ordinaryDay(14), queryStart: at(18, day: 13))
        let morning = try #require(learning.mornings.last)
        #expect(morning.start == at(7, 12))
        #expect(morning.end == at(9, 4))
        #expect(morning.apps.map(\.bundleIdentifier) == ["net.whatsapp.WhatsApp", "com.apple.mobilesafari",
            "com.google.ios.youtube", "com.chess.iphone", "com.apple.mobilemail"])
        let safari = try #require(morning.apps.first { $0.bundleIdentifier == "com.apple.mobilesafari" })
        #expect(safari.seconds == 40 * 60)
        #expect(safari.secondsMeasured)
        #expect(morning.apps.first?.isFirstPickupApp == true)
        let mail = try #require(morning.apps.last)
        #expect(!mail.secondsMeasured, "The last hour runs past the end of the morning.")
        #expect(mail.firstHourIndex == 2)
        #expect(!morning.apps.contains { $0.bundleIdentifier.hasPrefix("com.gibouu") || $0.bundleIdentifier.contains("LocalAuthentication") })

        let proposal = try #require(ScreenTimeRoutineProposal.make(from: learning, nextMorning: at(7, day: 15), baseRoutineID: nil, calendar: calendar()))
        #expect(proposal.morningsUsed == 1)
        #expect(proposal.typicalStartMinuteOfDay == 7 * 60 + 12)
        #expect(proposal.steps.map(\.title) == ["WhatsApp", "Safari", "YouTube", "Chess.com", "Mail"])
        #expect(proposal.steps.map(\.minutes) == [3, 40, 30, 25, 4])
        #expect(proposal.steps.allSatisfy { !$0.orderMeasured }, "Pickup counts have no times: order is always estimated.")
        #expect(proposal.steps.last?.minutesMeasured == false)
        #expect(proposal.steps.first { $0.title == "YouTube" }?.isAttentionSink == true)
        #expect(proposal.steps.first { $0.title == "Safari" }?.isAttentionSink == false)
    }

    @Test func anHourPastTheEndOfTheMorningIsSharedOutNotCountedInFull() throws {
        var hours = ordinaryDay(14)
        // A light 09:00 hour with 30 min in all and no time for most of it.
        hours[3] = hour(at(9), pickup: at(9), longest: (at(9), at(9, 4)), [app("com.apple.mobilemail", 10), app("com.burbn.instagram", 20)])
        let morning = try #require(learn(hours, queryStart: at(18, day: 13)).mornings.last)
        let lastHour = morning.apps.filter { $0.firstHourIndex == 2 }
        let total = lastHour.reduce(0) { $0 + $1.seconds }
        // Use goes on to 09:30 at least (pickup + 30 min), so the morning ends there.
        #expect(morning.end == at(9, 30))
        #expect(total <= morning.end.timeIntervalSince(at(9)) + 0.001, "At most the minutes the morning spent in that hour.")
        #expect(lastHour.allSatisfy { !$0.secondsMeasured })
    }

    @Test func testDrivenUseOfMoreDoesNotBreakTheNight() throws {
        var hours = ordinaryDay(14)
        hours.append(hour(at(4), pickup: at(4, 10), longest: (at(4, 10), at(4, 55)),
                          [app("com.gibouu.morningoperator", 45), app("com.gibouu.morningoperator.uitests.xctrunner", 1)]))
        let morning = try #require(learn(hours, queryStart: at(18, day: 13)).mornings.last)
        #expect(morning.start == at(7, 12))
        // A Face ID sheet during the test run does not make it the owner's use.
        var withHelper = ordinaryDay(14)
        withHelper.append(hour(at(4), pickup: at(4, 10), longest: (at(4, 10), at(4, 55)),
                               [app("com.gibouu.morningoperator", 45), app("com.apple.LocalAuthenticationUIService", 1)]))
        #expect(learn(withHelper, queryStart: at(18, day: 13)).mornings.last?.start == at(7, 12))
    }

    @Test func anHourReturnedTwiceCountsOnce() throws {
        let hours = ordinaryDay(14) + [hour(at(7), pickup: at(7, 12), [app("com.apple.mobilesafari", 40, pickups: 1),
                                                                         app("net.whatsapp.WhatsApp", 3, pickups: 2)])]
        let morning = try #require(learn(hours, queryStart: at(18, day: 13)).mornings.last)
        let safari = try #require(morning.apps.first { $0.bundleIdentifier == "com.apple.mobilesafari" })
        #expect(safari.seconds == 40 * 60, "\(morning)")
    }

    // MARK: Empty data, coverage and a morning still running

    @Test func noDataGivesNoMorningAndNoProposal() {
        let learning = learn([])
        #expect(learning.mornings.isEmpty)
        #expect(learning.earliestData == nil)
        #expect(learning.daysOfData == 0)
        #expect(ScreenTimeRoutineProposal.make(from: learning, nextMorning: at(7, day: 15), baseRoutineID: nil) == nil)
    }

    @Test func dataThatStartsMidMorningIsNotTakenForAWakeUp() {
        // Screen Time returns nothing before 08:00 on the 12th, although 00:00 on the 7th was asked for.
        let hours = [hour(at(8, day: 12), pickup: at(8, 5, day: 12), [app("com.apple.mobilesafari", 20)])]
        let learning = learn(hours, now: at(14, day: 12))
        #expect(learning.mornings.isEmpty)
        #expect(learning.daysWithoutMorning == 1)
        #expect(learning.earliestData == at(8, day: 12))
    }

    @Test func aMorningStillRunningIsLeftOut() {
        let learning = learn(Array(ordinaryDay(14).prefix(2)), now: at(7, 40), queryStart: at(18, day: 13))
        #expect(learning.mornings.isEmpty)
        // 07:05–07:10 then 07:25–07:29, read at 07:31: the pause seen in hourly data is not final.
        let light = [hour(at(22, day: 13), [app("com.apple.mobilemail", 10)]),
                     hour(at(7), pickup: at(7, 5), longest: (at(7, 5), at(7, 10)), [app("com.apple.mobilesafari", 9)])]
        #expect(learn(light, now: at(7, 31), queryStart: at(18, day: 13)).mornings.isEmpty)
        #expect(learn(light, now: at(8, 45), queryStart: at(18, day: 13)).mornings.count == 1)
    }

    @Test func lightHoursWithUnplacedUseDoNotEndTheMorningEarly() throws {
        // Sessions every 15 min from 07:05 to 08:46: 13 min per hour, but each hour only shows
        // its first pickup and a five-minute longest session.
        let hours = [hour(at(22, day: 13), [app("com.apple.mobilemail", 10)]),
                     hour(at(7), pickup: at(7, 5), longest: (at(7, 5), at(7, 10)), [app("com.apple.mobilesafari", 13)]),
                     hour(at(8), pickup: at(8, 3), longest: (at(8, 3), at(8, 8)), [app("com.apple.mobilesafari", 13)])]
        #expect(learn(hours, now: at(8, 50), queryStart: at(18, day: 13)).mornings.isEmpty, "Still possibly going on.")
        let morning = try #require(learn(hours, now: at(11), queryStart: at(18, day: 13)).mornings.last)
        #expect(morning.end == at(8, 16), "08:03 plus the hour's 13 minutes.")
        let safari = try #require(morning.apps.first)
        #expect(safari.seconds > 13 * 60, "Not only the first five minutes.")
        #expect(!safari.secondsMeasured)
    }

    @Test func aTestRunSharingAnHourWithRealUseDoesNotHideTheMorning() throws {
        var hours = ordinaryDay(14)
        hours.append(hour(at(4), pickup: at(4, 0), longest: (at(4, 10), at(4, 55)),
                          [app("com.apple.mobilesafari", 1), app("com.gibouu.morningoperator", 45)]))
        hours.append(hour(at(5), pickup: at(5, 2), longest: (at(5, 2), at(5, 30)),
                          [app("com.apple.mobilesafari", 1.5), app("com.gibouu.morningoperator.uitests.xctrunner", 28)]))
        let morning = try #require(learn(hours, queryStart: at(18, day: 13)).mornings.last)
        #expect(morning.start == at(7, 12))
    }

    @Test func idleInsideTheFirstHourDoesNotHideUnplacedUse() throws {
        // 07:05 pickup, longest 07:18–07:23, 13 min in all; next use at 08:03.
        let hours = [hour(at(22, day: 13), [app("com.apple.mobilemail", 10)]),
                     hour(at(7), pickup: at(7, 5), longest: (at(7, 18), at(7, 23)), [app("com.apple.mobilesafari", 13)]),
                     hour(at(8), pickup: at(8, 3), longest: (at(8, 3), at(8, 8)), [app("com.apple.MobileSMS", 5)])]
        let morning = try #require(learn(hours, now: at(11), queryStart: at(18, day: 13)).mornings.last)
        #expect(morning.end == at(8, 8))
        #expect(morning.apps.allSatisfy { !$0.secondsMeasured }, "Minutes past the rule's own end are estimated.")
    }

    @Test func theOwnerUsingMoreInHisMorningStillStartsIt() throws {
        let hours = [hour(at(22, day: 13), [app("com.apple.mobilemail", 10)]),
                     hour(at(4), pickup: at(4), longest: (at(4), at(4, 10)), [app("com.apple.mobilesafari", 10)]),
                     hour(at(7), pickup: at(7, 55), longest: (at(7, 55), at(8)),
                          [app("com.gibouu.morningoperator", 3), app("com.apple.mobilesafari", 2)])]
        let morning = try #require(learn(hours, now: at(11), queryStart: at(18, day: 13)).mornings.last)
        #expect(morning.start == at(7, 55))
    }

    @Test func coverageCountsHoursThatWereFilteredOut() throws {
        let hours = [hour(at(22, day: 13), pickup: at(22, 5, day: 13), [app("com.gibouu.morningoperator", 20)]),
                     hour(at(7), pickup: at(7, 12), longest: (at(7, 12), at(7, 40)), [app("com.apple.mobilesafari", 28)])]
        let learning = learn(hours, now: at(11), queryStart: at(0, day: 7))
        #expect(learning.mornings.last?.start == at(7, 12))
    }

    @Test func savedChoicesShapeTheSuggestion() throws {
        let learning = learn(ordinaryDay(14), queryStart: at(18, day: 13))
        var proposal = try #require(ScreenTimeRoutineProposal.make(from: learning, nextMorning: at(7, day: 15), baseRoutineID: nil, calendar: calendar()))
        var journal = RoutinePreferenceJournal()
        let exclude = try RoutinePreference(target: RoutineStep(title: "YouTube", kind: .entertainment), presence: .exclude)
        try journal.upsert(exclude)
        let timing = try RoutinePreference(target: RoutineStep(title: "Safari", kind: .custom), durationMinutes: 12)
        try journal.upsert(timing)
        let kept = proposal.applyPreferences(journal)
        #expect(kept)
        #expect(!proposal.steps.contains { $0.title == "YouTube" })
        #expect(proposal.steps.first { $0.title == "Safari" }?.minutes == 12)
    }

    @Test func aLongUseAtNightIsNotSkippedAsANightCheck() throws {
        let hours = [hour(at(22, day: 13), [app("com.apple.mobilemail", 10)]),
                     hour(at(3), pickup: at(3), longest: (at(3), at(3, 10)), [app("com.apple.mobilesafari", 30)]),
                     hour(at(7), pickup: at(7, 5), longest: (at(7, 5), at(7, 30)), [app("com.apple.MobileSMS", 25)])]
        let morning = try #require(learn(hours, now: at(12), queryStart: at(18, day: 13)).mornings.last)
        #expect(morning.start == at(3))
        let short = [hours[0], hour(at(3), pickup: at(3), longest: (at(3), at(3, 4)), [app("com.apple.mobilesafari", 4)]), hours[2]]
        #expect(learn(short, now: at(12), queryStart: at(18, day: 13)).mornings.last?.start == at(7, 5))
    }

    @Test func savedChoicesApplyByTitleEvenWithDuplicatesOrKeeps() throws {
        let hours = [hour(at(22, day: 13), [app("com.apple.mobilemail", 10)]),
                     hour(at(7), pickup: at(7, 5), longest: (at(7, 5), at(7, 50)),
                          [app("com.lichess.mobileapp", 10), app("org.lichess.mobileapp", 8), app("com.apple.mobilesafari", 20), app("com.apple.MobileSMS", 12)])]
        let learning = learn(hours, now: at(12), queryStart: at(18, day: 13))
        var proposal = try #require(ScreenTimeRoutineProposal.make(from: learning, nextMorning: at(7, day: 15), baseRoutineID: nil, calendar: calendar()))
        var journal = RoutinePreferenceJournal()
        let lichess = try RoutinePreference(target: RoutineStep(title: "Lichess", kind: .entertainment), durationMinutes: 6)
        let safari = try RoutinePreference(target: RoutineStep(title: "Safari", kind: .custom), presence: .exclude)
        let messages = try RoutinePreference(target: RoutineStep(title: "Messages", kind: .messages), presence: .keep, durationMinutes: 5)
        for entry in [lichess, safari, messages] { try journal.upsert(entry) }
        let kept = proposal.applyPreferences(journal)
        #expect(kept)
        #expect(!proposal.steps.contains { $0.title == "Safari" })
        #expect(proposal.steps.filter { $0.title == "Lichess" }.allSatisfy { $0.minutes == 6 })
        #expect(proposal.steps.first { $0.title == "Messages" }?.minutes == 5)
    }

    @Test func untimedMinutesCloseAGapTheyMustFill() throws {
        // 22:00 hour: 30 min, longest 22:00–22:10, so use goes on to 22:30 at least.
        let hours = [hour(at(22, day: 13), pickup: at(22, 0, day: 13), longest: (at(22, 0, day: 13), at(22, 10, day: 13)), [app("com.apple.mobilesafari", 30)]),
                     hour(at(1), pickup: at(1, 15), longest: (at(1, 15), at(1, 35)), [app("com.apple.mobilesafari", 20)]),
                     hour(at(7), pickup: at(7), longest: (at(7), at(7, 25)), [app("com.apple.MobileSMS", 25)])]
        #expect(learn(hours, now: at(12), queryStart: at(18, day: 13)).mornings.last?.start == at(7))
        // A short check at 00:30 stays skipped when a long use follows at 04:00.
        let nights = [hour(at(20, day: 13), pickup: at(20, 0, day: 13), [app("com.apple.mobilesafari", 5)]),
                      hour(at(0), pickup: at(0, 30), longest: (at(0, 30), at(0, 34)), [app("com.apple.mobilesafari", 4)]),
                      hour(at(4), pickup: at(4), longest: (at(4), at(4, 10)), [app("com.apple.mobilesafari", 30)]),
                      hour(at(8), pickup: at(8), longest: (at(8), at(8, 25)), [app("com.apple.MobileSMS", 25)])]
        #expect(learn(nights, now: at(12), queryStart: at(18, day: 13)).mornings.last?.start == at(4))
    }

    @Test func theBoundNeitherMeasuresMinutesNorStartsAMorning() throws {
        // 07:00 pickup, 19 min, longest 07:30–07:45: a 26-minute pause is possible, so the
        // first hour is not measured.
        let gap = [hour(at(22, day: 13), [app("com.apple.mobilemail", 10)]),
                   hour(at(7), pickup: at(7), longest: (at(7, 30), at(7, 45)), [app("com.apple.mobilesafari", 19)]),
                   hour(at(8), pickup: at(8), longest: (at(8), at(8, 10)), [app("com.apple.MobileSMS", 10)])]
        let morning = try #require(learn(gap, now: at(12), queryStart: at(18, day: 13)).mornings.last)
        #expect(morning.apps.first { $0.bundleIdentifier == "com.apple.mobilesafari" }?.secondsMeasured == false)
        // No pickup, longest 07:45–07:55, 10 min: the morning starts at 07:45, not at a bound.
        let late = [hour(at(22, day: 13), [app("com.apple.mobilemail", 10)]),
                    hour(at(7), longest: (at(7, 45), at(7, 55)), [app("com.apple.mobilesafari", 10)])]
        #expect(learn(late, now: at(12), queryStart: at(18, day: 13)).mornings.last?.start == at(7, 45))
        // No pickup, longest 07:45–07:55, but 30 min in the hour: use began by 07:30.
        let early = [late[0], hour(at(7), longest: (at(7, 45), at(7, 55)), [app("com.apple.mobilesafari", 30)])]
        let morning2 = try #require(learn(early, now: at(12), queryStart: at(18, day: 13)).mornings.last)
        #expect(morning2.start <= at(7, 30))
        #expect(morning2.apps.allSatisfy { !$0.secondsMeasured })
    }

    @Test func boundsBridgeRealGapsAndKeepNightChecksShort() throws {
        // 07:45–07:54 timed, 10 min in all, then 08:10–08:20: one morning.
        let joined = [hour(at(22, day: 13), [app("com.apple.mobilemail", 10)]),
                      hour(at(7), pickup: at(7, 45), longest: (at(7, 45), at(7, 54)), [app("com.apple.mobilesafari", 10)]),
                      hour(at(8), pickup: at(8, 10), longest: (at(8, 10), at(8, 20)), [app("com.apple.MobileSMS", 10)])]
        let morning = try #require(learn(joined, now: at(12), queryStart: at(18, day: 13)).mornings.last)
        #expect(morning.end == at(8, 20))
        #expect(morning.apps.contains { $0.bundleIdentifier == "com.apple.MobileSMS" })
        // 03:50–03:54, 5 min in all, then 07:05: still a night check.
        let night = [hour(at(22, day: 13), [app("com.apple.mobilemail", 10)]),
                     hour(at(3), pickup: at(3, 50), longest: (at(3, 50), at(3, 54)), [app("com.apple.mobilesafari", 5)]),
                     hour(at(7), pickup: at(7, 5), longest: (at(7, 5), at(7, 30)), [app("com.apple.MobileSMS", 25)])]
        #expect(learn(night, now: at(12), queryStart: at(18, day: 13)).mornings.last?.start == at(7, 5))
        // 03:00 hour without pickup: 20 min, longest 03:45–03:55. Not a night check by its total.
        let busyNight = [night[0], hour(at(3), longest: (at(3, 45), at(3, 55)), [app("com.apple.mobilesafari", 20)]), night[2]]
        let start = try #require(learn(busyNight, now: at(12), queryStart: at(18, day: 13)).mornings.last?.start)
        #expect(calendar().component(.hour, from: start) == 3)
        // Exactly 15 min, but in more than one stretch (longest 10 min): longer than a check.
        let split = [night[0], hour(at(3), pickup: at(3, 40), longest: (at(3, 45), at(3, 55)), [app("com.apple.mobilesafari", 15)]), night[2]]
        #expect(learn(split, now: at(12), queryStart: at(18, day: 13)).mornings.last?.start == at(3, 40))
        // One unbroken 15-minute check across 04:00 is still a night check.
        let across = [night[0], hour(at(3), pickup: at(3, 55), longest: (at(3, 55), at(4)), [app("com.apple.mobilesafari", 5)]),
                      hour(at(4), pickup: at(4), longest: (at(4), at(4, 10)), [app("com.apple.mobilesafari", 10)]),
                      hour(at(7), pickup: at(7, 15), longest: (at(7, 15), at(7, 40)), [app("com.apple.MobileSMS", 25)])]
        #expect(learn(across, now: at(12), queryStart: at(18, day: 13)).mornings.last?.start == at(7, 15))
        // 07:30–08:00 fully timed, then 08:30: the pause at the hour is real.
        let pause = [hour(at(22, day: 13), [app("com.apple.mobilemail", 10)]),
                     hour(at(7), pickup: at(7, 30), longest: (at(7, 30), at(8)), [app("com.apple.mobilesafari", 30)]),
                     hour(at(8), pickup: at(8, 30), longest: (at(8, 30), at(8, 40)), [app("com.apple.MobileSMS", 15)])]
        let ended = try #require(learn(pause, now: at(12), queryStart: at(18, day: 13)).mornings.last)
        #expect(ended.end == at(8))
        #expect(!ended.apps.contains { $0.bundleIdentifier == "com.apple.MobileSMS" })
    }

    @Test func useAroundMidnightIsNotADoubleMorning() {
        let hours = [hour(at(20, day: 13), pickup: at(20, 0, day: 13), longest: (at(20, 0, day: 13), at(20, 10, day: 13)), [app("com.apple.mobilesafari", 10)]),
                     hour(at(0, day: 14), pickup: at(0, 0, day: 14), longest: (at(0, 0, day: 14), at(0, 30, day: 14)), [app("com.apple.mobilesafari", 30)]),
                     hour(at(8, day: 14), pickup: at(8, 5, day: 14), longest: (at(8, 5, day: 14), at(8, 30, day: 14)), [app("com.apple.MobileSMS", 25)])]
        let learning = learn(hours, queryStart: at(12, day: 13))
        #expect(Set(learning.mornings.map(\.start)).count == learning.mornings.count)
        #expect(learning.mornings.allSatisfy { calendar().component(.hour, from: $0.start) < 14 })
    }

    @Test func daysOfDataCountsFromTheEarliestReturnedHour() {
        let hours = ordinaryDay(10) + ordinaryDay(12) + ordinaryDay(14)
        let learning = learn(hours)
        #expect(learning.earliestData == at(22, day: 9))
        #expect(learning.daysOfData == 6) // 9th to 14th
        #expect(learning.mornings.count == 3, "The evenings of the 11th and 13th are not mornings.")
        #expect(learning.mornings.allSatisfy { calendar().component(.hour, from: $0.start) == 7 })
    }

    // MARK: Several mornings

    @Test func severalMorningsGiveMedianMinutesStartAndRecurringApps() throws {
        // Five weekdays, 12–16 October 2026.
        let starts = [0, 10, 20, 30, 59]
        let safari: [Double] = [10, 20, 30, 40, 50]
        var hours: [ScreenTimeHour] = []
        for (index, day) in (12...16).enumerated() {
            var extra: [ScreenTimeAppHour] = []
            if index < 3 { extra.append(app("com.apple.weather", 2)) } // 3 of 5: kept
            if index < 2 { extra.append(app("com.reddit.Reddit", 5)) } // 2 of 5: dropped
            hours += ordinaryDay(day, startMinute: starts[index], safari: safari[index], extra: extra)
        }
        let learning = learn(hours, now: at(14, day: 16))
        #expect(learning.mornings.count == 5)
        let proposal = try #require(ScreenTimeRoutineProposal.make(from: learning, nextMorning: at(7, day: 19), baseRoutineID: nil, calendar: calendar()))
        #expect(proposal.morningsUsed == 5)
        #expect(proposal.typicalStartMinuteOfDay == 7 * 60 + 20)
        #expect(proposal.steps.first { $0.title == "Safari" }?.medianMinutes == 30)
        #expect(proposal.steps.contains { $0.bundleIdentifier == "com.apple.weather" })
        #expect(!proposal.steps.contains { $0.bundleIdentifier == "com.reddit.Reddit" })
        #expect(proposal.steps.first { $0.bundleIdentifier == "com.apple.weather" }?.morningsSeen == 3)
    }

    @Test func weekendMorningsAreComparedWithWeekendMornings() throws {
        // Thu 15, Fri 16 at 07:12; Sat 17, Sun 18 at 09:30 with TikTok.
        var hours = ordinaryDay(15) + ordinaryDay(16)
        for day in [17, 18] {
            hours += [hour(at(9, day: day), pickup: at(9, 30, day: day), [app("com.zhiliaoapp.musically", 25, pickups: 1)])]
        }
        let learning = learn(hours, now: at(14, day: 18))
        let saturday = try #require(ScreenTimeRoutineProposal.make(from: learning, nextMorning: at(8, day: 24), baseRoutineID: nil, calendar: calendar()))
        #expect(saturday.morningsUsed == 2)
        #expect(saturday.typicalStartMinuteOfDay == 9 * 60 + 30)
        #expect(saturday.steps.map(\.title) == ["TikTok"])
        #expect(saturday.steps.first?.isAttentionSink == true)
        let monday = try #require(ScreenTimeRoutineProposal.make(from: learning, nextMorning: at(8, day: 19), baseRoutineID: nil, calendar: calendar()))
        #expect(monday.typicalStartMinuteOfDay == 7 * 60 + 12)
        #expect(!monday.steps.contains { $0.title == "TikTok" })
    }

    @Test func theFirstPickupAppLeadsThenHourThenMinutes() throws {
        // Messages has fewer minutes than Safari in the same hour but was opened from the Lock Screen.
        let hours = [hour(at(22, day: 13), [app("com.apple.mobilemail", 10)]),
                     hour(at(7), pickup: at(7, 5), [app("com.apple.mobilesafari", 30), app("com.apple.MobileSMS", 2, pickups: 3),
                                                    app("com.apple.mobilecal", 10)]),
                     hour(at(8), pickup: at(8), longest: (at(8), at(8, 10)), [app("com.burbn.instagram", 50)])]
        let learning = learn(hours, queryStart: at(18, day: 13))
        let proposal = try #require(ScreenTimeRoutineProposal.make(from: learning, nextMorning: at(7, day: 15), baseRoutineID: nil, calendar: calendar()))
        #expect(proposal.steps.map(\.title) == ["Messages", "Safari", "Calendar", "Instagram"])
    }

    // MARK: Time zones

    @Test func aMorningIsFoundOnItsLocalDayInAnyTimeZone() throws {
        // 07:12 in Tokyo is 22:12 UTC the day before.
        let zone = "Asia/Tokyo"
        let learning = learn(ordinaryDay(14, zone: zone), now: at(14, zone: zone), queryStart: at(18, day: 13, zone: zone), zone: zone)
        let morning = try #require(learning.mornings.last)
        #expect(morning.start == at(7, 12, zone: zone))
        #expect(morning.startMinuteOfDay == 7 * 60 + 12)
    }

    @Test func theDaylightSavingNightDoesNotShiftTheMorning() throws {
        // Paris leaves summer time on Sunday 25 October 2026 at 03:00.
        let hours = [hour(at(22, day: 24), [app("com.apple.mobilemail", 10)]),
                     hour(at(8, day: 25), pickup: at(8, 15, day: 25), longest: (at(8, 15, day: 25), at(8, 40, day: 25)),
                          [app("com.apple.mobilesafari", 25, pickups: 1)])]
        let learning = learn(hours, now: at(14, day: 25), queryStart: at(18, day: 24))
        let morning = try #require(learning.mornings.last)
        #expect(morning.startMinuteOfDay == 8 * 60 + 15)
    }

    @Test func afterTravelEachMorningKeepsItsOwnLocalTime() throws {
        let paris = ScreenTimeMorning(start: at(7, 0, day: 13), end: at(8, 0, day: 13), endReason: .pause,
            timeZone: TimeZone(identifier: "Europe/Paris")!,
            apps: [.init(bundleIdentifier: "com.apple.MobileSMS", seconds: 300, secondsMeasured: true, firstHourIndex: 0, isFirstPickupApp: true, categoryName: nil)])
        let newYork = ScreenTimeMorning(start: at(7, 0, day: 14, zone: "America/New_York"), end: at(8, 0, day: 14, zone: "America/New_York"),
            endReason: .pause, timeZone: TimeZone(identifier: "America/New_York")!,
            apps: [.init(bundleIdentifier: "com.apple.MobileSMS", seconds: 420, secondsMeasured: true, firstHourIndex: 0, isFirstPickupApp: true, categoryName: nil)])
        let learning = ScreenTimeLearning(mornings: [paris, newYork], earliestData: at(0, day: 12), daysOfData: 3, daysWithoutMorning: 1)
        let proposal = try #require(ScreenTimeRoutineProposal.make(from: learning, nextMorning: at(7, day: 15), baseRoutineID: nil, calendar: calendar()))
        #expect(proposal.typicalStartMinuteOfDay == 7 * 60)
        #expect(proposal.steps.first?.medianMinutes == 6)
    }

    // MARK: The draft and the saved suggestion

    @Test func theDraftHasOnlyIncludedStepsWithEditedMinutesAndIsNotApproved() throws {
        let learning = learn(ordinaryDay(14), queryStart: at(18, day: 13))
        var proposal = try #require(ScreenTimeRoutineProposal.make(from: learning, nextMorning: at(7, day: 15), baseRoutineID: nil, calendar: calendar()))
        let youtube = try #require(proposal.steps.first { $0.title == "YouTube" })
        let safari = try #require(proposal.steps.first { $0.title == "Safari" })
        proposal.setIncluded(false, stepID: youtube.id)
        proposal.setMinutes(15, stepID: safari.id)
        proposal.setMinutes(10_000, stepID: try #require(proposal.steps.first).id)
        let base = DemoFixtures.candidateRoutine.approved()
        let draft = try proposal.draft(preserving: base)
        #expect(!draft.isApproved)
        #expect(draft.number == base.number + 1)
        #expect(draft.steps.map(\.title) == ["WhatsApp", "Safari", "Chess.com", "Mail"])
        #expect(draft.steps[0].durationMinutes == ScreenTimeRoutineProposal.minutesRange.upperBound)
        #expect(draft.steps[1].durationMinutes == 15)
        #expect(draft.steps.allSatisfy { $0.automation == nil && !$0.isRequired })
        #expect(draft.steps.map(\.target) == [.externalApp(.whatsapp, detail: nil), nil, nil, .externalApp(.mail, detail: nil)])
        #expect(draft.steps[3].detail.contains("Estimated"))
        #expect(draft.steps[1].detail.contains("Measured"))

        for step in proposal.steps { proposal.setIncluded(false, stepID: step.id) }
        #expect(throws: ScreenTimeProposalError.nothingIncluded) { try proposal.draft(preserving: nil) }
    }

    @Test func aSavedSuggestionRoundTripsAndADamagedOneIsRefused() throws {
        let learning = learn(ordinaryDay(14), queryStart: at(18, day: 13))
        let proposal = try #require(ScreenTimeRoutineProposal.make(from: learning, nextMorning: at(7, day: 15), baseRoutineID: UUID(), calendar: calendar()))
        let data = try JSONEncoder().encode(proposal)
        #expect(try JSONDecoder().decode(ScreenTimeRoutineProposal.self, from: data) == proposal)
        var json = try #require(JSONSerialization.jsonObject(with: data) as? [String: Any])
        var steps = try #require(json["steps"] as? [[String: Any]])
        steps[0]["minutes"] = 0
        json["steps"] = steps
        let damaged = try JSONSerialization.data(withJSONObject: json)
        #expect(throws: (any Error).self) { try JSONDecoder().decode(ScreenTimeRoutineProposal.self, from: damaged) }
    }

    @Test func appNamesAndLabelsHaveFrench() throws {
        let path = try #require(Bundle.module.path(forResource: "fr", ofType: "lproj"))
        let french = try #require(Bundle(path: path))
        #expect(french.localizedString(forKey: "Weather", value: nil, table: nil) == "Météo")
        #expect(french.localizedString(forKey: "Estimated from hourly Screen Time.", value: nil, table: nil)
            == "Estimé à partir des heures de Temps d’écran.")
        let format = french.localizedString(forKey: "Usually %lld min, on %lld of %lld mornings.", value: nil, table: nil)
        #expect(String(format: format, 12, 4, 5) == "En général 12 min, 4 matins sur 5.")
    }
}
