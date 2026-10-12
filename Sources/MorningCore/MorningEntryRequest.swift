import Foundation

/// A foreground invitation to enter a morning, never permission to approve or record.
public struct MorningEntryRequest: Equatable, Sendable, Identifiable {
    public let id: UUID
    public let requestedAt: Date
    public let expiresAt: Date

    public init(id: UUID = UUID(), requestedAt: Date = .now, lifetime: TimeInterval = 60) {
        self.id = id
        self.requestedAt = requestedAt
        self.expiresAt = requestedAt.addingTimeInterval(max(0, min(lifetime, 60)))
    }
}

public enum MorningEntryDestination: Equatable, Sendable {
    case wait, revealMorning, reviewDraft, learn, start, resume
}

/// Describes readiness only. The application must persist an entry receipt with the
/// run transition before dispatching speech or any other supported step.
public struct MorningEntryContext: Sendable {
    public var sceneIsActive: Bool
    public var isOccupied: Bool
    public var storageIsAvailable: Bool
    public var hasRoutine: Bool
    public var routineIsApproved: Bool
    public var sessionStatus: SessionStatus?

    public init(sceneIsActive: Bool, isOccupied: Bool, storageIsAvailable: Bool,
                hasRoutine: Bool, routineIsApproved: Bool, sessionStatus: SessionStatus?) {
        self.sceneIsActive = sceneIsActive
        self.isOccupied = isOccupied
        self.storageIsAvailable = storageIsAvailable
        self.hasRoutine = hasRoutine
        self.routineIsApproved = routineIsApproved
        self.sessionStatus = sessionStatus
    }
}

public enum MorningEntryPolicy {
    public static func destination(for request: MorningEntryRequest, context: MorningEntryContext,
                                   consumedIDs: [UUID], now: Date = .now) -> MorningEntryDestination {
        guard context.sceneIsActive, !context.isOccupied else { return .wait }
        // A delayed request reveals the ordinary start button rather than starting
        // unexpectedly after a long review. Clock rollback also fails closed.
        guard request.requestedAt <= now, now < request.expiresAt,
              !consumedIDs.contains(request.id), context.storageIsAvailable else { return .revealMorning }
        guard context.hasRoutine else { return .learn }
        guard context.routineIsApproved else { return .reviewDraft }
        switch context.sessionStatus {
        case .running: return .revealMorning
        case .paused: return .resume
        default: return .start
        }
    }
}
