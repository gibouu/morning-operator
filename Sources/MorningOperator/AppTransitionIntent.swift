import AppIntents
import Foundation
import MorningApple
import MorningCore

enum ShortcutObservedApp: String, AppEnum {
    case instagram, tiktok, snapchat
    static let typeDisplayRepresentation: TypeDisplayRepresentation = "Observed app"
    static let caseDisplayRepresentations: [Self: DisplayRepresentation] = [
        .instagram: "Instagram", .tiktok: "TikTok", .snapchat: "Snapchat"
    ]
    var observedApp: ObservedApp {
        switch self {
        case .instagram: .instagram
        case .tiktok: .tiktok
        case .snapchat: .snapchat
        }
    }
}

enum ShortcutAppTransition: String, AppEnum {
    case entered, exited
    static let typeDisplayRepresentation: TypeDisplayRepresentation = "App transition"
    static let caseDisplayRepresentations: [Self: DisplayRepresentation] = [
        .entered: "Opened or switched to", .exited: "Closed or switched from"
    ]
    var kind: AppTransitionKind { self == .entered ? .entered : .exited }
}

/// Add this action to user-created per-app Opened/Closed personal automations.
/// It neither observes other apps by itself nor brings Morning Operator to the foreground.
struct LogAppTransitionIntent: AppIntent {
    static let title: LocalizedStringResource = "Log an app transition"
    static let description = IntentDescription("Record a transition supplied by your configured App automation. Counts observed app entries, not pickups. This action does not start screen recording.")
    static let supportedModes: IntentModes = .background

    @Parameter(title: "App") var app: ShortcutObservedApp
    @Parameter(title: "Transition", default: .entered) var transition: ShortcutAppTransition
    @Parameter(title: "Event ID", description: "Optional UUID generated once for this event. Reuse it only when retrying that same event.")
    var eventID: String?

    static var parameterSummary: some ParameterSummary {
        Summary("Log \(\.$app): \(\.$transition)") { \.$eventID }
    }

    func perform() async throws -> some IntentResult {
        let supplied = eventID?.trimmingCharacters(in: .whitespacesAndNewlines)
        let id: UUID
        if let supplied, !supplied.isEmpty {
            guard let parsed = UUID(uuidString: supplied) else { throw TransitionIntentError.invalidEventID }
            id = parsed
        } else { id = UUID() }
        try await AppTransitionLogStore.shared.record(app: app.observedApp, kind: transition.kind, eventID: id)
        return .result()
    }
}

private enum TransitionIntentError: LocalizedError {
    case invalidEventID
    var errorDescription: String? { "Use a valid UUID for the event identifier, or leave it empty." }
}
