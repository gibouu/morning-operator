import Darwin
import Foundation
import MorningCore
import Testing
import Vision
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
        let ocr = RoutineMovieOCRRecorder()
        let extractor = MediaObservationService(ocr: .shared) { image in
            let index = await ocr.started(), start = ContinuousClock.now
            do {
                let value = try await MediaObservationService.recognizeNativeFrame(in: image)
                await ocr.finished(index, since: start, failure: nil)
                return value
            } catch {
                await ocr.finished(index, since: start, failure: RoutineMovieOCRRecorder.Failure(error))
                throw error
            }
        }
        let classifier = ObservationContextClassifier(), model = AppleIntelligenceService(model: .localOnly())
        report.contextCapability = classifier.capabilitySummary
        report.proposalCapability = model.capabilitySummary
        do {
            report.stage = "fingerprintAndExtraction"
            let fingerprint = try await ObservationFileFingerprintService().fingerprint(of: source)
            report.fingerprint = fingerprint
            let observation = try await extractor.extract(from: source)
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
        report.ocrDiagnostics = await ocr.snapshot()
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
        case AppleIntelligenceError.modelDidNotAnswer(let reason): "localModelDidNotAnswer.\(reason.rawValue)"
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
    /// Private native-call measurements, never raw errors or source contents.
    var ocrDiagnostics: [RoutineMovieOCRRecorder.Attempt] = []
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

/// The real recognizer and shared lane are unchanged. This test-only observer
/// preserves fixed error domains/codes that extraction deliberately hides in UI.
private actor RoutineMovieOCRRecorder {
    struct Failure: Encodable, Sendable {
        enum Domain: String, Encodable { case vision, cocoa, posix, cancellation, other }
        enum Category: String, Encodable, Sendable {
            case dataUnavailable, internalError, invalidArgument, invalidFormat, invalidImage, invalidModel
            case invalidOperation, ioError, operationFailed, outOfBoundsError, outOfMemory, pixelBufferCreationFailed
            case requestCancelled, timeout, timeStampNotFound, unsupportedComputeDevice, unsupportedComputeStage
            case unsupportedRequest, unsupportedRevision, unknownVisionCase
        }
        let domain: Domain
        let code: Int?
        let category: Category?
        init(_ error: any Error) {
            if let vision = error as? VisionError {
                domain = .vision; code = nil; category = Self.category(vision); return
            }
            category = nil
            if error is CancellationError { domain = .cancellation; code = nil; return }
            let native = error as NSError
            switch native.domain {
            case VNErrorDomain: domain = .vision
            case NSCocoaErrorDomain: domain = .cocoa
            case NSPOSIXErrorDomain: domain = .posix
            default: domain = .other
            }
            code = domain == .other ? nil : native.code
        }

        private static func category(_ error: VisionError) -> Category {
            // Associated strings (and the pixel-buffer payload) are never read.
            switch error {
            case .dataUnavailable(_): .dataUnavailable
            case .internalError(_): .internalError
            case .invalidArgument(_): .invalidArgument
            case .invalidFormat(_): .invalidFormat
            case .invalidImage(_): .invalidImage
            case .invalidModel(_): .invalidModel
            case .invalidOperation(_): .invalidOperation
            case .ioError(_): .ioError
            case .operationFailed(_): .operationFailed
            case .outOfBoundsError(_): .outOfBoundsError
            case .outOfMemory(_): .outOfMemory
            case .pixelBufferCreationFailed(_): .pixelBufferCreationFailed
            case .requestCancelled(_): .requestCancelled
            case .timeout(_): .timeout
            case .timeStampNotFound(_): .timeStampNotFound
            case .unsupportedComputeDevice(_): .unsupportedComputeDevice
            case .unsupportedComputeStage(_): .unsupportedComputeStage
            case .unsupportedRequest(_): .unsupportedRequest
            case .unsupportedRevision(_): .unsupportedRevision
            @unknown default: .unknownVisionCase
            }
        }
    }
    struct Attempt: Encodable, Sendable {
        let index: Int
        var elapsedSeconds: Double?
        var failure: Failure?
        var completed = false
    }
    private var attempts: [Attempt] = []
    func started() -> Int? {
        guard attempts.count < MediaObservationService.maximumFrames else { return nil }
        let index = attempts.count
        attempts.append(.init(index: index))
        return index
    }
    func finished(_ index: Int?, since start: ContinuousClock.Instant, failure: Failure?) {
        guard let index, attempts.indices.contains(index) else { return }
        let duration = start.duration(to: .now).components
        attempts[index].elapsedSeconds = max(0, Double(duration.seconds) + Double(duration.attoseconds) / 1e18)
        attempts[index].failure = failure
        attempts[index].completed = true
    }
    func snapshot() -> [Attempt] { attempts }
}

@Suite("Private movie OCR diagnostic boundaries")
struct RoutineMovieOCRDiagnosticTests {
    @Test func diagnosticsExcludeUnknownDomainsAndErrorContents() throws {
        let secret = "private-content-must-not-appear"
        let values = [
            RoutineMovieOCRRecorder.Failure(NSError(domain: secret, code: 99,
                userInfo: [NSLocalizedDescriptionKey: secret])),
            RoutineMovieOCRRecorder.Failure(NSError(domain: VNErrorDomain, code: 9,
                userInfo: [NSLocalizedDescriptionKey: secret])),
            RoutineMovieOCRRecorder.Failure(CancellationError()),
            RoutineMovieOCRRecorder.Failure(NSError(domain: NSCocoaErrorDomain, code: 257,
                userInfo: [NSLocalizedDescriptionKey: secret])),
            RoutineMovieOCRRecorder.Failure(NSError(domain: NSPOSIXErrorDomain, code: 13,
                userInfo: [NSLocalizedDescriptionKey: secret]))
        ]
        let encoded = String(decoding: try JSONEncoder().encode(values), as: UTF8.self)
        #expect(!encoded.contains(secret))
        #expect(values[0].domain == .other && values[0].code == nil)
        #expect(values[1].domain == .vision && values[1].code == 9)
        #expect(values[2].domain == .cancellation && values[2].code == nil)
        #expect(values[3].domain == .cocoa && values[3].code == 257)
        #expect(values[4].domain == .posix && values[4].code == 13)
        #expect(values.allSatisfy { $0.category == nil })
    }
    @Test func swiftVisionCategoriesNeverSerializeAssociatedContents() throws {
        let secret = "private-frame-path-and-recognized-content-must-not-appear"
        let cases: [(VisionError, RoutineMovieOCRRecorder.Failure.Category)] = [
            (.dataUnavailable(secret), .dataUnavailable), (.internalError(secret), .internalError),
            (.invalidArgument(secret), .invalidArgument), (.invalidFormat(secret), .invalidFormat),
            (.invalidImage(secret), .invalidImage), (.invalidModel(secret), .invalidModel),
            (.invalidOperation(secret), .invalidOperation), (.ioError(secret), .ioError),
            (.operationFailed(secret), .operationFailed), (.outOfBoundsError(secret), .outOfBoundsError),
            (.outOfMemory(secret), .outOfMemory), (.pixelBufferCreationFailed(-666), .pixelBufferCreationFailed),
            (.requestCancelled(secret), .requestCancelled), (.timeout(secret), .timeout),
            (.timeStampNotFound(secret), .timeStampNotFound), (.unsupportedComputeDevice(secret), .unsupportedComputeDevice),
            (.unsupportedComputeStage(secret), .unsupportedComputeStage), (.unsupportedRequest(secret), .unsupportedRequest),
            (.unsupportedRevision(secret), .unsupportedRevision)]
        let values = cases.map { RoutineMovieOCRRecorder.Failure($0.0) }
        #expect(values.map(\.category) == cases.map { Optional($0.1) })
        #expect(values.allSatisfy { $0.domain == .vision && $0.code == nil })
        let encoded = String(decoding: try JSONEncoder().encode(values), as: UTF8.self)
        #expect(!encoded.contains(secret) && !encoded.contains("-666"))
    }
    @Test func recordingIsBoundedAndDistinguishesPendingFromFinished() async {
        let recorder = RoutineMovieOCRRecorder()
        let first = await recorder.started()
        #expect(await recorder.snapshot().first?.completed == false)
        #expect(await recorder.snapshot().first?.failure == nil)
        await recorder.finished(first, since: .now, failure: .init(VisionError.requestCancelled("private cancellation reason")))
        let failed = await recorder.snapshot().first
        #expect(failed?.completed == true && failed?.failure?.category == .requestCancelled)
        #expect(failed?.elapsedSeconds != nil)
        let second = await recorder.started()
        await recorder.finished(second, since: .now, failure: nil)
        let completed = await recorder.snapshot().last
        #expect(completed?.completed == true && completed?.failure == nil)
        for _ in 0..<MediaObservationService.maximumFrames { _ = await recorder.started() }
        #expect(await recorder.snapshot().count == MediaObservationService.maximumFrames)
        #expect(await recorder.started() == nil)
    }
}
