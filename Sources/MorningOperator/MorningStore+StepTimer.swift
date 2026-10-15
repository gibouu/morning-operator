import Foundation
import MorningCore
import MorningApple
import UIKit

extension MorningStore {
    var activeStepTimer: StepTimer? {
        _ = stepTimerRevision
        guard sessionActive, let session, let step = currentStep, step.target != nil,
              let timer = StepTimerFile.load(), timer.belongs(to: session.id, stepID: step.id) else { return nil }
        return timer
    }

    /// A target's budget keeps running while its app is in front. Ordinary MORE
    /// narration keeps its existing pause-on-background behavior.
    var keepsTimerInBackground: Bool { session?.status == .running && activeStepTimer?.pausedAt == nil && activeStepTimer != nil }

    @discardableResult
    func beginTargetStep() -> Bool {
        guard let session, session.status == .running, let step = currentStep, let target = step.target else {
            endStepTimer(); return false
        }
        do {
            var timer = activeStepTimer ?? StepTimer(sessionID: session.id, stepID: step.id,
                minutes: step.durationMinutes, at: Date())
            timer.resume(at: Date())
            let shouldOpen = timer.openedAt == nil
            if shouldOpen { timer.markOpened(at: Date()) }
            try StepTimerFile.save(timer)
            stepTimerRevision += 1
            armStepTimer()
            if shouldOpen {
                switch target {
                case let .externalApp(app, detail):
                    guard let url = app.url(detail: detail), UIApplication.shared.canOpenURL(url) else {
                        notice = String(localized: "This app couldn't open. You can continue in MORE or choose Next.")
                        return true
                    }
                    UIApplication.shared.open(url) { [weak self] opened in
                        guard !opened else { return }
                        Task { @MainActor in
                            guard self?.session?.id == session.id, self?.currentStep?.id == step.id else { return }
                            self?.notice = String(localized: "This app couldn't open. You can continue in MORE or choose Next.")
                        }
                    }
                case let .inAppWeb(site): pendingWebTarget = site
                }
            }
            synchronizeMorningActivity()
            return true
        } catch {
            notice = String(localized: "The step timer couldn't be saved. Try again before leaving MORE.")
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
            self.notice = String(localized: "Time's up. Choose +2 min or Next.")
            let nextLabel = self.nextStepTimerLabel
            await StepTimerActivity.publish(timer: alertedTimer, timeIsUp: true)
            guard !Task.isCancelled, let current = self.activeStepTimer,
                  current.sessionID == timer.sessionID, current.stepID == timer.stepID,
                  current.endsAt == timer.endsAt, self.session?.status == .running else { return }
            // Background execution and audibility are system decisions. Ask for speech
            // only while MORE already has its foreground spoken-guidance path.
            if UIApplication.shared.applicationState == .active, self.readAloud, !self.voiceInputBlocksPlayback {
                self.speech.speak(String(localized: "Time's up. \(nextLabel)"))
            }
        }
    }

    var nextStepTimerLabel: String {
        guard let session, let next = StepNavigation.nextStep(in: session) else { return String(localized: "Finish") }
        return String(localized: "Next: \(next.target?.destination.displayName ?? "MORE")")
    }

    func extendStepTimer(expectedTimer: StepTimer? = nil) async {
        guard !privacyBlocksWork, let timer = activeStepTimer else { return }
        if let expectedTimer, !expectedTimer.belongs(to: timer.sessionID, stepID: timer.stepID) { return }
        _ = await StepTimerExtension.addTwoMinutes(sessionID: timer.sessionID, stepID: timer.stepID,
            expectedEnd: expectedTimer?.endsAt ?? timer.endsAt)
        stepTimerRevision += 1
        armStepTimer()
    }

    func pauseStepTimer() {
        stepTimerTask?.cancel(); stepTimerTask = nil
        if let timer = activeStepTimer {
            _ = StepTimerFile.update(sessionID: timer.sessionID, stepID: timer.stepID) { $0.pause(at: Date()) }
        }
        StepTimerAlert.cancel(); stepTimerRevision += 1
    }

    @discardableResult
    func endStepTimer() -> Bool {
        stepTimerTask?.cancel(); stepTimerTask = nil
        let retired = StepTimerFile.clear()
        StepTimerAlert.cancel()
        pendingWebTarget = nil
        stepTimerRevision += 1
        if !retired, !privacyBlocksWork {
            notice = String(localized: "The timer couldn't be stopped safely. Try again before leaving this moment.")
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
