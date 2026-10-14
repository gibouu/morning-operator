import Foundation
import Testing
@testable import MorningCore

// Fixtures only: synthetic messages, no device, no transport, no model and no external adapter.
// The same questions as "Phone loop message correlation", asked while a run recovers: after a
// duplicated command, a timeout, a reconnect, a manual intervention, an action sent again and a
// pause for an external effect. One gate lives through each run and every command comes from the
// real session. A recovery must leave the genuine messages usable and the stale ones without effect.
@Suite("Phone loop message correlation during recovery")
struct PhoneLoopRecoveryCorrelationTests {
    private let app = "com.example.synthetic"
    private let otherApp = "com.example.synthetic.other"
    private let home = PhoneScreenState(foregroundBundleID: "com.apple.springboard", elements: [])
    private struct UnexpectedDirective: Error {}

    private func session(steps: Int = 1, looks: Int = 2) throws -> PhoneLoopSession {
        let policy = try PhoneLoopPolicy(
            allowedBundleIDs: [app, otherApp], navigation: [:], tabLabels: [], allowsListScroll: false,
            maxEvidenceAgeSeconds: 15, commandTimeoutSeconds: 5, reconnectWindowSeconds: 30,
            maxExtraLooksPerStep: looks, maxActionResendsPerStep: 1, maxReconnects: 2,
            maxSteps: steps, maxExternalEffectWaitSeconds: 30)
        return try PhoneLoopSession(policy: policy, mode: .tetheredController,
                                    startedAt: Date(timeIntervalSince1970: 0))
    }

    private func command(_ directive: PhoneLoopDirective) throws -> PhoneCommandMessage {
        guard case .send(let value) = directive else { throw UnexpectedDirective() }
        return try JSONDecoder().decode(PhoneCommandMessage.self, from: JSONEncoder().encode(value))
    }

    private func answer(_ command: PhoneCommandMessage, id: UUID = UUID(), uptime: Double,
                        screen: PhoneScreenState? = nil, refusal: PhoneRunnerRefusal? = nil,
                        step: UUID? = nil) throws -> PhoneObservationMessage {
        let value = try PhoneObservationMessage(
            runID: command.runID, stepID: step ?? command.stepID, sequence: command.sequence,
            observationID: id,
            freshness: PhoneEvidenceFreshness(clockID: "synthetic-recovery-runner",
                capturedUptimeSeconds: uptime, capturedAtWallClock: Date(timeIntervalSince1970: 0),
                validForSeconds: 15), screen: screen ?? home, refusal: refusal)
        return try JSONDecoder().decode(PhoneObservationMessage.self, from: JSONEncoder().encode(value))
    }

    private func proposal(_ observation: PhoneObservationMessage, app: String? = nil,
                          effect: PhoneExternalEffectReference? = nil) -> PhoneActionProposal {
        PhoneActionProposal(runID: observation.runID, stepID: observation.stepID,
            observationID: observation.observationID,
            action: effect.map { .externalEffect($0) } ?? .readOnly(.openApp(bundleID: app ?? self.app)))
    }

    @Test
    func eitherAnswerToADuplicatedObserveSupportsTheOneAction() async throws {
        // Which of the two answers reaches the controller first is the transport's doing.
        for refusalArrivesFirst in [true, false] {
            let session = try session(looks: 0)
            let observe = try command(await session.start(now: 0))
            var gate = PhoneCommandGate(runID: observe.runID)
            #expect(gate.admit(observe) == nil)
            let original = try answer(observe, uptime: 10)
            gate.sent(original)

            // The transport delivers the command a second time. The runner refuses it and, as an
            // observation may, reports the screen as it is with the reason.
            #expect(gate.admit(observe) == .replayedOrOutOfOrder)
            let withRefusal = try answer(observe, uptime: 11, refusal: .replayedOrOutOfOrder)
            gate.sent(withRefusal)
            #expect(gate.basisObservationIDs == [original.observationID, withRefusal.observationID])

            let (first, late) = refusalArrivesFirst ? (withRefusal, original) : (original, withRefusal)
            #expect(await session.receive(first, now: 0.1)
                    == .requestProposal(stepID: observe.stepID, observationID: first.observationID))
            #expect(await session.receive(late, now: 0.15) == .ignored(.notExpectedInThisPhase))
            let action = try command(await session.propose(proposal(first), now: 0.2))
            #expect(gate.admit(action) == nil, "The action is based on an answer this runner sent to that observe")
            // One observe, one action: the other answer is used up with it.
            #expect(gate.basisObservationIDs.isEmpty)
            let other = PhoneCommandMessage(runID: action.runID, stepID: action.stepID, sequence: action.sequence + 1,
                                            basedOnObservationID: late.observationID,
                                            timeoutSeconds: action.timeoutSeconds, command: action.command)
            #expect(gate.admit(other) == .notBasedOnLatestObservation)

            #expect(await session.receive(late, now: 0.3) == .ignored(.outOfSequence))
            let post = try answer(action, uptime: 12, screen: PhoneScreenState(foregroundBundleID: app, elements: []))
            gate.sent(post)
            #expect(await session.receive(post, now: 0.4) == .completed)
            #expect(await session.record.steps.map(\.outcome) == [.verified])
        }
    }

    @Test
    func timedOutObserveLeavesItsReplacementAndFreshProposalUsable() async throws {
        let session = try session()
        let first = try command(await session.start(now: 0))
        var gate = PhoneCommandGate(runID: first.runID)
        #expect(gate.admit(first) == nil)
        let delayed = try answer(first, uptime: 10)
        gate.sent(delayed)
        let replacement = try command(await session.checkDeadlines(now: 5))
        #expect(replacement.stepID == first.stepID)
        #expect(gate.admit(replacement) == nil)
        gate.sent(delayed)
        #expect(await session.receive(delayed, now: 5.1) == .ignored(.outOfSequence))
        #expect(await session.propose(proposal(delayed), now: 5.1) == .ignored(.notExpectedInThisPhase))
        #expect(gate.basisObservationIDs.isEmpty)
        let fresh = try answer(replacement, uptime: 11)
        gate.sent(fresh)
        #expect(await session.receive(fresh, now: 5.2)
                == .requestProposal(stepID: first.stepID, observationID: fresh.observationID))
        #expect(await session.propose(proposal(delayed), now: 5.3) == .ignored(.notDerivedFromLatestObservation))
        let action = try command(await session.propose(proposal(fresh), now: 5.4))
        #expect(gate.admit(action) == nil)
        let post = try answer(action, uptime: 12, screen: PhoneScreenState(foregroundBundleID: app, elements: []))
        gate.sent(post)
        #expect(await session.receive(post, now: 5.5) == .completed)
        #expect(await session.record.steps.first?.roundTrips.map(\.result) == [.timedOut, .answered, .answered])
    }

    @Test
    func timeoutAndReconnectBothPermitAReconciledActionResend() async throws {
        for reconnect in [false, true] {
            let session = try session()
            let first = try command(await session.start(now: 0))
            var gate = PhoneCommandGate(runID: first.runID)
            #expect(gate.admit(first) == nil)
            let seen = try answer(first, uptime: 10)
            gate.sent(seen)
            _ = await session.receive(seen, now: 0.1)
            let lostAction = try command(await session.propose(proposal(seen), now: 0.2))
            // The action is lost before admission. The session must reconcile, then resend
            // with a higher sequence and fresh basis, even though the gate skipped a sequence.
            let look: PhoneCommandMessage
            if reconnect {
                #expect(await session.transportDisconnected(now: 0.3) == .wait)
                look = try command(await session.transportReconnected(now: 1))
            } else {
                look = try command(await session.checkDeadlines(now: 5.3))
            }
            #expect(look.stepID == lostAction.stepID && look.sequence > lostAction.sequence)
            #expect(gate.admit(look) == nil)
            // The old action arrives after the recovery observe. It cannot execute on the old basis.
            #expect(gate.admit(lostAction) == .replayedOrOutOfOrder)
            let lateRefusal = try answer(lostAction, uptime: 11, refusal: .replayedOrOutOfOrder)
            gate.sent(lateRefusal)
            #expect(await session.receive(lateRefusal, now: 5.4) == .ignored(.outOfSequence))
            let reconciled = try answer(look, uptime: 12)
            gate.sent(reconciled)
            let resend = try command(await session.receive(reconciled, now: 5.5))
            #expect(resend.command == lostAction.command && resend.stepID == first.stepID)
            #expect(resend.basedOnObservationID == reconciled.observationID)
            #expect(gate.admit(resend) == nil)
            #expect(gate.admit(resend) == .replayedOrOutOfOrder)
            let post = try answer(resend, uptime: 13, screen: PhoneScreenState(foregroundBundleID: app, elements: []))
            gate.sent(post)
            #expect(await session.receive(post, now: 5.6) == .completed)
            #expect(await session.record.steps.first?.actionResendCount == 1)
            #expect(await session.record.reconnectCount == (reconnect ? 1 : 0))
        }
    }

    @Test
    func manualInterventionCanReconcileAnAdmittedButUnperformedAction() async throws {
        let session = try session()
        let first = try command(await session.start(now: 0))
        var gate = PhoneCommandGate(runID: first.runID)
        #expect(gate.admit(first) == nil)
        let seen = try answer(first, uptime: 10)
        gate.sent(seen)
        _ = await session.receive(seen, now: 0.1)
        let originalAction = try command(await session.propose(proposal(seen), now: 0.2))
        #expect(gate.admit(originalAction) == nil)
        // The runner could not open the app. Its refusal answer is delayed while the person
        // touches the phone; the controller abandons the command and requests fresh evidence.
        let delayed = try answer(originalAction, uptime: 11, refusal: .appNotForeground)
        gate.sent(delayed)
        let look = try command(await session.recordManualIntervention(now: 0.3))
        #expect(gate.admit(look) == nil)
        gate.sent(delayed)
        #expect(await session.receive(delayed, now: 0.4) == .ignored(.outOfSequence))
        let fresh = try answer(look, uptime: 12)
        gate.sent(fresh)
        let resend = try command(await session.receive(fresh, now: 0.5))
        #expect(resend.stepID == first.stepID && resend.basedOnObservationID == fresh.observationID)
        #expect(gate.admit(originalAction) == .replayedOrOutOfOrder)
        #expect(gate.admit(resend) == nil)
        let post = try answer(resend, uptime: 13, screen: PhoneScreenState(foregroundBundleID: app, elements: []))
        gate.sent(post)
        #expect(await session.receive(post, now: 0.6) == .completed)
        let record = await session.record
        #expect(record.authorship == .mixed)
        #expect(record.steps.first?.manualInterventionCount == 1)
        #expect(record.steps.first?.actionResendCount == 1)
        #expect(record.steps.first?.roundTrips.map(\.result) == [.answered, .abandoned, .answered, .answered])
    }

    @Test
    func reconnectAndManualInterventionDoNotConsumeAFreshExternalIntent() async throws {
        let session = try session(steps: 2)
        let first = try command(await session.start(now: 0))
        var gate = PhoneCommandGate(runID: first.runID)
        #expect(gate.admit(first) == nil)
        let seen = try answer(first, uptime: 10)
        gate.sent(seen)
        _ = await session.receive(seen, now: 0.1)
        let a = PhoneExternalEffectReference(intentID: UUID())
        let b = PhoneExternalEffectReference(intentID: UUID())
        #expect(await session.propose(proposal(seen, effect: a), now: 0.2) == .routeToActionExecutor(a))
        #expect(await session.transportDisconnected(now: 0.3) == .wait)
        #expect(await session.recordManualIntervention(now: 0.4) == .wait)
        #expect(await session.propose(proposal(seen, effect: b), now: 0.5) == .ignored(.notExpectedInThisPhase))
        #expect(await session.transportReconnected(now: 0.6) == .wait)
        #expect(await session.externalEffectSettled(intentID: a.intentID, state: .readyToDispatch, now: 0.7)
                == .ignored(.effectNotSettled))
        let next = try command(await session.externalEffectSettled(intentID: a.intentID, state: .accepted, now: 0.8))
        #expect(next.stepID != first.stepID && gate.admit(next) == nil)
        let fresh = try answer(next, uptime: 11)
        gate.sent(fresh)
        _ = await session.receive(fresh, now: 0.9)
        // Rejected stale proposals, including one naming an already-routed intent, must neither
        // stop the new step nor reserve the still-unused intent B.
        #expect(await session.propose(proposal(seen, effect: a), now: 1) == .ignored(.wrongStep))
        #expect(await session.propose(proposal(seen, effect: b), now: 1) == .ignored(.wrongStep))
        #expect(await session.propose(proposal(fresh, effect: b), now: 1.1) == .routeToActionExecutor(b))
        let before = await session.record
        #expect(await session.externalEffectSettled(intentID: a.intentID, state: .verified, now: 1.2)
                == .ignored(.notTheAwaitedEffect))
        #expect(await session.record == before)
        #expect(await session.externalEffectSettled(intentID: b.intentID, state: .verified, now: 1.3) == .completed)
        let record = await session.record
        #expect(record.steps.map(\.externalIntentID) == [a.intentID, b.intentID])
        #expect(record.steps.first?.manualInterventionCount == 1 && record.steps.first?.extraLookCount == 0)
        #expect(record.reconnectCount == 1 && record.authorship == .mixed)
    }

    @Test
    func failedOrCancelledEffectsAllowNewIntentsAfterSettlingWhileDisconnected() async throws {
        for settled in [ActionAttemptState.failedKnown, .cancelled] {
            let session = try session(steps: 3)
            let first = try command(await session.start(now: 0))
            var gate = PhoneCommandGate(runID: first.runID)
            #expect(gate.admit(first) == nil)
            let seen = try answer(first, uptime: 10)
            gate.sent(seen)
            _ = await session.receive(seen, now: 0.1)
            let a = PhoneExternalEffectReference(intentID: UUID())
            let b = PhoneExternalEffectReference(intentID: UUID())
            #expect(await session.propose(proposal(seen, effect: a), now: 0.2) == .routeToActionExecutor(a))
            #expect(await session.transportDisconnected(now: 0.3) == .wait)
            #expect(await session.externalEffectSettled(intentID: a.intentID, state: settled, now: 0.4) == .wait)
            #expect(await session.phase == .disconnected)
            #expect(await session.externalEffectSettled(intentID: a.intentID, state: settled, now: 0.5)
                    == .ignored(.notExpectedInThisPhase))
            let next = try command(await session.transportReconnected(now: 0.6))
            #expect(next.stepID != first.stepID && gate.admit(next) == nil)
            let fresh = try answer(next, uptime: 11)
            gate.sent(fresh)
            _ = await session.receive(fresh, now: 0.7)
            // Executor retries use a new intent even when the earlier attempt failed or was cancelled.
            #expect(await session.propose(proposal(fresh, effect: b), now: 0.8) == .routeToActionExecutor(b))
            #expect(await session.externalEffectSettled(intentID: a.intentID, state: settled, now: 0.9)
                    == .ignored(.notTheAwaitedEffect))
            let third = try command(await session.externalEffectSettled(intentID: b.intentID, state: .verified, now: 1))
            #expect(gate.admit(third) == nil)
            let last = try answer(third, uptime: 12)
            gate.sent(last)
            _ = await session.receive(last, now: 1.1)
            // A failed/cancelled intent is still spent in ActionExecutor; refusing it here agrees.
            #expect(await session.propose(proposal(last, effect: a), now: 1.2) == .stopped(.actionNotPermitted))
            #expect(await session.record.steps.map(\.externalEffectState) == [settled, .verified, nil])
        }
    }

    @Test
    func lateSettlementsAndProposalsCannotReviveATerminalExternalPause() async throws {
        for reason in [PhoneLoopStopReason.externalEffectTimeout, .externalEffectUnknown, .transportDisconnected] {
            let session = try session(steps: 2)
            let first = try command(await session.start(now: 0))
            let seen = try answer(first, uptime: 10)
            _ = await session.receive(seen, now: 0.1)
            let effect = PhoneExternalEffectReference(intentID: UUID())
            #expect(await session.propose(proposal(seen, effect: effect), now: 0.2) == .routeToActionExecutor(effect))
            switch reason {
            case .externalEffectTimeout:
                #expect(await session.checkDeadlines(now: 31) == .stopped(reason))
            case .externalEffectUnknown:
                #expect(await session.externalEffectSettled(intentID: effect.intentID, state: .outcomeUnknown, now: 1)
                        == .stopped(reason))
            default:
                #expect(await session.transportDisconnected(now: 0.3) == .wait)
                #expect(await session.transportReconnected(now: 31) == .stopped(reason))
            }
            let before = await session.record
            #expect(await session.externalEffectSettled(intentID: effect.intentID, state: .verified, now: 32)
                    == .ignored(.notExpectedInThisPhase))
            #expect(await session.propose(proposal(seen, effect: effect), now: 32) == .ignored(.notExpectedInThisPhase))
            #expect(await session.receive(seen, now: 32) == .ignored(.notExpectedInThisPhase))
            #expect(await session.transportReconnected(now: 32) == .ignored(.notExpectedInThisPhase))
            #expect(await session.record == before)
            #expect(await session.phase == .stopped(reason))
        }
    }

    @Test
    func postActionIDsAndOldStepCommandsCannotPoisonTheNextStepsAction() async throws {
        let session = try session(steps: 2)
        let first = try command(await session.start(now: 0))
        var gate = PhoneCommandGate(runID: first.runID)
        #expect(gate.admit(first) == nil)
        let seen = try answer(first, uptime: 10)
        gate.sent(seen)
        _ = await session.receive(seen, now: 0.1)
        let action = try command(await session.propose(proposal(seen), now: 0.2))
        #expect(gate.admit(action) == nil)
        let post = try answer(action, uptime: 11, screen: PhoneScreenState(foregroundBundleID: app, elements: []))
        gate.sent(post)
        let next = try command(await session.receive(post, now: 0.3))
        #expect(gate.admit(next) == nil)
        let replay = try answer(next, id: post.observationID, uptime: 12)
        gate.sent(replay)
        #expect(await session.receive(replay, now: 0.4) == .ignored(.replayedObservation))
        #expect(gate.basisObservationIDs.isEmpty)
        let fresh = try answer(next, uptime: 13, screen: PhoneScreenState(foregroundBundleID: app, elements: []))
        let wrongStep = try answer(next, id: fresh.observationID, uptime: 999, step: first.stepID)
        gate.sent(wrongStep)
        #expect(await session.receive(wrongStep, now: 0.5) == .ignored(.wrongStep))
        gate.sent(fresh)
        _ = await session.receive(fresh, now: 0.6)
        let legitimate = try command(await session.propose(proposal(fresh, app: otherApp), now: 0.7))
        let oldStep = PhoneCommandMessage(runID: legitimate.runID, stepID: first.stepID, sequence: 999,
            basedOnObservationID: fresh.observationID, timeoutSeconds: 5, command: legitimate.command)
        #expect(gate.admit(oldStep) == .notBasedOnLatestObservation)
        #expect(gate.lastAdmittedSequence == next.sequence && gate.basisObservationIDs == [fresh.observationID])
        #expect(gate.admit(legitimate) == nil)
        let final = try answer(legitimate, uptime: 14, screen: PhoneScreenState(foregroundBundleID: otherApp, elements: []))
        gate.sent(final)
        #expect(await session.receive(final, now: 0.8) == .completed)
        #expect(await session.record.steps.map(\.outcome) == [.verified, .verified])
    }
}
