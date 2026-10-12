import Foundation
import MorningCore
import Testing
@testable import MorningApple

@Suite("Derived sampled-morning review")
struct ObservationReviewReportTests {
    private func date(_ text: String = "2026-10-09T12:00:00Z") throws -> Date {
        try #require(ISO8601DateFormatter().date(from: text))
    }
    private func observed(_ text: String = "2026-10-09T12:00:00Z", zone: String = "Europe/Paris") throws -> ObservationObservedDate {
        try .init(date: date(text), timeZoneIdentifier: zone, provenance: .userAssigned)
    }
    private func clip(_ labels: [String?], times: [Double]? = nil,
                      zone: String = "Europe/Paris", day: String? = "2026-10-09T12:00:00Z",
                      origin: ObservationAcquisitionOrigin = .human, classified: Bool = true,
                      key: ((String) -> String)? = nil) throws -> ObservationAcquisition {
        let values = times ?? labels.indices.map { Double($0) }
        let frames = try labels.enumerated().map { index, label in
            // Different requests can resolve to the same actual movie frame.
            try ObservationFrameEvidence(requestedTimeSeconds: Double(index) / 1_000, actualTimeSeconds: values[index],
                outcome: .observed, text: label ?? "Unresolved synthetic screen")
        }
        let evidence = try ObservationVideoEvidence(durationSeconds: (values.max() ?? 0) + 1, frames: frames)
        let decisions = zip(frames, labels).map { frame, label in
            ObservationFrameIdentityDecision(sampleID: frame.id, timeSeconds: frame.timeSeconds, timeBasis: frame.timeBasis,
                evidence: label.map { .identified(app: .init(key: key?($0) ?? "visual-context:\($0)", displayName: $0),
                                                    reference: frame.evidenceReference) } ?? .unknown,
                evidenceQuote: label)
        }
        let result = ObservationContextClassification(decisions: decisions, status: .completed,
            attemptedBatchCount: 1, respondedBatchCount: 1, failedBatchCount: 0,
            diagnostics: [], modelAvailability: "Synthetic test result; no model call")
        return try .init(importedAt: date(), observedDate: day.map { try observed($0, zone: zone) }, origin: origin,
            sourceKind: .video, sourceLabel: "Synthetic recording", originalText: evidence.renderedText,
            videoEvidence: evidence, classification: classified ? result : nil)
    }
    private func period(_ entries: [ObservationAcquisition]) throws -> ObservationReviewPeriod {
        try .init(archive: ObservationArchive(entries: entries), endingOn: date(), calendarTimeZoneIdentifier: "Europe/Paris")
    }

    @Test func unknownBetweenEqualContextsStaysVisibleWithoutInventingAReturn() throws {
        let source = try clip(["Today", nil, "Today"])
        let review = try ObservationClipReview(acquisition: source)
        #expect(review.rows.count == 3)
        #expect(review.rows.map(\.resolution) == [.recognized, .unknown, .recognized])
        #expect(review.rows.flatMap(\.samples).map(\.id) == source.videoEvidence?.frames.map(\.id))
        let report = try #require(review.traceReport)
        #expect(report.visits.count == 1)
        #expect(report.apps.first?.minimumVisibleReturnCount == 0)
        #expect(report.capturedDurationSeconds == nil)
        #expect(report.unassignedCapturedSeconds == nil)
        #expect(report.apps.allSatisfy { $0.sampledVisibleSecondsEstimate == nil })
        #expect(review.rows[0].resolvedContext?.displayName == "Today")
        #expect(review.rows[0].resolvedContext?.key == "visual-context:Today")
    }

    @Test func observedReturnHasExactPerSampleCitationsWithoutMeasuredDuration() throws {
        let source = try clip(["Cedar Mail", "Lumen Calendar", "Cedar Mail"])
        let review = try ObservationClipReview(acquisition: source)
        let report = try #require(review.traceReport)
        #expect(report.visits.map { $0.app.displayName } == ["Cedar Mail", "Lumen Calendar", "Cedar Mail"])
        #expect(report.appSummary(key: "visual-context:Cedar Mail")?.minimumVisibleReturnCount == 1)
        #expect(report.apps.allSatisfy { $0.sampledVisibleSecondsEstimate == nil })
        let weekly = try period([source])
        let recurrence = try #require(weekly.personalPartitions.first?.recurrence.first { $0.context.displayName == "Cedar Mail" })
        #expect(recurrence.seenDayCount == 1)
        #expect(recurrence.citations.count == 2)
        #expect(recurrence.citations.allSatisfy { $0.acquisitionID == source.id && $0.quote == "Cedar Mail" })
        #expect(Set(recurrence.citations.map(\.sampleID)) == Set([review.rows[0].id, review.rows[2].id]))
    }

    @Test func tiedTimestampConflictsAndUnknownsAreOneUnresolvedMoment() throws {
        let source = try clip(["Cedar", "Lumen", "Cedar"], times: [0, 0, 1])
        let review = try ObservationClipReview(acquisition: source)
        #expect(review.rows.count == 2)
        #expect(review.rows[0].samples.count == 2)
        #expect(review.rows[0].resolution == .conflicting)
        #expect(review.rows[0].resolvedContext == nil)
        #expect(review.traceReport?.visits.count == 1)
        #expect(review.traceReport?.unidentifiedMomentCount == 1)
        let incomplete = try ObservationClipReview(acquisition: clip(["Cedar", nil], times: [0, 0]))
        #expect(incomplete.rows[0].resolution == .conflicting)
        #expect(incomplete.traceReport?.visits.isEmpty == true)
        let agrees = try ObservationClipReview(acquisition: clip(["Cedar", "Cedar"], times: [0, 0]))
        #expect(agrees.rows[0].resolution == .recognized)
        #expect(agrees.traceReport?.distinctSampleMomentCount == 1)
        #expect(agrees.traceReport?.visits.first?.sampleIDs.count == 2)
    }

    @Test func failuresAndRequestedTimesKeepTheirOriginalEvidence() throws {
        let frames = try [
            ObservationFrameEvidence(requestedTimeSeconds: 0, outcome: .decodeFailed),
            ObservationFrameEvidence(requestedTimeSeconds: 1, actualTimeSeconds: 1, outcome: .blank),
            ObservationFrameEvidence(requestedTimeSeconds: 2, actualTimeSeconds: 2, outcome: .ocrFailed),
            ObservationFrameEvidence(requestedTimeSeconds: 3, outcome: .observed, text: "Today")
        ]
        let evidence = try ObservationVideoEvidence(durationSeconds: 4, frames: frames)
        let source = try ObservationAcquisition(sourceKind: .video, sourceLabel: "Synthetic failure samples",
            originalText: evidence.renderedText, videoEvidence: evidence)
        let review = try ObservationClipReview(acquisition: source)
        #expect(review.interpretationState == .unclassified)
        #expect(review.rows.flatMap(\.samples).map(\.frame) == frames)
        #expect(review.rows.map(\.hasRequestedTimeFallback) == [true, false, false, true])
        #expect(review.unknownMomentCount == 4)
        #expect(review.traceReport?.hasRequestedTimeFallback == true)
        #expect(review.traceReport?.apps.isEmpty == true)
    }

    @Test func decreasingActualTimesLeaveOneClipUnknownWithoutHidingOtherEvidence() throws {
        let malformed = try clip(["Cedar", "Lumen"], times: [2, 1])
        let valid = try clip(["Today"], day: "2026-10-08T12:00:00Z")
        let result = try period([malformed, valid])
        let partition = try #require(result.personalPartitions.first)
        let bad = try #require(partition.days.flatMap(\.clips).first { $0.id == malformed.id })
        #expect(bad.timelineOrderIsValid == false)
        #expect(bad.interpretationState == .invalid)
        #expect(bad.rows.map(\.timeSeconds) == [2, 1])
        #expect(bad.rows.flatMap(\.samples).map(\.id) == malformed.videoEvidence?.frames.map(\.id))
        #expect(bad.rows.allSatisfy { $0.resolvedContext == nil && $0.resolution == .unknown })
        #expect(bad.traceReport == nil)
        #expect(partition.observedDayCount == 2)
        #expect(partition.recognizedDayCount == 1)
        #expect(partition.recurrence.first?.context.displayName == "Today")
        #expect(partition.unclassifiedDayKeys == ["2026-10-09"])
    }

    @Test func ambiguousQuotationRemainsInspectableWithoutAnIdentity() throws {
        let evidence = try #require(clip(["Cedar or Lumen"]).videoEvidence)
        let frame = try #require(evidence.frames.first)
        let result = ObservationContextClassification(decisions: [.init(sampleID: frame.id, timeSeconds: 0,
            timeBasis: frame.timeBasis, evidence: .ambiguous(reference: frame.evidenceReference), evidenceQuote: frame.text)],
            status: .completed, attemptedBatchCount: 1, respondedBatchCount: 1, failedBatchCount: 0,
            diagnostics: [], modelAvailability: "Synthetic test result")
        let source = try ObservationAcquisition(sourceKind: .video, sourceLabel: "Synthetic ambiguity",
            originalText: evidence.renderedText, videoEvidence: evidence, classification: result)
        let review = try ObservationClipReview(acquisition: source)
        #expect(review.rows.first?.resolution == .ambiguous)
        #expect(review.rows.first?.samples.first?.quote == frame.text)
        #expect(review.rows.first?.resolvedContext == nil)
        #expect(review.traceReport?.visits.isEmpty == true)
    }

    @Test func multipleClipsAndMultipleOccurrencesStillContributeOneDay() throws {
        let first = try clip(["Today", "Today", "Today"])
        let second = try clip(["Today", "Other", "Today"])
        let previous = try clip(["Today"], day: "2026-10-08T12:00:00Z")
        let report = try period([first, second, previous])
        let partition = try #require(report.personalPartitions.first)
        #expect(partition.days.count == 7)
        #expect(partition.observedDayCount == 2)
        #expect(partition.recognizedDayCount == 2)
        #expect(partition.missingDayKeys.count == 5)
        #expect(partition.days.last?.clips.count == 2)
        let repeated = try #require(partition.recurrence.first { $0.context.displayName == "Today" })
        #expect(repeated.seenDayKeys == ["2026-10-08", "2026-10-09"])
        #expect(repeated.citations.count == 6)
        #expect(Set(repeated.citations.map(\.acquisitionID)) == Set([first.id, second.id, previous.id]))
    }

    @Test func zoneOriginAndSavedLocalDatePartitionWithoutReinterpretingTravel() throws {
        let paris = try clip(["Today"], day: "2026-10-09T00:30:00Z")
        let la = try clip(["Today"], zone: "America/Los_Angeles", day: "2026-10-09T00:30:00Z")
        let sample = try clip(["Today"], origin: .synthetic)
        let automated = try clip(["Today"], origin: .automated)
        let unknown = try clip(["Today"], origin: .unknown)
        let report = try period([paris, la, sample, automated, unknown])
        #expect(report.partitions.count == 5)
        #expect(report.personalPartitions.count == 2)
        let laPart = try #require(report.personalPartitions.first { $0.timeZoneIdentifier == "America/Los_Angeles" })
        #expect(laPart.recurrence.first?.seenDayKeys == ["2026-10-08"])
        #expect(report.personalPartitions.first { $0.timeZoneIdentifier == "Europe/Paris" }?.recurrence.first?.seenDayKeys == ["2026-10-09"])
        #expect(Set(report.partitions.map(\.id)).count == report.partitions.count)
        #expect(report.partitions.allSatisfy { Set($0.days.map(\.id)).count == 7 })
    }

    @Test func missingUnclassifiedAndCorrectedDaysStayOutOfRecognitionDenominator() throws {
        let seen = try clip(["Today"])
        let unclassified = try clip(["Today"], day: "2026-10-08T12:00:00Z", classified: false)
        let corrected = try clip(["Today"], day: "2026-10-07T12:00:00Z")
        let undated = try clip(["Today"], day: nil)
        var archive = try ObservationArchive(entries: [seen, unclassified, corrected, undated])
        try archive.correct(id: corrected.id, text: "My correction")
        let report = try ObservationReviewPeriod(archive: archive, endingOn: date(), calendarTimeZoneIdentifier: "Europe/Paris")
        let partition = try #require(report.personalPartitions.first)
        #expect(partition.observedDayCount == 3)
        #expect(partition.recognizedDayCount == 1)
        #expect(partition.missingDayKeys.count == 4)
        #expect(partition.unclassifiedDayKeys == ["2026-10-07", "2026-10-08"])
        #expect(partition.correctedDayKeys == ["2026-10-07"])
        #expect(partition.recurrence.first?.seenDayCount == 1)
        #expect(report.undatedAcquisitionIDs == [undated.id])
        let correctedClip = try #require(partition.days.flatMap(\.clips).first { $0.id == corrected.id })
        #expect(correctedClip.interpretationState == .corrected)
        #expect(correctedClip.rows.first?.samples.first?.frame.text == "Today")
        #expect(correctedClip.traceReport?.visits.isEmpty == true)
    }

    @Test func recomputesAfterCorrectionRedateDeletionAndReload() throws {
        let first = try clip(["Today"])
        let second = try clip(["Today"], day: "2026-10-08T12:00:00Z")
        var archive = try ObservationArchive(entries: [first, second])
        func report(_ value: ObservationArchive) throws -> ObservationReviewPeriod {
            try .init(archive: value, endingOn: date(), calendarTimeZoneIdentifier: "Europe/Paris")
        }
        #expect(try report(archive).personalPartitions.first?.recurrence.first?.seenDayCount == 2)
        try archive.assignObservedDate(id: second.id, value: observed(), origin: .human)
        #expect(try report(archive).personalPartitions.first?.recurrence.first?.seenDayCount == 1)
        try archive.correct(id: first.id, text: "A correction")
        #expect(try report(archive).personalPartitions.first?.recurrence.first?.citations.map(\.acquisitionID) == [second.id])
        let beforeReload = try report(archive)
        let restored = try JSONDecoder().decode(ObservationArchive.self, from: JSONEncoder().encode(archive))
        #expect(try report(restored) == beforeReload)
        try archive.delete(id: second.id)
        #expect(try report(archive).personalPartitions.first?.recurrence.isEmpty == true)
        try archive.delete(id: first.id)
        #expect(try report(archive).partitions.isEmpty)
    }

    @Test func conflictingSameKeyLabelsCannotCreateCrossClipRecurrence() throws {
        let first = try clip(["Cedar"], key: { _ in "visual-context:shared" })
        let second = try clip(["Lumen"], day: "2026-10-08T12:00:00Z", key: { _ in "visual-context:shared" })
        let result = try period([first, second])
        let partition = try #require(result.personalPartitions.first)
        #expect(partition.conflictingContextKeys == ["visual-context:shared"])
        #expect(partition.recurrence.isEmpty)
        #expect(partition.days.flatMap(\.clips).flatMap(\.rows).compactMap(\.resolvedContext).count == 2)
    }

    @Test func invalidQuoteIsDiscardedByArchiveAndDoesNotReappearInReview() throws {
        let source = try clip(["Today"])
        let evidence = try #require(source.videoEvidence)
        let frame = try #require(evidence.frames.first)
        let invalid = ObservationContextClassification(decisions: [.init(sampleID: frame.id, timeSeconds: frame.timeSeconds,
            timeBasis: frame.timeBasis, evidence: .identified(app: .init(key: "visual-context:Calendar", displayName: "Calendar"),
                reference: frame.evidenceReference), evidenceQuote: "Calendar")], status: .completed,
            attemptedBatchCount: 1, respondedBatchCount: 1, failedBatchCount: 0, diagnostics: [], modelAvailability: "Synthetic")
        let acquisition = try ObservationAcquisition(sourceKind: .video, sourceLabel: "Synthetic invalid quote",
            originalText: evidence.renderedText, videoEvidence: evidence, classification: invalid)
        let report = try ObservationClipReview(acquisition: acquisition)
        #expect(report.interpretationState == .invalid)
        #expect(report.rows.first?.samples.first?.frame.text == "Today")
        #expect(report.rows.first?.samples.first?.quote == nil)
        #expect(report.traceReport?.visits.isEmpty == true)
    }

    @Test func sevenLocalDaysUseCalendarArithmeticAndRejectInvalidPeriod() throws {
        let empty = ObservationArchive()
        let report = try ObservationReviewPeriod(archive: empty, endingOn: date("2026-03-30T12:00:00Z"),
            calendarTimeZoneIdentifier: "Europe/Paris")
        #expect(report.dayKeys == ["2026-03-24", "2026-03-25", "2026-03-26", "2026-03-27", "2026-03-28", "2026-03-29", "2026-03-30"])
        #expect(report.partitions.isEmpty)
        #expect(throws: ObservationReviewError.invalidPeriod) {
            try ObservationReviewPeriod(archive: empty, endingOn: date(), calendarTimeZoneIdentifier: "not/a-zone")
        }
        #expect(throws: ObservationReviewError.invalidPeriod) {
            try ObservationReviewPeriod(archive: empty, endingOn: Date(timeIntervalSince1970: .infinity), calendarTimeZoneIdentifier: "UTC")
        }
    }
}
