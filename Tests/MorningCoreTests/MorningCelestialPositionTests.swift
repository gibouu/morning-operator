import Foundation
import Testing
@testable import MorningCore

@Suite("Celestial artwork follows local time")
struct MorningCelestialPositionTests {
    private func near(_ a: Double, _ b: Double) -> Bool { abs(a - b) < 0.001 }

    @Test func theSunRisesOnTheLeftArcsOverAndSetsOnTheRight() {
        let sunrise = MorningCelestialClock.scene(atMinute: 7 * 60)
        let morning = MorningCelestialClock.scene(atMinute: 9 * 60)
        let midday = MorningCelestialClock.scene(atMinute: 13 * 60)
        let sunset = MorningCelestialClock.scene(atMinute: 19 * 60)
        #expect(near(sunrise.sun.centerX, 0) && near(sunrise.sun.centerY, 0.84))
        #expect(morning.sun.centerX > sunrise.sun.centerX && morning.sun.centerY < sunrise.sun.centerY)
        #expect(near(midday.sun.centerX, 0.5) && near(midday.sun.centerY, 0.61))
        #expect(near(sunset.sun.centerX, 1) && near(sunset.sun.centerY, 0.84))
        #expect(midday.sun.opacity == 1 && midday.moon.opacity == 0)
        // Left to right all day, on one circle: the same distance from the arc's centre
        // once the height is scaled back to the phone's proportions.
        var priorX = -1.0
        for minute in stride(from: 7 * 60, through: 19 * 60, by: 10) {
            let sun = MorningCelestialClock.scene(atMinute: Double(minute)).sun
            #expect(sun.centerX > priorX)
            priorX = sun.centerX
            let dx = sun.centerX - 0.5, dy = (sun.centerY - 0.84) / 0.46
            #expect(abs((dx * dx + dy * dy).squareRoot() - 0.5) < 0.001)
        }
    }

    @Test func atNightTheMoonTakesTheSameArc() {
        let moonrise = MorningCelestialClock.scene(atMinute: 19 * 60)
        let lateEvening = MorningCelestialClock.scene(atMinute: 22 * 60)
        let middleNight = MorningCelestialClock.scene(atMinute: 60)
        let beforeDawn = MorningCelestialClock.scene(atMinute: 5 * 60)
        let dawn = MorningCelestialClock.scene(atMinute: 7 * 60)
        #expect(near(moonrise.moon.centerX, 0) && near(moonrise.moon.centerY, 0.84))
        #expect(lateEvening.moon.centerX > moonrise.moon.centerX && lateEvening.moon.centerY < moonrise.moon.centerY)
        #expect(near(middleNight.moon.centerX, 0.5) && near(middleNight.moon.centerY, 0.61))
        #expect(beforeDawn.moon.centerX > middleNight.moon.centerX && beforeDawn.moon.centerY > middleNight.moon.centerY)
        #expect(near(dawn.moon.centerX, 1) && near(dawn.moon.centerY, 0.84))
        let night = MorningCelestialClock.scene(for: .night)
        #expect(night.sun.opacity == 0 && night.moon.opacity == 1)
    }

    @Test func everyMinuteIsFiniteBoundedAndContinuousIncludingMidnight() {
        var prior = MorningCelestialClock.scene(atMinute: 0)
        for minute in 1...1440 {
            let next = MorningCelestialClock.scene(atMinute: Double(minute))
            for (body, before) in [(next.sun, prior.sun), (next.moon, prior.moon)] {
                #expect(body.centerX.isFinite && body.centerY.isFinite && body.opacity.isFinite)
                #expect((0...1).contains(body.opacity))
                #expect((-0.01...1.01).contains(body.centerX))
                #expect((0.6...1.0).contains(body.centerY))
                #expect(abs(body.centerY - before.centerY) < 0.01)
                // A hidden body changes sides once a day, at the same height; a visible one never jumps.
                if body.opacity > 0 || before.opacity > 0 { #expect(abs(body.centerX - before.centerX) < 0.01) }
                #expect(abs(body.opacity - before.opacity) < 0.026)
            }
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
        #expect(near(winterDawn.sun.centerX, 0) && near(winterDawn.sun.centerY, 0.84))
        let winterNoon = MorningCelestialClock.scene(atMinute: 720, solar: winter).sun
        #expect(near(winterNoon.centerX, 0.5) && near(winterNoon.centerY, 0.61))
        for solar in [MorningSolarDay(sunriseMinute: .nan, sunsetMinute: .infinity),
                      MorningSolarDay(sunriseMinute: 900, sunsetMinute: 300)] {
            #expect(MorningCelestialClock.scene(atMinute: 540, solar: solar) == MorningCelestialClock.scene(atMinute: 540))
        }
        #expect(MorningCelestialClock.scene(atMinute: .nan).sun.centerY.isFinite)
    }
}
