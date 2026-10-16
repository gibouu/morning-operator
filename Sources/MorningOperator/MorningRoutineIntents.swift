import AppIntents
import Foundation
import MorningCore
import MorningApple
import UIKit

struct PendingMorningCommand: Equatable {
    enum Action: String { case brief, next, skip, end }
    let id = UUID()
    let action: Action
    let sessionID: UUID?
    let stepID: UUID?
    let expiresAt = Date().addingTimeInterval(30)
}

struct BriefMorningIntent: AppIntent {
    static let title: LocalizedStringResource = "Brief me"
    static let supportedModes: IntentModes = .foreground(.immediate)
    @MainActor func perform() async throws -> some IntentResult {
        MorningIntentRouter.shared.requestCommand(.brief); return .result()
    }
}
struct NextMorningStepIntent: AppIntent {
    static let title: LocalizedStringResource = "Next step"
    static let supportedModes: IntentModes = .foreground(.immediate)
    @MainActor func perform() async throws -> some IntentResult {
        MorningIntentRouter.shared.requestCommand(.next); return .result()
    }
}
struct SkipMorningStepIntent: AppIntent {
    static let title: LocalizedStringResource = "Skip step"
    static let supportedModes: IntentModes = .foreground(.immediate)
    @MainActor func perform() async throws -> some IntentResult {
        MorningIntentRouter.shared.requestCommand(.skip); return .result()
    }
}
struct EndMorningIntent: AppIntent {
    static let title: LocalizedStringResource = "End my morning"
    static let supportedModes: IntentModes = .foreground(.immediate)
    @MainActor func perform() async throws -> some IntentResult {
        MorningIntentRouter.shared.requestCommand(.end); return .result()
    }
}
private enum RoutineCaptureError: LocalizedError {
    case empty
    var errorDescription: String? { AppLanguage.localized("Add a few words to capture.") }
}

struct NoteDreamIntent: AppIntent {
    static let title: LocalizedStringResource = "Note a dream"
    static let supportedModes: IntentModes = .foreground(.immediate)
    @Parameter(title: "Dream", requestValueDialog: "What did you dream?") var text: String
    @MainActor func perform() async throws -> some IntentResult {
        guard !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { throw RoutineCaptureError.empty }
        try MorningIntentRouter.shared.requestCapture("\(AppLanguage.localized("Dream")): \(text)"); return .result()
    }
}
struct RememberMorningIntent: AppIntent {
    static let title: LocalizedStringResource = "Remember this"
    static let supportedModes: IntentModes = .foreground(.immediate)
    @Parameter(title: "Thought", requestValueDialog: "What would you like to remember?") var text: String
    @MainActor func perform() async throws -> some IntentResult {
        guard !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { throw RoutineCaptureError.empty }
        try MorningIntentRouter.shared.requestCapture("\(AppLanguage.localized("Thought")): \(text)"); return .result()
    }
}

extension MorningStore {
    func performMorningCommand(_ command: PendingMorningCommand) {
        guard !privacyBlocksWork, Date() < command.expiresAt else { return }
        switch command.action {
        case .next, .skip:
            nextTargetStep(sessionID: command.sessionID, stepID: command.stepID, skipping: command.action == .skip)
        case .end:
            guard command.sessionID == nil || session?.id == command.sessionID else { return }
            stop()
        case .brief:
            if currentOpening != nil { chooseOpening(.brief); return }
            guard !sessionActive, !voiceInputBlocksPlayback else {
                notice = AppLanguage.localized("Pause or finish your morning before playing another recap."); return
            }
            let generation = dataGeneration
            Task {
                guard let document = await briefing.refresh(), dataGeneration == generation,
                      !privacyBlocksWork, !sessionActive, !voiceInputBlocksPlayback,
                      UIApplication.shared.applicationState == .active,
                      document.isCurrent(at: Date(), timeZoneIdentifier: TimeZone.current.identifier),
                      briefing.permitsPlayback(of: document) else { return }
                notice = document.sleep.status == .notConfigured ? document.spokenText :
                    (AppLanguage.isFrench ? "Retrouvez ce récapitulatif dans Réglages → Calendrier, météo et sommeil."
                        : "Find this recap in Settings → Calendar, weather & sleep.")
                speech.speak(document.spokenText)
            }
        }
    }
}
