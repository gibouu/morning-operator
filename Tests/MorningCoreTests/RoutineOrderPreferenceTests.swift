import Foundation
import Testing
@testable import MorningCore

@Suite("Explicit routine order survives renewed observations")
struct RoutineOrderPreferenceTests {
    private func restored(_ journal: RoutinePreferenceJournal) throws -> RoutinePreferenceJournal {
        try JSONDecoder().decode(RoutinePreferenceJournal.self, from: JSONEncoder().encode(journal))
    }
    private func activity(_ title: String, _ kind: StepKind = .custom) -> RoutineStep {
        RoutineStep(title: title, kind: kind, durationMinutes: 2)
    }

    @Test func freshIDsFollowTheRecordedOrderWithoutHidingNewMoments() throws {
        let reading = activity("Read", .wellbeing), mail = activity("Mail", .messages), feed = activity("Feed", .entertainment)
        var journal = RoutinePreferenceJournal()
        let initial = journal.revision
        try journal.rememberOrder(of: [reading, mail, feed])
        let orderedRevision = journal.revision
        #expect(initial != orderedRevision)
        try journal.rememberOrder(of: [reading, mail, feed])
        #expect(journal.revision == orderedRevision)
        // Saving a later duration must not reset the standing order.
        try journal.upsert(.init(target: mail, durationMinutes: 7))
        let loaded = try restored(journal)
        #expect(loaded.order == journal.order && loaded.order?.count == 3)
        let newFirst = activity("Weather"), newMiddle = activity("Water"), newLast = activity("Music")
        let newMail = activity("  MAIL ", .messages), newFeed = activity("Feed", .entertainment), newRead = activity("Read", .wellbeing)
        let result = try loaded.reconcile(steps: [newFirst, newFeed, newMiddle, newMail, newRead, newLast])
        #expect(result.steps.map(\.id) == [newFirst.id, newRead.id, newMiddle.id, newMail.id, newFeed.id, newLast.id])
        #expect(result.steps[3].durationMinutes == 7)
        #expect(result.retainedStepIDs.isEmpty, "An order choice is not Keep.")
        #expect(try loaded.reconcile(steps: result.steps).steps == result.steps)
    }

    @Test func absenceDoesNotKeepAndExclusionStillWins() throws {
        let read = activity("Read"), feed = activity("Feed"), removed = activity("Shopping")
        var journal = RoutinePreferenceJournal()
        try journal.rememberOrder(of: [read, feed, removed])
        try journal.upsert(.init(target: removed, presence: .exclude))
        #expect(try restored(journal).reconcile(steps: [feed, removed]).steps == [feed])
        try journal.upsert(.init(target: read, presence: .keep))
        let result = try restored(journal).reconcile(steps: [feed, removed])
        #expect(result.steps == [read, feed])
        #expect(result.retainedStepIDs == [read.id] && result.excludedStepIDs == [removed.id])
    }

    @Test func exactIdentityWinsButFreshHomonymsNeverGetArbitrarySlots() throws {
        let one = activity("Inbox", .messages), two = activity("Feed", .entertainment)
        var journal = RoutinePreferenceJournal(); try journal.rememberOrder(of: [two, one])
        var renamed = one; renamed.title = "My mailbox"
        let newHomonym = activity("Inbox", .messages)
        #expect(try restored(journal).reconcile(steps: [renamed, newHomonym, two]).steps == [two, newHomonym, renamed])
        #expect(throws: RoutinePreferenceError.ambiguousMatch(one.id)) {
            try journal.reconcile(steps: [activity("Inbox", .messages), newHomonym])
        }
        var colliding = RoutinePreferenceJournal()
        try colliding.rememberOrder(of: [one, newHomonym])
        let fresh = activity("Inbox", .messages)
        #expect(throws: RoutinePreferenceError.conflictingMatch(fresh.id)) { try colliding.reconcile(steps: [fresh]) }
    }

    @Test func forgettingOrderPreservesEveryOtherChoiceAcrossPersistence() throws {
        let read = activity("Read"), mail = activity("Mail"), shopping = activity("Shopping")
        var journal = RoutinePreferenceJournal()
        try journal.rememberOrder(of: [read, mail, shopping])
        try journal.upsert(.init(target: read, presence: .keep))
        try journal.upsert(.init(target: shopping, presence: .exclude))
        try journal.upsert(.init(target: mail, durationMinutes: 7))
        journal = try restored(journal)
        let before = journal
        let cleared = journal.clearOrder()
        #expect(cleared && journal.order == nil && journal.revision != before.revision)
        #expect(journal.entries == before.entries)
        let loaded = try restored(journal)
        #expect(loaded == journal && loaded.order == nil)
        let result = try loaded.reconcile(steps: [mail, shopping, read])
        #expect(result.steps.map(\.id) == [mail.id, read.id])
        #expect(result.steps[0].durationMinutes == 7)
        #expect(result.retainedStepIDs == [read.id] && result.excludedStepIDs == [shopping.id])
        let revision = journal.revision
        let clearedAgain = journal.clearOrder()
        #expect(!clearedAgain && journal.revision == revision && journal.entries == before.entries)
    }

    @Test func legacyAbsenceAndMalformedOrdersRemainDistinct() throws {
        let empty = RoutinePreferenceJournal()
        let bytes = try JSONEncoder().encode(empty)
        #expect(!String(decoding: bytes, as: UTF8.self).contains("order"))
        #expect(try JSONDecoder().decode(RoutinePreferenceJournal.self, from: bytes).order == nil)
        var journal = empty; try journal.rememberOrder(of: [activity("Read")])
        let validObject = try #require(JSONSerialization.jsonObject(with: JSONEncoder().encode(journal)) as? [String: Any])
        let row = try #require((validObject["order"] as? [[String: Any]])?.first)
        var badTitle = row; badTitle["targetTitle"] = "Read\nsecret"
        var hugeTitle = row; hugeTitle["targetTitle"] = String(repeating: "x", count: 2_001)
        var blankTitle = row; blankTitle["targetTitle"] = "  "
        for invalid in [NSNull(), "bad order", [Any](), [row, row], [badTitle], [hugeTitle], [blankTitle], Array(repeating: row, count: 11)] as [Any] {
            var object = validObject; object["order"] = invalid
            let invalidBytes = try JSONSerialization.data(withJSONObject: object)
            #expect(throws: (any Error).self) { try JSONDecoder().decode(RoutinePreferenceJournal.self, from: invalidBytes) }
        }
        let before = journal
        #expect(throws: RoutinePreferenceError.invalidPreference) { try journal.rememberOrder(of: (1...11).map { activity("Step \($0)") }) }
        #expect(journal == before, "A rejected edit must preserve the old choice.")
        let cleared = journal.clear()
        #expect(cleared && journal.order == nil && journal.entries.isEmpty && journal.revision != before.revision)
        let clearedAgain = journal.clear()
        #expect(!clearedAgain)
    }
}
