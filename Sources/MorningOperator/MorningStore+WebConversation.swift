import Foundation
import MorningCore
import UIKit

extension MorningStore {
    var currentConversationController: WebMorningController? {
        guard !privacyBlocksWork, automatic, let session, let step = currentStep,
              step.webBehavior == .readUnread, case let .inAppWeb(url) = step.target,
              let site = WebMorningSite(url: url), WebConversationPolicy.supports(site) else { return nil }
        return routineWebMoment.existingController(for: .init(sessionID: session.id,
            routineVersionID: session.routine.id, stepID: step.id), privacyGeneration: dataGeneration)
    }

    var webConversationIsActive: Bool { currentConversationController?.conversationIsActive == true }

    func resumeAfterBrowserSignIn() {
        guard let binding = browserSignInPause, binding.context == handsFreeContext,
              binding.privacy == dataGeneration, binding.revision == handsFreePauseRevision,
              session?.status == .paused, !privacyBlocksWork, pendingWebTarget != nil,
              UIApplication.shared.applicationState == .active else { return }
        browserSignInPause = nil
        resume()
    }

    func reconcileBrowserSend(sent: Bool) async {
        guard let controller = currentConversationController, let context = handsFreeContext else { return }
        if session?.status == .running { pause() }
        let privacy = dataGeneration, revision = handsFreePauseRevision
        await controller.reconcileConversationSend(sent: sent, authorized: { [weak self] in
            guard let self else { return false }
            return !self.privacyBlocksWork && self.handsFreeContext == context && self.dataGeneration == privacy &&
                self.handsFreePauseRevision == revision && self.session?.status == .paused
        })
    }

    @discardableResult
    func handleWebConversationUtterance(_ text: String) async -> Bool {
        guard let controller = currentConversationController, let context = handsFreeContext else { return false }
        let parsed = WebConversationIntent.parse(text)
        let intent: WebConversationIntent
        if let parsed { intent = parsed }
        else if controller.conversationDraft.phase == .awaitingIntention { intent = .reply(text) }
        else { return false }
        // A bare yes/no must refer to a message MORE has actually observed.
        if [.accept, .decline, .cancel, .send, .repeatReply].contains(intent),
           controller.conversationSnapshot == nil, !controller.conversationIsActive { return false }
        guard !nativeMoment.isActive, !slackReply.isActive, !mailMorning.isAwaitingResponse else { return false }
        if session?.status == .running { pause() }
        handsFreeVoice.interruptedRunningSession = false
        let privacy = dataGeneration, revision = handsFreePauseRevision
        let authorized: @MainActor () -> Bool = { [weak self] in
            guard let self else { return false }
            return !self.privacyBlocksWork && self.handsFreeContext == context && self.dataGeneration == privacy &&
                self.handsFreePauseRevision == revision && self.session?.status == .paused &&
                UIApplication.shared.applicationState == .active
        }
        speech.stop()
        switch intent {
        case .decline, .cancel:
            controller.cancelConversationWork()
            if !controller.conversationIsActive { resume() }
        case .read:
            guard let result = await controller.observeConversation(authorized: authorized), authorized(), let source = result.snapshot else {
                speakHandsFree(french: "Ouvrez une conversation dans la page pour que je puisse la lire.",
                    english: "Open a conversation on the page so I can read it.")
                return true
            }
            speakHandsFree(french: "Message de \(source.recipient) : \(source.messageText). Voulez-vous répondre ?",
                english: "Message from \(source.recipient): \(source.messageText). Would you like to reply?")
        case .accept:
            if controller.conversationDraft.phase == .awaitingSend {
                speakHandsFree(french: "Dites envoie pour envoyer cette réponse, ou indiquez une correction.",
                    english: "Say send to send this reply, or say what to change.")
            } else if [.reviewing, .preparing].contains(controller.conversationDraft.phase) {
                await reviewBrowserReply(controller, authorized: authorized)
            } else if await controller.beginConversationReply(authorized: authorized), authorized() {
                speakHandsFree(french: "Que souhaitez-vous lui répondre ?", english: "What would you like to reply?")
            } else if authorized(), let line = controller.conversationMessage { speech.speak(line) }
        case .reply(let intention), .revise(let intention):
            if controller.conversationDraft.snapshot == nil {
                guard await controller.beginConversationReply(authorized: authorized), authorized() else {
                    speakHandsFree(french: controller.conversationMessage ?? "Ouvrez une conversation dans la page, puis demandez une réponse.",
                        english: controller.conversationMessage ?? "Open a conversation on the page, then ask for a reply.")
                    return true
                }
            }
            guard !intention.isEmpty else {
                speakHandsFree(french: "Que souhaitez-vous lui répondre ?", english: "What would you like to reply?")
                return true
            }
            await controller.prepareConversationReply(intention, authorized: authorized)
            guard authorized() else { return true }
            await reviewBrowserReply(controller, authorized: authorized)
        case .repeatReply:
            await reviewBrowserReply(controller, authorized: authorized)
        case .send:
            await controller.sendConversationReply(authorized: authorized)
            guard authorized() else { return true }
            let line = controller.conversationMessage ?? (AppLanguage.isFrench
                ? "Relisez le texte avant de demander l’envoi." : "Review the text before asking to send.")
            if controller.conversationDraft.phase == .completed {
                try? await speech.speakAndWait(line)
                if authorized(), controller.conversationDraft.phase == .completed { resume() }
            } else { speech.speak(line) }
        }
        return true
    }

    private func reviewBrowserReply(_ controller: WebMorningController, authorized: @MainActor () -> Bool) async {
        let body = controller.conversationDraft.body, operation = controller.conversationDraft.operationID
        guard !body.isEmpty, authorized() else {
            if let line = controller.conversationMessage { speech.speak(line) }
            return
        }
        let source = controller.conversationDraft.snapshot?.recipient ?? controller.site.displayName
        do {
            try await speech.speakAndWait(AppLanguage.isFrench
                ? "Réponse à \(source) : \(body). Dites envoie, ou indiquez une correction."
                : "Reply to \(source): \(body). Say send, or say what to change.")
            guard authorized(), controller.conversationDraft.operationID == operation else { return }
            controller.markConversationReplyReviewed()
        } catch { /* Interrupted review grants no send authority. The visible review remains available. */ }
    }
}
