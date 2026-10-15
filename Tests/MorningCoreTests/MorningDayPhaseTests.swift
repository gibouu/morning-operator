import Foundation
import Testing
@testable import MorningCore

/// The clock decides the light; every phase must still read. No display, no SwiftUI.
@Suite("Day phases: the light follows the clock and every phase reads")
struct MorningDayPhaseTests {
    private let solar = MorningSolarDay.fixed   // 07:00 / 19:00

    private func blend(_ hour: Double, _ minute: Double = 0) -> MorningPhaseBlend {
        MorningDayClock.blend(atMinute: hour * 60 + minute, solar: solar)
    }

    @Test func eachHourFallsInTheExpectedPhase() {
        #expect(blend(3).dominant == .night)
        #expect(blend(5, 45).dominant == .night)
        #expect(blend(6, 50).dominant == .dawn)
        #expect(blend(7, 20).dominant == .dawn)
        #expect(blend(9).dominant == .morning)
        #expect(blend(13).dominant == .day)
        #expect(blend(16).dominant == .day)
        #expect(blend(18, 30).dominant == .evening)
        #expect(blend(19, 15).dominant == .evening)
        #expect(blend(22).dominant == .night)
        #expect(blend(0).dominant == .night)
    }

    @Test func steadyPhasesHoldAndCrossoversEase() {
        #expect(blend(13) == .steady(.day))
        let crossing = blend(7, 52.5)   // halfway between dawn (07:30) and morning (08:15)
        #expect(crossing.from == .dawn && crossing.to == .morning)
        #expect(abs(crossing.progress - 0.5) < 0.05)
        #expect(blend(7, 45).progress < blend(7, 55).progress)
        #expect(blend(7, 55).progress < blend(8, 05).progress)
    }

    @Test func noMinuteJumps() {
        // One minute never moves the paper by more than a sliver: no jarring change.
        var previous = MorningPaletteValues.resolve(blend(0), dark: false)
        for minute in stride(from: 1.0, through: 24 * 60, by: 1) {
            let palette = MorningPaletteValues.resolve(MorningDayClock.blend(atMinute: minute, solar: solar), dark: false)
            let step = abs(palette.paper.luminance - previous.paper.luminance)
            #expect(step < 0.01, "Minute \(Int(minute)) moved the paper by \(step)")
            previous = palette
        }
    }

    @Test func wrapsAroundMidnightAndOddInputs() {
        #expect(MorningDayClock.blend(atMinute: -60, solar: solar).dominant == .night)
        #expect(MorningDayClock.blend(atMinute: 25 * 60, solar: solar).dominant == .night)
        #expect(MorningDayClock.blend(atMinute: 1440 + 9 * 60, solar: solar).dominant == .morning)
        #expect(MorningPhaseBlend(from: .day, to: .night, progress: 4).progress == 1)
        #expect(MorningPhaseBlend(from: .day, to: .night, progress: -1).progress == 0)
    }

    @Test func aDateIsReadInItsCalendar() throws {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = try #require(TimeZone(identifier: "Europe/Paris"))
        let nine = try #require(calendar.date(from: DateComponents(year: 2026, month: 10, day: 15, hour: 9)))
        #expect(MorningDayClock.blend(at: nine, calendar: calendar, solar: solar).dominant == .morning)
        var tokyo = Calendar(identifier: .gregorian)
        tokyo.timeZone = try #require(TimeZone(identifier: "Asia/Tokyo"))
        #expect(MorningDayClock.blend(at: nine, calendar: tokyo, solar: solar).dominant == .day)
    }

    @Test func aLaterSunriseMovesTheDawn() {
        let winter = MorningSolarDay(sunriseMinute: 8 * 60 + 30, sunsetMinute: 17 * 60)
        #expect(MorningDayClock.blend(atMinute: 7 * 60, solar: winter).dominant == .night)
        #expect(MorningDayClock.blend(atMinute: 8 * 60 + 30, solar: winter).dominant == .dawn)
        #expect(MorningDayClock.blend(atMinute: 17 * 60, solar: winter).dominant == .evening)
    }

    // MARK: Reading

    @Test func textReadsAtEveryPhaseInBothAppearances() {
        for phase in MorningDayPhase.allCases {
            for dark in [false, true] {
                let p = MorningPaletteValues.phase(phase, dark: dark)
                let name = "\(phase) \(dark ? "dark" : "light")"
                for ground in [p.paper, p.surface] {
                    #expect(MorningRGB.contrast(p.ink, ground) >= 7, "\(name): ink")
                    #expect(MorningRGB.contrast(p.inkSoft, ground) >= 4.5, "\(name): soft ink")
                    #expect(MorningRGB.contrast(p.accentText, ground) >= 4.5, "\(name): accent text")
                    #expect(MorningRGB.contrast(p.positive, ground) >= 4.5, "\(name): positive")
                    // A filled control must stand out from the page (non-text 3:1).
                    #expect(MorningRGB.contrast(p.accent, ground) >= 3, "\(name): accent fill on \(ground)")
                }
                #expect(MorningRGB.contrast(p.onInk, p.ink) >= 4.5, "\(name): text on ink")
            }
        }
    }

    @Test func crossoverPalettesStayReadable() {
        // Mixing two readable palettes must not pass through an unreadable one.
        for minute in stride(from: 0.0, to: 24 * 60, by: 5) {
            let blend = MorningDayClock.blend(atMinute: minute, solar: solar)
            for dark in [false, true] {
                let p = MorningPaletteValues.resolve(blend, dark: dark)
                #expect(MorningRGB.contrast(p.ink, p.paper) >= 7, "minute \(Int(minute))")
                #expect(MorningRGB.contrast(p.inkSoft, p.surface) >= 4.5, "minute \(Int(minute))")
            }
        }
    }

    @Test func morningPaperIsTheBrightestAndCoolestAndNightTheDimmest() {
        let light = MorningDayPhase.allCases.map { MorningPaletteValues.phase($0, dark: false) }
        let luminance = light.map(\.paper.luminance)
        #expect(luminance.max() == MorningPaletteValues.phase(.morning, dark: false).paper.luminance)
        #expect(luminance.min() == MorningPaletteValues.phase(.night, dark: false).paper.luminance)
        // Blue share of the paper: highest in the morning, lowest at night.
        func blueShare(_ c: MorningRGB) -> Double { c.blue / (c.red + c.green + c.blue) }
        #expect(blueShare(MorningPaletteValues.phase(.morning, dark: false).paper)
                > blueShare(MorningPaletteValues.phase(.night, dark: false).paper))
        // Dark appearance: the night is darker than the day.
        #expect(MorningPaletteValues.phase(.night, dark: true).paper.luminance
                < MorningPaletteValues.phase(.day, dark: true).paper.luminance)
    }

    @Test func rgbHelpers() {
        let white = MorningRGB(hex: 0xFFFFFF), black = MorningRGB(hex: 0x000000)
        #expect(abs(MorningRGB.contrast(white, black) - 21) < 0.01)
        #expect(MorningRGB.mix(white, black, 0.5) == MorningRGB(0.5, 0.5, 0.5))
        #expect(MorningRGB.mix(white, black, 2) == black)
        #expect(MorningRGB(hex: 0x1D3A8A) == MorningRGB(29.0 / 255, 58.0 / 255, 138.0 / 255))
    }
}
