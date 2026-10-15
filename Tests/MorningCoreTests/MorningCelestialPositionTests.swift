import Foundation
import Testing
@testable import MorningCore

@Suite("Celestial artwork follows local time")
struct MorningCelestialPositionTests {
    @Test func theSunStartsAtTheBottomCentreAndClimbsToMidday() {
        let dawn = MorningCelestialClock.scene(atMinute: 6 * 60 + 45)
        let morning = MorningCelestialClock.scene(atMinute: 9 * 60)
        let noon = MorningCelestialClock.scene(atMinute: 13 * 60)
        #expect(dawn.sun.centerX == 0.5)
        #expect(dawn.sun.centerY > 0.9)
        #expect(dawn.sun.centerY > morning.sun.centerY)
        #expect(morning.sun.centerY > noon.sun.centerY)
        #expect(abs(noon.sun.centerY - 0.2) < 0.001)
        #expect(noon.sun.opacity == 1 && noon.moon.opacity == 0)
    }

    @Test func eveningLowersTheSunAndNightReplacesItWithTheMoon() {
        let day = MorningCelestialClock.scene(for: .day)
        let evening = MorningCelestialClock.scene(for: .evening)
        let night = MorningCelestialClock.scene(for: .night)
        #expect(evening.sun.centerY > day.sun.centerY)
        #expect(night.sun.opacity == 0)
        #expect(night.moon.opacity == 1)
        #expect(night.moon.centerX == 0.5 && night.moon.centerY < 0.5)
    }

    @Test func theMoonRisesFromTheEveningHorizonAndLowersBeforeDawn() {
        let horizon = MorningCelestialClock.scene(atMinute: 19 * 60)
        let lateEvening = MorningCelestialClock.scene(atMinute: 22 * 60)
        let middleNight = MorningCelestialClock.scene(atMinute: 60)
        let beforeDawn = MorningCelestialClock.scene(atMinute: 5 * 60)
        #expect(horizon.moon.centerX == 0.5 && horizon.moon.centerY == 0.94)
        #expect(horizon.moon.centerY > lateEvening.moon.centerY)
        #expect(lateEvening.moon.centerY > middleNight.moon.centerY)
        #expect(abs(middleNight.moon.centerY - 0.24) < 0.001)
        #expect(beforeDawn.moon.centerY > middleNight.moon.centerY)
    }

    @Test func everyMinuteIsFiniteBoundedAndContinuousIncludingMidnight() {
        var prior = MorningCelestialClock.scene(atMinute: 0)
        for minute in 1...1440 {
            let next = MorningCelestialClock.scene(atMinute: Double(minute))
            for body in [next.sun, next.moon] {
                #expect(body.centerX.isFinite && body.centerY.isFinite && body.opacity.isFinite)
                #expect((0...1).contains(body.opacity))
                #expect((0.2...1.05).contains(body.centerY))
            }
            #expect(abs(next.sun.centerY - prior.sun.centerY) < 0.01)
            #expect(abs(next.moon.centerY - prior.moon.centerY) < 0.01)
            #expect(abs(next.sun.opacity - prior.sun.opacity) < 0.026)
            #expect(abs(next.moon.opacity - prior.moon.opacity) < 0.026)
            prior = next
        }
        #expect(prior == MorningCelestialClock.scene(atMinute: 0))
    }

    @Test func datesUseTheProvidedLocalCalendarAndOutOfRangeMinutesWrap() throws {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = try #require(TimeZone(identifier: "Europe/Paris"))
        let nine = try #require(calendar.date(from: DateComponents(year: 2026, month: 10, day: 15, hour: 9)))
        #expect(MorningCelestialClock.scene(at: nine, calendar: calendar) == MorningCelestialClock.scene(for: .morning))
        #expect(MorningCelestialClock.scene(atMinute: -60) == MorningCelestialClock.scene(atMinute: 23 * 60))
        #expect(MorningCelestialClock.scene(atMinute: 1440 + 9 * 60) == MorningCelestialClock.scene(for: .morning))
    }

    @Test func solarShiftAndInvalidSourcesCannotBreakTheJourney() {
        let winter = MorningSolarDay(sunriseMinute: 600, sunsetMinute: 840)
        let winterDawn = MorningCelestialClock.scene(atMinute: 600, solar: winter)
        #expect(winterDawn.sun.centerY == 0.94)
        #expect(MorningCelestialClock.scene(atMinute: 720, solar: winter).sun.centerY < 0.21)
        for solar in [MorningSolarDay(sunriseMinute: .nan, sunsetMinute: .infinity),
                      MorningSolarDay(sunriseMinute: 900, sunsetMinute: 300)] {
            #expect(MorningCelestialClock.scene(atMinute: 540, solar: solar) == MorningCelestialClock.scene(atMinute: 540))
        }
        #expect(MorningCelestialClock.scene(atMinute: .nan).sun.centerY.isFinite)
    }
}
