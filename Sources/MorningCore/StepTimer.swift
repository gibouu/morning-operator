import Foundation

/// The time budget of one running step that has a target. It holds absolute instants,
/// never a counter that ticks, so a suspended app cannot make it drift: the remaining
/// time is always `endsAt - now`.
public struct StepTimer: Codable, Hashable, Sendable {
    public static let extensionSeconds: TimeInterval = 120
    /// Thirty taps of +2 min, one hour. A stuck button cannot extend a step forever.
    public static let maximumExtensions = 30

    public let sessionID: UUID
    public let stepID: UUID
    public let startedAt: Date
    public private(set) var endsAt: Date
    public private(set) var extensionCount: Int
    /// When the step's target was opened. A timer that already opened it does not open
    /// it again on resume or relaunch.
    public private(set) var openedAt: Date?
    /// The end this timer already announced. A new end (after +2 min) is announced again;
    /// the same end never twice.
    public private(set) var alertedEnd: Date?
    public private(set) var pausedAt: Date?

    public init(sessionID: UUID, stepID: UUID, minutes: Int, at now: Date) {
        self.sessionID = sessionID; self.stepID = stepID; startedAt = now
        let minutes = min(max(RoutineStep.durationMinutesRange.lowerBound, minutes), RoutineStep.durationMinutesRange.upperBound)
        endsAt = now.addingTimeInterval(TimeInterval(minutes) * 60)
        extensionCount = 0
    }

    public func remaining(at now: Date) -> TimeInterval { max(0, endsAt.timeIntervalSince(pausedAt ?? now)) }
    public func isExpired(at now: Date) -> Bool { remaining(at: now) == 0 }
    public mutating func pause(at now: Date) { if pausedAt == nil { pausedAt = now } }
    public mutating func resume(at now: Date) {
        if let pausedAt { endsAt = endsAt.addingTimeInterval(max(0, now.timeIntervalSince(pausedAt))) }
        pausedAt = nil
    }
    public func belongs(to sessionID: UUID, stepID: UUID) -> Bool {
        self.sessionID == sessionID && self.stepID == stepID
    }

    public enum ExtensionResult: Equatable, Sendable {
        case extended(Date)
        /// The tap was made against an end that has already moved: a double tap, or a
        /// retried intent. Nothing changes.
        case duplicate
        case limitReached
    }

    /// Adds two minutes. `expectedEnd` is the end the person saw when tapping (the Live
    /// Activity sends the end it rendered). Two taps rendered against the same end add
    /// two minutes once. Nil (a voice command) always applies. An expired timer gets two
    /// minutes from now, not from its past end.
    public mutating func extend(expectedEnd: Date?, at now: Date) -> ExtensionResult {
        if let expectedEnd, abs(expectedEnd.timeIntervalSince(endsAt)) > 0.5 { return .duplicate }
        guard extensionCount < Self.maximumExtensions else { return .limitReached }
        endsAt = max(endsAt, pausedAt ?? now).addingTimeInterval(Self.extensionSeconds)
        extensionCount += 1
        return .extended(endsAt)
    }

    public mutating func markOpened(at now: Date) { if openedAt == nil { openedAt = now } }

    /// True once per end, and only when that end has passed.
    public mutating func claimAlert(at now: Date) -> Bool {
        guard isExpired(at: now), alertedEnd != endsAt else { return false }
        alertedEnd = endsAt
        return true
    }
    public var hasAlertedCurrentEnd: Bool { alertedEnd == endsAt }
}

/// What a Next request does to a session. The request names the session and the step
/// it was made from, so a stale or repeated Next cannot skip a second step or open the
/// app of a step the person never reached.
public enum StepNextDecision: Equatable, Sendable {
    /// Advance (resuming a paused run first), then open `target` if the new step has one.
    case advance(resumeFirst: Bool, then: RoutineStepTarget?)
    /// The request was made from a step that is no longer current. Do nothing.
    case stale
    /// No running or paused morning.
    case unavailable
}

public enum StepNavigation {
    public static func decide(session: RoutineSession?, sessionID: UUID?, stepID: UUID?) -> StepNextDecision {
        guard let session, session.status == .running || session.status == .paused,
              let current = session.currentStep else { return .unavailable }
        if let sessionID, sessionID != session.id { return .stale }
        if let stepID, stepID != current.id { return .stale }
        return .advance(resumeFirst: session.status == .paused, then: nextStep(in: session)?.target)
    }

    /// The step after the current one, or nil when the current one is the last.
    public static func nextStep(in session: RoutineSession) -> RoutineStep? {
        guard session.currentStep != nil else { return nil }
        let next = session.currentStepIndex + 1
        return session.routine.steps.indices.contains(next) ? session.routine.steps[next] : nil
    }

    /// `more://next?session=…&step=…`, the Live Activity's Next link.
    public static func nextURL(sessionID: UUID, stepID: UUID) -> URL {
        URL(string: "more://next?session=\(sessionID.uuidString)&step=\(stepID.uuidString)")!
    }

    /// The session and step a Next link names, or nil for any other URL.
    public static func parseNext(_ url: URL) -> (sessionID: UUID, stepID: UUID)? {
        guard url.scheme == "more", url.host == "next", url.path.isEmpty, url.fragment == nil,
              let items = URLComponents(url: url, resolvingAgainstBaseURL: false)?.queryItems,
              items.count == 2,
              let session = items.first(where: { $0.name == "session" })?.value.flatMap(UUID.init(uuidString:)),
              let step = items.first(where: { $0.name == "step" })?.value.flatMap(UUID.init(uuidString:))
        else { return nil }
        return (session, step)
    }
}
