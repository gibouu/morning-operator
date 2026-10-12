import Foundation
import MorningCore
import Testing
@testable import MorningApple

@Suite("Opt-in recorded screen layout extraction")
struct ObservationLayoutMovieIntegrationTests {
    @Test("Selected movie retains actual Vision line geometry without invoking a model", .enabled(
        "Set MO_LAYOUT_VIDEO_PATH and MO_LAYOUT_REPORT_PATH to explicit local paths; output contains screen evidence.") {
        let environment = ProcessInfo.processInfo.environment
        return !(environment["MO_LAYOUT_VIDEO_PATH"] ?? "").isEmpty &&
            !(environment["MO_LAYOUT_REPORT_PATH"] ?? "").isEmpty
    })
    func selectedMovieLayoutReport() async throws {
        let environment = ProcessInfo.processInfo.environment
        let input = try #require(environment["MO_LAYOUT_VIDEO_PATH"])
        let output = try #require(environment["MO_LAYOUT_REPORT_PATH"])
        try #require(input.hasPrefix("/") && output.hasPrefix("/"), "Use absolute local paths.")
        let source = URL(fileURLWithPath: input).standardizedFileURL
        let destination = URL(fileURLWithPath: output).standardizedFileURL
        try #require(source.resolvingSymlinksInPath() != destination.resolvingSymlinksInPath())
        try #require(!FileManager.default.fileExists(atPath: destination.path), "Choose a new output; preserve previous evidence.")
        let started = Date()
        let observation = try await MediaObservationService().extract(from: source)
        let evidence = try #require(observation.videoEvidence, "Choose an actual recorded movie.")
        let prepared = try ObservationContextValidation.prepare(frames: evidence.frames, catalog: [])
        let report = MovieLayoutArtifact(createdAt: .now, elapsedSeconds: Date().timeIntervalSince(started),
            sourceFilename: source.lastPathComponent, evidence: evidence, preparedInput: prepared.inputSelection,
            preparedBatchCount: prepared.batches.count)
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        encoder.dateEncodingStrategy = .iso8601
        let data = try encoder.encode(report)
        try FileManager.default.createDirectory(at: destination.deletingLastPathComponent(), withIntermediateDirectories: true)
        try data.write(to: destination, options: .withoutOverwriting)
        try FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: destination.path)

        let lines = evidence.frames.flatMap { $0.ocrLines ?? [] }
        #expect(!lines.isEmpty, "A geometry proof needs actual recognized lines; empty extraction is not a pass.")
        #expect(try JSONDecoder().decode(ObservationVideoEvidence.self, from: encoder.encode(evidence)) == evidence)
        #expect(prepared.batches.allSatisfy { $0.prompt.count <= ObservationContextLimits.maximumPromptCharacters })
        print("LAYOUT_MOVIE_REPORT_SAVED: samples=\(evidence.frames.count), lines=\(lines.count), selectedFrames=\(prepared.inputSelection.excerpts.count), preparedBatches=\(prepared.batches.count). No model was invoked and no app identity or gesture accuracy is implied.")
    }
}

private struct MovieLayoutArtifact: Encodable {
    let schemaVersion = 1
    let scope = "Full selected movie, single-pass Vision text and layout. No model, expected sequence, inferred actions, capture coverage or wall-clock capture date."
    let geometry = "Axis-aligned Vision line bounds normalized to the processed, oriented image, lower-left origin. OCR confidence is not semantic confidence. Exact stored values; model hints rounded separately."
    let createdAt: Date
    let elapsedSeconds: Double
    let sourceFilename: String
    let evidence: ObservationVideoEvidence
    let preparedInput: ObservationContextInputSelection
    let preparedBatchCount: Int
}
