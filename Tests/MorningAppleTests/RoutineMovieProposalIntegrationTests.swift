import Darwin
import Foundation
import MorningCore
import Testing
@testable import MorningApple

@Suite("Opt-in full selected movie to local routine proposal")
struct RoutineMovieProposalIntegrationTests {
    @Test("Actual video extraction, context inference and grounded proposal export", .enabled(
        "Set MO_RUN_MODEL_INTEGRATION=1, MO_ROUTINE_VIDEO_PATH and a new MO_ROUTINE_REPORT_PATH under work/.") {
        let environment = ProcessInfo.processInfo.environment
        return environment["MO_RUN_MODEL_INTEGRATION"] == "1" &&
            !(environment["MO_ROUTINE_VIDEO_PATH"] ?? "").isEmpty &&
            !(environment["MO_ROUTINE_REPORT_PATH"] ?? "").isEmpty
    })
    @MainActor
    func selectedMovieToRoutineReport() async throws {
        let environment = ProcessInfo.processInfo.environment
        let input = try #require(environment["MO_ROUTINE_VIDEO_PATH"])
        let output = try #require(environment["MO_ROUTINE_REPORT_PATH"])
        try #require(input.hasPrefix("/") && output.hasPrefix("/"), "Use explicit absolute paths.")
        let source = URL(fileURLWithPath: input).standardizedFileURL.resolvingSymlinksInPath()
        let destination = URL(fileURLWithPath: output).standardizedFileURL.resolvingSymlinksInPath()
        let ignored = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent()
            .deletingLastPathComponent().appendingPathComponent("work").resolvingSymlinksInPath()
        try #require(destination.path.hasPrefix(ignored.path + "/") && source != destination,
                     "Keep the private report in this checkout's ignored work directory, separate from the input.")
        try #require(!FileManager.default.fileExists(atPath: destination.path), "Never overwrite previous evidence.")
        var report = RoutineMovieProposalReport()
        let classifier = ObservationContextClassifier(), model = AppleIntelligenceService()
        report.contextCapability = classifier.capabilitySummary
        report.proposalCapability = model.capabilitySummary
        do {
            report.stage = "fingerprintAndExtraction"
            let fingerprint = try await ObservationFileFingerprintService().fingerprint(of: source)
            report.fingerprint = fingerprint
            let observation = try await MediaObservationService().extract(from: source)
            let finalFingerprint = try await ObservationFileFingerprintService().fingerprint(of: source)
            guard fingerprint == finalFingerprint else { throw ObservationFileFingerprintError.fileChanged }
            guard let video = observation.videoEvidence else { throw MediaObservationError.unsupportedFormat }
            report.videoEvidence = video; report.extractionWarnings = observation.warnings
            report.stage = "visibleContextClassification"
            let classification = try await classifier.classify(frames: video.frames, catalog: [])
            report.classification = classification
            report.contextCapability = classifier.capabilitySummary
            // Explicit QA-assigned day only: no capture timestamp, continuous
            // coverage, own-interface spans, frame reviews or intentions invented.
            let qaDay = try ObservationObservedDate(date: Date(timeIntervalSince1970: 1_792_123_200),
                timeZoneIdentifier: "Europe/Paris", provenance: .userAssigned)
            report.stage = "acquisitionAndEvidencePreparation"
            let acquisition = try ObservationAcquisition(fileSHA256: fingerprint.sha256, observedDate: qaDay,
                origin: .synthetic, sourceKind: .video, sourceLabel: "Selected synthetic video for local QA",
                originalText: observation.text, videoEvidence: video, classification: classification)
            report.acquisition = acquisition
            let archive = try ObservationArchive(entries: [acquisition])
            let evidence = try LearningEvidencePreparation.prepare(acquisitions: [acquisition])
            report.preparedUnitCount = evidence.units.count
            report.preparedSubmittedCharacterCount = evidence.submittedCharacterCount
            report.preparedModelRequestCount = evidence.modelRequestCount
            report.omissions = evidence.omissions
            report.stage = "localRoutineProposal"
            let proposal = try await model.propose(evidence: evidence, preserving: nil, progress: { completed, total in
                // Total is the serial runner's post-annotation workload, not an
                // attempted-request count. An interrupted request may not complete.
                report.proposalProgressTotalRequests = total
                report.proposalCompletedRequests = completed
            })
            report.proposalDiagnostics = model.proposalDiagnostics
            report.proposal = proposal; report.proposalCapability = model.capabilitySummary
            report.stage = "exactSourceValidation"
            report.citationsValid = proposal.isCurrent(archive: archive, baseRoutine: nil)
            guard report.citationsValid == true, !proposal.routine.isApproved, proposal.routine.isSynthetic,
                  (1...PortableRoutineDocument.maximumSteps).contains(proposal.routine.steps.count),
                  classification.status == .completed, classification.attemptedBatchCount > 0,
                  classification.respondedBatchCount > 0, classification.failedBatchCount == 0 else {
                throw RoutineMovieReportFailure.invalidResult
            }
            report.status = "completed"
        } catch {
            report.proposalDiagnostics = model.proposalDiagnostics
            report.errorCategory = Self.category(error)
            report.nativeError = ObservationContextErrorSanitizer.map(error)
            report.status = report.errorCategory == "localModelUnavailable" || report.classification?.status == .unavailable
                ? "unavailable" : "failed"
        }
        report.elapsedSeconds = Date().timeIntervalSince(report.createdAt)
        do { try report.writeNewPrivateFile(to: destination) }
        catch { throw RoutineMovieReportFailure.reportNotSaved }
        print("ROUTINE_MOVIE_REPORT_SAVED status=\(report.status) stage=\(report.stage) category=\(report.errorCategory ?? "none")")
        guard report.status == "completed" else { throw RoutineMovieReportFailure.pipelineFailed }
        #expect(report.citationsValid == true)
    }

    private static func category(_ error: any Error) -> String {
        switch error {
        case AppleIntelligenceError.unavailable: "localModelUnavailable"
        case RoutineEvidenceProposalError.invalidProposal: "invalidProposal"
        case RoutineEvidenceProposalError.invalidCitation: "invalidCitation"
        case RoutineEvidenceProposalError.insufficientEvidence: "insufficientEvidence"
        case RoutineEvidenceProposalError.inputBudgetExceeded: "inputBudgetExceeded"
        case RoutineEvidenceProposalError.outputBudgetExceeded: "outputBudgetExceeded"
        case RoutineMovieReportFailure.invalidResult: "invalidResult"
        case is RoutineEvidenceProposalError: "evidencePolicyRejected"
        case is MediaObservationError: "mediaExtractionRejected"
        case ObservationFileFingerprintError.fileChanged: "sourceChanged"
        default: ObservationContextErrorSanitizer.map(error).category.rawValue
        }
    }
}

private enum RoutineMovieReportFailure: Error { case invalidResult, pipelineFailed, reportNotSaved }

private struct RoutineMovieProposalReport: Encodable {
    let schemaVersion = 2
    let scope = "Selected synthetic movie only; no oracle/catalog/filename/expected intents supplied to either local model. QA-assigned day is not capture metadata. No semantic accuracy verdict or provider execution is claimed."
    let createdAt = Date()
    var elapsedSeconds = 0.0
    var stage = "notStarted", status = "notCompleted"
    var contextCapability = "", proposalCapability = ""
    var fingerprint: ObservationFileFingerprint?
    var videoEvidence: ObservationVideoEvidence?
    var extractionWarnings: [String] = []
    var classification: ObservationContextClassification?
    var acquisition: ObservationAcquisition?
    var preparedUnitCount: Int?, preparedSubmittedCharacterCount: Int?, preparedModelRequestCount: Int?
    var proposalProgressTotalRequests: Int?, proposalCompletedRequests: Int?
    /// Optional: older reports remain readable without this content-free detail.
    var proposalDiagnostics: RoutineProposalDiagnostics?
    var omissions: [LearningEvidenceOmission] = []
    var proposal: EvidenceRoutineProposal?
    var citationsValid: Bool?
    var errorCategory: String?
    var nativeError: ObservationContextNativeError?

    func writeNewPrivateFile(to destination: URL) throws {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]; encoder.dateEncodingStrategy = .iso8601
        let data = try encoder.encode(self)
        try FileManager.default.createDirectory(at: destination.deletingLastPathComponent(),
            withIntermediateDirectories: true, attributes: [.posixPermissions: 0o700])
        let descriptor = Darwin.open(destination.path, O_CREAT | O_EXCL | O_WRONLY | O_NOFOLLOW | O_CLOEXEC, mode_t(0o600))
        guard descriptor >= 0 else { throw RoutineMovieReportFailure.reportNotSaved }
        let handle = FileHandle(fileDescriptor: descriptor, closeOnDealloc: true)
        defer { try? handle.close() }
        try handle.write(contentsOf: data)
        try handle.synchronize()
    }
}
