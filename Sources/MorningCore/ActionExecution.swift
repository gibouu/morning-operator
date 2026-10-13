import CryptoKit
import Foundation

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
    public var intent: ActionIntent {
        ActionIntent(id: id, kind: kind, accountID: accountID, targetID: targetID,
                     payloadFingerprint: fingerprint, createdAt: createdAt)
    }

    public var description: String {
        "ActionDraft(id: \(id), kind: \(kind.rawValue), account: \(accountID), target: \(targetID), fingerprint: \(fingerprint))"
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
        "PreparedAction(attempt: \(attemptID), intent: \(intent.id), kind: \(intent.kind.rawValue), account: \(intent.accountID), target: \(intent.targetID), fingerprint: \(intent.payloadFingerprint))"
    }
    public var debugDescription: String { description }
}

/// What the adapter can establish when it returns. Claim only what the evidence shows:
/// a tap or a provider's acceptance is `accepted`, not `verified`.
public enum ActionDispatchOutcome: Sendable, Equatable {
    /// The channel took the action. The reference is a provider or evidence ID, never content.
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
/// It bounds its own waiting and throws on timeout; anything thrown from `dispatch` is recorded
/// as an unknown outcome, because the effect may already have happened. It must not call back
/// into the executor that invoked it: that executor is waiting for this call and would never answer.
public protocol ActionAdapter: Sendable {
    func dispatch(_ action: PreparedAction) async throws -> ActionDispatchOutcome
    /// Ask the channel what happened to an earlier attempt. The payload is no longer available
    /// (it is never persisted): use the intent ID, the receipt reference or the fingerprint.
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
        }
    }
}

/// Decides whether a drafted action may reach the adapter, and records what is known afterwards.
///
/// Approvals exist only because `approve` or `approveStanding` was called with typed values;
/// `dispatch` accepts an approval ID and uses this executor's own copy, so an `ActionApproval`
/// built or decoded anywhere else carries no authority. Grants live in memory: after a relaunch
/// nothing is approved until the person approves again.
///
/// `dispatch` and `reconcile` run strictly one at a time, including the adapter call: a second
/// request waits, then sees the journal the first one left behind. `revoke` never waits.
/// Use one executor per journal store.
public actor ActionExecutor {
    private let journal: ActionJournalStore
    private let adapter: any ActionAdapter
    private let now: @Sendable () -> Date
    private var approvals: [UUID: ActionApproval] = [:]
    private var isBusy = false
    private var waiters: [CheckedContinuation<Void, Never>] = []

    public init(journal: ActionJournalStore, adapter: any ActionAdapter, now: @escaping @Sendable () -> Date = { Date() }) {
        self.journal = journal; self.adapter = adapter; self.now = now
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
        await acquire(); defer { release() }
        let intent = draft.intent
        var date = now()
        var approval = try authorize(intent, approvalID: approvalID, at: date)

        let attempts = await journal.snapshot().attempts
        // An attempt still marked dispatching here means its outcome could not be written down.
        if let unresolved = attempts.first(where: { blocks($0, intent) }) {
            throw ActionExecutionError.unreconciledOutcome(attemptID: unresolved.id)
        }
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

        // `dispatching` is on disk, which took time and let other work in. Look once more, with no
        // suspension between the last check and the adapter call: another attempt at this conversation
        // must not be open (a second executor on the same store would show up here), and the approval
        // must still stand. The adapter has not been invoked, so a refusal here is a known non-event.
        do {
            if let other = await journal.snapshot().attempts.first(where: { $0.id != attempt.id && blocks($0, intent) }) {
                throw ActionExecutionError.unreconciledOutcome(attemptID: other.id)
            }
            _ = try authorize(intent, approvalID: approvalID, at: now())
        } catch {
            try? await journal.recordKnownFailure(attempt.id, at: now())
            throw error
        }

        // From here a thrown error can no longer mean "nothing happened".
        let outcome: ActionDispatchOutcome
        do { outcome = try await adapter.dispatch(PreparedAction(attemptID: attempt.id, intent: intent, payload: draft.payload)) }
        catch { outcome = .outcomeUnknown }
        switch outcome {
        case .accepted(let reference): try await journal.recordAccepted(attempt.id, receiptReference: reference, at: now())
        case .verified(let reference): try await journal.recordVerified(attempt.id, evidenceReference: reference, at: now())
        case .failedKnown: try await journal.recordKnownFailure(attempt.id, at: now())
        case .outcomeUnknown: try await journal.recordUnknown(attempt.id, at: now())
        }
        return try await current(attempt.id)
    }

    /// Asks the channel what happened to an attempt whose outcome is not settled. Never sends.
    /// A settled attempt is returned as it is, without asking.
    @discardableResult
    public func reconcile(_ attemptID: UUID) async throws -> ActionAttempt {
        await acquire(); defer { release() }
        let attempt = try await current(attemptID)
        guard [.dispatching, .accepted, .outcomeUnknown].contains(attempt.state) else { return attempt }
        let answer: ActionReconciliation
        do { answer = try await adapter.reconcile(attempt) } catch { answer = .stillUnknown }
        switch answer {
        case .delivered(let reference): try await journal.recordVerified(attemptID, evidenceReference: reference, at: now())
        case .notDelivered: try await journal.recordKnownFailure(attemptID, at: now())
        case .stillUnknown: if attempt.state == .dispatching { try await journal.recordUnknown(attemptID, at: now()) }
        }
        return try await current(attemptID)
    }

    /// An open or unknown attempt at the same action class, account and target.
    private func blocks(_ attempt: ActionAttempt, _ intent: ActionIntent) -> Bool {
        [.dispatching, .outcomeUnknown].contains(attempt.state) && attempt.intent.kind == intent.kind
        && attempt.intent.accountID == intent.accountID && attempt.intent.targetID == intent.targetID
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

    private func acquire() async {
        if !isBusy { isBusy = true; return }
        await withCheckedContinuation { waiters.append($0) }
    }
    private func release() {
        if waiters.isEmpty { isBusy = false } else { waiters.removeFirst().resume() }
    }
}
