import SwiftUI
import MorningApple
import MorningCore
import UIKit

struct MorningVoiceStartRequest: Identifiable, Equatable {
    let id = UUID()
    let languageCode = AppLanguage.code
    let routineVersionID: UUID
    let generation: UUID
    let originalSessionID: UUID?
    let originalSessionStatus: SessionStatus?
    let entryID: UUID?
}

struct MorningVoiceStartDecision {
    let request: MorningVoiceStartRequest
    let listen: Bool
    let onlineSpeech: Bool
}

struct MorningVoicePreparationPresenter: ViewModifier {
    @Bindable var store: MorningStore
    @Environment(\.scenePhase) private var scenePhase

    func body(content: Content) -> some View {
        content.morningSheet(item: Binding(get: { store.voiceStartRequest }, set: { request in
            if request == nil { store.cancelVoicePreparation() }
        })) { request in
            MorningVoicePreparationView(store: store, startRequest: request)
                .id(request.id)
        }
        .onChange(of: scenePhase) { _, phase in
            if phase == .background { store.cancelVoicePreparation() }
        }
        .onChange(of: store.dataGeneration) { _, _ in store.cancelVoicePreparation() }
        .onChange(of: store.routine?.id) { _, _ in store.cancelVoicePreparation() }
        .onChange(of: store.session?.status) { _, status in
            if let request = store.voiceStartRequest, status != request.originalSessionStatus { store.cancelVoicePreparation() }
        }
        .onChange(of: store.session?.id) { _, id in
            if let request = store.voiceStartRequest, id != request.originalSessionID { store.cancelVoicePreparation() }
        }
        .onChange(of: store.privacyBlocksWork) { _, blocked in
            if blocked { store.cancelVoicePreparation() }
        }
    }
}

extension MorningStore {
    var voicePreparationLanguage: MorningVoiceCommandLanguage { .current }

    var bypassesVoicePreparationForUITests: Bool {
        #if DEBUG
        let flags = ProcessInfo.processInfo.arguments
        return flags.contains("--ui-testing") && !flags.contains("--ui-testing-real-microphone") &&
            !flags.contains("--ui-testing-voice-preparation") && !flags.contains("--ui-testing-natural-voice-consent")
        #else
        return false
        #endif
    }
    var forcesVoicePreparationReviewForUITests: Bool {
        #if DEBUG
        let flags = ProcessInfo.processInfo.arguments
        return flags.contains("--ui-testing") && flags.contains("--ui-testing-voice-preparation") &&
            !flags.contains("--ui-testing-real-microphone")
        #else
        return false
        #endif
    }

    func voicePreparationIsCurrent(_ request: MorningVoiceStartRequest) -> Bool {
        !privacyBlocksWork && request.languageCode == AppLanguage.code && voiceStartRequest == request && dataGeneration == request.generation &&
            routine?.id == request.routineVersionID && session?.id == request.originalSessionID && session?.status == request.originalSessionStatus &&
            session?.status != .running
    }

    func cancelVoicePreparation() {
        voiceAccess.cancel()
        voiceStartRequest = nil
        voiceStartDecision = nil
    }

    @discardableResult
    func finishVoicePreparation(_ request: MorningVoiceStartRequest, listen: Bool, onlineSpeech: Bool = true) -> Bool {
        guard voicePreparationIsCurrent(request), UIApplication.shared.applicationState == .active else { return false }
        if listen, !voiceAccess.refresh(language: voicePreparationLanguage).isReady { return false }
        voiceStartDecision = MorningVoiceStartDecision(request: request, listen: listen, onlineSpeech: onlineSpeech)
        voiceStartRequest = nil
        defer { voiceStartDecision = nil }
        return start(entryID: request.entryID)
    }
}
