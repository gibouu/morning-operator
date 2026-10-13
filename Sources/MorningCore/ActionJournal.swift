import CryptoKit
import Foundation
import Synchronization

public enum ExternalActionKind: String, Codable, Sendable, CaseIterable {
    case navigate, readAloud, sendMessage, deleteMessage, updateCalendar
}

/// Store an opaque fingerprint of canonical payload bytes, never the message body or a token.
/// The integration creates the fingerprint and reuses this ID for retries of the same user intent.
public struct ActionIntent: Codable, Sendable, Identifiable, Equatable {
    public let id: UUID
    public let kind: ExternalActionKind
    public let accountID: String
    public let targetID: String
    public let payloadFingerprint: String
    public let createdAt: Date
    public init(id: UUID = UUID(), kind: ExternalActionKind, accountID: String, targetID: String,
                payloadFingerprint: String, createdAt: Date = Date()) {
        self.id = id; self.kind = kind; self.accountID = accountID; self.targetID = targetID
        self.payloadFingerprint = payloadFingerprint; self.createdAt = createdAt
    }
}

public struct ActionApproval: Codable, Sendable, Identifiable, Equatable {
    public let id: UUID
    public let intentID: UUID?
    public let kind: ExternalActionKind
    public let accountID: String
    public let targetID: String
    public let payloadFingerprint: String?
    public let grantedAt: Date
    public let expiresAt: Date?
    public var revokedAt: Date?

    private init(intentID: UUID?, kind: ExternalActionKind, accountID: String, targetID: String,
                 payloadFingerprint: String?, grantedAt: Date, expiresAt: Date?) {
        id = UUID(); self.intentID = intentID; self.kind = kind; self.accountID = accountID
        self.targetID = targetID; self.payloadFingerprint = payloadFingerprint
        self.grantedAt = grantedAt; self.expiresAt = expiresAt; revokedAt = nil
    }
    public static func exact(for intent: ActionIntent, at date: Date = Date(), expiresAt: Date? = nil) -> ActionApproval {
        ActionApproval(intentID: intent.id, kind: intent.kind, accountID: intent.accountID, targetID: intent.targetID,
                       payloadFingerprint: intent.payloadFingerprint, grantedAt: date, expiresAt: expiresAt)
    }
    /// Explicit standing authority remains confined to one account, target and action class.
    public static func standing(kind: ExternalActionKind, accountID: String, targetID: String,
                                at date: Date = Date(), expiresAt: Date? = nil) -> ActionApproval {
        ActionApproval(intentID: nil, kind: kind, accountID: accountID, targetID: targetID,
                       payloadFingerprint: nil, grantedAt: date, expiresAt: expiresAt)
    }
    public func allows(_ intent: ActionIntent, at date: Date = Date()) -> Bool {
        revokedAt == nil && date >= grantedAt && (expiresAt.map { date < $0 } ?? true)
        && kind == intent.kind && accountID == intent.accountID && targetID == intent.targetID
        && (intentID.map { $0 == intent.id } ?? true)
        && (payloadFingerprint.map { $0 == intent.payloadFingerprint } ?? true)
        && !intent.accountID.isEmpty && !intent.targetID.isEmpty && !intent.payloadFingerprint.isEmpty
    }
}

public enum ActionAttemptState: String, Codable, Sendable {
    case readyToDispatch, dispatching, accepted, verified, failedKnown, outcomeUnknown, cancelled
}
public struct ActionAttempt: Codable, Sendable, Identifiable, Equatable {
    public let id: UUID
    public let intent: ActionIntent
    public let approvalID: UUID
    public fileprivate(set) var state: ActionAttemptState
    public let createdAt: Date
    public fileprivate(set) var updatedAt: Date
    /// Only a provider receipt ID or an opaque evidence reference, not message content.
    /// Whatever is written here from now on has passed `ActionReference.constrained`.
    public fileprivate(set) var receiptReference: String?
}

/// The one rule for a receipt or evidence reference before it is written to the journal
/// (decided 13 October). An adapter hands back a string; nothing guarantees it is an identifier
/// and not a copy of the message, so the journal stores it only in one of these forms:
///
/// 1. **Blank** (empty, or whitespace only): nothing is stored.
/// 2. **Plain**: 1 to 128 characters, each one of the ASCII letters `A-Z a-z`, the digits `0-9`
///    or `- _ . : / + =`. Stored exactly as given. This covers UUIDs, identifiers made of
///    UUIDs joined by `:`, hexadecimal and base64 provider IDs.
/// 3. **Plain but longer than 128**: its first 48 characters, then `#sha256:`, then the 64
///    lowercase hexadecimal digits of the SHA-256 of the whole string (120 characters).
/// 4. **Anything else** (a space, a line break, punctuation outside the list, any non-ASCII
///    character): `#sha256:` and the 64 digits, with none of the original text (72 characters).
///
/// The hash is taken over the UTF-8 bytes of the string exactly as given, with no normalization,
/// so the same string always gives the same stored form and an adapter can recognise a reference
/// it is able to produce again. `#` is not a plain character: a stored form contains it if and
/// only if the rule changed the string. Nothing is ever refused, because by the time a reference
/// exists the action has been sent and the attempt must still be recorded.
///
/// What this does and does not buy: text with spaces or line breaks (a message body, a subject)
/// never reaches the journal file, and nothing longer than 128 characters does. A single short
/// token with no space cannot be told from an identifier and is kept; and the hash of a short,
/// guessable text can be found again by trying candidates, so it is not a way to keep a secret.
/// An adapter that needs its reference back for `reconcile` must return a plain one, or key on
/// the intent ID.
public enum ActionReference {
    public static let maximumLength = 128
    static let keptPrefixLength = 48
    static let hashMarker = "#sha256:"

    public static func constrained(_ reference: String?) -> String? {
        guard let reference, !reference.unicodeScalars.allSatisfy({ $0.properties.isWhitespace }) else { return nil }
        let bytes = Array(reference.utf8)
        let isPlain = bytes.allSatisfy(isPlain)
        if isPlain, bytes.count <= maximumLength { return reference }
        let digest = SHA256.hash(data: Data(bytes)).map { String(format: "%02x", $0) }.joined()
        // Plain bytes are ASCII, so a byte prefix is a character prefix.
        let prefix = isPlain ? String(decoding: bytes.prefix(keptPrefixLength), as: UTF8.self) : ""
        return prefix + hashMarker + digest
    }

    private static func isPlain(_ byte: UInt8) -> Bool {
        switch byte {
        case UInt8(ascii: "A")...UInt8(ascii: "Z"), UInt8(ascii: "a")...UInt8(ascii: "z"), UInt8(ascii: "0")...UInt8(ascii: "9"),
             UInt8(ascii: "-"), UInt8(ascii: "_"), UInt8(ascii: "."), UInt8(ascii: ":"), UInt8(ascii: "/"),
             UInt8(ascii: "+"), UInt8(ascii: "="): true
        default: false
        }
    }
}
public enum ActionJournalError: Error, LocalizedError, Equatable, Sendable {
    case approvalMismatch, duplicateIntent, attemptNotFound, invalidTransition
    public var errorDescription: String? {
        switch self {
        case .approvalMismatch: String(localized: "This action is outside its current approval scope.", bundle: .module)
        case .duplicateIntent: String(localized: "This intent is already journaled. Reconcile its outcome before taking another action.", bundle: .module)
        case .attemptNotFound: String(localized: "The action attempt could not be found.", bundle: .module)
        case .invalidTransition: String(localized: "This action cannot be dispatched or updated from its current state.", bundle: .module)
        }
    }
}
public struct ActionJournal: Codable, Sendable, Equatable {
    public fileprivate(set) var attempts: [ActionAttempt]
    public init(attempts: [ActionAttempt] = []) { self.attempts = attempts }
}

/// What this process, and only this process, still knows about an attempt that the journal shows
/// as unsettled: an adapter call that outlasted the executor's deadline, or an answer that came in
/// time and could not be saved. Never written to the journal file.
protocol UnsettledKnowledge: Sendable {
    /// True while a dispatch call is still running, and for good once the channel has said that
    /// it took the action or that the action was delivered.
    var mayHaveSent: Bool { get }
    /// True once the adapter call behind this has returned.
    var isOver: Bool { get }
    /// Returns once the adapter call behind this has returned.
    func returned() async
}

/// Single authoritative writer. No external effect is allowed before beginDispatch succeeds.
/// Reopening after process interruption marks dispatching attempts unknown, never ready to retry.
/// One instance/process owns a journal file; this is not a multi-process locking service.
///
/// Outside this module a store can be opened and read, nothing more. Its writes are internal and
/// belong to the one `ActionExecutor` the store has admitted (decided 13 October: the rule lives
/// here, not in a process-wide registry). "Unknown blocks, reconcile first" only holds when every
/// write passes through one executor's ordering, so the store admits one executor at a time and
/// takes the next only after that one has called `ActionExecutor.release()`.
public actor ActionJournalStore {
    /// Proof of admission. Only the holder of the current seat can give it back.
    struct ExecutorSeat: Sendable, Equatable { fileprivate let id = UUID() }

    private let file: AtomicJSONFile<ActionJournal>
    private var journal: ActionJournal
    /// Not actor state: admission is decided synchronously, inside the executor's initializer.
    private let seat = Mutex<ExecutorSeat?>(nil)
    /// By attempt, in memory only. Kept here and not in the executor, so that releasing an
    /// executor while an overdue call is still out does not forget it.
    private var unsettled: [UUID: [any UnsettledKnowledge]] = [:]

    /// The seat, or `nil` while another executor holds it.
    nonisolated func admitExecutor() -> ExecutorSeat? {
        seat.withLock { current in
            guard current == nil else { return nil }
            let admitted = ExecutorSeat()
            current = admitted
            return admitted
        }
    }

    /// Frees the seat if `held` is the current one. A seat already given back frees nothing,
    /// so a released executor cannot unseat its successor.
    nonisolated func vacate(_ held: ExecutorSeat) {
        seat.withLock { current in if current == held { current = nil } }
    }

    public init(fileURL: URL, recoveringAt date: Date = Date()) throws {
        let localFile = AtomicJSONFile<ActionJournal>(url: fileURL)
        var loaded = FileManager.default.fileExists(atPath: fileURL.path) ? try localFile.load() : ActionJournal()
        var changed = false
        for index in loaded.attempts.indices where loaded.attempts[index].state == .dispatching {
            loaded.attempts[index].state = .outcomeUnknown
            loaded.attempts[index].updatedAt = date
            changed = true
        }
        if changed { try localFile.save(loaded) }
        file = localFile; journal = loaded
    }

    public func snapshot() -> ActionJournal { journal }

    func note(_ knowledge: any UnsettledKnowledge, for attemptID: UUID) { unsettled[attemptID, default: []].append(knowledge) }

    /// Whether, for all this process knows, the action of this attempt could still go through or
    /// has gone through. While this is true, a "not delivered" answer from the channel is not the
    /// last word.
    func actionMayHaveBeenSent(_ attemptID: UUID) -> Bool {
        // A call that is over and claims nothing has no more to say.
        unsettled[attemptID]?.removeAll { $0.isOver && !$0.mayHaveSent }
        return unsettled[attemptID]?.contains { $0.mayHaveSent } ?? false
    }

    /// For tests: returns once every overdue adapter call still remembered has returned.
    func overdueCallsReturned() async { for knowledge in unsettled.values.flatMap({ $0 }) { await knowledge.returned() } }

    @discardableResult
    func prepare(_ intent: ActionIntent, approval: ActionApproval, at date: Date = Date()) throws -> ActionAttempt {
        guard approval.allows(intent, at: date) else { throw ActionJournalError.approvalMismatch }
        guard !journal.attempts.contains(where: { $0.intent.id == intent.id }) else { throw ActionJournalError.duplicateIntent }
        let attempt = ActionAttempt(id: UUID(), intent: intent, approvalID: approval.id, state: .readyToDispatch,
                                    createdAt: date, updatedAt: date, receiptReference: nil)
        var candidate = journal; candidate.attempts.append(attempt)
        try commit(candidate)
        return attempt
    }

    /// Persist dispatching BEFORE returning permission to invoke the external adapter.
    /// Pass the current policy object so expiry/revocation is rechecked immediately before dispatch.
    @discardableResult
    func beginDispatch(_ attemptID: UUID, approval: ActionApproval, at date: Date = Date()) throws -> ActionIntent {
        let index = try index(of: attemptID)
        let attempt = journal.attempts[index]
        guard attempt.state == .readyToDispatch else { throw ActionJournalError.invalidTransition }
        guard attempt.approvalID == approval.id, approval.allows(attempt.intent, at: date)
        else { throw ActionJournalError.approvalMismatch }
        try transition(index: index, to: .dispatching, at: date)
        return attempt.intent
    }

    func recordAccepted(_ attemptID: UUID, receiptReference: String? = nil, at date: Date = Date()) throws {
        try update(attemptID, allowed: [.dispatching], to: .accepted, receipt: receiptReference, at: date)
    }
    func recordVerified(_ attemptID: UUID, evidenceReference: String, at date: Date = Date()) throws {
        try update(attemptID, allowed: [.dispatching, .accepted, .outcomeUnknown], to: .verified, receipt: evidenceReference, at: date)
    }
    /// Use only when evidence establishes no side effect, not for a timeout or lost response.
    func recordKnownFailure(_ attemptID: UUID, at date: Date = Date()) throws {
        try update(attemptID, allowed: [.readyToDispatch, .dispatching, .accepted, .outcomeUnknown], to: .failedKnown, at: date)
    }
    func recordUnknown(_ attemptID: UUID, at date: Date = Date()) throws {
        try update(attemptID, allowed: [.dispatching, .accepted], to: .outcomeUnknown, at: date)
    }
    func cancel(_ attemptID: UUID, at date: Date = Date()) throws {
        try update(attemptID, allowed: [.readyToDispatch], to: .cancelled, at: date)
    }

    private func index(of id: UUID) throws -> Int {
        guard let index = journal.attempts.firstIndex(where: { $0.id == id }) else { throw ActionJournalError.attemptNotFound }
        return index
    }
    private func update(_ id: UUID, allowed: Set<ActionAttemptState>, to state: ActionAttemptState,
                        receipt: String? = nil, at date: Date) throws {
        let index = try index(of: id)
        guard allowed.contains(journal.attempts[index].state) else { throw ActionJournalError.invalidTransition }
        try transition(index: index, to: state, receipt: receipt, at: date)
    }
    private func transition(index: Int, to state: ActionAttemptState, receipt: String? = nil, at date: Date) throws {
        var candidate = journal
        candidate.attempts[index].state = state
        candidate.attempts[index].updatedAt = date
        // Every reference passes the rule here, whoever the caller is.
        if let receipt = ActionReference.constrained(receipt) { candidate.attempts[index].receiptReference = receipt }
        try commit(candidate)
        // A settled attempt has nothing left to doubt.
        if state == .verified || state == .failedKnown { unsettled[candidate.attempts[index].id] = nil }
    }
    private func commit(_ candidate: ActionJournal) throws {
        try file.save(candidate)
        journal = candidate
    }
}
