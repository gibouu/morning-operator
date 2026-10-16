import Foundation
import Observation
import MorningCore

public enum MorningLiveActivityState: String, Sendable, Equatable {
    case inactive, active, stale, dismissed, unavailable, notAuthorized, ending, failed
}
public enum MorningLiveActivityError: Error, LocalizedError, Sendable, Equatable {
    case unavailable, requestFailed, updateFailed, endFailed, endUnconfirmed, privacyBlocked, invalidSnapshot
    public var errorDescription: String? {
        switch self {
        case .unavailable: AppLanguage.localized("Live Activities aren't available on this device.", bundle: .module)
        case .requestFailed: AppLanguage.localized("The Lock Screen activity couldn't start.", bundle: .module)
        case .updateFailed: AppLanguage.localized("The Lock Screen activity couldn't update. Open MORE for current progress.", bundle: .module)
        case .endFailed, .endUnconfirmed: AppLanguage.localized("The Lock Screen activity hasn't been confirmed closed. Try again.", bundle: .module)
        case .privacyBlocked: AppLanguage.localized("Live Activities are paused while local data is being removed.", bundle: .module)
        case .invalidSnapshot: AppLanguage.localized("This morning's progress isn't current enough to display.", bundle: .module)
        }
    }
}
public enum MorningLiveActivityRecordState: Sendable, Equatable {
    case pending, active, stale, ended, dismissed
    public var canUpdate: Bool { self == .active || self == .stale }
}
public struct MorningLiveActivityRecord: Sendable, Equatable {
    public let id: String
    public let sessionID: UUID
    public let state: MorningLiveActivityRecordState
    public init(id: String, sessionID: UUID, state: MorningLiveActivityRecordState) {
        self.id = id; self.sessionID = sessionID; self.state = state
    }
}

/// Providers must enumerate and mutate only their own namespace. `end` means
/// immediate removal, not the system's default four-hour post-end presentation.
@MainActor public protocol MorningLiveActivityProviding: AnyObject {
    var isSupported: Bool { get }
    var authorizationEnabled: Bool { get }
    var records: [MorningLiveActivityRecord] { get }
    func request(snapshot: MorningActivitySnapshot, staleDate: Date) async throws -> String
    func update(id: String, snapshot: MorningActivitySnapshot, staleDate: Date) async throws
    func end(id: String) async throws
}

/// Serial ownership of local ActivityKit work. New desired state invalidates a
/// pending request before awaiting it; a late request is ended before the next
/// operation runs. Caller-task cancellation never abandons cleanup ownership.
@MainActor @Observable public final class MorningLiveActivityCoordinator {
    public static let staleAfter: TimeInterval = 60
    public private(set) var status: MorningLiveActivityState = .inactive
    public private(set) var lastError: MorningLiveActivityError?
    public private(set) var currentSnapshot: MorningActivitySnapshot?
    public private(set) var activeActivityID: String?
    public var authorizationEnabled: Bool { provider.authorizationEnabled }
    @ObservationIgnored private let provider: any MorningLiveActivityProviding
    @ObservationIgnored private let canPublish: @MainActor () -> Bool
    @ObservationIgnored private let now: @MainActor () -> Date
    @ObservationIgnored private var tail: Task<Void, Error>?
    @ObservationIgnored private var revision = UUID()
    @ObservationIgnored private var reconciledLaunch = false
    private struct StartGrant: Hashable { let sessionID: UUID; let requestID: UUID }
    @ObservationIgnored private var requestedGrants: Set<StartGrant> = []
    @ObservationIgnored private var pendingStartGrant: StartGrant?
    @ObservationIgnored private var desiredSessionID: UUID?
    @ObservationIgnored private var privacyBlocked = false
    @ObservationIgnored private var privacyEndConfirmed = false

    public convenience init(namespace: MorningActivityNamespace = .production,
                            canPublish: @escaping @MainActor () -> Bool = {
                                (try? LocalDataControl(directory: LocalDataControl.defaultDirectory).status().forgetPending) == false
                            }) {
        self.init(provider: NativeMorningLiveActivityProvider(namespace: namespace), canPublish: canPublish)
    }
    public init(provider: any MorningLiveActivityProviding,
                canPublish: @escaping @MainActor () -> Bool = { true },
                now: @escaping @MainActor () -> Date = { Date() }) {
        self.provider = provider; self.canPublish = canPublish; self.now = now
    }

    /// Each explicit, saved start/resume/opt-in receives a new `startRequestID`.
    /// Repeated synchronization with that same grant cannot recreate a dismissed
    /// or denied activity. Nil retains the legacy one-attempt-per-session policy.
    public func synchronize(snapshot: MorningActivitySnapshot?, enabled: Bool,
                            isForeground: Bool, allowStart: Bool = false, startRequestID: UUID? = nil) async throws {
        revision = UUID()
        let token = revision
        desiredSessionID = enabled && !privacyBlocked && canPublish() ? snapshot?.sessionID : nil
        if !enabled || snapshot == nil || privacyBlocked || !canPublish() {
            pendingStartGrant = nil
        } else if allowStart && isForeground, let snapshot {
            pendingStartGrant = StartGrant(sessionID: snapshot.sessionID, requestID: startRequestID ?? snapshot.sessionID)
        } else if pendingStartGrant?.sessionID != snapshot?.sessionID { pendingStartGrant = nil }
        try await enqueue { [self] in
            try await reconcile(snapshot: snapshot, enabled: enabled, isForeground: isForeground, token: token)
        }
    }

    /// Blocks admission synchronously, then waits for every older native operation
    /// and immediate end. A failed end remains retryable and blocks reset.
    public func endAllForPrivacy() async throws {
        privacyBlocked = true; privacyEndConfirmed = false
        pendingStartGrant = nil; desiredSessionID = nil; revision = UUID(); status = .ending
        try await enqueue { [self] in
            try await endAllRecords()
            reconciledLaunch = true; privacyEndConfirmed = true
        }
    }
    public func resetAfterPrivacyCleanup() throws {
        guard privacyBlocked else { return }
        guard privacyEndConfirmed else { throw MorningLiveActivityError.privacyBlocked }
        privacyBlocked = false; privacyEndConfirmed = false
        requestedGrants.removeAll(); pendingStartGrant = nil; revision = UUID()
    }

    private func enqueue(_ operation: @escaping @MainActor () async throws -> Void) async throws {
        let previous = tail
        let task = Task { @MainActor [self] in
            if let previous { _ = await previous.result }
            do { try await operation(); lastError = nil }
            catch {
                let safe = (error as? MorningLiveActivityError) ?? .endFailed
                lastError = safe; status = .failed; throw safe
            }
        }
        tail = task
        try await task.value
    }
    private func reconcile(snapshot: MorningActivitySnapshot?, enabled: Bool,
                           isForeground: Bool, token: UUID) async throws {
        if !reconciledLaunch {
            try await endAllRecords()
            reconciledLaunch = true
        }
        guard token == revision else { return }
        guard enabled, let snapshot, !privacyBlocked, canPublish() else {
            try await endAllRecords(); return
        }
        guard provider.isSupported else {
            consumePendingGrant(for: snapshot.sessionID)
            status = .unavailable; return
        }
        guard provider.authorizationEnabled else {
            consumePendingGrant(for: snapshot.sessionID)
            try await endAllRecords(); status = .notAuthorized; return
        }
        let instant = now()
        guard instant.timeIntervalSinceReferenceDate.isFinite,
              snapshot.state.updatedAt <= instant,
              instant.timeIntervalSince(snapshot.state.updatedAt) < Self.staleAfter else {
            try await endAllRecords(); throw MorningLiveActivityError.invalidSnapshot
        }
        if let id = activeActivityID {
            let record = provider.records.first { $0.id == id }
            if record == nil || record?.state == .dismissed || record?.state == .ended {
                if record?.state == .ended { try await provider.end(id: id) }
                // Do not reinterpret dismissal as permission to start again.
                activeActivityID = nil; currentSnapshot = nil; status = .dismissed
            } else if record?.sessionID != snapshot.sessionID {
                try await endAllRecords()
            } else {
                // An explicit grant while the activity is healthy is satisfied by
                // that activity, never saved for recreation after later dismissal.
                consumePendingGrant(for: snapshot.sessionID)
                // End any unexpected duplicate before updating our one activity.
                for other in provider.records where other.id != id && other.state != .dismissed {
                    try await provider.end(id: other.id)
                }
                guard provider.records.allSatisfy({ $0.id == id || $0.state == .dismissed }) else {
                    throw MorningLiveActivityError.endUnconfirmed
                }
                guard mayRetain(snapshot) else { try await endAllRecords(); return }
                guard token == revision else { return }
                if currentSnapshot?.state.hasSameProgress(as: snapshot.state) != true ||
                    currentSnapshot.map({ $0.state.brandAppearance(at: $0.state.updatedAt) }) != snapshot.state.brandAppearance(at: instant) ||
                    (record?.state == .stale && isForeground) {
                    do { try await provider.update(id: id, snapshot: snapshot,
                        staleDate: snapshot.state.staleDate(staleAfter: Self.staleAfter)) }
                    catch { throw (error as? MorningLiveActivityError) ?? .updateFailed }
                    guard mayRetain(snapshot) else { try await endAllRecords(); return }
                    currentSnapshot = snapshot
                }
                status = provider.records.first(where: { $0.id == id })?.state == .stale ? .stale : .active
                return
            }
        }
        guard token == revision, !privacyBlocked, canPublish(), isForeground,
              let grant = pendingStartGrant, grant.sessionID == snapshot.sessionID,
              !requestedGrants.contains(grant) else { return }
        // Cleanup precedes every creation, including a different newly started session.
        try await endAllRecords()
        guard token == revision, !privacyBlocked, canPublish(), provider.authorizationEnabled else { return }
        requestedGrants.insert(grant); pendingStartGrant = nil
        let id: String
        do { id = try await provider.request(snapshot: snapshot,
            staleDate: snapshot.state.staleDate(staleAfter: Self.staleAfter)) }
        catch { throw (error as? MorningLiveActivityError) ?? .requestFailed }
        activeActivityID = id; currentSnapshot = snapshot
        guard mayRetain(snapshot) else { try await endAllRecords(); return }
        status = .active
    }
    private func consumePendingGrant(for sessionID: UUID) {
        guard let grant = pendingStartGrant, grant.sessionID == sessionID else { return }
        requestedGrants.insert(grant); pendingStartGrant = nil
    }
    private func mayRetain(_ snapshot: MorningActivitySnapshot) -> Bool {
        desiredSessionID == snapshot.sessionID && !privacyBlocked && canPublish()
    }
    private func endAllRecords() async throws {
        var failure: MorningLiveActivityError?
        for record in provider.records where record.state != .dismissed {
            do { try await provider.end(id: record.id) }
            catch { failure = (error as? MorningLiveActivityError) ?? .endFailed }
        }
        if let failure { throw failure }
        guard provider.records.allSatisfy({ $0.state == .dismissed }) else {
            throw MorningLiveActivityError.endUnconfirmed
        }
        activeActivityID = nil; currentSnapshot = nil; status = .inactive
    }
}
