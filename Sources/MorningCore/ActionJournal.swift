import Foundation

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
    public fileprivate(set) var receiptReference: String?
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

/// Single authoritative writer. No external effect is allowed before beginDispatch succeeds.
/// Reopening after process interruption marks dispatching attempts unknown, never ready to retry.
/// One instance/process owns a journal file; this is not a multi-process locking service.
public actor ActionJournalStore {
    private let file: AtomicJSONFile<ActionJournal>
    private var journal: ActionJournal

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

    @discardableResult
    public func prepare(_ intent: ActionIntent, approval: ActionApproval, at date: Date = Date()) throws -> ActionAttempt {
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
    public func beginDispatch(_ attemptID: UUID, approval: ActionApproval, at date: Date = Date()) throws -> ActionIntent {
        let index = try index(of: attemptID)
        let attempt = journal.attempts[index]
        guard attempt.state == .readyToDispatch else { throw ActionJournalError.invalidTransition }
        guard attempt.approvalID == approval.id, approval.allows(attempt.intent, at: date)
        else { throw ActionJournalError.approvalMismatch }
        try transition(index: index, to: .dispatching, at: date)
        return attempt.intent
    }

    public func recordAccepted(_ attemptID: UUID, receiptReference: String? = nil, at date: Date = Date()) throws {
        try update(attemptID, allowed: [.dispatching], to: .accepted, receipt: receiptReference, at: date)
    }
    public func recordVerified(_ attemptID: UUID, evidenceReference: String, at date: Date = Date()) throws {
        try update(attemptID, allowed: [.dispatching, .accepted, .outcomeUnknown], to: .verified, receipt: evidenceReference, at: date)
    }
    /// Use only when evidence establishes no side effect, not for a timeout or lost response.
    public func recordKnownFailure(_ attemptID: UUID, at date: Date = Date()) throws {
        try update(attemptID, allowed: [.readyToDispatch, .dispatching, .accepted, .outcomeUnknown], to: .failedKnown, at: date)
    }
    public func recordUnknown(_ attemptID: UUID, at date: Date = Date()) throws {
        try update(attemptID, allowed: [.dispatching, .accepted], to: .outcomeUnknown, at: date)
    }
    public func cancel(_ attemptID: UUID, at date: Date = Date()) throws {
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
        if let receipt { candidate.attempts[index].receiptReference = receipt }
        try commit(candidate)
    }
    private func commit(_ candidate: ActionJournal) throws {
        try file.save(candidate)
        journal = candidate
    }
}
