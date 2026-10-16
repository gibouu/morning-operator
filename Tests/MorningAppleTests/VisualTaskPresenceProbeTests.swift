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
        try await runProbe(flatStepsFirst: false)
    }

    @Test(.enabled("Set MO_RUN_MODEL_INTEGRATION=1 and MO_RUN_VISUAL_TASK_FLAT_SELECTION_PROBE=1 with explicit private paths.") {
        let env = ProcessInfo.processInfo.environment
        return env["MO_RUN_MODEL_INTEGRATION"] == "1" && env["MO_RUN_VISUAL_TASK_FLAT_SELECTION_PROBE"] == "1"
    })
    @MainActor func compareFlatStepsBeforeAnExplicitDecision() async throws {
        try await runProbe(flatStepsFirst: true)
    }

    @MainActor private func runProbe(flatStepsFirst: Bool) async throws {
        #if canImport(FoundationModels)
        let env = ProcessInfo.processInfo.environment
        let inputPath = try #require(env["MO_TASK_PRESENCE_SOURCE_REPORT_PATH"])
        let videoPath = try #require(env["MO_TASK_PRESENCE_VIDEO_PATH"])
        let outputKey = flatStepsFirst ? "MO_TASK_FLAT_SELECTION_REPORT_PATH" : "MO_TASK_PRESENCE_REPORT_PATH"
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
        if flatStepsFirst {
            report.mode = "diagnostic-flat-steps-before-explicit-outcome-not-proposal"
            report.scope = "Same three synthetic acquisitions, retained production instruction bytes and anchored-input builder. Experimental test-only selection schema generates zero to four steps before an obligatory explicit outcome, with unchanged step hints and supplied qN IDs, at the production 1100-token response limit. The ordinary strict envelope decoder, anchor resolver and batch policy reject contradictions; no decision is derived or repaired from cardinality. No routine is assembled, approved or executed. A nonempty validated selection still requires independent semantic review, and the advertisement must be explicitly excluded. No oracle, account, provider or raw response is logged. Fresh unit IDs do not establish byte identity with historical SDK requests."
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
                let schema = try flatStepsFirst
                    ? Self.flatSelectionSchema(citationIDs: batch.anchors.map(\.id))
                    : Self.schema(citationIDs: batch.anchors.map(\.id))
                var record = PresenceCase(label: label, sourceKind: acquisition.sourceKind.rawValue,
                    origin: acquisition.origin.rawValue, unitCount: units.count, anchorCount: batch.anchors.count,
                    promptSHA256: Self.digest(Data(batch.prompt.utf8)), promptUTF8Bytes: batch.prompt.utf8.count,
                    schemaSHA256: Self.digest(try JSONEncoder().encode(schema)))
                let session = LanguageModelSession(model: SystemLanguageModel.default, instructions: instructions)
                report.respondInvocations += 1
                do {
                    let response = try await session.respond(to: batch.prompt, schema: schema,
                        options: GenerationOptions(temperature: 0, maximumResponseTokens: flatStepsFirst ? 1_100 : 200))
                    report.responseReturns += 1
                    try Task.checkCancellation()
                    let bytes = Data(response.content.jsonString.utf8)
                    if flatStepsFirst {
                        record.nativeSelectionValidated = false
                        let returned = try FlatSelectionResponse(bytes: bytes)
                        record.explicitOutcome = RoutineProposalDiagnostics.Outcome(rawValue: returned.selection.outcome) ?? .unrecognized
                        record.returnedStepCount = returned.selection.steps.count
                        record.validatedSelection = try returned.validated(in: batch)
                        record.nativeSelectionValidated = true
                        if label == "existingAdvertisementControl" {
                            let excluded = returned.selection.outcome == "insufficientEvidence" && returned.selection.steps.isEmpty
                            record.advertisementExplicitlyExcluded = excluded
                            guard excluded else { throw ProbeFailure.advertisementNotExcluded }
                        }
                    } else {
                        let value = try JSONDecoder().decode(PresenceAnswer.self, from: bytes)
                        guard !value.description.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
                              value.description.count <= 160, value.description.utf8.count <= 640,
                              value.citationID == nil || batch.anchors.contains(where: { $0.id == value.citationID }) else { throw ProbeFailure.invalidDiagnostic }
                        record.answer = value // Parsed diagnostic only; no assembly.
                    }
                } catch {
                    if case .advertisementNotExcluded? = error as? ProbeFailure { record.errorCategory = "advertisementNotExcluded" }
                    else { record.errorCategory = error is ProbeFailure ? "invalidDiagnostic" : ObservationContextErrorSanitizer.map(error).category.rawValue }
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
        let prefix = flatStepsFirst ? "VISUAL_TASK_FLAT_SELECTION_REPORT_SAVED" : "VISUAL_TASK_PRESENCE_REPORT_SAVED"
        print("\(prefix) status=\(report.status)")
        #expect(report.status == "diagnosticCompleted", "Errors or an advertised activity fail; a nonempty selection or Boolean answer is not product acceptance.")
        #else
        Issue.record("The explicitly requested diagnostic needs the local Foundation Models SDK.")
        #endif
    }

    @Test("The flat diagnostic never repairs an explicit outcome or bypasses citation policy")
    func flatSelectionPreservesDecisionsAndRejectsContradictions() throws {
        let acquisition = try ObservationAcquisition(
            observedDate: .init(date: Date(timeIntervalSince1970: 1_792_123_200), timeZoneIdentifier: "UTC", provenance: .userAssigned),
            origin: .synthetic, sourceKind: .manual, sourceLabel: "Flat decoder contract",
            originalText: "I review the project agenda after breakfast.")
        let prepared = try ModelCitationPreparation.prepare(LearningEvidencePreparation.prepare(acquisitions: [acquisition]))
        let batch = try #require(prepared.batchesByFirstUnitID.values.first), id = try #require(batch.anchors.first?.id)
        func response(outcome: String, ids: [String]) throws -> Data {
            let steps: [[String: Any]] = ids.map {
                ["citationIDs": [$0], "kind": "custom", "title": "Review the agenda", "durationMinutes": 2]
            }
            return try JSONSerialization.data(withJSONObject: ["selection": ["steps": steps, "outcome": outcome]])
        }
        for (outcome, ids) in [("insufficientEvidence", [String]()), ("supportedActivities", [id])] {
            let value = try FlatSelectionResponse(bytes: response(outcome: outcome, ids: ids))
            #expect(value.selection.outcome == outcome && value.selection.steps.count == ids.count)
            let checked = try value.validated(in: batch)
            #expect(checked.count == ids.count)
            if let step = checked.first {
                #expect(step.citationIDs == [id] && step.quotes == [batch.anchors[0].citation.quote])
            }
        }
        for (outcome, ids) in [("insufficientEvidence", [id]), ("supportedActivities", []),
                                ("unknown", []), ("supportedActivities", ["forged"]),
                                ("supportedActivities", Array(repeating: id, count: 5))] {
            let bytes = try response(outcome: outcome, ids: ids)
            let value = try FlatSelectionResponse(bytes: bytes)
            #expect(value.selection.outcome == outcome && value.selection.steps.count == ids.count)
            #expect(throws: (any Error).self) { try value.validated(in: batch) }
        }
        // Unknown envelope fields remain the strict decoder's refusal; parsing
        // diagnostic counts first cannot strip the field to make it pass.
        let legitimate = try response(outcome: "supportedActivities", ids: [id])
        var extra = try #require(JSONSerialization.jsonObject(with: legitimate) as? [String: Any])
        extra["approval"] = true
        let extraBytes = try JSONSerialization.data(withJSONObject: extra)
        let extraValue = try FlatSelectionResponse(bytes: extraBytes)
        #expect(throws: RoutineEvidenceProposalError.invalidProposal) { try extraValue.validated(in: batch) }
    }

    #if canImport(FoundationModels)
    // Experimental schema stays exclusively in this test. Production union42
    // and its decision/cardinality validator are unchanged.
    private static func flatSelectionSchema(citationIDs: [String]) throws -> GenerationSchema {
        let citation = DynamicGenerationSchema(name: "SuppliedCitationID", anyOf: citationIDs)
        let kind = DynamicGenerationSchema(name: "EvidenceStepKind", anyOf: StepKind.allCases.map(\.rawValue))
        let outcome = DynamicGenerationSchema(name: "ExplicitEvidenceOutcome", anyOf: ["insufficientEvidence", "supportedActivities"])
        let step = DynamicGenerationSchema(name: "CitedRoutineStep", properties: [
            .init(name: "citationIDs", description: "Select exactly one inserted ID of actual supporting task content or reported activity; never generic controls or labels.", schema: .init(arrayOf: .init(referenceTo: "SuppliedCitationID"), minimumElements: 1, maximumElements: 1)),
            .init(name: "kind", description: EvidenceRoutineFieldGuidance.kind, schema: .init(referenceTo: "EvidenceStepKind")),
            .init(name: "title", description: EvidenceRoutineFieldGuidance.title, schema: .init(type: String.self)),
            .init(name: "durationMinutes", description: EvidenceRoutineFieldGuidance.duration, schema: .init(type: Int.self, guides: [.range(1...60)]))
        ])
        let selection = DynamicGenerationSchema(name: "EvidenceSelection", description: EvidenceRoutineFieldGuidance.selection, properties: [
            .init(name: "steps", schema: .init(arrayOf: .init(referenceTo: "CitedRoutineStep"), minimumElements: 0, maximumElements: 4)),
            .init(name: "outcome", schema: .init(referenceTo: "ExplicitEvidenceOutcome"))
        ])
        let root = DynamicGenerationSchema(name: "CitedRoutineProposal", properties: [
            .init(name: "selection", schema: .init(referenceTo: "EvidenceSelection"))
        ])
        return try GenerationSchema(root: root, dependencies: [citation, kind, outcome, step, selection])
    }

    @Test("The flat diagnostic retains explicit outcomes, both empty and cited selections, and the original step hints")
    func flatDiagnosticSchemaRetainsTheExistingFieldsAndLimits() throws {
        let bytes = try JSONEncoder().encode(Self.flatSelectionSchema(citationIDs: ["q1", "q2"]))
        let value = try JSONSerialization.jsonObject(with: bytes)
        func objects(_ value: Any) -> [[String: Any]] {
            if let dictionary = value as? [String: Any] { return [dictionary] + dictionary.values.flatMap(objects) }
            if let array = value as? [Any] { return array.flatMap(objects) }
            return []
        }
        let nodes = objects(value)
        let fields = try #require(nodes.first { $0["outcome"] != nil && $0["steps"] != nil })
        #expect(Set(fields.keys) == ["steps", "outcome"])
        let steps = try #require(fields["steps"] as? [String: Any])
        #expect(steps["minItems"] as? Int == 0 && steps["maxItems"] as? Int == 4)
        #expect(nodes.contains { ($0["enum"] as? [String]) == ["insufficientEvidence", "supportedActivities"] })
        let step = try #require(nodes.first { $0["citationIDs"] != nil && $0["durationMinutes"] != nil })
        #expect(Set(step.keys) == ["citationIDs", "kind", "title", "durationMinutes"])
        for (name, hint) in [("kind", EvidenceRoutineFieldGuidance.kind), ("title", EvidenceRoutineFieldGuidance.title),
                             ("durationMinutes", EvidenceRoutineFieldGuidance.duration)] {
            #expect((step[name] as? [String: Any])?["description"] as? String == hint)
        }
        let citations = try #require(step["citationIDs"] as? [String: Any])
        #expect(citations["minItems"] as? Int == 1 && citations["maxItems"] as? Int == 1)
        #expect(nodes.contains { ($0["enum"] as? [String]) == ["q1", "q2"] })
        #expect(!nodes.contains { $0["actualTaskPresent"] != nil || $0["detail"] != nil })
    }

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
    var explicitOutcome: RoutineProposalDiagnostics.Outcome?, returnedStepCount: Int?
    var nativeSelectionValidated: Bool?, validatedSelection: [FlatValidatedStep]?
    var advertisementExplicitlyExcluded: Bool?
}
private struct PresenceReport: Encodable {
    var mode = "diagnostic-task-presence-not-proposal"
    let schemaVersion = 1, createdAt = Date()
    var scope = "Production instruction bytes and anchored-input builder, deliberately different output schema/task. Fresh unit IDs do not establish byte identity with a historical SDK submission. A short model declaration is not its internal cause, a validated routine, OCR authenticity or execution proof. All sources are synthetic. No oracle, prompt/raw response logging, assembly, approval, provider or account."
    var status = "failed", elapsedSeconds = 0.0, respondInvocations = 0, responseReturns = 0, failedCases = 0
    var inputReportSHA256: String?, instructionSHA256: String?, instructionLanguage: String?, instructionUTF8Bytes: Int?
    var fingerprint: ObservationFileFingerprint?, cases: [PresenceCase] = [], errorCategory: String?
}
private enum ProbeFailure: Error { case invalidInput, modelUnavailable, invalidDiagnostic, reportNotSaved, advertisementNotExcluded }

// Only the test's parseable diagnostic fields are retained before validation.
// The original bytes go to the original decoder: no outcome or step repair.
private struct FlatSelectionResponse {
    let selection: EvidenceModelRoutineProposal
    private let bytes: Data
    init(bytes: Data) throws {
        guard bytes.count <= 32 * 1_024,
              let root = try JSONSerialization.jsonObject(with: bytes) as? [String: Any],
              let returned = root["selection"] as? [String: Any] else { throw ProbeFailure.invalidDiagnostic }
        selection = try JSONDecoder().decode(EvidenceModelRoutineProposal.self,
            from: JSONSerialization.data(withJSONObject: returned))
        self.bytes = bytes
    }
    func validated(in batch: ModelCitationPreparation.Batch) throws -> [FlatValidatedStep] {
        let exact = try JSONDecoder().decode(GroundedRoutineSelection.self, from: bytes).selection
        let resolved = try exact.resolvedSteps(in: batch)
        try LearningEvidencePreparation.validateBatchResult(resolved, units: batch.units)
        return zip(exact.steps, resolved).map { model, source in
            .init(title: source.title, kind: source.kind.rawValue, durationMinutes: source.durationMinutes,
                  citationIDs: model.citationIDs, quotes: source.citations.map(\.quote))
        }
    }
}
private struct FlatValidatedStep: Encodable {
    let title: String, kind: String, durationMinutes: Int, citationIDs: [String], quotes: [String]
}
