import CoreGraphics
import CoreText
import Foundation
import MorningCore
import Testing
@testable import MorningApple

@Suite("Native OCR layout evidence")
struct MediaObservationLayoutTests {
    @Test("Real Vision extraction preserves exact joined spans and lower-left image bounds")
    func nativeTextAndBoundsFromSyntheticImage() async throws {
        let image = try makeSyntheticImage()
        let result = try await MediaObservationService().recognizeFrame(in: image)
        #expect(result.text.contains("Cedar Mail"))
        #expect(result.text.contains("Lumen Calendar"))
        let upper = try #require(result.lines.first { $0.text.contains("Cedar Mail") })
        let lower = try #require(result.lines.first { $0.text.contains("Lumen Calendar") })
        // The synthetic baselines are y=550 and y=200 in a 700-pixel image.
        // Broad bands tolerate normal OCR box variation while detecting a vertical flip.
        #expect(upper.bounds.y > 0.65 && upper.bounds.y < 0.9)
        #expect(lower.bounds.y > 0.2 && lower.bounds.y < 0.4)
        #expect(upper.bounds.x > 0.02 && upper.bounds.x < 0.12)
        #expect(lower.bounds.x > 0.4 && lower.bounds.x < 0.6)
        #expect(upper.bounds.y > lower.bounds.y + lower.bounds.height)
        #expect(upper.startCharacterOffset < lower.startCharacterOffset)
        let characters = Array(result.text)
        for line in result.lines {
            #expect(line.startCharacterOffset >= 0 && line.endCharacterOffset <= characters.count)
            #expect(String(characters[line.startCharacterOffset..<line.endCharacterOffset]) == line.text)
            #expect(line.confidence >= 0.25 && line.confidence <= 1)
            #expect(line.bounds.width > 0 && line.bounds.height > 0)
            #expect(line.bounds.x + line.bounds.width <= 1)
            #expect(line.bounds.y + line.bounds.height <= 1)
        }
        #expect(Set(result.lines.map(\.id)).count == result.lines.count)
        // Exercise the production frame assembler with this actual native result too.
        var builder = try VideoObservationBuilder(durationSeconds: 1)
        try builder.append(id: UUID(), requestedTimeSeconds: 0, actualTimeSeconds: 0,
                           outcome: .observed, text: result.text,
                           ocrLines: result.lines, ocrWarnings: result.warnings)
        let frame = try #require(builder.finish().frames.first)
        #expect(frame.text == result.text && frame.ocrLines == result.lines)
        #expect(try JSONDecoder().decode(ObservationFrameEvidence.self, from: JSONEncoder().encode(frame)) == frame)
    }

    private func makeSyntheticImage() throws -> CGImage {
        let context = try #require(CGContext(data: nil, width: 1_200, height: 700,
            bitsPerComponent: 8, bytesPerRow: 0, space: CGColorSpaceCreateDeviceRGB(),
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue))
        context.setFillColor(CGColor(gray: 1, alpha: 1))
        context.fill(CGRect(x: 0, y: 0, width: 1_200, height: 700))
        context.textMatrix = .identity
        let attributes: [NSAttributedString.Key: Any] = [
            NSAttributedString.Key(kCTFontAttributeName as String): CTFontCreateWithName("Helvetica" as CFString, 54, nil),
            NSAttributedString.Key(kCTForegroundColorAttributeName as String): CGColor(gray: 0, alpha: 1)
        ]
        for (text, point) in [("Cedar Mail", CGPoint(x: 60, y: 550)),
                              ("Lumen Calendar", CGPoint(x: 600, y: 200))] {
            context.textPosition = point
            CTLineDraw(CTLineCreateWithAttributedString(NSAttributedString(string: text, attributes: attributes)), context)
        }
        return try #require(context.makeImage())
    }
}
