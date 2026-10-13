import AppIntents
import Foundation
import Observation
import MorningCore
import MorningApple

/// Foreground intents only enqueue UI requests. A request stays held throughout its review sheet.
/// Nothing here approves a routine, writes to EventKit, or persists captured text.
@MainActor
@Observable
final class MorningIntentRouter {
    static let shared = MorningIntentRouter()
    private(set) var pendingCaptureText: String?
    private(set) var pendingStart: MorningEntryRequest?
    private(set) var invitationPayload: MorningInvitationPayload?

    private init() {}

    func resetPendingRequests() {
        pendingStart = nil
        invitationPayload = nil
        pendingCaptureText = nil
    }

    func requestStart(invitation: MorningInvitationPayload? = nil) {
        guard let state = try? LocalDataControl(directory: LocalDataControl.defaultDirectory).status(),
              !state.forgetPending else { return }
        // Repeated Siri phrases or duplicate notification callbacks cannot extend a
        // waiting request's lifetime or queue a second run behind the first.
        guard pendingStart == nil else { return }
        invitationPayload = invitation
        pendingStart = MorningEntryRequest(id: invitation?.occurrenceID ?? UUID())
    }

    func finishStart(_ id: UUID) {
        guard pendingStart?.id == id else { return }
        pendingStart = nil
        invitationPayload = nil
    }

    func requestCapture(_ text: String) throws {
        guard let state = try? LocalDataControl(directory: LocalDataControl.defaultDirectory).status(),
              !state.forgetPending else { throw MorningIntentError.dataRemovalPending }
        let text = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { throw MorningIntentError.emptyText }
        guard pendingCaptureText == nil else { throw MorningIntentError.captureWaiting }
        pendingCaptureText = text
    }

    /// Call after this request's sheet has actually dismissed, whether saved or cancelled.
    func finishCaptureReview() {
        pendingCaptureText = nil
    }
}

private enum MorningIntentError: LocalizedError {
    case emptyText, captureWaiting, dataRemovalPending

    var errorDescription: String? {
        switch self {
        case .dataRemovalPending: String(localized: "Finish removing local data in MORE before capturing another thought.")
        case .emptyText: String(localized: "Add a few words to capture.")
        case .captureWaiting: String(localized: "Review the capture already waiting in MORE, then try again.")
        }
    }
}

struct StartMorningIntent: AppIntent {
    static let title: LocalizedStringResource = "Start morning"
    static let description = IntentDescription("Open MORE and request your approved morning routine. A draft still needs your approval in the app.")
    static let supportedModes: IntentModes = .foreground(.immediate)
    static let authenticationPolicy: IntentAuthenticationPolicy = .requiresLocalDeviceAuthentication

    @MainActor
    func perform() async throws -> some IntentResult & ProvidesDialog {
        MorningIntentRouter.shared.requestStart()
        return .result(dialog: "Opening your morning in MORE.")
    }
}

enum MorningIntentCaptureKind: String, AppEnum {
    case thought, dream, reminder, calendar

    static let typeDisplayRepresentation: TypeDisplayRepresentation = "Capture kind"
    static let caseDisplayRepresentations: [Self: DisplayRepresentation] = [
        .thought: "Thought", .dream: "Dream", .reminder: "Reminder", .calendar: "Calendar idea"
    ]

    var textPrefix: String {
        switch self {
        case .thought: String(localized: "Thought")
        case .dream: String(localized: "Dream")
        case .reminder: String(localized: "Reminder")
        case .calendar: String(localized: "Calendar")
        }
    }
}

struct CaptureMorningIntent: AppIntent {
    static let title: LocalizedStringResource = "Capture for my morning"
    static let description = IntentDescription("Open a thought, dream, reminder request or calendar idea for review. This action does not save a reminder or calendar event.")
    static let supportedModes: IntentModes = .foreground(.immediate)

    @Parameter(title: "Kind", default: .thought)
    var kind: MorningIntentCaptureKind

    @Parameter(title: "Text", requestValueDialog: "What would you like to capture?")
    var text: String

    static var parameterSummary: some ParameterSummary {
        Summary("Capture \(\.$text) as a \(\.$kind)")
    }

    init() {}

    @MainActor
    func perform() async throws -> some IntentResult & ProvidesDialog {
        let content = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !content.isEmpty else { throw MorningIntentError.emptyText }
        try MorningIntentRouter.shared.requestCapture("\(kind.textPrefix): \(content)")
        return .result(dialog: "Ready for review in MORE.")
    }
}

struct MorningAppShortcuts: AppShortcutsProvider {
    static var appShortcuts: [AppShortcut] {
        AppShortcut(
            intent: StartMorningIntent(),
            phrases: ["Start my morning with \(.applicationName)", "Start \(.applicationName)"],
            shortTitle: "Start morning", systemImageName: "sun.max"
        )
        AppShortcut(
            intent: CaptureMorningIntent(),
            phrases: ["Capture a \(\.$kind) with \(.applicationName)", "Quick capture with \(.applicationName)"],
            shortTitle: "Quick capture", systemImageName: "square.and.pencil"
        )
    }
}
