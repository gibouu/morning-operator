import Foundation
import MorningCore
import MorningApple

extension MorningStore {
    func presentNativeStepFailure(context: MorningStepContext, reason: String) {
        guard !privacyBlocksWork, let session, sessionActive, let step = currentStep,
              step.target == nil, step.automation != nil, step.automation != .gmailInbox,
              context.executionID == MorningExecutionID(sessionID: session.id,
                routineVersionID: session.routine.id, stepID: step.id) else { return }
        guard recordExecution(.unavailable) else { pause(); return }
        if session.status == .running { pause() }
        let recovery: String
        if !canHearHandsFreeCommands {
            if step.automation == .todayCalendar || step.automation == .morningBriefing {
                recovery = AppLanguage.isFrench
                    ? "Votre matin est en pause. Vérifiez vos sources dans les réglages si besoin. Utilisez Actualiser ce récapitulatif pour réessayer, Suivant pour poursuivre ou Arrêter."
                    : "Your morning is paused. Check your sources in Settings if needed. Use Update this recap to retry, Next to move on or Stop."
            } else {
                recovery = AppLanguage.isFrench
                    ? "Votre matin est en pause. Utilisez Continuer pour réessayer, Suivant pour poursuivre ou Arrêter."
                    : "Your morning is paused. Use Continue to retry, Next to move on or Stop."
            }
        } else if step.automation == .todayCalendar || step.automation == .morningBriefing {
            recovery = AppLanguage.isFrench
                ? "Votre matin est en pause. Vérifiez vos sources dans les réglages si besoin, puis dites actualise ce briefing pour une nouvelle lecture, suivant pour continuer ou arrête."
                : "Your morning is paused. Check your sources in Settings if needed, then say refresh this briefing for a new reading, next to continue, or stop."
        } else {
            recovery = AppLanguage.isFrench
                ? "Votre matin est en pause. Dites reprends pour réessayer, suivant pour continuer ou arrête."
                : "Your morning is paused. Say resume to retry, next to continue, or stop."
        }
        let message = reason + " " + recovery
        connectedActionStatus = message
        notice = nil
        if readAloud { speech.speak(message) }
    }

    var executionSummary: String? {
        guard let session else { return nil }
        return executionSummary(for: session)
    }
    func executionRecapRows(for session: RoutineSession) -> [RoutineStepExecutionRecap] {
        guard !privacyBlocksWork else { return [] }
        return RoutineStepExecutionRecap.make(session: session, records: executionRecords)
    }

    func executionRecapText(for row: RoutineStepExecutionRecap, in session: RoutineSession) -> String {
        guard !privacyBlocksWork else { return "" }
        let french = AppLanguage.isFrench
        var text = row.summary(french: french)
        guard let step = session.routine.steps.first(where: { $0.id == row.id }),
              case .connectedAPI(let service, _, _, _) = step.target, service.lowercased() == "slack" else { return text }
        // A Slack reply is a separate durable effect, never evidence that the
        // read moment or its presentation succeeded. Query this exact context.
        guard let replies = slackActionCounts(for: session, stepID: row.id) else {
            return text + (french ? "\nÉtat des réponses Slack indisponible." : "\nSlack reply status unavailable.")
        }
        if replies.confirmed > 0 {
            text += french ? "\nRéponses Slack confirmées : \(replies.confirmed)." : "\nSlack replies confirmed: \(replies.confirmed)."
        }
        if replies.unconfirmed > 0 {
            text += french ? "\nRéponses Slack à vérifier : \(replies.unconfirmed)." : "\nSlack replies to check: \(replies.unconfirmed)."
        }
        return text
    }

    func executionSummary(for session: RoutineSession) -> String? {
        let records = executionRecords.filter { $0.sessionID == session.id }
        guard !records.isEmpty else { return nil }
        let done = records.filter { $0.outcome == .completed || $0.outcome == .budgetFinished }.count
        let unavailable = records.filter { $0.outcome == .unavailable }.count
        let uncertain = records.filter { $0.outcome == .uncertain }.count
        let skipped = records.filter { $0.outcome == .skipped || $0.outcome == .interrupted }.count
        let contents = records.reduce(0) { $0 + $1.observedContents }
        let likes = records.reduce(0) { $0 + $1.confirmedLikes }
        let timedIDs = Set(session.routine.steps.filter { $0.automation == .timedMoment }.map(\.id))
        let timed = records.filter { timedIDs.contains($0.stepID) && $0.outcome == .budgetFinished }.count
        let verified = done - timed
        let confirmedWithoutPresentation = records.filter {
            $0.confirmedExternalEffect == true && $0.outcome != .completed && $0.outcome != .budgetFinished
        }.count
        var parts: [String] = []
        if timed > 0 { parts.append(AppLanguage.isFrench ? "Moments chronométrés terminés : \(timed)." : "Timed moments finished: \(timed).") }
        if verified > 0 { parts.append(AppLanguage.isFrench ? "Opérations vérifiées : \(verified)." : "Verified operations: \(verified).") }
        if confirmedWithoutPresentation > 0 {
            parts.append(AppLanguage.isFrench
                ? "Actions confirmées par le service, restitution incomplète : \(confirmedWithoutPresentation)."
                : "Service-confirmed actions with incomplete presentation: \(confirmedWithoutPresentation).")
        }
        if skipped > 0 { parts.append(AppLanguage.isFrench ? "Moments passés : \(skipped)." : "Moments passed: \(skipped).") }
        if unavailable > 0 { parts.append(AppLanguage.isFrench ? "Indisponibles : \(unavailable)." : "Unavailable: \(unavailable).") }
        if uncertain > 0 { parts.append(AppLanguage.isFrench ? "Résultats à vérifier : \(uncertain)." : "Results to check: \(uncertain).") }
        if session.routine.steps.contains(where: { $0.webBehavior != nil }) {
            parts.append(AppLanguage.isFrench ? "Navigateur : \(contents) contenus observés, \(likes) likes confirmés." : "Browser: \(contents) contents observed, \(likes) likes confirmed.")
        }
        return parts.joined(separator: " ")
    }
    var currentExecutionRecord: RoutineExecutionRecord? {
        guard let session, let step = currentStep else { return nil }
        return executionRecords.last { $0.sessionID == session.id && $0.stepID == step.id }
    }

    @discardableResult
    func recordExecution(_ outcome: RoutineExecutionRecord.Outcome, observed: Int? = nil, likes: Int? = nil,
                         confirmedExternalEffect: Bool? = nil, webContentProgress: WebMorningContentProgress? = nil) -> Bool {
        guard !privacyBlocksWork, let session, let step = currentStep else { return false }
        let previous = executionRecords
        let old = currentExecutionRecord
        let record = RoutineExecutionRecord(sessionID: session.id, stepID: step.id, outcome: outcome,
            observedContents: max(observed ?? 0, old?.observedContents ?? 0), confirmedLikes: max(likes ?? 0, old?.confirmedLikes ?? 0),
            confirmedExternalEffect: confirmedExternalEffect ?? old?.confirmedExternalEffect,
            webContentProgress: webContentProgress ?? old?.webContentProgress)
        executionRecords.removeAll { $0.sessionID == session.id && $0.stepID == step.id }
        executionRecords.append(record)
        executionRecords = Array(executionRecords.suffix(256))
        guard persist() else { executionRecords = previous; return false }
        return true
    }

    func finishExecutionIfNeeded(skipping: Bool) {
        guard currentExecutionRecord?.outcome == .running || currentExecutionRecord == nil else { return }
        // An explicit Next ends the allotted moment; it does not certify a provider action.
        recordExecution(.skipped)
    }

    func completeAutomatedStep(sessionID: UUID, stepID: UUID) {
        guard !privacyBlocksWork, session?.id == sessionID, currentStep?.id == stepID,
              session?.status == .running else { return }
        guard recordExecution(.completed) else { pause(); return }
        advance(commandID: stepID)
    }

    func mayApproveExecution(in routine: RoutineVersion) -> Bool {
        for step in routine.steps {
            if case let .connectedAPI(service, _, tool, arguments) = step.target {
                guard !ConnectedRoutineActionPolicy.requiresSpokenMailSend(service: service, tool: tool) else {
                    notice = ConnectedRoutineActionPolicy.spokenMailSendExplanation; return false
                }
                do { _ = try ConnectedActionReview.summary(argumentsJSON: arguments) }
                catch { notice = error.moreDescription; return false }
            }
        }
        return true
    }

    var webExecutionPlan: WebMorningExecutionPlan? {
        guard automatic, let session, session.routine.isApproved,
              let step = session.currentStep, let behavior = step.webBehavior,
              case .inAppWeb = step.target else { return nil }
        return WebMorningExecutionPlan(sessionID: session.id, stepID: step.id,
            behavior: behavior, likesAllowed: step.webLikesAllowed == true,
            initialObservedContentCount: currentExecutionRecord?.observedContents ?? 0,
            initialConfirmedLikeCount: currentExecutionRecord?.confirmedLikes ?? 0,
            initialContentProgress: currentExecutionRecord?.webContentProgress)
    }

    func receiveWebExecution(_ event: WebMorningExecutionEvent) {
        guard !privacyBlocksWork, session?.id == event.sessionID, currentStep?.id == event.stepID,
              sessionActive else { return }
        let previousState = webExecutionEvent?.state
        webExecutionEvent = event
        var outcome: RoutineExecutionRecord.Outcome
        switch event.state {
        case .running, .waitingForPage: outcome = .running
        case .paused, .cancelled: outcome = .interrupted
        case .needsSignIn, .needsChoice, .unavailable: outcome = .unavailable
        case .uncertainAction, .performingAction: outcome = .uncertain
        case .finished: outcome = event.observedContentCount > 0 ? .budgetFinished : .unavailable
        }
        if currentExecutionRecord?.outcome == .uncertain,
           [.paused, .cancelled, .waitingForPage, .needsSignIn, .needsChoice, .unavailable].contains(event.state) { outcome = .uncertain }
        guard recordExecution(outcome, observed: event.observedContentCount, likes: event.confirmedLikeCount,
                              webContentProgress: event.contentProgress) else { pause(); return }
        if !event.spokenText.isEmpty, readAloud, session?.status == .running {
            executionSpeechTask?.cancel()
            executionSpeechTask = Task { [weak self] in
                guard let self else { return }
                try? await speech.speakAndWait(event.spokenText.joined(separator: ". "))
            }
        }
        if previousState != event.state, session?.status == .running, readAloud {
            let explanation: String?
            switch event.state {
            case .needsChoice:
                explanation = (AppLanguage.isFrench ? "Cette page attend votre choix. Votre matin est en pause. Faites votre choix dans la page. " : "This page needs your choice. Your morning is paused. Make your choice on the page. ") + nextMomentRecoveryInstruction
            case .needsSignIn:
                explanation = (AppLanguage.isFrench ? "Ce compte demande une connexion. Connectez-vous dans MORE. " : "This account needs a sign-in. Sign in in MORE. ") + nextMomentRecoveryInstruction
            case .unavailable:
                explanation = (AppLanguage.isFrench ? "Je ne peux pas parcourir ce contenu. " : "I can’t browse this content. ") + nextMomentRecoveryInstruction
            case .uncertainAction:
                explanation = (AppLanguage.isFrench ? "Ce like n’est pas confirmé. Je m’arrête pour éviter de le répéter. " : "This like is unconfirmed. I’ve stopped to avoid repeating it. ") + nextMomentRecoveryInstruction
            default: explanation = nil
            }
            if let explanation { connectedActionStatus = explanation; speech.speak(explanation) }
        }
        if event.state == .needsChoice, session?.status == .running {
            pause()
            if readAloud {
                speech.speak((AppLanguage.isFrench ? "Cette page attend votre choix. Votre matin est en pause. " : "This page needs your choice. Your morning is paused. ") + nextMomentRecoveryInstruction)
            }
            return
        }
        if event.state != .performingAction, let timer = activeStepTimer, timer.hasAlertedCurrentEnd {
            _ = finishAutomatedBudget(timer)
        }
    }

    private var nextMomentRecoveryInstruction: String {
        if canHearHandsFreeCommands {
            return AppLanguage.isFrench ? "Dites suivant pour poursuivre votre matin." : "Say next to continue your morning."
        }
        return AppLanguage.isFrench ? "Utilisez le bouton Suivant pour poursuivre votre matin." : "Use the Next button to continue your morning."
    }

    /// Time ends a budget. Only observed work may be recorded as performed.
    func finishAutomatedBudget(_ timer: StepTimer) -> Bool {
        guard session?.status == .running, currentStep?.id == timer.stepID,
              session?.id == timer.sessionID, let step = currentStep else { return false }
        if step.automation == .gmailInbox { return finishMailBudget(timer) }
        guard automatic else { return false }
        if step.automation == .timedMoment {
            guard recordExecution(.budgetFinished) else { pause(); return true }
            advance(commandID: step.id)
            return true
        }
        if step.target?.integrationRoute == .api {
            // A deadline cannot certify a remote effect. Wait for an active receipt
            // or presentation to settle, then preserve its actual recorded result.
            if connectedMoment.isInFlight { return true }
            let performed = currentExecutionRecord?.confirmedExternalEffect == true &&
                currentExecutionRecord?.outcome == .completed
            if performed { guard recordExecution(.budgetFinished) else { pause(); return true } }
            else if currentExecutionRecord?.outcome != .uncertain {
                guard recordExecution(.unavailable) else { pause(); return true }
            }
            advance(skipping: !performed, commandID: step.id)
            return true
        }
        guard step.webBehavior != nil else { return false }
        if webExecutionEvent?.sessionID == timer.sessionID, webExecutionEvent?.stepID == timer.stepID,
           webExecutionEvent?.state == .performingAction { return true }
        let record = currentExecutionRecord
        let performed = (record?.observedContents ?? 0) > 0 &&
            record?.outcome != .uncertain && record?.outcome != .unavailable && record?.outcome != .interrupted
        if performed { guard recordExecution(.budgetFinished) else { pause(); return true } }
        else if record?.outcome != .uncertain { guard recordExecution(.unavailable) else { pause(); return true } }
        advance(skipping: !performed, commandID: step.id)
        return true
    }
}
