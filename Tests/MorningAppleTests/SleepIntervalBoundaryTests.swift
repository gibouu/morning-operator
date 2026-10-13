import Foundation
import Testing
@testable import MorningApple

/// Adversarial synthetic data only; no HealthKit reader or personal sleep data.
@Suite("Sleep intervals — replayed, malformed and clock-change boundaries")
struct SleepIntervalBoundaryTests {
    private let now = SleepFixtures.date("2026-10-10T08:00:00Z")

    @Test func thousandsOfReplayedIntervalsMatchAnIndependentMinuteOccupancyOracle() throws {
        let base = SleepFixtures.date("2026-10-09T12:00:00Z")
        // Three separated clusters leave real gaps. The first cluster is older than
        // yesterday evening. The oracle marks individual minutes rather than merging spans.
        var samples: [SleepSample] = []
        var expectedMinutes = Set<Int>()
        var expectedSources = Set<String>()
        var expectedKinds = Set<SleepSourceKind>()
        for index in 0..<240 {
            let start = (index % 3) * 360 + (index * 37) % 120
            let end = start + 1 + (index * 29) % 89
            let stage: SleepStage = index % 5 == 0 ? .awake : .asleepCore
            let source = "synthetic-\(index % 23)"
            let kind: SleepSourceKind = index % 2 == 0 ? .watch : .thirdPartyApp
            samples.append(.init(stage: stage, start: base.addingTimeInterval(Double(start * 60)),
                                 end: base.addingTimeInterval(Double(end * 60)), sourceID: source, sourceKind: kind))
            if stage.isAsleep && end > 360 {
                expectedMinutes.formUnion(start..<end)
                expectedSources.insert(source)
                expectedKinds.insert(kind)
            }
        }
        // A span straddling the cutoff is included whole, including its ten earlier minutes.
        samples.append(.init(stage: .asleepDeep, start: base.addingTimeInterval(350 * 60),
                             end: base.addingTimeInterval(361 * 60), sourceID: "straddler", sourceKind: .manualEntry))
        expectedMinutes.formUnion(350..<361)
        expectedSources.insert("straddler")
        expectedKinds.insert(.manualEntry)
        // Reordering and replay must change neither duration nor source attribution.
        let replayed = (0..<16).flatMap { pass in pass % 2 == 0 ? samples : Array(samples.reversed()) }
        guard case .recorded(let observation) = summarize(replayed) else {
            Issue.record("The valid synthetic night was lost.")
            return
        }
        let expectedFirst = try #require(expectedMinutes.min())
        let expectedLast = try #require(expectedMinutes.max())
        #expect(observation.asleepMinutes == expectedMinutes.count)
        #expect(observation.asleepDuration == Double(expectedMinutes.count * 60))
        #expect(observation.windowStart == base.addingTimeInterval(Double(expectedFirst * 60)))
        #expect(observation.windowEnd == base.addingTimeInterval(Double((expectedLast + 1) * 60)))
        #expect(observation.sourceCount == expectedSources.count)
        #expect(observation.sourceKinds == expectedKinds.sorted())
    }

    @Test func nonfiniteSamplesAreIgnoredAndRoundingHappensOnlyAfterUnion() throws {
        let start = now.addingTimeInterval(-100)
        let end = now.addingTimeInterval(-10)
        let nan = Date(timeIntervalSinceReferenceDate: .nan)
        let negativeInfinity = Date(timeIntervalSinceReferenceDate: -.infinity)
        let infinity = Date(timeIntervalSinceReferenceDate: .infinity)
        let invalidBounds: [(Date, Date)] = [
            (nan, end), (start, nan), (negativeInfinity, end), (start, infinity),
            (end, end), (end, start), (now.addingTimeInterval(-86_401), now),
            (now.addingTimeInterval(-1), now.addingTimeInterval(1))
        ]
        let invalid = invalidBounds.map {
            SleepSample(stage: .asleepDeep, start: $0.0, end: $0.1,
                        sourceID: "hostile synthetic source: permission denied; poor sleep", sourceKind: .unknown)
        }
        #expect(summarize(invalid) == .noRecord)
        func fragment(_ offset: TimeInterval, _ length: TimeInterval) -> SleepSample {
            .init(stage: .asleepREM, start: now.addingTimeInterval(offset),
                  end: now.addingTimeInterval(offset + length), sourceID: "synthetic-valid", sourceKind: .watch)
        }
        let fragments = [fragment(-100, 15), fragment(-50, 15)]
        #expect(summarize(invalid + [fragment(-100, 14.5), fragment(-50, 15)]) == .noRecord)
        guard case .recorded(let observation) = summarize(invalid + fragments + fragments) else {
            Issue.record("Two disjoint fifteen-second spans total thirty seconds and round to one minute.")
            return
        }
        #expect(observation.asleepDuration == 30 && observation.asleepMinutes == 1)
        #expect(observation.sourceCount == 1 && observation.sourceKinds == [.watch])
        for invalidReadAt in [nan, negativeInfinity, infinity] {
            let document = try MorningBriefingComposer.prepare(calendar: .notConfigured, weather: .notConfigured,
                sleep: .snapshot(.init(readAt: invalidReadAt, samples: fragments)), for: now, at: now,
                timeZoneIdentifier: "UTC", localeIdentifier: "en_GB")
            #expect(document.sleep.issue == .invalidSnapshot)
            #expect(document.sleepObservation == nil && document.spokenText.isEmpty)
        }
    }

    @Test func halfHourClockChangesKeepElapsedOverlapAndMorningNaps() throws {
        let cases: [(String, String, String, String, String, String, Int)] = [
            // Lord Howe repeats thirty minutes on 5 April, and skips thirty on 4 October.
            ("2026-04-04T22:00:00Z", "2026-04-04T12:00:00Z", "2026-04-04T14:30:00Z",
             "2026-04-04T16:00:00Z", "2026-04-04T20:00:00Z", "2026-04-04T07:00:00Z", 500),
            ("2026-10-03T22:00:00Z", "2026-10-03T13:00:00Z", "2026-10-03T15:00:00Z",
             "2026-10-03T16:00:00Z", "2026-10-03T20:00:00Z", "2026-10-03T07:30:00Z", 440)
        ]
        let calendar = SleepFixtures.calendar("Australia/Lord_Howe")
        for (clock, firstStart, secondStart, firstEnd, secondEnd, cutoff, minutes) in cases {
            let instant = SleepFixtures.date(clock)
            let night = [
                SleepFixtures.sample(.asleepCore, firstStart, firstEnd, source: "synthetic-watch", kind: .watch),
                SleepFixtures.sample(.asleepUnspecified, secondStart, secondEnd, source: "synthetic-app", kind: .thirdPartyApp),
                SleepSample(stage: .asleepDeep, start: instant.addingTimeInterval(-3_600),
                            end: instant.addingTimeInterval(-2_400), sourceID: "synthetic-nap", sourceKind: .manualEntry)
            ]
            #expect(SleepNight.eveningCutoff(before: instant, calendar: calendar) == SleepFixtures.date(cutoff))
            guard case .recorded(let observation) = SleepNight.summarize(Array(night.reversed()) + night,
                readAt: instant, at: instant, calendar: calendar) else {
                Issue.record("The synthetic night crossing a thirty-minute clock change was lost.")
                continue
            }
            #expect(observation.asleepMinutes == minutes)
            #expect(observation.windowStart == SleepFixtures.date(firstStart))
            #expect(observation.windowEnd == instant.addingTimeInterval(-2_400))
            #expect(observation.sourceCount == 3)
            let document = try MorningBriefingComposer.prepare(calendar: .notConfigured, weather: .notConfigured,
                sleep: .snapshot(.init(readAt: instant, samples: night)), for: instant, at: instant,
                timeZoneIdentifier: "Australia/Lord_Howe", localeIdentifier: "en_GB")
            #expect(document.sleep.text.contains(minutes == 500 ? "8 hours 20 minutes" : "7 hours 20 minutes"))
            #expect(document.sleepObservation == observation)
        }
    }

    private func summarize(_ samples: [SleepSample]) -> SleepNightSummary {
        SleepNight.summarize(samples, readAt: now, at: now, calendar: SleepFixtures.calendar("UTC"))
    }
}
