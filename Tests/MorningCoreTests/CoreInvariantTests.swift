import Foundation
import Testing
@testable import MorningCore

@Suite("Morning domain invariants")
struct CoreInvariantTests {
    private func expectThrows<E: Error & Equatable>(_ expected: E, _ operation: () throws -> Void) {
        do { try operation(); Issue.record("Expected an error but the operation succeeded") }
        catch { #expect(error as? E == expected) }
    }

    private func location(_ name: String = "data.json") -> URL {
        FileManager.default.temporaryDirectory.appendingPathComponent("morning-core-tests-\(UUID().uuidString)").appendingPathComponent(name)
    }

    @Test
    func testInvalidRoutineCannotStart() throws {
        var unapproved = RoutineSession(routine: DemoFixtures.candidateRoutine)
        expectThrows(SessionError.routineNeedsApproval) { try unapproved.start() }
        #expect(unapproved.events.isEmpty)
        var empty = RoutineSession(routine: RoutineVersion(sourceLabel: "Test", steps: [], isApproved: true))
        expectThrows(SessionError.emptyRoutine) { try empty.start() }
        let step = RoutineStep(title: "Duplicate ID")
        var duplicate = RoutineSession(routine: RoutineVersion(sourceLabel: "Test", steps: [step, step], isApproved: true))
        expectThrows(SessionError.invalidRoutine) { try duplicate.start() }
    }

    @Test
    func testPinnedVersionAndTransitions() throws {
        let original = DemoFixtures.routine
        var session = RoutineSession(routine: original)
        try session.start()
        expectThrows(SessionError.invalidTransition) { try session.start() }
        try session.pause()
        expectThrows(SessionError.invalidTransition) { try session.advance() }
        try session.resume()
        let updated = original.revised(steps: [RoutineStep(title: "Changed tomorrow")]).approved()
        #expect(session.routine.id == original.id)
        #expect(session.routine.id != updated.id)
        let commandID = UUID()
        try session.advance(skipping: true, commandID: commandID)
        try session.advance(skipping: true, commandID: commandID)
        #expect(session.currentStepIndex == 1)
        while session.status == .running { try session.advance() }
        #expect(session.status == .completed)
        #expect(session.currentStep == nil)
        #expect(session.skippedStepIDs == [original.steps[0].id])
        #expect(session.completedStepIDs.count == original.steps.count - 1)
        #expect(session.progress == 1)
        expectThrows(SessionError.invalidTransition) { try session.advance() }
    }

    @Test
    func testProposalsKeepPreferences() throws {
        let original = DemoFixtures.routine
        let requiredCandidate = original.steps.first(where: { $0.isRequired })
        let required = try #require(requiredCandidate)
        let preference = RoutineStepPreference(stepID: required.id, isRequired: true, durationMinutes: 12)
        let proposal = original.proposing(steps: [original.steps[0]], preserving: [preference])
        #expect(!proposal.isApproved)
        #expect(proposal.number == original.number + 1)
        #expect(proposal.id != original.id)
        #expect(proposal.steps.last?.id == required.id)
        #expect(proposal.steps.last?.durationMinutes == 12)
        #expect(proposal.steps.last?.isRequired == true)
        // Explicit user edits can remove the same ritual; inference cannot.
        #expect(original.revised(steps: [original.steps[0]]).steps.count == 1)
    }

    @Test
    func testPersistenceAndSchema() throws {
        struct WorkspaceSnapshot: Codable, Sendable, Equatable {
            let routine: RoutineVersion?
            let session: RoutineSession?
        }
        let url = location()
        defer { try? FileManager.default.removeItem(at: url.deletingLastPathComponent()) }
        let routine = DemoFixtures.routine
        var session = RoutineSession(routine: routine)
        try session.start(); try session.advance(); try session.pause()
        let snapshot = WorkspaceSnapshot(routine: routine, session: session)
        let file = AtomicJSONFile<WorkspaceSnapshot>(url: url)
        try file.save(snapshot)
        #expect(try file.load() == snapshot)
        let attributes = try FileManager.default.attributesOfItem(atPath: url.path)
        #expect((attributes[.posixPermissions] as? NSNumber)?.intValue == 0o600)
        try Data("{\"schemaVersion\":999,\"value\":null}".utf8).write(to: url)
        expectThrows(PersistenceError.unsupportedSchema(999)) { _ = try file.load() }
    }

    @Test("Replacing a saved document commits the complete private replacement")
    func testPersistenceReplacementIsPrivateAndReadable() throws {
        let url = location("workspace.json")
        let directory = url.deletingLastPathComponent()
        defer { try? FileManager.default.removeItem(at: directory) }
        let file = AtomicJSONFile<[String]>(url: url)
        try file.save(["Previously approved morning"])
        try FileManager.default.setAttributes([.posixPermissions: 0o644], ofItemAtPath: url.path)

        let replacement = ["Reviewed update", "Exact source quotation", "Previous routine retained"]
        try file.save(replacement)
        #expect(try file.load() == replacement)
        let attributes = try FileManager.default.attributesOfItem(atPath: url.path)
        #expect((attributes[.posixPermissions] as? NSNumber)?.intValue == 0o600)
        #expect(try FileManager.default.contentsOfDirectory(atPath: directory.path) == ["workspace.json"])
    }

    @Test("A rejected commit preserves the destination and removes staged content")
    func testPersistenceRejectedRenameLeavesDestinationIntact() throws {
        let url = location("workspace.json")
        let directory = url.deletingLastPathComponent()
        defer { try? FileManager.default.removeItem(at: directory) }
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        let sentinel = url.appendingPathComponent("keep.txt")
        let existing = Data("Existing destination contents".utf8)
        try existing.write(to: sentinel)

        do {
            try AtomicJSONFile<[String]>(url: url).save(["Must not replace a directory"])
            Issue.record("Replacing a destination directory unexpectedly succeeded")
        } catch { #expect(error is POSIXError) }
        #expect(try Data(contentsOf: sentinel) == existing)
        #expect(try FileManager.default.contentsOfDirectory(atPath: url.path) == ["keep.txt"])
        #expect(try FileManager.default.contentsOfDirectory(atPath: directory.path) == ["workspace.json"])
    }

    @Test("Encoding failure leaves the previously saved document readable and unchanged")
    func testPersistenceEncodingFailurePreservesPreviousBytes() throws {
        let url = location("workspace.json")
        let directory = url.deletingLastPathComponent()
        defer { try? FileManager.default.removeItem(at: directory) }
        let file = AtomicJSONFile<Double>(url: url)
        try file.save(42)
        let previous = try Data(contentsOf: url)
        do {
            try file.save(.nan)
            Issue.record("JSON unexpectedly accepted a non-finite value")
        } catch { #expect(error is EncodingError) }
        #expect(try Data(contentsOf: url) == previous)
        #expect(try file.load() == 42)
        #expect(try FileManager.default.contentsOfDirectory(atPath: directory.path) == ["workspace.json"])
    }

    @Test
    func testApprovalCannotDrift() {
        let now = Date(timeIntervalSince1970: 1_800_000_000)
        let intent = ActionIntent(kind: .sendMessage, accountID: "account-A", targetID: "recipient-A", payloadFingerprint: "digest-A", createdAt: now)
        let approval = ActionApproval.exact(for: intent, at: now, expiresAt: now.addingTimeInterval(60))
        #expect(approval.allows(intent, at: now))
        let changed = ActionIntent(id: intent.id, kind: .sendMessage, accountID: "account-A", targetID: "recipient-A", payloadFingerprint: "digest-B", createdAt: now)
        #expect(!approval.allows(changed, at: now))
        #expect(!approval.allows(intent, at: now.addingTimeInterval(60)))
        var revoked = approval; revoked.revokedAt = now
        #expect(!revoked.allows(intent, at: now))
        let standing = ActionApproval.standing(kind: .sendMessage, accountID: "account-A", targetID: "recipient-A", at: now)
        #expect(standing.allows(changed, at: now))
        let otherAccount = ActionIntent(kind: .sendMessage, accountID: "account-B", targetID: "recipient-A", payloadFingerprint: "digest-A", createdAt: now)
        #expect(!standing.allows(otherAccount, at: now))
    }

    @Test
    func testInterruptedDispatchReconciles() async throws {
        let url = location("journal.json")
        defer { try? FileManager.default.removeItem(at: url.deletingLastPathComponent()) }
        let intent = ActionIntent(kind: .sendMessage, accountID: "demo", targetID: "self", payloadFingerprint: "opaque-digest")
        let approval = ActionApproval.exact(for: intent)
        let store = try ActionJournalStore(fileURL: url)
        let attempt = try await store.prepare(intent, approval: approval)
        _ = try await store.beginDispatch(attempt.id, approval: approval)
        // The external adapter may now run. Verify the dispatching mark reached disk first.
        let onDisk = try AtomicJSONFile<ActionJournal>(url: url).load()
        #expect(onDisk.attempts[0].state == .dispatching)
        let recovered = try ActionJournalStore(fileURL: url)
        let recoveredSnapshot = await recovered.snapshot()
        #expect(recoveredSnapshot.attempts[0].state == .outcomeUnknown)
        do {
            _ = try await recovered.beginDispatch(attempt.id, approval: approval)
            Issue.record("Unknown outcome was permitted to redispatch")
        } catch { #expect(error as? ActionJournalError == .invalidTransition) }
        do {
            _ = try await recovered.prepare(intent, approval: approval)
            Issue.record("Duplicate intent was permitted")
        } catch { #expect(error as? ActionJournalError == .duplicateIntent) }
        try await recovered.recordVerified(attempt.id, evidenceReference: "sent-folder-item-1")
        let verifiedSnapshot = await recovered.snapshot()
        #expect(verifiedSnapshot.attempts[0].state == .verified)
    }

    @Test
    func testApprovalRecheckedAtDispatch() async throws {
        let url = location("journal.json")
        defer { try? FileManager.default.removeItem(at: url.deletingLastPathComponent()) }
        let now = Date(timeIntervalSince1970: 1_800_000_000)
        let intent = ActionIntent(kind: .deleteMessage, accountID: "demo", targetID: "fixture", payloadFingerprint: "digest", createdAt: now)
        let approval = ActionApproval.exact(for: intent, at: now, expiresAt: now.addingTimeInterval(1))
        let store = try ActionJournalStore(fileURL: url, recoveringAt: now)
        let attempt = try await store.prepare(intent, approval: approval, at: now)
        do {
            _ = try await store.beginDispatch(attempt.id, approval: approval, at: now.addingTimeInterval(2))
            Issue.record("Expired approval was permitted")
        } catch { #expect(error as? ActionJournalError == .approvalMismatch) }
        let unchangedSnapshot = await store.snapshot()
        #expect(unchangedSnapshot.attempts[0].state == .readyToDispatch)
    }

    @Test
    func testFailedPersistenceDoesNotAuthorize() async throws {
        let url = location("blocker")
        defer { try? FileManager.default.removeItem(at: url.deletingLastPathComponent()) }
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        try Data("not a directory".utf8).write(to: url)
        let store = try ActionJournalStore(fileURL: url.appendingPathComponent("journal.json"))
        let intent = ActionIntent(kind: .sendMessage, accountID: "demo", targetID: "self", payloadFingerprint: "digest")
        let approval = ActionApproval.exact(for: intent)
        do {
            _ = try await store.prepare(intent, approval: approval)
            Issue.record("Write beneath a regular file unexpectedly succeeded")
        } catch { let unchanged = await store.snapshot(); #expect(unchanged.attempts.isEmpty) }
    }
}
