import Foundation
import Observation
import MorningCore

/// Executes only the concrete operation approved for this moment. Source facts
/// are pinned to the session/step, so Repeat never silently changes its meaning.
@MainActor @Observable
public final class MorningAppStepExecutor: MorningStepExecuting {
    public var spokenEnabled = true
    public private(set) var pinnedBriefing: PreparedMorningBriefing?
    public private(set) var pinnedExecutionID: MorningExecutionID?
    @ObservationIgnored private let prepare: @MainActor () async -> PreparedMorningBriefing?
    @ObservationIgnored private let speak: @MainActor (String) async throws -> Void
    @ObservationIgnored private let stop: @MainActor () -> Void
    @ObservationIgnored private let now: @MainActor () -> Date
    @ObservationIgnored private let timeZone: @MainActor () -> String
    @ObservationIgnored private let configurationID: @MainActor () -> UUID?
    @ObservationIgnored private let permitsPlayback: @MainActor (PreparedMorningBriefing) -> Bool
    @ObservationIgnored private let resolveObservation: @MainActor (RoutineStep) -> String?
    @ObservationIgnored private var pinnedConfigurationID: UUID?
    @ObservationIgnored private var attempt = UUID()

    public convenience init(speech: SpeechCoordinator, briefing: MorningBriefingController,
                            resolveObservation: @escaping @MainActor (RoutineStep) -> String? = { _ in nil }) {
        self.init(prepare: { await briefing.refresh() },
                  speak: { try await speech.speakAndWait($0) }, stop: { speech.stop() },
                  configurationID: { briefing.playbackRevision },
                  permitsPlayback: { briefing.permitsPlayback(of: $0) }, resolveObservation: resolveObservation)
    }

    public init(prepare: @escaping @MainActor () async -> PreparedMorningBriefing?,
                speak: @escaping @MainActor (String) async throws -> Void,
                stop: @escaping @MainActor () -> Void,
                now: @escaping @MainActor () -> Date = { Date() },
                timeZone: @escaping @MainActor () -> String = { TimeZone.current.identifier },
                configurationID: @escaping @MainActor () -> UUID? = { nil },
                permitsPlayback: @escaping @MainActor (PreparedMorningBriefing) -> Bool = { _ in true },
                resolveObservation: @escaping @MainActor (RoutineStep) -> String? = { _ in nil }) {
        self.prepare = prepare; self.speak = speak; self.stop = stop
        self.now = now; self.timeZone = timeZone
        self.configurationID = configurationID; self.permitsPlayback = permitsPlayback
        self.resolveObservation = resolveObservation
    }

    public func execute(step: RoutineStep, context: MorningStepContext) async throws -> MorningStepOutcome {
        let token = UUID()
        attempt = token
        if pinnedExecutionID != context.executionID {
            pinnedBriefing = nil; pinnedExecutionID = nil
        }
        guard spokenEnabled else { return .needsUser(String(localized: "Read at your pace, then tap Next.", bundle: .module)) }
        switch step.automation {
        case .spokenNote:
            try await speak("\(step.title). \(step.detail)")
        case .savedObservation:
            // Resolve against the current local archive on every play and Repeat.
            // Never turn deleted or changed evidence into an ordinary static note.
            guard step.observationReference != nil, let text = resolveObservation(step),
                  !text.isEmpty, text.utf8.elementsEqual(step.detail.utf8) else {
                return .unavailable(String(localized: "This saved excerpt has changed or was removed. Choose it again in Review, or tap Next.", bundle: .module))
            }
            try checkAttempt(token)
            try await speak(text)
        case .todayCalendar, .morningBriefing:
            if pinnedBriefing == nil {
                let configuration = configurationID()
                let document = await prepare()
                try checkAttempt(token)
                guard configurationID() == configuration else { throw CancellationError() }
                guard let document, document.isCurrent(at: now(), timeZoneIdentifier: timeZone()) else {
                    return .unavailable(String(localized: "Your day isn't ready. Check Your day in Settings, or tap Next to continue.", bundle: .module))
                }
                if step.automation == .todayCalendar && document.calendar.status != .fresh {
                    return .unavailable(String(localized: "Your selected calendars aren't ready. Check Your day in Settings, or tap Next.", bundle: .module))
                }
                pinnedBriefing = document
                pinnedExecutionID = context.executionID
                pinnedConfigurationID = configuration
            }
            guard let document = pinnedBriefing else { throw CancellationError() }
            guard document.isCurrent(at: now(), timeZoneIdentifier: timeZone()) else {
                return .unavailable(String(localized: "This recap needs an update. Open this moment to prepare it again, or tap Next.", bundle: .module))
            }
            guard pinnedConfigurationID == configurationID(), permitsPlayback(document) else {
                return .unavailable(String(localized: "Your sources have changed. Update this recap before playing it again.", bundle: .module))
            }
            if step.automation == .todayCalendar && document.calendar.status != .fresh {
                return .unavailable(String(localized: "Your selected calendars aren't ready. Check Your day in Settings, or tap Next.", bundle: .module))
            }
            let text = Self.text(for: step.automation, in: document)
            guard !text.isEmpty else { return .unavailable(String(localized: "There's no current briefing to read yet.", bundle: .module)) }
            try checkAttempt(token)
            try await speak(text)
        case nil:
            return .needsUser(String(localized: "Enjoy this moment. Tap Next when you're ready.", bundle: .module))
        }
        try checkAttempt(token)
        return .completed
    }

    /// The same segments supply the detail sheet and the utterance.
    public static func text(for operation: RoutineStepAutomation?, in document: PreparedMorningBriefing) -> String {
        document.segments.filter { operation != .todayCalendar || $0.source != .weather }
            .map(\.text).joined(separator: " ")
    }

    public func cancel(context: MorningStepContext) { cancelPlayback() }
    public func cancelPlayback() { attempt = UUID(); stop() }
    public func clear() {
        cancelPlayback()
        pinnedBriefing = nil; pinnedExecutionID = nil
        pinnedConfigurationID = nil
    }

    private func checkAttempt(_ token: UUID) throws {
        try Task.checkCancellation()
        guard attempt == token else { throw CancellationError() }
    }
}
