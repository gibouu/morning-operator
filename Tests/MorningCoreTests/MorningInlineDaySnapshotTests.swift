import Foundation
import Testing
@testable import MorningCore

@Suite("Inline day evidence and calendar navigation")
struct MorningInlineDaySnapshotTests {
    private func date(_ string: String) throws -> Date {
        try #require(ISO8601DateFormatter().date(from: string))
    }

    private func calendar(_ zone: String, identifier: Calendar.Identifier = .gregorian) throws -> Calendar {
        var calendar = Calendar(identifier: identifier)
        calendar.timeZone = try #require(TimeZone(identifier: zone))
        return calendar
    }

    private func run(at start: Date, zone: String = "UTC", completed: Bool = true,
                     started: Bool = true, synthetic: Bool = false, sourceLabel: String = "Unit test") throws -> MorningRunRecord {
        let routine = RoutineVersion(sourceLabel: sourceLabel, steps: [
            RoutineStep(title: "A saved step", kind: .entertainment, durationMinutes: 5, isRequired: true)
        ], isApproved: true)
        var session = RoutineSession(routine: routine)
        if started { try session.start(at: start) }
        if completed { try session.advance(at: start.addingTimeInterval(15)) }
        else { try session.stop(at: start.addingTimeInterval(15)) }
        return try MorningRunRecord(session: session, timeZoneIdentifier: zone,
                                    recordedAt: start.addingTimeInterval(20), isSynthetic: synthetic)
    }

    @Test func calendarUsesActualDaysAcrossBothDSTChanges() throws {
        let paris = try calendar("Europe/Paris")
        for (today, expectedHours) in [("2026-03-30T12:00:00Z", 23.0), ("2026-10-26T12:00:00Z", 25.0)] {
            let end = try date(today)
            let navigation = try MorningInlineDayCalendar(today: end, calendar: paris)
            let days = try navigation.days(around: end)
            #expect(days.count == 7)
            #expect(Set(days).count == 7)
            #expect(days.last == navigation.today)
            #expect(days[6].timeIntervalSince(days[5]) == expectedHours * 3_600)
            #expect(try navigation.day(offset: -1, from: days[6]) == days[5])
            #expect(try navigation.day(offset: 1, from: days[5]) == days[6])
        }
    }

    @Test func windowCentersOldSelectionAndCrossesYearBoundaryWithoutHistoryLimit() throws {
        let utc = try calendar("UTC")
        let today = try date("2026-10-15T12:00:00Z")
        let selection = try date("2020-01-01T12:00:00Z")
        let navigation = try MorningInlineDayCalendar(today: today, calendar: utc)
        let days = try navigation.days(around: selection)
        #expect(days.first == (try date("2019-12-29T00:00:00Z")))
        #expect(days[3] == (try date("2020-01-01T00:00:00Z")))
        #expect(days.last == (try date("2020-01-04T00:00:00Z")))
        #expect(try navigation.day(offset: -365, from: selection) < days[0])
    }

    @Test func futureSelectionAndForwardNavigationClampToToday() throws {
        let now = try date("2026-10-15T22:30:00Z")
        let paris = try calendar("Europe/Paris")
        let navigation = try MorningInlineDayCalendar(today: now, calendar: paris)
        // It is already October 16 in Paris.
        let future = try date("2026-12-31T12:00:00Z")
        #expect(try navigation.day(offset: 1, from: now) == navigation.today)
        let snapshot = try MorningInlineDaySnapshot(selectedDate: future, today: now, calendar: paris)
        #expect(snapshot.dayKey == "2026-10-16")
        #expect(snapshot.date == navigation.today)
        #expect(snapshot.isToday)
        #expect(try navigation.days(around: future).allSatisfy { $0 <= navigation.today })
    }

    @Test func sourceLocalDaySurvivesTravelAndDisplayCalendarChange() throws {
        let instant = try date("2026-10-09T00:30:00Z")
        let savedRun = try run(at: instant, zone: "America/Los_Angeles")
        let savedObservation = try MorningInlineDayEvidence(id: UUID(), observedAt: instant,
            timeZoneIdentifier: "America/Los_Angeles", origin: .human)
        let history = MorningHistory(runs: [savedRun])
        let paris = try calendar("Europe/Paris", identifier: .buddhist)
        let original = try MorningInlineDaySnapshot(selectedDate: date("2026-10-08T12:00:00Z"),
            today: instant, calendar: paris, history: history, observations: [savedObservation])
        #expect(original.dayKey == "2026-10-08")
        #expect(original.state == .completed)
        #expect(original.completedRuns == [savedRun])
        #expect(original.observations == [savedObservation])
        #expect(original.sourceTimeZoneIdentifiers == ["America/Los_Angeles"])
        let current = try MorningInlineDaySnapshot(selectedDate: instant, today: instant,
            calendar: paris, history: history, observations: [savedObservation])
        #expect(current.dayKey == "2026-10-09")
        #expect(current.state == .noSavedEvidence)
    }

    @Test func timezoneChangesPreservePastCivilDayAndTodayFollowsActualNewDay() throws {
        let now = try date("2026-10-15T00:30:00Z")
        let paris = try calendar("Europe/Paris")
        let losAngeles = try calendar("America/Los_Angeles")
        let navigation = try MorningInlineDayCalendar(today: now, calendar: losAngeles)
        let oldPastSelection = paris.startOfDay(for: try date("2026-10-08T12:00:00Z"))
        // Interpreting that old midnight directly in LA would select October 7.
        #expect(losAngeles.component(.day, from: oldPastSelection) == 7)
        let past = try navigation.rebasedSelection(oldPastSelection, from: paris, at: now)
        #expect(losAngeles.component(.day, from: past) == 8)
        #expect(past == losAngeles.startOfDay(for: try date("2026-10-08T12:00:00Z")))
        let today = try navigation.rebasedSelection(paris.startOfDay(for: now), from: paris, at: now)
        #expect(today == navigation.today)
        #expect(losAngeles.component(.day, from: today) == 14)
        #expect(paris.component(.day, from: now) == 15)
    }

    @Test func completedStoppedAndUnstartedStoppedRemainDistinct() throws {
        let day = try date("2026-10-09T08:00:00Z")
        let utc = try calendar("UTC")
        let stopped = try run(at: day, completed: false)
        let unstarted = try run(at: day, completed: false, started: false)
        let completed = try run(at: day)
        let partialHistory = MorningHistory(runs: [stopped, unstarted])
        let partial = try MorningInlineDaySnapshot(selectedDate: day, today: day, calendar: utc, history: partialHistory)
        #expect(partial.state == .partial)
        #expect(partial.completedRuns.isEmpty)
        #expect(partial.stoppedRuns.count == 2)
        #expect(partial.stoppedRuns.allSatisfy { $0.completedStepCount == 0 })
        #expect(unstarted.startedAt == nil)
        let complete = try MorningInlineDaySnapshot(selectedDate: day, today: day, calendar: utc,
            history: MorningHistory(runs: [stopped, completed]))
        #expect(complete.state == .completed)
        #expect(complete.completedRuns == [completed])
        #expect(complete.stoppedRuns == [stopped])
        // Reading dates did not change either archived session or its routine.
        #expect(partialHistory.runs == [stopped, unstarted])
        #expect(partialHistory.runs[0].routine.id == stopped.routine.id)
    }

    @Test func syntheticAndUnmarkedSourcesNeverBecomePersonalDayEvidence() throws {
        let day = try date("2026-10-09T08:00:00Z")
        let syntheticRun = try run(at: day, synthetic: true)
        // Legacy run flags cannot override retained sample provenance in its routine.
        let legacySyntheticRun = try run(at: day, sourceLabel: "Demo fixture")
        let syntheticApp = try DailyAppObservation(date: day, timeZoneIdentifier: "UTC", appName: "Test app",
            provenance: .syntheticDemo, evidenceReferences: ["fixture"])
        let excluded = try [MorningInlineDayEvidenceOrigin.synthetic, .automated, .unknown].map {
            try MorningInlineDayEvidence(id: UUID(), observedAt: day, timeZoneIdentifier: "UTC", origin: $0)
        }
        let snapshot = try MorningInlineDaySnapshot(selectedDate: day, today: day, calendar: calendar("UTC"),
            history: MorningHistory(runs: [syntheticRun, legacySyntheticRun], appObservations: [syntheticApp]), observations: excluded)
        #expect(snapshot.state == .noSavedEvidence)
        #expect(snapshot.completedRuns.isEmpty)
        #expect(snapshot.observations.isEmpty)
        #expect(snapshot.appObservations.isEmpty)
        #expect(snapshot.sourceTimeZoneIdentifiers.isEmpty)
    }

    @Test func observationEvidenceDoesNotImplyRoutineCompletionOrFullDayCoverage() throws {
        let day = try date("2026-10-09T08:00:00Z")
        let note = try MorningInlineDayEvidence(id: UUID(), observedAt: day, timeZoneIdentifier: "UTC", origin: .human)
        let app = try DailyAppObservation(date: day, timeZoneIdentifier: "UTC", appName: "Test app",
            counts: .init(likes: 0), coverage: .partialWindow, provenance: .deviceCapture, evidenceReferences: ["frame"])
        for (history, evidence) in [(MorningHistory(), [note]), (MorningHistory(appObservations: [app]), [])] {
            let snapshot = try MorningInlineDaySnapshot(selectedDate: day, today: day, calendar: calendar("UTC"),
                history: history, observations: evidence)
            #expect(snapshot.state == .evidenceOnly)
            #expect(snapshot.completedRuns.isEmpty)
        }
        #expect(app.coverage == .partialWindow)
        #expect(app.counts.likes == 0)
        #expect(app.counts.emailsRead == nil)
    }

    @Test func undatedEvidenceIsUnassignedOnEveryDayAndInvalidMetadataIsRefused() throws {
        let day = try date("2026-10-09T08:00:00Z")
        let undated = try MorningInlineDayEvidence(id: UUID(), observedAt: nil, timeZoneIdentifier: nil, origin: .human)
        let unknown = try MorningInlineDayEvidence(id: UUID(), observedAt: nil, timeZoneIdentifier: nil, origin: .unknown)
        let snapshot = try MorningInlineDaySnapshot(selectedDate: day, today: day, calendar: calendar("UTC"),
            observations: [undated, unknown])
        #expect(snapshot.state == .noSavedEvidence)
        #expect(snapshot.observations.isEmpty)
        #expect(snapshot.undatedObservationCount == 1)
        #expect(undated.dayKey == nil)
        #expect(throws: MorningHistoryError.invalidTimeZone) {
            _ = try MorningInlineDayEvidence(id: UUID(), observedAt: day, timeZoneIdentifier: "invalid/zone", origin: .human)
        }
        #expect(throws: MorningHistoryError.invalidDate) {
            _ = try MorningInlineDayCalendar(today: Date(timeIntervalSince1970: .nan))
        }
    }
}
