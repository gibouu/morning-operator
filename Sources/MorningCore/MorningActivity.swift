import Foundation
#if canImport(ActivityKit) && os(iOS)
import ActivityKit
#endif

/// Closed vocabulary only: nothing from titles, notes, calendar facts or OCR.
public enum MorningActivityCategory: String, Codable, Hashable, Sendable, CaseIterable {
    case briefing, messages, calendar, wellbeing, entertainment, custom
    public var displayName: String {
        switch self {
        case .briefing: "Briefing"
        case .messages: "Messages"
        case .calendar: "Calendar"
        case .wellbeing: "Wellbeing"
        case .entertainment: "Time to enjoy"
        case .custom: "Your moment"
        }
    }
}

public enum MorningActivityStatus: String, Codable, Hashable, Sendable, CaseIterable {
    case running, paused, needsAttention
    public var displayName: String {
        switch self {
        case .running: "In progress"
        case .paused: "Paused"
        case .needsAttention: "Your turn"
        }
    }
}

/// Tests use a distinct namespace even when running the same installed bundle.
public enum MorningActivityNamespace: Codable, Hashable, Sendable {
    case production
    case testing(workspaceID: UUID)
}

public enum MorningActivityValidationError: Error, Sendable, Equatable {
    case invalidProgress, invalidTimestamp
}

public struct MorningActivityContentState: Codable, Hashable, Sendable {
    public let category: MorningActivityCategory
    public let status: MorningActivityStatus
    /// Number of moments passed, including explicitly skipped moments; not a
    /// claim that a real-world action was performed or a message was read.
    public let completedSteps: Int
    public let totalSteps: Int
    public let updatedAt: Date
    public var currentStepNumber: Int { completedSteps + 1 }

    public init(category: MorningActivityCategory, status: MorningActivityStatus,
                completedSteps: Int, totalSteps: Int, updatedAt: Date) throws {
        guard (1...100).contains(totalSteps), completedSteps >= 0, completedSteps < totalSteps else {
            throw MorningActivityValidationError.invalidProgress
        }
        guard updatedAt.timeIntervalSinceReferenceDate.isFinite else {
            throw MorningActivityValidationError.invalidTimestamp
        }
        self.category = category; self.status = status
        self.completedSteps = completedSteps; self.totalSteps = totalSteps; self.updatedAt = updatedAt
    }
    private enum CodingKeys: CodingKey { case category, status, completedSteps, totalSteps, updatedAt }
    public init(from decoder: any Decoder) throws {
        let value = try decoder.container(keyedBy: CodingKeys.self)
        try self.init(category: value.decode(MorningActivityCategory.self, forKey: .category),
            status: value.decode(MorningActivityStatus.self, forKey: .status),
            completedSteps: value.decode(Int.self, forKey: .completedSteps),
            totalSteps: value.decode(Int.self, forKey: .totalSteps),
            updatedAt: value.decode(Date.self, forKey: .updatedAt))
    }
    public func hasSameProgress(as other: Self) -> Bool {
        category == other.category && status == other.status &&
        completedSteps == other.completedSteps && totalSteps == other.totalSteps
    }
}

public struct MorningActivitySnapshot: Codable, Hashable, Sendable {
    public let sessionID: UUID
    public let state: MorningActivityContentState
    public init(sessionID: UUID, state: MorningActivityContentState) {
        self.sessionID = sessionID; self.state = state
    }
}

public enum MorningActivityProjection {
    /// Ready and terminal sessions have no Live Activity. Paused is explicit;
    /// a running session may instead need attention for an unavailable operation.
    public static func snapshot(session: RoutineSession?, needsAttention: Bool = false,
                                at date: Date = Date()) -> MorningActivitySnapshot? {
        guard let session, session.status == .running || session.status == .paused,
              session.routine.isApproved, let step = session.currentStep,
              let category = MorningActivityCategory(rawValue: step.kind.rawValue) else { return nil }
        let status: MorningActivityStatus = session.status == .paused ? .paused :
            (needsAttention ? .needsAttention : .running)
        guard let state = try? MorningActivityContentState(category: category, status: status,
            completedSteps: session.currentStepIndex, totalSteps: session.routine.steps.count, updatedAt: date) else { return nil }
        return .init(sessionID: session.id, state: state)
    }
}

#if canImport(ActivityKit) && os(iOS)
public struct MorningActivityAttributes: ActivityAttributes {
    public typealias ContentState = MorningActivityContentState
    public let sessionID: UUID
    public let namespace: MorningActivityNamespace
    public init(sessionID: UUID, namespace: MorningActivityNamespace = .production) {
        self.sessionID = sessionID; self.namespace = namespace
    }
}
#endif
