import Foundation
import Testing
@testable import MorningCore

@Suite("Measured morning history")
struct MorningHistoryTests {
    private func date(_ string: String) throws -> Date {
        let value = ISO8601DateFormatter().date(from: string)
        return try #require(value)
    }
    private func routine() -> RoutineVersion {
        RoutineVersion(sourceLabel: "Test fixture", steps: [
            RoutineStep(title: "Keep an enjoyable moment", kind: .entertainment, durationMinutes: 45, isRequired: true)
        ], isApproved: true)
    }
    private func finished(at start: Date, seconds: Double = 30) throws -> RoutineSession {
        var session = RoutineSession(routine: routine())
        try session.start(at: start)
        try session.advance(at: start.addingTimeInterval(seconds))
        return session
    }
    private func observation(on day: String, counts: ObservedAppCounts,
                             coverage: ObservationCoverage = .partialWindow,
                             provenance: AppObservationProvenance = .deviceCapture,
                             updatedAt: Date? = nil) throws -> DailyAppObservation {
        let observedAt = try date(day + "T08:00:00Z")
        return try DailyAppObservation(date: observedAt, timeZoneIdentifier: "Europe/Paris", appName: "Example social app",
                                       bundleIdentifier: "example.social", counts: counts, coverage: coverage,
                                       provenance: provenance, evidenceReferences: ["test-observation"], updatedAt: updatedAt ?? observedAt)
    }

    @Test func pausesAreExcludedAndPlannedTimeIsNeverReportedAsMeasured() throws {
        let start = try date("2026-10-09T06:00:00Z")
        var session = RoutineSession(routine: routine())
        try session.start(at: start)
        try session.pause(at: start.addingTimeInterval(60))
        try session.resume(at: start.addingTimeInterval(180))
        try session.advance(at: start.addingTimeInterval(300))
        let record = try MorningRunRecord(session: session, timeZoneIdentifier: "Europe/Paris", recordedAt: start.addingTimeInterval(301))
        #expect(record.id == session.id)
        #expect(record.plannedDurationMinutes == 45)
        #expect(record.elapsedDurationSeconds == 300)
        #expect(record.activeDurationSeconds == 180)
        #expect(record.pausedDurationSeconds == 120)
        #expect(record.timingStatus == .complete)
        #expect(record.completedStepCount == 1)
        let restored = try JSONDecoder().decode(MorningRunRecord.self, from: JSONEncoder().encode(record))
        #expect(restored == record)
        #expect(restored.activeDurationSeconds == 180)
    }

    @Test func stoppingWhilePausedIncludesTheFinalPauseAndNeverStartedIsUnknown() throws {
        let start = try date("2026-10-09T06:00:00Z")
        var paused = RoutineSession(routine: routine())
        try paused.start(at: start)
        try paused.pause(at: start.addingTimeInterval(15))
        try paused.stop(at: start.addingTimeInterval(115))
        let pausedRecord = try MorningRunRecord(session: paused, timeZoneIdentifier: "UTC")
        #expect(pausedRecord.activeDurationSeconds == 15)
        #expect(pausedRecord.pausedDurationSeconds == 100)
        #expect(pausedRecord.elapsedDurationSeconds == 115)
        #expect(pausedRecord.completedStepCount == 0)
        var unopened = RoutineSession(routine: routine())
        try unopened.stop(at: start)
        let unopenedRecord = try MorningRunRecord(session: unopened, timeZoneIdentifier: "UTC")
        #expect(unopenedRecord.timingStatus == .notStarted)
        #expect(unopenedRecord.activeDurationSeconds == nil)
        #expect(unopenedRecord.elapsedDurationSeconds == nil)
        var history = MorningHistory(runs: [unopenedRecord])
        history.upsert(unopenedRecord)
        #expect(history.runs.count == 1)
    }

    @Test func invalidClocksAndIncompleteRunsCannotInventDurations() throws {
        let start = try date("2026-10-09T06:00:00Z")
        var session = RoutineSession(routine: routine())
        try session.start(at: start)
        #expect(throws: MorningHistoryError.unfinishedSession) {
            _ = try MorningRunRecord(session: session, timeZoneIdentifier: "UTC")
        }
        try session.pause(at: start.addingTimeInterval(-5))
        try session.stop(at: start.addingTimeInterval(10))
        let record = try MorningRunRecord(session: session, timeZoneIdentifier: "UTC")
        #expect(record.timingStatus == .invalid)
        #expect(record.activeDurationSeconds == nil)
        #expect(record.pausedDurationSeconds == nil)
        #expect(record.elapsedDurationSeconds == nil)
    }

    @Test func sevenDaysUseCalendarArithmeticAcrossDaylightSaving() throws {
        let end = try date("2026-03-30T12:00:00Z")
        let summary = try MorningHistory().sevenDaySummary(endingOn: end, timeZoneIdentifier: "Europe/Paris")
        #expect(summary.days.count == 7)
        #expect(summary.days.first?.dayKey == "2026-03-24")
        #expect(summary.days.last?.dayKey == "2026-03-30")
        #expect(summary.days[6].date.timeIntervalSince(summary.days[5].date) == 23 * 60 * 60)
        #expect(summary.missingDayCount == 7)
        #expect(summary.averageActiveDurationSeconds == nil)
        #expect(summary.totalActiveDurationSeconds == nil)
    }

    @Test func capturedLocalDatesSurviveTravelAndMidnightBoundaries() throws {
        let instant = try date("2026-10-09T00:30:00Z")
        let record = try MorningRunRecord(session: finished(at: instant), timeZoneIdentifier: "America/Los_Angeles")
        #expect(record.dayKey == "2026-10-08")
        let history = MorningHistory(runs: [record, record])
        let summary = try history.sevenDaySummary(endingOn: instant, timeZoneIdentifier: "Europe/Paris")
        #expect(summary.runCount == 1)
        #expect(summary.days.last?.dayKey == "2026-10-09")
        #expect(summary.days.first(where: { $0.dayKey == "2026-10-08" })?.runCount == 1)
        #expect(summary.sourceTimeZoneIdentifiers == ["America/Los_Angeles"])
    }

    @Test func explicitZeroHasEvidenceButMissingMetricsDoNotEnterTheDenominator() throws {
        let a = try observation(on: "2026-10-07", counts: .init(reelsViewed: 10), coverage: .completeWindow)
        let b = try observation(on: "2026-10-08", counts: .init(reelsViewed: 0, likes: 2))
        let c = try observation(on: "2026-10-09", counts: .init(), coverage: .unknown)
        let summary = try MorningHistory(appObservations: [a, b, c])
            .sevenDaySummary(endingOn: date("2026-10-09T12:00:00Z"), timeZoneIdentifier: "Europe/Paris")
        let app = try #require(summary.apps.first)
        #expect(app.observedDayCount == 3)
        #expect(app.reelsViewed.total == 10)
        #expect(app.reelsViewed.daysWithEvidence == 2)
        #expect(app.reelsViewed.averagePerEvidenceDay == 5)
        #expect(app.reelsViewed.daysMissingEvidence == 5)
        #expect(app.likes.total == 2)
        #expect(app.likes.daysWithEvidence == 1)
        #expect(app.emailsRead.total == nil)
        #expect(app.emailsRead.daysWithEvidence == 0)
        #expect(app.emailsRead.averagePerEvidenceDay == nil)
        #expect(app.totalObservedDurationSeconds == nil)
        #expect(app.completeWindowDayCount == 1)
        #expect(app.partialWindowDayCount == 1)
        #expect(summary.recordedDayCount == 3)
        #expect(summary.missingDayCount == 4)
    }

    @Test func snapshotsReplaceInsteadOfDoubleCountingAndOlderImportsDoNotWin() throws {
        let first = try observation(on: "2026-10-09", counts: .init(reelsViewed: 10))
        let updated = try observation(on: "2026-10-09", counts: .init(reelsViewed: 12),
                                      updatedAt: first.updatedAt.addingTimeInterval(30))
        var history = MorningHistory(appObservations: [first, updated])
        history.upsert(first)
        #expect(history.appObservations.count == 1)
        let restored = try JSONDecoder().decode(MorningHistory.self, from: JSONEncoder().encode(history))
        let summary = try restored.sevenDaySummary(endingOn: first.date, timeZoneIdentifier: "Europe/Paris")
        #expect(summary.apps.first?.reelsViewed.total == 12)
        #expect(summary.apps.first?.reelsViewed.daysWithEvidence == 1)
    }

    @Test func averagesUseTimedRunCountAndSyntheticDataIsExcludedByDefault() throws {
        let start = try date("2026-10-09T06:00:00Z")
        let realA = try MorningRunRecord(session: finished(at: start, seconds: 20), timeZoneIdentifier: "UTC")
        let realB = try MorningRunRecord(session: finished(at: start.addingTimeInterval(60), seconds: 40), timeZoneIdentifier: "UTC")
        let fixture = try MorningRunRecord(session: finished(at: start.addingTimeInterval(120), seconds: 999), timeZoneIdentifier: "UTC", isSynthetic: true)
        let fixtureObservation = try observation(on: "2026-10-09", counts: .init(reelsViewed: 999), provenance: .syntheticDemo)
        let history = MorningHistory(runs: [realA, realB, fixture], appObservations: [fixtureObservation])
        let summary = try history.sevenDaySummary(endingOn: start, timeZoneIdentifier: "UTC")
        #expect(summary.runCount == 2)
        #expect(summary.timedRunCount == 2)
        #expect(summary.averageActiveDurationSeconds == 30)
        #expect(summary.totalActiveDurationSeconds == 60)
        #expect(summary.averagePlannedDurationMinutes == 45)
        #expect(summary.apps.isEmpty)
        #expect(!summary.includesSyntheticData)
        let demo = try history.sevenDaySummary(endingOn: start, timeZoneIdentifier: "UTC", includingSynthetic: true)
        #expect(demo.runCount == 3)
        #expect(demo.includesSyntheticData)
        #expect(demo.apps.first?.reelsViewed.total == 999)
    }

    @Test func interruptedRecoveryRetainsTheRunButNeverCountsUnobservedTime() throws {
        let start = try date("2026-10-08T06:00:00Z")
        var recovered = RoutineSession(routine: routine())
        try recovered.start(at: start)
        // Recovery can only pause at relaunch; the intervening day was not observed.
        try recovered.pause(at: start.addingTimeInterval(86_400))
        try recovered.resume(at: start.addingTimeInterval(86_420))
        try recovered.advance(at: start.addingTimeInterval(86_440))
        let interrupted = try MorningRunRecord(session: recovered, timeZoneIdentifier: "UTC", timingInterrupted: true)
        #expect(interrupted.timingInterrupted)
        #expect(interrupted.timingStatus == .incomplete)
        #expect(interrupted.activeDurationSeconds == nil)
        #expect(interrupted.pausedDurationSeconds == nil)
        #expect(interrupted.elapsedDurationSeconds == nil)
        #expect(interrupted.startedAt == start)
        #expect(interrupted.endedAt == start.addingTimeInterval(86_440))
        #expect(interrupted.dayKey == "2026-10-08")
        #expect(interrupted.completedStepCount == 1)
        #expect(interrupted.plannedDurationMinutes == 45)

        let restored = try JSONDecoder().decode(MorningRunRecord.self, from: JSONEncoder().encode(interrupted))
        #expect(restored == interrupted)
        #expect(restored.timingStatus == .incomplete)
        #expect(restored.elapsedDurationSeconds == nil)
        let measured = try MorningRunRecord(session: finished(at: start.addingTimeInterval(86_500), seconds: 60), timeZoneIdentifier: "UTC")
        let summary = try MorningHistory(runs: [restored, measured])
            .sevenDaySummary(endingOn: start.addingTimeInterval(86_500), timeZoneIdentifier: "UTC")
        #expect(summary.runCount == 2)
        #expect(summary.completedRunCount == 2)
        #expect(summary.timedRunCount == 1)
        #expect(summary.totalActiveDurationSeconds == 60)
        #expect(summary.averageActiveDurationSeconds == 60)
    }

    @Test func legacyRunWithoutInterruptionFlagKeepsItsMeasuredTiming() throws {
        let start = try date("2026-10-09T06:00:00Z")
        let record = try MorningRunRecord(session: finished(at: start), timeZoneIdentifier: "UTC")
        let data = try JSONEncoder().encode(record)
        var legacy = try #require(JSONSerialization.jsonObject(with: data) as? [String: Any])
        legacy.removeValue(forKey: "timingInterrupted")
        let restored = try JSONDecoder().decode(MorningRunRecord.self, from: JSONSerialization.data(withJSONObject: legacy))
        #expect(!restored.timingInterrupted)
        #expect(restored.timingStatus == .complete)
        #expect(restored.activeDurationSeconds == 30)
        #expect(restored == record)
    }

    @Test func measurementsRequireEvidenceAndCannotBeNegativeOrExceedCoverage() throws {
        let observedAt = try date("2026-10-09T06:00:00Z")
        #expect(throws: MorningHistoryError.invalidObservation) {
            _ = try DailyAppObservation(date: observedAt, appName: "App", counts: .init(likes: -1),
                                        provenance: .deviceCapture, evidenceReferences: ["frame-1"])
        }
        #expect(throws: MorningHistoryError.invalidObservation) {
            _ = try DailyAppObservation(date: observedAt, appName: "App", counts: .init(likes: 0),
                                        provenance: .deviceCapture, evidenceReferences: [])
        }
        #expect(throws: MorningHistoryError.invalidObservation) {
            _ = try DailyAppObservation(date: observedAt, appName: "App", observedDurationSeconds: 20, coveredSeconds: 10,
                                        provenance: .deviceCapture, evidenceReferences: ["frame-1"])
        }
        #expect(throws: MorningHistoryError.invalidTimeZone) {
            _ = try DailyAppObservation(date: observedAt, timeZoneIdentifier: "invalid/time-zone", appName: "App",
                                        provenance: .deviceCapture, evidenceReferences: ["frame-1"])
        }
    }

    /// Reading the missing days of such a saved summary used to overflow and end the process.
    @Test("A saved count of days below zero is refused, and the largest counts are read safely")
    func decodedCountSummaryCannotOverflow() throws {
        func decode(evidence: Int, window: Int) throws -> CountSummary {
            try JSONDecoder().decode(CountSummary.self,
                from: Data(#"{"total":0,"daysWithEvidence":\#(evidence),"windowDayCount":\#(window)}"#.utf8))
        }
        for (evidence, window) in [(Int.min, 0), (-1, 7), (0, Int.min), (0, -1)] {
            #expect(throws: DecodingError.self) { _ = try decode(evidence: evidence, window: window) }
        }
        #expect(try decode(evidence: 0, window: .max).daysMissingEvidence == .max)
        #expect(try decode(evidence: .max, window: 0).daysMissingEvidence == 0)
        let ordinary = try decode(evidence: 3, window: 7)
        #expect(ordinary.daysMissingEvidence == 4)
        #expect(try JSONDecoder().decode(CountSummary.self, from: JSONEncoder().encode(ordinary)) == ordinary)
    }
}
