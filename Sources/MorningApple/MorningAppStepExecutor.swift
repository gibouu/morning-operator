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
    @ObservationIgnored private let advice: @MainActor (PreparedMorningBriefing) async throws -> String
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
                  permitsPlayback: { briefing.permitsPlayback(of: $0) }, resolveObservation: resolveObservation,
                  advice: { document in
                      guard MoreLanguageModel.shared.usesOpenAI, document.weather.status == .fresh else { return "" }
                      return try await MorningVoiceConversation().morningAdvice(context: document.weather.text)
                  })
    }

    public init(prepare: @escaping @MainActor () async -> PreparedMorningBriefing?,
                speak: @escaping @MainActor (String) async throws -> Void,
                stop: @escaping @MainActor () -> Void,
                now: @escaping @MainActor () -> Date = { Date() },
                timeZone: @escaping @MainActor () -> String = { TimeZone.current.identifier },
                configurationID: @escaping @MainActor () -> UUID? = { nil },
                permitsPlayback: @escaping @MainActor (PreparedMorningBriefing) -> Bool = { _ in true },
                resolveObservation: @escaping @MainActor (RoutineStep) -> String? = { _ in nil },
                advice: @escaping @MainActor (PreparedMorningBriefing) async throws -> String = { _ in "" }) {
        self.prepare = prepare; self.speak = speak; self.stop = stop
        self.now = now; self.timeZone = timeZone
        self.configurationID = configurationID; self.permitsPlayback = permitsPlayback
        self.resolveObservation = resolveObservation
        self.advice = advice
    }

    public func execute(step: RoutineStep, context: MorningStepContext) async throws -> MorningStepOutcome {
        let token = UUID()
        attempt = token
        if pinnedExecutionID != context.executionID {
            pinnedBriefing = nil; pinnedExecutionID = nil
        }
        switch step.automation {
        case .spokenNote:
            guard spokenEnabled else { return .needsUser(AppLanguage.localized("Read at your pace, then tap Next.", bundle: .module)) }
            try await speak("\(step.title). \(step.detail)")
        case .savedObservation:
            guard spokenEnabled else { return .needsUser(AppLanguage.localized("Read at your pace, then tap Next.", bundle: .module)) }
            // Resolve against the current local archive on every play and Repeat.
            // Never turn deleted or changed evidence into an ordinary static note.
            guard step.observationReference != nil, let text = resolveObservation(step),
                  !text.isEmpty, text.utf8.elementsEqual(step.detail.utf8) else {
                return .unavailable(AppLanguage.localized("This saved excerpt has changed or was removed.", bundle: .module))
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
                    return .unavailable(AppLanguage.localized("Your day is not ready. Check Calendar & weather in Settings.", bundle: .module))
                }
                if step.automation == .todayCalendar && document.calendar.status != .fresh {
                    return .unavailable(AppLanguage.localized("Your selected calendars are not ready. Check Calendar & weather in Settings.", bundle: .module))
                }
                pinnedBriefing = document
                pinnedExecutionID = context.executionID
                pinnedConfigurationID = configuration
            }
            guard let document = pinnedBriefing else { throw CancellationError() }
            guard document.isCurrent(at: now(), timeZoneIdentifier: timeZone()) else {
                return .unavailable(AppLanguage.localized("This recap needs an update before it can be read.", bundle: .module))
            }
            guard pinnedConfigurationID == configurationID(), permitsPlayback(document) else {
                return .unavailable(AppLanguage.localized("Your sources changed. This recap needs an update.", bundle: .module))
            }
            if step.automation == .todayCalendar && document.calendar.status != .fresh {
                return .unavailable(AppLanguage.localized("Your selected calendars are not ready. Check Calendar & weather in Settings.", bundle: .module))
            }
            let text = Self.text(for: step.automation, in: document)
            guard !text.isEmpty else { return .unavailable(AppLanguage.localized("There is no current briefing to read.", bundle: .module)) }
            // Muting speech still obtains and presents current facts; it cannot certify that they were read.
            guard spokenEnabled else { return .needsUser(AppLanguage.localized("Read at your pace, then tap Next.", bundle: .module)) }
            var spoken = text
            if step.automation == .morningBriefing, document.weather.status == .fresh {
                do {
                    let suggestion = try await advice(document)
                    try checkAttempt(token)
                    if !suggestion.isEmpty { spoken += " " + suggestion }
                } catch {
                    try checkAttempt(token)
                    // Optional advice may fail; verified source facts remain readable.
                }
            }
            try checkAttempt(token)
            guard pinnedConfigurationID == configurationID(), permitsPlayback(document),
                  document.isCurrent(at: now(), timeZoneIdentifier: timeZone()) else { throw CancellationError() }
            try await speak(spoken)
        case nil:
            return .needsUser(AppLanguage.localized("Enjoy this moment. Tap Next when you're ready.", bundle: .module))
        case .timedMoment, .gmailInbox:
            return .needsUser(AppLanguage.localized("This moment is managed by your morning session.", bundle: .module))
        }
        try checkAttempt(token)
        return .completed
    }

    /// The same segments supply the detail sheet and the utterance.
    public static func text(for operation: RoutineStepAutomation?, in document: PreparedMorningBriefing) -> String {
        // Calendar-only speech keeps the introduction and the calendar, nothing else.
        document.segments.filter { operation != .todayCalendar || $0.source == .introduction || $0.source == .calendar }
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
