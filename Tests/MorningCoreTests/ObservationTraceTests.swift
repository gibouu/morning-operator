import Foundation
import Testing
@testable import MorningCore

@Suite("Timestamped observation evidence")
struct ObservationTraceTests {
    private let inbox = ObservationAppIdentity(key: "fixture.inbox", displayName: "Synthetic inbox")
    private let calendar = ObservationAppIdentity(key: "fixture.calendar", displayName: "Synthetic calendar")

    private func sample(_ time: Double, _ app: ObservationAppIdentity,
                        reference: String? = nil,
                        timeBasis: ObservationSampleTimeBasis = .mediaPresentation) -> ObservationTraceSample {
        .init(timeSeconds: time, timeBasis: timeBasis,
              appEvidence: .identified(app: app, reference: reference ?? "synthetic-frame-\(time)"))
    }

    private func trace(_ samples: [ObservationTraceSample], duration: Double = 10,
                       origin: ObservationTraceOrigin = .synthetic) throws -> ObservationTrace {
        try ObservationTrace(durationSeconds: duration,
                             capturedIntervals: [.init(startSeconds: 0, endSeconds: duration)],
                             origin: origin, samples: samples)
    }

    @Test func returnToIdenticalAppRemainsAnOrderedVisitRatherThanGlobalTextDeduplication() throws {
        let frames = [sample(0, inbox), sample(2, inbox), sample(4, calendar),
                      sample(6, calendar), sample(8, inbox), sample(10, inbox)]
        let input = try trace(frames)
        let report = try input.report(maximumSampleGapSeconds: 2)
        #expect(report.visits.map(\.app.key) == [inbox.key, calendar.key, inbox.key])
        #expect(report.appSummary(key: inbox.key)?.minimumVisibleVisitCount == 2)
        #expect(report.appSummary(key: inbox.key)?.minimumVisibleReturnCount == 1)
        #expect(report.appSummary(key: inbox.key)?.sampledVisibleSecondsEstimate == 4)
        #expect(report.appSummary(key: calendar.key)?.sampledVisibleSecondsEstimate == 2)
        #expect(report.observationDurationSeconds == 10)
        #expect(report.capturedDurationSeconds == 10)
        #expect(report.unassignedCapturedSeconds == 4)
        #expect(report.captureIsComplete)
        #expect(input.samples == frames)
        let decoded = try JSONDecoder().decode(ObservationTrace.self, from: JSONEncoder().encode(input))
        #expect(decoded == input)
        #expect(try decoded.report(maximumSampleGapSeconds: 2) == report)
    }

    @Test func repeatedContentAndDuplicatePresentationTimeDoNotCreateNewVisitsOrExtraDuration() throws {
        let frames = [sample(0, inbox, reference: "same-visible-content"),
                      sample(2, inbox, reference: "same-visible-content"),
                      sample(2, inbox, reference: "same-visible-content"),
                      sample(4, inbox, reference: "same-visible-content")]
        let report = try trace(frames, duration: 4).report(maximumSampleGapSeconds: 2)
        #expect(report.sampleCount == 4)
        #expect(report.distinctSampleMomentCount == 3)
        #expect(report.visits.count == 1)
        #expect(report.visits[0].sampleIDs.count == 4)
        #expect(report.appSummary(key: inbox.key)?.sampledVisibleSecondsEstimate == 4)
        #expect(report.appSummary(key: inbox.key)?.durationEvidenceSampleIDs.count == 4)
    }

    @Test func ambiguousFramesAndConflictingTiedLabelsCannotInventADepartureOrTimedUse() throws {
        let frames = [sample(0, inbox),
                      ObservationTraceSample(timeSeconds: 2, appEvidence: .ambiguous(reference: "obscured-frame")),
                      sample(4, inbox)]
        let report = try trace(frames, duration: 4).report(maximumSampleGapSeconds: 2)
        #expect(report.unidentifiedMomentCount == 1)
        #expect(report.appSummary(key: inbox.key)?.minimumVisibleVisitCount == 1)
        #expect(report.appSummary(key: inbox.key)?.sampledVisibleSecondsEstimate == nil)
        #expect(report.unassignedCapturedSeconds == 4)

        let tied = try trace([sample(0, inbox), sample(2, calendar), sample(2, inbox), sample(4, inbox)], duration: 4)
            .report(maximumSampleGapSeconds: 2)
        #expect(tied.unidentifiedMomentCount == 1)
        #expect(tied.appSummary(key: calendar.key) == nil)
        #expect(tied.visits.count == 1)
        #expect(tied.appSummary(key: inbox.key)?.sampledVisibleSecondsEstimate == nil)
    }

    @Test func unknownCaptureAndPartialCaptureRemainSeparateFromObservationDuration() throws {
        let frames = stride(from: 0, through: 10, by: 2).map { sample(Double($0), inbox) }
        let unknown = try ObservationTrace(durationSeconds: 10, capturedIntervals: nil,
                                           origin: .synthetic, samples: frames).report(maximumSampleGapSeconds: 2)
        #expect(unknown.observationDurationSeconds == 10)
        #expect(unknown.capturedDurationSeconds == nil)
        #expect(unknown.unassignedCapturedSeconds == nil)
        #expect(unknown.appSummary(key: inbox.key)?.sampledVisibleSecondsEstimate == nil)
        #expect(unknown.appSummary(key: inbox.key)?.minimumVisibleVisitCount == 1)

        let partial = try ObservationTrace(durationSeconds: 10,
                                           capturedIntervals: [.init(startSeconds: 0, endSeconds: 3),
                                                               .init(startSeconds: 5, endSeconds: 10)],
                                           origin: .synthetic, samples: frames).report(maximumSampleGapSeconds: 2)
        #expect(partial.capturedDurationSeconds == 8)
        #expect(!partial.captureIsComplete)
        #expect(partial.appSummary(key: inbox.key)?.sampledVisibleSecondsEstimate == 6)
        #expect(partial.unassignedCapturedSeconds == 2)
    }

    @Test func failedSamplesRequestedTimesAndLongGapsDoNotBecomeContinuousDuration() throws {
        let failed = try trace([sample(0, inbox), .init(timeSeconds: 2, outcome: .decodeFailed), sample(4, inbox)], duration: 4)
            .report(maximumSampleGapSeconds: 2)
        #expect(failed.unidentifiedMomentCount == 1)
        #expect(failed.appSummary(key: inbox.key)?.sampledVisibleSecondsEstimate == nil)
        let fallback = try trace([sample(0, inbox), sample(2, inbox, timeBasis: .requestedSamplingTime)], duration: 2)
            .report(maximumSampleGapSeconds: 2)
        #expect(fallback.hasRequestedTimeFallback)
        #expect(fallback.appSummary(key: inbox.key)?.sampledVisibleSecondsEstimate == nil)
        let sparse = try trace([sample(0, inbox), sample(10, inbox)]).report(maximumSampleGapSeconds: 2)
        #expect(sparse.largestObservedSampleGapSeconds == 10)
        #expect(sparse.appSummary(key: inbox.key)?.sampledVisibleSecondsEstimate == nil)
    }

    @Test func invalidTimesCoverageIdentityAndDuplicateEventsAreRejectedIncludingDecode() throws {
        for time in [-1.0, 11.0, Double.nan, Double.infinity] {
            #expect(throws: ObservationTraceError.invalidTimestamp) { try trace([sample(time, inbox)]) }
        }
        #expect(throws: ObservationTraceError.unorderedSamples) { try trace([sample(4, inbox), sample(2, calendar)]) }
        let duplicated = sample(2, inbox)
        #expect(throws: ObservationTraceError.duplicateSampleID) { try trace([duplicated, duplicated]) }
        #expect(throws: ObservationTraceError.invalidAppEvidence) { try trace([sample(2, inbox, reference: " ")]) }
        #expect(throws: ObservationTraceError.invalidCoverage) {
            try ObservationTrace(durationSeconds: 10,
                                 capturedIntervals: [.init(startSeconds: 0, endSeconds: 6),
                                                     .init(startSeconds: 4, endSeconds: 10)], origin: .synthetic, samples: [])
        }
        let data = try JSONEncoder().encode(trace([]))
        var object = try #require(JSONSerialization.jsonObject(with: data) as? [String: Any])
        object["durationSeconds"] = -1
        let malformed = try JSONSerialization.data(withJSONObject: object)
        #expect(throws: ObservationTraceError.invalidDuration) { try JSONDecoder().decode(ObservationTrace.self, from: malformed) }
    }

    private func date(_ day: Int) -> Date {
        // Synthetic consecutive UTC dates, intentionally unrelated to an actual capture date.
        Date(timeIntervalSince1970: 1_760_000_000 + Double(day) * 86_400)
    }

    private func day(_ number: Int, sequence: [ObservationAppIdentity],
                     origin: ObservationTraceOrigin = .synthetic,
                     partial: Bool = false) throws -> ObservationTraceDay {
        let frames = sequence.enumerated().map { sample(Double($0.offset), $0.element) }
        let observation = try ObservationTrace(durationSeconds: 7,
            capturedIntervals: [.init(startSeconds: 0, endSeconds: partial ? 6 : 7)], origin: origin, samples: frames)
        return try ObservationTraceDay(date: date(number), timeZoneIdentifier: "UTC", comparisonKey: "synthetic-seven-second-v1", trace: observation)
    }

    private func window(_ days: [ObservationTraceDay], count: Int = 5,
                        origin: ObservationTraceOrigin = .synthetic) throws -> ObservationTraceWindowReport {
        try ObservationTraceWindowReport(days: days, scheduledDays: (0..<count).map(date), timeZoneIdentifier: "UTC",
            comparisonKey: "synthetic-seven-second-v1",
            policy: .init(expectedWindowSeconds: 7, maximumSampleGapSeconds: 1), origin: origin)
    }

    @Test func fourObservedDaysOutOfFiveUseFourAndMetricSpecificDenominators() throws {
        let twice = [inbox, inbox, calendar, calendar, inbox, inbox, inbox, inbox]
        let three = [inbox, calendar, inbox, calendar, inbox, inbox, inbox, inbox]
        let once = Array(repeating: inbox, count: 8)
        let days = try [day(0, sequence: twice), day(1, sequence: three), day(2, sequence: once), day(3, sequence: twice)]
        let result = try window(days)
        #expect(result.scheduledDayCount == 5)
        #expect(result.includedDayKeys.count == 4)
        #expect(result.missingDayKeys.count == 1)
        #expect(result.excludedDays.isEmpty)
        #expect(result.includesSynthetic)
        let matchingInbox = result.apps.first { $0.app.key == inbox.key }
        let inboxResult = try #require(matchingInbox)
        #expect(inboxResult.minimumVisibleVisits.mean == 2)
        #expect(inboxResult.minimumVisibleVisits.daysWithEvidence == 4)
        #expect(inboxResult.minimumVisibleVisits.minimum == 1)
        #expect(inboxResult.minimumVisibleVisits.maximum == 3)
        let matchingCalendar = result.apps.first { $0.app.key == calendar.key }
        let calendarResult = try #require(matchingCalendar)
        #expect(calendarResult.minimumVisibleVisits.mean == 1)
        #expect(calendarResult.minimumVisibleVisits.daysWithEvidence == 4)
        #expect(calendarResult.sampledVisibleSecondsEstimate.mean == 1)
        #expect(calendarResult.sampledVisibleSecondsEstimate.daysWithEvidence == 2)
        #expect(result.observationDurationSeconds.mean == 7)
    }

    @Test func partialFifthDayIsExcludedRatherThanMissingOrAZeroMorning() throws {
        let sequence = Array(repeating: inbox, count: 8)
        let days = try (0..<5).map { try day($0, sequence: sequence, partial: $0 == 4) }
        let result = try window(days)
        #expect(result.includedDayKeys.count == 4)
        #expect(result.missingDayKeys.isEmpty)
        #expect(result.excludedDays.map(\.reason) == [.partialCapture])
        #expect(result.apps.first?.minimumVisibleVisits.mean == 1)
        #expect(result.apps.first?.minimumVisibleVisits.daysWithEvidence == 4)
    }

    @Test func humanAndSyntheticWindowsCannotMixAndDuplicateDaysCannotInflateAverages() throws {
        let sequence = Array(repeating: inbox, count: 8)
        let human = try day(0, sequence: sequence, origin: .human)
        let synthetic = try day(1, sequence: sequence)
        let result = try window([human, synthetic], count: 2, origin: .human)
        #expect(result.includedDayKeys.count == 1)
        #expect(result.excludedDays.map(\.reason) == [.differentOrigin])
        #expect(!result.includesSynthetic)
        #expect(result.apps.first?.minimumVisibleVisits.daysWithEvidence == 1)
        #expect(throws: ObservationTraceError.duplicateDay) { try window([human, human], count: 1, origin: .human) }
        let reused = try ObservationTraceDay(date: date(1), timeZoneIdentifier: "UTC",
                                            comparisonKey: human.comparisonKey, trace: human.trace)
        #expect(throws: ObservationTraceError.duplicateTraceID) { try window([human, reused], count: 2, origin: .human) }
        #expect(throws: ObservationTraceError.invalidPolicy) { try window([human], count: 1, origin: .unknown) }
    }

    @Test func noUsableDaysProduceUnknownAveragesWithoutInventedAppMetrics() throws {
        let result = try window([])
        #expect(result.missingDayKeys.count == 5)
        #expect(result.observationDurationSeconds.mean == nil)
        #expect(result.observationDurationSeconds.daysWithEvidence == 0)
        #expect(result.apps.isEmpty)
    }

    @Test func mixedTimeZonesAreRejectedAndSparseAnalysisDoesNotBecomeAnEligibleMorning() throws {
        let frames = [sample(0, inbox), sample(7, inbox)]
        let observation = try trace(frames, duration: 7)
        let travel = try ObservationTraceDay(date: date(0), timeZoneIdentifier: "Europe/Paris",
                                           comparisonKey: "synthetic-seven-second-v1", trace: observation)
        #expect(throws: ObservationTraceError.incompatibleTimeZone) { try window([travel], count: 1) }
        let sparse = try ObservationTraceDay(date: date(0), timeZoneIdentifier: "UTC",
                                           comparisonKey: "synthetic-seven-second-v1", trace: observation)
        let result = try window([sparse], count: 1)
        #expect(result.excludedDays.map(\.reason) == [.sparseSamples])
        #expect(result.observationDurationSeconds.daysWithEvidence == 0)
        #expect(result.apps.isEmpty)
    }
}
