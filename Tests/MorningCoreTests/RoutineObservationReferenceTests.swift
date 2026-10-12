import Foundation
import Testing
@testable import MorningCore

@Suite("Reviewed observation references")
struct RoutineObservationReferenceTests {
    @Test func validReferenceRoundTripsWithoutChangingExactQuote() throws {
        for isSynthetic in [false, true] {
            let reference = try RoutineObservationReference(acquisitionID: UUID(), revisionSHA256: String(repeating: "A", count: 64),
                frameID: UUID(), quote: "  Cafe\u{0301} — exact source  ", isSynthetic: isSynthetic)
            let restored = try JSONDecoder().decode(RoutineObservationReference.self, from: JSONEncoder().encode(reference))
            #expect(restored == reference)
            #expect(restored.quote.utf8.elementsEqual(reference.quote.utf8))
            #expect(restored.revisionSHA256 == String(repeating: "a", count: 64))
            #expect(restored.isSynthetic == isSynthetic)
        }
    }

    @Test func invalidReferenceAndMalformedDecodeAreRejected() throws {
        for digest in ["", String(repeating: "x", count: 64), String(repeating: "a", count: 63)] {
            #expect(throws: RoutineObservationReferenceError.invalidRevision) {
                try RoutineObservationReference(acquisitionID: UUID(), revisionSHA256: digest, quote: "Exact line")
            }
        }
        for quote in ["", "   ", "First\nSecond", String(repeating: "a", count: 501), "a" + String(repeating: "\u{0301}", count: 2_001)] {
            #expect(throws: RoutineObservationReferenceError.invalidQuote) {
                try RoutineObservationReference(acquisitionID: UUID(), revisionSHA256: String(repeating: "b", count: 64), quote: quote)
            }
        }
        let reference = try RoutineObservationReference(acquisitionID: UUID(), revisionSHA256: String(repeating: "b", count: 64), quote: "Exact line")
        var json = try #require(JSONSerialization.jsonObject(with: JSONEncoder().encode(reference)) as? [String: Any])
        json["quote"] = String(repeating: "a", count: 501)
        #expect(throws: RoutineObservationReferenceError.invalidQuote) {
            try JSONDecoder().decode(RoutineObservationReference.self, from: JSONSerialization.data(withJSONObject: json))
        }
    }

    @Test func inferredRowsLoseReferenceWhileExplicitKeptStepRetainsIt() throws {
        let reference = try RoutineObservationReference(acquisitionID: UUID(), revisionSHA256: String(repeating: "b", count: 64), quote: "Exact line")
        let malicious = RoutineStep(title: "Untrusted proposal", automation: .savedObservation, observationReference: reference)
        let candidate = RoutineVersion(sourceLabel: "Synthetic model output", steps: [malicious])
        let cleaned = RoutineVersion.inferredDraft(from: candidate, preserving: nil)
        #expect(cleaned.steps[0].automation == nil && cleaned.steps[0].observationReference == nil)
        #expect(!cleaned.isApproved)
        let kept = RoutineStep(title: "Reviewed excerpt", detail: "Explicitly reviewed text", isRequired: true,
            automation: .savedObservation, observationReference: reference)
        let prior = RoutineVersion(sourceLabel: "User reviewed plan", steps: [kept], isApproved: true)
        let reconciled = RoutineVersion.inferredDraft(from: candidate, preserving: prior)
        #expect(reconciled.steps.last == kept)
        #expect(reconciled.steps.first?.observationReference == nil)
    }

    @Test func oldManualStepDecodesWithoutReference() throws {
        let legacy = Data("{\"id\":\"11111111-1111-4111-8111-111111111111\",\"title\":\"A manual moment\",\"detail\":\"\",\"kind\":\"custom\",\"durationMinutes\":1,\"isRequired\":false}".utf8)
        let step = try JSONDecoder().decode(RoutineStep.self, from: legacy)
        #expect(step.observationReference == nil && step.automation == nil)
    }
    @Test func missingProvenanceDecodesConservativelyAndSurvivesAnotherSave() throws {
        let reference = try RoutineObservationReference(acquisitionID: UUID(), revisionSHA256: String(repeating: "b", count: 64), quote: "Exact line")
        var json = try #require(JSONSerialization.jsonObject(with: JSONEncoder().encode(reference)) as? [String: Any])
        json.removeValue(forKey: "isSynthetic")
        let restored = try JSONDecoder().decode(RoutineObservationReference.self, from: JSONSerialization.data(withJSONObject: json))
        #expect(restored.isSynthetic)
        let savedAgain = try JSONDecoder().decode(RoutineObservationReference.self, from: JSONEncoder().encode(restored))
        #expect(savedAgain.isSynthetic)
        json["isSynthetic"] = "false"
        #expect(throws: DecodingError.self) {
            try JSONDecoder().decode(RoutineObservationReference.self, from: JSONSerialization.data(withJSONObject: json))
        }
    }

    @Test func keptSyntheticReferenceSurvivesPersonalRelabelAndJournalReload() throws {
        let reference = try RoutineObservationReference(acquisitionID: UUID(), revisionSHA256: String(repeating: "c", count: 64),
            quote: "A sample memory", isSynthetic: true)
        let kept = RoutineStep(title: "Saved sample", isRequired: true, automation: .savedObservation,
            observationReference: reference)
        var journal = RoutinePreferenceJournal()
        try journal.upsert(RoutinePreference(target: kept, presence: .keep))
        let reloaded = try JSONDecoder().decode(RoutinePreferenceJournal.self, from: JSONEncoder().encode(journal))
        let personal = RoutineStep(title: "New personal moment")
        let reconciled = try reloaded.reconcile(steps: [personal])
        let updated = RoutineVersion(sourceLabel: "Selected saved observations — tentative proposal", steps: reconciled.steps)
        #expect(updated.isSynthetic)
        #expect(updated.steps.first(where: { $0.id == kept.id }) == kept)
        let restored = try JSONDecoder().decode(RoutineVersion.self, from: JSONEncoder().encode(updated))
        #expect(restored.isSynthetic)
        // Legacy inferred retention must not reinterpret a relabeled sample as a personal ritual.
        let candidate = RoutineVersion(sourceLabel: "Personal evidence", steps: [personal])
        let learned = RoutineVersion.inferredDraft(from: candidate, preserving: restored)
        #expect(learned.steps == [personal])
        #expect(!learned.isSynthetic)
        #expect(RoutineVersion(sourceLabel: "Demo fixture — sample", steps: []).isSynthetic)
        #expect(!RoutineVersion(sourceLabel: "Personal plan", steps: [personal]).isSynthetic)
    }

}
