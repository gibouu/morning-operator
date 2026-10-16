import Testing
@testable import MorningCore

@Suite("Approved MORE day and night branding")
struct MorningBrandTests {
    @Test func appearanceUsesTheSceneThresholdAtTwilight() {
        #expect(MorningBrandAppearance.resolve(moonOpacity: 0) == .day)
        #expect(MorningBrandAppearance.resolve(moonOpacity: 0.57) == .day)
        #expect(MorningBrandAppearance.resolve(moonOpacity: 0.570_001) == .night)
        #expect(MorningBrandAppearance.resolve(moonOpacity: 1) == .night)
    }

    @Test func approvedLettersStayIdenticalAcrossBothAppearances() {
        let day = MorningBrandArtwork.wordmark(appearance: .day)
        let night = MorningBrandArtwork.wordmark(appearance: .night)
        let letters = day.filter { $0.color == MorningBrandPalette.ink }
        let nightLetters = night.filter { $0.color == MorningBrandPalette.paper }
        #expect(letters.count == 366)
        #expect(letters.map { [$0.x, $0.y, $0.radius] } == nightLetters.map { [$0.x, $0.y, $0.radius] })
        #expect(letters.contains { $0.x == 0 && $0.y == 14 })
        #expect(letters.contains { $0.x == 71 && $0.y == 6 })
    }

    @Test func fullSunAndMoonReplaceTheOWithNoHorizonInTheWordmark() {
        let day = MorningBrandArtwork.wordmark(appearance: .day).filter { $0.x > 21 && $0.x < 43 }
        let night = MorningBrandArtwork.wordmark(appearance: .night).filter { $0.x > 21 && $0.x < 43 }
        #expect(day.count == 117)
        #expect(night.count == 169)
        // All eight rays, including the one below the complete solar disc.
        for (x, y) in [(31.5, -2.0), (40.5, 7.0), (31.5, 16.0), (22.5, 7.0)] {
            #expect(day.contains { $0.x == x && $0.y == y && $0.radius == 0.4 })
        }
        #expect(night.contains { $0.x == 31.5 && $0.y == 0 })
        #expect(night.contains { $0.x == 31.5 && $0.y == 14 })
        #expect(night.contains { $0.color == MorningBrandPalette.crater })
    }

    @Test func sharedBoundsNeverClipAnyApprovedDotOrRay() {
        for appearance in MorningBrandAppearance.allCases {
            for (dots, bounds) in [
                (MorningBrandArtwork.wordmark(appearance: appearance), MorningBrandArtwork.wordmarkBounds),
                (MorningBrandArtwork.symbol(appearance: appearance), MorningBrandArtwork.symbolBounds)
            ] {
                for dot in dots {
                    #expect(dot.x - dot.radius >= bounds.x - 0.000_001)
                    #expect(dot.y - dot.radius >= bounds.y - 0.000_001)
                    #expect(dot.x + dot.radius <= bounds.x + bounds.width + 0.000_001)
                    #expect(dot.y + dot.radius <= bounds.y + bounds.height + 0.000_001)
                }
            }
        }
    }

    @Test func contrastingArtworkOnlyChangesDaytimeInk() {
        for appearance in MorningBrandAppearance.allCases {
            for (regular, contrasting) in [
                (MorningBrandArtwork.wordmark(appearance: appearance), MorningBrandArtwork.wordmark(appearance: appearance, contrasting: true)),
                (MorningBrandArtwork.symbol(appearance: appearance), MorningBrandArtwork.symbol(appearance: appearance, contrasting: true))
            ] {
                #expect(regular.count == contrasting.count)
                for (before, after) in zip(regular, contrasting) {
                    #expect(before.x == after.x && before.y == after.y && before.radius == after.radius)
                    #expect(after.color == (before.color == MorningBrandPalette.ink ? MorningBrandPalette.paper : before.color))
                }
            }
        }
    }

    @Test func standaloneDayIconKeepsItsSunriseAndNightIconHasAFullMoon() {
        let day = MorningBrandArtwork.symbol(appearance: .day)
        let night = MorningBrandArtwork.symbol(appearance: .night)
        #expect(day.filter { $0.y == 49 && $0.color == MorningBrandPalette.ink }.count == 15)
        #expect(day.filter { $0.y == 56 && $0.color == MorningBrandPalette.ink }.count == 8)
        #expect(night.filter { $0.y < 32 }.count == night.filter { $0.y > 32 }.count)
        #expect(night.allSatisfy { $0.color == MorningBrandPalette.moon || $0.color == MorningBrandPalette.crater })
    }
}
