import Foundation
import Testing
@testable import MorningCore

@Suite("Live Activity branding follows the solar clock")
struct MorningActivityBrandClockTests {
    private func calendar(_ zone: String = "Europe/Paris") -> Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: zone)!
        return calendar
    }
    private func date(_ hour: Int, _ minute: Int = 0, calendar: Calendar) -> Date {
        calendar.date(from: DateComponents(year: 2026, month: 10, day: 16, hour: hour, minute: minute))!
    }

    @Test func payloadKeepsTheSameSolarBoundaryAndTimeZoneAsHome() throws {
        let calendar = calendar()
        let solar = MorningSolarDay(sunriseMinute: 8 * 60, sunsetMinute: 17 * 60)
        let clock = MorningActivityBrandClock(solar: solar, calendar: calendar)
        let decoded = try JSONDecoder().decode(MorningActivityBrandClock.self, from: JSONEncoder().encode(clock))
        #expect(decoded == clock)
        for minute in stride(from: 0, to: 1440, by: 5) {
            let instant = date(minute / 60, minute % 60, calendar: calendar)
            let expected = MorningBrandAppearance.resolve(moonOpacity:
                MorningCelestialClock.scene(at: instant, calendar: calendar, solar: solar).moon.opacity)
            #expect(decoded.appearance(at: instant) == expected)
        }
        let json = String(decoding: try JSONEncoder().encode(clock), as: UTF8.self)
        #expect(!json.contains("latitude") && !json.contains("longitude") && !json.contains("location"))
    }

    @Test func progressPauseAndAttentionDoNotChangeTheBrand() throws {
        let calendar = calendar("UTC")
        let clock = MorningActivityBrandClock(solar: .fixed, calendar: calendar)
        let morning = date(10, calendar: calendar), evening = date(23, calendar: calendar)
        for status in MorningActivityStatus.allCases {
            for completed in 0..<3 {
                let state = try MorningActivityContentState(category: .custom, status: status,
                    completedSteps: completed, totalSteps: 3, updatedAt: morning, brandClock: clock)
                #expect(state.brandAppearance(at: morning) == .day)
                // The render date matters even when the last routine update was in the morning.
                #expect(state.brandAppearance(at: evening) == .night)
            }
        }
    }

    @Test func polarDaysAndPreviewPinsRemainStable() {
        let calendar = calendar()
        for hour in [0, 8, 12, 18, 23] {
            let instant = date(hour, calendar: calendar)
            let day = MorningActivityBrandClock(solar: .init(sunriseMinute: 0, sunsetMinute: 0,
                                                            condition: .allDay), calendar: calendar)
            let night = MorningActivityBrandClock(solar: .init(sunriseMinute: 0, sunsetMinute: 0,
                                                              condition: .allNight), calendar: calendar)
            #expect(day.appearance(at: instant) == .day)
            #expect(night.appearance(at: instant) == .night)
            #expect(MorningActivityBrandClock(solar: .fixed, calendar: calendar,
                pinnedAppearance: .night).appearance(at: instant) == .night)
        }
    }

    @Test func olderPayloadsStillDecodeAndClockChangesArePublished() throws {
        let instant = date(10, calendar: calendar())
        let old = try MorningActivityContentState(category: .briefing, status: .paused,
            completedSteps: 0, totalSteps: 1, updatedAt: instant)
        let json = try JSONEncoder().encode(old)
        #expect(!String(decoding: json, as: UTF8.self).contains("brandClock"))
        let decoded = try JSONDecoder().decode(MorningActivityContentState.self, from: json)
        #expect(decoded == old && decoded.brandClock == nil)
        let clock = MorningActivityBrandClock(solar: .fixed, calendar: calendar())
        let branded = try MorningActivityContentState(category: .briefing, status: .paused,
            completedSteps: 0, totalSteps: 1, updatedAt: instant, brandClock: clock)
        #expect(!old.hasSameProgress(as: branded))
        #expect(try JSONDecoder().decode(MorningActivityContentState.self, from: JSONEncoder().encode(branded)) == branded)
        #expect(try JSONEncoder().encode(branded).count < 1_024)
    }
}
