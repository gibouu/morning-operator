import Foundation
import MorningCore
import Testing
@testable import MorningApple

/// Invented inputs only: no screen is captured and no model is called.
@Suite("Stated kinds, saved frame boundaries and home dates, through archive reloads")
struct EvidenceFramingArchiveTests {
    private let marker = "[Observed frame at 00:10.0]"
    private let calendar = "Calendar\n09:00 Team planning meeting"

    private func acquisition(_ text: String, kind: ObservationAcquisitionSourceKind,
                             video: ObservationVideoEvidence? = nil) throws -> ObservationAcquisition {
        try ObservationAcquisition(
            observedDate: .init(date: Date(timeIntervalSince1970: 1_791_158_400),
                                timeZoneIdentifier: "UTC", provenance: .userAssigned),
            origin: .synthetic, sourceKind: kind, sourceLabel: "Invented framing fixture",
            originalText: text, videoEvidence: video)
    }

    private func reload(_ entry: ObservationAcquisition) throws -> ObservationAcquisition {
        let archive = try ObservationArchive(entries: [entry])
        let restored = try JSONDecoder().decode(ObservationArchive.self, from: JSONEncoder().encode(archive))
        return try #require(restored.entries.first)
    }

    @Test func impossibleRendererTimestampsCannotForgeRecordingBoundaries() {
        // Neither timestamp can be printed by %02d:%04.1f for a nonnegative time.
        // 00:60.0 is deliberately NOT here: rounding 59.96 really prints that value.
        for timestamp in ["00:99.9", "000:10.0"] {
            let body = "Sampled moment\n\n[Observed frame at \(timestamp)]\n\(calendar)\nDone"
            let saved = "[Observed frame at 00:00.0]\n" + body
            #expect(ObservationVideoEvidence.frameTexts(inRenderedText: saved) == [body],
                    "Impossible timestamp must stay content: \(timestamp)")
            #expect(throws: AppleIntelligenceError.insufficientActivityEvidence) {
                try LearningEvidencePolicy.prepare(saved, as: .recording)
            }
        }
    }

    @Test func nonemptyAndNonLFSeparatorsCannotForgeRecordingBoundaries() {
        for separator in ["\n", "\r\r", "\r\n\r\n", "\u{2028}\u{2028}", "\n \n", "\n\t\n"] {
            let body = "Sampled moment" + separator + marker + "\n" + calendar + "\nDone"
            let saved = "[Observed frame at 00:00.0]\n" + body
            #expect(ObservationVideoEvidence.frameTexts(inRenderedText: saved) == [body])
            #expect(throws: AppleIntelligenceError.insufficientActivityEvidence) {
                try LearningEvidencePolicy.prepare(saved, as: .recording)
            }
        }
    }

    @Test func screenshotsRemainWholeAcrossHeaderAndArchiveRoundTrips() throws {
        let screens = [
            "Sampled moment\n\n\(marker)\n\(calendar)\nDone",
            "\(marker)\n\(calendar)\nSampled moment\nDone",
            "Sampled moment\n\n[Observed frame at 00:99.9]\n\(calendar)\nDone"
        ]
        for screen in screens {
            for text in [screen, LearningEvidencePolicy.screenshotHeader + screen] {
                #expect(throws: AppleIntelligenceError.insufficientActivityEvidence) {
                    try LearningEvidencePolicy.prepare(text, as: .screenshot)
                }
                let restored = try reload(acquisition(text, kind: .image))
                #expect(Data(restored.originalText.utf8) == Data(text.utf8))
                #expect(throws: RoutineEvidenceProposalError.insufficientEvidence) {
                    try LearningEvidencePreparation.prepare(acquisitions: [restored])
                }
            }
        }
    }

    @Test func structuredArchiveRetainsWholeFramesDespiteSavedTextAmbiguity() throws {
        let ownSheet = "Sampled moment\n\n\(marker)\n\(calendar)\nDone"
        let external = "Messages\nPlease bring the printed meeting notes tomorrow."
        let frames = try [ownSheet, external].enumerated().map { index, text in
            try ObservationFrameEvidence(requestedTimeSeconds: Double(index) * 20,
                                         outcome: .observed, text: text)
        }
        let video = try ObservationVideoEvidence(durationSeconds: 40, frames: frames)
        let original = try acquisition(video.renderedText, kind: .video, video: video)
        let restored = try reload(original)
        #expect(restored.videoEvidence == video)
        #expect(Data(restored.originalText.utf8) == Data(original.originalText.utf8))
        for entry in [original, restored] {
            let prepared = try LearningEvidencePreparation.prepare(acquisitions: [entry])
            #expect(prepared.units.map(\.sampleID) == [frames[1].id])
            #expect(prepared.omissions.map(\.sampleID) == [frames[0].id])
            #expect(prepared.omissions.first?.reason == .unsupportedVisualContext)
        }
        #expect(try LearningEvidencePolicy.prepare(frames: frames.map(\.text)).map(\.text) == [external])
        // Characterize the disclosed limit honestly: only the text-only path leaks this fragment.
        #expect(ObservationVideoEvidence.frameTexts(inRenderedText: video.renderedText) == [
            "Sampled moment", calendar + "\nDone", external
        ])
        #expect(try LearningEvidencePolicy.prepare(video.renderedText, as: .recording).map(\.text) == [
            calendar + "\nDone", external
        ])
    }

    @Test func oldRendererTextIncludingRoundedSecondsSurvivesArchiveReload() throws {
        let saved = """
        [Recording coverage: The recording was interrupted once.]

        [User-selected video: 01:10.0; 3 frames sampled. This is partial visual evidence, not a complete interaction log.]

        [Observed frame at 00:00.0]
        Sampled moment
        [Observed frame at 00:10.0]
        Calendar
        09:00 Team planning meeting
        Done

        [Observed frame at 00:60.0]
        Calendar
        10:30 Review project milestones

        [Some OCR text was omitted to stay within the import limit. Truncated frames cannot support app identification.]
        """
        let expected = ["Sampled moment\n\(marker)\n\(calendar)\nDone",
                        "Calendar\n10:30 Review project milestones"]
        let rounded = try ObservationFrameEvidence(requestedTimeSeconds: 59.96, outcome: .observed,
                                                   text: expected[1])
        let rendered = try ObservationVideoEvidence(durationSeconds: 70, frames: [rounded]).renderedText
        #expect(rendered.contains("[Observed frame at 00:60.0]"))
        let restored = try reload(acquisition(saved, kind: .video))
        for text in [saved, restored.originalText] {
            #expect(ObservationVideoEvidence.frameTexts(inRenderedText: text) == expected)
            #expect(try LearningEvidencePolicy.prepare(text, as: .recording).map(\.text) == [expected[1]])
        }
        // Legacy text without structured samples cannot silently become live structured evidence.
        #expect(throws: RoutineEvidenceProposalError.unsupportedSource) {
            try LearningEvidencePreparation.prepare(acquisitions: [restored])
        }
    }

    @Test func dateLookalikesWithAdditionalTokensRemainEligible() throws {
        for row in ["Save 1", "Tue, Apr 31", "mar. 31 avr.",
                    "Tue, Oct 13 A B C D", "Tue, Oct 13 0 0 0"] {
            let screen = "Recorder\n\(row) MORE Recording\n09:00 Team planning meeting"
            let isOwn = OwnInterfaceWording.identifies(.init(screen))
            #expect(isOwn == false, "Not a home date: \(row)")
            #expect(throws: Never.self) {
                try LearningEvidencePolicy.prepare(screen, as: .screenshot)
            }
        }
    }

    @Test func genuineRegionalHomeDatesStillExcludeOwnInterface() throws {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = try #require(TimeZone(identifier: "UTC"))
        let day = try #require(calendar.date(from: DateComponents(year: 2028, month: 1, day: 1)))
        for locale in ["en_US", "fr_FR", "en_CZ", "en_HU", "fr_MA"] {
            var style = Date.FormatStyle.dateTime.weekday(.abbreviated).month(.abbreviated).day()
            style.locale = Locale(identifier: locale)
            style.timeZone = calendar.timeZone
            let date = day.formatted(style)
            let badge = locale.hasPrefix("fr") ? "MORE · Enregistrement" : "MORE · Recording"
            let screen = "Recorder\n\(date) \(badge)\n09:00 Team planning meeting"
            #expect(OwnInterfaceWording.identifies(.init(screen)), "Unrecognized real home date (\(locale)): \(date)")
            #expect(throws: AppleIntelligenceError.insufficientActivityEvidence) {
                try LearningEvidencePolicy.prepare(screen, as: .screenshot)
            }
            let frame = try ObservationFrameEvidence(requestedTimeSeconds: 0, outcome: .observed, text: screen)
            let video = try ObservationVideoEvidence(durationSeconds: 10, frames: [frame])
            let restored = try reload(acquisition(video.renderedText, kind: .video, video: video))
            #expect(throws: RoutineEvidenceProposalError.insufficientEvidence) {
                try LearningEvidencePreparation.prepare(acquisitions: [restored])
            }
        }
    }

    @Test func writtenMarkerReportsKeepBytesAndProvenanceAfterArchiveReload() throws {
        let report = "Every morning I review my calendar and quote \(marker) in my debugging notes.\n\n"
            + marker + "\nThen I read my mail before breakfast."
        let prepared = try LearningEvidencePolicy.prepare(report, as: .writtenReport)
        #expect(prepared.map(\.text) == [report])
        #expect(prepared.first?.kind == .userReportedActivity)
        for kind: ObservationAcquisitionSourceKind in [.manual, .text] {
            let restored = try reload(acquisition(report, kind: kind))
            let evidence = try LearningEvidencePreparation.prepare(acquisitions: [restored])
            #expect(evidence.units.allSatisfy { $0.kind == .userReportedActivity })
            #expect(Data(evidence.units.map(\.text).joined().utf8) == Data(report.utf8))
        }
    }
}
