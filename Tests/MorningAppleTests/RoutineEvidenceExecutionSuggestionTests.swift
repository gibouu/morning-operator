import Foundation
import MorningCore
import Testing
@testable import MorningApple

@Suite("Reviewed-video execution suggestions")
struct RoutineEvidenceExecutionSuggestionTests {
    private let instant = Date(timeIntervalSince1970: 1_760_000_000)
    private let content = "A colleague shared the complete project agenda."

    @Test("A cited exact reviewed frame proposes a concrete action before approval")
    func reviewedFrameSuggestsExecution() throws {
        for label in ["Gmail", "Apple Calendar", "Instagram"] {
            let entry = try video(labels: [label])
            let evidence = try LearningEvidencePreparation.prepare(acquisitions: [entry])
            let proposal = try assemble(evidence)
            let step = try #require(proposal.routine.steps.first)
            #expect(!proposal.routine.isApproved && !step.isRequired)
            #expect(step.observationReference == nil)
            switch label {
            case "Gmail": #expect(step.automation == .gmailInbox && step.target == nil)
            case "Apple Calendar": #expect(step.automation == .todayCalendar && step.target == nil)
            default:
                guard case let .inAppWeb(url) = step.target else { Issue.record("Expected a reviewed browser suggestion"); continue }
                #expect(WebMorningSite(url: url) == .instagram)
                #expect(step.webBehavior != nil && step.webLikesAllowed == false)
            }
            #expect(proposal.support.first?.citations.count == 1)
            #expect(proposal.isCurrent(archive: try ObservationArchive(entries: [entry]), baseRoutine: nil))
            let restored = try JSONDecoder().decode(EvidenceRoutineProposal.self, from: JSONEncoder().encode(proposal))
            #expect(restored.isCurrent(archive: try ObservationArchive(entries: [entry]), baseRoutine: nil))
        }
    }

    @Test("Model names, OCR service mentions and unreviewed frames cannot choose execution")
    func unreviewedAndUnknownStayManual() throws {
        for label in [nil, "instagram", "My Instagram", "Unknown context"] as [String?] {
            let entry = try video(labels: [label])
            let evidence = try LearningEvidencePreparation.prepare(acquisitions: [entry])
            let proposal = try assemble(evidence, title: "Gmail Instagram Calendar", kind: .calendar)
            let step = try #require(proposal.routine.steps.first)
            #expect(step.automation == nil && step.target == nil && step.webBehavior == nil && step.webLikesAllowed == nil)
            #expect(proposal.isCurrent(archive: try ObservationArchive(entries: [entry]), baseRoutine: nil))
        }
    }

    @Test("Every supporting unit must agree on the same exact reviewed context")
    func mergedSupportRequiresUnambiguousReviewedIdentity() throws {
        for labels in [["Instagram", "Gmail"], ["Instagram", nil], ["X", "Twitter"]] as [[String?]] {
            let entry = try video(labels: labels)
            let evidence = try LearningEvidencePreparation.prepare(acquisitions: [entry])
            let proposal = try assemble(evidence)
            #expect(proposal.support.first?.citations.count == 2)
            #expect(proposal.routine.steps.first?.target == nil)
            #expect(proposal.routine.steps.first?.automation == nil)
            #expect(proposal.isCurrent(archive: try ObservationArchive(entries: [entry]), baseRoutine: nil))
        }
        let entry = try video(labels: ["Instagram", "Instagram"])
        let evidence = try LearningEvidencePreparation.prepare(acquisitions: [entry])
        #expect(try assemble(evidence).routine.steps.first?.webLikesAllowed == false)
    }

    @Test("Restore rejects a different bounded action despite unchanged citations")
    func forgedBoundedActionsFailArchiveRecomputation() throws {
        let entry = try video(labels: ["Instagram"])
        let evidence = try LearningEvidencePreparation.prepare(acquisitions: [entry])
        let proposal = try assemble(evidence)
        let archive = try ObservationArchive(entries: [entry])
        var object = try payload(proposal)
        var routine = try #require(object["routine"] as? [String: Any])
        var steps = try #require(routine["steps"] as? [[String: Any]])
        steps[0]["automation"] = "gmailInbox"
        steps[0].removeValue(forKey: "target")
        steps[0].removeValue(forKey: "webBehavior")
        steps[0].removeValue(forKey: "webLikesAllowed")
        routine["steps"] = steps; object["routine"] = routine
        let forged = try JSONDecoder().decode(EvidenceRoutineProposal.self, from: JSONSerialization.data(withJSONObject: object))
        #expect(!forged.isCurrent(archive: archive, baseRoutine: nil))
        object = try payload(proposal)
        routine = try #require(object["routine"] as? [String: Any])
        steps = try #require(routine["steps"] as? [[String: Any]])
        steps[0]["webLikesAllowed"] = true
        routine["steps"] = steps; object["routine"] = routine
        let likesData = try JSONSerialization.data(withJSONObject: object)
        #expect(throws: RoutineEvidenceProposalError.invalidProposal) {
            try JSONDecoder().decode(EvidenceRoutineProposal.self, from: likesData)
        }
    }

    @Test("A reviewed header on another frame cannot lend identity to the cited frame")
    func reviewIsBoundToExactFrame() throws {
        let entry = try video(labels: ["Instagram", nil])
        let evidence = try LearningEvidencePreparation.prepare(acquisitions: [entry])
        let unit = try #require(evidence.units.last)
        let input = EvidenceRoutineStepInput(title: "Instagram", detail: "A tentative moment", kind: .entertainment,
            durationMinutes: 2, citations: [.init(unitID: unit.id, quote: content)])
        let proposal = try LearningEvidencePreparation.assemble(evidence: evidence, steps: [input], preserving: nil)
        #expect(proposal.routine.steps.first?.target == nil)
        #expect(proposal.isCurrent(archive: try ObservationArchive(entries: [entry]), baseRoutine: nil))
    }

    @Test("Preferences apply after suggestion: kept manual choices win and exclusions stay removed")
    func preferencesWin() throws {
        let entry = try video(labels: ["Instagram"])
        let evidence = try LearningEvidencePreparation.prepare(acquisitions: [entry])
        let kept = RoutineStep(title: "My selected moment", detail: "I prefer doing this myself", kind: .entertainment,
            durationMinutes: 7, isRequired: false)
        let preferences = try RoutinePreferenceJournal(entries: [RoutinePreference(target: kept, presence: .keep)], revision: UUID())
        let proposal = try assemble(evidence, preferences: preferences)
        #expect(proposal.routine.steps == [kept])
        #expect(proposal.isCurrent(archive: try ObservationArchive(entries: [entry]), baseRoutine: nil, preferences: preferences))
        let excluded = try RoutinePreferenceJournal(entries: [RoutinePreference(target: kept, presence: .exclude)], revision: UUID())
        #expect(throws: RoutineEvidenceProposalError.insufficientEvidence) {
            try assemble(evidence, preferences: excluded)
        }
    }

    private func assemble(_ evidence: PreparedLearningEvidence, title: String = "My selected moment", kind: StepKind = .entertainment,
                          preferences: RoutinePreferenceJournal? = nil) throws -> EvidenceRoutineProposal {
        // Deliberately propose one activity supported by all frames. These tests
        // check its execution suggestion, not equivalence between separate inputs.
        try LearningEvidencePreparation.assemble(evidence: evidence,
            steps: [EvidenceRoutineStepInput(title: title, detail: "A tentative moment", kind: kind, durationMinutes: 2,
                citations: evidence.units.map { .init(unitID: $0.id, quote: content) })],
            preserving: nil, preferences: preferences, at: instant)
    }

    private func video(labels: [String?]) throws -> ObservationAcquisition {
        let frames = try labels.enumerated().map { index, label in
            try ObservationFrameEvidence(requestedTimeSeconds: Double(index), actualTimeSeconds: Double(index),
                outcome: .observed, text: (label ?? "Instagram Gmail Calendar") + "\n" + content)
        }
        let video = try ObservationVideoEvidence(durationSeconds: Double(frames.count + 1), frames: frames)
        let reviews = try labels.enumerated().compactMap { index, label -> ObservationFrameReview? in
            guard let label else { return nil }
            return try ObservationFrameReview(sampleID: frames[index].id, label: label, evidenceQuote: label, reviewedAt: instant)
        }
        return try ObservationAcquisition(importedAt: instant,
            observedDate: ObservationObservedDate(date: instant, timeZoneIdentifier: "Europe/Paris", provenance: .userAssigned),
            origin: .human, sourceKind: .video, sourceLabel: "Synthetic reviewed video test",
            originalText: video.renderedText, videoEvidence: video, frameReviews: reviews)
    }

    private func payload(_ proposal: EvidenceRoutineProposal) throws -> [String: Any] {
        let encoded = try JSONEncoder().encode(proposal)
        return try #require(JSONSerialization.jsonObject(with: encoded) as? [String: Any])
    }
}
