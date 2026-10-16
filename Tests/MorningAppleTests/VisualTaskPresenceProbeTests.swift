import CryptoKit
import Darwin
import Foundation
import MorningCore
import Testing
@testable import MorningApple
#if canImport(FoundationModels)
import FoundationModels
#endif

@Suite("Opt-in task-presence diagnostic — no routine or authority", .serialized)
struct VisualTaskPresenceProbeTests {
    @Test @MainActor func productionInstructionBytesStayAtTheRetainedENFRCheckpoint() {
        // Frozen public instruction bytes at 42dc82b; no source evidence here.
        #expect(Self.digest(Data(AppleIntelligenceService.groundedProposalInstructions(french: false).utf8)) ==
            "f0f19c9b2c50063640ad64465ff8971161923da45f624ae08d37435ed237a472")
        #expect(Self.digest(Data(AppleIntelligenceService.groundedProposalInstructions(french: true).utf8)) ==
            "eae15f61ba3b4b6f14d07ad7dd874859885b1517d0b1d4e6ee81705e9760b165")
    }

    @Test(.enabled("Set MO_RUN_MODEL_INTEGRATION=1 and MO_RUN_VISUAL_TASK_PRESENCE_PROBE=1 with explicit private paths.") {
        let env = ProcessInfo.processInfo.environment
        return env["MO_RUN_MODEL_INTEGRATION"] == "1" && env["MO_RUN_VISUAL_TASK_PRESENCE_PROBE"] == "1"
    })
    @MainActor func compareThreeUnchangedSourcesWithoutAssemblingAProposal() async throws {
        #if canImport(FoundationModels)
        let env = ProcessInfo.processInfo.environment
        let inputPath = try #require(env["MO_TASK_PRESENCE_SOURCE_REPORT_PATH"])
        let videoPath = try #require(env["MO_TASK_PRESENCE_VIDEO_PATH"])
        let outputPath = try #require(env["MO_TASK_PRESENCE_REPORT_PATH"])
        let rawTime = try #require(env["MO_TASK_PRESENCE_FRAME_REQUESTED_SECONDS"])
        let requested = try #require(Double(rawTime)); try #require(requested.isFinite)
        let input = URL(fileURLWithPath: inputPath).standardizedFileURL.resolvingSymlinksInPath()
        let videoURL = URL(fileURLWithPath: videoPath).standardizedFileURL.resolvingSymlinksInPath()
        let output = URL(fileURLWithPath: outputPath).standardizedFileURL.resolvingSymlinksInPath()
        let work = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent()
            .deletingLastPathComponent().appendingPathComponent("work").resolvingSymlinksInPath()
        try #require([inputPath, videoPath, outputPath].allSatisfy { $0.hasPrefix("/") })
        try #require(input.path.hasPrefix(work.path + "/") && output.path.hasPrefix(work.path + "/"))
        try #require(output != input && output != videoURL && output.pathExtension == "json")
        try #require(!FileManager.default.fileExists(atPath: output.path))
        var report = PresenceReport()
        do {
            guard (try input.resourceValues(forKeys: [.fileSizeKey]).fileSize ?? Int.max) <= 8 * 1_024 * 1_024 else { throw ProbeFailure.invalidInput }
            let bytes = try Data(contentsOf: input), decoder = JSONDecoder()
            decoder.dateDecodingStrategy = .iso8601
            let source = try decoder.decode(PresenceInput.self, from: bytes), original = source.acquisition
            let fingerprint = try await ObservationFileFingerprintService().fingerprint(of: videoURL)
            report.inputReportSHA256 = Self.digest(bytes); report.fingerprint = fingerprint
            guard source.schemaVersion == 2, source.mode == nil, fingerprint == source.fingerprint,
                  original.fileSHA256 == fingerprint.sha256, original.origin == .synthetic,
                  original.sourceKind == .video, original.videoEvidence == source.videoEvidence,
                  original.classification == source.classification, original.correctedText == nil,
                  original.frameReviews.isEmpty, let observedDate = original.observedDate else { throw ProbeFailure.invalidInput }
            let frames = source.videoEvidence.frames.filter { $0.requestedTimeSeconds.bitPattern == requested.bitPattern }
            guard frames.count == 1, let frame = frames.first, frame.canSupportIdentity else { throw ProbeFailure.invalidInput }
            let projected = try ObservationVideoEvidence(durationSeconds: source.videoEvidence.durationSeconds,
                frames: [frame], warnings: source.videoEvidence.warnings)
            let archived = try ObservationAcquisition(importedAt: original.importedAt, fileSHA256: original.fileSHA256,
                observedDate: observedDate, origin: original.origin, sourceKind: .video, sourceLabel: original.sourceLabel,
                originalText: projected.renderedText, videoEvidence: projected)
            // Exact existing realSyntheticTaskProposal inputs, including the short banner.
            let controls = try [
                "SYNTHETIC\n09:10 Inspect the workshop materials\nNotebook and pencils are on the table.",
                "SYNTHETIC\nA colleague asks whether the workshop notes are ready.\nPlease review the blue folder before the meeting."
            ].enumerated().map {
                try ObservationFrameEvidence(requestedTimeSeconds: Double($0.offset), actualTimeSeconds: Double($0.offset),
                    outcome: .observed, text: $0.element)
            }
            let controlVideo = try ObservationVideoEvidence(durationSeconds: 2, frames: controls)
            let bare = try ObservationAcquisition(importedAt: original.importedAt, observedDate: observedDate,
                origin: .synthetic, sourceKind: .video, sourceLabel: "Synthetic task positive control",
                originalText: controlVideo.renderedText, videoEvidence: controlVideo)
            let advertisement = try ObservationAcquisition(importedAt: original.importedAt, observedDate: observedDate,
                origin: .synthetic, sourceKind: .image, sourceLabel: "Task origin contract",
                originalText: "Sponsored advertisement\nBuy a new notebook today and save twenty percent.")
            guard SystemLanguageModel.default.isAvailable else { throw ProbeFailure.modelUnavailable }
            let french = AppLanguage.isFrench
            let instructions = AppleIntelligenceService.groundedProposalInstructions(french: french)
            report.instructionSHA256 = Self.digest(Data(instructions.utf8)); report.instructionUTF8Bytes = instructions.utf8.count
            report.instructionLanguage = french ? "fr" : "en"
            for (label, acquisition) in [("archivedOneFrame", archived), ("existingVisualControl", bare), ("existingAdvertisementControl", advertisement)] {
                try Task.checkCancellation()
                let evidence = try LearningEvidencePreparation.prepare(acquisitions: [acquisition])
                let anchored = try ModelCitationPreparation.prepare(evidence)
                guard anchored.evidence.batches.count == 1, let units = anchored.evidence.batches.first,
                      let first = units.first, let batch = anchored.batchesByFirstUnitID[first.id], batch.units == units,
                      !batch.anchors.isEmpty else { throw ProbeFailure.invalidInput }
                let schema = try Self.schema(citationIDs: batch.anchors.map(\.id))
                var record = PresenceCase(label: label, sourceKind: acquisition.sourceKind.rawValue,
                    origin: acquisition.origin.rawValue, unitCount: units.count, anchorCount: batch.anchors.count,
                    promptSHA256: Self.digest(Data(batch.prompt.utf8)), promptUTF8Bytes: batch.prompt.utf8.count,
                    schemaSHA256: Self.digest(try JSONEncoder().encode(schema)))
                let session = LanguageModelSession(model: SystemLanguageModel.default, instructions: instructions)
                report.respondInvocations += 1
                do {
                    let response = try await session.respond(to: batch.prompt, schema: schema,
                        options: GenerationOptions(temperature: 0, maximumResponseTokens: 200))
                    report.responseReturns += 1
                    try Task.checkCancellation()
                    let value = try JSONDecoder().decode(PresenceAnswer.self, from: Data(response.content.jsonString.utf8))
                    guard !value.description.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
                          value.description.count <= 160, value.description.utf8.count <= 640,
                          value.citationID == nil || batch.anchors.contains(where: { $0.id == value.citationID }) else { throw ProbeFailure.invalidDiagnostic }
                    record.answer = value // Parsed diagnostic only; no raw SDK response or routine assembly.
                } catch {
                    record.errorCategory = error is ProbeFailure ? "invalidDiagnostic" : ObservationContextErrorSanitizer.map(error).category.rawValue
                    report.failedCases += 1
                }
                report.cases.append(record)
                if Task.isCancelled { throw CancellationError() }
            }
            let after = try await ObservationFileFingerprintService().fingerprint(of: videoURL)
            guard after == fingerprint else { throw ProbeFailure.invalidInput }
            report.status = report.failedCases == 0 ? "diagnosticCompleted" : "failed"
        } catch {
            report.errorCategory = error is ProbeFailure ? "invalidInputOrUnavailable" : ObservationContextErrorSanitizer.map(error).category.rawValue
        }
        report.elapsedSeconds = Date().timeIntervalSince(report.createdAt)
        try Self.write(report, to: output)
        print("VISUAL_TASK_PRESENCE_REPORT_SAVED status=\(report.status)")
        #expect(report.status == "diagnosticCompleted", "A diagnostic error is a failure; either Boolean answer alone is not product acceptance.")
        #else
        Issue.record("The explicitly requested diagnostic needs the local Foundation Models SDK.")
        #endif
    }

    #if canImport(FoundationModels)
    private static func schema(citationIDs: [String]) throws -> GenerationSchema {
        let citations = DynamicGenerationSchema(name: "PresenceCitationID", anyOf: citationIDs)
        let categories = DynamicGenerationSchema(name: "PresenceCategory", anyOf: PresenceCategory.allCases.map(\.rawValue))
        let root = DynamicGenerationSchema(name: "TaskPresenceDiagnostic", description:
            "Diagnostic output only, not a routine. Report whether concrete task content can support tentative review under the supplied policy. Do not give internal reasoning or propose any action.", properties: [
                .init(name: "actualTaskPresent", schema: .init(type: Bool.self)),
                .init(name: "citationID", description: "Optional supplied ID of an excerpt relevant to this diagnostic decision; never invent an ID.", schema: .init(referenceTo: "PresenceCitationID"), isOptional: true),
                .init(name: "category", schema: .init(referenceTo: "PresenceCategory")),
                .init(name: "description", description: "One brief observable reason, at most 160 characters. No internal reasoning.", schema: .init(type: String.self))
            ])
        return try GenerationSchema(root: root, dependencies: [citations, categories])
    }
    #endif

    private static func digest(_ data: Data) -> String { SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined() }
    private static func write(_ report: PresenceReport, to url: URL) throws {
        let encoder = JSONEncoder(); encoder.dateEncodingStrategy = .iso8601; encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        let bytes = try encoder.encode(report)
        let fd = open(url.path, O_WRONLY | O_CREAT | O_EXCL | O_NOFOLLOW, S_IRUSR | S_IWUSR)
        guard fd >= 0 else { throw ProbeFailure.reportNotSaved }
        let file = FileHandle(fileDescriptor: fd, closeOnDealloc: true); defer { try? file.close() }
        try file.write(contentsOf: bytes); try file.synchronize()
    }
}

private enum PresenceCategory: String, Codable, CaseIterable { case taskContent, labelsOrControls, promotion, provenanceOnly, unclear, other }
private struct PresenceAnswer: Codable { let actualTaskPresent: Bool; let citationID: String?; let category: PresenceCategory; let description: String }
private struct PresenceInput: Decodable {
    let schemaVersion: Int, mode: String?
    let fingerprint: ObservationFileFingerprint, videoEvidence: ObservationVideoEvidence
    let acquisition: ObservationAcquisition, classification: ObservationContextClassification?
}
private struct PresenceCase: Encodable {
    let label: String, sourceKind: String, origin: String, unitCount: Int, anchorCount: Int
    let promptSHA256: String, promptUTF8Bytes: Int, schemaSHA256: String
    var answer: PresenceAnswer?, errorCategory: String?
}
private struct PresenceReport: Encodable {
    let mode = "diagnostic-task-presence-not-proposal", schemaVersion = 1, createdAt = Date()
    let scope = "Production instruction bytes and anchored-input builder, deliberately different output schema/task. Fresh unit IDs do not establish byte identity with a historical SDK submission. A short model declaration is not its internal cause, a validated routine, OCR authenticity or execution proof. All sources are synthetic. No oracle, prompt/raw response logging, assembly, approval, provider or account."
    var status = "failed", elapsedSeconds = 0.0, respondInvocations = 0, responseReturns = 0, failedCases = 0
    var inputReportSHA256: String?, instructionSHA256: String?, instructionLanguage: String?, instructionUTF8Bytes: Int?
    var fingerprint: ObservationFileFingerprint?, cases: [PresenceCase] = [], errorCategory: String?
}
private enum ProbeFailure: Error { case invalidInput, modelUnavailable, invalidDiagnostic, reportNotSaved }
