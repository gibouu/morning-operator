import Foundation
import MorningCore
import Testing
@testable import MorningApple

/// Diagnostic contrasts only. Completing this probe, including valid abstentions,
/// is not a semantic-accuracy or end-to-end product acceptance verdict.
@Suite("Opt-in source-kind and banner contrast diagnostic")
struct VisibleTaskContrastProbeTests {
    private enum Stimulus: String, Sendable {
        case original, explicitEnglish, explicitFrench

        var texts: [String] {
            switch self {
            case .original:
                // Exact bodies from the existing frozen visual positive control,
                // with only its leading SYNTHETIC line varied by the case.
                ["09:10 Inspect the workshop materials\nNotebook and pencils are on the table.",
                 "A colleague asks whether the workshop notes are ready.\nPlease review the blue folder before the meeting."]
            case .explicitEnglish:
                ["Calendar\nFriday, 16 October 2026\n10:40 Project review meeting\nPlace: West room.",
                 "Messages\nFrom: a colleague\nThe project meeting starts at 10:40. Please bring the printed agenda."]
            case .explicitFrench:
                // Matched translation of this independent toy stimulus; nothing
                // is taken from the long movie, expected activities or oracle.
                ["Calendrier\nVendredi 16 octobre 2026\n10:40 Réunion de revue du projet\nLieu : salle Ouest.",
                 "Messages\nDe : un collègue\nLa réunion de projet commence à 10:40. Apporte l’ordre du jour imprimé."]
            }
        }

        var language: String { self == .explicitFrench ? "fr" : "en" }
    }

    private struct Contrast: Sendable {
        let stimulus: Stimulus
        let kind: ObservationAcquisitionSourceKind
        let banner: Bool
        var label: String { "\(stimulus.rawValue)_\(kind.rawValue)_\(banner ? "banner" : "noBanner")" }
        var texts: [String] { stimulus.texts.map { (banner ? "SYNTHETIC\n" : "") + $0 } }
    }

    private static var contrasts: [Contrast] {
        [Stimulus.original, .explicitEnglish, .explicitFrench].flatMap { stimulus in
            [false, true].map { Contrast(stimulus: stimulus, kind: .video, banner: $0) }
        } + [false, true].map { Contrast(stimulus: .original, kind: .manual, banner: $0) }
    }

    private enum Result: String, Encodable { case proposedDraft, validatedEmpty, failed }
    private enum ProbeFailure: Error { case invalidResult }
    private struct Record: Encodable {
        let schemaVersion = 1
        let scope = "Diagnostic only: no required positive result, semantic accuracy verdict, product acceptance or provider effect. SDK invocations are not backend calls."
        let contrast: String, stimulusLanguage: String, sourceKind: String, bannerPresent: Bool
        var sourceOrigins: [String] = [], evidenceKinds: [String] = []
        var acquisitionCount = 0, unitCount = 0, plannedBatchCount = 0
        var anchorCounts: [Int] = []
        var result: Result = .failed
        var proposedStepCount: Int?
        var errorCategory: String?
        var diagnostics: RoutineProposalDiagnostics?
    }

    private struct ValidatedProposalRecord: Encodable {
        let contrast: String
        let proposal: EvidenceRoutineProposal
    }

    private func observations(for contrast: Contrast) throws -> [ObservationAcquisition] {
        let instant = Date(timeIntervalSince1970: 1_792_123_200)
        let day = try ObservationObservedDate(date: instant, timeZoneIdentifier: "UTC", provenance: .userAssigned)
        if contrast.kind == .manual {
            return try contrast.texts.map {
                try .init(importedAt: instant, observedDate: day, origin: .synthetic, sourceKind: .manual,
                    sourceLabel: "Synthetic contrast diagnostic", originalText: $0)
            }
        }
        let frames = try contrast.texts.enumerated().map {
            try ObservationFrameEvidence(requestedTimeSeconds: Double($0.offset), actualTimeSeconds: Double($0.offset),
                outcome: .observed, text: $0.element)
        }
        let video = try ObservationVideoEvidence(durationSeconds: 2, frames: frames)
        return [try .init(importedAt: instant, observedDate: day, origin: .synthetic, sourceKind: .video,
            sourceLabel: "Synthetic contrast diagnostic", originalText: video.renderedText, videoEvidence: video)]
    }

    @Test("The diagnostic varies only its declared source-kind, stimulus language and banner factors")
    func contrastsKeepNativeOriginAndSourceBytes() throws {
        #expect(Self.contrasts.count == 8)
        for contrast in Self.contrasts {
            let sources = try observations(for: contrast)
            let evidence = try LearningEvidencePreparation.prepare(acquisitions: sources)
            let prepared = try ModelCitationPreparation.prepare(evidence)
            #expect(sources.count == (contrast.kind == .manual ? 2 : 1))
            #expect(evidence.units.count == 2 && evidence.sourceSnapshots.allSatisfy { $0.origin == .synthetic })
            #expect(evidence.units.allSatisfy { $0.kind == (contrast.kind == .manual ? .userReportedActivity : .visibleTaskContent) })
            #expect(evidence.units.map(\.text) == contrast.texts)
            #expect(prepared.evidence.units == evidence.units && prepared.evidence.sourceSnapshots == evidence.sourceSnapshots)
            #expect(prepared.evidence.modelRequestCount <= 2)
            #expect(prepared.batchesByFirstUnitID.values.allSatisfy { !$0.anchors.isEmpty })
            #expect(prepared.evidence.prompts.allSatisfy {
                $0.count <= LearningEvidencePreparation.maximumBatchCharacters && $0.utf8.count <= LearningEvidencePreparation.maximumBatchUTF8Bytes
            })
        }
    }

    @Test("Compare actual local proposal outcomes without requiring a nonempty draft", .enabled(
        "Set MO_RUN_MODEL_INTEGRATION=1 and MO_RUN_VISUAL_EVIDENCE_CONTRAST=1. This is a diagnostic, not product acceptance.") {
        let environment = ProcessInfo.processInfo.environment
        return environment["MO_RUN_MODEL_INTEGRATION"] == "1" && environment["MO_RUN_VISUAL_EVIDENCE_CONTRAST"] == "1"
    })
    @MainActor
    func realLocalContrastDiagnostic() async throws {
        // One test and an awaited loop keep all eight probes serial.
        for contrast in Self.contrasts {
            try Task.checkCancellation()
            await probe(contrast)
        }
    }

    @MainActor private func probe(_ contrast: Contrast) async {
        let service = AppleIntelligenceService()
        var record = Record(contrast: contrast.label, stimulusLanguage: contrast.stimulus.language,
            sourceKind: contrast.kind.rawValue, bannerPresent: contrast.banner)
        defer {
            record.diagnostics = service.proposalDiagnostics
            let encoder = JSONEncoder(); encoder.outputFormatting = [.sortedKeys]
            if let data = try? encoder.encode(record) {
                // Only fixed input-factor labels and native metadata are logged.
                // No raw input/model text, source IDs, citations or prompts.
                print("VISUAL_EVIDENCE_CONTRAST \(String(decoding: data, as: UTF8.self))")
            } else { Issue.record("Contrast diagnostic could not be encoded.") }
        }
        do {
            let sources = try observations(for: contrast)
            let evidence = try LearningEvidencePreparation.prepare(acquisitions: sources)
            let prepared = try ModelCitationPreparation.prepare(evidence)
            record.acquisitionCount = sources.count; record.unitCount = evidence.units.count
            record.sourceOrigins = Array(Set(evidence.sourceSnapshots.map { $0.origin.rawValue })).sorted()
            record.evidenceKinds = Array(Set(evidence.units.map { $0.kind.rawValue })).sorted()
            record.plannedBatchCount = prepared.evidence.modelRequestCount
            record.anchorCounts = prepared.evidence.batches.compactMap { batch in
                batch.first.flatMap { prepared.batchesByFirstUnitID[$0.id]?.anchors.count }
            }
            guard service.isAvailable else { throw AppleIntelligenceError.unavailable("The diagnostic requires an available local model.") }
            let proposal = try await service.propose(evidence: evidence, preserving: nil)
            guard proposal.routine.isSynthetic, !proposal.routine.isApproved,
                  proposal.isCurrent(archive: try ObservationArchive(entries: sources), baseRoutine: nil) else {
                throw ProbeFailure.invalidResult
            }
            // This separate semantic-review payload contains only a natively
            // validated proposal from the constant synthetic inputs above.
            // It is not the SDK response and never enters the diagnostic DTO.
            let encoder = JSONEncoder(); encoder.outputFormatting = [.sortedKeys]
            encoder.dateEncodingStrategy = .iso8601
            let data = try encoder.encode(ValidatedProposalRecord(contrast: contrast.label, proposal: proposal))
            print("VISUAL_EVIDENCE_CONTRAST_VALIDATED_PROPOSAL \(String(decoding: data, as: UTF8.self))")
            record.result = .proposedDraft; record.proposedStepCount = proposal.routine.steps.count
        } catch RoutineEvidenceProposalError.insufficientEvidence {
            // A valid empty model result reaches assemble only after every batch
            // has returned and passed native validation. Earlier refusals fail.
            if let diagnostic = service.proposalDiagnostics, diagnostic.phase == .assembling,
               diagnostic.plannedBatchCount > 0, diagnostic.respondInvocations == diagnostic.plannedBatchCount,
               diagnostic.responseReturns == diagnostic.plannedBatchCount,
               diagnostic.validatedBatchCount == diagnostic.plannedBatchCount, diagnostic.resolvedStepCount == 0 {
                record.result = .validatedEmpty; record.proposedStepCount = 0
                record.errorCategory = "insufficientEvidence"
            } else {
                record.errorCategory = "unexpectedEvidenceRefusal"
                Issue.record("Contrast \(contrast.label) was refused before a fully validated model result.")
            }
        } catch {
            let category: String
            switch error {
            case RoutineEvidenceProposalError.invalidCitation: category = "invalidCitation"
            case RoutineEvidenceProposalError.invalidProposal: category = "invalidProposal"
            case RoutineEvidenceProposalError.inputBudgetExceeded: category = "inputBudgetExceeded"
            case RoutineEvidenceProposalError.outputBudgetExceeded: category = "outputBudgetExceeded"
            case ProbeFailure.invalidResult: category = "invalidResult"
            default: category = ObservationContextErrorSanitizer.map(error).category.rawValue
            }
            record.errorCategory = category
            Issue.record("Contrast \(contrast.label) failed: \(category).")
        }
    }
}
