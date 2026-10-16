import Foundation
import MorningCore
import Testing
@testable import MorningApple

@Suite("Observed provenance never substitutes for task evidence")
struct ObservedTextRolePolicyTests {
    @Test(arguments: ["No real account, send, write or like", "OFFLINE STORYBOARD • NOT NATIVE CAPTURE",
        "Invented content · no audio · no external service", "Contenu fictif · sans audio · aucun service externe"])
    func visibleDisclaimerDoesNotEraseTheTaskOnTheSameFrame(_ disclaimer: String) throws {
        let task = "09:15 Prepare eight green cards in the Cedar Room"
        let text = disclaimer + "\nHarbor Calendar\n" + task
        let units = try LearningEvidencePolicy.prepare(frames: [text])
        #expect(units.count == 1 && units[0].text.utf8.elementsEqual(text.utf8))
        #expect(!LearningEvidencePolicy.supports(quote: disclaimer, source: text, context: text,
            kind: .visibleTaskContent, claimedKind: LearningEvidenceKind.visibleTaskContent.rawValue))
        #expect(LearningEvidencePolicy.supports(quote: task, source: text, context: text,
            kind: .visibleTaskContent, claimedKind: LearningEvidenceKind.visibleTaskContent.rawValue))
        #expect(throws: AppleIntelligenceError.insufficientActivityEvidence) { try LearningEvidencePolicy.prepare(frames: [disclaimer]) }
    }

    @Test(arguments: ["No real account, send, write or like", "OFFLINE STORYBOARD • NOT NATIVE CAPTURE",
        "Invented content · no audio · no external service", "Contenu fictif · sans audio · aucun service externe"])
    func preparedAnchorsAndFinalValidationShareTheNegativeRole(_ disclaimer: String) throws {
        let task = "09:15 Prepare eight green cards in the Cedar Room"
        let text = disclaimer + "\nHarbor Calendar\n" + task
        let frame = try ObservationFrameEvidence(requestedTimeSeconds: 0, actualTimeSeconds: 0, outcome: .observed, text: text)
        let video = try ObservationVideoEvidence(durationSeconds: 1, frames: [frame])
        let source = try ObservationAcquisition(observedDate: .init(date: Date(timeIntervalSince1970: 1_792_123_200),
            timeZoneIdentifier: "Europe/Paris", provenance: .userAssigned), origin: .synthetic, sourceKind: .video,
            sourceLabel: "Synthetic role boundary", originalText: video.renderedText, videoEvidence: video)
        let evidence = try LearningEvidencePreparation.prepare(acquisitions: [source])
        let unit = try #require(evidence.units.first)
        let anchored = try ModelCitationPreparation.prepare(evidence)
        let batch = try #require(anchored.batchesByFirstUnitID.values.first)
        #expect(batch.units[0].text == unit.text && unit.text == text)
        #expect(batch.prompt.contains(disclaimer) && batch.anchors.count == 1)
        #expect(!batch.anchors.contains { $0.citation.quote.trimmingCharacters(in: .whitespacesAndNewlines) == disclaimer })
        #expect(batch.anchors.contains { $0.citation.quote == task })
        let forged = EvidenceRoutineStepInput(title: "Review the calendar", detail: "Tentative review of visible calendar content.",
            kind: .calendar, durationMinutes: 2, citations: [.init(unitID: unit.id, quote: disclaimer)])
        #expect(throws: RoutineEvidenceProposalError.invalidCitation) { try LearningEvidencePreparation.validateBatchResult([forged], units: [unit]) }
        #expect(throws: RoutineEvidenceProposalError.invalidCitation) { try LearningEvidencePreparation.assemble(evidence: evidence, steps: [forged], preserving: nil) }
    }

    @Test func fictionalDisclosureKeepsNearbyTaskTextAndWrittenReports() {
        for line in ["Invented content · no audio · no external service",
                     "Fictional data — without sound or network", "Contenu inventé · sans son ni service externe"] {
            #expect(ObservedTextRolePolicy.isPureProvenance(line))
            let text = line + "\n09:15 Review the workshop materials"
            #expect(!ObservedTextRolePolicy.isPureProvenance(text))
            #expect(LearningEvidencePolicy.supports(quote: text, source: text, context: text,
                kind: .visibleTaskContent, claimedKind: LearningEvidenceKind.visibleTaskContent.rawValue))
            #expect(LearningEvidencePolicy.supports(quote: line, source: line, context: line,
                kind: .userReportedActivity, claimedKind: LearningEvidenceKind.userReportedActivity.rawValue))
        }
        for text in ["Invented Content Studio", "Fictional data reader without audio",
                     "Invented content · no audio · review the budget report",
                     "Contenu fictif · sans audio · relire le message du projet"] {
            #expect(!ObservedTextRolePolicy.isPureProvenance(text))
        }
    }

    @Test func ordinaryNamesAndCloseTaskSentencesAreNotBlacklisted() {
        for text in ["Synthetic Studio", "Test Kitchen", "Demo Reader", "Cedar News • Browser SIMULATED",
                     "Offline Journal", "Native Instruments", "Storyboard Studio",
                     "No real account was changed; review the project notes."] {
            #expect(!ObservedTextRolePolicy.isProvenanceLine(text))
        }
        let task = "No real account was changed; review the project notes."
        #expect(LearningEvidencePolicy.supports(quote: task, source: task, context: task,
            kind: .visibleTaskContent, claimedKind: LearningEvidenceKind.visibleTaskContent.rawValue))
        // Written reports have their existing separate provenance contract.
        let disclaimer = "No real account, send, write or like"
        #expect(LearningEvidencePolicy.supports(quote: disclaimer, source: disclaimer, context: disclaimer,
            kind: .userReportedActivity, claimedKind: LearningEvidenceKind.userReportedActivity.rawValue))
    }
}
