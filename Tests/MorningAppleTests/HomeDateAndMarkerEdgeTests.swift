import Foundation
import MorningCore
import Testing
@testable import MorningApple

/// Synthetic fixtures only; no captured content or model calls.
@Suite("Home dates beside hours and extra words, and saved markers with times at their limits")
struct HomeDateAndMarkerEdgeTests {
    private let calendarText = "Calendar\n09:00 Team planning meeting"

    private func recorderScreen(_ row: String) -> String {
        "Recorder\n\(row)\n09:00 Team planning meeting"
    }

    @Test func weekdayFirstClockTimesAreNotHomeDates() {
        // A recorder's weekday and start time are not the home's month/day date.
        // The colon is present, not a hypothetical OCR omission.
        for row in ["Tue 09:30 MORE Recording", "mar. 09:30 MORE Enregistrement"] {
            let screen = recorderScreen(row)
            let isOwn = OwnInterfaceWording.identifies(.init(screen))
            #expect(isOwn == false, "Clock row: \(row)")
            #expect(throws: Never.self, "External recording remains eligible: \(row)") {
                let units = try LearningEvidencePolicy.prepare(screen, as: .screenshot)
                #expect(units.map(\.text) == [screen])
            }
        }
    }

    @Test func weekdayLastClockTimesAreNotHomeDates() {
        // Plausible time-first rows in a recording list, in both app languages.
        for row in ["09:30 Tue MORE Recording", "09:30 mar. MORE Enregistrement"] {
            let screen = recorderScreen(row)
            let isOwn = OwnInterfaceWording.identifies(.init(screen))
            #expect(isOwn == false, "Clock row: \(row)")
            #expect(throws: Never.self, "External recording remains eligible: \(row)") {
                let units = try LearningEvidencePolicy.prepare(frames: [screen])
                #expect(units.map(\.text) == [screen])
            }
        }
    }

    @Test func extraRecordingMetadataCannotBeStrippedAsSymbols() throws {
        for row in [
            "Tue, Oct 13 A B MORE Recording",
            "Tue, Oct 13 0 O 0 MORE Recording",
            "Oct 13, Tue v v MORE Recording",
            "mar. 13 oct. 0 v MORE Enregistrement",
            "mar. 13 oct. v 00 MORE Enregistrement",
            "Tue 09:30 AM MORE Recording",
            "09:30 PM Tue MORE Recording"
        ] {
            let screen = recorderScreen(row)
            #expect(!OwnInterfaceWording.identifies(.init(screen)), "Metadata row: \(row)")
            #expect(try LearningEvidencePolicy.prepare(screen, as: .screenshot).map(\.text) == [screen])
        }
    }

    @Test func additionalRegionalHomeDatesRemainRecognized() throws {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = try #require(TimeZone(identifier: "UTC"))
        let locales = ["en_DK", "en_SE", "en_KR", "en_JP", "en_CH", "en_ZA",
                       "fr_CA", "fr_CH", "fr_BE", "fr_DZ", "fr_TN", "fr_SN", "fr_KR", "fr_HU",
                       "en_GW", "fr_LT", "fr_BG", "fr_FI"]
        for locale in locales {
            var style = Date.FormatStyle.dateTime.weekday(.abbreviated).month(.abbreviated).day()
            style.locale = Locale(identifier: locale)
            style.timeZone = calendar.timeZone
            let badge = locale.hasPrefix("fr") ? "MORE · Enregistrement" : "MORE · Recording"
            // Vary months and days, including leap day and two-digit numeric dates.
            for (month, day) in [(2, 29), (6, 7), (7, 14), (8, 31), (9, 30), (10, 13)] {
                let date = try #require(calendar.date(from: DateComponents(year: 2028, month: month, day: day)))
                let printed = date.formatted(style)
                for suffix in ["", " v 0"] {
                    let screen = recorderScreen("\(printed)\(suffix) \(badge)")
                    #expect(OwnInterfaceWording.identifies(.init(screen)), "Real home date \(locale): \(printed)")
                    #expect(throws: AppleIntelligenceError.insufficientActivityEvidence) {
                        try LearningEvidencePolicy.prepare(screen, as: .screenshot)
                    }
                }
            }
        }
    }

    @Test func impossibleMinuteMagnitudeCannotForgeFrameBoundary() {
        // This exceeds even Int's range, independently of import-duration limits.
        // It therefore cannot be emitted by the renderer's Int/%02d conversion.
        let impossibleTime = "999999999999999999999999:00.0"
        #expect(Int(impossibleTime.split(separator: ":")[0]) == nil)
        let body = "Sampled moment\n\n[Observed frame at \(impossibleTime)]\n\(calendarText)\nDone"
        let saved = "[Observed frame at 00:00.0]\n" + body
        #expect(ObservationVideoEvidence.frameTexts(inRenderedText: saved) == [body])
        #expect(throws: AppleIntelligenceError.insufficientActivityEvidence) {
            try LearningEvidencePolicy.prepare(saved, as: .recording)
        }
    }

    @Test func decoratedAndUnicodeMarkersRemainFrameContent() {
        let markers = [
            "[Observed frame at 00:60.1]", "[Observed frame at 00:61.0]",
            "[Observed frame at +00:10.0]", "[Observed frame at 00:10,0]",
            "[Observed frame at ٠٠:١٠.٠]", "[Observed frame at ００:１０.０]",
            "[Observed frame at 00:10.0]\u{200B}", "\u{FEFF}[Observed frame at 00:10.0]",
            "[Observed frame at 00:10.0] ", "> [Observed frame at 00:10.0]",
            "[Observed frame at 00:10.0]\n[Observed frame at 00:20.0]"
        ]
        for marker in markers {
            // A valid marker followed directly by another valid marker is still
            // content here: the preceding line for the first one is nonempty.
            let separator = marker.contains("\n") ? "\n" : "\n\n"
            let body = "Sampled moment" + separator + marker + "\n" + calendarText + "\nDone"
            let saved = "[Observed frame at 00:00.0]\n" + body
            #expect(ObservationVideoEvidence.frameTexts(inRenderedText: saved) == [body], "Marker: \(marker)")
            #expect(throws: AppleIntelligenceError.insufficientActivityEvidence) {
                try LearningEvidencePolicy.prepare(saved, as: .recording)
            }
        }
    }

    @Test func legacyRendererTextPreservesRoundingLongTimesAndContent() throws {
        let text = """
        [Recording coverage: The recording was interrupted once.]

        [User-selected video: 121:00.0; 3 frames sampled. This is partial visual evidence, not a complete interaction log.]

        [Observed frame at 00:00.0]
        Calendar
        09:00 Team planning meeting

        [Observed frame at 09:60.0]
        Messages
        Please bring the printed meeting notes tomorrow.

        [Observed frame at 120:59.9]
        Calendar
        11:00 Review project milestones

        [Some OCR text was omitted to stay within the import limit. Truncated frames cannot support app identification.]
        """
        let expected = [calendarText, "Messages\nPlease bring the printed meeting notes tomorrow.",
                        "Calendar\n11:00 Review project milestones"]
        // The existing compatibility suite admits long saved timestamps even
        // though a new video import is bounded to 31 minutes.
        #expect(ObservationVideoEvidence.frameTexts(inRenderedText: text) == expected)
        #expect(try LearningEvidencePolicy.prepare(text, as: .recording).map(\.text) == expected)
        let roundTripped = try JSONDecoder().decode(String.self, from: JSONEncoder().encode(text))
        #expect(ObservationVideoEvidence.frameTexts(inRenderedText: roundTripped) == expected)

        let frame = try ObservationFrameEvidence(requestedTimeSeconds: 599.96,
                                                 outcome: .observed, text: calendarText)
        let rendered = try ObservationVideoEvidence(durationSeconds: 610, frames: [frame]).renderedText
        #expect(rendered.contains("[Observed frame at 09:60.0]"))
        #expect(ObservationVideoEvidence.frameTexts(inRenderedText: rendered) == [calendarText])
    }

    @Test func rendererProducedNegativeZeroTimestampStillParses() throws {
        // IEEE negative zero satisfies the constructor's finite/nonnegative
        // contract. Obtain the marker from the renderer itself, not a guess.
        let frame = try ObservationFrameEvidence(requestedTimeSeconds: -Double.zero,
                                                 outcome: .observed, text: calendarText)
        let video = try ObservationVideoEvidence(durationSeconds: 10, frames: [frame])
        let saved = video.renderedText
        #expect(saved.contains("[Observed frame at 00:-0.0]"))
        #expect(ObservationVideoEvidence.frameTexts(inRenderedText: saved) == [calendarText])
        #expect(throws: Never.self) {
            let units = try LearningEvidencePolicy.prepare(saved, as: .recording)
            #expect(units.map(\.text) == [calendarText])
        }
    }
}
