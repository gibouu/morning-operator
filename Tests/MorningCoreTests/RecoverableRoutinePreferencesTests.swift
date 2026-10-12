import Foundation
import Testing
@testable import MorningCore

@Suite("Recoverable routine preference storage")
struct RecoverableRoutinePreferencesTests {
    private func decode(_ object: [String: Any]) throws -> RecoverableRoutinePreferences {
        try JSONDecoder().decode(RecoverableRoutinePreferences.self,
            from: JSONSerialization.data(withJSONObject: object))
    }

    private func object(_ recovery: RecoverableRoutinePreferences) throws -> NSDictionary {
        try #require(JSONSerialization.jsonObject(with: JSONEncoder().encode(recovery)) as? NSDictionary)
    }

    private func validObject() throws -> [String: Any] {
        var journal = RoutinePreferenceJournal()
        try journal.upsert(RoutinePreference(target: RoutineStep(title: "Chess", kind: .entertainment),
            presence: .keep, durationMinutes: 12))
        return try #require(JSONSerialization.jsonObject(with: JSONEncoder().encode(journal)) as? [String: Any])
    }

    @Test("A valid explicit empty journal remains present instead of becoming a legacy migration")
    func validAndExplicitEmptyRemainValid() throws {
        let empty = RoutinePreferenceJournal()
        let wrapped = RecoverableRoutinePreferences(empty)
        let loaded = try JSONDecoder().decode(RecoverableRoutinePreferences.self, from: JSONEncoder().encode(wrapped))
        #expect(loaded.value == empty)
        let nonempty = try decode(validObject())
        #expect(nonempty.value?.entries.count == 1)
        #expect(nonempty.value?.entries.first?.durationMinutes == 12)
    }

    @Test("Invalid fields and unknown choices remain unreadable after encoding again")
    func malformedChoicesAreRetainedUntilReset() throws {
        let original = try validObject()
        let originalEntries = try #require(original["entries"] as? [[String: Any]])
        var invalidDuration = original
        var durationEntries = originalEntries
        durationEntries[0]["durationMinutes"] = 121
        invalidDuration["entries"] = durationEntries

        var unknownPresence = original
        var presenceEntries = originalEntries
        presenceEntries[0]["presence"] = "some-future-choice"
        unknownPresence["entries"] = presenceEntries

        var invalidRevision = original
        invalidRevision["revision"] = ["unrecognized": true]
        for malformed in [invalidDuration, unknownPresence, invalidRevision] {
            let recovery = try decode(malformed)
            #expect(recovery.value == nil)
            #expect(try object(recovery) == (malformed as NSDictionary))
            let reloaded = try JSONDecoder().decode(RecoverableRoutinePreferences.self, from: JSONEncoder().encode(recovery))
            #expect(reloaded.value == nil)
            #expect(try object(reloaded) == (malformed as NSDictionary))
        }
    }

    @Test("An unrelated atomic save preserves unknown nested preferences and the current routine")
    func unrelatedSaveDoesNotEraseRecoveryPayload() throws {
        struct Workspace: Codable, Sendable {
            var routine: RoutineVersion
            var preferences: RecoverableRoutinePreferences
            var unrelatedSetting: Bool
        }
        let malformed: [String: Any] = [
            "entries": "cannot-decode-this-as-a-journal",
            "future": ["nested": [true, false, NSNull(), "Café 🌅", -3, 0.25] as [Any]],
            "largeInteger": UInt64.max
        ]
        let routine = RoutineVersion(sourceLabel: "Synthetic test", steps: [RoutineStep(title: "Breakfast")], isApproved: true)
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent("morning-preference-recovery-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: directory) }
        let file = AtomicJSONFile<Workspace>(url: directory.appendingPathComponent("workspace.json"))
        try file.save(Workspace(routine: routine, preferences: decode(malformed), unrelatedSetting: false))
        var restored = try file.load()
        restored.unrelatedSetting = true
        try file.save(restored)
        let reloaded = try file.load()
        #expect(reloaded.routine == routine)
        #expect(reloaded.unrelatedSetting)
        #expect(reloaded.preferences.value == nil)
        #expect(try object(reloaded.preferences) == (malformed as NSDictionary))
    }

    @Test("A present null or primitive remains an unreadable marker, not an empty journal")
    func nullAndMigrationMarkersSurviveRoundTrip() throws {
        for source in ["null", "true", "123", "[]", "\"unreadable legacy choices\""] {
            let decoded = try JSONDecoder().decode(RecoverableRoutinePreferences.self, from: Data(source.utf8))
            #expect(decoded.value == nil)
            let encoded = try JSONEncoder().encode(decoded)
            #expect(String(decoding: encoded, as: UTF8.self) == source)
            let reloaded = try JSONDecoder().decode(RecoverableRoutinePreferences.self, from: encoded)
            #expect(reloaded.value == nil)
        }
        let marker = RecoverableRoutinePreferences(unreadable: "Legacy choices need repair")
        let reloaded = try JSONDecoder().decode(RecoverableRoutinePreferences.self, from: JSONEncoder().encode(marker))
        #expect(reloaded.value == nil)
        let reset = RecoverableRoutinePreferences(RoutinePreferenceJournal())
        let resetLoaded = try JSONDecoder().decode(RecoverableRoutinePreferences.self, from: JSONEncoder().encode(reset))
        #expect(resetLoaded.value?.entries.isEmpty == true)
    }
}
