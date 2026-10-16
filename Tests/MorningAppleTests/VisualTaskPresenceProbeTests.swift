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
        try await runProbe(assessmentBeforeSelection: false)
    }

    @Test(.enabled("Set MO_RUN_MODEL_INTEGRATION=1 and MO_RUN_VISUAL_TASK_SELECTION_PROBE=1 with explicit private paths.") {
        let env = ProcessInfo.processInfo.environment
        return env["MO_RUN_MODEL_INTEGRATION"] == "1" && env["MO_RUN_VISUAL_TASK_SELECTION_PROBE"] == "1"
    })
    @MainActor func compareAssessmentBeforeTheUnchangedExplicitSelection() async throws {
        try await runProbe(assessmentBeforeSelection: true)
    }

    @MainActor private func runProbe(assessmentBeforeSelection: Bool) async throws {
        #if canImport(FoundationModels)
        let env = ProcessInfo.processInfo.environment
        let inputPath = try #require(env["MO_TASK_PRESENCE_SOURCE_REPORT_PATH"])
        let videoPath = try #require(env["MO_TASK_PRESENCE_VIDEO_PATH"])
        let outputKey = assessmentBeforeSelection ? "MO_TASK_SELECTION_REPORT_PATH" : "MO_TASK_PRESENCE_REPORT_PATH"
        let outputPath = try #require(env[outputKey])
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
        if assessmentBeforeSelection {
            report.mode = "diagnostic-assessment-before-explicit-selection-not-proposal"
            report.scope = "Same three synthetic acquisitions, production instruction bytes and anchored-input builder as the task-presence probe. The output schema adds the same assessment before the unchanged production selection union; the response limit is the production 1100 tokens. A short model declaration is not its internal cause. Explicit outcome and step count are never repaired from the assessment. Only selection fields passing the existing decoder, anchor resolver and batch policy are retained as validated. No routine is assembled, approved or executed. No oracle, account, provider or raw SDK response. Fresh unit IDs do not prove byte identity with a historical request."
        }
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
                let ids = batch.anchors.map(\.id)
                let schema = try assessmentBeforeSelection
                    ? EvidenceRoutineGenerationSchema.make(citationIDs: ids, assessment: Self.assessment(citationIDs: ids))
                    : Self.schema(citationIDs: ids)
                var record = PresenceCase(label: label, sourceKind: acquisition.sourceKind.rawValue,
                    origin: acquisition.origin.rawValue, unitCount: units.count, anchorCount: batch.anchors.count,
                    promptSHA256: Self.digest(Data(batch.prompt.utf8)), promptUTF8Bytes: batch.prompt.utf8.count,
                    schemaSHA256: Self.digest(try JSONEncoder().encode(schema)))
                let session = LanguageModelSession(model: SystemLanguageModel.default, instructions: instructions)
                report.respondInvocations += 1
                do {
                    let response = try await session.respond(to: batch.prompt, schema: schema,
                        options: GenerationOptions(temperature: 0, maximumResponseTokens: assessmentBeforeSelection ? 1_100 : 200))
                    report.responseReturns += 1
                    try Task.checkCancellation()
                    let bytes = Data(response.content.jsonString.utf8)
                    if assessmentBeforeSelection {
                        record.nativeSelectionValidated = false
                        let returned = try AssessedSelectionResponse(bytes: bytes, batch: batch)
                        record.answer = returned.answer
                        record.explicitOutcome = RoutineProposalDiagnostics.Outcome(rawValue: returned.selection.outcome) ?? .unrecognized
                        record.returnedStepCount = returned.selection.steps.count
                        // Pass precisely the returned selection to the original strict
                        // envelope decoder. Assessment never replaces its decision.
                        record.validatedSelection = try returned.validated(in: batch)
                        record.nativeSelectionValidated = true
                    } else {
                        let value = try JSONDecoder().decode(PresenceAnswer.self, from: bytes)
                        try value.validate(in: batch)
                        record.answer = value // Parsed diagnostic only; no assembly.
                    }
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
        let prefix = assessmentBeforeSelection ? "VISUAL_TASK_SELECTION_REPORT_SAVED" : "VISUAL_TASK_PRESENCE_REPORT_SAVED"
        print("\(prefix) status=\(report.status)")
        #expect(report.status == "diagnosticCompleted", "A diagnostic error is a failure; either Boolean answer alone is not product acceptance.")
        #else
        Issue.record("The explicitly requested diagnostic needs the local Foundation Models SDK.")
        #endif
    }

    @Test("The contrast preserves a differing assessment and explicit decision without repairing either")
    func assessmentDoesNotChooseOrRepairTheSelection() throws {
        let batch = try Self.validationBatch()
        let id = try #require(batch.anchors.first?.id)
        for (present, outcome, ids) in [(true, "insufficientEvidence", [String]()),
                                        (false, "supportedActivities", [id])] {
            let bytes = try Self.assessedResponse(present: present, outcome: outcome, ids: ids)
            let response = try AssessedSelectionResponse(bytes: bytes, batch: batch)
            let validated = try response.validated(in: batch)
            #expect(response.answer.actualTaskPresent == present && response.selection.outcome == outcome)
            #expect(response.selection.steps.count == ids.count && validated.count == ids.count)
            if let step = validated.first {
                #expect(step.citationIDs == [id] && step.quotes == [batch.anchors[0].citation.quote])
            }
        }
        for (outcome, ids) in [("insufficientEvidence", [id]), ("supportedActivities", []),
                                ("unsupportedDecision", []), ("supportedActivities", ["not-supplied"])] {
            let bytes = try Self.assessedResponse(present: true, outcome: outcome, ids: ids)
            let response = try AssessedSelectionResponse(bytes: bytes, batch: batch)
            #expect(response.selection.outcome == outcome && response.selection.steps.count == ids.count)
            #expect(throws: (any Error).self) { try response.validated(in: batch) }
        }
    }

    private static func validationBatch() throws -> ModelCitationPreparation.Batch {
        let acquisition = try ObservationAcquisition(
            observedDate: .init(date: Date(timeIntervalSince1970: 1_792_123_200), timeZoneIdentifier: "UTC", provenance: .userAssigned),
            origin: .synthetic, sourceKind: .manual, sourceLabel: "Diagnostic decoder contract",
            originalText: "I review the project agenda after breakfast.")
        let prepared = try ModelCitationPreparation.prepare(LearningEvidencePreparation.prepare(acquisitions: [acquisition]))
        return try #require(prepared.batchesByFirstUnitID.values.first)
    }

    private static func assessedResponse(present: Bool, outcome: String, ids: [String]) throws -> Data {
        let rows: [[String: Any]] = ids.map {
            ["citationIDs": [$0], "kind": "custom", "title": "Review the agenda", "durationMinutes": 2]
        }
        return try JSONSerialization.data(withJSONObject: [
            "assessment": ["actualTaskPresent": present, "category": "taskContent", "description": "Observable task content."],
            "selection": ["outcome": outcome, "steps": rows]
        ])
    }

    #if canImport(FoundationModels)
    private static func schema(citationIDs: [String]) throws -> GenerationSchema {
        let value = assessment(citationIDs: citationIDs)
        return try GenerationSchema(root: value.schema, dependencies: value.dependencies)
    }

    private static func assessment(citationIDs: [String]) -> (schema: DynamicGenerationSchema, dependencies: [DynamicGenerationSchema]) {
        let citations = DynamicGenerationSchema(name: "PresenceCitationID", anyOf: citationIDs)
        let categories = DynamicGenerationSchema(name: "PresenceCategory", anyOf: PresenceCategory.allCases.map(\.rawValue))
        let root = DynamicGenerationSchema(name: "TaskPresenceDiagnostic", description:
            "Diagnostic output only, not a routine. Report whether concrete task content can support tentative review under the supplied policy. Do not give internal reasoning or propose any action.", properties: [
                .init(name: "actualTaskPresent", schema: .init(type: Bool.self)),
                .init(name: "citationID", description: "Optional supplied ID of an excerpt relevant to this diagnostic decision; never invent an ID.", schema: .init(referenceTo: "PresenceCitationID"), isOptional: true),
                .init(name: "category", schema: .init(referenceTo: "PresenceCategory")),
                .init(name: "description", description: "One brief observable reason, at most 160 characters. No internal reasoning.", schema: .init(type: String.self))
            ])
        return (root, [citations, categories])
    }

    @Test("An absent diagnostic leaves the canonical product schema unchanged, including the empty-anchor case", arguments: [[], ["q1", "q2"]])
    func nilAssessmentDoesNotChangeTheProductSchema(_ ids: [String]) throws {
        let encoder = JSONEncoder(); encoder.outputFormatting = .sortedKeys
        let ordinary = try encoder.encode(EvidenceRoutineGenerationSchema.make(citationIDs: ids))
        let absent = try encoder.encode(EvidenceRoutineGenerationSchema.make(citationIDs: ids, assessment: nil))
        #expect(ordinary == absent)
        let added = try encoder.encode(EvidenceRoutineGenerationSchema.make(citationIDs: ids,
            assessment: Self.assessment(citationIDs: ids.isEmpty ? ["q1"] : ids)))
        let baseline = try JSONSerialization.jsonObject(with: ordinary)
        let contrast = try JSONSerialization.jsonObject(with: added)
        // Remove only the newly added diagnostic property/dependencies for a
        // canonical equality proof of the complete retained selection schema.
        #expect(try Self.canonical(baseline) == Self.canonical(Self.removingAssessment(contrast)))
    }

    private static func canonical(_ value: Any) throws -> Data {
        try JSONSerialization.data(withJSONObject: value, options: .sortedKeys)
    }

    private static func removingAssessment(_ value: Any) -> Any {
        if let dictionary = value as? [String: Any] {
            var result = dictionary
            for key in ["TaskPresenceDiagnostic", "PresenceCitationID", "PresenceCategory"] { result.removeValue(forKey: key) }
            if var properties = result["properties"] as? [String: Any] {
                properties.removeValue(forKey: "assessment"); result["properties"] = properties
            }
            if let required = result["required"] as? [String] {
                result["required"] = required.filter { $0 != "assessment" }
            }
            return result.mapValues(removingAssessment)
        }
        if let array = value as? [Any] { return array.map(removingAssessment) }
        return value
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
private struct PresenceAnswer: Codable {
    let actualTaskPresent: Bool, citationID: String?, category: PresenceCategory, description: String
    func validate(in batch: ModelCitationPreparation.Batch) throws {
        guard !description.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
              description.count <= 160, description.utf8.count <= 640,
              citationID == nil || batch.anchors.contains(where: { $0.id == citationID }) else { throw ProbeFailure.invalidDiagnostic }
    }
}
private struct PresenceInput: Decodable {
    let schemaVersion: Int, mode: String?
    let fingerprint: ObservationFileFingerprint, videoEvidence: ObservationVideoEvidence
    let acquisition: ObservationAcquisition, classification: ObservationContextClassification?
}
private struct PresenceCase: Encodable {
    let label: String, sourceKind: String, origin: String, unitCount: Int, anchorCount: Int
    let promptSHA256: String, promptUTF8Bytes: Int, schemaSHA256: String
    var answer: PresenceAnswer?, errorCategory: String?
    var explicitOutcome: RoutineProposalDiagnostics.Outcome?, returnedStepCount: Int?
    var nativeSelectionValidated: Bool?, validatedSelection: [ValidatedProbeStep]?
}
private struct PresenceReport: Encodable {
    var mode = "diagnostic-task-presence-not-proposal"
    let schemaVersion = 1, createdAt = Date()
    var scope = "Production instruction bytes and anchored-input builder, deliberately different output schema/task. Fresh unit IDs do not establish byte identity with a historical SDK submission. A short model declaration is not its internal cause, a validated routine, OCR authenticity or execution proof. All sources are synthetic. No oracle, prompt/raw response logging, assembly, approval, provider or account."
    var status = "failed", elapsedSeconds = 0.0, respondInvocations = 0, responseReturns = 0, failedCases = 0
    var inputReportSHA256: String?, instructionSHA256: String?, instructionLanguage: String?, instructionUTF8Bytes: Int?
    var fingerprint: ObservationFileFingerprint?, cases: [PresenceCase] = [], errorCategory: String?
}
private enum ProbeFailure: Error { case invalidInput, modelUnavailable, invalidDiagnostic, reportNotSaved }

// The test-only envelope extracts the returned selection verbatim as a JSON
// value. Its explicit outcome/steps are still decoded by the product decoder;
// no assessment Boolean, inferred cardinality or fallback can replace them.
private struct AssessedSelectionResponse {
    let answer: PresenceAnswer, selection: EvidenceModelRoutineProposal
    private let wrappedSelection: Data

    init(bytes: Data, batch: ModelCitationPreparation.Batch) throws {
        guard bytes.count <= 32 * 1_024,
              let object = try JSONSerialization.jsonObject(with: bytes) as? [String: Any],
              Set(object.keys) == ["assessment", "selection"],
              let assessment = object["assessment"] as? [String: Any],
              Set(assessment.keys).isSubset(of: ["actualTaskPresent", "citationID", "category", "description"]),
              ["actualTaskPresent", "category", "description"].allSatisfy({ assessment[$0] != nil }),
              let returned = object["selection"] as? [String: Any] else { throw ProbeFailure.invalidDiagnostic }
        let decoder = JSONDecoder()
        answer = try decoder.decode(PresenceAnswer.self, from: JSONSerialization.data(withJSONObject: assessment))
        try answer.validate(in: batch)
        selection = try decoder.decode(EvidenceModelRoutineProposal.self, from: JSONSerialization.data(withJSONObject: returned))
        wrappedSelection = try JSONSerialization.data(withJSONObject: ["selection": returned])
    }

    func validated(in batch: ModelCitationPreparation.Batch) throws -> [ValidatedProbeStep] {
        let exact = try JSONDecoder().decode(GroundedRoutineSelection.self, from: wrappedSelection).selection
        let steps = try exact.resolvedSteps(in: batch)
        try LearningEvidencePreparation.validateBatchResult(steps, units: batch.units)
        return zip(exact.steps, steps).map { model, resolved in
            .init(title: resolved.title, kind: resolved.kind.rawValue, durationMinutes: resolved.durationMinutes,
                  citationIDs: model.citationIDs, quotes: resolved.citations.map(\.quote))
        }
    }
}

private struct ValidatedProbeStep: Encodable {
    let title: String, kind: String, durationMinutes: Int, citationIDs: [String], quotes: [String]
}
