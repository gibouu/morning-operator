import Foundation
import MorningCore
import MorningApple
import UIKit

extension MorningStore {
    private var externalAppOpenFailureNotice: String {
        AppLanguage.localized("This app couldn't open. You can continue in MORE or choose Next.")
    }

    var activeStepTimer: StepTimer? {
        _ = stepTimerRevision
        guard sessionActive, let session, let step = currentStep, step.target != nil || step.automation == .timedMoment || step.automation == .gmailInbox,
              let timer = StepTimerFile.load(), timer.belongs(to: session.id, stepID: step.id) else { return nil }
        return timer
    }

    /// A target's budget keeps running while its app is in front. Ordinary MORE
    /// narration keeps its existing pause-on-background behavior.
    var keepsTimerInBackground: Bool {
        if currentStep?.webBehavior != nil || currentStep?.automation == .gmailInbox { return false }
        if currentStep?.target?.integrationRoute == .api { return false }
        return session?.status == .running && activeStepTimer?.pausedAt == nil && activeStepTimer != nil
    }

    /// The scene captures this only on an actual trip to the background.
    var externalAppDeparture: StepTimer? {
        guard automatic, !privacyBlocksWork, notice != externalAppOpenFailureNotice, let timer = activeStepTimer,
              timer.openedAt != nil, timer.pausedAt == nil,
              StepNavigation.mayAdvanceAfterExternalAppReturn(session: session,
                sessionID: timer.sessionID, stepID: timer.stepID) else { return nil }
        return timer
    }

    func returnedFromExternalApp(_ departure: StepTimer) {
        guard automatic, !privacyBlocksWork, notice != externalAppOpenFailureNotice, let timer = activeStepTimer,
              departure.openedAt != nil, timer.openedAt == departure.openedAt, timer.pausedAt == nil,
              StepNavigation.mayAdvanceAfterExternalAppReturn(session: session,
                sessionID: departure.sessionID, stepID: departure.stepID) else { return }
        nextTargetStep(sessionID: departure.sessionID, stepID: departure.stepID)
    }

    @discardableResult
    func beginTargetStep() -> Bool {
        guard let session, session.status == .running, let step = currentStep,
              step.target != nil || step.automation == .timedMoment || step.automation == .gmailInbox else {
            endStepTimer(); return false
        }
        do {
            try step.target?.validateIntegration()
            let target = step.target?.routineExecutionTarget
            var timer = activeStepTimer ?? StepTimer(sessionID: session.id, stepID: step.id,
                minutes: step.durationMinutes, at: Date())
            #if DEBUG
            let isManualWeb: Bool = {
                if case .inAppWeb = target { return webExecutionPlan == nil }
                return false
            }()
            if activeStepTimer == nil, ProcessInfo.processInfo.arguments.contains("--ui-testing"),
               ProcessInfo.processInfo.arguments.contains("--ui-testing-short-budgets"),
               step.automation == .timedMoment || isManualWeb {
                timer = StepTimer(sessionID: session.id, stepID: step.id, minutes: 1, at: Date().addingTimeInterval(-55))
            }
            #endif
            timer.resume(at: Date())
            let shouldOpen = timer.openedAt == nil
            if shouldOpen { timer.markOpened(at: Date()) }
            try StepTimerFile.save(timer)
            stepTimerRevision += 1
            armStepTimer()
            if currentExecutionRecord == nil { guard recordExecution(.running) else { pause(); return true } }
            if !shouldOpen, webExecutionPlan != nil, case let .inAppWeb(url) = target {
                pendingWebTarget = url
            }
            if !shouldOpen, case let .connectedAPI(service, connectionID, tool, arguments) = step.target {
                runConnectedAction(service: service, connectionID: connectionID, tool: tool,
                    argumentsJSON: arguments, sessionID: session.id, stepID: step.id)
            }
            if !shouldOpen, case let .googleCalendarDay(target) = step.target {
                runGoogleCalendarDay(target, sessionID: session.id, stepID: step.id)
            }
            if !shouldOpen, case let .calendlyDay(target) = step.target {
                runCalendlyDay(target, sessionID: session.id, stepID: step.id)
            }
            if !shouldOpen, case let .outlookInbox(target) = step.target {
                runOutlookInbox(target, sessionID: session.id, stepID: step.id)
            }
            if shouldOpen {
                switch target {
                case let .externalApp(app, detail):
                    guard let url = app.url(detail: detail), UIApplication.shared.canOpenURL(url) else {
                        notice = externalAppOpenFailureNotice
                        return true
                    }
                    UIApplication.shared.open(url) { [weak self] opened in
                        guard !opened else { return }
                        Task { @MainActor in
                            guard self?.session?.id == session.id, self?.currentStep?.id == step.id else { return }
                            self?.notice = self?.externalAppOpenFailureNotice
                        }
                    }
                case let .inAppWeb(site): pendingWebTarget = site
                case let .shortcut(name, input):
                    let url = try nativeConnections.launchShortcut(name: name, input: input)
                    let requestID = nativeConnections.pendingShortcut?.id
                    if let requestID { nativeStepContext = (requestID, session.id, step.id) }
                    UIApplication.shared.open(url) { [weak self] opened in
                        guard !opened else { return }
                        Task { @MainActor in
                            guard let self, let requestID,
                                  self.nativeStepContext?.requestID == requestID,
                                  self.session?.id == session.id, self.currentStep?.id == step.id else { return }
                            self.nativeConnections.shortcutCouldNotOpen(requestID: requestID)
                            self.notice = AppLanguage.localized("Shortcuts couldn't open. Check the installed shortcut before trying again.")
                        }
                    }
                case let .connectedAPI(service, connectionID, tool, arguments):
                    runConnectedAction(service: service, connectionID: connectionID, tool: tool,
                        argumentsJSON: arguments, sessionID: session.id, stepID: step.id)
                case let .googleCalendarDay(target):
                    runGoogleCalendarDay(target, sessionID: session.id, stepID: step.id)
                case let .calendlyDay(target):
                    runCalendlyDay(target, sessionID: session.id, stepID: step.id)
                case let .outlookInbox(target):
                    runOutlookInbox(target, sessionID: session.id, stepID: step.id)
                case nil:
                    if step.automation != .gmailInbox, readAloud { speech.speak("\(step.title). \(step.detail)") }
                }
            }
            synchronizeMorningActivity()
            return true
        } catch {
            notice = AppLanguage.localized("This moment couldn't start: \(error.moreDescription)")
            pause()
            return true
        }
    }

    func armStepTimer() {
        stepTimerTask?.cancel()
        guard let timer = activeStepTimer, session?.status == .running else { return }
        StepTimerSignals.onExtended = { [weak self] timer in
            guard let self, self.session?.id == timer.sessionID, self.currentStep?.id == timer.stepID else { return }
            self.stepTimerRevision += 1
            self.armStepTimer()
            self.synchronizeMorningActivity()
        }
        Task { await StepTimerAlert.schedule(for: timer, nextLabel: nextStepTimerLabel) }
        stepTimerTask = Task { [weak self] in
            try? await Task.sleep(for: .seconds(max(0, timer.endsAt.timeIntervalSinceNow)))
            guard !Task.isCancelled, let self, let current = self.activeStepTimer,
                  current.endsAt == timer.endsAt, self.session?.status == .running else { return }
            let claimed = StepTimerFile.update(sessionID: timer.sessionID, stepID: timer.stepID) { $0.claimAlert(at: Date()) }
            guard let (alertedTimer, claimedAlert) = claimed, claimedAlert else { return }
            self.stepTimerRevision += 1
            if self.finishAutomatedBudget(alertedTimer) { return }
            if self.automatic, case .inAppWeb = self.currentStep?.target?.routineExecutionTarget, self.webExecutionPlan == nil {
                // A completed time allowance does not verify anything done on the page.
                guard self.recordExecution(.skipped) else { self.pause(); return }
                self.advance(commandID: timer.stepID)
                return
            }
            self.notice = AppLanguage.localized("Time's up. Choose +2 min or Next.")
            let nextLabel = self.nextStepTimerLabel
            await StepTimerActivity.publish(timer: alertedTimer, timeIsUp: true)
            guard !Task.isCancelled, let current = self.activeStepTimer,
                  current.sessionID == timer.sessionID, current.stepID == timer.stepID,
                  current.endsAt == timer.endsAt, self.session?.status == .running else { return }
            // Background execution and audibility are system decisions. Ask for speech
            // only while MORE already has its foreground spoken-guidance path.
            if UIApplication.shared.applicationState == .active, self.readAloud, !self.voiceInputBlocksPlayback {
                self.speech.speak(AppLanguage.localized("Time's up. \(nextLabel)"))
            }
        }
    }

    var nextStepTimerLabel: String {
        guard let session, let next = StepNavigation.nextStep(in: session) else { return AppLanguage.localized("Finish") }
        return AppLanguage.localized("Next: \(next.target?.destination.displayName ?? "MORE")")
    }

    func extendStepTimer(expectedTimer: StepTimer? = nil) async {
        guard !privacyBlocksWork, let timer = activeStepTimer else { return }
        if let expectedTimer, !expectedTimer.belongs(to: timer.sessionID, stepID: timer.stepID) { return }
        let generation = dataGeneration
        let pauseRevision = handsFreePauseRevision
        let context = session.flatMap { session in currentStep.map {
            MorningExecutionID(sessionID: session.id, routineVersionID: session.routine.id, stepID: $0.id)
        } }
        let resumesMail = currentStep?.automation == .gmailInbox && session?.status == .paused &&
            (mailBudgetDeadlinePaused == context || (timer.hasAlertedCurrentEnd && timer.isExpired(at: Date()))) &&
            mailMorning.context == context && !nativeMoment.isActive
        let result = await StepTimerExtension.addTwoMinutes(sessionID: timer.sessionID, stepID: timer.stepID,
            expectedEnd: expectedTimer?.endsAt ?? timer.endsAt)
        guard dataGeneration == generation, !privacyBlocksWork,
              session?.id == timer.sessionID, currentStep?.id == timer.stepID else { return }
        stepTimerRevision += 1
        if resumesMail, handsFreePauseRevision == pauseRevision, case .extended? = result, let context {
            resumeForNext()
            guard resumeMailBudget(context: context) else { return }
            mailBudgetDeadlinePaused = nil
            connectedActionStatus = mailMorning.message
        }
        armStepTimer()
    }

    func pauseStepTimer() {
        if connectedAPITask != nil {
            connectedAPITask?.cancel(); connectedAPITask = nil
            connectedMoment.pause()
            // A confirmed result survives an interruption; pausing must not replace it
            // with an uncertainty message or trigger the provider effect on resume.
            if !connectedMoment.effectConfirmed, connectedMoment.wasDispatched {
                connectedActionStatus = AppLanguage.isFrench
                    ? "L’action n’est pas confirmée. Vérifiez son résultat dans le compte connecté, ou dites suivant."
                    : "The action is unconfirmed. Check its result in the connected account, or say next."
            }
        }
        stepTimerTask?.cancel(); stepTimerTask = nil
        if let timer = activeStepTimer {
            _ = StepTimerFile.update(sessionID: timer.sessionID, stepID: timer.stepID) { $0.pause(at: Date()) }
        }
        StepTimerAlert.cancel(); stepTimerRevision += 1
    }

    @discardableResult
    func endStepTimer() -> Bool {
        connectedAPITask?.cancel(); connectedAPITask = nil
        connectedActionStatus = nil
        nativeStepContext = nil
        nativeConnections.cancelPendingWork()
        stepTimerTask?.cancel(); stepTimerTask = nil
        let retired = StepTimerFile.clear()
        if retired {
            connectedMoment.clear(); routineWebMoment.clear(); clearNativeMoment(); clearSlackReply(); clearGoogleCalendarDay(); clearCalendlyDay(); clearOutlookInbox()
            mailBudgetWork = [:]; mailBudgetDeadlinePaused = nil
        }
        StepTimerAlert.cancel()
        pendingWebTarget = nil
        stepTimerRevision += 1
        if !retired, !privacyBlocksWork {
            notice = AppLanguage.localized("The timer couldn't be stopped safely. Try again before leaving this moment.")
        }
        return retired
    }

    func nextTargetStep(sessionID: UUID?, stepID: UUID?, skipping: Bool = false) {
        guard !privacyBlocksWork else { return }
        guard case let .advance(resumeFirst, _) = StepNavigation.decide(session: session, sessionID: sessionID, stepID: stepID) else { return }
        // Resume the session without dispatching its old target before advancing.
        if resumeFirst { resumeForNext() }
        guard session?.status == .running else { return }
        advance(skipping: skipping)
    }
}
