import Foundation
import MorningCore
import Testing
@testable import MorningApple

@Suite("Evidence retention plan — expiry and forgetting one observation")
struct EvidenceRetentionPlanTests {
    private let now = Date(timeIntervalSince1970: 1_791_417_600) // A fixed synthetic instant.
    private let week: TimeInterval = 7 * 86_400

    private func morning(_ text: String = "I review my calendar after breakfast.", age: TimeInterval? = 0,
                         day: Int = 0) throws -> ObservationAcquisition {
        try .init(importedAt: age.map { now.addingTimeInterval(-$0) },
            observedDate: ObservationObservedDate(date: now.addingTimeInterval(Double(day - 30) * 86_400),
                timeZoneIdentifier: "Europe/Paris", provenance: .userAssigned),
            origin: .human, sourceKind: .text, sourceLabel: "Synthetic test notes", originalText: text)
    }

    /// The same step the app builds when a person adds a saved moment to a draft.
    private func savedMoment(_ source: ObservationAcquisition) throws -> RoutineStep {
        let candidate = try #require(ObservationNarrationComposer.candidates(for: source).first)
        let prepared = try ObservationNarrationComposer.prepare(acquisition: source, candidate: candidate)
        return RoutineStep(title: "A saved moment", detail: prepared.spokenText, kind: .briefing,
            durationMinutes: 1, automation: .savedObservation, observationReference: prepared.reference)
    }

    private func proposal(from sources: [ObservationAcquisition],
                          preferences: RoutinePreferenceJournal? = nil) throws -> EvidenceRoutineProposal {
        let evidence = try LearningEvidencePreparation.prepare(acquisitions: sources)
        let steps = evidence.units.map {
            EvidenceRoutineStepInput(title: "Review calendar", detail: "Consider a short calendar review.",
                kind: .calendar, durationMinutes: 3, citations: [.init(unitID: $0.id, quote: $0.text)])
        }
        return try LearningEvidencePreparation.assemble(evidence: evidence, steps: steps, preserving: nil,
            preferences: preferences, at: now)
    }

    private func plan(_ entries: [ObservationAcquisition], current: RoutineVersion? = nil,
                      previous: RoutineVersion? = nil, proposal: EvidenceRoutineProposal? = nil,
                      preferences: RoutinePreferenceJournal? = .init(), runs: [MorningRunRecord] = [],
                      session: RoutineSession? = nil, maximumAge: TimeInterval? = nil) throws -> EvidenceRetentionPlan {
        .init(archive: try ObservationArchive(entries: entries), currentRoutine: current, previousRoutine: previous,
              session: session, pendingProposal: proposal, preferences: preferences, history: MorningHistory(runs: runs),
              now: now, maximumAge: maximumAge ?? week)
    }

    private func run(_ routine: RoutineVersion, start: Bool = true) throws -> MorningRunRecord {
        var session = RoutineSession(routine: routine)
        if start { try session.start(at: now) }
        try session.stop(at: now.addingTimeInterval(60))
        return try MorningRunRecord(session: session, timeZoneIdentifier: "Europe/Paris", recordedAt: now)
    }

    @Test func theSavedSessionCopyIsListedAndFollowsItsRoutine() throws {
        let source = try morning("A quiet cup of tea.")
        let draft = RoutineVersion(sourceLabel: "Your selected saved observation", steps: [try savedMoment(source)])
        let approved = draft.approved()
        let ready = try plan([source], current: approved, session: RoutineSession(routine: approved)).dependents(of: source.id)
        #expect(ready.map(\.store) == [.currentRoutine, .session])
        #expect(ready.allSatisfy { $0.reason == .approvedQuotation })
        // The app also saves a session for a routine not yet approved.
        let unapproved = try plan([source], current: draft, session: RoutineSession(routine: draft)).dependents(of: source.id)
        #expect(unapproved.map(\.store) == [.currentRoutine, .session])
        #expect(unapproved.allSatisfy { $0.reason == .unapprovedDraftQuotation })
    }

    @Test func nothingIsListedForRemovalWhileSavedChoicesCannotBeRead() throws {
        let source = try morning("A quiet cup of tea.")
        let draft = RoutineVersion(sourceLabel: "Your selected saved observation", steps: [try savedMoment(source)])
        #expect(try plan([source], current: draft).dependents(of: source.id).map(\.disposition) == [.removed])
        let unread = try plan([source], current: draft, preferences: nil)
        #expect(unread.dependents(of: source.id).map(\.reason) == [.choicesUnavailable])
        #expect(!unread.dependentCopies.contains { $0.disposition == .removed })
    }

    @Test func savedRunsStillHoldingAQuotationAreListedAfterTheRoutineMovedOn() throws {
        let source = try morning("A quiet cup of tea.")
        let learned = try morning(day: 1)
        let step = try savedMoment(source)
        let ran = RoutineVersion(sourceLabel: "Your selected saved observation", steps: [step]).approved()
        let accepted = try proposal(from: [learned]).routine.approved()
        let runs = [try run(ran), try run(ran), try run(accepted)]
        // Neither the current nor the previous routine holds the saved moment any more.
        let later = RoutineVersion(sourceLabel: "Your morning", steps: [RoutineStep(title: "Stretch")]).approved()
        let result = try plan([source, learned], current: later, previous: later, runs: runs)
        let copies = result.dependents(of: source.id)
        #expect(copies.count == 2 && copies.allSatisfy { $0.store == .runHistory && $0.kind == .savedMomentStep
            && $0.stepID == step.id && $0.quote == "A quiet cup of tea."
            && $0.disposition == .separatelyRetained && $0.reason == .approvedQuotation })
        // An accepted suggestion's evidence line inside a run is found by its words.
        let worded = result.dependents(of: learned.id)
        #expect(worded.map(\.store) == [.runHistory] && worded[0].kind == .unlinkedStepText)
        #expect(worded[0].quote == learned.originalText && worded[0].disposition == .separatelyRetained)

        // A quotation the person approved and ran stays approved in a later draft.
        let draft = RoutineVersion(sourceLabel: "Your morning", steps: [step])
        let protected = try plan([source], current: draft, runs: [try run(ran)]).dependents(of: source.id)
        #expect(protected.map(\.store) == [.currentRoutine, .runHistory])
        #expect(protected.allSatisfy { $0.reason == .approvedQuotation })
        #expect(try plan([source], current: draft).dependents(of: source.id).map(\.disposition) == [.removed])

        // A morning stopped before it started can pin an unapproved draft. Its record is
        // kept and listed, but it is not an approval and protects nothing else.
        let unstarted = try plan([source], current: draft, runs: [try run(draft, start: false)]).dependents(of: source.id)
        #expect(unstarted.map(\.reason) == [.unapprovedDraftQuotation, .savedRun])
        #expect(unstarted.map(\.disposition) == [.removed, .separatelyRetained])
    }

    @Test func keptQuotationIsListedAsASeparateRetainedCopy() throws {
        let source = try morning(age: 30 * 86_400)
        let step = try savedMoment(source)
        var journal = RoutinePreferenceJournal()
        try journal.upsert(RoutinePreference(target: step, presence: .keep))
        // The draft itself was never approved: only the explicit Keep protects it.
        let draft = RoutineVersion(sourceLabel: "Your selected saved observation", steps: [step])
        let result = try plan([source], current: draft, preferences: journal)
        #expect(result.expiredAcquisitionIDs == [source.id])
        let copies = result.dependents(of: source.id)
        let snapshot = try #require(copies.first { $0.store == .preferenceJournal })
        #expect(snapshot.kind == .keptChoiceSnapshot && snapshot.stepID == step.id)
        #expect(snapshot.quote == step.observationReference?.quote)
        #expect(snapshot.disposition == .separatelyRetained && snapshot.reason == .keptChoice)
        let inRoutine = try #require(copies.first { $0.store == .currentRoutine })
        #expect(inRoutine.kind == .savedMomentStep && inRoutine.reason == .keptChoice)
        #expect(copies.count == 2 && copies.allSatisfy { $0.disposition == .separatelyRetained })
        #expect(!snapshot.reason.explanation.isEmpty)
    }

    @Test func routineQuotationOutlivesRawExpiryOnlyWhenApproved() throws {
        let source = try morning(age: 30 * 86_400)
        let draft = RoutineVersion(sourceLabel: "Your selected saved observation", steps: [try savedMoment(source)])
        let unapproved = try plan([source], current: draft).dependents(of: source.id)
        #expect(unapproved.map(\.disposition) == [.removed])
        #expect(unapproved.map(\.reason) == [.unapprovedDraftQuotation])
        #expect(unapproved[0].quote == draft.steps[0].observationReference?.quote)

        let approved = try plan([source], current: draft.approved()).dependents(of: source.id)
        #expect(approved.map(\.disposition) == [.separatelyRetained])
        #expect(approved.map(\.reason) == [.approvedQuotation])
        #expect(approved[0].kind == .savedMomentStep && approved[0].store == .currentRoutine)
    }

    @Test func editingAnApprovedMomentDoesNotPutItsQuotationUpForRemoval() throws {
        let source = try morning()
        let original = try savedMoment(source)
        let approved = RoutineVersion(sourceLabel: "Your selected saved observation", steps: [original]).approved()
        // Any saved edit makes a new unapproved draft and moves the approved version back.
        var renamed = original
        renamed.title = "A note from Mum"; renamed.durationMinutes = 4; renamed.kind = .wellbeing
        let draft = approved.revised(steps: [renamed], at: now)
        #expect(!draft.isApproved)
        let copies = try plan([source], current: draft, previous: approved).dependents(of: source.id)
        #expect(copies.map(\.store) == [.currentRoutine, .previousRoutine])
        #expect(copies.allSatisfy { $0.disposition == .separatelyRetained && $0.reason == .approvedQuotation })
    }

    @Test func aReworkedStepKeepsItsWordsAndIsNeverListedForRemoval() throws {
        let source = try morning()
        var reworded = try savedMoment(source)
        // Never approved or kept. The words are now the person's own and a stale
        // source reference is all that still names the observation.
        reworded.automation = .spokenNote
        reworded.detail = "Call Mum before the school run."
        var relabelled = try savedMoment(source)
        relabelled.detail = "My own reminder."
        // The editor lets the action go to plain text and back, keeping the reference.
        // New wording that merely ends with the excerpt is still the person's own.
        var extended = try savedMoment(source)
        let quote = try #require(extended.observationReference?.quote)
        extended.detail = "Not on Fridays: " + quote
        #expect(extended.detail.hasSuffix(quote))
        let draft = RoutineVersion(sourceLabel: "Your morning", steps: [
            reworded, relabelled, extended, RoutineStep(title: "Stretch", detail: "Ten slow breaths.")])
        let copies = try plan([source], current: draft).dependents(of: source.id)
        #expect(copies.map(\.stepID) == [reworded.id, relabelled.id, extended.id])
        #expect(copies.map(\.kind) == [.routineStepReference, .savedMomentStep, .savedMomentStep])
        #expect(copies.allSatisfy { $0.disposition == .invalidated && $0.reason == .reworkedStep })
        #expect(!copies.contains { $0.disposition == .removed })
    }

    @Test func anExcerptWhoseSourceChangedCannotBeProvenUntouchedAndIsKept() throws {
        let source = try morning()
        let draft = RoutineVersion(sourceLabel: "Your selected saved observation", steps: [try savedMoment(source)])
        var archive = try ObservationArchive(entries: [source])
        try archive.correct(id: source.id, text: "I review my calendar after lunch.")
        let result = EvidenceRetentionPlan(archive: archive, currentRoutine: draft, previousRoutine: nil,
            session: nil, pendingProposal: nil, preferences: .init(), history: .init(), now: now, maximumAge: week)
        #expect(result.dependents(of: source.id).map(\.reason) == [.reworkedStep])
        // The same holds once the observation is no longer in the archive at all.
        let orphaned = try plan([], current: draft).dependents(of: source.id)
        #expect(orphaned.map(\.disposition) == [.invalidated])
    }

    @Test func wordsCopiedWithoutASourceLinkAreStillListedAndKept() throws {
        let learned = try morning()
        let other = try morning("I stretch before coffee.", day: 1)
        // Accepting a suggestion clears it and leaves its quotations in the routine text.
        let accepted = try proposal(from: [learned]).routine
        #expect(accepted.steps.allSatisfy { $0.observationReference == nil })
        for routine in [accepted, accepted.approved()] {
            let result = try plan([learned, other], current: routine)
            let copies = result.dependents(of: learned.id)
            #expect(copies.map(\.kind) == [.unlinkedStepText] && copies[0].store == .currentRoutine)
            #expect(copies[0].quote == learned.originalText && copies[0].stepID == routine.steps[0].id)
            #expect(copies[0].disposition == .separatelyRetained && copies[0].reason == .unlinkedMatchingText)
            #expect(result.dependents(of: other.id).isEmpty)
        }

        // A saved moment turned into an ordinary note loses its reference, not its words.
        var note = try savedMoment(other)
        note.automation = .spokenNote; note.observationReference = nil
        var journal = RoutinePreferenceJournal()
        try journal.upsert(RoutinePreference(target: note, presence: .keep))
        let draft = RoutineVersion(sourceLabel: "Your morning", steps: [note])
        let kept = try plan([learned, other], current: draft, previous: draft.approved(), preferences: journal)
        let copies = kept.dependents(of: other.id)
        #expect(copies.map(\.store) == [.currentRoutine, .previousRoutine, .preferenceJournal])
        #expect(copies.allSatisfy { $0.kind == .unlinkedStepText && $0.quote == other.originalText
            && $0.disposition == .separatelyRetained })
        #expect(kept.dependents(of: learned.id).isEmpty)

        // Correcting the observation keeps its original text in the archive, so the
        // original excerpt is still found there.
        var corrected = try ObservationArchive(entries: [learned, other])
        try corrected.correct(id: other.id, text: "I stretch before tea.")
        let afterCorrection = EvidenceRetentionPlan(archive: corrected, currentRoutine: draft, previousRoutine: nil,
            session: nil, pendingProposal: nil, preferences: journal, history: .init(), now: now, maximumAge: week)
        #expect(afterCorrection.dependents(of: other.id).map(\.store) == [.currentRoutine, .preferenceJournal])
    }

    @Test func evidenceLinesAreStillFoundAfterTheTextAroundThemIsEdited() throws {
        let learned = try morning()
        var step = try #require(try proposal(from: [learned]).routine.steps.first)
        let quote = learned.originalText
        // The introduction is cut so the evidence line comes first, and a remark with
        // its own quotation marks is added after it.
        step.detail = "Evidence: “\(quote)”\nRemember “coffee” too."
        let draft = RoutineVersion(sourceLabel: "Your morning", steps: [step])
        let copies = try plan([learned], current: draft).dependents(of: learned.id)
        #expect(copies.map(\.quote) == [quote])
        #expect(copies.map(\.disposition) == [.separatelyRetained])
        // A quotation with its own marks is reported whole, not cut at the first one.
        let marked = try morning("I choose “tea” before breakfast.", day: 1)
        step.detail = "Evidence: “\(marked.originalText)”\nRemember “coffee” too."
        #expect(try plan([marked], current: RoutineVersion(sourceLabel: "Your morning", steps: [step]))
            .dependents(of: marked.id).map(\.quote) == [marked.originalText])
        // So is an untouched quotation that happens to contain the marker itself.
        let nested = try morning("I review Evidence: “the calendar” after breakfast.", day: 2)
        let accepted = try proposal(from: [nested]).routine.approved()
        #expect(try plan([nested], current: accepted).dependents(of: nested.id).map(\.quote) == [nested.originalText])
        // Two spellings of the same letters are two quotations, both listed.
        let spelled = try morning("I review caf\u{00E9}.\nI review cafe\u{0301}.", day: 3)
        step.detail = "Evidence: “I review caf\u{00E9}.”\nEvidence: “I review cafe\u{0301}.”"
        let spellings = try plan([spelled], current: RoutineVersion(sourceLabel: "Your morning", steps: [step]))
            .dependents(of: spelled.id).compactMap { $0.quote.map { Array($0.utf8) } }
        #expect(spellings == [Array("I review caf\u{00E9}.".utf8), Array("I review cafe\u{0301}.".utf8)])
        // An observation that itself looks like evidence lines cannot hide a quotation.
        let tricky = try morning("I review my calendar.”\nEvidence: “I review “mail\nI review “mail” carefully.", day: 4)
        step.detail = "Evidence: “I review my calendar.”\nEvidence: “I review “mail” carefully.”"
        let tricked = try plan([tricky], current: RoutineVersion(sourceLabel: "Your morning", steps: [step]))
            .dependents(of: tricky.id).compactMap(\.quote)
        #expect(tricked.contains("I review “mail” carefully.") && tricked.count == 2)
        // A quotation running over several lines is not cut at a shorter whole line.
        let long = try morning("I review\nI review” then\nmy bank statement.", day: 5)
        step.detail = "Evidence: “I review” then\nmy bank statement.”"
        #expect(try plan([long], current: RoutineVersion(sourceLabel: "Your morning", steps: [step]))
            .dependents(of: long.id).map(\.quote) == ["I review” then\nmy bank statement."])
        // A few typed letters after the marker would match nearly any observation.
        step.detail = "Evidence: “review”\nEvidence: “ ”\nEvidence: “I review”"
        #expect(try plan([learned], current: RoutineVersion(sourceLabel: "Your morning", steps: [step]))
            .dependents(of: learned.id).map(\.quote) == ["I review"])
        // Retyped words are not the observation's words and are not listed.
        step.detail = "Evidence: “I look at my diary once I have eaten.”"
        #expect(try plan([learned], current: RoutineVersion(sourceLabel: "Your morning", steps: [step]))
            .dependentCopies.isEmpty)
    }

    @Test("An edited evidence line is found under every label a detail was saved with",
          arguments: EvidenceDetailText.savedLabels)
    func evidenceLinesAreFoundInEverySavedLanguage(label: String) throws {
        let learned = try morning()
        var step = try #require(try proposal(from: [learned]).routine.steps.first)
        // Not a whole line of the observation, so only the label can find it.
        let quote = String(learned.originalText.dropLast(2))
        #expect(quote.count >= 8)
        step.detail = "\(label) “\(quote)”\nRemember “coffee” too."
        let copies = try plan([learned], current: RoutineVersion(sourceLabel: "Your morning", steps: [step]))
            .dependents(of: learned.id)
        #expect(copies.contains { $0.quote == quote })
    }

    @Test func aKeptLearnedStepInsideANewSuggestionFromTheSameMorningIsListed() throws {
        let learned = try morning()
        let approved = try proposal(from: [learned]).routine.approved()
        let keptStep = try #require(approved.steps.first)
        var journal = RoutinePreferenceJournal()
        try journal.upsert(RoutinePreference(target: keptStep, presence: .keep))
        let evidence = try LearningEvidencePreparation.prepare(acquisitions: [learned])
        let again = try LearningEvidencePreparation.assemble(evidence: evidence, steps: evidence.units.map {
            EvidenceRoutineStepInput(title: "Stretch", detail: "Consider a short stretch.", kind: .wellbeing,
                durationMinutes: 2, citations: [.init(unitID: $0.id, quote: $0.text)])
        }, preserving: approved, preferences: journal, at: now)
        #expect(again.support.first { $0.stepID == keptStep.id }?.citations.isEmpty == true)
        let result = try plan([learned], current: approved, proposal: again, preferences: journal)
        let inSuggestion = result.dependents(of: learned.id).filter { $0.store == .pendingProposal }
        // The source and the new step's citation, then the kept step's words in the
        // suggested routine and in the suggestion's copy of the saved choices.
        #expect(inSuggestion.map(\.kind) == [.proposalSource, .proposalCitation, .unlinkedStepText, .unlinkedStepText])
        #expect(inSuggestion.suffix(2).allSatisfy { $0.stepID == keptStep.id && $0.quote == learned.originalText
            && $0.reason == .insideDiscardedSuggestion })
        // The person's own copies stay, each listed.
        let own = result.dependents(of: learned.id).filter { $0.store != .pendingProposal }
        #expect(own.map(\.store) == [.currentRoutine, .preferenceJournal])
        #expect(own.allSatisfy { $0.disposition == .separatelyRetained })
    }

    @Test func aSecondLineOfTheSameObservationInAKeptMomentIsListedToo() throws {
        let source = try morning("A quiet cup of tea.\nA little time to play.")
        var step = try savedMoment(source)
        let quote = try #require(step.observationReference?.quote)
        #expect(quote == "A quiet cup of tea.")
        step.detail += "\nA little time to play."
        var journal = RoutinePreferenceJournal()
        try journal.upsert(RoutinePreference(target: step, presence: .keep))
        let draft = RoutineVersion(sourceLabel: "Your morning", steps: [step])
        let copies = try plan([source], current: draft, preferences: journal).dependents(of: source.id)
        #expect(copies.map(\.quote) == ["A little time to play.", quote, "A little time to play.", quote])
        #expect(copies.map(\.store) == [.currentRoutine, .currentRoutine, .preferenceJournal, .preferenceJournal])
        #expect(copies.allSatisfy { $0.disposition == .separatelyRetained })
    }

    @Test func forgettingOneMorningInvalidatesOnlyTheSuggestionBuiltFromIt() throws {
        let cited = try morning()
        let other = try morning("I stretch before coffee.", day: 1)
        let pending = try proposal(from: [cited])
        let archive = try ObservationArchive(entries: [cited, other])
        #expect(pending.isCurrent(archive: archive, baseRoutine: nil))
        let result = try plan([cited, other], proposal: pending)

        let copies = result.dependents(of: cited.id)
        #expect(copies.map(\.kind) == [.proposalSource, .proposalCitation])
        #expect(copies.allSatisfy { $0.store == .pendingProposal && $0.disposition == .invalidated })
        #expect(copies[1].quote == pending.support[0].citations[0].quote)
        #expect(copies[1].stepID == pending.routine.steps[0].id)
        #expect(result.invalidatesPendingProposal(forgetting: cited.id))

        #expect(result.dependents(of: other.id).isEmpty)
        #expect(!result.invalidatesPendingProposal(forgetting: other.id))

        // The plan agrees with what the saved suggestion itself reports afterwards.
        var withoutCited = archive; try withoutCited.delete(id: cited.id)
        var withoutOther = archive; try withoutOther.delete(id: other.id)
        #expect(!pending.isCurrent(archive: withoutCited, baseRoutine: nil))
        #expect(pending.isCurrent(archive: withoutOther, baseRoutine: nil))
    }

    @Test func aKeptMomentCarriedIntoASuggestionStaysWithIt() throws {
        let quoted = try morning("A quiet cup of tea.")
        let learned = try morning(day: 1)
        let step = try savedMoment(quoted)
        var journal = RoutinePreferenceJournal()
        try journal.upsert(RoutinePreference(target: step, presence: .keep))
        let pending = try proposal(from: [learned], preferences: journal)
        #expect(pending.routine.steps.contains { $0.observationReference?.acquisitionID == quoted.id })
        let result = try plan([quoted, learned], proposal: pending, preferences: journal)

        let copies = result.dependents(of: quoted.id)
        #expect(copies.map(\.store) == [.pendingProposal, .pendingProposal, .preferenceJournal])
        #expect(copies.map(\.kind) == [.savedMomentStep, .keptChoiceSnapshot, .keptChoiceSnapshot])
        #expect(copies.allSatisfy { $0.disposition == .separatelyRetained && $0.reason == .keptChoice })
        #expect(!result.invalidatesPendingProposal(forgetting: quoted.id))
        var remaining = try ObservationArchive(entries: [quoted, learned]); try remaining.delete(id: quoted.id)
        #expect(pending.isCurrent(archive: remaining, baseRoutine: nil, preferences: journal))

        #expect(result.invalidatesPendingProposal(forgetting: learned.id))

        // After the Keep is cleared the suggestion is stale for that reason alone.
        // Its copies are still listed and never put up for removal.
        let cleared = try plan([quoted, learned], proposal: pending)
        #expect(cleared.dependents(of: quoted.id).count == 2)
        #expect(cleared.dependents(of: quoted.id).allSatisfy { $0.disposition == .separatelyRetained })
        #expect(!cleared.invalidatesPendingProposal(forgetting: quoted.id))
        #expect(!pending.isCurrent(archive: remaining, baseRoutine: nil, preferences: RoutinePreferenceJournal()))
    }

    @Test func aRequiredMomentWithoutASavedChoiceIsKeptAndLeavesTheSuggestionValid() throws {
        let quoted = try morning("A quiet cup of tea.")
        let learned = try morning(day: 1)
        var step = try savedMoment(quoted)
        step.isRequired = true
        // An older workspace: the required flag is the only record of the choice.
        let draft = RoutineVersion(sourceLabel: "Your morning", steps: [step])
        let evidence = try LearningEvidencePreparation.prepare(acquisitions: [learned])
        let pending = try LearningEvidencePreparation.assemble(evidence: evidence, steps: evidence.units.map {
            EvidenceRoutineStepInput(title: "Review calendar", detail: "Consider a short calendar review.",
                kind: .calendar, durationMinutes: 3, citations: [.init(unitID: $0.id, quote: $0.text)])
        }, preserving: draft, at: now)
        let result = try plan([quoted, learned], current: draft, proposal: pending)
        let copies = result.dependents(of: quoted.id)
        #expect(copies.map(\.store) == [.currentRoutine, .pendingProposal])
        #expect(copies.allSatisfy { $0.disposition == .separatelyRetained && $0.reason == .markedRequired })
        #expect(!result.invalidatesPendingProposal(forgetting: quoted.id))
        var remaining = try ObservationArchive(entries: [quoted, learned]); try remaining.delete(id: quoted.id)
        #expect(pending.isCurrent(archive: remaining, baseRoutine: draft))
    }

    @Test func missingImportDateIsUnknownAgeAndNeverExpires() throws {
        let undated = try morning(age: nil)
        let old = try morning("I stretch before coffee.", age: 400 * 86_400, day: 1)
        for limit: TimeInterval in [0, week, 100 * 365 * 86_400] {
            let result = try plan([undated, old], maximumAge: limit)
            #expect(result.unknownAgeAcquisitionIDs == [undated.id])
            #expect(!result.expiredAcquisitionIDs.contains(undated.id))
        }
        #expect(try plan([undated, old]).expiredAcquisitionIDs == [old.id])
    }

    @Test func anObservationExactlyAtTheMaximumAgeIsNotExpired() throws {
        let atLimit = try morning(age: week)
        let justOver = try morning("I stretch before coffee.", age: week + 1, day: 1)
        let fresh = try morning("I water the plants.", age: 60, day: 2)
        let future = try morning("I open the shutters.", age: -3_600, day: 3)
        let entries = [atLimit, justOver, fresh, future]
        let result = try plan(entries)
        #expect(result.expiredAcquisitionIDs == [justOver.id])
        #expect(result.unknownAgeAcquisitionIDs.isEmpty)
        // An unusable limit expires nothing instead of everything.
        for limit: TimeInterval in [-1, .nan, .infinity, -.infinity] {
            #expect(try plan(entries, maximumAge: limit).expiredAcquisitionIDs.isEmpty)
        }
        #expect(try plan(entries, maximumAge: 0).expiredAcquisitionIDs == [atLimit.id, justOver.id, fresh.id])
        for clock in [Date(timeIntervalSince1970: .infinity), Date(timeIntervalSince1970: .nan)] {
            let broken = EvidenceRetentionPlan(archive: try ObservationArchive(entries: entries), currentRoutine: nil,
                previousRoutine: nil, session: nil, pendingProposal: nil, preferences: .init(), history: .init(), now: clock, maximumAge: week)
            #expect(broken.expiredAcquisitionIDs.isEmpty)
        }
    }

    @Test func anObservationNothingElseHoldsHasNoDependents() throws {
        let lonely = try morning(age: 30 * 86_400)
        let other = try morning("A quiet cup of tea.", day: 1)
        let routine = RoutineVersion(sourceLabel: "Your morning", steps: [
            try savedMoment(other), RoutineStep(title: "Stretch", detail: "Ten slow breaths.")]).approved()
        let result = try plan([lonely, other], current: routine)
        #expect(result.expiredAcquisitionIDs == [lonely.id])
        #expect(result.dependents(of: lonely.id).isEmpty)
        #expect(!result.invalidatesPendingProposal(forgetting: lonely.id))
        #expect(result.dependentCopies.map(\.acquisitionID) == [other.id])
        // Steps and choices that name no observation are never listed.
        #expect(try plan([lonely], current: DemoFixtures.routine).dependentCopies.isEmpty)
    }

    @Test func everyReasonHasOneDispositionAndAPlainExplanation() {
        let retained: Set<EvidenceRetentionReason> = [.approvedQuotation, .keptChoice, .markedRequired, .savedRun,
            .choicesUnavailable, .unlinkedMatchingText]
        for reason in EvidenceRetentionReason.allCases {
            #expect(!reason.explanation.isEmpty)
            #expect((reason.disposition == .separatelyRetained) == retained.contains(reason))
        }
        #expect(EvidenceRetentionReason.allCases.filter { $0.disposition == .removed } == [.unapprovedDraftQuotation])
        #expect(EvidenceRetentionStore.allCases.count == 6)
    }
}
