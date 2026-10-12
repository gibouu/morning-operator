import Foundation
import Testing
@testable import MorningCore

@Suite("OCR line layout and exact source provenance")
struct ObservationOCRLineTests {
    private func bounds() throws -> ObservationNormalizedBounds {
        try .init(x: 0.1, y: 0.8, width: 0.7, height: 0.1)
    }

    private func line(_ text: String, at start: Int = 0, id: UUID = UUID()) throws -> ObservationOCRLine {
        try .init(id: id, text: text, startCharacterOffset: start,
                  endCharacterOffset: start + text.count, bounds: bounds(), confidence: 0.9)
    }

    private func frame(_ text: String, lines: [ObservationOCRLine]?, truncated: Bool = false) throws -> ObservationFrameEvidence {
        try .init(requestedTimeSeconds: 0, actualTimeSeconds: 0, outcome: .observed,
                  text: text, textWasTruncated: truncated, ocrLines: lines)
    }

    @Test func layoutAndLocalIDsSurviveRoundTripWithCharacterOffsets() throws {
        // The emoji and decomposed accent make Character, UTF-8 and UTF-16 counts differ.
        let first = "👨‍👩‍👧‍👦 Cafe\u{301}"
        let second = "Synthetic heading"
        let lines = try [line(first), line(second, at: first.count + 1)]
        let source = try frame(first + "\n" + second, lines: lines)
        let evidence = try ObservationVideoEvidence(durationSeconds: 1, frames: [source])
        let restored = try JSONDecoder().decode(ObservationVideoEvidence.self, from: JSONEncoder().encode(evidence))
        #expect(restored == evidence)
        #expect(restored.frames[0].ocrLines?.map(\.id) == lines.map(\.id))
        #expect(restored.frames[0].ocrLines?[1].startCharacterOffset == first.count + 1)
        #expect(restored.frames[0].ocrLines?[0].bounds.y == 0.8)
        #expect(restored.frames[0].ocrLines?[0].confidence == 0.9)
    }

    @Test func missingOrNullLegacyLayoutRemainsNilWhileEmptyMeansNoRetainedSpans() throws {
        let source = try frame("Synthetic heading", lines: [])
        let encoded = try JSONEncoder().encode(source)
        let json = try JSONSerialization.jsonObject(with: encoded)
        var object = try #require(json as? [String: Any])
        let explicitEmpty = try JSONDecoder().decode(ObservationFrameEvidence.self, from: encoded)
        #expect(explicitEmpty.ocrLines == [])
        object.removeValue(forKey: "ocrLines")
        let missing = try JSONDecoder().decode(ObservationFrameEvidence.self,
            from: JSONSerialization.data(withJSONObject: object))
        #expect(missing.ocrLines == nil)
        object["ocrLines"] = NSNull()
        let null = try JSONDecoder().decode(ObservationFrameEvidence.self,
            from: JSONSerialization.data(withJSONObject: object))
        #expect(null.ocrLines == nil)
        #expect(missing.text == source.text)
        #expect(null.canSupportIdentity == source.canSupportIdentity)
    }

    @Test func normalizedBoundsRejectNonfiniteEmptyAndOutsideImageCoordinates() throws {
        let invalid: [(Double, Double, Double, Double)] = [
            (-0.01, 0, 0.5, 0.5), (0, -0.01, 0.5, 0.5),
            (0, 0, 0, 0.5), (0, 0, 0.5, 0),
            (0, 0, -0.1, 0.5), (0.8, 0, 0.3, 0.5), (0, 0.8, 0.5, 0.3),
            (.nan, 0, 0.5, 0.5), (0, .infinity, 0.5, 0.5),
            (0, 0, .infinity, 0.5), (0, 0, 0.5, .nan)
        ]
        for value in invalid {
            #expect(throws: ObservationOCRLineError.invalidBounds) {
                try ObservationNormalizedBounds(x: value.0, y: value.1, width: value.2, height: value.3)
            }
        }
        let fullImage = try ObservationNormalizedBounds(x: 0, y: 0, width: 1, height: 1)
        #expect(fullImage.width == 1)
        #expect(fullImage.height == 1)
    }

    @Test func confidenceAndIntrinsicCharacterSpanMustBeValid() throws {
        let box = try bounds()
        for confidence in [Double.nan, .infinity, -0.01, 1.01] {
            #expect(throws: ObservationOCRLineError.invalidConfidence) {
                try ObservationOCRLine(text: "A", startCharacterOffset: 0, endCharacterOffset: 1,
                                       bounds: box, confidence: confidence)
            }
        }
        for confidence in [0.0, 1.0] {
            let accepted = try ObservationOCRLine(text: "A", startCharacterOffset: 0,
                endCharacterOffset: 1, bounds: box, confidence: confidence)
            #expect(accepted.confidence == confidence)
        }
        for span in [(-1, 0), (0, 0), (1, 0), (0, 2), (0, Int.max)] {
            #expect(throws: ObservationOCRLineError.invalidLine) {
                try ObservationOCRLine(text: "A", startCharacterOffset: span.0,
                    endCharacterOffset: span.1, bounds: box, confidence: 1)
            }
        }
        #expect(throws: ObservationOCRLineError.invalidLine) {
            try ObservationOCRLine(text: " ", startCharacterOffset: 0, endCharacterOffset: 1,
                                   bounds: box, confidence: 1)
        }
    }

    @Test func sourceValidationRejectsOverlapsDisorderDuplicateIDsAndBorrowedText() throws {
        let first = try line("AB")
        let second = try line("CD", at: 3)
        #expect(throws: ObservationVideoEvidenceError.invalidFrame) {
            try frame("AB\nCD", lines: [second, first])
        }
        let overlap = try line("B", at: 1)
        #expect(throws: ObservationVideoEvidenceError.invalidFrame) {
            try frame("AB\nCD", lines: [first, overlap])
        }
        let duplicateID = try line("CD", at: 3, id: first.id)
        #expect(throws: ObservationVideoEvidenceError.invalidFrame) {
            try frame("AB\nCD", lines: [first, duplicateID])
        }
        let borrowed = try line("XY", at: 3)
        #expect(throws: ObservationVideoEvidenceError.invalidFrame) {
            try frame("AB\nCD", lines: [first, borrowed])
        }
        let outside = try line("CD", at: 6)
        #expect(throws: ObservationVideoEvidenceError.invalidFrame) {
            try frame("AB\nCD", lines: [outside])
        }
        // Equal-looking, canonically equivalent text is not the exact source scalar sequence.
        let composed = "Caf\u{00E9}"
        let decomposed = "Cafe\u{0301}"
        #expect(composed == decomposed)
        let changedScalars = try line(decomposed)
        #expect(throws: ObservationVideoEvidenceError.invalidFrame) {
            try frame(composed, lines: [changedScalars])
        }
    }

    @Test func lineBudgetIsBoundedIndependentlyOfOCRCharacterBudget() throws {
        let count = ObservationFrameEvidence.maximumOCRLines
        let lines = try (0...count).map { try line("A", at: $0 * 2) }
        let text = Array(repeating: "A", count: count + 1).joined(separator: "\n")
        let bounded = try frame(text, lines: Array(lines.prefix(count)))
        #expect(bounded.ocrLines?.count == count)
        #expect(throws: ObservationVideoEvidenceError.invalidFrame) { try frame(text, lines: lines) }
        #expect(throws: ObservationVideoEvidenceError.invalidFrame) {
            try ObservationFrameEvidence(requestedTimeSeconds: 0, outcome: .blank, ocrLines: [lines[0]])
        }
    }

    @Test func truncatedSourceRejectsOriginalSpansBeyondRetainedText() throws {
        let heading = try line("Heading")
        let body = try line("Synthetic body", at: 8)
        let retained = try frame("Heading\nSynthetic", lines: [heading], truncated: true)
        #expect(retained.ocrLines == [heading])
        #expect(!retained.canSupportIdentity)
        // An original line extending beyond the retained prefix cannot be carried forward.
        #expect(throws: ObservationVideoEvidenceError.invalidFrame) {
            try frame("Heading\nSynthetic", lines: [heading, body], truncated: true)
        }
        let noSpans = try frame("Head", lines: [], truncated: true)
        #expect(noSpans.ocrLines == [])
        #expect(!noSpans.canSupportIdentity)
    }

    @Test func decodingRevalidatesNestedBoundsConfidenceAndSourceSpans() throws {
        let original = try frame("Synthetic heading", lines: [line("Synthetic heading")])
        let json = try JSONSerialization.jsonObject(with: JSONEncoder().encode(original))
        let originalObject = try #require(json as? [String: Any])
        let originalLines = try #require(originalObject["ocrLines"] as? [[String: Any]])
        let originalBounds = try #require(originalLines[0]["bounds"] as? [String: Any])
        var object = originalObject
        var lines = originalLines
        var box = originalBounds
        box["width"] = 0
        lines[0]["bounds"] = box
        object["ocrLines"] = lines
        #expect(throws: ObservationOCRLineError.invalidBounds) {
            try JSONDecoder().decode(ObservationFrameEvidence.self, from: JSONSerialization.data(withJSONObject: object))
        }
        lines = originalLines
        lines[0]["confidence"] = 1.5
        object["ocrLines"] = lines
        #expect(throws: ObservationOCRLineError.invalidConfidence) {
            try JSONDecoder().decode(ObservationFrameEvidence.self, from: JSONSerialization.data(withJSONObject: object))
        }
        lines = originalLines
        lines[0]["startCharacterOffset"] = 1
        lines[0]["endCharacterOffset"] = "Synthetic heading".count + 1
        object["ocrLines"] = lines
        #expect(throws: ObservationVideoEvidenceError.invalidFrame) {
            try JSONDecoder().decode(ObservationFrameEvidence.self, from: JSONSerialization.data(withJSONObject: object))
        }
    }
}
