import CoreGraphics
import CoreText
import Foundation
import ImageIO
import MorningCore
import Testing
import UniformTypeIdentifiers
@testable import MorningApple
#if canImport(FoundationModels)
import FoundationModels
#endif

@Suite("Apple integration boundaries")
struct MorningAppleTests {
    #if canImport(FoundationModels)
    @Test("The dynamic guided-generation schema resolves all references")
    func structuredSchemaResolvesAllReferences() throws {
        let schema = try RoutineGenerationSchema.make()
        let encoded = try JSONEncoder().encode(schema)
        #expect(encoded.count > 100)
    }

    @Test("The real local model independently abstains on synthetic setup screens", .enabled("Set MO_RUN_MODEL_INTEGRATION=1; this bypasses the deterministic prefilter to evaluate model behavior.") {
        await ModelIntegrationGate.isReady()
    })
    @MainActor
    func realLocalModelSetupAbstention() async throws {
        let session = LanguageModelSession(model: SystemLanguageModel.default, instructions: AppleIntelligenceService.instructions)
        let response = try await session.respond(
            to: "Evidence type: visibleTaskContent. Decide whether actual activity is evidenced.\n<observations>\n\(LearningEvidenceFixtures.setupOnly)\n</observations>",
            schema: RoutineGenerationSchema.make(),
            options: GenerationOptions(temperature: 0, maximumResponseTokens: 1_100)
        )
        let result = try JSONDecoder().decode(ModelAbstentionResult.self, from: Data(response.content.jsonString.utf8))
        #expect(result.outcome == "insufficientEvidence")
        #expect(result.steps.isEmpty)
    }
    #endif

    @Test("Apple's local model proposes an unapproved grounded routine", .enabled("Set MO_RUN_MODEL_INTEGRATION=1; requires an available local Apple model.") {
        await ModelIntegrationGate.isReady()
    })
    @MainActor
    func realLocalModelIntegration() async throws {
        let service = AppleIntelligenceService()
        let source = "At 07:30 I review today's calendar. After breakfast I play chess for ten minutes."
        let proposal = try await service.analyze(text: source, as: .writtenReport, sourceLabel: "Synthetic model integration test")
        #expect(!proposal.isApproved)
        #expect(!proposal.steps.isEmpty)
        #expect(proposal.steps.allSatisfy { !$0.isRequired && $0.detail.contains(EvidenceDetailText.label) })
        #expect(proposal.steps.allSatisfy { (1...60).contains($0.durationMinutes) })
        print("MODEL_INTEGRATION_PASSED: actual local model returned \(proposal.steps.count) grounded, unapproved steps from synthetic notes.")
    }

    @Test("Unsupported actions and invented evidence are rejected")
    func rejectsHallucinatedEvidenceAndUnknownActions() {
        let source = "At 07:30 I review the calendar and read two messages."
        #expect(ProposalValidation.step(title: "Read mail", detail: "Review mail", kind: "messages", durationMinutes: 5,
            evidenceQuote: "send money", source: source) == nil)
        #expect(ProposalValidation.step(title: "Send money", detail: "", kind: "payment", durationMinutes: 5,
            evidenceQuote: "review the calendar", source: source) == nil)
        #expect(ProposalValidation.step(title: "Calendar", detail: "", kind: "calendar", durationMinutes: -10,
            evidenceQuote: "review the calendar", source: source) == nil)
    }

    @Test("Grounded proposals are optional and retain their source quote")
    func groundedProposalRemainsOptionalAndIncludesEvidence() throws {
        let proposed = ProposalValidation.step(
            title: "Review calendar", detail: "Check today's schedule.", kind: "calendar", durationMinutes: 3,
            evidenceQuote: "review the calendar", source: "I review the calendar after breakfast."
        )
        let step = try #require(proposed)
        #expect(step.kind == .calendar)
        #expect(!step.isRequired)
        #expect(step.detail.contains("review the calendar"))
    }

    @Test("Long observations are rejected rather than silently truncated")
    func inputIsNeverSilentlyTruncated() {
        #expect(throws: AppleIntelligenceError.inputTooLong(maximumCharacters: 5)) {
            try ObservationText.validated("abcdef", maximumCharacters: 5)
        }
        #expect(throws: AppleIntelligenceError.emptyInput) {
            try ObservationText.validated("\n  ", maximumCharacters: 5)
        }
    }

    @Test("Unicode chunking preserves every nonwhitespace character")
    func unicodeChunkingPreservesEvidence() {
        let text = String(repeating: "朝の予定🗓️を確認\n", count: 80)
        let chunks = ObservationText.chunks(text, maximumCharacters: 79)
        #expect(chunks.allSatisfy { !$0.isEmpty && $0.count <= 79 })
        #expect(chunks.joined().filter { !$0.isWhitespace } == text.filter { !$0.isWhitespace })
    }

    @Test("Sparse sampling covers a long clip within the frame budget")
    func sparseSamplingCoversLongClipWithinCap() {
        let times = FrameSampling.timestamps(duration: 1_800, maximumFrames: 24)
        #expect(times.count == 24)
        #expect(times.first == 0)
        #expect(abs((times.last ?? 0) - 1_799.9) < 0.01)
        #expect(times == times.sorted())
        #expect(times.allSatisfy { $0 >= 0 && $0 < 1_800 })
        #expect(FrameSampling.timestamps(duration: 0.05, maximumFrames: 24) == [0])
        #expect(FrameSampling.timestamps(duration: .infinity, maximumFrames: 24).isEmpty)
    }

    @Test("Remote media is never downloaded implicitly")
    func remoteMediaIsRejected() async throws {
        let url = try #require(URL(string: "https://example.com/recording.mp4"))
        await #expect(throws: MediaObservationError.localFileRequired) {
            try await MediaObservationService().extractText(from: url)
        }
    }

    @Test("Selected UTF-8 notes are read without modifying the source")
    func selectedUTF8NotesAreReadWithoutChangingSource() async throws {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString).appendingPathExtension("txt")
        let text = "I review the calendar, then play chess."
        try text.write(to: url, atomically: true, encoding: .utf8)
        defer { try? FileManager.default.removeItem(at: url) }
        let result = try await MediaObservationService().extract(from: url)
        #expect(result.kind == .text)
        #expect(result.text == text)
        #expect(try String(contentsOf: url, encoding: .utf8) == text)
    }

    @Test("Vision really reads a synthetic screenshot")
    func realVisionOCRFromSyntheticScreenshot() async throws {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString).appendingPathExtension("png")
        defer { try? FileManager.default.removeItem(at: url) }
        try Self.writeSyntheticScreenshot(to: url)
        let result = try await MediaObservationService().extract(from: url)
        #expect(result.kind == .image)
        #expect(result.sampledFrameCount == 1)
        #expect(result.text.lowercased().contains("calendar"))
        #expect(result.text.contains("09:00"))
    }

    private static func writeSyntheticScreenshot(to url: URL) throws {
        let context = try #require(CGContext(
            data: nil, width: 1_200, height: 500, bitsPerComponent: 8, bytesPerRow: 0,
            space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        ))
        context.setFillColor(CGColor(gray: 1, alpha: 1))
        context.fill(CGRect(x: 0, y: 0, width: 1_200, height: 500))
        context.textMatrix = .identity
        let attributes: [NSAttributedString.Key: Any] = [
            NSAttributedString.Key(kCTFontAttributeName as String): CTFontCreateWithName("Helvetica" as CFString, 54, nil),
            NSAttributedString.Key(kCTForegroundColorAttributeName as String): CGColor(gray: 0, alpha: 1)
        ]
        for (index, text) in ["Calendar", "09:00 Morning meeting", "10:30 Review project"].enumerated() {
            context.textPosition = CGPoint(x: 60, y: 370 - index * 105)
            let line = CTLineCreateWithAttributedString(NSAttributedString(string: text, attributes: attributes))
            CTLineDraw(line, context)
        }
        let image = try #require(context.makeImage())
        let destination = try #require(CGImageDestinationCreateWithURL(url as CFURL, UTType.png.identifier as CFString, 1, nil))
        CGImageDestinationAddImage(destination, image, nil)
        #expect(CGImageDestinationFinalize(destination))
    }
}

#if canImport(FoundationModels)
private struct ModelAbstentionResult: Decodable {
    struct Step: Decodable {}
    let outcome: String
    let steps: [Step]
}
#endif

private enum ModelIntegrationGate {
    static func isReady() async -> Bool {
        guard ProcessInfo.processInfo.environment["MO_RUN_MODEL_INTEGRATION"] == "1" else { return false }
        return await MainActor.run {
            let service = AppleIntelligenceService()
            if !service.isAvailable {
                print("MODEL_INTEGRATION_UNAVAILABLE: \(service.capabilitySummary) Inference test is skipped, not passed.")
            }
            return service.isAvailable
        }
    }
}
