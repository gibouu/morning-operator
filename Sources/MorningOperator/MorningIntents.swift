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
    private(set) var pendingCommand: PendingMorningCommand?
    private(set) var pendingCaptureText: String?
    private(set) var pendingStart: MorningEntryRequest?
    private(set) var invitationPayload: MorningInvitationPayload?

    #if DEBUG
    /// Debug spike (docs/SEAMLESS-LEARNING.md): `more://watch-morning` opens the recorder
    /// and presents Apple's picker at once, so only Apple's confirmation is left to tap.
    private(set) var pendingWatchMorning = false
    func requestWatchMorning() { pendingWatchMorning = true }
    func consumeWatchMorning() -> Bool {
        defer { pendingWatchMorning = false }
        return pendingWatchMorning
    }
    #endif

    private init() {}

    func resetPendingRequests() {
        pendingStart = nil
        pendingCommand = nil
        invitationPayload = nil
        pendingCaptureText = nil
        #if DEBUG
        pendingWatchMorning = false
        #endif
    }

    func requestCommand(_ action: PendingMorningCommand.Action) {
        guard pendingCommand == nil, let state = try? LocalDataControl(directory: LocalDataControl.defaultDirectory).status(), !state.forgetPending else { return }
        let timer = StepTimerFile.load()
        pendingCommand = PendingMorningCommand(action: action, sessionID: timer?.sessionID, stepID: timer?.stepID)
    }

    func takeCommand() -> PendingMorningCommand? {
        defer { pendingCommand = nil }; return pendingCommand
    }

    func requestStart(invitation: MorningInvitationPayload? = nil, entryID: UUID? = nil) {
        guard let state = try? LocalDataControl(directory: LocalDataControl.defaultDirectory).status(),
              !state.forgetPending else { return }
        // Repeated Siri phrases or duplicate notification callbacks cannot extend a
        // waiting request's lifetime or queue a second run behind the first.
        guard pendingStart == nil else { return }
        invitationPayload = invitation
        pendingStart = MorningEntryRequest(id: entryID ?? invitation?.occurrenceID ?? UUID())
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
        case .dataRemovalPending: AppLanguage.localized("Finish removing local data in MORE before capturing another thought.")
        case .emptyText: AppLanguage.localized("Add a few words to capture.")
        case .captureWaiting: AppLanguage.localized("Review the capture already waiting in MORE, then try again.")
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
        return .result(dialog: IntentDialog(stringLiteral: String(localized: "Opening your morning in MORE.", bundle: AppLanguage.bundle(), locale: AppLanguage.locale)))
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
        case .thought: AppLanguage.localized("Thought")
        case .dream: AppLanguage.localized("Dream")
        case .reminder: AppLanguage.localized("Reminder")
        case .calendar: AppLanguage.localized("Calendar")
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
        return .result(dialog: IntentDialog(stringLiteral: String(localized: "Ready for review in MORE.", bundle: AppLanguage.bundle(), locale: AppLanguage.locale)))
    }
}

struct MorningAppShortcuts: AppShortcutsProvider {
    static var appShortcuts: [AppShortcut] {
        AppShortcut(
            intent: StartMorningIntent(),
            phrases: ["Start my morning with \(.applicationName)", "Start \(.applicationName)"],
            shortTitle: "Start morning", systemImageName: "sun.max"
        )
        AppShortcut(intent: BriefMorningIntent(), phrases: ["Brief me with \(.applicationName)"], shortTitle: "Brief me", systemImageName: "sun.max")
        AppShortcut(intent: NextMorningStepIntent(), phrases: ["Next step in \(.applicationName)"], shortTitle: "Next step", systemImageName: "arrow.right")
        AppShortcut(intent: AddStepTimeIntent(), phrases: ["Add two minutes in \(.applicationName)"], shortTitle: "Add two minutes", systemImageName: "timer")
        AppShortcut(intent: SkipMorningStepIntent(), phrases: ["Skip step in \(.applicationName)"], shortTitle: "Skip step", systemImageName: "forward.end")
        AppShortcut(intent: EndMorningIntent(), phrases: ["End my morning in \(.applicationName)"], shortTitle: "End morning", systemImageName: "stop")
        AppShortcut(intent: NoteDreamIntent(), phrases: ["Note a dream with \(.applicationName)"], shortTitle: "Note a dream", systemImageName: "moon")
        AppShortcut(intent: RememberMorningIntent(), phrases: ["Remember this with \(.applicationName)"], shortTitle: "Remember this", systemImageName: "square.and.pencil")
        AppShortcut(
            intent: CaptureMorningIntent(),
            phrases: ["Capture a \(\.$kind) with \(.applicationName)", "Quick capture with \(.applicationName)"],
            shortTitle: "Quick capture", systemImageName: "square.and.pencil"
        )
    }
}
