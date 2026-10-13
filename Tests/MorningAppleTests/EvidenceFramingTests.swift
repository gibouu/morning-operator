import Foundation
import MorningCore
import Testing
@testable import MorningApple

/// Invented text only: these fixtures are not captures of anybody's screen or notes.
@Suite("The kind of a text and its frame boundaries are stated, never read from what it says")
struct EvidenceFramingTests {
    private let marker = "[Observed frame at 00:10.0]"
    private let calendar = "Calendar\n09:00 Team planning meeting"
    /// MORE's sampled-moment sheet displaying an earlier frame, marker included.
    private var ownSheet: String { "Sampled moment\n\(marker)\n\(calendar)\nDone" }

    private func rejectsEverything(_ text: String, as kind: LearningEvidenceTextKind) {
        #expect(throws: AppleIntelligenceError.insufficientActivityEvidence) {
            try LearningEvidencePolicy.prepare(text, as: kind)
        }
    }

    // MARK: A screen that displays a marker is still one screen

    @Test("A frame marker displayed inside MORE's sampled-text sheet cannot split its screenshot")
    func screenshotContentCannotForgeAFrameBoundary() {
        #expect(!LearningEvidencePolicy.isEligibleVisualContext(ownSheet))
        rejectsEverything(LearningEvidencePolicy.screenshotHeader + ownSheet, as: .screenshot)
        rejectsEverything(ownSheet, as: .screenshot)
        // However the marker stands in the screenshot: first, after an empty line, twice.
        for screen in ["\(marker)\n\(calendar)\nSampled moment\nDone", "Sampled moment\nDone\n\n\(marker)\n\(calendar)",
                       "Sampled moment\n\(marker)\n\(calendar)\n\n\(marker)\n\(calendar)\nDone"] {
            #expect(!LearningEvidencePolicy.isEligibleVisualContext(screen))
            rejectsEverything(LearningEvidencePolicy.screenshotHeader + screen, as: .screenshot)
        }
    }

    @Test("The same sheet sampled in a recording stays one rejected frame, as frames and as saved text")
    func recordedFrameContentCannotForgeAFrameBoundary() throws {
        let frames = try [ownSheet, calendar + " tomorrow"].enumerated().map { index, text in
            try ObservationFrameEvidence(requestedTimeSeconds: Double(index) * 20, outcome: .observed, text: text)
        }
        let video = try ObservationVideoEvidence(durationSeconds: 60, frames: frames)
        // The frames themselves, as the app passes them.
        let entry = try ObservationAcquisition(observedDate: .init(date: Date(timeIntervalSince1970: 1_791_158_400),
            timeZoneIdentifier: "UTC", provenance: .userAssigned), origin: .synthetic, sourceKind: .video,
            sourceLabel: "Synthetic framing fixture", originalText: video.renderedText, videoEvidence: video)
        let prepared = try LearningEvidencePreparation.prepare(acquisitions: [entry])
        #expect(prepared.units.map(\.sampleID) == [frames[1].id])
        #expect(prepared.omissions.map(\.sampleID) == [frames[0].id])
        #expect(prepared.omissions.first?.reason == .unsupportedVisualContext)
        // The text saved for them, where only that is held.
        #expect(ObservationVideoEvidence.frameTexts(inRenderedText: video.renderedText) == frames.map(\.text))
        let units = try LearningEvidencePolicy.prepare(video.renderedText, as: .recording)
        #expect(units.map(\.text) == [frames[1].text])
        rejectsEverything("[Observed frame at 00:00.0]\n" + ownSheet, as: .recording)
    }

    @Test("Lines that only resemble a marker never begin a frame", arguments: [
        "[Observed frame at 00:10.0] Calendar", " [Observed frame at 00:10.0]", "[Observed frame at 00:10.0]\r",
        "[Observed frame at 0:10.0]", "[Observed frame at 00:10]", "[Observed frame at 00:1.0]",
        "[Observed frame at 00:10.00]", "[Observed frame at ten seconds]", "[observed frame at 00:10.0]",
        "[Observed frame at 00:10.0", "Observed frame at 00:10.0]", "[Observed frame at -0:10.0]"
    ])
    func lookAlikeLinesAreContent(line: String) throws {
        // After the empty line a real boundary needs, so only the line's own form decides.
        let saved = "[Observed frame at 00:00.0]\nSampled moment\n\n\(line)\n\(calendar)\nDone"
        #expect(ObservationVideoEvidence.frameTexts(inRenderedText: saved) == ["Sampled moment\n\n\(line)\n\(calendar)\nDone"])
        rejectsEverything(saved, as: .recording)
    }

    @Test("Known limit of saved text: an empty line directly above a marker line inside one frame reads as a boundary")
    func savedTextCannotTellAnEmptyLineAboveAMarkerFromABoundary() throws {
        // Text recognition never yields an empty line, so no screen produces this; a frame
        // built by hand can. Held as frames, it is one frame and is rejected whole.
        let handBuilt = "Sampled moment\n\n\(marker)\n\(calendar)\nDone"
        #expect(throws: AppleIntelligenceError.insufficientActivityEvidence) {
            try LearningEvidencePolicy.prepare(frames: [handBuilt])
        }
        #expect(ObservationVideoEvidence.frameTexts(inRenderedText: "[Observed frame at 00:00.0]\n" + handBuilt).count == 2)
    }

    // MARK: Written words are never frames

    @Test("Quoting a marker does not turn a written personal report into a recording", arguments: [
        "Every morning I review my calendar and write the literal marker [Observed frame at 00:10.0] in my debugging notes.",
        "[Observed frame at 00:10.0]\nEvery morning I review my calendar before breakfast.",
        "Every morning I review my calendar before breakfast.\n\n[Observed frame at 00:10.0]\nThen I read my mail.",
        "[User-selected screenshot; one moment, not a confirmed habit]\nEvery morning I review my calendar before breakfast.",
        "[User-selected video: 00:40.3; 3 frames sampled.]\nEvery morning I review my calendar before breakfast."
    ])
    func literalMarkerInWrittenReportPreservesTextAndProvenance(report: String) throws {
        #expect(LearningEvidencePolicy.isEligibleWrittenContext(report))
        let units = try LearningEvidencePolicy.prepare(report, as: .writtenReport)
        #expect(units.count == 1)
        #expect(units.first?.kind == .userReportedActivity)
        #expect(units.first?.text.utf8.elementsEqual(report.utf8) == true)
    }

    @Test("A written personal report through the saved-observation path keeps its marker as text")
    func writtenObservationWithAMarkerIsOneWrittenUnit() throws {
        let report = "Every morning I review my calendar.\n\n\(marker)\nThen I read my mail before breakfast."
        let entry = try ObservationAcquisition(observedDate: .init(date: Date(timeIntervalSince1970: 1_791_158_400),
            timeZoneIdentifier: "UTC", provenance: .userAssigned), origin: .synthetic, sourceKind: .manual,
            sourceLabel: "Synthetic framing fixture", originalText: report)
        let prepared = try LearningEvidencePreparation.prepare(acquisitions: [entry])
        #expect(prepared.units.allSatisfy { $0.kind == .userReportedActivity })
        #expect(prepared.units.map(\.text).joined().utf8.elementsEqual(report.utf8))
    }

    // MARK: Text saved before this rule still reads the same

    @Test("A recording saved in the current format, coverage note and omission note included, gives back its frames")
    func savedRecordingTextStillReads() throws {
        // Written out, not rendered here: this is what observations already on a phone hold.
        let saved = """
        [Recording coverage: The recording was interrupted once.]

        [User-selected video: 00:40.3; 4 frames sampled. This is partial visual evidence, not a complete interaction log.]

        [Observed frame at 00:00.0]
        Calendar
        Today
        09:00 Team planning meeting

        [Observed frame at 00:10.2]
        Learning your morning
        THE LAST SEVEN MORNINGS
        Find your rhythm.

        [Observed frame at 00:08.0]
        Messages
        Alex
        Please bring the printed meeting notes tomorrow.

        [Observed frame at 120:59.9]
        Calendar
        10:30 Review project milestones

        [Some OCR text was omitted to stay within the import limit. Truncated frames cannot support app identification.]
        """
        let frames = ObservationVideoEvidence.frameTexts(inRenderedText: saved)
        #expect(frames == [
            "Calendar\nToday\n09:00 Team planning meeting",
            "Learning your morning\nTHE LAST SEVEN MORNINGS\nFind your rhythm.",
            "Messages\nAlex\nPlease bring the printed meeting notes tomorrow.",
            "Calendar\n10:30 Review project milestones"
        ])
        let units = try LearningEvidencePolicy.prepare(saved, as: .recording)
        #expect(units.map(\.text) == [frames[0], frames[2], frames[3]])
        #expect(units.allSatisfy { $0.kind == .visibleTaskContent })
    }

    @Test("A saved screenshot is one frame with or without its header line")
    func savedScreenshotTextStillReads() throws {
        let saved = "[User-selected screenshot; one moment, not a confirmed habit]\n" + calendar
        for text in [saved, calendar] {
            let units = try LearningEvidencePolicy.prepare(text, as: .screenshot)
            #expect(units.map(\.text) == [calendar])
            #expect(units.first?.kind == .visibleTaskContent)
        }
    }
}
