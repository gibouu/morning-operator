import Foundation
import Testing
@testable import MorningCore

@Suite("Durable user routine preferences")
struct RoutinePreferenceTests {
    private func expectThrows(_ expected: RoutinePreferenceError, _ operation: () throws -> Void) {
        do { try operation(); Issue.record("Expected the preference operation to fail") }
        catch { #expect(error as? RoutinePreferenceError == expected) }
    }

    private func restored(_ journal: RoutinePreferenceJournal) throws -> RoutinePreferenceJournal {
        try JSONDecoder().decode(RoutinePreferenceJournal.self, from: JSONEncoder().encode(journal))
    }

    @Test("Empty defaults and no-op edits do not invalidate a proposal snapshot")
    func emptyAndNoopRevisionsAreStable() throws {
        var journal = RoutinePreferenceJournal()
        #expect(journal == RoutinePreferenceJournal())
        let emptyRevision = journal.revision
        let removedMissing = journal.remove(targetID: UUID())
        let clearedEmpty = journal.clear()
        #expect(!removedMissing && !clearedEmpty)
        #expect(journal.revision == emptyRevision)

        let step = RoutineStep(title: "Chess", kind: .entertainment)
        let preference = try RoutinePreference(target: step, presence: .keep)
        try journal.upsert(preference)
        let firstRevision = journal.revision
        #expect(firstRevision != emptyRevision)
        try journal.upsert(preference)
        #expect(journal.revision == firstRevision)
        #expect(try restored(journal) == journal)
        let removed = journal.remove(targetID: step.id)
        #expect(removed)
        #expect(journal.entries.isEmpty)
        #expect(journal.revision != firstRevision)
    }

    @Test("A kept moment retains every user-owned field through fresh model IDs and relaunch")
    func keepUsesFullSnapshotAndStableIdentity() throws {
        let kept = RoutineStep(title: "  Read my note  ", detail: "My exact words. 🌅",
            kind: .briefing, durationMinutes: 9, isRequired: false, automation: .spokenNote)
        let generated = RoutineStep(title: "read MY note", detail: "An inferred replacement",
            kind: .briefing, durationMinutes: 2, isRequired: true, automation: .todayCalendar)
        let other = RoutineStep(title: "Stretch")
        var journal = RoutinePreferenceJournal()
        try journal.upsert(RoutinePreference(target: kept, presence: .keep))
        journal = try restored(journal)

        let result = try journal.reconcile(steps: [other, generated])
        #expect(result.steps == [other, kept])
        #expect(result.retainedStepIDs == [kept.id])
        #expect(result.durationOverriddenStepIDs.isEmpty)
        #expect(result.appliedPreferenceIDsByStepID == [kept.id: [kept.id]])
        #expect(try journal.reconcile(steps: result.steps) == result)
        #expect(try journal.reconcile(steps: [other]).steps == [other, kept])
    }

    @Test("A duration choice changes only a matched duration and does not add an absent activity")
    func durationOnlyMatchesConservativelyWithoutInserting() throws {
        let target = RoutineStep(title: "Morning chess", kind: .entertainment, durationMinutes: 8)
        let proposed = RoutineStep(title: " MORNING\n  chess ", detail: "New observed detail",
            kind: .entertainment, durationMinutes: 3)
        var expected = proposed
        expected.durationMinutes = 12
        var journal = RoutinePreferenceJournal()
        try journal.upsert(RoutinePreference(target: target, durationMinutes: 12))
        let result = try journal.reconcile(steps: [proposed])
        #expect(result.steps == [expected])
        #expect(result.retainedStepIDs.isEmpty)
        #expect(result.durationOverriddenStepIDs == [proposed.id])
        #expect(result.appliedPreferenceIDsByStepID == [proposed.id: [target.id]])
        #expect(try journal.reconcile(steps: result.steps) == result)
        #expect(try journal.reconcile(steps: []).steps.isEmpty)

        let punctuation = RoutineStep(title: "Morning chess!", kind: .entertainment)
        let otherKind = RoutineStep(title: "Morning chess", kind: .custom)
        #expect(try journal.reconcile(steps: [punctuation, otherKind]).steps == [punctuation, otherKind])
        #expect(try journal.matchingPreference(for: proposed)?.id == target.id)
    }

    @Test("An explicit duration can override a kept snapshot without replacing its operation or content")
    func keepAndDurationCombine() throws {
        let kept = RoutineStep(title: "My calendar", detail: "Leave space between meetings",
            kind: .calendar, durationMinutes: 7, isRequired: true, automation: .todayCalendar)
        var journal = RoutinePreferenceJournal()
        try journal.upsert(RoutinePreference(target: kept, presence: .keep, durationMinutes: 4))
        var expected = kept
        expected.durationMinutes = 4
        let result = try journal.reconcile(steps: [])
        #expect(result.steps == [expected])
        #expect(result.retainedStepIDs == [kept.id])
        #expect(result.durationOverriddenStepIDs == [kept.id])
        #expect(try restored(journal).reconcile(steps: result.steps) == result)
    }

    @Test("Exclusions survive relaunch and defeat a legacy required-row reinsertion")
    func exclusionRemovesRequiredAndFreshIdentity() throws {
        let removed = RoutineStep(title: "Social feed", kind: .entertainment, isRequired: true)
        let kept = RoutineStep(title: "Breakfast")
        let previous = RoutineVersion(sourceLabel: "Personal morning", steps: [removed, kept], isApproved: true)
        let candidate = RoutineVersion(sourceLabel: "Observed", steps: [kept])
        let legacy = RoutineVersion.inferredDraft(from: candidate, preserving: previous)
        #expect(legacy.steps.contains { $0.id == removed.id })
        var journal = RoutinePreferenceJournal()
        try journal.upsert(RoutinePreference(target: removed, presence: .exclude, durationMinutes: 2))
        journal = try restored(journal)
        let result = try journal.reconcile(steps: legacy.steps)
        #expect(result.steps == [kept])
        #expect(result.excludedStepIDs == [removed.id])
        #expect(result.durationOverriddenStepIDs.isEmpty)
        #expect(result.appliedPreferenceIDsByStepID.isEmpty)
        let fresh = RoutineStep(title: " SOCIAL feed ", kind: .entertainment)
        #expect(try journal.reconcile(steps: [fresh]).steps.isEmpty)
        let didRemove = journal.remove(targetID: removed.id)
        #expect(didRemove)
        // Explicit-empty callers supply sanitized candidates without legacy retention.
        #expect(try restored(journal).reconcile(steps: [fresh]).steps == [fresh])
    }

    @Test("Ambiguous matching blocks instead of resurrecting or assigning a preference by guess")
    func ambiguityAndConflictingRecordsAreRejected() throws {
        let target = RoutineStep(title: "Chess", kind: .entertainment)
        let first = RoutineStep(title: "Chess", kind: .entertainment)
        let second = RoutineStep(title: " chess ", kind: .entertainment)
        var journal = RoutinePreferenceJournal()
        try journal.upsert(RoutinePreference(target: target, presence: .exclude))
        expectThrows(.ambiguousMatch(target.id)) { _ = try journal.reconcile(steps: [first, second]) }
        expectThrows(.ambiguousMatch(target.id)) { _ = try journal.reconcile(steps: [target, first]) }
        let snapshot = journal
        let otherTarget = RoutineStep(title: "Chess", kind: .entertainment)
        try journal.upsert(RoutinePreference(target: otherTarget, durationMinutes: 9))
        expectThrows(.conflictingMatch(first.id)) { _ = try journal.reconcile(steps: [first]) }
        expectThrows(.ambiguousMatch(first.id)) { _ = try journal.matchingPreference(for: first) }
        #expect(snapshot.entries.count == 1)
        #expect(journal.entries.count == 2)
    }

    @Test("An exact step identity still matches after the user renames or recategorizes it")
    func exactIdentityWinsWithoutFuzzyTitleMatching() throws {
        let target = RoutineStep(title: "Read", kind: .messages)
        let renamed = RoutineStep(id: target.id, title: "Morning correspondence", detail: "Changed by me",
            kind: .custom, durationMinutes: 6)
        let sameKeyOtherID = RoutineStep(title: "Read", kind: .messages)
        var journal = RoutinePreferenceJournal()
        try journal.upsert(RoutinePreference(target: target, durationMinutes: 11))
        let result = try journal.reconcile(steps: [sameKeyOtherID, renamed])
        #expect(result.steps[0] == sameKeyOtherID)
        #expect(result.steps[1].id == target.id)
        #expect(result.steps[1].title == renamed.title)
        #expect(result.steps[1].detail == renamed.detail)
        #expect(result.steps[1].kind == renamed.kind)
        #expect(result.steps[1].durationMinutes == 11)
        #expect(try journal.matchingPreference(for: renamed)?.targetID == target.id)
    }

    @Test("Replacing keep with exclude and clearing the journal are durable explicit choices")
    func choiceTransitionsAndClearDoNotRetainAnOldKeep() throws {
        let step = RoutineStep(title: "Chess", kind: .entertainment, isRequired: true)
        var journal = RoutinePreferenceJournal()
        try journal.upsert(RoutinePreference(target: step, presence: .keep))
        try journal.upsert(RoutinePreference(target: step, presence: .exclude))
        #expect(journal.entries.count == 1)
        #expect(journal.entries[0].retainedStep == nil)
        #expect(try restored(journal).reconcile(steps: [step]).steps.isEmpty)
        let beforeClear = journal.revision
        let cleared = journal.clear()
        #expect(cleared)
        #expect(journal.revision != beforeClear)
        #expect(try restored(journal).reconcile(steps: []).steps.isEmpty)
        #expect(try journal.reconcile(steps: [step]).steps == [step])
    }

    @Test("Invalid choices and duplicate identities cannot become persisted preferences")
    func invalidChoicesAndDecodingAreRejected() throws {
        let step = RoutineStep(title: "Chess")
        expectThrows(.invalidPreference) { _ = try RoutinePreference(target: step) }
        expectThrows(.invalidPreference) { _ = try RoutinePreference(target: step, durationMinutes: 0) }
        expectThrows(.invalidPreference) { _ = try RoutinePreference(target: step, durationMinutes: 121) }
        expectThrows(.invalidPreference) {
            _ = try RoutinePreference(target: RoutineStep(title: " \n "), presence: .keep)
        }
        let preference = try RoutinePreference(target: step, presence: .keep)
        expectThrows(.invalidPreference) {
            _ = try RoutinePreferenceJournal(entries: [preference, preference], revision: UUID())
        }
        var object = try #require(JSONSerialization.jsonObject(with: JSONEncoder().encode(preference)) as? [String: Any])
        object["durationMinutes"] = 121
        let invalidDuration = try JSONSerialization.data(withJSONObject: object)
        expectThrows(.invalidPreference) { _ = try JSONDecoder().decode(RoutinePreference.self, from: invalidDuration) }
        object.removeValue(forKey: "durationMinutes")
        object.removeValue(forKey: "retainedStep")
        let missingKeepSnapshot = try JSONSerialization.data(withJSONObject: object)
        expectThrows(.invalidPreference) { _ = try JSONDecoder().decode(RoutinePreference.self, from: missingKeepSnapshot) }

        let validObject = try #require(JSONSerialization.jsonObject(with: JSONEncoder().encode(preference)) as? [String: Any])
        let duplicateDocument = try JSONSerialization.data(withJSONObject: [
            "entries": [validObject, validObject], "revision": UUID().uuidString
        ])
        expectThrows(.invalidPreference) { _ = try JSONDecoder().decode(RoutinePreferenceJournal.self, from: duplicateDocument) }
        var mismatchedIdentity = validObject
        mismatchedIdentity["targetID"] = UUID().uuidString
        let mismatchedDocument = try JSONSerialization.data(withJSONObject: mismatchedIdentity)
        expectThrows(.invalidPreference) { _ = try JSONDecoder().decode(RoutinePreference.self, from: mismatchedDocument) }
    }

    @Test("A full journal rejects another choice without changing the saved snapshot")
    func entryCapRejectsAtomically() throws {
        let entries = try (0..<RoutinePreferenceJournal.maximumEntries).map {
            try RoutinePreference(target: RoutineStep(title: "Activity \($0)"), presence: .exclude)
        }
        var journal = try RoutinePreferenceJournal(entries: entries, revision: UUID())
        let before = journal
        let additional = try RoutinePreference(target: RoutineStep(title: "Additional activity"), presence: .exclude)
        expectThrows(.tooManyPreferences) { try journal.upsert(additional) }
        #expect(journal == before)
        let malformed = try JSONSerialization.data(withJSONObject: [
            "entries": try JSONSerialization.jsonObject(with: JSONEncoder().encode(entries + [additional])),
            "revision": UUID().uuidString
        ])
        expectThrows(.tooManyPreferences) { _ = try JSONDecoder().decode(RoutinePreferenceJournal.self, from: malformed) }
    }

    @Test("Retained text is bounded in encoded bytes, with rollback when a new snapshot is too large")
    func encodedSizeCapRejectsAtomically() throws {
        let detail = String(repeating: "🌅", count: 32_000)
        let entries = try (0..<32).map {
            try RoutinePreference(target: RoutineStep(title: "Moment \($0)", detail: detail), presence: .keep)
        }
        var journal = try RoutinePreferenceJournal(entries: entries, revision: UUID())
        let before = journal
        let additional = try RoutinePreference(target: RoutineStep(title: "Another moment", detail: detail), presence: .keep)
        expectThrows(.preferencesTooLarge) { try journal.upsert(additional) }
        #expect(journal == before)
    }

    @Test("Byte-distinct Unicode edits advance the revision even when String equality agrees")
    func exactUserTextChangesInvalidateTheSnapshot() throws {
        let composed = RoutineStep(title: "Café", detail: "Keep this exact note")
        var decomposed = composed
        decomposed.title = "Cafe\u{301}"
        #expect(composed.title == decomposed.title)
        #expect(!composed.title.utf8.elementsEqual(decomposed.title.utf8))
        var journal = RoutinePreferenceJournal()
        try journal.upsert(RoutinePreference(target: composed, presence: .keep))
        let before = journal.revision
        try journal.upsert(RoutinePreference(target: decomposed, presence: .keep))
        #expect(journal.revision != before)
        let reloaded = try restored(journal)
        let kept = try #require(reloaded.entries.first?.retainedStep)
        #expect(kept.title.utf8.elementsEqual(decomposed.title.utf8))
    }
}
