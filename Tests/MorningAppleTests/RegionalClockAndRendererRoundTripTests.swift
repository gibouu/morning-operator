import Foundation
import MorningCore
import Testing
@testable import MorningApple

/// Invented screen content only; no media capture, model calls or personal data.
@Suite("Regional hours, letters beside the date, and what the renderer writes read back")
struct RegionalClockAndRendererRoundTripTests {
    private let task = "Calendar\n09:00 Team planning meeting"
    private let omissionNote = "[Some OCR text was omitted to stay within the import limit. Truncated frames cannot support app identification.]"

    private func video(_ text: String, truncated: Bool = false) throws -> ObservationVideoEvidence {
        try ObservationVideoEvidence(durationSeconds: 10, frames: [
            ObservationFrameEvidence(requestedTimeSeconds: 0, outcome: .observed,
                                     text: text, textWasTruncated: truncated)
        ])
    }

    private func utcDate(month: Int = 10, day: Int = 13, hour: Int = 9, minute: Int = 5) throws -> Date {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = try #require(TimeZone(identifier: "UTC"))
        return try #require(calendar.date(from: DateComponents(year: 2026, month: month,
                                                               day: day, hour: hour, minute: minute)))
    }

    @Test("Known limit: an hour written with a dot is the numeric date some regions print")
    func dottedHourCannotBeToldFromANumericDate() throws {
        // English with Finland prints the hour as "Tue 9.05"; French with Bulgaria prints the
        // home's date for 9 May as « sam., 9.05 ». Words alone cannot tell them apart, so a
        // line ending in the badge's capitals after either one is read as the home.
        var clock = Date.FormatStyle.dateTime.weekday(.abbreviated).hour().minute()
        clock.locale = Locale(identifier: "en_FI")
        clock.timeZone = try #require(TimeZone(identifier: "UTC"))
        #expect(try utcDate().formatted(clock) == "Tue 9.05")
        var date = Date.FormatStyle.dateTime.weekday(.abbreviated).month(.abbreviated).day()
        date.locale = Locale(identifier: "fr_BG")
        date.timeZone = clock.timeZone
        #expect(try utcDate(month: 5, day: 9).formatted(date) == "sam., 9.05")
        #expect(OwnInterfaceWording.identifies(.init("Recorder\nTue 9.05 MORE Recording\n09:00 Team planning meeting")))
        // With the colon most regions print, the hour is not a date.
        #expect(!OwnInterfaceWording.identifies(.init("Recorder\nTue 9:05 MORE Recording\n09:00 Team planning meeting")))
    }

    @Test func singleLetterTrackLabelsAreNotHomeSymbols() throws {
        // An external recorder can put a track/take letter between a date and
        // its MORE action/status columns. A and B are content, not a chevron.
        for row in ["Tue, Oct 13 A MORE Recording", "mar. 13 oct. B MORE Enregistrement"] {
            let screen = "Recorder\n\(row)\n09:00 Team planning meeting"
            let isOwn = OwnInterfaceWording.identifies(.init(screen))
            #expect(isOwn == false, "Track row: \(row)")
            #expect(throws: Never.self) {
                let units = try LearningEvidencePolicy.prepare(screen, as: .screenshot)
                #expect(units.map(\.text) == [screen])
            }
            #expect(throws: Never.self) {
                let units = try LearningEvidencePolicy.prepare(frames: [screen])
                #expect(units.map(\.text) == [screen])
            }
        }
    }

    @Test("A frame ending with the renderer's own closing note keeps it as frames; saved text drops that one line")
    func quotedOmissionNoticeRemainsFrameContent() throws {
        // A hand-built frame: an empty line, then the note. Held as frames or as a screenshot
        // it is whole. Saved text cannot tell the quoted note from the renderer's, and leaves
        // out a line that describes no activity.
        let prefix = "Notes\nPlease bring the printed meeting notes tomorrow."
        let source = prefix + "\n\n" + omissionNote
        let evidence = try video(source)
        #expect(evidence.frames.allSatisfy { !$0.textWasTruncated })
        #expect(try LearningEvidencePolicy.prepare(frames: [source]).map(\.text) == [source])
        #expect(try LearningEvidencePolicy.prepare(source, as: .screenshot).map(\.text) == [source])
        #expect(ObservationVideoEvidence.frameTexts(inRenderedText: evidence.renderedText) == [prefix])
        #expect(try LearningEvidencePolicy.prepare(evidence.renderedText, as: .recording).map(\.text) == [prefix])
        // When a real notice is appended, only that appended copy goes.
        let actuallyTruncated = try video(source, truncated: true)
        #expect(ObservationVideoEvidence.frameTexts(inRenderedText: actuallyTruncated.renderedText) == [source])
    }

    @Test func explicitClockSeparatorsWithSpacingRemainExternal() throws {
        let rows = ["Tue 9 : 05 MORE Recording", "9\u{202F}:\u{202F}05 Tue MORE Recording",
                    "mar. 9 h 05 MORE Enregistrement", "9 H 05 mar. MORE Enregistrement"]
        for row in rows {
            let screen = "Recorder\n\(row)\n09:00 Team planning meeting"
            #expect(!OwnInterfaceWording.identifies(.init(screen)), "Clock row: \(row)")
            #expect(try LearningEvidencePolicy.prepare(screen, as: .screenshot).map(\.text) == [screen])
            #expect(try LearningEvidencePolicy.prepare(video(screen).renderedText, as: .recording).map(\.text) == [screen])
        }
    }

    @Test func generatedHomeDatesAndAdjacentExternalFramesStaySeparate() throws {
        for locale in ["en_FI", "en_DK", "en_HU", "fr_CA", "fr_MA", "fr_CH"] {
            var style = Date.FormatStyle.dateTime.weekday(.abbreviated).month(.abbreviated).day()
            style.locale = Locale(identifier: locale)
            style.timeZone = try #require(TimeZone(identifier: "UTC"))
            let printed = try utcDate().formatted(style)
            let badge = locale.hasPrefix("fr") ? "MORE · Enregistrement" : "MORE · Recording"
            let home = "09:41\n\(printed) \(badge)\nNow\n09:00 Team planning meeting\nPause"
            let external = "Recorder\nTue 09:05 MORE Recording\nPlease bring the printed meeting notes tomorrow."
            #expect(OwnInterfaceWording.identifies(.init(home)), "Home date: \(locale): \(printed)")
            let evidence = try ObservationVideoEvidence(durationSeconds: 10, frames: [
                ObservationFrameEvidence(requestedTimeSeconds: 0, outcome: .observed, text: home),
                ObservationFrameEvidence(requestedTimeSeconds: 5, outcome: .observed, text: external)
            ])
            #expect(try LearningEvidencePolicy.prepare(frames: evidence.frames.map(\.text)).map(\.text) == [external])
            #expect(try LearningEvidencePolicy.prepare(evidence.renderedText, as: .recording).map(\.text) == [external])
        }
    }

    @Test func rendererBoundaryTimesRoundTripIncludingActualNegativeZero() throws {
        let times: [Double] = [-Double.zero, .leastNonzeroMagnitude, 0.05, 59.95.nextDown,
                               59.95.nextUp, 60, 119.999, 1859.999, 1860]
        for time in times {
            // Actual presentation time can differ from requested sampling time.
            let frame = try ObservationFrameEvidence(requestedTimeSeconds: 0, actualTimeSeconds: time,
                                                      outcome: .observed, text: task)
            let evidence = try ObservationVideoEvidence(durationSeconds: 1860, frames: [frame])
            #expect(ObservationVideoEvidence.frameTexts(inRenderedText: evidence.renderedText) == [task],
                    "Renderer output: \(evidence.renderedText)")
            #expect(try LearningEvidencePolicy.prepare(evidence.renderedText, as: .recording).map(\.text) == [task])
            let restored = try JSONDecoder().decode(ObservationVideoEvidence.self, from: JSONEncoder().encode(evidence))
            #expect(ObservationVideoEvidence.frameTexts(inRenderedText: restored.renderedText) == [task])
        }
    }

    @Test func impossibleNegativeZeroVariantsCannotDetachOwnContext() throws {
        for time in ["01:-0.0", "00:-0.1", "000:-0.0", "00:+0.0", "00:00.00", "099:00.0"] {
            let source = "Sampled moment\n\n[Observed frame at \(time)]\n\(task)\nDone"
            let evidence = try video(source)
            #expect(ObservationVideoEvidence.frameTexts(inRenderedText: evidence.renderedText) == [source],
                    "Not a renderer timestamp: \(time)")
            #expect(throws: AppleIntelligenceError.insufficientActivityEvidence) {
                try LearningEvidencePolicy.prepare(evidence.renderedText, as: .recording)
            }
        }
    }

    @Test func rendererPreservesContentLineEndingsAndAdjacentMarkerLines() throws {
        let sources = ["\n" + task + "\n\n",
                       "Messages\r\nPlease bring the printed meeting notes tomorrow.\r",
                       "[Observed frame at 00:05.0]\n" + task]
        let frames = try sources.enumerated().map { index, text in
            try ObservationFrameEvidence(requestedTimeSeconds: Double(index), outcome: .observed, text: text)
        }
        let evidence = try ObservationVideoEvidence(durationSeconds: 10, frames: frames)
        let parsed = ObservationVideoEvidence.frameTexts(inRenderedText: evidence.renderedText)
        #expect(parsed.map { Data($0.utf8) } == sources.map { Data($0.utf8) })
        #expect(try LearningEvidencePolicy.prepare(evidence.renderedText, as: .recording).map(\.text) == sources)
    }
}
