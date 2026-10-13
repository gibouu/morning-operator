import CryptoKit
import Foundation
import Synchronization

/// The reviewable content of one action, as named text fields (a message has "body").
///
/// Normalization happens once, here, so only one form of a payload exists: what the person
/// reviews, what is fingerprinted and what the adapter receives are the same bytes.
/// - Field names and values use Unicode NFC. Canonically equivalent text is indistinguishable
///   on screen and Swift's own `==` already treats it as equal, so it must not break an approval.
///   NFKC is deliberately not used: it folds visibly different text ("ﬁ"/"fi", "²"/"2").
/// - In values, CRLF and a lone CR become LF: an invisible, platform-dependent difference.
/// - Every other character is kept exactly: leading, trailing and repeated whitespace, case,
///   zero-width and bidirectional controls are content. Changing one needs a new approval.
/// - An empty field is distinct from an absent field.
///
/// Not Codable, and its descriptions and mirror are redacted, so a body cannot reach a journal
/// file, a log line or `dump` by accident. Read `fields` only to show or send it.
public struct ActionPayload: Sendable, Equatable, CustomStringConvertible, CustomDebugStringConvertible, CustomReflectable {
    public let fields: [String: String]

    public init(fields: [String: String]) {
        self.fields = fields.reduce(into: [:]) { result, field in
            result[field.key.precomposedStringWithCanonicalMapping] = Self.canonicalValue(field.value)
        }
    }

    static func canonicalValue(_ value: String) -> String {
        var scalars = String.UnicodeScalarView()
        var previousWasCarriageReturn = false
        for scalar in value.unicodeScalars {
            if scalar == "\r" { scalars.append("\n"); previousWasCarriageReturn = true; continue }
            if scalar == "\n", previousWasCarriageReturn { previousWasCarriageReturn = false; continue }
            previousWasCarriageReturn = false
            scalars.append(scalar)
        }
        return String(scalars).precomposedStringWithCanonicalMapping
    }

    public var description: String {
        "ActionPayload(\(fields.count) field(s), \(fields.values.reduce(0) { $0 + $1.utf8.count }) byte(s), content withheld)"
    }
    public var debugDescription: String { description }
    public var customMirror: Mirror { Mirror(self, children: EmptyCollection<Mirror.Child>(), displayStyle: .struct) }
}

/// An action that has been drafted and can be reviewed, but is not approved and not journaled.
/// `id` becomes the intent ID: it identifies one user intent for good, so a later attempt at the
/// same content is a new draft with a new ID. Editing anything produces a different fingerprint.
public struct ActionDraft: Sendable, Identifiable, Equatable, CustomStringConvertible, CustomDebugStringConvertible {
    public let id: UUID
    public let kind: ExternalActionKind
    public let accountID: String
    public let targetID: String
    public let payload: ActionPayload
    public let createdAt: Date
    /// Lowercase hexadecimal SHA-256 over kind, account, target and payload. Layout, in order,
    /// each text as an 8-byte big-endian UTF-8 byte count followed by those bytes: the format
    /// label `morning-operator.action-fingerprint.v1`, `kind.rawValue`, `accountID`, `targetID`,
    /// then the field count as 8 big-endian bytes and each field name and value, fields ordered
    /// by the unsigned UTF-8 bytes of their names. Length prefixes stop two different splits of
    /// the same characters from hashing alike; the byte ordering makes field order irrelevant.
    public let fingerprint: String

    /// Account and target identifiers are opaque: NFC only (to agree with the journal's `==`),
    /// no trimming and no case folding. The integration resolves them to one canonical ID.
    public init(id: UUID = UUID(), kind: ExternalActionKind, accountID: String, targetID: String,
                payload: ActionPayload, createdAt: Date = Date()) {
        self.id = id; self.kind = kind
        self.accountID = accountID.precomposedStringWithCanonicalMapping
        self.targetID = targetID.precomposedStringWithCanonicalMapping
        self.payload = payload; self.createdAt = createdAt
        fingerprint = Self.fingerprint(kind: kind, accountID: self.accountID, targetID: self.targetID, payload: payload)
    }

    /// The journaled form: identifiers and the fingerprint, never the payload.
    /// Descriptions leave out the account and target: for a mail or message channel those are
    /// addresses or handles. (`dump` and the journal's own types still show them.)
    public var intent: ActionIntent {
        ActionIntent(id: id, kind: kind, accountID: accountID, targetID: targetID,
                     payloadFingerprint: fingerprint, createdAt: createdAt)
    }

    public var description: String {
        "ActionDraft(id: \(id), kind: \(kind.rawValue), fingerprint: \(fingerprint))"
    }
    public var debugDescription: String { description }

    private static func fingerprint(kind: ExternalActionKind, accountID: String, targetID: String,
                                    payload: ActionPayload) -> String {
        var bytes = Data()
        func append(count: Int) { withUnsafeBytes(of: UInt64(count).bigEndian) { bytes.append(contentsOf: $0) } }
        func append(_ utf8: [UInt8]) { append(count: utf8.count); bytes.append(contentsOf: utf8) }
        append(Array("morning-operator.action-fingerprint.v1".utf8))
        append(Array(kind.rawValue.utf8)); append(Array(accountID.utf8)); append(Array(targetID.utf8))
        let fields = payload.fields.map { (name: Array($0.key.utf8), value: Array($0.value.utf8)) }
            .sorted { $0.name.lexicographicallyPrecedes($1.name) }
        append(count: fields.count)
        for field in fields { append(field.name); append(field.value) }
        return SHA256.hash(data: bytes).map { String(format: "%02x", $0) }.joined()
    }
}

/// What an adapter is handed: an attempt whose `dispatching` mark is already on disk.
/// It has no public initializer: outside this module only `ActionExecutor` produces one,
/// so an integration cannot invoke its adapter ahead of the journal.
public struct PreparedAction: Sendable, Equatable, CustomStringConvertible, CustomDebugStringConvertible {
    public let attemptID: UUID
    /// `intent.id` is the idempotency key: pass it to the channel when the channel supports one.
    public let intent: ActionIntent
    public let payload: ActionPayload

    public var description: String {
        "PreparedAction(attempt: \(attemptID), intent: \(intent.id), kind: \(intent.kind.rawValue), fingerprint: \(intent.payloadFingerprint))"
    }
    public var debugDescription: String { description }
}

/// What the adapter can establish when it returns. Claim only what the evidence shows:
/// a tap or a provider's acceptance is `accepted`, not `verified`.
///
/// A reference is a provider or evidence ID, never content. The journal does not take that on
/// trust: every reference passes `ActionReference.constrained` before it is written.
public enum ActionDispatchOutcome: Sendable, Equatable {
    /// The channel took the action.
    case accepted(receiptReference: String?)
    /// The effect was observed in the channel (for example the item in the sent folder).
    case verified(evidenceReference: String)
    /// Evidence establishes that nothing was sent. Not for a timeout or a lost response.
    case failedKnown
    case outcomeUnknown
}

public enum ActionReconciliation: Sendable, Equatable {
    case delivered(evidenceReference: String)
    /// The channel was checked and the effect is not there.
    case notDelivered
    case stillUnknown
}

/// One external channel. An adapter performs exactly what it is handed and decides nothing.
/// Anything thrown from `dispatch` is recorded as an unknown outcome, because the effect may
/// already have happened. It must not call back into the executor that invoked it: that executor
/// is waiting for this call and would never answer.
///
/// **Deadline (decided 13 October).** The executor does not rely on the adapter's own timeout.
/// When its deadline passes, the call's task is cancelled, the attempt is recorded as
/// outcome-unknown and the executor moves on. Whatever the call returns after that is not
/// recorded; the executor only remembers it to weigh a later `reconcile` answer. So an adapter
/// may be called again (for another conversation, or to reconcile) while an overdue call of its
/// own is still running, and must tolerate that.
///
/// **First real channel (decided 13 October): Reminders and Calendar through EventKit.** Not built
/// yet. How the present shape fits "a single body plus a typed target":
/// - *Single body*: fits as it is. A payload with the one field `body` is a valid `ActionPayload`,
///   it is what the person reviews and what is fingerprinted.
/// - *Typed target*: does not fit yet. `targetID` is one opaque string and `ExternalActionKind`
///   has `updateCalendar` but nothing for a reminder. A reminder list and a calendar are different
///   kinds of target, and a due date or a start and end are typed values, not text. Building that
///   adapter needs (a) a reminder case in `ExternalActionKind`, which old journal files survive
///   but old builds cannot read, and (b) either a typed target in `ActionIntent` (a journal format
///   change, to be made on purpose) or a documented text encoding of "which store, which list"
///   inside `targetID`, with dates carried as further named fields. Neither is done here:
///   the choice belongs with the adapter.
public protocol ActionAdapter: Sendable {
    /// Perform the action once. `action.intent.id` is the idempotency key.
    func dispatch(_ action: PreparedAction) async throws -> ActionDispatchOutcome
    /// Ask the channel what happened to an earlier attempt. The payload is no longer available
    /// (it is never persisted). Look the attempt up by its intent ID or receipt reference; the
    /// fingerprint is a last resort, because a retry of the same content has the same one.
    /// Must not send anything.
    func reconcile(_ attempt: ActionAttempt) async throws -> ActionReconciliation
}

public enum ActionExecutionError: Error, LocalizedError, Equatable, Sendable {
    case approvalNotIssued(approvalID: UUID)
    case approvalRevoked(approvalID: UUID)
    case approvalExpired(approvalID: UUID)
    case fingerprintMismatch(approved: String, current: String)
    case outsideApprovedScope(approvalID: UUID)
    case duplicateIntent(intentID: UUID)
    case unreconciledOutcome(attemptID: UUID)
    case attemptNotFound(attemptID: UUID)
    case journalAlreadyHasExecutor
    /// This executor gave its journal store back with `release()` and does nothing any more.
    case executorReleased
    /// The adapter was invoked, but what it reported could not be written to the journal.
    case outcomeNotRecorded(attemptID: UUID)

    public var errorDescription: String? {
        switch self {
        case .approvalNotIssued(let id): "Approval \(id) was not granted in this session. Review and approve the action again."
        case .approvalRevoked(let id): "Approval \(id) was withdrawn."
        case .approvalExpired(let id): "Approval \(id) has expired."
        case .fingerprintMismatch(let approved, let current):
            "The action changed after it was approved (approved \(approved), now \(current)). Review and approve it again."
        case .outsideApprovedScope(let id): "This action is outside what approval \(id) covers."
        case .duplicateIntent(let id): "Action \(id) is already in the journal and will not be dispatched again. Draft it anew to retry."
        case .unreconciledOutcome(let id):
            "The outcome of attempt \(id) is still unknown. Check what happened before sending anything else there."
        case .attemptNotFound(let id): "Attempt \(id) could not be found."
        case .journalAlreadyHasExecutor: "This action journal already has an executor."
        case .executorReleased: "This executor was released and can no longer send or check anything."
        case .outcomeNotRecorded(let id):
            "Attempt \(id) was handed to the channel, but its result could not be saved. Check what happened before sending anything else there."
        }
    }
}

/// One adapter call raced against the executor's deadline. Whichever comes first, the answer or
/// the deadline, is the result; the other has no recipient. An answer that arrives after the
/// deadline is kept here, in memory, and goes nowhere by itself.
private final class AdapterCall<Answer: Sendable>: Sendable {
    enum Result: Sendable {
        /// The adapter returned in time; `nil` when it threw.
        case answered(Answer?)
        case overdue
    }
    enum Late: Sendable { case stillRunning, answered(Answer?) }

    private struct State: Sendable {
        var result: Result?
        var waiter: CheckedContinuation<Result, Never>?
        var lateAnswer: Answer??
        var work: Task<Void, Never>?
    }
    private let state = Mutex(State())

    /// After the deadline: whether the adapter has returned since, and with what. `nil` before it.
    var late: Late? {
        state.withLock { state in
            guard case .overdue = state.result else { return nil }
            return state.lateAnswer.map { .answered($0) } ?? .stillRunning
        }
    }

    /// Returns at the answer or at the deadline, never later. It does not wait for an adapter
    /// that ignores cancellation, which a task group would.
    ///
    /// The deadline is one instant on `clock`, fixed here before the adapter is called. An answer
    /// counts as in time only if the clock has not reached that instant when the answer comes
    /// back, so the verdict does not depend on which of two tasks happens to run first.
    func run(deadline: Duration, clock: any Clock<Duration>,
             _ operation: @escaping @Sendable () async throws -> Answer) async -> Result {
        // Opens the existential, so that the clock's own instants can be compared.
        func timed(on clock: some Clock<Duration>) async -> Result { await race(deadline: deadline, clock: clock, operation) }
        return await timed(on: clock)
    }

    private func race<C: Clock>(deadline: Duration, clock: C,
                                _ operation: @escaping @Sendable () async throws -> Answer) async -> Result where C.Duration == Duration {
        let limit = clock.now.advanced(by: deadline)
        let work = Task { [self] in
            let answer = try? await operation()
            if clock.now >= limit { settle(.overdue) }
            settle(.answered(answer))
        }
        state.withLock { $0.work = work }
        let timer = Task { [self] in
            do { try await clock.sleep(until: limit, tolerance: nil) } catch { return }
            settle(.overdue)
        }
        // Cancelling the request reaches the adapter, as it did when the call was made directly,
        // but the result is still the adapter's answer or the deadline: an adapter told to stop
        // may already have sent.
        let result = await withTaskCancellationHandler {
            await withCheckedContinuation { continuation in
                let ready: Result? = state.withLock { state in
                    if let result = state.result { return result }
                    state.waiter = continuation
                    return nil
                }
                if let ready { continuation.resume(returning: ready) }
            }
        } onCancel: { work.cancel() }
        timer.cancel()
        if case .overdue = result { work.cancel() }
        return result
    }

    /// Returns once the adapter call itself has returned, however late.
    func adapterReturned() async { await state.withLock { $0.work }?.value }

    private func settle(_ outcome: Result) {
        let waiter: CheckedContinuation<Result, Never>? = state.withLock { state in
            guard let first = state.result else {
                state.result = outcome
                defer { state.waiter = nil }
                return state.waiter
            }
            if case .overdue = first, case .answered(let answer) = outcome { state.lateAnswer = .some(answer) }
            return nil
        }
        waiter?.resume(returning: outcome)
    }
}

/// The channel answered in time that it took the action, and that answer could not be saved.
private struct UnrecordedAcceptance: OverdueDispatch {
    var mayHaveSent: Bool { true }
    func returned() async {}
}

extension AdapterCall: OverdueDispatch where Answer == ActionDispatchOutcome {
    var mayHaveSent: Bool {
        switch late {
        case nil: false
        case .stillRunning, .answered(.accepted), .answered(.verified): true
        // It came back failed, unknown or with an error: no claim of delivery to protect.
        case .answered: false
        }
    }
    func returned() async { await adapterReturned() }
}

/// Decides whether a drafted action may reach the adapter, and records what is known afterwards.
///
/// Approvals exist only because `approve` or `approveStanding` was called with typed values;
/// `dispatch` accepts an approval ID and uses this executor's own copy, so an `ActionApproval`
/// built or decoded anywhere else carries no authority.
///
/// `dispatch` and `reconcile` run strictly one at a time, including the adapter call: a second
/// request waits, then sees the journal the first one left behind. `revoke` never waits.
///
/// Decided by the owner on 13 October (the open questions of the first version):
/// 1. **Standing and exact approvals live in memory only.** After a relaunch nothing is approved
///    until the person approves again. They are not persisted anywhere.
/// 2. **An unknown outcome blocks the whole conversation**: nothing of any kind is dispatched to
///    the same account and target until that attempt has been reconciled. A send whose outcome is
///    in doubt also holds back a delete or a calendar change there.
/// 3. **A "not delivered" answer never overrides a provider acceptance.** An accepted attempt
///    stays accepted until delivery is verified; "not there" may only mean "not there yet".
/// 4. **The executor puts its own deadline on every adapter call.** A `dispatch` call that
///    outlasts it is recorded as outcome-unknown, never failed-known, and the turn is given up, so
///    `reconcile` works again (and `revoke` never stopped working). A `reconcile` call that
///    outlasts it settles nothing. The late answer is never written to the journal and never
///    causes a call to the adapter. It is taken into account in one place only, `reconcile`:
///    while the overdue call is still running, or once it has come back saying the channel took
///    the action, a "not delivered" answer is not believed, by rule 3. (The same holds for an
///    acceptance that came in time but could not be saved.) That memory is held by
///    the journal store, in memory: it survives a change of executor, and after a relaunch only
///    the journal's "unknown" remains (the overdue call itself is gone with the process).
/// 5. **Receipt and evidence references are constrained** by `ActionReference.constrained`
///    before they are written. Nothing is refused after a send.
/// 6. **One executor per journal store, enforced by the store.** A second is refused with
///    `journalAlreadyHasExecutor` until the first has called `release()`. Dropping an executor
///    without releasing it frees nothing: the store then stays closed to others for its lifetime.
/// 7. **The first real channel is Reminders and Calendar through EventKit**, not built here.
///    See `ActionAdapter`.
public actor ActionExecutor {
    /// The default deadline on one adapter call. Thirty seconds: a local EventKit save answers in
    /// well under a second and a network provider usually within ten, so a call that passes this
    /// is stuck, not slow, and cutting it earlier would turn slow successes into unknown outcomes
    /// that each cost a reconciliation. It is also about as long as a person will wait for a send
    /// before wanting the app to answer again, and while one call runs every other request waits.
    public static let defaultAdapterDeadline: Duration = .seconds(30)

    private let journal: ActionJournalStore
    private let adapter: any ActionAdapter
    private let adapterDeadline: Duration
    private let clock: any Clock<Duration>
    private let now: @Sendable () -> Date
    /// `nil` once released.
    private var seat: ActionJournalStore.ExecutorSeat?
    private var approvals: [UUID: ActionApproval] = [:]
    private var isBusy = false
    private var waiters: [CheckedContinuation<Void, Never>] = []

    /// Throws `journalAlreadyHasExecutor` while the store has another executor that has not been
    /// released. `adapterDeadline` bounds each adapter call, measured on `clock`; a deadline of
    /// zero or less makes every call overdue at once. `now` stamps the journal and judges expiry.
    public init(journal: ActionJournalStore, adapter: any ActionAdapter,
                adapterDeadline: Duration = ActionExecutor.defaultAdapterDeadline,
                clock: any Clock<Duration> = ContinuousClock(),
                now: @escaping @Sendable () -> Date = { Date() }) throws {
        guard let seat = journal.admitExecutor() else { throw ActionExecutionError.journalAlreadyHasExecutor }
        self.seat = seat
        self.journal = journal; self.adapter = adapter
        self.adapterDeadline = adapterDeadline; self.clock = clock; self.now = now
    }

    /// Gives the journal store back, so that it can admit another executor. From the moment this
    /// is called, every `dispatch` and `reconcile` that has not started is refused with
    /// `executorReleased`; the one in progress, if any, finishes first, and only then is the store
    /// free. When this returns the store admits a new executor. Calling it again changes nothing.
    public func release() async {
        let held = seat
        seat = nil
        // A second call also takes its turn, behind the first, so it too returns with the store free.
        await enter(); defer { leave() }
        if let held { journal.vacate(held) }
    }

    /// The person approved exactly this draft: this intent, account, target and payload.
    public func approve(_ draft: ActionDraft, expiresAt: Date? = nil) -> ActionApproval {
        remember(.exact(for: draft.intent, at: now(), expiresAt: expiresAt))
    }

    /// The person granted standing authority for one action class on one account and one target.
    public func approveStanding(kind: ExternalActionKind, accountID: String, targetID: String,
                                expiresAt: Date? = nil) -> ActionApproval {
        remember(.standing(kind: kind, accountID: accountID, targetID: targetID, at: now(), expiresAt: expiresAt))
    }

    /// Immediate. Every dispatch whose adapter has not been invoked yet is refused, including
    /// one already waiting its turn; an adapter call already under way cannot be recalled.
    public func revoke(_ approvalID: UUID) {
        if approvals[approvalID]?.revokedAt == nil { approvals[approvalID]?.revokedAt = now() }
    }

    /// Journals the draft, persists `dispatching`, then invokes the adapter once.
    /// Throws without invoking the adapter when the action is refused.
    @discardableResult
    public func dispatch(_ draft: ActionDraft, approvalID: UUID) async throws -> ActionAttempt {
        await enter(); defer { leave() }
        guard seat != nil else { throw ActionExecutionError.executorReleased }
        // A request cancelled while it waited its turn goes no further: nothing exists yet.
        try Task.checkCancellation()
        let intent = draft.intent
        var date = now()
        var approval = try authorize(intent, approvalID: approvalID, at: date)

        let attempts = await journal.snapshot().attempts
        // An unsettled attempt of any kind blocks its whole conversation (account and target).
        // One still marked dispatching here means its outcome could not be written down.
        if let unresolved = attempts.first(where: {
            [.dispatching, .outcomeUnknown].contains($0.state)
            && $0.intent.accountID == intent.accountID && $0.intent.targetID == intent.targetID
        }) { throw ActionExecutionError.unreconciledOutcome(attemptID: unresolved.id) }
        guard !attempts.contains(where: { $0.intent.id == intent.id })
        else { throw ActionExecutionError.duplicateIntent(intentID: intent.id) }

        let attempt = try await translating(intent, approvalID) { try await journal.prepare(intent, approval: approval, at: date) }
        do {
            // Expiry and revocation are judged again, with a fresh clock reading, at the last moment.
            date = now()
            approval = try authorize(intent, approvalID: approvalID, at: date)
            _ = try await translating(intent, approvalID) { try await journal.beginDispatch(attempt.id, approval: approval, at: date) }
        } catch {
            try? await journal.cancel(attempt.id, at: now())
            throw error
        }

        // `dispatching` is on disk, which took time: the request may have been cancelled, or the
        // approval may have expired or been withdrawn meanwhile. Check once more, with nothing else
        // awaited between this and the adapter call. The adapter has not been invoked, so stopping
        // here is a known non-event.
        do { _ = try authorize(intent, approvalID: approvalID, at: now()); try Task.checkCancellation() } catch {
            try? await journal.recordKnownFailure(attempt.id, at: now())
            throw error
        }

        // From here neither a thrown error nor silence can mean "nothing happened".
        let prepared = PreparedAction(attemptID: attempt.id, intent: intent, payload: draft.payload)
        let call = AdapterCall<ActionDispatchOutcome>()
        let outcome: ActionDispatchOutcome
        switch await call.run(deadline: adapterDeadline, clock: clock, { [adapter] in try await adapter.dispatch(prepared) }) {
        case .answered(let answer?): outcome = answer
        case .answered(nil): outcome = .outcomeUnknown
        case .overdue:
            // The call may still send, or already has. Its answer, if one comes, stays in `call`,
            // which the store keeps for `reconcile` to weigh.
            await journal.noteOverdueDispatch(call, for: attempt.id)
            outcome = .outcomeUnknown
        }
        do {
            switch outcome {
            case .accepted(let reference): try await journal.recordAccepted(attempt.id, receiptReference: reference, at: now())
            // "Verified" with nothing to point at is only an acceptance.
            case .verified(let reference) where Self.isBlank(reference): try await journal.recordAccepted(attempt.id, at: now())
            case .verified(let reference): try await journal.recordVerified(attempt.id, evidenceReference: reference, at: now())
            case .failedKnown: try await journal.recordKnownFailure(attempt.id, at: now())
            case .outcomeUnknown: try await journal.recordUnknown(attempt.id, at: now())
            }
        } catch {
            // The adapter ran but the journal still says `dispatching`: that keeps the conversation
            // blocked until `reconcile`, and becomes outcome-unknown at the next launch. If the
            // channel said it took the action, that is remembered (in memory) like a late
            // acceptance, so a "not there" cannot close the attempt as failed.
            switch outcome {
            case .accepted, .verified: await journal.noteOverdueDispatch(UnrecordedAcceptance(), for: attempt.id)
            case .failedKnown, .outcomeUnknown: break
            }
            throw ActionExecutionError.outcomeNotRecorded(attemptID: attempt.id)
        }
        return try await current(attempt.id)
    }

    /// Asks the channel what happened to an attempt whose outcome is not settled. Never sends.
    /// A settled attempt is returned as it is, without asking.
    @discardableResult
    public func reconcile(_ attemptID: UUID) async throws -> ActionAttempt {
        await enter(); defer { leave() }
        guard seat != nil else { throw ActionExecutionError.executorReleased }
        let attempt = try await current(attemptID)
        guard [.dispatching, .accepted, .outcomeUnknown].contains(attempt.state) else { return attempt }
        // Judged before the channel is asked as well as after: a "not there" observed while the
        // overdue call was still running says nothing about what that call did next.
        let doubtedBefore = await journal.overdueDispatchMayHaveSent(attemptID)
        let answer: ActionReconciliation
        let call = AdapterCall<ActionReconciliation>()
        if case .answered(let reply?) = await call.run(deadline: adapterDeadline, clock: clock,
                                                       { [adapter] in try await adapter.reconcile(attempt) }) {
            answer = reply
        } else {
            // It threw, or outlasted the deadline. Its late answer is dropped: a later reconciliation asks again.
            answer = .stillUnknown
        }
        // The channel said it took this action, in time or late. "Not there" may only mean "not
        // there yet", and failed-known would invite a second send, so an acceptance is never downgraded.
        let doubtedAfter = await journal.overdueDispatchMayHaveSent(attemptID)
        let notThereIsBelievable = attempt.state != .accepted && !doubtedBefore && !doubtedAfter
        switch answer {
        case .delivered(let reference) where !Self.isBlank(reference):
            try await journal.recordVerified(attemptID, evidenceReference: reference, at: now())
        case .notDelivered where notThereIsBelievable:
            try await journal.recordKnownFailure(attemptID, at: now())
        // No answer, an unsupported "delivered", or a "not there" that cannot be believed: nothing is settled.
        default: if attempt.state == .dispatching { try await journal.recordUnknown(attemptID, at: now()) }
        }
        return try await current(attemptID)
    }

    private static func isBlank(_ reference: String) -> Bool {
        reference.unicodeScalars.allSatisfy { $0.properties.isWhitespace }
    }

    private func remember(_ approval: ActionApproval) -> ActionApproval {
        approvals[approval.id] = approval
        return approval
    }

    private func authorize(_ intent: ActionIntent, approvalID: UUID, at date: Date) throws -> ActionApproval {
        guard let approval = approvals[approvalID] else { throw ActionExecutionError.approvalNotIssued(approvalID: approvalID) }
        guard approval.revokedAt == nil else { throw ActionExecutionError.approvalRevoked(approvalID: approvalID) }
        if let expiresAt = approval.expiresAt, date >= expiresAt { throw ActionExecutionError.approvalExpired(approvalID: approvalID) }
        if let approved = approval.payloadFingerprint, approved != intent.payloadFingerprint {
            throw ActionExecutionError.fingerprintMismatch(approved: approved, current: intent.payloadFingerprint)
        }
        guard approval.allows(intent, at: date) else { throw ActionExecutionError.outsideApprovedScope(approvalID: approvalID) }
        return approval
    }

    private func translating<Value: Sendable>(_ intent: ActionIntent, _ approvalID: UUID,
                                              _ operation: () async throws -> Value) async throws -> Value {
        do { return try await operation() }
        catch ActionJournalError.duplicateIntent { throw ActionExecutionError.duplicateIntent(intentID: intent.id) }
        catch ActionJournalError.approvalMismatch { throw ActionExecutionError.outsideApprovedScope(approvalID: approvalID) }
    }

    private func current(_ attemptID: UUID) async throws -> ActionAttempt {
        guard let attempt = await journal.snapshot().attempts.first(where: { $0.id == attemptID })
        else { throw ActionExecutionError.attemptNotFound(attemptID: attemptID) }
        return attempt
    }

    private func enter() async {
        if !isBusy { isBusy = true; return }
        await withCheckedContinuation { waiters.append($0) }
    }
    private func leave() {
        if waiters.isEmpty { isBusy = false } else { waiters.removeFirst().resume() }
    }
}
