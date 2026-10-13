import Foundation
import Synchronization
import Testing
@testable import MorningCore

// Fixtures only: synthetic payloads and journal files in a temporary folder. Nothing reaches a
// real channel. These tests put the executor and its journal under conditions the main suite
// ("Action execution") does not: unusual payload bytes, an intent ID used again with other
// content after a relaunch, a damaged journal file, a wall clock that is not a number or goes
// backwards, conversation names stored in another Unicode form, and a journal that cannot be
// written at the first step.
private actor FixedOutcomeAdapter: ActionAdapter {
    private(set) var received: [PreparedAction] = []
    let outcome: ActionDispatchOutcome
    init(_ outcome: ActionDispatchOutcome = .accepted(receiptReference: "synthetic-provider-id")) {
        self.outcome = outcome
    }
    func dispatch(_ action: PreparedAction) async throws -> ActionDispatchOutcome {
        received.append(action)
        return outcome
    }
    func reconcile(_ attempt: ActionAttempt) async throws -> ActionReconciliation { .stillUnknown }
}

private final class ScriptedDates: Sendable {
    private struct State: Sendable { var dates: [Date]; var index = 0 }
    private let state: Mutex<State>
    init(_ dates: [Date]) { state = Mutex(State(dates: dates)) }
    func read() -> Date {
        state.withLock { value in
            let date = value.dates[min(value.index, value.dates.count - 1)]
            value.index += 1
            return date
        }
    }
}

private struct JournalFixture {
    let directory = FileManager.default.temporaryDirectory
        .appendingPathComponent("morning-action-hostile-tests-\(UUID().uuidString)")
    var url: URL { directory.appendingPathComponent("journal.json") }
    func cleanup() { try? FileManager.default.removeItem(at: directory) }
}

@Suite("Action execution under hostile conditions")
struct ActionExecutionHostileConditionsTests {
    private let date = Date(timeIntervalSince1970: 1_800_000_000)

    private func draft(id: UUID = UUID(), kind: ExternalActionKind = .sendMessage,
                       account: String = "synthetic-account", target: String = "synthetic-thread",
                       fields: [String: String] = ["body": "Synthetic fixture"]) -> ActionDraft {
        ActionDraft(id: id, kind: kind, accountID: account, targetID: target,
                    payload: ActionPayload(fields: fields), createdAt: date)
    }

    private func refused(_ operation: () async throws -> ActionAttempt) async -> ActionExecutionError? {
        do { _ = try await operation(); Issue.record("Expected a refusal but the action went through"); return nil }
        catch { return error as? ActionExecutionError }
    }

    @Test
    func largePayloadControlCharactersAndEmptyFieldsReachAdapterAsExactlyReviewedBytes() async throws {
        let fixture = JournalFixture(); defer { fixture.cleanup() }
        let body = "SYNTHETIC PRIVATE MESSAGE\r\r\n" + String(repeating: "Cafe\u{0301} 👩🏽‍💻 \u{202E}x\u{202C}\0\u{200B}\t", count: 4_096)
        let reviewed = draft(fields: ["body": body, "empty": "", "cafe\u{0301}": "ﬁ²", "": "value"])
        let adapter = FixedOutcomeAdapter(.verified(evidenceReference: body))
        let journal = try ActionJournalStore(fileURL: fixture.url)
        let executor = try ActionExecutor(journal: journal, adapter: adapter)
        let approval = await executor.approve(reviewed)
        var editedFields = reviewed.payload.fields
        editedFields["body"]! += "\u{200B}"
        let edited = draft(id: reviewed.id, fields: editedFields)
        #expect(await refused { try await executor.dispatch(edited, approvalID: approval.id) }
                == .fingerprintMismatch(approved: reviewed.fingerprint, current: edited.fingerprint))
        let attempt = try await executor.dispatch(reviewed, approvalID: approval.id)
        let delivered = try #require(await adapter.received.first)
        #expect(await adapter.received.count == 1)
        #expect(delivered.payload.fields.count == 4)
        for (name, value) in reviewed.payload.fields {
            #expect(Array(delivered.payload.fields[name]!.utf8) == Array(value.utf8))
        }
        #expect(delivered.payload.fields["empty"] == "")
        #expect(delivered.payload.fields["absent"] == nil)
        #expect(delivered.payload.fields["body"]!.hasPrefix("SYNTHETIC PRIVATE MESSAGE\n\n"))
        #expect(Array(delivered.payload.fields["café"]!.utf8) == Array("ﬁ²".utf8))
        #expect(attempt.intent.payloadFingerprint == reviewed.fingerprint)
        #expect(attempt.state == .verified)
        #expect(attempt.receiptReference?.hasPrefix("#sha256:") == true)
        let disk = try String(contentsOf: fixture.url, encoding: .utf8)
        #expect(!disk.contains("SYNTHETIC PRIVATE MESSAGE"))
        #expect(!disk.contains("Café"))
        await executor.release()
    }

    @Test
    func reusingIntentIDWithDifferentContentAndConversationStaysSpentAfterRelaunch() async throws {
        for state in [ActionAttemptState.readyToDispatch, .cancelled, .failedKnown, .accepted, .verified] {
            let fixture = JournalFixture(); defer { fixture.cleanup() }
            let original = draft()
            // Seed the exact durable boundary of a crash or a completed attempt.
            let store = try ActionJournalStore(fileURL: fixture.url)
            let approval = ActionApproval.exact(for: original.intent, at: date)
            let attempt = try await store.prepare(original.intent, approval: approval, at: date)
            switch state {
            case .readyToDispatch: break
            case .cancelled: try await store.cancel(attempt.id, at: date)
            default:
                _ = try await store.beginDispatch(attempt.id, approval: approval, at: date)
                switch state {
                case .failedKnown: try await store.recordKnownFailure(attempt.id, at: date)
                case .accepted: try await store.recordAccepted(attempt.id, at: date)
                case .verified: try await store.recordVerified(attempt.id, evidenceReference: "synthetic-evidence", at: date)
                default: break
                }
            }
            let before = try Data(contentsOf: fixture.url)
            let reopened = try ActionJournalStore(fileURL: fixture.url, recoveringAt: date)
            let adapter = FixedOutcomeAdapter()
            let executor = try ActionExecutor(journal: reopened, adapter: adapter)
            let recycled = draft(id: original.id, kind: .deleteMessage, account: "other-account",
                                 target: "other-thread", fields: ["body": "Different content"])
            let freshApproval = await executor.approve(recycled)
            #expect(await refused { try await executor.dispatch(recycled, approvalID: freshApproval.id) }
                    == .duplicateIntent(intentID: original.id))
            #expect(await adapter.received.isEmpty)
            #expect(try Data(contentsOf: fixture.url) == before)
            await executor.release()
        }
    }

    @Test
    func malformedJournalCannotSilentlyResetSpentIntentsOnRelaunch() async throws {
        let fixture = JournalFixture(); defer { fixture.cleanup() }
        let adapter = FixedOutcomeAdapter()
        let original = draft()
        let executor = try ActionExecutor(journal: ActionJournalStore(fileURL: fixture.url), adapter: adapter)
        _ = try await executor.dispatch(original, approvalID: await executor.approve(original).id)
        await executor.release()
        let valid = try Data(contentsOf: fixture.url)
        let root = try #require(JSONSerialization.jsonObject(with: valid) as? [String: Any])
        var malformed = [Data(valid.prefix(valid.count / 2))]
        for field in ["state", "receiptReference", "intent"] {
            var changed = root
            var value = try #require(changed["value"] as? [String: Any])
            var attempts = try #require(value["attempts"] as? [[String: Any]])
            attempts[0][field] = field == "state" ? "not-a-real-state" : ["body": "synthetic corrupt field"]
            value["attempts"] = attempts
            changed["value"] = value
            malformed.append(try JSONSerialization.data(withJSONObject: changed))
        }
        for bytes in malformed {
            try bytes.write(to: fixture.url)
            do {
                _ = try ActionJournalStore(fileURL: fixture.url)
                Issue.record("A malformed journal reopened as usable state")
            } catch { #expect(error is DecodingError) }
            #expect(try Data(contentsOf: fixture.url) == bytes)
        }
        try valid.write(to: fixture.url)
        let reopened = try ActionExecutor(journal: ActionJournalStore(fileURL: fixture.url), adapter: adapter)
        #expect(await refused { try await reopened.dispatch(original, approvalID: await reopened.approve(original).id) }
                == .duplicateIntent(intentID: original.id))
        #expect(await adapter.received.count == 1)
        await reopened.release()
    }

    @Test
    func unsoundWallClockAtEachAuthorizationBoundaryCannotReachAdapter() async throws {
        for badTime in [Double.nan, .infinity, -.infinity, date.timeIntervalSinceReferenceDate - 1] {
            for boundary in 0...2 {
                let fixture = JournalFixture(); defer { fixture.cleanup() }
                let dates = ScriptedDates([date] + Array(repeating: date, count: boundary)
                                            + [Date(timeIntervalSinceReferenceDate: badTime)])
                let adapter = FixedOutcomeAdapter()
                let journal = try ActionJournalStore(fileURL: fixture.url)
                let executor = try ActionExecutor(journal: journal, adapter: adapter, now: { dates.read() })
                let original = draft()
                let approval = await executor.approve(original, expiresAt: date.addingTimeInterval(60))
                do {
                    _ = try await executor.dispatch(original, approvalID: approval.id)
                    Issue.record("Unsound authorization clock allowed dispatch at boundary \(boundary)")
                } catch { /* A refusal, including inability to persist a nonfinite date, is safe. */ }
                #expect(await adapter.received.isEmpty, "Clock \(badTime), authorization boundary \(boundary)")
                await executor.release()
                // Failure cleanup must not replace a valid file with un-decodable nonfinite JSON.
                let reopened = try ActionJournalStore(fileURL: fixture.url, recoveringAt: date)
                #expect(await reopened.snapshot().attempts.allSatisfy { $0.updatedAt.timeIntervalSinceReferenceDate.isFinite })
            }
        }
    }

    @Test
    func legacyDecomposedConversationBlocksEveryActionKindAfterRelaunch() async throws {
        let fixture = JournalFixture(); defer { fixture.cleanup() }
        let legacy = ActionIntent(kind: .sendMessage, accountID: "cafe\u{0301}", targetID: "re\u{0301}union",
                                  payloadFingerprint: "synthetic-legacy-digest", createdAt: date)
        let store = try ActionJournalStore(fileURL: fixture.url)
        let approval = ActionApproval.exact(for: legacy, at: date)
        let interrupted = try await store.prepare(legacy, approval: approval, at: date)
        _ = try await store.beginDispatch(interrupted.id, approval: approval, at: date)
        let reopened = try ActionJournalStore(fileURL: fixture.url, recoveringAt: date)
        let adapter = FixedOutcomeAdapter()
        let executor = try ActionExecutor(journal: reopened, adapter: adapter)
        for kind in ExternalActionKind.allCases {
            let retry = draft(kind: kind, account: "café", target: "réunion")
            #expect(await refused { try await executor.dispatch(retry, approvalID: await executor.approve(retry).id) }
                    == .unreconciledOutcome(attemptID: interrupted.id))
        }
        #expect(await adapter.received.isEmpty)
        #expect(await reopened.snapshot().attempts.count == 1)
        await executor.release()
    }

    @Test
    func failedPrepareCanRetrySameIntentOnceAndRelaunchStillPreventsReplay() async throws {
        let fixture = JournalFixture(); defer { fixture.cleanup() }
        let adapter = FixedOutcomeAdapter()
        let journal = try ActionJournalStore(fileURL: fixture.url)
        let executor = try ActionExecutor(journal: journal, adapter: adapter)
        let original = draft()
        let approval = await executor.approve(original)
        // A directory at the destination forces atomic replacement to fail before dispatch.
        try FileManager.default.createDirectory(at: fixture.url, withIntermediateDirectories: true)
        do {
            _ = try await executor.dispatch(original, approvalID: approval.id)
            Issue.record("Dispatch proceeded without a durable prepare record")
        } catch { #expect(await adapter.received.isEmpty) }
        #expect(await journal.snapshot().attempts.isEmpty)
        try FileManager.default.removeItem(at: fixture.url)
        #expect(try await executor.dispatch(original, approvalID: approval.id).state == .accepted)
        await executor.release()
        let reopened = try ActionExecutor(journal: ActionJournalStore(fileURL: fixture.url), adapter: adapter)
        #expect(await refused { try await reopened.dispatch(original, approvalID: await reopened.approve(original).id) }
                == .duplicateIntent(intentID: original.id))
        #expect(await adapter.received.map(\.intent.id) == [original.id])
        await reopened.release()
    }
}
