import Foundation
import MorningApple
import MorningCore

extension MorningStore {
    /// Capture an in-flight send before cancellation/background clears its private
    /// dialogue. The durable recap must preserve an unconfirmed external effect.
    func preserveMailExecutionBeforeInterruption() {
        guard let session, let step = currentStep,
              mailMorning.context?.sessionID == session.id, mailMorning.context?.stepID == step.id else { return }
        mailMorning.cancel()
        if let outcome = mailMorning.interruptedExecutionOutcome,
           currentExecutionRecord?.outcome != .uncertain || mailMorning.lastSendOutcome == .sent {
            recordExecution(outcome)
        }
    }

    func beginMailMorning() {
        guard !privacyBlocksWork, let session, session.status == .running,
              let step = session.currentStep, step.automation == .gmailInbox else { return }
        let context = MorningExecutionID(sessionID: session.id, routineVersionID: session.routine.id, stepID: step.id)
        handsFreeUtteranceHandler = { [weak self] text in await self?.handleMailUtterance(text) ?? false }
        if let timer = activeStepTimer, !timer.isExpired(at: Date()) { mailBudgetDeadlinePaused = nil }
        if mailMorning.context == context {
            if mailMorning.isAwaitingResponse {
                connectedActionStatus = mailMorning.message
                return
            }
            if mailMorning.isCompleted {
                updateMailMorning(context: context)
                return
            }
            if [.preparing, .preparingReply, .sending].contains(mailMorning.state), connectedAPITask != nil { return }
        }
        let generation = dataGeneration
        let privacyGeneration = (try? LocalDataControl(directory: LocalDataControl.defaultDirectory).status())?.generation
        if currentExecutionRecord?.outcome != .uncertain {
            guard recordExecution(.running) else { return }
        }
        connectedActionStatus = AppLanguage.isFrench ? "Je prépare vos mails…" : "Preparing your mail…"
        connectedAPITask?.cancel()
        connectedAPITask = Task { @MainActor [weak self] in
            guard let self, !Task.isCancelled, dataGeneration == generation, !privacyBlocksWork,
                  self.session?.id == context.sessionID, currentStep?.id == context.stepID else { return }
            let work = beginMailBudgetWork(context: context)
            defer { endMailBudgetWork(work, context: context) }
            await mailMorning.begin(context: context, generation: privacyGeneration)
            guard !Task.isCancelled, dataGeneration == generation, !privacyBlocksWork,
                  self.session?.id == context.sessionID, currentStep?.id == context.stepID else { return }
            connectedAPITask = nil
            updateMailMorning(context: context)
        }
    }

    func handleMailUtterance(_ text: String) async -> Bool {
        guard !privacyBlocksWork, let session, let step = session.currentStep, step.automation == .gmailInbox else { return false }
        let context = MorningExecutionID(sessionID: session.id, routineVersionID: session.routine.id, stepID: step.id)
        guard mailMorning.context == context, mailMorning.isAwaitingResponse else { return false }
        let generation = dataGeneration
        // Barge-in paused this same session. Resume state without redispatching
        // the mail step, or we would fetch/announce the Inbox over the reply.
        if session.status == .paused, handsFreeVoice.interruptedRunningSession { resumeForNext() }
        handsFreeVoice.interruptedRunningSession = false
        if self.session?.status == .running, !resumeMailBudget(context: context) { return true }
        let work = beginMailBudgetWork(context: context)
        defer { endMailBudgetWork(work, context: context) }
        await mailMorning.respond(text, context: context)
        guard !Task.isCancelled, dataGeneration == generation, !privacyBlocksWork,
              self.session?.id == context.sessionID, currentStep?.id == context.stepID else { return true }
        updateMailMorning(context: context)
        return true
    }

    /// Touch fallback uses the same profile-bound draft and explicit-send dialogue
    /// as speech. It is available only in this active Gmail moment.
    func beginSelfMail() {
        performMailReviewAction { mail, context in await mail.beginSelfMessage(context: context) }
    }

    func reviewSelfMail() {
        let subject = mailMorning.selfMessageSubject, body = mailMorning.draftText
        performMailReviewAction { mail, context in
            await mail.reviewSelfMessage(subject: subject, body: body, context: context)
        }
    }

    func sendReviewedSelfMail() {
        guard mailMorning.canSendSelfMessage else { return }
        performMailReviewAction { mail, context in await mail.respond("envoie", context: context) }
    }

    func editSelfMail(subject: String, body: String) {
        guard let context = currentMailContext, !privacyBlocksWork else { return }
        connectedAPITask?.cancel(); connectedAPITask = nil
        speech.stop()
        mailMorning.editSelfMessage(subject: subject, body: body, context: context)
        connectedActionStatus = mailMorning.message
    }

    func continueMailMorning() {
        performMailReviewAction { mail, context in await mail.respond("continuer", context: context) }
    }

    func chooseReadMail(id: String) {
        guard mailMorning.canChooseMessage else { return }
        performMailReviewAction { mail, context in await mail.chooseMessage(id: id, context: context) }
    }

    private var currentMailContext: MorningExecutionID? {
        guard !privacyBlocksWork, sessionActive, let session, let step = currentStep,
              step.automation == .gmailInbox else { return nil }
        let context = MorningExecutionID(sessionID: session.id, routineVersionID: session.routine.id, stepID: step.id)
        return mailMorning.context == context ? context : nil
    }

    private func performMailReviewAction(_ action: @escaping @MainActor (GmailMorningConversation, MorningExecutionID) async -> Void) {
        guard let context = currentMailContext else { return }
        if session?.status == .running { pause() }
        guard session?.status == .paused else { return }
        resumeForNext()
        guard session?.status == .running, resumeMailBudget(context: context) else { return }
        let generation = dataGeneration
        connectedAPITask?.cancel()
        connectedAPITask = Task { @MainActor [weak self] in
            guard let self, !Task.isCancelled, dataGeneration == generation, !privacyBlocksWork,
                  currentMailContext == context else { return }
            let work = beginMailBudgetWork(context: context)
            defer { endMailBudgetWork(work, context: context) }
            await action(mailMorning, context)
            guard !Task.isCancelled, dataGeneration == generation, !privacyBlocksWork,
                  currentMailContext == context else { return }
            connectedAPITask = nil
            updateMailMorning(context: context)
        }
    }

    @discardableResult
    func resumeMailBudget(context: MorningExecutionID) -> Bool {
        guard !privacyBlocksWork, session?.status == .running,
              session?.id == context.sessionID, session?.routine.id == context.routineVersionID,
              currentStep?.id == context.stepID, currentStep?.automation == .gmailInbox,
              let timer = activeStepTimer else { return false }
        if timer.pausedAt != nil {
            guard StepTimerFile.update(sessionID: context.sessionID, stepID: context.stepID,
                { $0.resume(at: Date()) }) != nil else {
                pause()
                notice = AppLanguage.isFrench ? "Le budget mail n’a pas pu reprendre. Réessayez ou dites suivant."
                    : "The mail budget could not resume. Try again or say next."
                return false
            }
            stepTimerRevision += 1
        }
        armStepTimer()
        synchronizeMorningActivity()
        return true
    }

    private func beginMailBudgetWork(context: MorningExecutionID) -> UUID {
        let id = UUID(); mailBudgetWork[id] = context; return id
    }

    private func endMailBudgetWork(_ id: UUID, context: MorningExecutionID) {
        mailBudgetWork[id] = nil
        guard !privacyBlocksWork, session?.status == .running,
              session?.id == context.sessionID, session?.routine.id == context.routineVersionID,
              currentStep?.id == context.stepID, let timer = activeStepTimer,
              timer.hasAlertedCurrentEnd, timer.isExpired(at: Date()) else { return }
        _ = finishMailBudget(timer)
    }

    /// Wait for the exact model/provider/speech turn before deciding the end of the budget.
    @discardableResult
    func finishMailBudget(_ timer: StepTimer) -> Bool {
        guard !privacyBlocksWork, session?.status == .running, let session, let step = currentStep,
              step.automation == .gmailInbox, timer.belongs(to: session.id, stepID: step.id) else { return false }
        let context = MorningExecutionID(sessionID: session.id, routineVersionID: session.routine.id, stepID: step.id)
        let uncertain = currentExecutionRecord?.outcome == .uncertain && mailMorning.lastSendOutcome != .sent
        let decision = GmailMomentBudgetPolicy.decision(state: mailMorning.state, readOutcome: mailMorning.readOutcome,
            hasUnfinishedIntention: mailMorning.hasUnfinishedIntention, hasUncertainRecord: uncertain,
            workInFlight: connectedAPITask != nil || mailBudgetWork.values.contains(context),
            hasOtherDialogue: nativeMoment.isActive)
        if decision == .waitForWork { return true }
        if decision == .pauseKeepingDialogue || !automatic {
            mailBudgetDeadlinePaused = context
            pause()
            let message: String
            if uncertain || mailMorning.state == .uncertain {
                message = AppLanguage.isFrench
                    ? "Le temps des mails est écoulé. L’envoi reste à vérifier ; aucun nouvel envoi n’est lancé. Votre matin est en pause. Dites encore deux minutes pour le vérifier, ou suivant pour continuer."
                    : "Mail time is up. The send still needs checking; no new send is started. Your morning is paused. Say two more minutes to check it, or next to continue."
            } else {
                message = AppLanguage.isFrench
                    ? "Le temps des mails est écoulé. Votre matin est en pause, sans envoi. Votre choix en cours est conservé. Dites encore deux minutes pour continuer ici, ou suivant pour quitter ce moment."
                    : "Mail time is up. Your morning is paused without sending. Your current choice is kept. Say two more minutes to continue here, or next to leave this moment."
            }
            connectedActionStatus = message
            if readAloud { speech.speak(message) }
            return true
        }
        if case .advance(let outcome) = decision {
            guard recordExecution(outcome) else { pause(); return true }
            advance(skipping: outcome != .budgetFinished, commandID: step.id)
            return true
        }
        return true
    }

    private func updateMailMorning(context: MorningExecutionID) {
        connectedActionStatus = mailMorning.message
        switch mailMorning.state {
        case .completed:
            if currentExecutionRecord?.outcome == .uncertain, mailMorning.lastSendOutcome != .sent {
                advance(skipping: true, commandID: context.stepID)
            } else if let outcome = mailMorning.completedExecutionOutcome, outcome != .completed {
                guard recordExecution(outcome) else { return }
                advance(skipping: true, commandID: context.stepID)
            } else {
                completeAutomatedStep(sessionID: context.sessionID, stepID: context.stepID)
            }
        case .uncertain:
            recordExecution(.uncertain)
        case .unavailable:
            if currentExecutionRecord?.outcome != .uncertain { recordExecution(.unavailable) }
        default: break
        }
        synchronizeMorningActivity()
    }
}
