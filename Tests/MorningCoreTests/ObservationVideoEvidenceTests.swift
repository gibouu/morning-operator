import Foundation
import Testing
@testable import MorningCore

@Suite("Structured video evidence and citations")
struct ObservationVideoEvidenceTests {
    private func frame(_ time: Double, _ text: String, actual: Double? = nil,
                       truncated: Bool = false) throws -> ObservationFrameEvidence {
        try .init(requestedTimeSeconds: time, actualTimeSeconds: actual ?? time,
                  outcome: .observed, text: text, textWasTruncated: truncated)
    }

    private func decision(_ frame: ObservationFrameEvidence, key: String = "visible.inbox",
                          quote: String? = nil) -> ObservationFrameIdentityDecision {
        .init(sampleID: frame.id, timeSeconds: frame.timeSeconds, timeBasis: frame.timeBasis,
              evidence: .identified(app: .init(key: key, displayName: key), reference: frame.evidenceReference),
              evidenceQuote: quote ?? frame.text)
    }

    @Test func structuredFramesSurviveNotesDeduplicationAndRoundTripWithTheSameIDs() throws {
        let a = "Demo Inbox\nAn entirely synthetic message subject"
        let b = "Demo Calendar\n09:00 A synthetic planning meeting"
        let frames = try [frame(0, a), frame(1, a), frame(2, b), frame(3, a)]
        let evidence = try ObservationVideoEvidence(durationSeconds: 4, frames: frames)
        #expect(evidence.frames.count == 4)
        #expect(evidence.renderedText.components(separatedBy: "[Observed frame at ").count - 1 == 3)
        let restored = try JSONDecoder().decode(ObservationVideoEvidence.self, from: JSONEncoder().encode(evidence))
        #expect(restored == evidence)
        #expect(restored.frames.map(\.id) == frames.map(\.id))
        let decisions = [decision(frames[0]), decision(frames[1]), decision(frames[2], key: "visible.calendar"), decision(frames[3])]
        let trace = try restored.makeTrace(decisions: decisions, origin: .synthetic)
        let report = try trace.report(maximumSampleGapSeconds: 2)
        #expect(trace.samples.map(\.id) == frames.map(\.id))
        #expect(report.visits.map(\.app.key) == ["visible.inbox", "visible.calendar", "visible.inbox"])
        #expect(report.capturedDurationSeconds == nil)
        #expect(report.appSummary(key: "visible.inbox")?.sampledVisibleSecondsEstimate == nil)
    }

    @Test func renderedTextReadsBackAsTheFramesItWasWrittenFrom() throws {
        let a = "Demo Inbox\nAn entirely synthetic message subject"
        // A screen showing an earlier observation: a marker line inside the frame's own text.
        let b = "Demo Review\n[Observed frame at 00:00.0]\nDemo Inbox\n[Observed frame at 99:59.9]"
        let c = "[Observed frame at 00:02.0]\nDemo Calendar\r\n09:00 A synthetic planning meeting\u{2028}Next"
        // Repeats, a blank and a failed sample, times out of order, a truncated last frame.
        let frames = try [frame(0, a, actual: 3), frame(1, a), frame(2, b, actual: 0.5),
            ObservationFrameEvidence(requestedTimeSeconds: 3, outcome: .blank),
            frame(4, b), ObservationFrameEvidence(requestedTimeSeconds: 5, outcome: .decodeFailed),
            frame(6, c), frame(7, a, truncated: true)]
        let evidence = try ObservationVideoEvidence(durationSeconds: 8, frames: frames)
        #expect(ObservationVideoEvidence.frameTexts(inRenderedText: evidence.renderedText) == [a, b, b, c, a])
        // The note MorningStore puts above an interrupted recording changes nothing.
        let noted = "[Recording coverage: interrupted once]\n\n" + evidence.renderedText
        #expect(ObservationVideoEvidence.frameTexts(inRenderedText: noted) == [a, b, b, c, a])
        #expect(ObservationVideoEvidence.frameTexts(inRenderedText: "No frames here.\n[Observed frame at 00:00.0]").isEmpty)
        #expect(ObservationVideoEvidence.frameTexts(inRenderedText: "").isEmpty)
    }

    @Test func everyRequestedFailureAndBlankHasARecordAndMissingDecisionsRemainUnknown() throws {
        let frames = try [frame(0, "Synthetic inbox content"),
            ObservationFrameEvidence(requestedTimeSeconds: 1, actualTimeSeconds: 1, outcome: .blank),
            ObservationFrameEvidence(requestedTimeSeconds: 2, outcome: .decodeFailed),
            ObservationFrameEvidence(requestedTimeSeconds: 3, actualTimeSeconds: 3, outcome: .ocrFailed)]
        let evidence = try ObservationVideoEvidence(durationSeconds: 4, frames: frames)
        #expect(evidence.decodedFrameCount == 3)
        let trace = try evidence.makeTrace(decisions: [decision(frames[0])])
        #expect(trace.origin == .unknown)
        #expect(trace.samples.count == 4)
        #expect(trace.samples.map(\.outcome) == [.observed, .blank, .decodeFailed, .ocrFailed])
        #expect(trace.samples[2].timeBasis == .requestedSamplingTime)
        #expect(trace.samples[2].timeSeconds == 2)
        #expect(trace.samples.dropFirst().allSatisfy { $0.appEvidence == .unknown })
    }

    @Test func duplicateUnknownDecisionsAndForeignSampleIDsAreRejected() throws {
        let source = try frame(0, "Demo Inbox synthetic message")
        let evidence = try ObservationVideoEvidence(durationSeconds: 1, frames: [source])
        let unknown = ObservationFrameIdentityDecision(sampleID: source.id, timeSeconds: 0,
                                                       timeBasis: .mediaPresentation, evidence: .unknown)
        #expect(throws: ObservationVideoEvidenceError.duplicateDecision) {
            try evidence.makeTrace(decisions: [unknown, unknown])
        }
        let foreign = ObservationFrameIdentityDecision(sampleID: UUID(), timeSeconds: 0,
                                                       timeBasis: .mediaPresentation, evidence: .unknown)
        #expect(throws: ObservationVideoEvidenceError.unknownDecisionSample) { try evidence.makeTrace(decisions: [foreign]) }
    }

    @Test func quoteCannotBorrowAnotherFrameOrChangeItsReferenceOrTime() throws {
        let a = try frame(0, "Demo Inbox synthetic message")
        let b = try frame(1, "Demo Calendar synthetic appointment")
        let evidence = try ObservationVideoEvidence(durationSeconds: 2, frames: [a, b])
        #expect(throws: ObservationVideoEvidenceError.invalidCitation) { try evidence.makeTrace(decisions: [decision(a, quote: b.text)]) }
        let wrongReference = ObservationFrameIdentityDecision(sampleID: a.id, timeSeconds: a.timeSeconds, timeBasis: a.timeBasis,
            evidence: .identified(app: .init(key: "visible.inbox", displayName: "Inbox"), reference: b.evidenceReference), evidenceQuote: a.text)
        #expect(throws: ObservationVideoEvidenceError.invalidCitation) { try evidence.makeTrace(decisions: [wrongReference]) }
        let wrongTime = ObservationFrameIdentityDecision(sampleID: a.id, timeSeconds: 0.1, timeBasis: a.timeBasis, evidence: .unknown)
        #expect(throws: ObservationVideoEvidenceError.decisionTimeMismatch) { try evidence.makeTrace(decisions: [wrongTime]) }
        let wrongBasis = ObservationFrameIdentityDecision(sampleID: a.id, timeSeconds: 0, timeBasis: .requestedSamplingTime, evidence: .unknown)
        #expect(throws: ObservationVideoEvidenceError.decisionTimeMismatch) { try evidence.makeTrace(decisions: [wrongBasis]) }
    }

    @Test func visuallyEqualUnicodeQuoteMustRetainExactSourceBytes() throws {
        let originalQuote = "Caf\u{00E9}"
        let rewrittenQuote = "Cafe\u{0301}"
        #expect(originalQuote == rewrittenQuote)
        #expect(Array(originalQuote.utf8) != Array(rewrittenQuote.utf8))
        let source = try frame(0, "Synthetic appointment at " + originalQuote)
        let evidence = try ObservationVideoEvidence(durationSeconds: 1, frames: [source])
        #expect(throws: ObservationVideoEvidenceError.invalidCitation) {
            try evidence.makeTrace(decisions: [decision(source, quote: rewrittenQuote)])
        }
        let accepted = try evidence.makeTrace(decisions: [decision(source, quote: originalQuote)], origin: .synthetic)
        #expect(accepted.samples.map(\.id) == [source.id])
        let report = try accepted.report(maximumSampleGapSeconds: 2)
        #expect(report.visits.count == 1)
        #expect(report.visits.first?.app.key == "visible.inbox")
    }

    @Test func truncatedOCRCannotSupportIdentityEvenWithAnExactVisibleQuote() throws {
        let source = try frame(0, "Demo Inbox", truncated: true)
        let evidence = try ObservationVideoEvidence(durationSeconds: 1, frames: [source])
        #expect(evidence.hasRecognizedText)
        #expect(!source.canSupportIdentity)
        #expect(evidence.renderedText.contains("Some OCR text was omitted"))
        #expect(throws: ObservationVideoEvidenceError.invalidCitation) { try evidence.makeTrace(decisions: [decision(source)]) }
        #expect(try evidence.makeTrace().samples.first?.appEvidence == .unknown)
    }

    @Test func coverageIsDeclaredSeparatelyAndNeverInferredFromTheMovieDuration() throws {
        let frames = try [frame(0, "Demo Inbox"), frame(1, "Demo Inbox")]
        let evidence = try ObservationVideoEvidence(durationSeconds: 2, frames: frames)
        let decisions = frames.map { decision($0) }
        let unknown = try evidence.makeTrace(decisions: decisions).report(maximumSampleGapSeconds: 2)
        #expect(unknown.observationDurationSeconds == 2)
        #expect(!unknown.captureIsComplete)
        #expect(unknown.capturedDurationSeconds == nil)
        let declared = try evidence.makeTrace(decisions: decisions, origin: .synthetic,
            capturedIntervals: [.init(startSeconds: 0, endSeconds: 2)]).report(maximumSampleGapSeconds: 2)
        #expect(declared.captureIsComplete)
        #expect(declared.appSummary(key: "visible.inbox")?.sampledVisibleSecondsEstimate == 1)
        #expect(declared.unassignedCapturedSeconds == 1)
    }

    @Test func boundedValidationAlsoRunsWhenEvidenceIsDecoded() throws {
        let source = try frame(0, "Synthetic calendar text")
        #expect(throws: ObservationVideoEvidenceError.duplicateSample) {
            try ObservationVideoEvidence(durationSeconds: 2, frames: [source, source])
        }
        let later = try frame(1, "Later frame")
        #expect(throws: ObservationVideoEvidenceError.invalidFrameOrder) {
            try ObservationVideoEvidence(durationSeconds: 2, frames: [later, source])
        }
        #expect(throws: ObservationVideoEvidenceError.invalidFrame) {
            try ObservationFrameEvidence(requestedTimeSeconds: 0, outcome: .blank, text: "Not blank")
        }
        let evidence = try ObservationVideoEvidence(durationSeconds: 1, frames: [source])
        let json = try JSONSerialization.jsonObject(with: JSONEncoder().encode(evidence))
        var object = try #require(json as? [String: Any])
        object["durationSeconds"] = 2_000
        let corrupt = try JSONSerialization.data(withJSONObject: object)
        #expect(throws: ObservationVideoEvidenceError.invalidDuration) { try JSONDecoder().decode(ObservationVideoEvidence.self, from: corrupt) }
    }

    @Test func allBlankExtractionIsDiagnosticEvidenceRatherThanFabricatedReadableText() throws {
        let frame = try ObservationFrameEvidence(requestedTimeSeconds: 0, actualTimeSeconds: 0, outcome: .blank)
        let evidence = try ObservationVideoEvidence(durationSeconds: 1, frames: [frame])
        #expect(!evidence.hasRecognizedText)
        #expect(evidence.renderedText.contains("partial visual evidence"))
        let report = try evidence.makeTrace().report(maximumSampleGapSeconds: 2)
        #expect(report.unidentifiedMomentCount == 1)
        #expect(report.apps.isEmpty)
    }
}
