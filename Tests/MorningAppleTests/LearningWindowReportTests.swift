import Foundation
import MorningCore
import Testing
@testable import MorningApple

/// Every recording here is manufactured: no capture, OCR, model or personal data. Each one
/// is built the way the app saves a native recording, with the start its session
/// acknowledged, so the path from a learning window to comparable mornings is the real one.
@Suite("Learning windows read against saved observations")
struct LearningWindowReportTests {
    private let paris = "Europe/Paris"
    private let feed = "visual-context:Feed"

    private func at(_ day: Int, _ hour: Int, _ minute: Int = 0, _ second: Int = 0,
                    zone: String = "Europe/Paris") throws -> Date {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = try #require(TimeZone(identifier: zone))
        return try #require(calendar.date(from: DateComponents(year: 2026, month: 10, day: day,
                                                                hour: hour, minute: minute, second: second)))
    }
    private func key(_ day: Int) -> String { String(format: "2026-10-%02d", day) }

    /// 07:00 to 07:05 in Paris, every day, started on Monday 12 October at 06:00.
    /// A recording may start up to 60 s late and end up to 30 s early.
    private func window(mornings: Int = 4) throws -> LearningWindow {
        var value = try LearningWindow(startMinuteOfDay: 7 * 60, durationSeconds: 300,
            weekdays: Set(LearningWindowWeekday.allCases), timeZoneIdentifier: paris, morningCount: mornings,
            createdAt: at(11, 20), limits: .currentCapture)
        try value.start(at: at(12, 6))
        return value
    }

    /// A native recording that started at `start` and lasted `seconds`, sampled 21 times.
    /// Each sample names the context it shows: F is the feed, C is chess.
    private func recording(_ start: Date, seconds: Double, zone: String = "Europe/Paris",
                           origin: ObservationAcquisitionOrigin = .human, pattern: String = "FFCC",
                           native: Bool = true) throws -> ObservationAcquisition {
        let letters = Array(pattern)
        let frames = try (0...20).map { index in
            try ObservationFrameEvidence(requestedTimeSeconds: Double(index) / 1_000,
                actualTimeSeconds: seconds * Double(index) / 20, outcome: .observed,
                text: letters[index % letters.count] == "F" ? "Feed" : "Chess")
        }
        let evidence = try ObservationVideoEvidence(durationSeconds: seconds, frames: frames)
        let decisions = frames.map { frame in
            ObservationFrameIdentityDecision(sampleID: frame.id, timeSeconds: frame.timeSeconds, timeBasis: frame.timeBasis,
                evidence: .identified(app: .init(key: "visual-context:\(frame.text)", displayName: frame.text),
                                      reference: frame.evidenceReference), evidenceQuote: frame.text)
        }
        let result = ObservationContextClassification(decisions: decisions, status: .completed,
            attemptedBatchCount: 1, respondedBatchCount: 1, failedBatchCount: 0,
            diagnostics: [], modelAvailability: "Synthetic test result; no model call")
        let context = native ? try ObservationRecordingContext(startedAt: start, timeZoneIdentifier: zone) : nil
        return try .init(observedDate: .init(date: start, timeZoneIdentifier: zone, provenance: .recordingSession),
                         origin: origin, sourceKind: .video, sourceLabel: "Synthetic recording",
                         originalText: evidence.renderedText, videoEvidence: evidence, classification: result,
                         recordingContext: context)
    }

    // MARK: The whole path

    @Test func aFourMorningWindowWithOneMissedAndOnePartialMorningReachesTheReportWithRightDenominators() throws {
        var learning = try window()
        var archive = ObservationArchive()
        // Monday: started 30 s late, ran the full five minutes.
        let monday = try recording(at(12, 7, 0, 30), seconds: 300)
        // Tuesday: nothing.
        // Wednesday: started two and a half minutes late.
        let wednesday = try recording(at(14, 7, 2, 30), seconds: 200)
        // Thursday: started ten seconds early.
        let thursday = try recording(at(15, 6, 59, 50), seconds: 320)
        for entry in [monday, wednesday, thursday] {
            try archive.insert(entry)
            try archive.declareCapture(of: entry.id, to: learning, at: entry.recordingContext!.startedAt.addingTimeInterval(900))
        }
        let now = try at(15, 8)
        let outcome1 = learning.completeIfDue(at: now)
        #expect(outcome1)

        let report = LearningWindowReport(window: learning, archive: archive, now: now)
        #expect(report.mornings.map(\.dayKey) == (12...15).map(key))
        #expect(report.mornings.map(\.status) == [.observedInWindow, .missed, .observedPartly, .observedInWindow])
        #expect(report.mornings.map(\.notCountedReason) == [nil, .missed, .observedPartly, nil])
        #expect(report.mornings[0].coverage == .init(expectedSeconds: 300, coveredSeconds: 270,
                                                     startedLateSeconds: 30, endedEarlySeconds: 0))
        // The missed morning has no coverage at all: not zero minutes of activity, nothing.
        #expect(report.mornings[1].coverage == nil && report.mornings[1].acquisitionIDs.isEmpty)
        // Recorded 07:02:30 to 07:05:00 of the window: two whole minutes, never rounded up to three.
        #expect(report.mornings[2].coverage == .init(expectedSeconds: 300, coveredSeconds: 150,
                                                     startedLateSeconds: 150, endedEarlySeconds: 0))
        #expect(report.mornings[2].coverage?.coveredMinutes == 2)
        #expect(report.mornings[2].coverage?.uncoveredSeconds == 150)
        #expect(report.mornings[3].coverage?.coveredSeconds == 300)
        #expect(report.progress == .init(askedMorningCount: 4, adequateMorningCount: 2, remainingMorningCount: 0))
        #expect(report.progress.stillNeededCount == 2 && report.progress.shortfallCount == 2)
        #expect(report.ignoredAcquisitionIDs.isEmpty && report.reassignedAcquisitionIDs.isEmpty)

        // The same archive through comparable mornings: four scheduled, two compared.
        let profile = try ComparableMorningProfile(window: learning, archive: archive, now: now, maximumSampleGapSeconds: 16)
        let comparison = profile.report
        #expect(comparison.origin == .human && !comparison.includesSynthetic)
        #expect(comparison.scheduledDayCount == 4)
        #expect(comparison.includedDayKeys == [key(12), key(15)])
        #expect(comparison.missingDayKeys == [key(13)])
        #expect(comparison.excludedDays == [.init(dayKey: key(14), reason: .partialCapture)])
        // Compared over the part of the window every adequate morning shares: 07:01:00 to 07:04:30.
        #expect(comparison.policy.expectedWindowSeconds == 210)
        #expect(comparison.observationDurationSeconds.mean == 210)
        #expect(comparison.observationDurationSeconds.daysWithEvidence == 2)
        #expect(comparison.observationDurationSeconds.scheduledDayCount == 4)
        #expect(comparison.observationDurationSeconds.daysWithoutEvidence == 2)
        let feedSummary = try #require(comparison.apps.first { $0.app.key == feed })
        // Two mornings, never four: the missed and the partial morning are not two zeros.
        #expect(feedSummary.minimumVisibleVisits.daysWithEvidence == 2)
        #expect(feedSummary.minimumVisibleVisits.scheduledDayCount == 4)
        #expect(comparison.firstContexts.allSatisfy { $0.frequency.daysWithEvidence == 2 && $0.frequency.scheduledDayCount == 4 })
        #expect(comparison.firstContexts.reduce(0) { $0 + $1.frequency.seenDayCount } == 2)
        #expect(profile.acquisitionIDsByDayKey == [key(12): [monday.id], key(14): [wednesday.id], key(15): [thursday.id]])
    }

    @Test func aRealMorningIsUnknownCaptureUntilItIsDeclaredToAWindow() throws {
        let learning = try window(mornings: 1)
        let entry = try recording(at(12, 7), seconds: 300)
        var archive = try ObservationArchive(entries: [entry])
        let now = try at(12, 8)
        let before = try ComparableMorningProfile(window: learning, archive: archive, now: now, maximumSampleGapSeconds: 16)
        #expect(before.report.excludedDays == [.init(dayKey: key(12), reason: .unknownCapture)])
        #expect(LearningWindowReport(window: learning, archive: archive, now: now).mornings.map(\.status) == [.missed])

        let capture = try archive.declareCapture(of: entry.id, to: learning, at: now)
        #expect(archive.entry(id: entry.id)?.windowCapture == capture)
        try #expect(capture.actualStart == (at(12, 7)) && capture.actualEnd == (at(12, 7, 5)))
        let after = try ComparableMorningProfile(window: learning, archive: archive, now: now, maximumSampleGapSeconds: 16)
        #expect(after.report.includedDayKeys == [key(12)] && after.report.excludedDays.isEmpty)
        #expect(LearningWindowReport(window: learning, archive: archive, now: now).progress.adequateMorningCount == 1)

        // The explicit per-call declaration that existed before still works, untouched.
        let explicit = try ComparableMorningProfile(archive: try ObservationArchive(entries: [entry]),
            scheduledDays: [try at(12, 7)], timeZoneIdentifier: paris, origin: .human, comparisonKey: "five-minutes",
            policy: .init(expectedWindowSeconds: 300, maximumSampleGapSeconds: 16),
            declaredCapture: [entry.id: [.init(startSeconds: 0, endSeconds: 300)]])
        #expect(explicit.report.includedDayKeys == [key(12)])
        #expect(explicit.report.observationDurationSeconds.mean == 300)
    }

    @Test func aMorningStillToComeIsNeitherMissedNorADayWithoutAnObservation() throws {
        let learning = try window(mornings: 3)
        var archive = ObservationArchive()
        let monday = try recording(at(12, 7), seconds: 300)
        try archive.insert(monday)
        try archive.declareCapture(of: monday.id, to: learning, at: at(12, 7, 10))
        // Tuesday 07:03: the window is open and nothing is saved yet.
        let now = try at(13, 7, 3)
        let report = LearningWindowReport(window: learning, archive: archive, now: now)
        #expect(report.mornings.map(\.status) == [.observedInWindow, .notYetDue, .notYetDue])
        #expect(report.progress == .init(askedMorningCount: 3, adequateMorningCount: 1, remainingMorningCount: 2))
        #expect(report.progress.stillNeededCount == 2 && report.progress.shortfallCount == 0)
        let profile = try ComparableMorningProfile(window: learning, archive: archive, now: now, maximumSampleGapSeconds: 16)
        #expect(profile.report.scheduledDayCount == 1 && profile.report.missingDayKeys.isEmpty)
    }

    // MARK: Statuses

    @Test func pausedAndSkippedMorningsAreReportedAsSuchAndNeverAsMissed() throws {
        var learning = try window(mornings: 2)
        try learning.skip(dayKey: key(13), at: at(12, 8))
        try learning.pause(at: at(13, 12))
        try learning.start(at: at(14, 12))
        let now = try at(16, 9)
        let report = LearningWindowReport(window: learning, archive: ObservationArchive(), now: now)
        #expect(report.mornings.map(\.dayKey) == (12...15).map(key))
        #expect(report.mornings.map(\.status) == [.missed, .skipped, .paused, .missed])
        #expect(report.progress == .init(askedMorningCount: 2, adequateMorningCount: 0, remainingMorningCount: 0))
        // Only the two counted mornings are scheduled days of the comparison.
        let profile = try ComparableMorningProfile(window: learning, archive: ObservationArchive(), now: now, maximumSampleGapSeconds: 16)
        #expect(profile.report.scheduledDayCount == 2)
        #expect(profile.report.missingDayKeys == [key(12), key(15)])
    }

    @Test func aRecordingOutsideTheWindowAnEarlyEndAndSeveralRecordingsNeverCountAsAnObservedMorning() throws {
        let learning = try window(mornings: 4)
        var archive = ObservationArchive()
        let evening = try recording(at(12, 19), seconds: 300)
        let endedEarly = try recording(at(13, 7), seconds: 240)
        let firstHalf = try recording(at(14, 7), seconds: 150)
        let secondHalf = try recording(at(14, 7, 2, 30), seconds: 150)
        let sample = try recording(at(15, 7), seconds: 300, origin: .synthetic)
        for entry in [evening, endedEarly, firstHalf, secondHalf, sample] {
            try archive.insert(entry)
            try archive.declareCapture(of: entry.id, to: learning, at: at(15, 20))
        }
        let now = try at(15, 21)
        let report = LearningWindowReport(window: learning, archive: archive, now: now)
        #expect(report.mornings.map(\.status) == [.observedOutsideWindow, .observedPartly, .observedInWindow, .observedInWindow])
        #expect(report.mornings.map(\.notCountedReason) == [.observedOutsideWindow, .observedPartly, .severalRecordings, .originNotConfirmed])
        #expect(report.mornings[0].coverage == .init(expectedSeconds: 300, coveredSeconds: 0,
                                                     startedLateSeconds: nil, endedEarlySeconds: nil))
        #expect(report.mornings[1].coverage == .init(expectedSeconds: 300, coveredSeconds: 240,
                                                     startedLateSeconds: 0, endedEarlySeconds: 60))
        #expect(report.mornings[2].acquisitionIDs == [firstHalf.id, secondHalf.id])
        #expect(report.progress.adequateMorningCount == 0)
        #expect(report.progress.stillNeededCount == 4 && report.progress.shortfallCount == 4)

        // Comparable mornings agree, each for its own stated reason.
        let profile = try ComparableMorningProfile(window: learning, archive: archive, now: now, maximumSampleGapSeconds: 16)
        #expect(profile.report.includedDayKeys.isEmpty)
        #expect(profile.report.excludedDays == [.init(dayKey: key(12), reason: .partialCapture),
                                                .init(dayKey: key(13), reason: .partialCapture),
                                                .init(dayKey: key(14), reason: .duplicateDay),
                                                .init(dayKey: key(15), reason: .differentOrigin)])
        // The same window learned from samples counts the sample morning and nothing else.
        let synthetic = LearningWindowReport(window: learning, archive: archive, now: now, origin: .synthetic)
        #expect(synthetic.mornings.map(\.notCountedReason) == [.observedOutsideWindow, .observedPartly, .severalRecordings, nil])
    }

    @Test func aSampleSavedBesideThePersonsRecordingNeitherJoinsNorBlocksTheMorning() throws {
        let learning = try window(mornings: 1)
        let person = try recording(at(12, 7), seconds: 300)
        let sample = try recording(at(12, 7, 0, 10), seconds: 300, origin: .synthetic)
        var archive = try ObservationArchive(entries: [person, sample])
        for entry in [person, sample] { try archive.declareCapture(of: entry.id, to: learning, at: at(12, 8)) }
        let now = try at(12, 9)
        // Progress and the comparison agree: one morning of the person's, judged on their recording alone.
        let report = LearningWindowReport(window: learning, archive: archive, now: now)
        #expect(report.mornings.map(\.notCountedReason) == [nil])
        #expect(report.progress.adequateMorningCount == 1)
        #expect(report.mornings[0].acquisitionIDs == [person.id, sample.id])
        let profile = try ComparableMorningProfile(window: learning, archive: archive, now: now, maximumSampleGapSeconds: 16)
        #expect(profile.report.includedDayKeys == [key(12)])
        #expect(profile.otherOriginAcquisitionIDs == [sample.id])
    }

    @Test func aRecordingThePersonMovedToAnotherDayNoLongerCountsForItsMorning() throws {
        let learning = try window(mornings: 2)
        let monday = try recording(at(12, 7), seconds: 300)
        var archive = try ObservationArchive(entries: [monday])
        try archive.declareCapture(of: monday.id, to: learning, at: at(12, 8))
        try archive.assignObservedDate(id: monday.id, value: .init(date: at(13, 7), timeZoneIdentifier: paris,
                                                                   provenance: .userAssigned))
        #expect(archive.entry(id: monday.id)?.windowCapture != nil, "The declaration itself is kept.")
        let now = try at(13, 9)
        let report = LearningWindowReport(window: learning, archive: archive, now: now)
        #expect(report.mornings.map(\.status) == [.missed, .missed])
        #expect(report.reassignedAcquisitionIDs == [monday.id])
        #expect(report.progress.adequateMorningCount == 0)
        // On the day it was moved to, it has no declared capture.
        let profile = try ComparableMorningProfile(window: learning, archive: archive, now: now, maximumSampleGapSeconds: 16)
        #expect(profile.report.missingDayKeys == [key(12)])
        #expect(profile.report.excludedDays == [.init(dayKey: key(13), reason: .unknownCapture)])
    }

    // MARK: Refusals

    @Test func onlyANativeRecordingOfTheWindowCanBeDeclaredAndOnlyOnce() throws {
        let learning = try window()
        let imported = try recording(at(12, 7), seconds: 300, native: false)
        let tokyo = try recording(at(13, 7, zone: "Asia/Tokyo"), seconds: 300, zone: "Asia/Tokyo")
        let good = try recording(at(13, 7), seconds: 300)
        var archive = try ObservationArchive(entries: [imported, tokyo, good])
        let untouched = archive

        // An imported file has no recording session: nothing knows when it was recorded.
        #expect(throws: LearningWindowError.recordingStartUnknown) {
            try archive.declareCapture(of: imported.id, to: learning, at: at(13, 9))
        }
        #expect(throws: LearningWindowError.differentTimeZone) {
            try archive.declareCapture(of: tokyo.id, to: learning, at: at(13, 9))
        }
        #expect(throws: ObservationArchiveError.unknownAcquisition) {
            try archive.declareCapture(of: UUID(), to: learning, at: at(13, 9))
        }
        #expect(archive == untouched)

        let first = try archive.declareCapture(of: good.id, to: learning, at: at(13, 9))
        #expect(throws: LearningWindowError.alreadyDeclared) {
            try archive.declareCapture(of: good.id, to: learning, at: at(13, 10))
        }
        try #expect(!archive.attachWindowCapture(first, to: good.id), "A second declaration never replaces the first.")
        #expect(archive.entry(id: good.id)?.windowCapture == first)

        // A declaration must describe that recording's own session and movie.
        let other = try learning.capture(recordingStartedAt: at(12, 7), recordingTimeZoneIdentifier: paris,
                                         recordedSeconds: 300, declaredAt: at(13, 9))
        var second = try ObservationArchive(entries: [good, imported])
        #expect(throws: ObservationArchiveError.invalidRecordingContext) { try second.attachWindowCapture(other, to: good.id) }
        #expect(throws: ObservationArchiveError.invalidRecordingContext) { try second.attachWindowCapture(first, to: imported.id) }
        let longer = try learning.capture(recordingStartedAt: at(13, 7), recordingTimeZoneIdentifier: paris,
                                          recordedSeconds: 301, declaredAt: at(13, 9))
        #expect(throws: ObservationArchiveError.invalidRecordingContext) { try second.attachWindowCapture(longer, to: good.id) }
    }

    /// Issue #19: "Stop/cancel must end acquisition and prevent later stale data from being
    /// appended to the session."
    @Test func stopEndsTheWindowAndPreventsLaterStaleDataFromBeingAppendedToIt() throws {
        var learning = try window(mornings: 3)
        let monday = try recording(at(12, 7), seconds: 300)
        let tuesday = try recording(at(13, 7), seconds: 300)
        var archive = try ObservationArchive(entries: [monday, tuesday])
        try archive.declareCapture(of: monday.id, to: learning, at: at(12, 7, 10))
        let running = learning

        // Tuesday was recorded 07:00 to 07:05. Stop is pressed at 07:06, before it is declared.
        let outcome2 = try learning.stop(at: at(13, 7, 6))
        #expect(outcome2)
        let stoppedArchive = archive
        #expect(throws: LearningWindowError.windowStopped) {
            try archive.declareCapture(of: tuesday.id, to: learning, at: at(13, 7, 7))
        }
        #expect(archive == stoppedArchive, "A refused recording leaves the archive as it was.")
        #expect(archive.entry(id: tuesday.id)?.windowCapture == nil)

        let now = try at(20, 9)
        var report = LearningWindowReport(window: learning, archive: archive, now: now)
        #expect(report.state == .stopped)
        // Wednesday was never reached. Tuesday had begun and has nothing declared.
        #expect(report.mornings.map(\.dayKey) == [key(12), key(13)])
        #expect(report.mornings.map(\.status) == [.observedInWindow, .missed])
        #expect(report.progress == .init(askedMorningCount: 3, adequateMorningCount: 1, remainingMorningCount: 0))
        #expect(report.progress.shortfallCount == 2)

        // A caller that still held the running window can write a late declaration on the
        // observation. The stopped window does not count it.
        try archive.declareCapture(of: tuesday.id, to: running, at: at(13, 7, 7))
        report = LearningWindowReport(window: learning, archive: archive, now: now)
        #expect(report.mornings.map(\.status) == [.observedInWindow, .missed])
        #expect(report.ignoredAcquisitionIDs == [tuesday.id])
        #expect(report.progress.adequateMorningCount == 1)
        let profile = try ComparableMorningProfile(window: learning, archive: archive, now: now, maximumSampleGapSeconds: 16)
        #expect(profile.report.includedDayKeys == [key(12)])
        #expect(profile.report.excludedDays == [.init(dayKey: key(13), reason: .unknownCapture)])
    }

    // MARK: Saved archives

    @Test func anArchiveSavedBeforeLearningWindowsLoadsUnchangedAndADeclarationSurvivesSaving() throws {
        let learning = try window()
        let entry = try recording(at(12, 7), seconds: 300)
        let old = try ObservationArchive(entries: [entry, recording(at(13, 7), seconds: 300, native: false)])
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        let oldData = try encoder.encode(old)
        let oldText = try #require(String(data: oldData, encoding: .utf8))
        // An archive with no declaration is written exactly as before: the field is absent.
        #expect(!oldText.contains("windowCapture"))
        let loaded = try JSONDecoder().decode(ObservationArchive.self, from: oldData)
        #expect(loaded == old)
        #expect(loaded.entries.allSatisfy { $0.windowCapture == nil })
        try #expect(encoder.encode(loaded) == oldData)

        var declared = loaded
        let capture = try declared.declareCapture(of: entry.id, to: learning, at: at(12, 8))
        let saved = try encoder.encode(declared)
        let restored = try JSONDecoder().decode(ObservationArchive.self, from: saved)
        #expect(restored == declared)
        #expect(restored.entry(id: entry.id)?.windowCapture == capture)
        // Everything else about the observation is as it was.
        #expect(restored.entry(id: entry.id)?.recordingContext == entry.recordingContext)
        #expect(restored.entry(id: entry.id)?.classification == entry.classification)
        // Later edits keep the declaration.
        var edited = restored
        try edited.assignObservedDate(id: entry.id, value: entry.observedDate, origin: .human)
        #expect(edited.entry(id: entry.id)?.windowCapture == capture)

        // A declaration that cannot be read costs the observation nothing but the declaration.
        var object = try #require(JSONSerialization.jsonObject(with: saved) as? [String: Any])
        var entries = try #require(object["entries"] as? [[String: Any]])
        var damaged = try #require(entries[0]["windowCapture"] as? [String: Any])
        damaged["actualEnd"] = "soon"
        entries[0]["windowCapture"] = damaged
        object["entries"] = entries
        let recovered = try JSONDecoder().decode(ObservationArchive.self, from: JSONSerialization.data(withJSONObject: object))
        #expect(recovered.entries.count == 2 && recovered.entry(id: entry.id)?.windowCapture == nil)
        #expect(recovered.entry(id: entry.id)?.videoEvidence == entry.videoEvidence)
    }

    @Test func theDurationBoundsAreTheRecordersOwn() throws {
        let limits = LearningWindowLimits.currentCapture
        #expect(limits.minimumDurationSeconds == ScreenRecordingDuration.allCases.map(\.rawValue).min())
        #expect(limits.maximumDurationSeconds == ScreenRecordingDuration.allCases.map(\.rawValue).max())
        #expect(limits == .init(minimumDurationSeconds: 300, maximumDurationSeconds: 1_800))
        #expect(throws: LearningWindowError.durationTooLong(maximumSeconds: 1_800)) {
            try LearningWindow(startMinuteOfDay: 420, durationSeconds: 2_400, weekdays: [.monday],
                               timeZoneIdentifier: paris, morningCount: 3, createdAt: at(11, 20), limits: limits)
        }
    }
}
