import Foundation
import MorningCore
import Testing
@testable import MorningApple

@Suite("Historical observation narration — deterministic sources")
struct ObservationNarrationComposerTests {
    private let date = Date(timeIntervalSince1970: 1_791_417_600) // A fixed synthetic source date.

    private func notes(_ text: String = "A quiet cup of tea.\nA little time to play.",
                       kind: ObservationAcquisitionSourceKind = .manual,
                       origin: ObservationAcquisitionOrigin = .human,
                       dated: Bool = true) throws -> ObservationAcquisition {
        try .init(importedAt: date.addingTimeInterval(1_000),
            observedDate: dated ? ObservationObservedDate(date: date, timeZoneIdentifier: "Europe/Paris", provenance: .userAssigned) : nil,
            origin: origin, sourceKind: kind, sourceLabel: "Synthetic test source", originalText: text)
    }

    private func video(truncated: Bool = false) throws -> ObservationAcquisition {
        let frames = try [
            ObservationFrameEvidence(requestedTimeSeconds: 0, actualTimeSeconds: 0, outcome: .observed,
                text: "Cedar Mail\nA synthetic visible line.", textWasTruncated: truncated),
            ObservationFrameEvidence(requestedTimeSeconds: 2, actualTimeSeconds: nil, outcome: .ocrFailed, text: "")
        ]
        let evidence = try ObservationVideoEvidence(durationSeconds: 3, frames: frames)
        return try .init(observedDate: ObservationObservedDate(date: date, timeZoneIdentifier: "UTC", provenance: .userAssigned),
            origin: .human, sourceKind: .video, sourceLabel: "Synthetic test recording", originalText: evidence.renderedText,
            videoEvidence: evidence)
    }

    @Test func exactDatedPreviewResolvesIdenticallyAfterArchiveReload() throws {
        let source = try notes("  Cafe\u{0301} and tea.  ")
        let candidate = try #require(ObservationNarrationComposer.candidates(for: source).first)
        let prepared = try ObservationNarrationComposer.prepare(acquisition: source, candidate: candidate)
        #expect(prepared.reference.quote.utf8.elementsEqual(candidate.text.utf8))
        #expect(prepared.spokenText.hasPrefix("In your saved note from "))
        #expect(prepared.spokenText.hasSuffix("\n  Cafe\u{0301} and tea.  "))
        #expect(prepared.sourceDateLabel.contains("2026") && prepared.sourceDateLabel.contains("Europe/Paris"))
        #expect(!prepared.spokenText.contains("today") && !prepared.spokenText.contains("live"))
        let archive = try ObservationArchive(entries: [source])
        let reloaded = try JSONDecoder().decode(ObservationArchive.self, from: JSONEncoder().encode(archive))
        let resolved = try ObservationNarrationComposer.resolve(reference: prepared.reference, archive: reloaded)
        #expect(resolved == prepared)
    }

    @Test func wholeLinesAreBoundedNeverTruncatedAndNoMoreThan24AreOffered() throws {
        let source = try notes(String(repeating: "a", count: 501) + "\n\n" + (0..<30).map { "Line \($0)" }.joined(separator: "\n"))
        let candidates = ObservationNarrationComposer.candidates(for: source)
        #expect(candidates.count == 24)
        #expect(candidates.first?.text == "Line 0" && candidates.last?.text == "Line 23")
        #expect(candidates.allSatisfy { !$0.text.hasPrefix("aaa") })
        #expect(Set(candidates.map(\.id)).count == candidates.count)
        let empty = try notes(String(repeating: "b", count: 501))
        #expect(ObservationNarrationComposer.candidates(for: empty).isEmpty)
    }

    @Test func videoQuotesUseObservedFramesAndCorrectionsBecomeReviewedNotes() throws {
        let source = try video()
        let candidates = ObservationNarrationComposer.candidates(for: source)
        #expect(candidates.count == 2)
        #expect(candidates.allSatisfy { $0.frameID == source.videoEvidence?.frames[0].id })
        let prepared = try ObservationNarrationComposer.prepare(acquisition: source, candidate: candidates[0])
        #expect(prepared.spokenText.contains("saved screen text"))
        #expect(!prepared.spokenText.contains("opened") && !prepared.spokenText.contains("read your messages"))
        var archive = try ObservationArchive(entries: [source])
        try archive.correct(id: source.id, text: "I was planning tomorrow.")
        let corrected = try #require(archive.entry(id: source.id))
        let correctedCandidate = try #require(ObservationNarrationComposer.candidates(for: corrected).first)
        #expect(correctedCandidate.frameID == nil)
        let correctedPreview = try ObservationNarrationComposer.prepare(acquisition: corrected, candidate: correctedCandidate)
        #expect(correctedPreview.spokenText.contains("reviewed note"))
        #expect(correctedPreview.spokenText.hasSuffix("I was planning tomorrow."))
        #expect(ObservationNarrationComposer.candidates(for: try video(truncated: true)).isEmpty)
    }

    @Test func unknownUndatedAndAutomatedSourcesCannotCreateNarration() throws {
        for origin in [ObservationAcquisitionOrigin.unknown, .automated] {
            #expect(ObservationNarrationComposer.candidates(for: try notes(origin: origin)).isEmpty)
        }
        #expect(ObservationNarrationComposer.candidates(for: try notes(dated: false)).isEmpty)
        #expect(ObservationNarrationComposer.candidates(for: try notes(kind: .unknown)).isEmpty)
        let sample = try notes(origin: .synthetic)
        let preview = try ObservationNarrationComposer.prepare(acquisition: sample,
            candidate: #require(ObservationNarrationComposer.candidates(for: sample).first))
        #expect(preview.spokenText.hasPrefix("In this synthetic sample's saved note"))
    }

    @Test func correctionRedatingOriginChangesAndDeletionInvalidateExistingReference() throws {
        let source = try notes()
        let preview = try ObservationNarrationComposer.prepare(acquisition: source,
            candidate: #require(ObservationNarrationComposer.candidates(for: source).first))
        var archive = try ObservationArchive(entries: [source])
        try archive.correct(id: source.id, text: "A correction")
        #expect(throws: ObservationNarrationError.sourceChanged) { try ObservationNarrationComposer.resolve(reference: preview.reference, archive: archive) }
        archive = try .init(entries: [source])
        try archive.assignObservedDate(id: source.id, value: ObservationObservedDate(date: date.addingTimeInterval(86_400),
            timeZoneIdentifier: "UTC", provenance: .userAssigned))
        #expect(throws: ObservationNarrationError.sourceChanged) { try ObservationNarrationComposer.resolve(reference: preview.reference, archive: archive) }
        archive = try .init(entries: [source])
        try archive.assignObservedDate(id: source.id, value: source.observedDate, origin: .synthetic)
        #expect(throws: ObservationNarrationError.sourceChanged) { try ObservationNarrationComposer.resolve(reference: preview.reference, archive: archive) }
        try archive.delete(id: source.id)
        #expect(throws: ObservationNarrationError.sourceMissing) { try ObservationNarrationComposer.resolve(reference: preview.reference, archive: archive) }
    }

    @Test func forgedQuoteWrongFrameAndCanonicalUnicodeSubstituteCannotResolve() throws {
        let source = try notes("Caf\u{00E9}")
        let prepared = try ObservationNarrationComposer.prepare(acquisition: source,
            candidate: #require(ObservationNarrationComposer.candidates(for: source).first))
        let archive = try ObservationArchive(entries: [source])
        for quote in ["A different note", "Cafe\u{0301}"] {
            let forged = try RoutineObservationReference(acquisitionID: source.id,
                revisionSHA256: prepared.reference.revisionSHA256, quote: quote)
            #expect(throws: ObservationNarrationError.invalidExcerpt) { try ObservationNarrationComposer.resolve(reference: forged, archive: archive) }
        }
        let wrongFrame = try RoutineObservationReference(acquisitionID: source.id,
            revisionSHA256: prepared.reference.revisionSHA256, frameID: UUID(), quote: prepared.reference.quote)
        #expect(throws: ObservationNarrationError.invalidExcerpt) { try ObservationNarrationComposer.resolve(reference: wrongFrame, archive: archive) }
    }

    @Test func independentClassificationDoesNotChangeReviewedTextReference() throws {
        let source = try video()
        let prepared = try ObservationNarrationComposer.prepare(acquisition: source,
            candidate: #require(ObservationNarrationComposer.candidates(for: source).first))
        let frames = try #require(source.videoEvidence?.frames)
        let decisions = frames.map { ObservationFrameIdentityDecision(sampleID: $0.id, timeSeconds: $0.timeSeconds,
            timeBasis: $0.timeBasis, evidence: .unknown, reason: "Synthetic unavailable classification") }
        let result = ObservationContextClassification(decisions: decisions, status: .unavailable, attemptedBatchCount: 0,
            respondedBatchCount: 0, failedBatchCount: 0, diagnostics: [], modelAvailability: "Synthetic unavailable model")
        var archive = try ObservationArchive(entries: [source])
        try archive.classify(id: source.id, result: result)
        #expect(try ObservationNarrationComposer.resolve(reference: prepared.reference, archive: archive) == prepared)
    }
    @Test func sourceProvenanceTravelsWithReferenceAndForgedOriginCannotResolve() throws {
        for origin in [ObservationAcquisitionOrigin.human, .synthetic] {
            let source = try notes(origin: origin)
            let prepared = try ObservationNarrationComposer.prepare(acquisition: source,
                candidate: #require(ObservationNarrationComposer.candidates(for: source).first))
            #expect(prepared.reference.isSynthetic == (origin == .synthetic))
            let archive = try ObservationArchive(entries: [source])
            let restored = try JSONDecoder().decode(RoutineObservationReference.self, from: JSONEncoder().encode(prepared.reference))
            #expect(try ObservationNarrationComposer.resolve(reference: restored, archive: archive) == prepared)
            let step = RoutineStep(title: "A retained excerpt", automation: .savedObservation, observationReference: restored)
            #expect(RoutineVersion(sourceLabel: "An independently updated label", steps: [step]).isSynthetic == (origin == .synthetic))
            let forged = try RoutineObservationReference(acquisitionID: source.id,
                revisionSHA256: restored.revisionSHA256, frameID: restored.frameID, quote: restored.quote,
                isSynthetic: !restored.isSynthetic)
            #expect(throws: ObservationNarrationError.sourceChanged) {
                try ObservationNarrationComposer.resolve(reference: forged, archive: archive)
            }
        }
    }

    @Test func directSampleQuoteRequiresTheSameFrameAndWholeExactLine() throws {
        let frames = try [
            ObservationFrameEvidence(requestedTimeSeconds: 0, actualTimeSeconds: 0, outcome: .observed,
                text: "Cedar Mail\nA synthetic visible line."),
            ObservationFrameEvidence(requestedTimeSeconds: 1, actualTimeSeconds: 1, outcome: .observed,
                text: "Cedar Mail\nAnother synthetic line.")
        ]
        let evidence = try ObservationVideoEvidence(durationSeconds: 2, frames: frames)
        let source = try ObservationAcquisition(observedDate: notes().observedDate, origin: .human,
            sourceKind: .video, sourceLabel: "Synthetic direct-handoff test", originalText: evidence.renderedText,
            videoEvidence: evidence)
        let prepared = try ObservationNarrationComposer.prepare(acquisition: source, frameID: frames[1].id, quote: "Cedar Mail")
        #expect(prepared.reference.frameID == frames[1].id)
        #expect(prepared.reference.quote == "Cedar Mail")
        #expect(prepared.spokenText.hasSuffix("\nCedar Mail"))
        for (id, quote) in [(frames[1].id, "A synthetic visible line."), (frames[0].id, "synthetic visible"),
                            (UUID(), "Cedar Mail"), (frames[0].id, " Cedar Mail")] {
            #expect(throws: ObservationNarrationError.invalidExcerpt) {
                try ObservationNarrationComposer.prepare(acquisition: source, frameID: id, quote: quote)
            }
        }
    }

    @Test func directHandoffCannotReplaceUnavailableOrCorrectedSourceWithAnotherLine() throws {
        let source = try video()
        let frame = try #require(source.videoEvidence?.frames.first)
        let archive = try ObservationArchive(entries: [source])
        let prepared = try ObservationNarrationComposer.prepare(acquisition: source, frameID: frame.id, quote: "Cedar Mail")
        #expect(try ObservationNarrationComposer.resolve(reference: prepared.reference, archive: archive) == prepared)
        var changed = archive
        try changed.correct(id: source.id, text: "Cedar Mail")
        let corrected = try #require(changed.entry(id: source.id))
        #expect(throws: ObservationNarrationError.invalidExcerpt) {
            try ObservationNarrationComposer.prepare(acquisition: corrected, frameID: frame.id, quote: "Cedar Mail")
        }
        #expect(throws: ObservationNarrationError.sourceChanged) {
            try ObservationNarrationComposer.resolve(reference: prepared.reference, archive: changed)
        }
        let truncated = try video(truncated: true)
        let truncatedFrame = try #require(truncated.videoEvidence?.frames.first)
        #expect(throws: ObservationNarrationError.invalidExcerpt) {
            try ObservationNarrationComposer.prepare(acquisition: truncated, frameID: truncatedFrame.id, quote: "Cedar Mail")
        }
        try changed.assignObservedDate(id: source.id, value: nil)
        let undated = try #require(changed.entry(id: source.id))
        #expect(throws: ObservationNarrationError.dateRequired) {
            try ObservationNarrationComposer.prepare(acquisition: undated, frameID: frame.id, quote: "Cedar Mail")
        }
        try changed.assignObservedDate(id: source.id, value: source.observedDate, origin: .unknown)
        let unknown = try #require(changed.entry(id: source.id))
        #expect(throws: ObservationNarrationError.originNotEligible) {
            try ObservationNarrationComposer.prepare(acquisition: unknown, frameID: frame.id, quote: "Cedar Mail")
        }
    }

}
