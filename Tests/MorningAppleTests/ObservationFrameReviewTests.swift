import Foundation
import MorningCore
import Testing
@testable import MorningApple

@Suite("Reviewed screen evidence")
struct ObservationFrameReviewTests {
    private let savedAt = Date(timeIntervalSince1970: 1_791_547_200)

    private func source(_ texts: [String] = ["Cedar Mail\nInbox", "Lumen Calendar\nToday"],
                        times: [Double]? = nil, dayOffset: Int = 0,
                        classified: Bool = true) throws -> ObservationAcquisition {
        let frames = try texts.enumerated().map { index, text in
            try ObservationFrameEvidence(requestedTimeSeconds: Double(index) / 10,
                actualTimeSeconds: times?[index] ?? Double(index), outcome: .observed, text: text)
        }
        let evidence = try ObservationVideoEvidence(durationSeconds: 10, frames: frames)
        let decisions = frames.map { frame in
            ObservationFrameIdentityDecision(sampleID: frame.id, timeSeconds: frame.timeSeconds,
                timeBasis: frame.timeBasis, evidence: .identified(app: .init(key: "visual-context:cedar",
                    displayName: "Cedar"), reference: frame.evidenceReference),
                evidenceQuote: String(frame.text.split(separator: "\n")[0]))
        }
        let interpretation = ObservationContextClassification(decisions: decisions, status: .completed,
            attemptedBatchCount: 1, respondedBatchCount: 1, failedBatchCount: 0, diagnostics: [],
            modelAvailability: "Synthetic test fixture; no model invocation")
        return try .init(importedAt: savedAt, fileSHA256: String(repeating: "a", count: 63) + String(dayOffset + 1),
            observedDate: .init(date: savedAt.addingTimeInterval(Double(dayOffset) * 86_400),
                timeZoneIdentifier: "Europe/Paris", provenance: .userAssigned), origin: .synthetic,
            sourceKind: .video, sourceLabel: "Synthetic reviewed screen fixture", originalText: evidence.renderedText,
            videoEvidence: evidence, classification: classified ? interpretation : nil)
    }

    private func label(_ frame: ObservationFrameEvidence, _ label: String = "Mail") throws -> ObservationFrameReview {
        try .init(sampleID: frame.id, label: label,
            evidenceQuote: String(frame.text.split(separator: "\n")[0]), reviewedAt: savedAt)
    }

    @Test func roundTripKeepsOriginalSourceAndModelSeparateFromOrderedHumanReviews() throws {
        let original = try source()
        let frames = try #require(original.videoEvidence?.frames)
        try #require(frames.count == 2)
        var archive = try ObservationArchive(entries: [original])
        let second = try label(frames[1], "Calendar")
        let first = try label(frames[0], "Mail")
        try archive.reviewFrame(id: original.id, review: second)
        try archive.reviewFrame(id: original.id, review: first)
        let restored = try JSONDecoder().decode(ObservationArchive.self, from: JSONEncoder().encode(archive))
        let entry = try #require(restored.entry(id: original.id))
        #expect(entry.frameReviews == [first, second])
        #expect(entry.originalText.utf8.elementsEqual(original.originalText.utf8))
        #expect(entry.videoEvidence == original.videoEvidence)
        #expect(entry.classification == original.classification)
        #expect(entry.observedDate == original.observedDate)
        #expect(entry.importedAt == original.importedAt)
        #expect(entry.correctedText == nil)
        let rows = try ObservationClipReview(acquisition: entry).rows
        #expect(rows.flatMap(\.samples).map(\.provenance) == [.userReviewed, .userReviewed])
        #expect(rows.flatMap(\.samples).map(\.frame) == frames)
    }

    @Test func explicitUnknownOverridesWithoutErasingModelAndRemovalRestoresIt() throws {
        let original = try source(["Cedar Mail"])
        let frame = try #require(original.videoEvidence?.frames.first)
        var archive = try ObservationArchive(entries: [original])
        try archive.reviewFrame(id: original.id, review: label(frame))
        let unknown = try ObservationFrameReview(sampleID: frame.id, label: nil, reviewedAt: savedAt)
        try archive.reviewFrame(id: original.id, review: unknown)
        let entry = try #require(archive.entry(id: original.id))
        #expect(entry.frameReviews == [unknown])
        #expect(entry.classification == original.classification)
        let clip = try ObservationClipReview(acquisition: entry)
        #expect(clip.rows.first?.resolution == .unknown)
        #expect(clip.rows.first?.samples.first?.provenance == .userReviewed)
        #expect(clip.rows.first?.samples.first?.quote == nil)
        #expect(clip.traceReport?.apps.isEmpty == true)
        try archive.removeFrameReview(id: original.id, sampleID: frame.id)
        let reset = try ObservationClipReview(acquisition: #require(archive.entry(id: original.id)))
        #expect(reset.rows.first?.resolvedContext?.key == "visual-context:cedar")
        #expect(reset.rows.first?.samples.first?.provenance == .model)
    }

    @Test func exactQuotesRejectCanonicalEquivalenceOtherFramesAndUnknownIDsTransactionally() throws {
        let original = try source(["Caf\u{00e9}", "Other header"])
        let frames = try #require(original.videoEvidence?.frames)
        try #require(frames.count == 2)
        var archive = try ObservationArchive(entries: [original])
        let before = archive
        for (id, quote) in [(frames[0].id, "Cafe\u{0301}"), (frames[0].id, "Other header"), (UUID(), "Caf\u{00e9}")] {
            let review = try ObservationFrameReview(sampleID: id, label: "Cafe", evidenceQuote: quote, reviewedAt: savedAt)
            #expect(throws: ObservationArchiveError.invalidFrameReview) { try archive.reviewFrame(id: original.id, review: review) }
            #expect(archive == before)
        }
        try archive.reviewFrame(id: original.id, review: label(frames[0], "Cafe"))
        #expect(archive.entry(id: original.id)?.frameReviews.first?.evidenceQuote?.utf8.elementsEqual("Caf\u{00e9}".utf8) == true)
    }

    @Test func standaloneReviewRejectsInvalidBoundsAndKeepsExactLabelIdentity() throws {
        let id = UUID()
        for value in ["", " \n ", String(repeating: "x", count: 81), "Mail\nCalendar", "Mail\u{0000}"] {
            #expect(throws: ObservationArchiveError.invalidFrameReview) {
                try ObservationFrameReview(sampleID: id, label: value, evidenceQuote: "Mail", reviewedAt: savedAt)
            }
        }
        #expect(throws: ObservationArchiveError.invalidFrameReview) {
            try ObservationFrameReview(sampleID: id, label: "Mail", evidenceQuote: String(repeating: "x", count: 321))
        }
        #expect(throws: ObservationArchiveError.invalidFrameReview) {
            try ObservationFrameReview(sampleID: id, label: nil, evidenceQuote: "Mail")
        }
        #expect(throws: ObservationArchiveError.invalidFrameReview) {
            try ObservationFrameReview(sampleID: id, label: nil, reviewedAt: Date(timeIntervalSince1970: .infinity))
        }
        let first = try ObservationFrameReview(sampleID: id, label: "Caf\u{00e9}", evidenceQuote: "Header", reviewedAt: savedAt)
        let other = try ObservationFrameReview(sampleID: id, label: "Cafe\u{0301}", evidenceQuote: "Header", reviewedAt: savedAt)
        #expect(first != other)
        #expect(first.contextIdentity?.key != other.contextIdentity?.key)
        #expect(first.contextIdentity?.key.hasPrefix("reviewed-context:") == true)
        let anotherFrame = try ObservationFrameReview(sampleID: UUID(), label: "Caf\u{00e9}", evidenceQuote: "Different source", reviewedAt: savedAt)
        #expect(first.contextIdentity == anotherFrame.contextIdentity)
    }

    @Test func failedAndTruncatedFramesCannotGainLabelButCanBeExplicitlyUnknown() throws {
        let frames = try [
            ObservationFrameEvidence(requestedTimeSeconds: 0, actualTimeSeconds: 0, outcome: .observed, text: "Partial header", textWasTruncated: true),
            ObservationFrameEvidence(requestedTimeSeconds: 1, outcome: .decodeFailed),
            ObservationFrameEvidence(requestedTimeSeconds: 2, actualTimeSeconds: 2, outcome: .blank)
        ]
        let video = try ObservationVideoEvidence(durationSeconds: 3, frames: frames)
        let original = try ObservationAcquisition(sourceKind: .video, sourceLabel: "Synthetic failed extraction",
            originalText: video.renderedText, videoEvidence: video)
        var archive = try ObservationArchive(entries: [original])
        for frame in frames {
            let invalid = try ObservationFrameReview(sampleID: frame.id, label: "Mail", evidenceQuote: "Partial header", reviewedAt: savedAt)
            #expect(throws: ObservationArchiveError.invalidFrameReview) { try archive.reviewFrame(id: original.id, review: invalid) }
            try archive.reviewFrame(id: original.id, review: .init(sampleID: frame.id, label: nil, reviewedAt: savedAt))
        }
        let clip = try ObservationClipReview(acquisition: #require(archive.entry(id: original.id)))
        #expect(clip.recognizedMomentCount == 0)
        #expect(clip.rows.flatMap(\.samples).allSatisfy { $0.provenance == .userReviewed })
    }

    @Test func duplicateAndOversizedReviewArraysAreRejectedWithoutSourceMutation() throws {
        let original = try source(["Cedar Mail"])
        let frame = try #require(original.videoEvidence?.frames.first)
        let review = try label(frame)
        for reviews in [[review, review], Array(repeating: review, count: 25)] {
            #expect(throws: ObservationArchiveError.invalidFrameReview) {
                try ObservationAcquisition(sourceKind: .video, sourceLabel: "Synthetic review bounds",
                    originalText: original.originalText, videoEvidence: original.videoEvidence, frameReviews: reviews)
            }
        }
    }

    @Test func legacyAndMalformedRestorationPreserveSourceWithoutRevivingRejectedModel() throws {
        let original = try source(["Cedar Mail"])
        let frame = try #require(original.videoEvidence?.frames.first)
        var archive = try ObservationArchive(entries: [original])
        try archive.reviewFrame(id: original.id, review: .init(sampleID: frame.id, label: nil, reviewedAt: savedAt))
        let saved = try #require(archive.entry(id: original.id))
        var encoded = try #require(JSONSerialization.jsonObject(with: JSONEncoder().encode(saved)) as? [String: Any])
        encoded.removeValue(forKey: "frameReviews")
        let legacy = try JSONDecoder().decode(ObservationAcquisition.self, from: JSONSerialization.data(withJSONObject: encoded))
        #expect(legacy.frameReviews.isEmpty)
        #expect(legacy.classification == original.classification)
        encoded["frameReviews"] = NSNull()
        #expect(try JSONDecoder().decode(ObservationAcquisition.self, from: JSONSerialization.data(withJSONObject: encoded)).frameReviews.isEmpty)
        let reviewObject = try #require(JSONSerialization.jsonObject(with: JSONEncoder().encode(try label(frame))) as? [String: Any])
        var wrongQuote = reviewObject; wrongQuote["evidenceQuote"] = "Not the source"
        var wrongID = reviewObject; wrongID["sampleID"] = UUID().uuidString
        let invalidOverlays: [Any] = ["damaged overlay", [wrongQuote], [wrongID], [reviewObject, reviewObject]]
        for invalid in invalidOverlays {
            encoded["frameReviews"] = invalid
            let restored = try JSONDecoder().decode(ObservationAcquisition.self, from: JSONSerialization.data(withJSONObject: encoded))
            #expect(restored.originalText == original.originalText)
            #expect(restored.videoEvidence == original.videoEvidence)
            #expect(restored.observedDate == original.observedDate)
            #expect(restored.frameReviews.isEmpty)
            #expect(restored.classification == nil)
            #expect(restored.warnings.contains(.invalidFrameReviewsRemoved))
            #expect(try ObservationClipReview(acquisition: restored).recognizedMomentCount == 0)
        }
    }

    @Test func sourceEditsClearReviewsButUnchangedSavesDedupAndMetadataUpdatesPreserveThem() throws {
        let original = try source(["Cedar Mail"])
        let frame = try #require(original.videoEvidence?.frames.first)
        var archive = try ObservationArchive(entries: [original])
        let review = try label(frame)
        try archive.reviewFrame(id: original.id, review: review)
        try archive.correct(id: original.id, text: nil)
        try archive.classify(id: original.id, result: original.classification)
        try archive.assignObservedDate(id: original.id, value: nil, origin: .automated)
        let context = try ObservationRecordingContext(startedAt: savedAt, timeZoneIdentifier: "Europe/Paris")
        _ = try archive.attachRecordingContext(context, to: original.id, matchingFileSHA256: #require(original.fileSHA256))
        let reimport = try source(["Different synthetic OCR"])
        #expect(try archive.insert(reimport) == original.id)
        #expect(archive.entry(id: original.id)?.frameReviews == [review])
        #expect(archive.entry(id: original.id)?.recordingContext == context)
        try archive.correct(id: original.id, text: "Edited synthetic observation")
        #expect(archive.entry(id: original.id)?.frameReviews.isEmpty == true)
        #expect(archive.entry(id: original.id)?.classification == nil)
        #expect(throws: ObservationArchiveError.correctedObservation) { try archive.reviewFrame(id: original.id, review: review) }
        try archive.correct(id: original.id, text: nil)
        #expect(archive.entry(id: original.id)?.frameReviews.isEmpty == true)
        #expect(archive.entry(id: original.id)?.classification == nil)
        #expect(archive.entry(id: original.id)?.originalText == original.originalText)
    }

    @Test func reviewedReturnsAndTwoDayRecurrenceKeepIndependentCitationsWithoutDurations() throws {
        let first = try source(["Cedar Mail", "Lumen Calendar", "Cedar Mail"], classified: false)
        let second = try source(["Cedar Mail"], dayOffset: 1, classified: false)
        var archive = try ObservationArchive(entries: [first, second])
        for entry in [first, second] {
            for frame in entry.videoEvidence?.frames ?? [] {
                try archive.reviewFrame(id: entry.id, review: label(frame, frame.text == "Lumen Calendar" ? "Calendar" : "Mail"))
            }
        }
        let clip = try ObservationClipReview(acquisition: #require(archive.entry(id: first.id)))
        #expect(clip.classificationStatus == nil)
        #expect(clip.traceReport?.visits.map { $0.app.displayName } == ["Mail", "Calendar", "Mail"])
        #expect(clip.traceReport?.apps.first { $0.app.displayName == "Mail" }?.minimumVisibleReturnCount == 1)
        #expect(clip.traceReport?.capturedDurationSeconds == nil)
        #expect(clip.traceReport?.apps.allSatisfy { $0.sampledVisibleSecondsEstimate == nil } == true)
        let period = try ObservationReviewPeriod(archive: archive, endingOn: savedAt.addingTimeInterval(86_400), calendarTimeZoneIdentifier: "Europe/Paris")
        let partition = try #require(period.partitions.first)
        let mail = try #require(partition.recurrence.first { $0.context.displayName == "Mail" })
        #expect(mail.seenDayCount == 2)
        #expect(mail.citations.count == 3)
        #expect(mail.citations.allSatisfy { $0.provenance == .userReviewed && $0.quote == "Cedar Mail" })
        #expect(partition.missingDayKeys.count == 5)
        #expect(partition.recognizedDayCount == 2)
        #expect(Set(mail.citations.map(\.acquisitionID)) == Set([first.id, second.id]))
    }

    @Test func equalNamesNeverSilentlyMergeModelAndUserEvidence() throws {
        let original = try source(["Cedar Mail", "Cedar Mail"])
        let frame = try #require(original.videoEvidence?.frames.first)
        var archive = try ObservationArchive(entries: [original])
        try archive.reviewFrame(id: original.id, review: label(frame, "Cedar"))
        let period = try ObservationReviewPeriod(archive: archive, endingOn: savedAt, calendarTimeZoneIdentifier: "Europe/Paris")
        let recurrence = try #require(period.partitions.first).recurrence
        #expect(recurrence.count == 2)
        #expect(recurrence.allSatisfy { $0.context.displayName == "Cedar" && $0.seenDayCount == 1 })
        #expect(Set(recurrence.flatMap(\.citations).map(\.provenance)) == Set([.model, .userReviewed]))
    }

    @Test func duplicatePresentationTimesStillRequireAgreementAndNeverInventOrder() throws {
        let original = try source(["Cedar Mail", "Lumen Calendar"], times: [0, 0])
        let frames = try #require(original.videoEvidence?.frames)
        try #require(frames.count == 2)
        var archive = try ObservationArchive(entries: [original])
        try archive.reviewFrame(id: original.id, review: label(frames[0], "Mail"))
        var clip = try ObservationClipReview(acquisition: #require(archive.entry(id: original.id)))
        #expect(clip.rows.first?.resolution == .conflicting)
        #expect(clip.traceReport?.visits.isEmpty == true)
        try archive.reviewFrame(id: original.id, review: .init(sampleID: frames[1].id, label: nil, reviewedAt: savedAt))
        clip = try ObservationClipReview(acquisition: #require(archive.entry(id: original.id)))
        #expect(clip.rows.first?.resolution == .conflicting)
        try archive.reviewFrame(id: original.id, review: label(frames[1], "Mail"))
        clip = try ObservationClipReview(acquisition: #require(archive.entry(id: original.id)))
        #expect(clip.rows.first?.resolution == .recognized)
        #expect(clip.traceReport?.distinctSampleMomentCount == 1)
        #expect(clip.traceReport?.visits.count == 1)
        #expect(clip.rows.first?.samples.count == 2)
    }
}
