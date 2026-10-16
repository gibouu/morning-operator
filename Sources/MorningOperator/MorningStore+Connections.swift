import Foundation
import MorningCore
import MorningApple

extension MorningStore {
    /// Rebuild presentation from retained facts; this never retries an operation.
    func refreshConnectedPresentationLanguage() {
        connectedMoment.invalidateSummaryForLanguageChange()
        guard !privacyBlocksWork, sessionActive, let session, let step = currentStep else { return }
        let context = MorningExecutionID(sessionID: session.id, routineVersionID: session.routine.id, stepID: step.id)
        if nativeMoment.context == context, nativeMoment.isActive, !nativeMoment.message.isEmpty {
            connectedActionStatus = nativeMoment.message; return
        }
        if slackReply.context == context, slackReply.isActive, !slackReply.message.isEmpty {
            connectedActionStatus = slackReply.message; return
        }
        if mailMorning.context == context, mailMorning.state != .idle, !mailMorning.message.isEmpty {
            connectedActionStatus = mailMorning.message; return
        }
        let matches = connectedMoment.executionID == context
        if currentExecutionRecord?.outcome == .uncertain || (matches && connectedMoment.phase == .uncertain) {
            connectedActionStatus = uncertainConnectedResultMessage; return
        }
        let paused = AppLanguage.isFrench ? " Votre matin est en pause. " : " Your morning is paused. "
        let incomplete = currentExecutionRecord?.outcome == .unavailable
            ? (AppLanguage.isFrench ? "La dernière lecture n’a pas pu se terminer. " : "The last reading could not finish. ") : ""
        switch step.target {
        case .googleCalendarDay:
            if let document = currentGoogleCalendarDay {
                connectedActionStatus = incomplete + document.summary() + paused + (AppLanguage.isFrench
                    ? "Utilisez Relire cette journée pour retrouver ces mêmes informations, ou Suivant."
                    : "Use Read this day again for the same information, or Next.")
            } else {
                connectedActionStatus = (AppLanguage.isFrench
                    ? "La lecture de ce calendrier a expiré ou n’est plus disponible. Utilisez Actualiser ce calendrier, Suivant ou Arrêter."
                    : "This calendar reading has expired or is unavailable. Use Refresh this calendar, Next or Stop.") + paused
            }
        case .calendlyDay:
            if let document = currentCalendlyDay {
                connectedActionStatus = incomplete + document.summary() + paused + (AppLanguage.isFrench
                    ? "Utilisez Relire ces rendez-vous pour retrouver ces mêmes informations, ou Suivant."
                    : "Use Read these bookings again for the same information, or Next.")
            } else {
                connectedActionStatus = (AppLanguage.isFrench
                    ? "La lecture de vos rendez-vous a expiré ou n’est plus disponible. Utilisez Actualiser mes rendez-vous, Suivant ou Arrêter."
                    : "This booking reading has expired or is unavailable. Use Refresh my bookings, Next or Stop.") + paused
            }
        case .outlookInbox:
            if let source = currentOutlookInbox {
                let summary = currentOutlookMessage?.summary() ?? source.summary()
                let expiredMessage = outlookMessageDocument != nil && currentOutlookMessage == nil
                    ? (AppLanguage.isFrench ? "Le message choisi a expiré. " : "The selected message has expired. ") : ""
                connectedActionStatus = incomplete + expiredMessage + summary + paused + (AppLanguage.isFrench
                    ? "Utilisez Relire cette lecture pour retrouver les informations disponibles, ou Suivant."
                    : "Use Read this again for the available information, or Next.")
            } else {
                connectedActionStatus = (AppLanguage.isFrench
                    ? "Cette lecture Outlook a expiré ou n’est plus disponible. Utilisez Actualiser Outlook, Suivant ou Arrêter."
                    : "This Outlook reading has expired or is unavailable. Use Refresh Outlook, Next or Stop.") + paused
            }
        case .connectedAPI:
            if (matches && connectedMoment.effectConfirmed) || currentExecutionRecord?.confirmedExternalEffect == true {
                connectedActionStatus = matches && connectedMoment.document != nil
                    ? (AppLanguage.isFrench
                        ? "Le service a confirmé l’action. Les informations reçues sont conservées. "
                        : "The service confirmed the action. The received information is kept. ") + (canHearHandsFreeCommands
                            ? (AppLanguage.isFrench ? "Dites répète pour les relire dans la langue choisie, ou suivant."
                                : "Say repeat to hear it in your chosen language, or next.")
                            : connectedNextInstruction) + paused
                    : clearedConnectedResultMessage
            } else {
                connectedActionStatus = (AppLanguage.isFrench
                    ? "La demande au service n’est pas terminée. Vérifiez la connexion avant de reprendre, ou choisissez Suivant."
                    : "The service request is unfinished. Check the connection before resuming, or choose Next.") + paused
            }
        default:
            if connectedActionStatus != nil {
                connectedActionStatus = incomplete + (AppLanguage.isFrench
                    ? "Votre matin est en pause. Vérifiez les informations de ce moment avant de reprendre, ou choisissez Suivant."
                    : "Your morning is paused. Review this moment’s information before resuming, or choose Next.")
            }
        }
    }

    @discardableResult
    func handleNativeConnectionURL(_ url: URL) -> Bool {
        guard nativeConnections.handle(url: url) else { return false }
        if let context = nativeStepContext, let outcome = nativeConnections.shortcutOutcomes[.custom],
           outcome.requestID == context.requestID, session?.id == context.sessionID,
           currentStep?.id == context.stepID, !privacyBlocksWork {
            connectedActionStatus = outcome.status == .returned
                ? AppLanguage.localized("Shortcut returned. \(outcome.text)")
                : AppLanguage.localized("The shortcut did not finish. Check its outcome before running it again.")
            nativeStepContext = nil
        }
        return true
    }
    @discardableResult
    func addAPIAction(connection: ComposioConnection, tool: ComposioTool, argumentsJSON: String) -> Bool {
        guard !privacyBlocksWork, !sessionActive, !busy else { return false }
        guard !ConnectedRoutineActionPolicy.requiresSpokenMailSend(service: connection.service, tool: tool.slug) else {
            notice = ConnectedRoutineActionPolicy.spokenMailSendExplanation
            return false
        }
        let target = RoutineStepTarget.connectedAPI(service: connection.service, connectionID: connection.id,
            tool: tool.slug, argumentsJSON: argumentsJSON)
        let detail: String
        do {
            try target.validateIntegration()
            let review = try ConnectedActionReview.summary(argumentsJSON: argumentsJSON, schema: tool.inputSchema,
                account: connection.accountLabel ?? connection.name)
            let fixedValues = AppLanguage.isFrench
                ? "Les mêmes valeurs, y compris les dates affichées, seront utilisées à chaque matin. Modifiez ce moment pour les changer."
                : "The same values, including the dates shown, will be used each morning. Edit this moment to change them."
            detail = review + "\n\n" + fixedValues
            guard detail.count <= ConnectedActionReview.maximumSummaryCharacters else { throw ConnectedActionReviewError.tooLarge }
        } catch { notice = error.moreDescription; return false }
        let step = RoutineStep(title: tool.name, detail: detail, durationMinutes: 1, target: target)
        if addConnectedStep(step) {
            notice = AppLanguage.localized("Action added to your draft. Review and approve the routine before starting.")
            return true
        }
        return false
    }

    func runConnectedAction(service: String, connectionID: String, tool: String, argumentsJSON: String,
                            sessionID: UUID, stepID: UUID) {
        guard !privacyBlocksWork, let session, session.id == sessionID, session.status == .running,
              session.routine.isApproved, let step = currentStep, step.id == stepID,
              step.target == .connectedAPI(service: service, connectionID: connectionID, tool: tool, argumentsJSON: argumentsJSON) else { return }
        let context = MorningExecutionID(sessionID: sessionID, routineVersionID: session.routine.id, stepID: stepID)
        #if DEBUG
        if usesSyntheticSlack, service == "slack" { presentSyntheticSlack(context: context); return }
        #endif
        guard !ConnectedRoutineActionPolicy.requiresSpokenMailSend(service: service, tool: tool) else {
            connectedActionStatus = ConnectedRoutineActionPolicy.spokenMailSendExplanation
            notice = connectedActionStatus
            recordExecution(.unavailable)
            if readAloud { speech.speak(ConnectedRoutineActionPolicy.spokenMailSendExplanation) }
            return
        }
        guard let attempt = connectedMoment.begin(executionID: context, record: currentExecutionRecord) else {
            if connectedAPITask == nil { resumeConnectedMoment(context: context) }
            return
        }
        connectedAPITask?.cancel()
        let generation = dataGeneration, privacyGeneration = localPrivacyGeneration
        let requestID = IntegrationRequestID.make(sessionID: sessionID, stepID: stepID)
        connectedActionStatus = AppLanguage.localized("Requesting the connected service…")
        connectedAPITask = Task { @MainActor [weak self] in
            guard let self else { return }
            defer {
                if connectedMoment.matches(attempt, executionID: context) {
                    connectedAPITask = nil
                }
            }
            do {
                let connections = try await composio.connections()
                try Task.checkCancellation()
                guard connectedActionIsCurrent(context, generation: generation), self.session?.status == .running,
                      connectedMoment.matches(attempt, executionID: context) else { return }
                guard connections.contains(where: { $0.id == connectionID && $0.service == service && $0.isActive }) else {
                    connectedMoment.fail(attempt, executionID: context)
                    finishConnectedFailure((AppLanguage.isFrench
                        ? "Ce compte doit être reconnecté dans Apps et comptes."
                        : "Reconnect this account in Apps & accounts.") + " " + connectedNextInstruction, outcome: .unavailable)
                    return
                }
                let arguments = try ComposioJSONValue.parseObject(argumentsJSON)
                // Save the no-replay boundary before a provider effect can occur.
                guard recordExecution(.uncertain), connectedMoment.markDispatched(attempt, executionID: context) else {
                    connectedMoment.fail(attempt, executionID: context); pause(); return
                }
                let result = try await composio.execute(tool: tool, arguments: arguments,
                    connectionID: connectionID, requestID: requestID)
                guard connectedActionIsCurrent(context, generation: generation), localPrivacyGeneration == privacyGeneration else { return }
                if result.successful {
                    let receipt = connectedMoment.receive(attempt, executionID: context, service: service,
                        result: result.data, resultAvailable: result.resultAvailable != false,
                        origin: ConnectedMomentOrigin(tool: tool, connectionID: connectionID, arguments: arguments, privacyGeneration: privacyGeneration))
                    guard receipt != .stale else { return }
                    guard recordExecution(.running, confirmedExternalEffect: true) else { pause(); return }
                    guard receipt == .sourceAvailable else {
                        finishConnectedFailure(receipt == .tooLarge ? ConnectedResultError.tooLarge.moreDescription : clearedConnectedResultMessage,
                            outcome: .unavailable)
                        return
                    }
                    // A receipt remains confirmed if a pause cancelled the narration.
                    guard !Task.isCancelled, self.session?.status == .running else { return }
                    await presentConnectedMoment(context: context, generation: generation, attempt: attempt)
                } else {
                    connectedMoment.fail(attempt, executionID: context)
                    finishConnectedFailure(uncertainConnectedResultMessage, outcome: .uncertain)
                }
            } catch {
                guard connectedActionIsCurrent(context, generation: generation),
                      connectedMoment.matches(attempt, executionID: context) else { return }
                connectedMoment.fail(attempt, executionID: context)
                guard !Task.isCancelled else { return }
                finishConnectedFailure(connectedMoment.wasDispatched ? uncertainConnectedResultMessage :
                    (AppLanguage.isFrench ? "Le service est inaccessible. Vérifiez la connexion. " : "The service is unavailable. Check the connection. ") + connectedNextInstruction,
                    outcome: connectedMoment.wasDispatched ? .uncertain : .unavailable)
            }
        }
    }

    /// Explicitly refresh only the approved Slack read. This cannot publish or change its destination.
    func refreshSlackMessages() {
        guard let context = currentSlackContext, let step = currentStep,
              case let .connectedAPI(_, connectionID, tool, json) = step.target,
              ![.sending, .uncertain].contains(slackReply.phase) else { return }
        clearSlackReply()
        if session?.status == .running { pause() }
        connectedAPITask?.cancel()
        connectedMoment.clear()
        #if DEBUG
        if usesSyntheticSlack { presentSyntheticSlack(context: context); return }
        #endif
        guard let attempt = connectedMoment.begin(executionID: context, record: nil) else { return }
        let generation = dataGeneration, privacyGeneration = localPrivacyGeneration
        connectedActionStatus = AppLanguage.isFrench ? "Actualisation des messages Slack…" : "Refreshing Slack messages…"
        connectedAPITask = Task { @MainActor [weak self] in
            guard let self else { return }
            defer { if connectedMoment.matches(attempt, executionID: context) { connectedAPITask = nil } }
            do {
                let connections = try await composio.connections()
                guard !Task.isCancelled, connectedActionIsCurrent(context, generation: generation),
                      connections.contains(where: { $0.id == connectionID && $0.service == "slack" && $0.isActive }) else { throw SlackReplyError.accountChanged }
                let arguments = try ComposioJSONValue.parseObject(json)
                let result = try await composio.readSlack(tool: tool, arguments: arguments, connectionID: connectionID)
                try Task.checkCancellation()
                guard connectedActionIsCurrent(context, generation: generation), localPrivacyGeneration == privacyGeneration,
                      connectedMoment.markDispatched(attempt, executionID: context),
                      result.successful, result.resultAvailable != false,
                      connectedMoment.receive(attempt, executionID: context, service: "slack", result: result.data,
                        origin: ConnectedMomentOrigin(tool: tool, connectionID: connectionID, arguments: arguments, privacyGeneration: privacyGeneration)) == .sourceAvailable else { throw SlackReplyError.unavailable }
                await presentConnectedMoment(context: context, generation: generation, attempt: attempt)
            } catch {
                guard !Task.isCancelled, connectedActionIsCurrent(context, generation: generation), connectedMoment.matches(attempt, executionID: context) else { return }
                connectedMoment.fail(attempt, executionID: context)
                connectedActionStatus = (AppLanguage.isFrench ? "La lecture Slack n’a pas pu être actualisée. Aucun message n’a été publié. Réessayez. "
                    : "Slack messages could not be refreshed. Nothing was posted. Try again. ") + connectedNextInstruction
                recordExecution(.unavailable)
                if readAloud, let connectedActionStatus { speech.speak(connectedActionStatus) }
            }
        }
    }

    /// Repeat is local presentation, including while paused. It never dispatches an API action.
    @discardableResult
    func repeatConnectedMoment() -> Bool {
        guard let session, let step = currentStep, case .connectedAPI = step.target else { return false }
        let context = MorningExecutionID(sessionID: session.id, routineVersionID: session.routine.id, stepID: step.id)
        if let summary = connectedMoment.summary(for: context) { speech.speak(summary) }
        else if connectedMoment.executionID == context, connectedMoment.document != nil, connectedAPITask == nil {
            resumeConnectedMoment(context: context)
        } else {
            let message = (connectedMoment.executionID == context && connectedMoment.effectConfirmed) || currentExecutionRecord?.confirmedExternalEffect == true
                ? clearedConnectedResultMessage
                : connectedActionStatus ?? ((AppLanguage.isFrench ? "Le résultat n’est pas encore disponible. " : "The result is not available yet. ") + connectedNextInstruction)
            speech.speak(message)
        }
        return true
    }

    private func resumeConnectedMoment(context: MorningExecutionID) {
        if let summary = connectedMoment.summary(for: context) {
            guard let attempt = connectedMoment.beginPresentation(for: context) else { return }
            let generation = dataGeneration
            connectedAPITask = Task { @MainActor [weak self] in
                guard let self else { return }
                defer { if connectedMoment.matches(attempt, executionID: context) { connectedAPITask = nil } }
                connectedActionStatus = summary
                do { if readAloud { try await speech.speakAndWait(summary) } }
                catch {
                    guard !Task.isCancelled, connectedActionIsCurrent(context, generation: generation),
                          connectedMoment.matches(attempt, executionID: context) else { return }
                    connectedMoment.fail(attempt, executionID: context)
                    finishConnectedFailure((AppLanguage.isFrench
                        ? "Le résultat est confirmé, mais je n’ai pas pu finir sa lecture. "
                        : "The result is confirmed, but I could not finish reading it. ") + (canHearHandsFreeCommands
                            ? (AppLanguage.isFrench ? "Dites répète ou suivant." : "Say repeat or next.")
                            : connectedNextInstruction), outcome: .unavailable)
                    return
                }
                guard !Task.isCancelled, connectedActionIsCurrent(context, generation: generation),
                      connectedMoment.matches(attempt, executionID: context) else { return }
                connectedMoment.finishPresentation(attempt, executionID: context)
                settleConnectedBudgetIfExpired()
            }
            return
        }
        guard let attempt = connectedMoment.beginPresentation(for: context) else {
            finishConnectedFailure(connectedMoment.effectConfirmed ? clearedConnectedResultMessage : uncertainConnectedResultMessage,
                outcome: connectedMoment.effectConfirmed ? .unavailable : .uncertain)
            return
        }
        let generation = dataGeneration
        connectedAPITask = Task { @MainActor [weak self] in
            guard let self else { return }
            defer { if connectedMoment.matches(attempt, executionID: context) { connectedAPITask = nil } }
            await presentConnectedMoment(context: context, generation: generation, attempt: attempt)
        }
    }

    private func presentConnectedMoment(context: MorningExecutionID, generation: UUID, attempt: UUID) async {
        guard let document = connectedMoment.document, document.executionID == context else { return }
        connectedMoment.markPresenting(attempt, executionID: context)
        do {
            let narrator: ConnectedResultNarrator
            #if DEBUG
            if SlackSetupUITestFixture.integratedJourneyRequested {
                narrator = ConnectedResultNarrator(model: .localOnly(directory: LocalDataControl.defaultDirectory))
            } else { narrator = ConnectedResultNarrator() }
            #else
            narrator = ConnectedResultNarrator()
            #endif
            let summary = try await narrator.summarize(document.result, service: document.service)
            guard !Task.isCancelled, connectedActionIsCurrent(context, generation: generation),
                  connectedMoment.present(summary, token: attempt, executionID: context) else { return }
            connectedMoment.markPresenting(attempt, executionID: context)
            connectedActionStatus = summary
            guard recordExecution(.completed, confirmedExternalEffect: true) else { pause(); return }
            if readAloud { try await speech.speakAndWait(summary) }
            guard !Task.isCancelled, connectedActionIsCurrent(context, generation: generation),
                  connectedMoment.matches(attempt, executionID: context) else { return }
            connectedMoment.finishPresentation(attempt, executionID: context)
            settleConnectedBudgetIfExpired()
        } catch {
            guard !Task.isCancelled, connectedActionIsCurrent(context, generation: generation),
                  connectedMoment.matches(attempt, executionID: context) else { return }
            connectedMoment.fail(attempt, executionID: context)
            finishConnectedFailure(ConnectedResultError.modelUnavailable.moreDescription + " " + connectedNextInstruction, outcome: .unavailable)
        }
    }

    private func connectedActionIsCurrent(_ context: MorningExecutionID, generation: UUID) -> Bool {
        !privacyBlocksWork && dataGeneration == generation && session?.id == context.sessionID &&
            session?.routine.id == context.routineVersionID && currentStep?.id == context.stepID && sessionActive
    }

    private func finishConnectedFailure(_ message: String, outcome: RoutineExecutionRecord.Outcome) {
        connectedActionStatus = message
        guard recordExecution(outcome) else { pause(); return }
        if readAloud, session?.status == .running { speech.speak(message) }
        settleConnectedBudgetIfExpired()
    }

    private func settleConnectedBudgetIfExpired() {
        if let timer = activeStepTimer, timer.hasAlertedCurrentEnd { _ = finishAutomatedBudget(timer) }
    }

    private var connectedNextInstruction: String {
        MorningInteractionGuidance.next(canHearCommands: canHearHandsFreeCommands, french: AppLanguage.isFrench)
    }

    private var uncertainConnectedResultMessage: String {
        (AppLanguage.isFrench
            ? "L’action n’est pas confirmée. Je ne la répéterai pas. Vérifiez son résultat dans le compte connecté. "
            : "The action is unconfirmed. I will not repeat it. Check its result in the connected account. ") + connectedNextInstruction
    }

    private var clearedConnectedResultMessage: String {
        (AppLanguage.isFrench
            ? "Le service a confirmé l’action. Son contenu n’est plus disponible dans ce moment et je ne relancerai pas l’action pour le relire. "
            : "The service confirmed the action. Its content is no longer available in this moment, and I will not run it again to reread it. ") + connectedNextInstruction
    }
}
