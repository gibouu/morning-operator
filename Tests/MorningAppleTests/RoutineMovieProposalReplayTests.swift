import CryptoKit
import Darwin
import Foundation
import MorningCore
import Testing
@testable import MorningApple

/// One explicitly selected diagnostic per invocation; run variants serially.
@Suite("Opt-in proposal replay; no extraction or classification", .serialized)
struct RoutineMovieProposalReplayTests {
    @Test(.enabled("Set MO_RUN_MODEL_INTEGRATION=1 and MO_RUN_ROUTINE_REPLAY=1 with explicit paths.") {
        let env = ProcessInfo.processInfo.environment
        return env["MO_RUN_MODEL_INTEGRATION"] == "1" && env["MO_RUN_ROUTINE_REPLAY"] == "1"
    })
    @MainActor func replayOneSelectedVariant() async throws {
        let env = ProcessInfo.processInfo.environment
        let videoPath = try #require(env["MO_ROUTINE_VIDEO_PATH"]), inputPath = try #require(env["MO_ROUTINE_REPLAY_SOURCE_REPORT_PATH"])
        let outputPath = try #require(env["MO_ROUTINE_REPLAY_REPORT_PATH"])
        let video = URL(fileURLWithPath: videoPath).standardizedFileURL.resolvingSymlinksInPath()
        let input = URL(fileURLWithPath: inputPath).standardizedFileURL.resolvingSymlinksInPath()
        let output = URL(fileURLWithPath: outputPath).standardizedFileURL.resolvingSymlinksInPath()
        let work = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent()
            .deletingLastPathComponent().appendingPathComponent("work").resolvingSymlinksInPath()
        try #require(["MO_ROUTINE_VIDEO_PATH", "MO_ROUTINE_REPLAY_SOURCE_REPORT_PATH", "MO_ROUTINE_REPLAY_REPORT_PATH"].allSatisfy { env[$0]?.hasPrefix("/") == true })
        try #require(input.path.hasPrefix(work.path + "/") && output.path.hasPrefix(work.path + "/") && output != input && output != video)
        try #require(video.pathExtension.lowercased() == "mp4" && output.pathExtension == "json" && !FileManager.default.fileExists(atPath: output.path))
        let variant = env["MO_ROUTINE_REPLAY_VARIANT"] ?? "exact"
        var report = ReplayReport(variant: ["exact", "noClassification", "oneFrame"].contains(variant) ? variant : "invalid")
        let model = AppleIntelligenceService(model: .localOnly())
        do {
            guard ["exact", "noClassification", "oneFrame"].contains(report.variant),
                  (try input.resourceValues(forKeys: [.fileSizeKey]).fileSize ?? Int.max) <= 8 * 1_024 * 1_024 else { throw ReplayFailure.invalidInput }
            let bytes = try Data(contentsOf: input), decoder = JSONDecoder()
            decoder.dateDecodingStrategy = .iso8601
            let source = try decoder.decode(ReplayInput.self, from: bytes), original = source.acquisition
            let fingerprint = try await ObservationFileFingerprintService().fingerprint(of: video)
            guard source.schemaVersion == 2, source.mode == nil, fingerprint == source.fingerprint,
                  original.fileSHA256 == fingerprint.sha256, original.origin == .synthetic, original.sourceKind == .video,
                  original.videoEvidence == source.videoEvidence, original.classification == source.classification,
                  original.observedDate != nil, original.correctedText == nil, original.frameReviews.isEmpty,
                  original.recordingContext == nil, original.windowCapture == nil, original.sessionSegment == nil,
                  original.warnings.isEmpty else { throw ReplayFailure.invalidInput }
            report.inputReportSHA256 = Self.digest(bytes); report.fingerprint = fingerprint
            report.sourceAcquisitionSHA256 = try Self.encodedDigest(original)
            guard try Self.encodedDigest(original.videoEvidence) == Self.encodedDigest(Optional(source.videoEvidence)) else { throw ReplayFailure.invalidInput }
            var selectedVideo = source.videoEvidence
            if report.variant == "oneFrame" {
                guard let raw = env["MO_ROUTINE_REPLAY_FRAME_REQUESTED_SECONDS"], let time = Double(raw), time.isFinite else { throw ReplayFailure.invalidInput }
                let matches = source.videoEvidence.frames.filter { $0.requestedTimeSeconds.bitPattern == time.bitPattern }
                guard matches.count == 1, let frame = matches.first, frame.canSupportIdentity else { throw ReplayFailure.invalidInput }
                selectedVideo = try ObservationVideoEvidence(durationSeconds: source.videoEvidence.durationSeconds,
                    frames: [frame], warnings: source.videoEvidence.warnings)
            }
            let acquisition: ObservationAcquisition
            if report.variant == "exact" { acquisition = original }
            else {
                acquisition = try ObservationAcquisition(importedAt: original.importedAt, fileSHA256: original.fileSHA256,
                    observedDate: original.observedDate, origin: .synthetic, sourceKind: .video, sourceLabel: original.sourceLabel,
                    originalText: report.variant == "oneFrame" ? selectedVideo.renderedText : original.originalText, videoEvidence: selectedVideo)
                guard acquisition.classification == nil, acquisition.frameReviews.isEmpty,
                      report.variant == "oneFrame" || acquisition.originalText.utf8.elementsEqual(original.originalText.utf8) else { throw ReplayFailure.invalidInput }
            }
            report.acquisition = acquisition; report.replayedAcquisitionSHA256 = try Self.encodedDigest(acquisition)
            let archive = try ObservationArchive(entries: [acquisition])
            let evidence = try LearningEvidencePreparation.prepare(acquisitions: [acquisition])
            report.preparedUnitCount = evidence.units.count; report.omissions = evidence.omissions
            report.preparedModelRequestCount = evidence.modelRequestCount; report.preparedSubmittedCharacterCount = evidence.submittedCharacterCount
            let proposal = try await model.propose(evidence: evidence, preserving: nil, progress: { completed, total in
                report.proposalCompletedRequests = completed; report.proposalProgressTotalRequests = total
            })
            guard proposal.isCurrent(archive: archive, baseRoutine: nil), !proposal.routine.isApproved,
                  proposal.routine.isSynthetic, (1...PortableRoutineDocument.maximumSteps).contains(proposal.routine.steps.count) else { throw ReplayFailure.invalidProposal }
            report.validatedProposal = proposal; report.status = "proposedDraft"
        } catch {
            report.nativeError = ObservationContextErrorSanitizer.map(error)
            report.errorCategory = Self.category(error)
            if case RoutineEvidenceProposalError.insufficientEvidence = error, let d = model.proposalDiagnostics,
               d.phase == .assembling, d.plannedBatchCount > 0, d.respondInvocations == d.plannedBatchCount,
               d.responseReturns == d.plannedBatchCount, d.validatedBatchCount == d.plannedBatchCount, d.resolvedStepCount == 0,
               d.batches.count == d.plannedBatchCount, d.batches.allSatisfy({ $0.phase == .validated && $0.outcome == .insufficientEvidence && $0.stepCount == 0 }) {
                report.status = "validatedEmpty"
            }
        }
        // Even successful generation cannot bless a file changed during replay.
        do {
            let after = try await ObservationFileFingerprintService().fingerprint(of: video)
            guard let before = report.fingerprint, after == before else { throw ReplayFailure.invalidInput }
        } catch { report.status = "failed"; report.validatedProposal = nil; report.nativeError = ObservationContextErrorSanitizer.map(error); report.errorCategory = Self.category(error) }
        report.proposalDiagnostics = model.proposalDiagnostics; report.proposalCapability = model.capabilitySummary
        report.elapsedSeconds = Date().timeIntervalSince(report.createdAt)
        do { try Self.write(report, to: output) } catch { throw ReplayFailure.reportNotSaved }
        print("ROUTINE_REPLAY_REPORT_SAVED variant=\(report.variant) status=\(report.status)")
        guard report.status != "failed" else { throw ReplayFailure.replayFailed }
    }

    private static func digest(_ data: Data) -> String { SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined() }
    private static func encoder() -> JSONEncoder {
        let value = JSONEncoder(); value.outputFormatting = [.prettyPrinted, .sortedKeys]; value.dateEncodingStrategy = .iso8601; return value
    }
    private static func encodedDigest<T: Encodable>(_ value: T) throws -> String { digest(try encoder().encode(value)) }
    private static func category(_ error: any Error) -> String {
        switch error {
        case AppleIntelligenceError.unavailable: "localModelUnavailable"
        case AppleIntelligenceError.modelDidNotAnswer(let reason): "localModelDidNotAnswer.\(reason.rawValue)"
        case RoutineEvidenceProposalError.insufficientEvidence: "insufficientEvidence"
        case RoutineEvidenceProposalError.invalidCitation: "invalidCitation"
        case RoutineEvidenceProposalError.invalidProposal, ReplayFailure.invalidProposal: "invalidProposal"
        case ReplayFailure.invalidInput: "invalidReplayInput"
        default: ObservationContextErrorSanitizer.map(error).category.rawValue
        }
    }
    private static func write(_ report: ReplayReport, to output: URL) throws {
        let bytes = try encoder().encode(report)
        try FileManager.default.createDirectory(at: output.deletingLastPathComponent(), withIntermediateDirectories: true, attributes: [.posixPermissions: 0o700])
        let fd = Darwin.open(output.path, O_CREAT | O_EXCL | O_WRONLY | O_NOFOLLOW | O_CLOEXEC, mode_t(0o600))
        guard fd >= 0 else { throw ReplayFailure.reportNotSaved }
        let file = FileHandle(fileDescriptor: fd, closeOnDealloc: true); defer { try? file.close() }
        try file.write(contentsOf: bytes); try file.synchronize()
    }
}

private struct ReplayInput: Decodable {
    let schemaVersion: Int, mode: String?
    let fingerprint: ObservationFileFingerprint, videoEvidence: ObservationVideoEvidence
    let acquisition: ObservationAcquisition, classification: ObservationContextClassification?
}
private struct ReplayReport: Encodable {
    let mode = "replay-not-full-pipeline", schemaVersion = 1
    let scope = "Diagnostic replay of archived synthetic evidence, not a new extraction or classification. File bytes do not authenticate archived OCR. No oracle, catalog, expected intents, review, approval or provider execution. OneFrame is an explicit native projection retaining the complete selected frame and its original times."
    let createdAt = Date(), variant: String
    var status = "failed", proposalCapability = "", elapsedSeconds = 0.0
    var errorCategory: String?
    var inputReportSHA256: String?, sourceAcquisitionSHA256: String?, replayedAcquisitionSHA256: String?
    var fingerprint: ObservationFileFingerprint?, acquisition: ObservationAcquisition?
    var preparedUnitCount: Int?, preparedModelRequestCount: Int?, preparedSubmittedCharacterCount: Int?
    var proposalCompletedRequests: Int?, proposalProgressTotalRequests: Int?
    var omissions: [LearningEvidenceOmission] = [], proposalDiagnostics: RoutineProposalDiagnostics?
    var validatedProposal: EvidenceRoutineProposal?, nativeError: ObservationContextNativeError?
}
private enum ReplayFailure: Error { case invalidInput, invalidProposal, replayFailed, reportNotSaved }
