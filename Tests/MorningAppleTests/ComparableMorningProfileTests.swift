import Foundation
import MorningCore
import Testing
@testable import MorningApple

/// Every observation here is manufactured: no capture, OCR, model or personal data.
@Suite("Comparable mornings from the saved archive")
struct ComparableMorningProfileTests {
    private let zone = "Europe/Paris"
    private let scope = "synthetic-seven-second-morning-v1"
    private let feed = "visual-context:Feed"
    private let chess = "visual-context:Chess"
    private let complete = [ObservationTraceInterval(startSeconds: 0, endSeconds: 7)]

    /// 07:00 in Paris on a day of October 2026.
    private func date(_ day: Int, zone: String = "Europe/Paris") throws -> Date {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = try #require(TimeZone(identifier: zone))
        return try #require(calendar.date(from: DateComponents(year: 2026, month: 10, day: day, hour: 7)))
    }
    private func key(_ day: Int) -> String { String(format: "2026-10-%02d", day) }

    /// One sample a second for seven seconds, each naming the context it shows.
    private func clip(_ day: Int?, _ letters: String, origin: ObservationAcquisitionOrigin = .synthetic,
                      zone: String = "Europe/Paris") throws -> ObservationAcquisition {
        let labels = letters.map { $0 == "F" ? "Feed" : "Chess" }
        let frames = try labels.enumerated().map { index, label in
            try ObservationFrameEvidence(requestedTimeSeconds: Double(index) / 1_000, actualTimeSeconds: Double(index),
                                         outcome: .observed, text: label)
        }
        let evidence = try ObservationVideoEvidence(durationSeconds: 7, frames: frames)
        let decisions = zip(frames, labels).map { frame, label in
            ObservationFrameIdentityDecision(sampleID: frame.id, timeSeconds: frame.timeSeconds, timeBasis: frame.timeBasis,
                evidence: .identified(app: .init(key: "visual-context:\(label)", displayName: label),
                                      reference: frame.evidenceReference), evidenceQuote: label)
        }
        let result = ObservationContextClassification(decisions: decisions, status: .completed,
            attemptedBatchCount: 1, respondedBatchCount: 1, failedBatchCount: 0,
            diagnostics: [], modelAvailability: "Synthetic test result; no model call")
        let observed = try day.map {
            try ObservationObservedDate(date: date($0, zone: zone), timeZoneIdentifier: zone, provenance: .userAssigned)
        }
        return try .init(observedDate: observed, origin: origin, sourceKind: .video,
                         sourceLabel: "Synthetic recording", originalText: evidence.renderedText,
                         videoEvidence: evidence, classification: result)
    }

    private func profile(_ entries: [ObservationAcquisition], days: ClosedRange<Int>,
                         origin: ObservationAcquisitionOrigin = .synthetic,
                         capture: [UUID: [ObservationTraceInterval]]? = nil) throws -> ComparableMorningProfile {
        try ComparableMorningProfile(archive: ObservationArchive(entries: entries),
            scheduledDays: days.map { try date($0) }, timeZoneIdentifier: zone, origin: origin,
            comparisonKey: scope, policy: .init(expectedWindowSeconds: 7, maximumSampleGapSeconds: 1),
            declaredCapture: capture ?? Dictionary(uniqueKeysWithValues: entries.map { ($0.id, complete) }))
    }

    @Test func fourAdequateMorningsOutOfSixKeepMissingAndPartialDaysOutOfEveryDenominator() throws {
        let entries = try [clip(1, "FFCCFFFF"), clip(2, "FCFCFFFF"), clip(3, "CCCCCCCC"),
                           clip(4, "FFCCFFFF"), clip(5, "FFFFFFFF")]
        var capture = Dictionary(uniqueKeysWithValues: entries.map { ($0.id, complete) })
        capture[entries[4].id] = [.init(startSeconds: 0, endSeconds: 6)]
        let result = try profile(entries, days: 1...6, capture: capture)
        let report = result.report

        #expect(report.scheduledDayCount == 6)
        #expect(report.includedDayKeys == (1...4).map(key))
        #expect(report.excludedDays == [.init(dayKey: key(5), reason: .partialCapture)])
        #expect(report.missingDayKeys == [key(6)])
        #expect(report.includesSynthetic)
        #expect(result.acquisitionIDsByDayKey.count == 5)
        #expect(result.acquisitionIDsByDayKey[key(6)] == nil)

        // Duration and visit ranges each state how many mornings they rest on.
        #expect(report.observationDurationSeconds.mean == 7)
        #expect(report.observationDurationSeconds.daysWithEvidence == 4)
        #expect(report.observationDurationSeconds.daysWithoutEvidence == 2)
        let feedSummary = try #require(report.apps.first { $0.app.key == feed })
        // 2, 3, 0 and 2 visits over four mornings. The missing and partial days are not two
        // more zeros: the mean is 7/4, never 7/6.
        #expect(feedSummary.minimumVisibleVisits.mean == 1.75)
        #expect(feedSummary.minimumVisibleVisits.minimum == 0)
        #expect(feedSummary.minimumVisibleVisits.maximum == 3)
        #expect(feedSummary.minimumVisibleVisits.daysWithEvidence == 4)
        #expect(feedSummary.minimumVisibleVisits.scheduledDayCount == 6)
        // A duration estimate exists only on the three mornings that showed the feed.
        #expect(feedSummary.sampledVisibleSecondsEstimate.daysWithEvidence == 3)
        #expect(feedSummary.sampledVisibleSecondsEstimate.minimum == 3)
        #expect(feedSummary.sampledVisibleSecondsEstimate.maximum == 4)
        let chessSummary = try #require(report.apps.first { $0.app.key == chess })
        #expect(chessSummary.sampledVisibleSecondsEstimate.maximum == 7)

        #expect(report.firstContexts.map(\.app.key) == [feed, chess])
        #expect(report.firstContexts[0].frequency.seenDayKeys == [key(1), key(2), key(4)])
        #expect(report.firstContexts[0].frequency.daysWithEvidence == 4)
        #expect(report.firstContexts[0].frequency.scheduledDayCount == 6)
        #expect(report.firstContexts[1].frequency.seenDayKeys == [key(3)])
        #expect(report.transitions.map { [$0.from.key, $0.to.key] } == [[chess, feed], [feed, chess]])
        #expect(report.transitions.allSatisfy { $0.frequency.seenDayCount == 3 && $0.frequency.daysWithEvidence == 4 })
    }

    @Test func humanAndSyntheticNeverShareAProfileAndAssistantOrUnlabelledDaysAreNeverIncluded() throws {
        let sample = try clip(1, "FFFFFFFF")
        let person = try clip(2, "FFFFFFFF", origin: .human)
        let assistant = try clip(3, "FFFFFFFF", origin: .automated)
        let unlabelled = try clip(4, "FFFFFFFF", origin: .unknown)
        let sameDateSample = try clip(2, "CCCCCCCC")
        let entries = [sample, person, assistant, unlabelled, sameDateSample]

        let human = try profile(entries, days: 1...4, origin: .human)
        #expect(human.report.origin == .human)
        #expect(human.report.includedDayKeys == [key(2)])
        #expect(!human.report.includesSynthetic)
        #expect(human.report.missingDayKeys.isEmpty)
        #expect(human.report.excludedDays == [.init(dayKey: key(1), reason: .differentOrigin),
                                              .init(dayKey: key(3), reason: .automatedOrigin),
                                              .init(dayKey: key(4), reason: .unknownOrigin)])
        // The sample saved on the person's date is set aside; it neither joins nor blocks it.
        #expect(human.report.apps.map(\.app.key) == [feed])
        #expect(human.acquisitionIDsByDayKey == [key(2): [person.id]])
        #expect(human.otherOriginAcquisitionIDs == [sample.id, assistant.id, unlabelled.id, sameDateSample.id])

        let synthetic = try profile(entries, days: 1...4)
        #expect(synthetic.report.includedDayKeys == [key(1), key(2)])
        #expect(synthetic.report.includesSynthetic)
        #expect(synthetic.otherOriginAcquisitionIDs == [person.id, assistant.id, unlabelled.id])

        for origin in [ObservationAcquisitionOrigin.automated, .unknown] {
            #expect(throws: ObservationTraceError.invalidPolicy) { try profile(entries, days: 1...4, origin: origin) }
        }
    }

    @Test func twoRecordingsOnOneDateExcludeThatDateWithAReasonInsteadOfThrowing() throws {
        let first = try clip(1, "FFFFFFFF")
        let second = try clip(1, "CCCCCCCC")
        let other = try clip(2, "FFCCFFFF")
        let result = try profile([first, second, other], days: 1...2)
        #expect(result.report.excludedDays == [.init(dayKey: key(1), reason: .duplicateDay)])
        #expect(result.report.includedDayKeys == [key(2)])
        #expect(result.report.missingDayKeys.isEmpty)
        #expect(result.acquisitionIDsByDayKey[key(1)] == [first.id, second.id])
        // Neither recording of the excluded date reaches an estimate.
        #expect(result.report.observationDurationSeconds.daysWithEvidence == 1)
        #expect(result.report.firstContexts.map(\.frequency.seenDayKeys) == [[key(2)]])
    }

    @Test func oneExtractionSavedOnTwoDatesIsNotTwoMornings() throws {
        let first = try clip(1, "FFCCFFFF")
        let again = try ObservationAcquisition(
            observedDate: .init(date: date(2), timeZoneIdentifier: zone, provenance: .userAssigned),
            origin: .synthetic, sourceKind: .video, sourceLabel: "Synthetic recording, saved again",
            originalText: first.originalText, videoEvidence: first.videoEvidence, classification: first.classification)
        let result = try profile([first, again, try clip(3, "CCCCCCCC")], days: 1...3)
        #expect(result.report.excludedDays == [.init(dayKey: key(1), reason: .repeatedRecording),
                                              .init(dayKey: key(2), reason: .repeatedRecording)])
        #expect(result.report.includedDayKeys == [key(3)])
        #expect(result.report.apps.map(\.app.key) == [chess])
    }

    @Test func recordingsWithNoDeclaredCaptureAreExcludedAsUnknownCaptureNotGuessed() throws {
        let entries = try (1...4).map { try clip($0, "FFCCFFFF", origin: .human) }
        let result = try profile(entries, days: 1...4, origin: .human, capture: [:])
        #expect(result.report.includedDayKeys.isEmpty)
        #expect(result.report.missingDayKeys.isEmpty)
        #expect(result.report.excludedDays.map(\.reason) == Array(repeating: .unknownCapture, count: 4))
        #expect(result.report.observationDurationSeconds.mean == nil)
        #expect(result.report.observationDurationSeconds.daysWithEvidence == 0)
        #expect(result.report.apps.isEmpty)
        #expect(result.report.firstContexts.isEmpty)
        #expect(result.report.transitions.isEmpty)
    }

    @Test func undatedOtherZoneNotesOnlyCorrectedAndUnorderedObservationsNeverBecomeMornings() throws {
        let undated = try clip(nil, "FFFFFFFF")
        let elsewhere = try clip(1, "FFFFFFFF", zone: "America/Toronto")
        let notes = try ObservationAcquisition(
            observedDate: .init(date: date(2), timeZoneIdentifier: zone, provenance: .userAssigned),
            origin: .synthetic, sourceKind: .text, sourceLabel: "Synthetic notes", originalText: "Read the feed, then chess.")
        let corrected = try clip(3, "FFFFFFFF")
        // Two samples whose actual movie times run backwards cannot be read as a sequence.
        let backwards = try ObservationVideoEvidence(durationSeconds: 7, frames: [
            .init(requestedTimeSeconds: 0, actualTimeSeconds: 5, outcome: .observed, text: "Feed"),
            .init(requestedTimeSeconds: 1, actualTimeSeconds: 2, outcome: .observed, text: "Chess")
        ])
        let unordered = try ObservationAcquisition(
            observedDate: .init(date: date(4), timeZoneIdentifier: zone, provenance: .userAssigned),
            origin: .synthetic, sourceKind: .video, sourceLabel: "Synthetic recording",
            originalText: backwards.renderedText, videoEvidence: backwards)
        var archive = try ObservationArchive(entries: [undated, elsewhere, notes, corrected, unordered])
        try archive.correct(id: corrected.id, text: "I was playing chess, not reading the feed.")
        let result = try ComparableMorningProfile(archive: archive, scheduledDays: (1...4).map { try date($0) },
            timeZoneIdentifier: zone, origin: .synthetic, comparisonKey: scope,
            policy: .init(expectedWindowSeconds: 7, maximumSampleGapSeconds: 1),
            declaredCapture: [corrected.id: complete, unordered.id: complete])
        #expect(result.undatedAcquisitionIDs == [undated.id])
        #expect(result.otherTimeZoneAcquisitionIDs == [elsewhere.id])
        #expect(result.report.missingDayKeys == [key(1)])
        // A correction withdraws the model's reading of the recording, so nothing is identified.
        #expect(result.report.excludedDays == [.init(dayKey: key(2), reason: .noSampledEvidence),
                                              .init(dayKey: key(3), reason: .unresolvedSamples),
                                              .init(dayKey: key(4), reason: .unreadableSamples)])
        #expect(result.report.includedDayKeys.isEmpty)
    }

    /// Fixture, not an observed week: four manufactured mornings whose social browsing varies
    /// and which all show the same ritual. A shorter target must not be met by dropping it.
    @Test func shorterTargetDoesNotDropTheRequiredRitualAcrossFourSyntheticMornings() throws {
        let entries = try [clip(1, "FFCCFFFF"), clip(2, "FCFCFCCC"), clip(3, "CCCCFFFF"), clip(4, "FCFCFCFC")]
        let result = try profile(entries, days: 1...4)
        #expect(result.report.includedDayKeys.count == 4)
        let browsing = try #require(result.report.apps.first { $0.app.key == feed })
        #expect(browsing.minimumVisibleVisits.minimum == 1)
        #expect(browsing.minimumVisibleVisits.maximum == 4)
        #expect(browsing.minimumVisibleVisits.daysWithEvidence == 4)
        let ritualSeen = try #require(result.report.apps.first { $0.app.key == chess })
        #expect(ritualSeen.minimumVisibleVisits.minimum == 1)
        // It stays labelled as a fixture, and contributes nothing to a personal profile.
        #expect(result.report.origin == .synthetic)
        #expect(result.report.includesSynthetic)
        let personal = try profile(entries, days: 1...4, origin: .human)
        #expect(personal.report.includedDayKeys.isEmpty)
        #expect(personal.report.excludedDays.map(\.reason) == Array(repeating: .differentOrigin, count: 4))
        #expect(personal.report.apps.isEmpty)

        let ritual = RoutineStep(title: "Morning chess", detail: "A game for myself.", kind: .entertainment,
                                 durationMinutes: 8, isRequired: true)
        let current = RoutineVersion(sourceLabel: "Approved routine", steps: [
            RoutineStep(title: "Social browsing", kind: .entertainment, durationMinutes: 12), ritual
        ], isApproved: true)
        // A shorter suggestion that reaches ten minutes only by leaving the ritual out.
        let shorter = RoutineVersion(sourceLabel: "Synthetic four-morning fixture", steps: [
            RoutineStep(title: "Social browsing", kind: .entertainment, durationMinutes: 4)
        ])
        var journal = RoutinePreferenceJournal()
        try journal.upsert(RoutinePreference(target: ritual, presence: .keep))

        var draft = RoutineVersion.inferredDraft(from: shorter, preserving: current)
        #expect(draft.steps.filter { $0 == ritual }.count == 1)
        #expect(!draft.isApproved)
        let reconciled = try journal.reconcile(steps: draft.steps)
        #expect(reconciled.steps.filter { $0 == ritual }.count == 1)
        #expect(reconciled.retainedStepIDs == [ritual.id])
        // The journal alone restores it when there is no earlier routine to inherit from.
        let fresh = RoutineVersion.inferredDraft(from: shorter, preserving: nil)
        #expect(!fresh.steps.contains(ritual))
        #expect(try journal.reconcile(steps: fresh.steps).steps.filter { $0 == ritual }.count == 1)

        draft.steps = reconciled.steps
        let budget = RoutineTimeBudget(routine: draft, targetMinutes: 10, preferences: journal)
        #expect(budget.totalMinutes == 12)
        #expect(budget.fit == .overTarget)
        #expect(budget.requiredStepIDs == [ritual.id])
        #expect(budget.choices == [.editRoutine, .acceptLongerPlan])
        #expect(budget.longerPlanMinutes == 12)
        #expect(RoutineTimeBudget(routine: draft, targetMinutes: 6, preferences: journal).fit == .requiredAloneOverTarget)
        #expect(draft.steps.contains(ritual))
    }
}
