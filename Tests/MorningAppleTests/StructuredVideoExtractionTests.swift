import Foundation
import MorningCore
import Testing
@testable import MorningApple

@Suite("Single-pass video evidence assembly")
struct StructuredVideoExtractionTests {
    @Test func productionAssemblerRetainsOneResultPerRequestBeforeAnyDisplayDeduplication() throws {
        var builder = try VideoObservationBuilder(durationSeconds: 8)
        let ids = (0..<5).map { _ in UUID() }
        try builder.append(id: ids[0], requestedTimeSeconds: 0, actualTimeSeconds: 0, outcome: .observed, text: "Demo Inbox")
        try builder.append(id: ids[1], requestedTimeSeconds: 1, actualTimeSeconds: 1, outcome: .observed, text: "Demo Inbox")
        try builder.append(id: ids[2], requestedTimeSeconds: 2, actualTimeSeconds: nil, outcome: .decodeFailed)
        try builder.append(id: ids[3], requestedTimeSeconds: 3, actualTimeSeconds: 3, outcome: .ocrFailed)
        try builder.append(id: ids[4], requestedTimeSeconds: 4, actualTimeSeconds: 4, outcome: .blank)
        let result = try builder.finish()
        #expect(result.frames.map(\.id) == ids)
        #expect(result.frames.map(\.requestedTimeSeconds) == [0, 1, 2, 3, 4])
        #expect(result.frames.map(\.outcome) == [.observed, .observed, .decodeFailed, .ocrFailed, .blank])
        #expect(result.frames.count == 5)
        #expect(result.renderedText.components(separatedBy: "[Observed frame at ").count - 1 == 1)
        #expect(result.decodedFrameCount == 4)
        #expect(result.warnings.contains { $0.contains("2 of 5") })
    }

    @Test func textBudgetTruncationIsExplicitAndLaterRequestsAreStillRepresented() throws {
        var builder = try VideoObservationBuilder(durationSeconds: 10)
        try builder.append(id: UUID(), requestedTimeSeconds: 0, actualTimeSeconds: 0, outcome: .observed,
                           text: String(repeating: "x", count: ObservationVideoEvidence.maximumOCRCharacters + 1))
        try builder.append(id: UUID(), requestedTimeSeconds: 1, actualTimeSeconds: 1, outcome: .observed, text: "Later synthetic content")
        try builder.append(id: UUID(), requestedTimeSeconds: 2, actualTimeSeconds: nil, outcome: .decodeFailed)
        let result = try builder.finish()
        #expect(result.frames.count == 3)
        #expect(result.frames[0].text.count == ObservationVideoEvidence.maximumOCRCharacters)
        #expect(result.frames[0].textWasTruncated)
        #expect(result.frames[1].text.isEmpty && result.frames[1].textWasTruncated)
        #expect(result.frames[1].outcome == .observed, "Omitted OCR must not falsely label a screen blank.")
        #expect(result.frames[2].outcome == .decodeFailed)
        #expect(result.frames.allSatisfy { !$0.canSupportIdentity })
        #expect(result.renderedText.count <= ObservationVideoEvidence.maximumRenderedCharacters)
    }

    @Test func UTF8BudgetKeepsWholeCharactersAndInvalidActualTimesBecomeExplicitFallbacks() throws {
        var builder = try VideoObservationBuilder(durationSeconds: 10)
        let family = "👨‍👩‍👧‍👦"
        try builder.append(id: UUID(), requestedTimeSeconds: 0, actualTimeSeconds: .nan,
                           outcome: .observed, text: String(repeating: family, count: 20_000))
        let result = try builder.finish()
        let source = try #require(result.frames.first)
        #expect(source.textWasTruncated)
        #expect(source.text.utf8.count <= ObservationVideoEvidence.maximumOCRBytes)
        #expect(source.text.allSatisfy { String($0) == family })
        #expect(source.actualTimeSeconds == nil)
        #expect(source.timeBasis == .requestedSamplingTime)
        #expect(source.timeSeconds == 0)
        #expect(source.warnings.contains { $0.contains("fallback") })
    }

    @Test func frameCapRejectsAnExtraRequestWithoutDiscardingTheAcceptedTrace() throws {
        var builder = try VideoObservationBuilder(durationSeconds: 100)
        for index in 0..<ObservationVideoEvidence.maximumFrames {
            try builder.append(id: UUID(), requestedTimeSeconds: Double(index), actualTimeSeconds: Double(index), outcome: .blank)
        }
        #expect(throws: ObservationVideoEvidenceError.evidenceTooLarge) {
            try builder.append(id: UUID(), requestedTimeSeconds: 24, actualTimeSeconds: 24, outcome: .blank)
        }
        #expect(try builder.finish().frames.count == 24)
        #expect(try !builder.finish().hasRecognizedText)
    }

    @Test("Character-budget clipping retains only complete original layout spans")
    func characterBudgetPreservesWholeLineEvidence() throws {
        var builder = try VideoObservationBuilder(durationSeconds: 4)
        try builder.append(id: UUID(), requestedTimeSeconds: 0, actualTimeSeconds: 0, outcome: .observed,
                           text: String(repeating: "x", count: ObservationVideoEvidence.maximumOCRCharacters - 15))
        let header = try line("Cedar Mail", start: 0)
        let partial = try line("Lumen Calendar", start: 11)
        try builder.append(id: UUID(), requestedTimeSeconds: 1, actualTimeSeconds: 1, outcome: .observed,
                           text: "Cedar Mail\nLumen Calendar", ocrLines: [header, partial])
        try builder.append(id: UUID(), requestedTimeSeconds: 2, actualTimeSeconds: 2, outcome: .observed,
                           text: "Later", ocrLines: [try line("Later", start: 0)])
        let frames = try builder.finish().frames
        #expect(frames[0].ocrLines == nil, "Legacy callers must not gain invented layout metadata.")
        #expect(frames[1].text == "Cedar Mail\nLume")
        #expect(frames[1].ocrLines == [header], "Do not shorten or relocate a clipped region's source span.")
        #expect(frames[1].textWasTruncated && !frames[1].canSupportIdentity)
        #expect(frames[1].warnings.contains { $0.contains("layout regions were omitted") })
        #expect(frames[2].ocrLines == [] && frames[2].text.isEmpty)
        #expect(frames[2].outcome == .observed && frames[2].textWasTruncated)
    }

    @Test("UTF-8 clipping preserves graphemes and drops partial geometry without relabeling OCR failure")
    func byteBudgetPreservesWholeLineEvidence() throws {
        var builder = try VideoObservationBuilder(durationSeconds: 4)
        let family = "👨‍👩‍👧‍👦"
        let padding = String(repeating: family, count: 10_000)
        try builder.append(id: UUID(), requestedTimeSeconds: 0, actualTimeSeconds: 0, outcome: .observed, text: padding)
        let header = try line("Cedar Mail", start: 0)
        let body = String(repeating: family, count: 400)
        try builder.append(id: UUID(), requestedTimeSeconds: 1, actualTimeSeconds: 1, outcome: .observed,
                           text: "Cedar Mail\n" + body, ocrLines: [header, try line(body, start: 11)])
        try builder.append(id: UUID(), requestedTimeSeconds: 2, actualTimeSeconds: nil, outcome: .decodeFailed)
        let frames = try builder.finish().frames
        #expect(frames[1].textWasTruncated && frames[1].outcome == .observed)
        #expect(frames[1].text.hasPrefix("Cedar Mail\n"))
        #expect(frames[1].text.dropFirst(11).allSatisfy { String($0) == family })
        #expect(frames[1].ocrLines == [header])
        #expect(frames[0].text.utf8.count + frames[1].text.utf8.count <= ObservationVideoEvidence.maximumOCRBytes)
        #expect(frames[2].outcome == .decodeFailed && frames[2].ocrLines == nil)
    }

    @Test("The line cap omits metadata explicitly while preserving the complete flattened text")
    func layoutCapDoesNotDiscardText() throws {
        let labels = (0...ObservationFrameEvidence.maximumOCRLines).map { "Row \($0)" }
        var offset = 0
        let lines = try labels.map { text in
            defer { offset += text.count + 1 }
            return try line(text, start: offset)
        }
        var builder = try VideoObservationBuilder(durationSeconds: 1)
        try builder.append(id: UUID(), requestedTimeSeconds: 0, actualTimeSeconds: 0,
                           outcome: .observed, text: labels.joined(separator: "\n"), ocrLines: lines)
        let frame = try #require(builder.finish().frames.first)
        #expect(frame.text == labels.joined(separator: "\n") && !frame.textWasTruncated)
        #expect(frame.ocrLines == Array(lines.prefix(ObservationFrameEvidence.maximumOCRLines)))
        #expect(frame.warnings.contains { $0.contains("line limit; their text was preserved") })
    }

    private func line(_ text: String, start: Int) throws -> ObservationOCRLine {
        try ObservationOCRLine(text: text, startCharacterOffset: start, endCharacterOffset: start + text.count,
            bounds: ObservationNormalizedBounds(x: 0.1, y: 0.5, width: 0.6, height: 0.05), confidence: 0.9)
    }
}
