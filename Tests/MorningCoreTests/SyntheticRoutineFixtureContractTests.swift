import Foundation
import Testing
@testable import MorningCore

/// Direct portable-plan contract only. These checks do not decode a movie, run
/// Vision/OCR or a model, recognize speech, navigate a provider, or prove an effect.
/// Pixel/storyboard claims and the manual oracle never supply execution authority.
@Suite("Synthetic long portable plan — no OCR, model or provider proof")
struct SyntheticRoutineFixtureContractTests {
    private let instant = Date(timeIntervalSince1970: 1_792_129_500)
    private var directory: URL {
        URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent()
            .deletingLastPathComponent().appendingPathComponent("Benchmarks/routine-fixture-v1", isDirectory: true)
    }
    private func data(_ language: String) throws -> Data {
        try Data(contentsOf: directory.appendingPathComponent("oracle-draft-\(language).more-routine.json"))
    }
    private struct Oracle: Decodable {
        struct Step: Decodable {
            let id: UUID; let title: [String: String]; let detail: [String: String]
            let kind: StepKind; let durationMinutes: Int; let isRequired: Bool
        }
        let origin: String; let approvalExpected: Bool; let steps: [Step]
    }
    private func oracle() throws -> Oracle {
        try JSONDecoder().decode(Oracle.self, from: Data(contentsOf: directory.appendingPathComponent("expected-parsed.json")))
    }

    @Test("Both authored plans import as ten manual synthetic moments needing approval", arguments: ["fr", "en"])
    func portableDraftDoesNotImportAuthority(_ language: String) throws {
        let document = try PortableRoutineDocument.decode(data(language)), expected = try oracle()
        #expect(expected.origin == "synthetic" && !expected.approvalExpected)
        #expect(document.sourceIsSynthetic && !document.approvalAtExport && document.steps.count == 10)
        #expect(document.steps.map(\.id) == expected.steps.map(\.id))
        for (step, expectation) in zip(document.steps, expected.steps) {
            #expect(step.title == expectation.title[language] && step.detail == expectation.detail[language])
            #expect(step.kind == expectation.kind && step.durationMinutes == expectation.durationMinutes && step.isRequired == expectation.isRequired)
        }
        let predecessor = RoutineVersion(number: 7, createdAt: instant, sourceLabel: "Demo fixture — previous approved plan",
            steps: [RoutineStep(title: "SYNTHETIC previous moment")], isApproved: true)
        var ongoing = RoutineSession(routine: predecessor); try ongoing.start(at: instant)
        let draft = try document.importedDraft(replacing: predecessor, at: instant.addingTimeInterval(1))
        #expect(draft.number == 8 && draft.id != predecessor.id && draft.id != document.sourceRoutineID)
        #expect(draft.isSynthetic && !draft.isApproved && draft.totalDurationMinutes == 28)
        #expect(draft.steps.allSatisfy { $0.target == nil && $0.automation == nil && $0.webBehavior == nil && $0.webLikesAllowed == nil })
        #expect(ongoing.routine == predecessor && ongoing.status == .running)
        var unapproved = RoutineSession(routine: draft)
        #expect(throws: SessionError.routineNeedsApproval) { try unapproved.start(at: instant) }
        let exportedAgain = try PortableRoutineDocument.decode(PortableRoutineDocument(routine: draft, detail: .includeDetails).encoded())
        #expect(exportedAgain.sourceIsSynthetic && !exportedAgain.approvalAtExport)
    }

    @Test("Keep, Exclude, duration and order survive journal restoration and fresh inference IDs", arguments: ["fr", "en"])
    func personalChoicesAndTheApprovedSnapshotStayPinned(_ language: String) throws {
        let imported = try PortableRoutineDocument.decode(data(language)).importedDraft(replacing: nil, at: instant)
        var kept = imported.steps[7]; kept.detail = "SYNTHETIC owner-written ritual, kept verbatim."
        let shopping = RoutineStep(title: language == "fr" ? "Shopping fictif" : "Invented shopping", kind: .entertainment, durationMinutes: 2)
        let order = [7, 3, 0, 1, 2, 4, 5, 6, 8, 9].map { imported.steps[$0] }
        var preferences = RoutinePreferenceJournal()
        try preferences.rememberOrder(of: order)
        try preferences.upsert(.init(target: kept, presence: .keep))
        try preferences.upsert(.init(target: shopping, presence: .exclude))
        try preferences.upsert(.init(target: imported.steps[4], durationMinutes: 3))
        let saved = try JSONEncoder().encode(preferences)
        let restored = try JSONDecoder().decode(RoutinePreferenceJournal.self, from: saved)
        // This is an invented renewed proposal, not extracted video or model output.
        // Reading is absent; Shopping reappears under a fresh ID; every other ID changes.
        var candidates = [8, 4, 3, 1, 0, 5, 2, 6, 9].map { index in
            let old = imported.steps[index]
            return RoutineStep(title: old.title, detail: "SYNTHETIC renewed observation.", kind: old.kind,
                durationMinutes: index == 4 ? 4 : old.durationMinutes)
        }
        candidates.append(RoutineStep(title: shopping.title, kind: shopping.kind, durationMinutes: 2))
        let untrusted = RoutineVersion(createdAt: instant, sourceLabel: "Demo fixture — invented renewed inference", steps: candidates)
        let safe = RoutineVersion.inferredDraft(from: untrusted, preserving: nil, at: instant)
        let result = try restored.reconcile(steps: safe.steps)
        #expect(result.steps.count == 10 && result.steps.map(\.title) == order.map(\.title))
        #expect(result.steps.first == kept && result.retainedStepIDs == [kept.id])
        #expect(!result.steps.contains { $0.title == shopping.title })
        #expect(restored.entry(targetID: shopping.id)?.presence == .exclude)
        #expect(result.steps.first(where: { $0.title == imported.steps[4].title })?.durationMinutes == 3)
        #expect(result.steps.allSatisfy { $0.automation == nil && $0.target == nil })
        let reviewed = imported.revised(steps: result.steps, at: instant.addingTimeInterval(2))
        #expect(!reviewed.isApproved && reviewed.isSynthetic)
        let approved = reviewed.approved()
        var session = RoutineSession(routine: approved)
        try session.start(at: instant.addingTimeInterval(3))
        try session.pause(at: instant.addingTimeInterval(4))
        let paused = try JSONDecoder().decode(RoutineSession.self, from: JSONEncoder().encode(session))
        #expect(paused.status == .paused && paused.currentStepIndex == 0 && paused.currentStep?.id == kept.id)
        session = paused; try session.resume(at: instant.addingTimeInterval(5))
        #expect(session.status == .running && session.currentStepIndex == 0 && session.routine == approved)
        #expect(session.completedStepIDs.isEmpty && session.skippedStepIDs.isEmpty, "Pause/resume certifies no provider action.")
        let laterDraft = reviewed.revised(steps: Array(result.steps.reversed()), at: instant.addingTimeInterval(6))
        #expect(!laterDraft.isApproved && laterDraft.id != session.routine.id)
        #expect(session.routine.steps.map(\.id) == result.steps.map(\.id), "A later edit cannot rewrite the approved active session.")
        #expect(try restored.reconcile(steps: safe.steps).steps == result.steps)
    }

    @Test("Even authored fixture text and exported approval cannot smuggle executable fields")
    func portableEnvelopeStillRejectsActionsAndOverflow() throws {
        let bytes = try data("fr")
        let object = try #require(JSONSerialization.jsonObject(with: bytes) as? [String: Any])
        var approvedMetadata = object; approvedMetadata["approvalAtExport"] = true
        let decoded = try PortableRoutineDocument.decode(JSONSerialization.data(withJSONObject: approvedMetadata))
        #expect(try !decoded.importedDraft(replacing: nil, at: instant).isApproved)
        for field in ["automation", "target"] {
            var altered = object, steps = try #require(object["steps"] as? [[String: Any]])
            steps[0][field] = "gmailInbox"; altered["steps"] = steps
            let bad = try JSONSerialization.data(withJSONObject: altered)
            #expect(throws: PortableRoutineDocumentError.unexpectedFields) { try PortableRoutineDocument.decode(bad) }
        }
        var overflow = object, steps = try #require(object["steps"] as? [[String: Any]])
        var extra = steps[0]; extra["id"] = UUID().uuidString; steps.append(extra); overflow["steps"] = steps
        let bad = try JSONSerialization.data(withJSONObject: overflow)
        #expect(throws: PortableRoutineDocumentError.invalidRoutine) { try PortableRoutineDocument.decode(bad) }
    }
}
