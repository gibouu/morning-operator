import Foundation
import MorningCore
import Testing
@testable import MorningApple

@Suite("Opt-in local visible-context inference")
struct ObservationContextModelIntegrationTests {
    @Test("The actual local model identifies a grounded synthetic visible header", .enabled(
        "Set MO_RUN_MODEL_INTEGRATION=1; requires an available Apple local model.") {
        await ObservationContextModelGate.isReady()
    })
    @MainActor
    func realLocalVisibleHeader() async throws {
        let frame = try ObservationFrameEvidence(requestedTimeSeconds: 0, actualTimeSeconds: 0,
            outcome: .observed, text: "Cedar Mail\nInbox\nFrom: Synthetic Garden Club\nSubject: Saturday seed exchange\nPlease bring spare seed packets.")
        let result = try await ObservationContextClassifier().classify(frames: [frame],
            catalog: [.init(label: "Cedar Mail"), .init(label: "Lumen Calendar")])
        #expect(result.status == .completed)
        #expect(result.attemptedBatchCount > 0 && result.respondedBatchCount > 0 && result.failedBatchCount == 0)
        let decision = try #require(result.decisions.first)
        #expect(decision.evidence == .identified(app: .init(key: "visual-context:cedar mail", displayName: "Cedar Mail"),
                                                reference: frame.evidenceReference))
        #expect(decision.evidenceQuote == "Cedar Mail")
        print("CONTEXT_MODEL_INTEGRATION: actual local inference evaluated one synthetic header; see assertions for outcome.")
    }

    @Test("Selected full movie exports evidence and local-model results without controller truth", .enabled(
        "Set MO_RUN_MODEL_INTEGRATION=1 plus MO_OBSERVATION_VIDEO_PATH and MO_OBSERVATION_REPORT_PATH; output remains local.") {
        let environment = ProcessInfo.processInfo.environment
        return environment["MO_RUN_MODEL_INTEGRATION"] == "1" &&
            !(environment["MO_OBSERVATION_VIDEO_PATH"] ?? "").isEmpty &&
            !(environment["MO_OBSERVATION_REPORT_PATH"] ?? "").isEmpty
    })
    @MainActor
    func selectedMovieInferenceAndReport() async throws {
        let environment = ProcessInfo.processInfo.environment
        let videoPath = try #require(environment["MO_OBSERVATION_VIDEO_PATH"])
        let reportPath = try #require(environment["MO_OBSERVATION_REPORT_PATH"])
        try #require(videoPath.hasPrefix("/") && reportPath.hasPrefix("/"), "Use explicit absolute local paths.")
        let videoURL = URL(fileURLWithPath: videoPath).standardizedFileURL
        let reportURL = URL(fileURLWithPath: reportPath).standardizedFileURL
        try #require(videoURL.resolvingSymlinksInPath() != reportURL.resolvingSymlinksInPath(),
                     "The result must not overwrite the selected movie.")
        let started = Date()
        // This is the complete selected movie, including setup and teardown. Never trim to
        // a controller's expected interval or send its scripted actions to the model.
        let observation = try await MediaObservationService().extract(from: videoURL)
        let evidence = try #require(observation.videoEvidence, "The selected input must decode as structured video evidence.")
        let fixtureCatalog = environment["MO_OBSERVATION_FIXTURE_CATALOG"] == "1"
        // This optional vocabulary describes two independent fixture headers only. It has
        // no ordering, frequency, timing or expected actions from any benchmark script.
        let catalog: [ObservationContextCatalogEntry] = fixtureCatalog ?
            [.init(label: "Cedar Mail"), .init(label: "Lumen Calendar")] : []
        let classification = try await ObservationContextClassifier().classify(frames: evidence.frames, catalog: catalog)
        let origin = ObservationTraceOrigin(rawValue: environment["MO_OBSERVATION_ORIGIN"] ?? "unknown") ?? .unknown
        let rawGap = Double(environment["MO_OBSERVATION_MAX_SAMPLE_GAP_SECONDS"] ?? "2") ?? 2
        let maximumGap = rawGap.isFinite && rawGap > 0 ? rawGap : 2
        // A movie timeline is not itself evidence of continuous screen capture. Keep
        // captured intervals unknown; a separate scorer may apply verified capture metadata.
        let trace = try evidence.makeTrace(decisions: classification.decisions, origin: origin, capturedIntervals: nil)
        let report = try trace.report(maximumSampleGapSeconds: maximumGap)
        let artifact = ObservationMovieInferenceArtifact(createdAt: .now,
            elapsedSeconds: Date().timeIntervalSince(started), sourceFilename: videoURL.lastPathComponent,
            usedFixtureCatalog: fixtureCatalog, catalog: catalog, evidence: evidence,
            classification: classification, trace: trace, report: report)
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        encoder.dateEncodingStrategy = .iso8601
        let data = try encoder.encode(artifact)
        try FileManager.default.createDirectory(at: reportURL.deletingLastPathComponent(), withIntermediateDirectories: true)
        try data.write(to: reportURL, options: .atomic)
        try FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: reportURL.path)
        // Save even unavailable/failed results before failing the model requirement. A
        // runtime-unavailable run is not relabeled as a successful extraction+model test.
        print("OBSERVATION_MOVIE_REPORT_SAVED: frames=\(evidence.frames.count), modelStatus=\(classification.status.rawValue), attempted=\(classification.attemptedBatchCount), responded=\(classification.respondedBatchCount), failed=\(classification.failedBatchCount). No semantic-accuracy verdict is implied.")
        try #require(classification.status != .unavailable,
                     "LOCAL_MODEL_UNAVAILABLE: extraction and unknown decisions were saved; model inference did not run.")
        try #require(classification.status != .noEligibleFrames,
                     "NO_ELIGIBLE_MODEL_FRAMES: extraction/exclusions were saved; model inference did not run.")
        #expect(classification.status == .completed, "Generation failures remain in the saved report.")
        #expect(classification.attemptedBatchCount > 0 && classification.respondedBatchCount > 0)
        #expect(classification.decisions.map(\.sampleID) == evidence.frames.map(\.id))
        #expect(report.sampleCount == evidence.frames.count)
        // Expected sequences/counts belong to the independent scorer, never this model input.
    }
}

private struct ObservationMovieInferenceArtifact: Encodable {
    let schemaVersion = 1
    let scope = "Complete selected video; classification of visible context, not verified OS opens or human habits. Capture coverage unknown unless independently established."
    let createdAt: Date
    let elapsedSeconds: Double
    let sourceFilename: String
    let usedFixtureCatalog: Bool
    let catalog: [ObservationContextCatalogEntry]
    let evidence: ObservationVideoEvidence
    let classification: ObservationContextClassification
    let trace: ObservationTrace
    let report: ObservationTraceReport
}

private enum ObservationContextModelGate {
    static func isReady() async -> Bool {
        guard ProcessInfo.processInfo.environment["MO_RUN_MODEL_INTEGRATION"] == "1" else { return false }
        return await MainActor.run {
            let service = ObservationContextClassifier()
            if !service.isAvailable {
                print("CONTEXT_MODEL_INTEGRATION_UNAVAILABLE: \(service.capabilitySummary) Header inference is skipped, not passed.")
            }
            return service.isAvailable
        }
    }
}
