import Foundation
import Testing
@testable import MorningCore

@Suite("Comparable-window sequence and known exclusions")
struct ObservationTraceWindowSequenceTests {
    private let inbox = ObservationAppIdentity(key: "fixture.inbox", displayName: "Synthetic inbox")
    private let calendar = ObservationAppIdentity(key: "fixture.calendar", displayName: "Synthetic calendar")
    private let scope = "synthetic-seven-second-v1"

    private func date(_ day: Int) -> Date {
        // Synthetic consecutive UTC dates, intentionally unrelated to an actual capture date.
        Date(timeIntervalSince1970: 1_760_000_000 + Double(day) * 86_400)
    }
    private func dayKey(_ day: Int) -> String {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "UTC")!
        let parts = calendar.dateComponents([.year, .month, .day], from: date(day))
        return String(format: "%04d-%02d-%02d", parts.year!, parts.month!, parts.day!)
    }

    private func day(_ number: Int, _ sequence: [ObservationAppIdentity]) throws -> ObservationTraceDay {
        let samples = sequence.enumerated().map {
            ObservationTraceSample(timeSeconds: Double($0.offset),
                                   appEvidence: .identified(app: $0.element, reference: "synthetic-frame-\($0.offset)"))
        }
        let trace = try ObservationTrace(durationSeconds: 7, capturedIntervals: [.init(startSeconds: 0, endSeconds: 7)],
                                         origin: .synthetic, samples: samples)
        return try ObservationTraceDay(date: date(number), timeZoneIdentifier: "UTC", comparisonKey: scope, trace: trace)
    }

    private func window(_ days: [ObservationTraceDay], count: Int,
                        excluding: [ObservationExcludedDay] = []) throws -> ObservationTraceWindowReport {
        try ObservationTraceWindowReport(days: days, scheduledDays: (0..<count).map(date), timeZoneIdentifier: "UTC",
            comparisonKey: scope, policy: .init(expectedWindowSeconds: 7, maximumSampleGapSeconds: 1),
            origin: .synthetic, excluding: excluding)
    }

    @Test func firstContextAndTransitionsCountDaysOnceOverComparableDaysOnly() throws {
        let back = [inbox, inbox, calendar, calendar, inbox, inbox, inbox, inbox]
        let twice = [inbox, calendar, inbox, calendar, inbox, inbox, inbox, inbox]
        let other = [calendar, calendar, calendar, calendar, inbox, inbox, inbox, inbox]
        let still = Array(repeating: inbox, count: 8)
        let result = try window([day(0, back), day(1, twice), day(2, other), day(3, still)], count: 5)

        #expect(result.firstContexts.map(\.app) == [inbox, calendar])
        #expect(result.firstContexts[0].frequency.seenDayKeys == [dayKey(0), dayKey(1), dayKey(3)])
        #expect(result.firstContexts[1].frequency.seenDayKeys == [dayKey(2)])
        #expect(result.firstContexts.allSatisfy {
            $0.frequency.daysWithEvidence == 4 && $0.frequency.scheduledDayCount == 5 && $0.frequency.daysWithoutEvidence == 1
        })
        // Day 1 shows inbox→calendar twice and still counts as one day.
        #expect(result.transitions.map { [$0.from.key, $0.to.key] } == [
            [calendar.key, inbox.key], [inbox.key, calendar.key]
        ])
        #expect(result.transitions[0].frequency.seenDayKeys == [dayKey(0), dayKey(1), dayKey(2)])
        #expect(result.transitions[1].frequency.seenDayKeys == [dayKey(0), dayKey(1)])
        #expect(result.transitions[1].frequency.seenDayCount == 2)
        #expect(result.transitions[1].frequency.daysWithEvidence == 4)
    }

    @Test func noComparableDayMeansNoSequenceRatherThanAnEmptyMorning() throws {
        let result = try window([], count: 3)
        #expect(result.firstContexts.isEmpty)
        #expect(result.transitions.isEmpty)
    }

    @Test func oneContextKeyUnderTwoNamesExcludesThoseDaysInsteadOfFailingTheWindow() throws {
        let renamed = ObservationAppIdentity(key: inbox.key, displayName: "Another inbox")
        let result = try window([day(0, Array(repeating: inbox, count: 8)),
                                 day(1, [renamed, renamed, calendar, calendar, calendar, calendar, calendar, calendar]),
                                 day(2, Array(repeating: calendar, count: 8))], count: 4)
        #expect(result.excludedDays == [.init(dayKey: dayKey(0), reason: .conflictingContext),
                                        .init(dayKey: dayKey(1), reason: .conflictingContext)])
        #expect(result.includedDayKeys == [dayKey(2)])
        #expect(result.missingDayKeys == [dayKey(3)])
        #expect(result.apps.map(\.app) == [calendar])
        #expect(result.apps[0].minimumVisibleVisits.daysWithEvidence == 1)
        #expect(result.observationDurationSeconds.daysWithEvidence == 1)
        #expect(result.transitions.isEmpty)
    }

    @Test func knownExclusionsAreReportedAsExcludedNeverAsMissingOrAsAMorning() throws {
        let sequence = Array(repeating: inbox, count: 8)
        let result = try window([day(0, sequence)], count: 3, excluding: [
            .init(dayKey: dayKey(1), reason: .duplicateDay),
            .init(dayKey: "1999-01-01", reason: .automatedOrigin)
        ])
        #expect(result.includedDayKeys == [dayKey(0)])
        #expect(result.excludedDays == [.init(dayKey: dayKey(1), reason: .duplicateDay)])
        #expect(result.missingDayKeys == [dayKey(2)])
        #expect(result.observationDurationSeconds.daysWithEvidence == 1)
        #expect(result.includedDayKeys.count + result.excludedDays.count + result.missingDayKeys.count == result.scheduledDayCount)

        #expect(throws: ObservationTraceError.duplicateDay) {
            try window([day(0, sequence)], count: 3, excluding: [.init(dayKey: dayKey(0), reason: .duplicateDay)])
        }
        #expect(throws: ObservationTraceError.duplicateDay) {
            try window([], count: 3, excluding: [.init(dayKey: dayKey(1), reason: .duplicateDay),
                                                 .init(dayKey: dayKey(1), reason: .noSampledEvidence)])
        }
    }
}
