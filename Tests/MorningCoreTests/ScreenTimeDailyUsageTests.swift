import Foundation
import Testing
@testable import MorningCore

@Suite("Actual daily app-use summaries")
struct ScreenTimeDailyUsageTests {
    @Test("Only returned days appear, duplicate hours count once, own and system apps stay out")
    func coverageAndDeduplication() throws {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 0)!
        let start = Date(timeIntervalSinceReferenceDate: 800_000_000)
        let hour = ScreenTimeHour(interval: DateInterval(start: start, duration: 3600), apps: [
            .init(bundleIdentifier: "com.burbn.instagram", seconds: 120),
            .init(bundleIdentifier: "com.gibouu.morningoperator", seconds: 300),
            .init(bundleIdentifier: "com.apple.LocalAuthenticationUIService", seconds: 30)])
        let days = ScreenTimeDailyUsage.summarize(hours: [hour, hour], calendar: calendar)
        #expect(days.count == 1)
        #expect(days[0].summary.apps.map(\.name) == ["Instagram"])
        #expect(days[0].summary.totalSeconds == 120)
        #expect(ScreenTimeDailyUsage.summarize(hours: [], calendar: calendar).isEmpty)
    }

    @Test("Known applications receive the reviewed target; unknown bundles never become URL schemes")
    func safeTargets() {
        #expect(ScreenTimeAppCatalog.routineTarget(for: "com.burbn.instagram") == .inAppWeb(site: WebMorningSite.instagram.table.startURL))
        #expect(ScreenTimeAppCatalog.routineTarget(for: "com.linkedin.LinkedIn") == .inAppWeb(site: WebMorningSite.linkedin.table.startURL))
        #expect(ScreenTimeAppCatalog.routineTarget(for: "com.tinyspeck.chatlyio") == .inAppWeb(site: WebMorningSite.slack.table.startURL))
        #expect(ScreenTimeAppCatalog.routineTarget(for: "com.example.unknown") == nil)
        #expect(ScreenTimeAppCatalog.routineTarget(for: "com.apple.mobilesafari") == nil)
        #expect(ScreenTimeAppCatalog.routineTarget(for: "com.google.Maps") == nil)
    }
}
