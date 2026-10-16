import Foundation
import MorningCore
import Testing
@testable import MorningApple
#if canImport(FoundationModels)
import FoundationModels
#endif

@Suite("Saved-observation routine proposals")
struct RoutineEvidenceProposalTests {
    private let instant = Date(timeIntervalSince1970: 1_760_000_000)
    private let words = "I review my calendar after breakfast."

    @Test("Editing a learned proposal retains exact evidence and standing exclusions without approving it")
    func editableDraftRetainsEvidenceAndPreferences() throws {
        let entry = try source()
        let archive = try ObservationArchive(entries: [entry])
        let evidence = try LearningEvidencePreparation.prepare(acquisitions: [entry])
        let excluded = RoutineStep(title: "Old habit", kind: .entertainment, durationMinutes: 8)
        let base = RoutineVersion(sourceLabel: "User-approved routine", steps: [excluded], isApproved: true)
        var preferences = RoutinePreferenceJournal()
        try preferences.upsert(RoutinePreference(target: excluded, presence: .exclude))
        let proposal = try LearningEvidencePreparation.assemble(evidence: evidence,
            steps: [step(try #require(evidence.units.first))], preserving: base, preferences: preferences, at: instant)
        let originalSources = proposal.sourceSnapshots
        let originalSupport = proposal.support
        let originalPreferences = preferences
        let draft = try proposal.draftForEditing(archive: archive, baseRoutine: base, preferences: preferences)
        #expect(!draft.isApproved)
        #expect(draft == proposal.routine)
        #expect(draft.steps[0].detail.contains(words))
        #expect(!draft.steps.contains { $0.id == excluded.id })
        #expect(proposal.sourceSnapshots == originalSources)
        #expect(proposal.support == originalSupport)
        #expect(archive.entry(id: entry.id) == entry)
        #expect(preferences == originalPreferences)
        var unapprovedSession = RoutineSession(routine: draft)
        #expect(throws: SessionError.routineNeedsApproval) { try unapprovedSession.start(at: instant) }
    }

    @Test("An edit handoff refuses changed sources, preferences and pinned running or paused sessions")
    func editableDraftRequiresCurrentSourcesAndNoActiveSession() throws {
        let entry = try source()
        let archive = try ObservationArchive(entries: [entry])
        let evidence = try LearningEvidencePreparation.prepare(acquisitions: [entry])
        let base = RoutineVersion(sourceLabel: "Approved", steps: [RoutineStep(title: "Kept morning", durationMinutes: 1)], isApproved: true)
        let preferences = RoutinePreferenceJournal()
        let proposal = try LearningEvidencePreparation.assemble(evidence: evidence,
            steps: [step(try #require(evidence.units.first))], preserving: base, preferences: preferences, at: instant)
        var changedArchive = archive
        try changedArchive.correct(id: entry.id, text: "A different observed morning.")
        #expect(throws: RoutineEvidenceProposalError.invalidProposal) {
            try proposal.draftForEditing(archive: changedArchive, baseRoutine: base, preferences: preferences)
        }
        var changedPreferences = preferences
        try changedPreferences.upsert(RoutinePreference(target: base.steps[0], presence: .exclude))
        #expect(throws: RoutineEvidenceProposalError.invalidProposal) {
            try proposal.draftForEditing(archive: archive, baseRoutine: base, preferences: changedPreferences)
        }
        var running = RoutineSession(routine: base)
        try running.start(at: instant)
        let pinned = running
        #expect(throws: RoutineEvidenceProposalError.invalidProposal) {
            try proposal.draftForEditing(archive: archive, baseRoutine: base, preferences: preferences, session: running)
        }
        #expect(running == pinned)
        try running.pause(at: instant.addingTimeInterval(1))
        let paused = running
        #expect(throws: RoutineEvidenceProposalError.invalidProposal) {
            try proposal.draftForEditing(archive: archive, baseRoutine: base, preferences: preferences, session: running)
        }
        #expect(running == paused)
    }

    private func source(id: UUID = UUID(), day: Int = 0, text: String? = nil,
                        correction: String? = nil, origin: ObservationAcquisitionOrigin = .human,
                        zone: String = "Europe/Paris", dated: Bool = true,
                        digest: String? = nil) throws -> ObservationAcquisition {
        try ObservationAcquisition(id: id, importedAt: instant, fileSHA256: digest,
            observedDate: dated ? ObservationObservedDate(date: instant.addingTimeInterval(Double(day) * 86_400),
                timeZoneIdentifier: zone, provenance: .userAssigned) : nil,
            origin: origin, sourceKind: .text, sourceLabel: "Synthetic test notes", originalText: text ?? words,
            correctedText: correction)
    }

    private func step(_ unit: PreparedLearningEvidenceUnit, quote: String? = nil,
                      title: String = "Review calendar") -> EvidenceRoutineStepInput {
        .init(title: title, detail: "Consider a short calendar review.", kind: .calendar, durationMinutes: 3,
              citations: [.init(unitID: unit.id, quote: quote ?? unit.text)])
    }

    @Test("Independent dates retain independent citations even with identical source text")
    func fourDatesAreNotGloballyDeduplicated() throws {
        let sources = try (0..<4).map { try source(day: $0) }
        let evidence = try LearningEvidencePreparation.prepare(acquisitions: sources)
        #expect(evidence.units.count == 4)
        let proposal = try LearningEvidencePreparation.assemble(evidence: evidence,
            steps: evidence.units.map { step($0) }, preserving: nil, at: instant)
        #expect(proposal.routine.steps.count == 1)
        #expect(proposal.support[0].citations.count == 4)
        #expect(Set(proposal.sourceSnapshots.map { $0.observedDate.dayKey }).count == 4)
        #expect(!proposal.routine.isApproved)
        #expect(proposal.routine.steps.allSatisfy { !$0.isRequired && $0.automation == nil && $0.observationReference == nil })
        #expect(proposal.isCurrent(archive: try ObservationArchive(entries: sources), baseRoutine: nil))
        #expect(evidence.modelRequestCount <= 6)
        #expect(evidence.submittedCharacterCount <= 8_000)
    }

    @Test("Two clips on one date keep source references without becoming two mornings")
    func sameDayAndDuplicateSelection() throws {
        let first = try source()
        let second = try source()
        let evidence = try LearningEvidencePreparation.prepare(acquisitions: [first, second])
        let proposal = try LearningEvidencePreparation.assemble(evidence: evidence,
            steps: evidence.units.map { step($0) }, preserving: nil)
        #expect(proposal.support[0].citations.count == 2)
        #expect(Set(proposal.sourceSnapshots.map { $0.observedDate.dayKey }).count == 1)
        #expect(throws: RoutineEvidenceProposalError.invalidSelection) {
            try LearningEvidencePreparation.prepare(acquisitions: [first, first])
        }
        let digest = String(repeating: "a", count: 64)
        #expect(throws: RoutineEvidenceProposalError.invalidSelection) {
            try LearningEvidencePreparation.prepare(acquisitions: [source(digest: digest), source(day: 1, digest: digest)])
        }
    }

    @Test("Generic titles do not merge independent mail and team-message frames")
    func genericTitlesKeepIndependentSupports() throws {
        let quotes = ["L'atelier reste en salle Cèdre à 09:15.",
                      "La table est prête. Combien de cartes apportes-tu ?"]
        let entry = try videoSource(texts: ["Cedar Mail - Gmail SIMULATED\n" + quotes[0],
                                            "Cedar Team - Slack SIMULATED\n" + quotes[1]])
        let evidence = try LearningEvidencePreparation.prepare(acquisitions: [entry])
        let inputs = evidence.units.enumerated().map { index, unit in
            EvidenceRoutineStepInput(title: "Review messages", detail: "A tentative review.", kind: .messages,
                durationMinutes: index + 2, citations: [.init(unitID: unit.id, quote: quotes[index])])
        }
        let proposal = try LearningEvidencePreparation.assemble(evidence: evidence, steps: inputs, preserving: nil, at: instant)
        #expect(proposal.routine.steps.map(\.title) == ["Review messages", "Review messages"])
        #expect(proposal.routine.steps.map(\.durationMinutes) == [2, 3])
        #expect(proposal.support.map { $0.citations.map(\.quote) } == quotes.map { [$0] })
        let frames = try #require(entry.videoEvidence).frames
        #expect(proposal.support.map { $0.citations.first?.sampleID } == frames.map { Optional($0.id) })
        #expect(proposal.routine.steps.allSatisfy { $0.target == nil && $0.automation == nil })
        #expect(!proposal.routine.isApproved)
        let restored = try JSONDecoder().decode(EvidenceRoutineProposal.self, from: JSONEncoder().encode(proposal))
        #expect(restored.routine.steps == proposal.routine.steps)
        #expect(restored.isCurrent(archive: try ObservationArchive(entries: [entry]), baseRoutine: nil))
        let kept = RoutineStep(title: "Review messages", detail: "My exact saved ritual", kind: .messages,
            durationMinutes: 7, isRequired: true)
        let base = RoutineVersion(sourceLabel: "My approved morning", steps: [kept], isApproved: true)
        let journal = try RoutinePreferenceJournal(entries: [RoutinePreference(target: kept, presence: .keep)], revision: UUID())
        #expect(throws: RoutinePreferenceError.ambiguousMatch(kept.id)) {
            try LearningEvidencePreparation.assemble(evidence: evidence, steps: inputs,
                preserving: base, preferences: journal, at: instant)
        }
        #expect(base.steps == [kept] && base.isApproved)
        #expect(journal.entries.first?.retainedStep == kept)
    }

    @Test("A shared exact support is deduplicated before personal timing is applied and restored")
    func sharedSupportRetainsPersonalTiming() throws {
        let entry = try source()
        let evidence = try LearningEvidencePreparation.prepare(acquisitions: [entry])
        let input = step(try #require(evidence.units.first))
        let personal = RoutineStep(title: input.title, detail: "My existing note", kind: input.kind, durationMinutes: 7)
        let preference = try RoutinePreference(target: personal, durationMinutes: 7)
        let journal = try RoutinePreferenceJournal(entries: [preference], revision: UUID())
        let proposal = try LearningEvidencePreparation.assemble(evidence: evidence, steps: [input, input],
            preserving: nil, preferences: journal, at: instant)
        #expect(proposal.routine.steps.count == 1)
        #expect(proposal.routine.steps.first?.durationMinutes == 7)
        #expect(proposal.support.first?.citations.count == 1)
        #expect(proposal.support.first?.citations.first?.quote == words)
        #expect(proposal.support.first?.reason == .inferredEvidenceWithUserPreference)
        #expect(proposal.preferenceSnapshot == journal)
        let restored = try JSONDecoder().decode(EvidenceRoutineProposal.self, from: JSONEncoder().encode(proposal))
        #expect(restored == proposal)
        #expect(restored.isCurrent(archive: try ObservationArchive(entries: [entry]), baseRoutine: nil, preferences: journal))
    }

    @Test("The same quoted sentence in different written contexts does not establish equivalence")
    func repeatedQuoteDoesNotEraseItsContext() throws {
        let sources = try [source(text: words + " Then I read my team's messages."),
                           source(day: 1, text: words + " Then I listen to music.")]
        let evidence = try LearningEvidencePreparation.prepare(acquisitions: sources)
        let proposal = try LearningEvidencePreparation.assemble(evidence: evidence,
            steps: evidence.units.map { step($0, quote: words) }, preserving: nil, at: instant)
        #expect(proposal.routine.steps.count == 2)
        #expect(proposal.support.map { $0.citations.count } == [1, 1])
        #expect(proposal.isCurrent(archive: try ObservationArchive(entries: sources), baseRoutine: nil))
    }

    @Test("Identical text on distinct video frames stays distinct and never silently bypasses the ten-moment limit")
    func distinctFramesKeepTheExplicitLimit() throws {
        let entry = try videoSource(texts: Array(repeating: "Calendar\n09:00 Project planning meeting", count: 11))
        let evidence = try LearningEvidencePreparation.prepare(acquisitions: [entry])
        #expect(evidence.units.count == 11)
        #expect(throws: RoutineEvidenceProposalError.tooManySteps) {
            try LearningEvidencePreparation.assemble(evidence: evidence,
                steps: evidence.units.map { step($0, quote: "09:00 Project planning meeting") }, preserving: nil, at: instant)
        }
    }

    private func videoSource(texts: [String]) throws -> ObservationAcquisition {
        let frames = try texts.enumerated().map { index, text in
            try ObservationFrameEvidence(requestedTimeSeconds: Double(index), actualTimeSeconds: Double(index),
                outcome: .observed, text: text)
        }
        let video = try ObservationVideoEvidence(durationSeconds: Double(frames.count + 1), frames: frames)
        return try ObservationAcquisition(importedAt: instant, observedDate: source().observedDate, origin: .synthetic,
            sourceKind: .video, sourceLabel: "SYNTHETIC independent support test", originalText: video.renderedText,
            videoEvidence: video)
    }

    @Test("Dates, origin and original zone are explicit prerequisites")
    func rejectsUnassignedAndMixedSources() throws {
        #expect(throws: RoutineEvidenceProposalError.dateRequired) {
            try LearningEvidencePreparation.prepare(acquisitions: [source(dated: false)])
        }
        for origin in [ObservationAcquisitionOrigin.unknown, .automated] {
            #expect(throws: RoutineEvidenceProposalError.incompatibleSources) {
                try LearningEvidencePreparation.prepare(acquisitions: [source(origin: origin)])
            }
        }
        #expect(throws: RoutineEvidenceProposalError.incompatibleSources) {
            try LearningEvidencePreparation.prepare(acquisitions: [source(), source(day: 1, origin: .synthetic)])
        }
        #expect(throws: RoutineEvidenceProposalError.incompatibleSources) {
            try LearningEvidencePreparation.prepare(acquisitions: [source(), source(day: 1, zone: "UTC")])
        }
        #expect(throws: RoutineEvidenceProposalError.invalidSelection) {
            try LearningEvidencePreparation.prepare(acquisitions: [])
        }
        #expect(throws: RoutineEvidenceProposalError.invalidSelection) {
            try LearningEvidencePreparation.prepare(acquisitions: (0..<6).map { try source(day: $0) })
        }
    }

    @Test("Long sources are batched completely and empty selected corrections still fail")
    func longEvidenceIsNotSilentlyTruncated() throws {
        let long = String(repeating: "I review the calendar after breakfast. ", count: 220)
        let longEvidence = try LearningEvidencePreparation.prepare(acquisitions: [source(text: long)])
        #expect(longEvidence.modelRequestCount > 6)
        #expect(longEvidence.units.map(\.text).joined().utf8.elementsEqual(long.utf8))
        #expect(longEvidence.prompts.allSatisfy { $0.count <= 1_500 && $0.utf8.count <= 6_000 })
        #expect(throws: RoutineEvidenceProposalError.insufficientEvidence) {
            try LearningEvidencePreparation.prepare(acquisitions: [source(), source(day: 1, correction: "")])
        }
        let evidence = try LearningEvidencePreparation.prepare(acquisitions: [source(text: String(repeating: words, count: 45))])
        #expect(evidence.units.map(\.text).joined() == String(repeating: words, count: 45))
        #expect(evidence.submittedCharacterCount == evidence.prompts.reduce(0) { $0 + $1.count })
    }

    @Test("Correction citations cannot borrow original source or video interpretation")
    func correctionTakesPrecedence() throws {
        let entry = try source(correction: "I enjoy a quiet cup of tea before breakfast.")
        let evidence = try LearningEvidencePreparation.prepare(acquisitions: [entry])
        let unit = try #require(evidence.units.first)
        #expect(unit.sourceLayer == .correction)
        #expect(unit.text == entry.correctedText)
        #expect(throws: RoutineEvidenceProposalError.invalidCitation) {
            try LearningEvidencePreparation.assemble(evidence: evidence, steps: [step(unit, quote: words)], preserving: nil)
        }
        let proposal = try LearningEvidencePreparation.assemble(evidence: evidence, steps: [step(unit)], preserving: nil)
        #expect(proposal.support[0].citations[0].sourceLayer == .correction)
        #expect(proposal.isCurrent(archive: try ObservationArchive(entries: [entry]), baseRoutine: nil))
    }

    @Test("Exact submitted units reject quote borrowing, invented identifiers and Unicode substitutions")
    func citationsAreByteExactAndUnitScoped() throws {
        let decomposed = "I drink cafe\u{301} before reviewing my calendar."
        let sources = try [source(text: decomposed), source(day: 1, text: "I play chess after breakfast.")]
        let evidence = try LearningEvidencePreparation.prepare(acquisitions: sources)
        let first = evidence.units[0]
        let second = evidence.units[1]
        #expect(throws: RoutineEvidenceProposalError.invalidCitation) {
            try LearningEvidencePreparation.assemble(evidence: evidence,
                steps: [step(first, quote: "I drink café before reviewing my calendar.")], preserving: nil)
        }
        #expect(throws: RoutineEvidenceProposalError.invalidCitation) {
            try LearningEvidencePreparation.assemble(evidence: evidence,
                steps: [step(first, quote: second.text)], preserving: nil)
        }
        #expect(throws: RoutineEvidenceProposalError.invalidCitation) {
            try LearningEvidencePreparation.assemble(evidence: evidence, steps: [EvidenceRoutineStepInput(
                title: "Review", detail: "", kind: .calendar, durationMinutes: 3,
                citations: [.init(unitID: UUID(), quote: first.text)])], preserving: nil)
        }
        let proposal = try LearningEvidencePreparation.assemble(evidence: evidence, steps: [step(first)], preserving: nil)
        let citation = proposal.support[0].citations[0]
        #expect(citation.quote.utf8.elementsEqual(decomposed.utf8))
        #expect(citation.startCharacterOffset == 0)
        #expect(citation.endCharacterOffset == decomposed.count)
        #expect(ProposalValidation.step(title: "Calendar", detail: "", kind: "calendar", durationMinutes: 3,
            evidenceQuote: "I drink café before reviewing my calendar.", source: decomposed) == nil)
    }

    @Test("Recorded frame IDs and offsets survive while unsupported frames are disclosed")
    func videoProvenanceAndOmissions() throws {
        let frame = try ObservationFrameEvidence(requestedTimeSeconds: 0, actualTimeSeconds: 0,
            outcome: .observed, text: "Calendar\n09:00 Project planning meeting")
        let blank = try ObservationFrameEvidence(requestedTimeSeconds: 1, actualTimeSeconds: 1, outcome: .blank)
        let setup = try ObservationFrameEvidence(requestedTimeSeconds: 2, actualTimeSeconds: 2,
            outcome: .observed, text: "Screen Sharing\nShare Screen\nCancel")
        let video = try ObservationVideoEvidence(durationSeconds: 3, frames: [frame, blank, setup])
        let entry = try ObservationAcquisition(observedDate: source().observedDate, origin: .human,
            sourceKind: .video, sourceLabel: "Generated fixture", originalText: video.renderedText, videoEvidence: video)
        let evidence = try LearningEvidencePreparation.prepare(acquisitions: [entry])
        #expect(evidence.units.count == 1)
        #expect(evidence.omissions.count == 2)
        let proposal = try LearningEvidencePreparation.assemble(evidence: evidence,
            steps: [step(evidence.units[0], quote: "09:00 Project planning meeting")], preserving: nil)
        let citation = proposal.support[0].citations[0]
        #expect(citation.sampleID == frame.id)
        #expect(citation.startCharacterOffset == "Calendar\n".count)
        #expect(citation.sourceLayer == .videoFrame)
        #expect(proposal.isCurrent(archive: try ObservationArchive(entries: [entry]), baseRoutine: nil))
    }

    @Test("Same acquisition ID cannot hide corrections, source changes, date changes or deletion")
    func sourceChangesMakeProposalStale() throws {
        let entry = try source()
        let evidence = try LearningEvidencePreparation.prepare(acquisitions: [entry])
        let proposal = try LearningEvidencePreparation.assemble(evidence: evidence, steps: [step(evidence.units[0])], preserving: nil)
        var archive = try ObservationArchive(entries: [entry])
        try archive.correct(id: entry.id, text: "I skip calendar review today.")
        #expect(!proposal.isCurrent(archive: archive, baseRoutine: nil))
        archive = try ObservationArchive(entries: [entry])
        try archive.assignObservedDate(id: entry.id, value: source(day: 1).observedDate)
        #expect(!proposal.isCurrent(archive: archive, baseRoutine: nil))
        archive = try ObservationArchive(entries: [entry])
        try archive.assignObservedDate(id: entry.id, value: entry.observedDate, origin: .synthetic)
        #expect(!proposal.isCurrent(archive: archive, baseRoutine: nil))
        let changed = try source(id: entry.id, text: "I do not review the calendar today.")
        #expect(!proposal.isCurrent(archive: try ObservationArchive(entries: [changed]), baseRoutine: nil))
        #expect(!proposal.isCurrent(archive: ObservationArchive(), baseRoutine: nil))
    }

    @Test("Full base state catches same-ID approval and step edits")
    func baseRevisionIncludesApprovalAndAllFields() throws {
        let entry = try source()
        let evidence = try LearningEvidencePreparation.prepare(acquisitions: [entry])
        let base = RoutineVersion(createdAt: instant, sourceLabel: "My routine",
            steps: [RoutineStep(title: "Tea", detail: "Quiet time", durationMinutes: 7)])
        let proposal = try LearningEvidencePreparation.assemble(evidence: evidence, steps: [step(evidence.units[0])], preserving: base)
        let archive = try ObservationArchive(entries: [entry])
        #expect(proposal.isCurrent(archive: archive, baseRoutine: base))
        #expect(!proposal.isCurrent(archive: archive, baseRoutine: base.approved()))
        var edited = base
        edited.steps[0].detail = "Changed without replacing the routine ID"
        #expect(!proposal.isCurrent(archive: archive, baseRoutine: edited))
        edited = base; edited.steps[0].automation = .spokenNote
        #expect(!proposal.isCurrent(archive: archive, baseRoutine: edited))
        edited = base; edited.number += 1
        #expect(!proposal.isCurrent(archive: archive, baseRoutine: edited))
        #expect(!proposal.isCurrent(archive: archive, baseRoutine: nil))
    }

    @Test("Kept rituals retain user values and do not borrow fresh model evidence")
    func requiredRitualReconciliationIsHonest() throws {
        let entry = try source()
        let evidence = try LearningEvidencePreparation.prepare(acquisitions: [entry])
        let kept = RoutineStep(title: "Review calendar", detail: "My exact custom reminder", kind: .calendar,
            durationMinutes: 11, isRequired: true, automation: .spokenNote)
        let base = RoutineVersion(createdAt: instant, sourceLabel: "My approved morning", steps: [kept], isApproved: true)
        let proposal = try LearningEvidencePreparation.assemble(evidence: evidence, steps: [step(evidence.units[0])], preserving: base)
        #expect(proposal.routine.steps == [kept])
        #expect(!proposal.routine.isApproved)
        #expect(proposal.support[0].stepID == kept.id)
        #expect(proposal.support[0].reason == .preservedUserDecision)
        #expect(proposal.support[0].citations.isEmpty)
        #expect(proposal.isCurrent(archive: try ObservationArchive(entries: [entry]), baseRoutine: base))
    }

    @Test("Synthetic proposals stay synthetic and sample rituals do not become personal preferences")
    func syntheticOriginAndSampleExclusion() throws {
        let entry = try source(origin: .synthetic)
        let evidence = try LearningEvidencePreparation.prepare(acquisitions: [entry])
        let proposal = try LearningEvidencePreparation.assemble(evidence: evidence, steps: [step(evidence.units[0])], preserving: DemoFixtures.routine)
        #expect(proposal.routine.sourceLabel.localizedCaseInsensitiveContains("demo fixture"))
        #expect(proposal.routine.sourceLabel.contains("synthetic saved observations"))
        #expect(proposal.sourceSnapshots.allSatisfy { $0.origin == .synthetic })
        #expect(proposal.routine.steps.count == 1)
        #expect(proposal.support.allSatisfy { $0.reason == .inferredEvidence })
    }

    @Test("Validated restoration rejects approval and corrupted citation offsets")
    func codableRestorationIsValidated() throws {
        let entry = try source()
        let evidence = try LearningEvidencePreparation.prepare(acquisitions: [entry])
        let proposal = try LearningEvidencePreparation.assemble(evidence: evidence, steps: [step(evidence.units[0])], preserving: nil)
        let data = try JSONEncoder().encode(proposal)
        let restored = try JSONDecoder().decode(EvidenceRoutineProposal.self, from: data)
        #expect(restored == proposal)
        #expect(restored.isCurrent(archive: try ObservationArchive(entries: [entry]), baseRoutine: nil))
        var object = try #require(JSONSerialization.jsonObject(with: data) as? [String: Any])
        var routine = try #require(object["routine"] as? [String: Any])
        routine["isApproved"] = true; object["routine"] = routine
        #expect(throws: RoutineEvidenceProposalError.invalidProposal) {
            try JSONDecoder().decode(EvidenceRoutineProposal.self, from: JSONSerialization.data(withJSONObject: object))
        }
        object = try #require(JSONSerialization.jsonObject(with: data) as? [String: Any])
        var support = try #require(object["support"] as? [[String: Any]])
        var citations = try #require(support[0]["citations"] as? [[String: Any]])
        citations[0]["startCharacterOffset"] = Int.max
        citations[0]["endCharacterOffset"] = Int.min
        support[0]["citations"] = citations; object["support"] = support
        #expect(throws: RoutineEvidenceProposalError.invalidProposal) {
            try JSONDecoder().decode(EvidenceRoutineProposal.self, from: JSONSerialization.data(withJSONObject: object))
        }
    }

    @Test("Restored inferred rows cannot carry a hidden observation binding", arguments: [false, true])
    func restoredInferenceRejectsObservationReferences(withOperation: Bool) throws {
        let entry = try source()
        let evidence = try LearningEvidencePreparation.prepare(acquisitions: [entry])
        let proposal = try LearningEvidencePreparation.assemble(evidence: evidence,
            steps: [step(evidence.units[0])], preserving: nil)
        let reference = try RoutineObservationReference(acquisitionID: entry.id,
            revisionSHA256: String(repeating: "a", count: 64), quote: words)
        var object = try #require(JSONSerialization.jsonObject(with: JSONEncoder().encode(proposal)) as? [String: Any])
        var routine = try #require(object["routine"] as? [String: Any])
        var steps = try #require(routine["steps"] as? [[String: Any]])
        steps[0]["observationReference"] = try JSONSerialization.jsonObject(with: JSONEncoder().encode(reference))
        if withOperation { steps[0]["automation"] = "savedObservation" }
        routine["steps"] = steps; object["routine"] = routine
        let forged = try JSONSerialization.data(withJSONObject: object)
        #expect(throws: RoutineEvidenceProposalError.invalidProposal) {
            try JSONDecoder().decode(EvidenceRoutineProposal.self, from: forged)
        }
    }

    @Test("A trusted kept moment preserves its binding without granting one to inferred rows", arguments: [false, true])
    func keptObservationReferenceSurvivesProposalRoundtrip(usingJournal: Bool) throws {
        let entry = try source()
        let evidence = try LearningEvidencePreparation.prepare(acquisitions: [entry])
        // This tests authority retention only. Playback independently resolves the source.
        let reference = try RoutineObservationReference(acquisitionID: entry.id,
            revisionSHA256: String(repeating: "b", count: 64), quote: words)
        let kept = RoutineStep(title: "Review calendar", detail: "A source I explicitly selected.", kind: .calendar,
            durationMinutes: 2, isRequired: !usingJournal, automation: .savedObservation,
            observationReference: reference)
        let base = RoutineVersion(createdAt: instant, sourceLabel: "My approved morning", steps: [kept], isApproved: true)
        let preferences: RoutinePreferenceJournal? = usingJournal
            ? try RoutinePreferenceJournal(entries: [RoutinePreference(target: kept, presence: .keep)], revision: UUID())
            : nil
        let proposal = try LearningEvidencePreparation.assemble(evidence: evidence,
            steps: [step(evidence.units[0])], preserving: base, preferences: preferences)
        #expect(proposal.routine.steps == [kept])
        #expect(proposal.support[0].reason == .preservedUserDecision)
        #expect(proposal.support[0].citations.isEmpty)
        let restored = try JSONDecoder().decode(EvidenceRoutineProposal.self, from: JSONEncoder().encode(proposal))
        #expect(restored == proposal)
        let archive = try ObservationArchive(entries: [entry])
        #expect(restored.isCurrent(archive: archive, baseRoutine: base, preferences: preferences))
    }

    @Test("Personal evidence cannot relabel an explicitly kept synthetic excerpt", arguments: [
        "My approved morning", "Demo fixture — includes a synthetic saved observation"
    ])
    func keptSyntheticReferencePreservesProposalProvenance(baseLabel: String) throws {
        let entry = try source()
        let evidence = try LearningEvidencePreparation.prepare(acquisitions: [entry])
        let reference = try RoutineObservationReference(acquisitionID: UUID(),
            revisionSHA256: String(repeating: "d", count: 64), quote: "A deliberately kept sample excerpt.",
            isSynthetic: true)
        let kept = RoutineStep(title: "A saved sample", detail: "A deliberately kept sample excerpt.",
            kind: .briefing, durationMinutes: 1, automation: .savedObservation,
            observationReference: reference)
        let base = RoutineVersion(createdAt: instant, sourceLabel: baseLabel, steps: [kept], isApproved: true)
        let preferences = try RoutinePreferenceJournal(
            entries: [RoutinePreference(target: kept, presence: .keep)], revision: UUID())
        let proposal = try LearningEvidencePreparation.assemble(evidence: evidence,
            steps: [step(evidence.units[0])], preserving: base, preferences: preferences)
        #expect(proposal.sourceSnapshots.allSatisfy { $0.origin == .human })
        #expect(proposal.routine.isSynthetic)
        #expect(proposal.routine.sourceLabel.localizedCaseInsensitiveContains("demo fixture"))
        #expect(proposal.routine.steps.contains(kept))
        #expect(proposal.support.first { $0.stepID == kept.id }?.reason == .preservedUserDecision)
        let data = try JSONEncoder().encode(proposal)
        let restored = try JSONDecoder().decode(EvidenceRoutineProposal.self, from: data)
        let archive = try ObservationArchive(entries: [entry])
        #expect(restored == proposal)
        #expect(restored.isCurrent(archive: archive, baseRoutine: base, preferences: preferences))

        // The source-label marker is checked on restoration as well as assembly.
        var object = try #require(JSONSerialization.jsonObject(with: data) as? [String: Any])
        var routine = try #require(object["routine"] as? [String: Any])
        routine["sourceLabel"] = "Selected saved observations — tentative proposal"
        object["routine"] = routine
        #expect(throws: RoutineEvidenceProposalError.invalidProposal) {
            try JSONDecoder().decode(EvidenceRoutineProposal.self,
                from: JSONSerialization.data(withJSONObject: object))
        }

        // Keeping a synthetic marker does not permit weakening the retained
        // reference itself; its authoritative journal snapshot still wins.
        object = try #require(JSONSerialization.jsonObject(with: data) as? [String: Any])
        routine = try #require(object["routine"] as? [String: Any])
        var steps = try #require(routine["steps"] as? [[String: Any]])
        let keptIndex = try #require(steps.firstIndex { ($0["id"] as? String) == kept.id.uuidString })
        var forgedReference = try #require(steps[keptIndex]["observationReference"] as? [String: Any])
        forgedReference["isSynthetic"] = false
        steps[keptIndex]["observationReference"] = forgedReference
        routine["steps"] = steps; object["routine"] = routine
        let changed = try JSONDecoder().decode(EvidenceRoutineProposal.self,
            from: JSONSerialization.data(withJSONObject: object))
        #expect(!changed.isCurrent(archive: archive, baseRoutine: base, preferences: preferences))
    }

    @Test("A synthetic reference excludes legacy required retention even under a personal label")
    func syntheticReferenceCannotBecomeImplicitPersonalPreference() throws {
        let entry = try source()
        let evidence = try LearningEvidencePreparation.prepare(acquisitions: [entry])
        let reference = try RoutineObservationReference(acquisitionID: UUID(),
            revisionSHA256: String(repeating: "e", count: 64), quote: "A synthetic required ritual.",
            isSynthetic: true)
        let sample = RoutineStep(title: "A saved sample", isRequired: true,
            automation: .savedObservation, observationReference: reference)
        let base = RoutineVersion(sourceLabel: "My approved morning", steps: [sample], isApproved: true)
        let proposal = try LearningEvidencePreparation.assemble(evidence: evidence,
            steps: [step(evidence.units[0])], preserving: base)
        #expect(!proposal.routine.steps.contains { $0.id == sample.id })
        #expect(!proposal.routine.isSynthetic)
        #expect(proposal.support.allSatisfy { $0.reason == .inferredEvidence })
        #expect(proposal.isCurrent(archive: try ObservationArchive(entries: [entry]), baseRoutine: base))
    }

    @Test("Portable plans omit private observation bindings even with notes included")
    func portablePlansCannotTransferObservationReferences() throws {
        let privateQuote = "SYNTHETIC_PRIVATE_REFERENCE_ONLY_QUOTE"
        let reference = try RoutineObservationReference(acquisitionID: UUID(),
            revisionSHA256: String(repeating: "c", count: 64), quote: privateQuote)
        let selected = RoutineStep(title: "A selected observation", detail: "Read my reviewed source.",
            automation: .savedObservation, observationReference: reference)
        let routine = RoutineVersion(sourceLabel: "Synthetic transfer boundary", steps: [selected], isApproved: true)
        for detail in [RoutineExportDetail.planOnly, .includeDetails] {
            let document = try PortableRoutineDocument(routine: routine, detail: detail)
            let bytes = try document.encoded()
            let serialized = String(decoding: bytes, as: UTF8.self)
            for forbidden in [privateQuote, "observationReference", "savedObservation", reference.acquisitionID.uuidString] {
                #expect(!serialized.contains(forbidden))
            }
            let imported = try PortableRoutineDocument.decode(bytes).importedDraft(replacing: nil)
            #expect(!imported.isApproved)
            #expect(imported.steps.allSatisfy { $0.automation == nil && $0.observationReference == nil })
            var object = try #require(JSONSerialization.jsonObject(with: bytes) as? [String: Any])
            var steps = try #require(object["steps"] as? [[String: Any]])
            steps[0]["observationReference"] = try JSONSerialization.jsonObject(with: JSONEncoder().encode(reference))
            object["steps"] = steps
            let forged = try JSONSerialization.data(withJSONObject: object)
            #expect(throws: PortableRoutineDocumentError.unexpectedFields) {
                try PortableRoutineDocument.decode(forged)
            }
        }
    }

    @Test("More than ten moments fails without silently removing kept rituals")
    func totalMomentLimitIncludesRequiredRituals() throws {
        let entry = try source()
        let evidence = try LearningEvidencePreparation.prepare(acquisitions: [entry])
        let kept = (0..<10).map { RoutineStep(title: "Kept ritual \($0)", isRequired: true) }
        let base = RoutineVersion(sourceLabel: "My personal routine", steps: kept, isApproved: true)
        #expect(throws: RoutineEvidenceProposalError.tooManySteps) {
            try LearningEvidencePreparation.assemble(evidence: evidence, steps: [step(evidence.units[0])], preserving: base)
        }
        #expect(base.steps == kept)
        #expect(base.isApproved)
    }

    @Test("Approved routine retains bounded exact quotations after pending receipt removal")
    func routineRetainsEvidenceAfterApproval() throws {
        let sources = try [source(), source(day: 1), source(day: 2, text: "I review tomorrow’s appointments after breakfast.")]
        let evidence = try LearningEvidencePreparation.prepare(acquisitions: sources)
        let proposal = try LearningEvidencePreparation.assemble(evidence: evidence,
            steps: evidence.units.map { step($0) }, preserving: nil)
        let approved = proposal.routine.approved()
        let detail = approved.steps[0].detail
        #expect(approved.isApproved)
        // Generation writes the label of the language the tests run in.
        #expect(detail.contains(EvidenceDetailText.label))
        #expect(Data(detail.utf8).range(of: Data(words.utf8)) != nil)
        #expect(Data(detail.utf8).range(of: Data(sources[2].originalText.utf8)) != nil)
        #expect(detail.components(separatedBy: EvidenceDetailText.label).count == 3)
        #expect(detail.count <= 8_000)
    }

    @Test("Restored inferred values cannot overflow routine totals or bypass detail bounds")
    func restoredStepBoundsAndBaseOverflow() throws {
        let entry = try source()
        let evidence = try LearningEvidencePreparation.prepare(acquisitions: [entry])
        let proposal = try LearningEvidencePreparation.assemble(evidence: evidence, steps: [step(evidence.units[0])], preserving: nil)
        let data = try JSONEncoder().encode(proposal)
        for duration in [-1, 0, Int.min, Int.max, 61, 1_441] {
            var object = try #require(JSONSerialization.jsonObject(with: data) as? [String: Any])
            var routine = try #require(object["routine"] as? [String: Any])
            var steps = try #require(routine["steps"] as? [[String: Any]])
            steps[0]["durationMinutes"] = duration
            routine["steps"] = steps; object["routine"] = routine
            #expect(throws: RoutineEvidenceProposalError.invalidProposal) {
                try JSONDecoder().decode(EvidenceRoutineProposal.self, from: JSONSerialization.data(withJSONObject: object))
            }
        }
        var object = try #require(JSONSerialization.jsonObject(with: data) as? [String: Any])
        var routine = try #require(object["routine"] as? [String: Any])
        var steps = try #require(routine["steps"] as? [[String: Any]])
        steps[0]["detail"] = String(repeating: "x", count: LearningEvidencePreparation.maximumDetailCharacters + 1)
        routine["steps"] = steps; object["routine"] = routine
        #expect(throws: RoutineEvidenceProposalError.invalidProposal) {
            try JSONDecoder().decode(EvidenceRoutineProposal.self, from: JSONSerialization.data(withJSONObject: object))
        }
        let extreme = RoutineVersion(number: Int.max, sourceLabel: "My routine", steps: [])
        #expect(throws: RoutineEvidenceProposalError.invalidProposal) {
            try LearningEvidencePreparation.assemble(evidence: evidence, steps: [step(evidence.units[0])], preserving: extreme)
        }
    }

    @Test("Restoration cannot discard or normalize the quotation retained after approval")
    func restoredDetailMustRetainExactEvidenceEntry() throws {
        let original = "I drink cafe\u{301} before reviewing my calendar."
        let entry = try source(text: original)
        let evidence = try LearningEvidencePreparation.prepare(acquisitions: [entry])
        let proposal = try LearningEvidencePreparation.assemble(evidence: evidence,
            steps: [step(evidence.units[0])], preserving: nil)
        let data = try JSONEncoder().encode(proposal)
        let alteredDetails = [
            "A tentative calendar review with no retained quotation.",
            original, // Bare prose is not the app-owned retained Evidence entry.
            "Evidence: “I drink café before reviewing my calendar.”" // Canonically equal, different bytes.
        ]
        for detail in alteredDetails {
            var object = try #require(JSONSerialization.jsonObject(with: data) as? [String: Any])
            var routine = try #require(object["routine"] as? [String: Any])
            var steps = try #require(routine["steps"] as? [[String: Any]])
            steps[0]["detail"] = detail
            routine["steps"] = steps; object["routine"] = routine
            // Typed citations and original source hashes remain intact in all cases.
            #expect(throws: RoutineEvidenceProposalError.invalidProposal) {
                try JSONDecoder().decode(EvidenceRoutineProposal.self,
                    from: JSONSerialization.data(withJSONObject: object))
            }
        }
        let restored = try JSONDecoder().decode(EvidenceRoutineProposal.self, from: data)
        #expect(restored.isCurrent(archive: try ObservationArchive(entries: [entry]), baseRoutine: nil))
    }

    @Test("Restored proposal version must follow the full current base or begin at one")
    func restoredVersionMustMatchBase() throws {
        let entry = try source()
        let archive = try ObservationArchive(entries: [entry])
        let evidence = try LearningEvidencePreparation.prepare(acquisitions: [entry])
        let base = RoutineVersion(number: 4, createdAt: instant, sourceLabel: "My morning",
            steps: [RoutineStep(title: "Tea")], isApproved: true)
        for prior in [nil, base] as [RoutineVersion?] {
            let proposal = try LearningEvidencePreparation.assemble(evidence: evidence,
                steps: [step(evidence.units[0])], preserving: prior)
            #expect(proposal.routine.number == (prior?.number ?? 0) + 1)
            #expect(proposal.isCurrent(archive: archive, baseRoutine: prior))
            let data = try JSONEncoder().encode(proposal)
            for wrongNumber in [proposal.routine.number + 1, Int.max] {
                var object = try #require(JSONSerialization.jsonObject(with: data) as? [String: Any])
                var routine = try #require(object["routine"] as? [String: Any])
                routine["number"] = wrongNumber; object["routine"] = routine
                let restored = try JSONDecoder().decode(EvidenceRoutineProposal.self,
                    from: JSONSerialization.data(withJSONObject: object))
                #expect(!restored.isCurrent(archive: archive, baseRoutine: prior))
            }
        }
        let proposal = try LearningEvidencePreparation.assemble(evidence: evidence,
            steps: [step(evidence.units[0])], preserving: base)
        var extreme = base; extreme.number = Int.max
        #expect(!proposal.isCurrent(archive: archive, baseRoutine: extreme))
    }

    @Test("Explicit timing overrides retain generated evidence and identify the user decision")
    func journalDurationKeepsCitations() throws {
        let entry = try source()
        let archive = try ObservationArchive(entries: [entry])
        let evidence = try LearningEvidencePreparation.prepare(acquisitions: [entry])
        let target = RoutineStep(title: "Review calendar", kind: .calendar)
        var preferences = RoutinePreferenceJournal()
        try preferences.upsert(RoutinePreference(target: target, durationMinutes: 90))
        let proposal = try LearningEvidencePreparation.assemble(evidence: evidence,
            steps: [step(evidence.units[0])], preserving: nil, preferences: preferences)
        #expect(proposal.routine.steps[0].durationMinutes == 90)
        #expect(!proposal.routine.steps[0].isRequired)
        #expect(proposal.routine.steps[0].automation == nil)
        #expect(proposal.support[0].reason == .inferredEvidenceWithUserPreference)
        #expect(proposal.support[0].preferenceIDs == [target.id])
        #expect(proposal.support[0].citations[0].quote == words)
        #expect(Data(proposal.routine.approved().steps[0].detail.utf8).range(of: Data(words.utf8)) != nil)
        #expect(proposal.isCurrent(archive: archive, baseRoutine: nil, preferences: preferences))
        let restored = try JSONDecoder().decode(EvidenceRoutineProposal.self, from: JSONEncoder().encode(proposal))
        #expect(restored.isCurrent(archive: archive, baseRoutine: nil, preferences: preferences))
        #expect(!restored.isCurrent(archive: archive, baseRoutine: nil))
        try preferences.upsert(RoutinePreference(target: target, durationMinutes: 8))
        #expect(!restored.isCurrent(archive: archive, baseRoutine: nil, preferences: preferences))
    }

    @Test("Kept snapshots are user support, including when inserted without matching observation")
    func journalKeepDoesNotInventCitations() throws {
        let entry = try source()
        let evidence = try LearningEvidencePreparation.prepare(acquisitions: [entry])
        let kept = RoutineStep(title: "My tea ritual", detail: "A handwritten reminder.",
            kind: .wellbeing, durationMinutes: 11, isRequired: true, automation: .spokenNote)
        var preferences = RoutinePreferenceJournal()
        try preferences.upsert(RoutinePreference(target: kept, presence: .keep))
        let proposal = try LearningEvidencePreparation.assemble(evidence: evidence,
            steps: [step(evidence.units[0])], preserving: nil, preferences: preferences)
        #expect(proposal.routine.steps.last == kept)
        let matchingSupport = proposal.support.first { $0.stepID == kept.id }
        let support = try #require(matchingSupport)
        #expect(support.reason == .preservedUserDecision)
        #expect(support.citations.isEmpty)
        #expect(support.preferenceIDs == [kept.id])
        #expect(proposal.isCurrent(archive: try ObservationArchive(entries: [entry]),
            baseRoutine: nil, preferences: preferences))
        // A matched kept first row must remain first during restore replay too.
        let matching = RoutineStep(title: "Review calendar", detail: "My exact words", kind: .calendar,
            durationMinutes: 7, isRequired: true)
        try preferences.upsert(RoutinePreference(target: matching, presence: .keep))
        let ordered = try LearningEvidencePreparation.assemble(evidence: evidence,
            steps: [step(evidence.units[0]), step(evidence.units[0], title: "Another review")],
            preserving: nil, preferences: preferences)
        #expect(ordered.routine.steps.first == matching)
        #expect(ordered.isCurrent(archive: try ObservationArchive(entries: [entry]),
            baseRoutine: nil, preferences: preferences))
    }

    @Test("Explicit empty journal and cleared keep do not resurrect legacy required flags")
    func authoritativeJournalControlsLegacyRetention() throws {
        let entry = try source()
        let archive = try ObservationArchive(entries: [entry])
        let evidence = try LearningEvidencePreparation.prepare(acquisitions: [entry])
        let kept = RoutineStep(title: "My tea ritual", isRequired: true)
        let base = RoutineVersion(sourceLabel: "My routine", steps: [kept], isApproved: true)
        let legacy = try LearningEvidencePreparation.assemble(evidence: evidence,
            steps: [step(evidence.units[0])], preserving: base)
        #expect(legacy.routine.steps.contains(kept))
        #expect(legacy.preferenceSnapshot == nil)
        let empty = RoutinePreferenceJournal()
        let explicit = try LearningEvidencePreparation.assemble(evidence: evidence,
            steps: [step(evidence.units[0])], preserving: base, preferences: empty)
        #expect(explicit.routine.steps.count == 1)
        #expect(explicit.preferenceSnapshot != nil)
        #expect(explicit.isCurrent(archive: archive, baseRoutine: base, preferences: empty))
        #expect(!explicit.isCurrent(archive: archive, baseRoutine: base))
        #expect(!legacy.isCurrent(archive: archive, baseRoutine: base, preferences: empty))
        var cleared = RoutinePreferenceJournal()
        try cleared.upsert(RoutinePreference(target: kept, presence: .keep))
        let removed = cleared.remove(targetID: kept.id)
        #expect(removed)
        let afterClear = try LearningEvidencePreparation.assemble(evidence: evidence,
            steps: [step(evidence.units[0])], preserving: base, preferences: cleared)
        #expect(!afterClear.routine.steps.contains { $0.id == kept.id })
        #expect(afterClear.isCurrent(archive: archive, baseRoutine: base, preferences: cleared))
    }

    @Test("An exclusion defeats required retention and can remove all proposed activities")
    func journalExclusionIsAuthoritative() throws {
        let entry = try source()
        let evidence = try LearningEvidencePreparation.prepare(acquisitions: [entry])
        let excluded = RoutineStep(title: "Review calendar", kind: .calendar, isRequired: true)
        let base = RoutineVersion(sourceLabel: "My routine", steps: [excluded], isApproved: true)
        var preferences = RoutinePreferenceJournal()
        try preferences.upsert(RoutinePreference(target: excluded, presence: .exclude))
        let proposal = try LearningEvidencePreparation.assemble(evidence: evidence,
            steps: [step(evidence.units[0]), step(evidence.units[0], title: "Review plans")],
            preserving: base, preferences: preferences)
        #expect(proposal.routine.steps.count == 1)
        #expect(proposal.routine.steps[0].title == "Review plans")
        #expect(proposal.isCurrent(archive: try ObservationArchive(entries: [entry]),
            baseRoutine: base, preferences: preferences))
        #expect(throws: RoutineEvidenceProposalError.insufficientEvidence) {
            try LearningEvidencePreparation.assemble(evidence: evidence,
                steps: [step(evidence.units[0])], preserving: base, preferences: preferences)
        }
        // A restored receipt cannot append the excluded activity with a fresh model ID.
        var object = try #require(JSONSerialization.jsonObject(with: JSONEncoder().encode(proposal)) as? [String: Any])
        var routine = try #require(object["routine"] as? [String: Any])
        var steps = try #require(routine["steps"] as? [[String: Any]])
        var supports = try #require(object["support"] as? [[String: Any]])
        let revivedID = UUID().uuidString
        var revivedStep = steps[0]
        revivedStep["id"] = revivedID; revivedStep["title"] = excluded.title
        steps.append(revivedStep)
        var revivedSupport = supports[0]
        revivedSupport["stepID"] = revivedID
        supports.append(revivedSupport)
        routine["steps"] = steps; object["routine"] = routine; object["support"] = supports
        let restored = try JSONDecoder().decode(EvidenceRoutineProposal.self,
            from: JSONSerialization.data(withJSONObject: object))
        #expect(!restored.isCurrent(archive: try ObservationArchive(entries: [entry]),
            baseRoutine: base, preferences: preferences))
    }

    @Test("Preference receipts reject altered snapshots and forged override values")
    func restoredPreferencesAndEffectsAreValidated() throws {
        let entry = try source()
        let archive = try ObservationArchive(entries: [entry])
        let evidence = try LearningEvidencePreparation.prepare(acquisitions: [entry])
        let target = RoutineStep(title: "Review calendar", kind: .calendar)
        var preferences = RoutinePreferenceJournal()
        try preferences.upsert(RoutinePreference(target: target, durationMinutes: 9))
        let proposal = try LearningEvidencePreparation.assemble(evidence: evidence,
            steps: [step(evidence.units[0])], preserving: nil, preferences: preferences)
        let data = try JSONEncoder().encode(proposal)
        for missingKey in ["preferenceSnapshot", "preferenceRevision"] {
            var object = try #require(JSONSerialization.jsonObject(with: data) as? [String: Any])
            object.removeValue(forKey: missingKey)
            #expect(throws: RoutineEvidenceProposalError.invalidProposal) {
                try JSONDecoder().decode(EvidenceRoutineProposal.self,
                    from: JSONSerialization.data(withJSONObject: object))
            }
        }
        var object = try #require(JSONSerialization.jsonObject(with: data) as? [String: Any])
        var malformedSnapshot = try #require(object["preferenceSnapshot"] as? [String: Any])
        var entries = try #require(malformedSnapshot["entries"] as? [[String: Any]])
        entries[0]["durationMinutes"] = 0
        malformedSnapshot["entries"] = entries; object["preferenceSnapshot"] = malformedSnapshot
        #expect(throws: RoutinePreferenceError.invalidPreference) {
            try JSONDecoder().decode(EvidenceRoutineProposal.self,
                from: JSONSerialization.data(withJSONObject: object))
        }
        object = try #require(JSONSerialization.jsonObject(with: data) as? [String: Any])
        var snapshot = try #require(object["preferenceSnapshot"] as? [String: Any])
        snapshot["revision"] = UUID().uuidString
        object["preferenceSnapshot"] = snapshot
        #expect(throws: RoutineEvidenceProposalError.invalidProposal) {
            try JSONDecoder().decode(EvidenceRoutineProposal.self,
                from: JSONSerialization.data(withJSONObject: object))
        }
        object = try #require(JSONSerialization.jsonObject(with: data) as? [String: Any])
        var routine = try #require(object["routine"] as? [String: Any])
        var steps = try #require(routine["steps"] as? [[String: Any]])
        steps[0]["durationMinutes"] = 10
        routine["steps"] = steps; object["routine"] = routine
        let wrongDuration = try JSONDecoder().decode(EvidenceRoutineProposal.self,
            from: JSONSerialization.data(withJSONObject: object))
        #expect(!wrongDuration.isCurrent(archive: archive, baseRoutine: nil, preferences: preferences))
        object = try #require(JSONSerialization.jsonObject(with: data) as? [String: Any])
        var support = try #require(object["support"] as? [[String: Any]])
        support[0]["preferenceIDs"] = [UUID().uuidString]
        object["support"] = support
        #expect(throws: RoutineEvidenceProposalError.invalidProposal) {
            try JSONDecoder().decode(EvidenceRoutineProposal.self,
                from: JSONSerialization.data(withJSONObject: object))
        }
    }

    @Test("A forged exact target ID cannot borrow timing for a different generated activity")
    func restoredTimingRequiresMatchingActivityKey() throws {
        let entry = try source()
        let archive = try ObservationArchive(entries: [entry])
        let evidence = try LearningEvidencePreparation.prepare(acquisitions: [entry])
        let target = RoutineStep(title: "Review calendar", kind: .calendar)
        var preferences = RoutinePreferenceJournal()
        try preferences.upsert(RoutinePreference(target: target, durationMinutes: 9))
        let proposal = try LearningEvidencePreparation.assemble(evidence: evidence,
            steps: [step(evidence.units[0])], preserving: nil, preferences: preferences)
        #expect(proposal.isCurrent(archive: archive, baseRoutine: nil, preferences: preferences))
        let data = try JSONEncoder().encode(proposal)
        for changeKind in [false, true] {
            var object = try #require(JSONSerialization.jsonObject(with: data) as? [String: Any])
            var routine = try #require(object["routine"] as? [String: Any])
            var steps = try #require(routine["steps"] as? [[String: Any]])
            var support = try #require(object["support"] as? [[String: Any]])
            // Source snapshots, quote bytes, timing and preference receipts stay intact.
            // Only a generated ID and its activity key are changed in the saved payload.
            steps[0]["id"] = target.id.uuidString
            support[0]["stepID"] = target.id.uuidString
            if changeKind { steps[0]["kind"] = StepKind.wellbeing.rawValue }
            else { steps[0]["title"] = "Another activity" }
            routine["steps"] = steps; object["routine"] = routine; object["support"] = support
            let restored = try JSONDecoder().decode(EvidenceRoutineProposal.self,
                from: JSONSerialization.data(withJSONObject: object))
            #expect(!restored.isCurrent(archive: archive, baseRoutine: nil, preferences: preferences))
        }
    }

    @Test("Legacy proposal decoding defaults only the absent journal and support fields")
    func legacyProposalDefaultsToLegacyMode() throws {
        let entry = try source()
        let evidence = try LearningEvidencePreparation.prepare(acquisitions: [entry])
        let proposal = try LearningEvidencePreparation.assemble(evidence: evidence,
            steps: [step(evidence.units[0])], preserving: nil)
        var object = try #require(JSONSerialization.jsonObject(with: JSONEncoder().encode(proposal)) as? [String: Any])
        object.removeValue(forKey: "preferenceSnapshot")
        object.removeValue(forKey: "preferenceRevision")
        var support = try #require(object["support"] as? [[String: Any]])
        for index in support.indices { support[index].removeValue(forKey: "preferenceIDs") }
        object["support"] = support
        let restored = try JSONDecoder().decode(EvidenceRoutineProposal.self,
            from: JSONSerialization.data(withJSONObject: object))
        #expect(restored.preferenceSnapshot == nil)
        #expect(restored.preferenceRevision == nil)
        #expect(restored.support[0].preferenceIDs.isEmpty)
        #expect(restored.isCurrent(archive: try ObservationArchive(entries: [entry]), baseRoutine: nil))
    }

    @Test("The ten-moment limit includes newly journal-kept snapshots")
    func journalKeptRowsCountTowardLimit() throws {
        let entry = try source()
        let evidence = try LearningEvidencePreparation.prepare(acquisitions: [entry])
        var preferences = RoutinePreferenceJournal()
        for index in 0..<10 {
            try preferences.upsert(RoutinePreference(target: RoutineStep(title: "Kept \(index)"), presence: .keep))
        }
        #expect(throws: RoutineEvidenceProposalError.tooManySteps) {
            try LearningEvidencePreparation.assemble(evidence: evidence,
                steps: [step(evidence.units[0])], preserving: nil, preferences: preferences)
        }
        #expect(preferences.entries.count == 10)
    }

    #if canImport(FoundationModels)
    @Test("The cited guided schema resolves its exact supplied citation identifiers")
    func citedSchemaResolves() throws {
        let schema = try EvidenceRoutineGenerationSchema.make(citationIDs: ["q1", "q2"])
        #expect(try JSONEncoder().encode(schema).count > 100)
    }
    #endif
    private func reviewableVideo(_ texts: [String], day: Int = 0) throws -> ObservationAcquisition {
        let frames = try texts.enumerated().map { index, text in
            try ObservationFrameEvidence(requestedTimeSeconds: Double(index), actualTimeSeconds: Double(index),
                outcome: .observed, text: text)
        }
        let video = try ObservationVideoEvidence(durationSeconds: Double(texts.count + 1), frames: frames)
        return try ObservationAcquisition(importedAt: instant, observedDate: source(day: day).observedDate,
            origin: .human, sourceKind: .video, sourceLabel: "Synthetic review test recording",
            originalText: video.renderedText, videoEvidence: video)
    }

    @Test("Reviewed context guides the prompt without becoming OCR or action evidence")
    func reviewedLabelsRemainSeparateFromOriginalQuotes() throws {
        let entry = try reviewableVideo(["Calendar\n09:00 Project planning meeting"])
        let frame = try #require(entry.videoEvidence?.frames.first)
        let label = "A deliberately reviewed context"
        var archive = try ObservationArchive(entries: [entry])
        try archive.reviewFrame(id: entry.id, review: ObservationFrameReview(sampleID: frame.id,
            label: label, evidenceQuote: "Calendar", reviewedAt: instant))
        let evidence = try LearningEvidencePreparation.prepare(acquisitions: [#require(archive.entry(id: entry.id))])
        let unit = try #require(evidence.units.first)
        #expect(unit.text.utf8.elementsEqual(frame.text.utf8))
        #expect(unit.sourceLayer == .videoFrame && unit.sampleID == frame.id)
        #expect(unit.kind == .visibleTaskContent)
        #expect(unit.reviewedContext?.label == label)
        #expect(unit.reviewedContext?.evidenceQuote == "Calendar")
        #expect(unit.reviewedContext?.reviewedAt == instant)
        #expect(evidence.prompts.joined().contains("User-reviewed visible context only (not action evidence)"))
        #expect(evidence.prompts.joined().contains(label))
        #expect(throws: RoutineEvidenceProposalError.invalidCitation) {
            try LearningEvidencePreparation.assemble(evidence: evidence,
                steps: [step(unit, quote: label)], preserving: nil)
        }
        let proposal = try LearningEvidencePreparation.assemble(evidence: evidence,
            steps: [step(unit, quote: "09:00 Project planning meeting")], preserving: nil)
        let citation = try #require(proposal.support.first?.citations.first)
        #expect(citation.quote == "09:00 Project planning meeting")
        #expect(citation.startCharacterOffset == "Calendar\n".count)
        #expect(citation.endCharacterOffset == frame.text.count)
        #expect(citation.sourceLayer == .videoFrame)
        #expect(proposal.routine.steps.allSatisfy { $0.automation == nil && $0.observationReference == nil })
    }

    @Test("An explicit unknown excludes only its frame and never becomes a positive report")
    func reviewedUnknownFramesAreDisclosedAndNotSubmitted() throws {
        let entry = try reviewableVideo(["Calendar\n09:00 Project planning meeting", "Chess\nWhite to move"])
        let frames = try #require(entry.videoEvidence?.frames)
        var archive = try ObservationArchive(entries: [entry])
        try archive.reviewFrame(id: entry.id, review: ObservationFrameReview(sampleID: frames[0].id,
            label: nil, evidenceQuote: nil, reviewedAt: instant))
        let evidence = try LearningEvidencePreparation.prepare(acquisitions: [#require(archive.entry(id: entry.id))])
        #expect(evidence.units.map(\.sampleID) == [frames[1].id])
        #expect(evidence.omissions.count == 1)
        #expect(evidence.omissions.first?.reason == .explicitlyReviewedUnknown)
        #expect(evidence.omissions.first?.sampleID == frames[0].id)
        #expect(!evidence.prompts.joined().contains("Project planning"))
        try archive.reviewFrame(id: entry.id, review: ObservationFrameReview(sampleID: frames[1].id,
            label: nil, evidenceQuote: nil, reviewedAt: instant))
        #expect(throws: RoutineEvidenceProposalError.insufficientEvidence) {
            try LearningEvidencePreparation.prepare(acquisitions: [#require(archive.entry(id: entry.id))])
        }
    }

    @Test("Adding, changing or removing frame review invalidates pending evidence across reload")
    func reviewRevisionsInvalidateProposalsAndClearingRestoresBaseline() throws {
        let entry = try reviewableVideo(["Calendar\n09:00 Project planning meeting"])
        let frame = try #require(entry.videoEvidence?.frames.first)
        let original = try LearningEvidencePreparation.prepare(acquisitions: [entry])
        let originalProposal = try LearningEvidencePreparation.assemble(evidence: original,
            steps: [step(original.units[0], quote: "09:00 Project planning meeting")], preserving: nil)
        var archive = try ObservationArchive(entries: [entry])
        try archive.reviewFrame(id: entry.id, review: ObservationFrameReview(sampleID: frame.id,
            label: "Planning context", evidenceQuote: "Calendar", reviewedAt: instant))
        #expect(!originalProposal.isCurrent(archive: archive, baseRoutine: nil))
        let reviewed = try LearningEvidencePreparation.prepare(acquisitions: [#require(archive.entry(id: entry.id))])
        let proposal = try LearningEvidencePreparation.assemble(evidence: reviewed,
            steps: [step(reviewed.units[0], quote: "09:00 Project planning meeting")], preserving: nil)
        let savedProposal = try JSONDecoder().decode(EvidenceRoutineProposal.self, from: JSONEncoder().encode(proposal))
        archive = try JSONDecoder().decode(ObservationArchive.self, from: JSONEncoder().encode(archive))
        #expect(savedProposal.isCurrent(archive: archive, baseRoutine: nil))
        try archive.reviewFrame(id: entry.id, review: ObservationFrameReview(sampleID: frame.id,
            label: "Another visible context", evidenceQuote: "Calendar", reviewedAt: instant.addingTimeInterval(1)))
        #expect(!savedProposal.isCurrent(archive: archive, baseRoutine: nil))
        try archive.removeFrameReview(id: entry.id, sampleID: frame.id)
        #expect(!savedProposal.isCurrent(archive: archive, baseRoutine: nil))
        let cleared = try LearningEvidencePreparation.prepare(acquisitions: [#require(archive.entry(id: entry.id))])
        #expect(cleared.sourceSnapshots == original.sourceSnapshots)
        #expect(originalProposal.isCurrent(archive: archive, baseRoutine: nil))
    }

    @Test("Reviewed labels cannot promote bare headings or permission UI into activities")
    func reviewedLabelDoesNotBypassVisualEligibility() throws {
        for text in ["Calendar", "Screen Sharing\nShare Screen\nCancel"] {
            let entry = try reviewableVideo([text])
            let frame = try #require(entry.videoEvidence?.frames.first)
            var archive = try ObservationArchive(entries: [entry])
            try archive.reviewFrame(id: entry.id, review: ObservationFrameReview(sampleID: frame.id,
                label: "I read all messages and replied to everyone", evidenceQuote: text,
                reviewedAt: instant))
            #expect(throws: RoutineEvidenceProposalError.insufficientEvidence) {
                try LearningEvidencePreparation.prepare(acquisitions: [#require(archive.entry(id: entry.id))])
            }
        }
    }

    @Test("Review metadata shares the input budget without truncating original OCR")
    func reviewedContextBudgetPreservesEveryOriginalCharacter() throws {
        let text = String(repeating: "09:00 Project planning meeting\n", count: 55)
        let entry = try reviewableVideo([text])
        let frame = try #require(entry.videoEvidence?.frames.first)
        var archive = try ObservationArchive(entries: [entry])
        try archive.reviewFrame(id: entry.id, review: ObservationFrameReview(sampleID: frame.id,
            label: String(repeating: "L", count: 80), evidenceQuote: "Project planning meeting", reviewedAt: instant))
        let evidence = try LearningEvidencePreparation.prepare(acquisitions: [#require(archive.entry(id: entry.id))])
        #expect(evidence.units.count > 1)
        #expect(evidence.units.map(\.text).joined().utf8.elementsEqual(text.utf8))
        #expect(evidence.units.allSatisfy { $0.reviewedContext != nil && $0.kind == .visibleTaskContent })
        #expect(evidence.units[1].startCharacterOffset == evidence.units[0].text.count)
        #expect(evidence.prompts.allSatisfy { $0.count <= 1_500 })
        #expect(evidence.submittedCharacterCount == evidence.prompts.reduce(0) { $0 + $1.count })
        #expect(evidence.submittedCharacterCount <= 8_000)
    }

    @Test("No-review sources retain the pre-review source hash")
    func absentReviewsPreserveLegacySnapshotHash() throws {
        let entry = try source(id: UUID(uuidString: "11111111-1111-4111-8111-111111111111")!, zone: "UTC")
        let evidence = try LearningEvidencePreparation.prepare(acquisitions: [entry])
        // Fixed legacy sorted JSON source envelope: reference-date seconds 781692800,
        // UTC observed day, human text source, no optional correction/video/digest.
        #expect(evidence.sourceSnapshots[0].sourceRevision == "f29fe0e791f9b6d8bcc20935027b51f5644fc41fadd7201498ff9f722fd2f82f")
        #expect(evidence.units.first?.reviewedContext == nil)
        #expect(!evidence.prompts.joined().contains("User-reviewed visible context"))
    }

    @Test("A repaired revision string cannot restore citations to a reviewed-unknown frame")
    func restoredProposalCannotBypassUnknownWithCurrentRevision() throws {
        let entry = try reviewableVideo(["Calendar\n09:00 Project planning meeting", "Chess\nWhite to move"])
        let frames = try #require(entry.videoEvidence?.frames)
        let evidence = try LearningEvidencePreparation.prepare(acquisitions: [entry])
        let proposal = try LearningEvidencePreparation.assemble(evidence: evidence,
            steps: [step(evidence.units[0], quote: "09:00 Project planning meeting")], preserving: nil)
        var archive = try ObservationArchive(entries: [entry])
        try archive.reviewFrame(id: entry.id, review: ObservationFrameReview(sampleID: frames[0].id,
            label: nil, evidenceQuote: nil, reviewedAt: instant))
        let current = try LearningEvidencePreparation.prepare(acquisitions: [#require(archive.entry(id: entry.id))])
        let currentRevision = try #require(current.sourceSnapshots.first?.sourceRevision)
        var object = try #require(JSONSerialization.jsonObject(with: JSONEncoder().encode(proposal)) as? [String: Any])
        var snapshots = try #require(object["sourceSnapshots"] as? [[String: Any]])
        snapshots[0]["sourceRevision"] = currentRevision
        object["sourceSnapshots"] = snapshots
        var support = try #require(object["support"] as? [[String: Any]])
        var citations = try #require(support[0]["citations"] as? [[String: Any]])
        citations[0]["sourceRevision"] = currentRevision
        support[0]["citations"] = citations
        object["support"] = support
        let restored = try JSONDecoder().decode(EvidenceRoutineProposal.self,
            from: JSONSerialization.data(withJSONObject: object))
        #expect(!restored.isCurrent(archive: archive, baseRoutine: nil))
    }

    @Test("Unreadable saved reviews preserve source but require explicit notes before learning")
    func corruptFrameReviewBlocksOriginalLearningButAllowsCorrectedNotes() throws {
        let entry = try reviewableVideo(["Calendar\n09:00 Project planning meeting"])
        let frame = try #require(entry.videoEvidence?.frames.first)
        let originalEvidence = try LearningEvidencePreparation.prepare(acquisitions: [entry])
        let originalProposal = try LearningEvidencePreparation.assemble(evidence: originalEvidence,
            steps: [step(originalEvidence.units[0], quote: "09:00 Project planning meeting")], preserving: nil)
        var archive = try ObservationArchive(entries: [entry])
        try archive.reviewFrame(id: entry.id, review: ObservationFrameReview(sampleID: frame.id,
            label: nil, evidenceQuote: nil, reviewedAt: instant))
        let reviewed = try #require(archive.entry(id: entry.id))
        var object = try #require(JSONSerialization.jsonObject(with: JSONEncoder().encode(reviewed)) as? [String: Any])
        object["frameReviews"] = "malformed saved review payload"
        let restored = try JSONDecoder().decode(ObservationAcquisition.self,
            from: JSONSerialization.data(withJSONObject: object))
        #expect(restored.originalText.utf8.elementsEqual(entry.originalText.utf8))
        #expect(restored.videoEvidence == entry.videoEvidence)
        #expect(restored.warnings.contains(.invalidFrameReviewsRemoved))
        #expect(restored.frameReviews.isEmpty)
        #expect(throws: RoutineEvidenceProposalError.unsupportedSource) {
            try LearningEvidencePreparation.prepare(acquisitions: [restored])
        }
        archive = try ObservationArchive(entries: [restored])
        #expect(!originalProposal.isCurrent(archive: archive, baseRoutine: nil))
        try archive.correct(id: entry.id, text: "I review my calendar after breakfast.")
        let corrected = try #require(archive.entry(id: entry.id))
        let evidence = try LearningEvidencePreparation.prepare(acquisitions: [corrected])
        #expect(evidence.units.count == 1)
        #expect(evidence.units[0].sourceLayer == .correction)
        #expect(evidence.units[0].kind == .userReportedActivity)
        #expect(evidence.units[0].sampleID == nil && evidence.units[0].reviewedContext == nil)
        let proposal = try LearningEvidencePreparation.assemble(evidence: evidence,
            steps: [step(evidence.units[0])], preserving: nil)
        #expect(proposal.isCurrent(archive: archive, baseRoutine: nil))
    }

    /// The test process runs in one interface language. Each argument selects the fragments a
    /// build running in another language (or an English build from before French existed) saved.
    @Test("A saved proposal stays valid whichever language wrote its generated section",
          arguments: EvidenceDetailText.savedLabels.indices)
    func savedProposalValidatesUnderAnotherLanguage(language: Int) throws {
        let savedLabel = EvidenceDetailText.savedLabels[language]
        let savedNote = EvidenceDetailText.savedTentativeNotes[language]
        let entry = try source()
        let archive = try ObservationArchive(entries: [entry])
        let evidence = try LearningEvidencePreparation.prepare(acquisitions: [entry])
        let proposal = try LearningEvidencePreparation.assemble(evidence: evidence,
            steps: [step(evidence.units[0])], preserving: nil)
        var object = try #require(JSONSerialization.jsonObject(with: JSONEncoder().encode(proposal)) as? [String: Any])
        var routine = try #require(object["routine"] as? [String: Any])
        var steps = try #require(routine["steps"] as? [[String: Any]])
        let written = try #require(steps[0]["detail"] as? String)
        let quote = proposal.support[0].citations[0].quote
        let savedLine = "\(savedLabel) “\(quote)”"
        let saved = written.replacingOccurrences(of: EvidenceDetailText.line(quote), with: savedLine)
            .replacingOccurrences(of: EvidenceDetailText.tentativeNote, with: savedNote)
        #expect(saved == "Consider a short calendar review.\n\(savedNote)\n\(savedLine)")
        steps[0]["detail"] = saved
        routine["steps"] = steps; object["routine"] = routine
        let restored = try JSONDecoder().decode(EvidenceRoutineProposal.self,
            from: JSONSerialization.data(withJSONObject: object))
        #expect(restored.routine.steps[0].detail == saved)
        #expect(restored.isCurrent(archive: archive, baseRoutine: nil))
        #expect(EvidenceDetailText.description(of: saved, citing: [quote]) == "Consider a short calendar review.")
        // One language writes the whole section; a note and a label of two languages is not it.
        let otherNote = EvidenceDetailText.savedTentativeNotes[(language + 1) % EvidenceDetailText.savedTentativeNotes.count]
        steps[0]["detail"] = saved.replacingOccurrences(of: savedNote, with: otherNote)
        routine["steps"] = steps; object["routine"] = routine
        #expect(throws: RoutineEvidenceProposalError.invalidProposal) {
            try JSONDecoder().decode(EvidenceRoutineProposal.self, from: JSONSerialization.data(withJSONObject: object))
        }
    }

    @Test("Another language's marker inside the description is text: it neither replaces the evidence line nor cuts the description",
          arguments: EvidenceDetailText.savedLabels)
    func markerInsideDescriptionIsOrdinaryText(embeddedLabel: String) throws {
        let entry = try source()
        let archive = try ObservationArchive(entries: [entry])
        let evidence = try LearningEvidencePreparation.prepare(acquisitions: [entry])
        let quote = evidence.units[0].text
        let description = "Review the calendar.\n\(embeddedLabel) shared calendar\nThe note says “\(embeddedLabel) “\(quote)””"
        let proposal = try LearningEvidencePreparation.assemble(evidence: evidence, steps: [
            .init(title: "Review calendar", detail: description, kind: .calendar, durationMinutes: 3,
                  citations: [.init(unitID: evidence.units[0].id, quote: quote)])
        ], preserving: nil)
        let written = proposal.routine.steps[0].detail
        #expect(EvidenceDetailText.description(of: written, citing: [quote]) == description)
        let restored = try JSONDecoder().decode(EvidenceRoutineProposal.self, from: JSONEncoder().encode(proposal))
        #expect(restored.isCurrent(archive: archive, baseRoutine: nil))
        // Remove the generated evidence line; typed citations and source hashes stay intact.
        let generated = "\n" + EvidenceDetailText.line(quote)
        #expect(written.hasSuffix(generated))
        var object = try #require(JSONSerialization.jsonObject(with: JSONEncoder().encode(proposal)) as? [String: Any])
        var routine = try #require(object["routine"] as? [String: Any])
        var steps = try #require(routine["steps"] as? [[String: Any]])
        steps[0]["detail"] = String(written.dropLast(generated.count))
        routine["steps"] = steps; object["routine"] = routine
        #expect(throws: RoutineEvidenceProposalError.invalidProposal) {
            try JSONDecoder().decode(EvidenceRoutineProposal.self, from: JSONSerialization.data(withJSONObject: object))
        }
    }

    @Test("A label no build ever wrote still cannot stand in for the retained quotation")
    func unknownEvidenceLabelIsRejected() throws {
        let entry = try source()
        let evidence = try LearningEvidencePreparation.prepare(acquisitions: [entry])
        let proposal = try LearningEvidencePreparation.assemble(evidence: evidence,
            steps: [step(evidence.units[0])], preserving: nil)
        var object = try #require(JSONSerialization.jsonObject(with: JSONEncoder().encode(proposal)) as? [String: Any])
        var routine = try #require(object["routine"] as? [String: Any])
        var steps = try #require(routine["steps"] as? [[String: Any]])
        let written = try #require(steps[0]["detail"] as? String)
        let quote = proposal.support[0].citations[0].quote
        let unknown = written.replacingOccurrences(of: EvidenceDetailText.line(quote), with: "Beweis: “\(quote)”")
        #expect(unknown != written)
        steps[0]["detail"] = unknown
        routine["steps"] = steps; object["routine"] = routine
        #expect(throws: RoutineEvidenceProposalError.invalidProposal) {
            try JSONDecoder().decode(EvidenceRoutineProposal.self, from: JSONSerialization.data(withJSONObject: object))
        }
    }
}
