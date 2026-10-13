import Foundation
import Testing
@testable import MorningCore

// Fixtures only: synthetic messages, no device, no transport, no model and no external adapter.
// Each test feeds the runner's gate and the session messages that do not belong to the
// outstanding command (another run, step or sequence, an earlier command's identifiers, a
// repeated observation ID, a repeated report) and checks that they change nothing and that the
// genuine message still counts afterwards.
@Suite("Phone loop message correlation")
struct PhoneLoopMessageCorrelationTests {
    private let app = "com.example.synthetic"
    private let home = PhoneScreenState(foregroundBundleID: "com.apple.springboard", elements: [])
    private struct UnexpectedDirective: Error {}

    private func session() throws -> PhoneLoopSession {
        let policy = try PhoneLoopPolicy(
            allowedBundleIDs: [app], navigation: [:], tabLabels: [], allowsListScroll: false,
            maxEvidenceAgeSeconds: 15, commandTimeoutSeconds: 5, reconnectWindowSeconds: 30,
            maxExtraLooksPerStep: 2, maxActionResendsPerStep: 0, maxReconnects: 1,
            maxSteps: 3, maxExternalEffectWaitSeconds: 30)
        return try PhoneLoopSession(policy: policy, mode: .tetheredController,
                                    startedAt: Date(timeIntervalSince1970: 0))
    }

    private func command(_ directive: PhoneLoopDirective) throws -> PhoneCommandMessage {
        guard case .send(let message) = directive else { throw UnexpectedDirective() }
        return message
    }

    private func changed(_ message: PhoneCommandMessage, run: UUID? = nil, step: UUID? = nil,
                         sequence: Int? = nil, basis: UUID? = nil) throws -> PhoneCommandMessage {
        let value = PhoneCommandMessage(runID: run ?? message.runID, stepID: step ?? message.stepID,
                                        sequence: sequence ?? message.sequence,
                                        basedOnObservationID: basis ?? message.basedOnObservationID,
                                        timeoutSeconds: message.timeoutSeconds, command: message.command)
        return try JSONDecoder().decode(PhoneCommandMessage.self, from: JSONEncoder().encode(value))
    }

    private func answer(_ command: PhoneCommandMessage, run: UUID? = nil, step: UUID? = nil,
                        sequence: Int? = nil, id: UUID = UUID(), uptime: Double = 10,
                        screen: PhoneScreenState? = nil) throws -> PhoneObservationMessage {
        let value = try PhoneObservationMessage(
            runID: run ?? command.runID, stepID: step ?? command.stepID,
            sequence: sequence ?? command.sequence, observationID: id,
            freshness: PhoneEvidenceFreshness(clockID: "synthetic-correlation-runner",
                                              capturedUptimeSeconds: uptime,
                                              capturedAtWallClock: Date(timeIntervalSince1970: 0),
                                              validForSeconds: 15), screen: screen ?? home)
        return try JSONDecoder().decode(PhoneObservationMessage.self, from: JSONEncoder().encode(value))
    }

    private func proposal(_ observation: PhoneObservationMessage, run: UUID? = nil,
                          step: UUID? = nil, id: UUID? = nil,
                          effect: PhoneExternalEffectReference? = nil) -> PhoneActionProposal {
        PhoneActionProposal(runID: run ?? observation.runID, stepID: step ?? observation.stepID,
                            observationID: id ?? observation.observationID,
                            action: effect.map { .externalEffect($0) } ?? .readOnly(.openApp(bundleID: app)))
    }

    @Test
    func mismatchedAnswersDoNotConsumeEitherCorrelationSlot() async throws {
        let session = try session()
        let observe = try command(await session.start(now: 0))
        var gate = PhoneCommandGate(runID: observe.runID)
        #expect(gate.admit(observe) == nil)
        let genuine = try answer(observe)
        // Share the genuine observation ID, but poison the screen and capture time. Rejection
        // must not reserve that ID, consume the answer, record a trip or update runner freshness.
        let hostileScreen = PhoneScreenState(foregroundBundleID: app, dialogVisible: true, elements: [])
        let strays: [(PhoneObservationMessage, PhoneLoopRejection)] = [
            (try answer(observe, run: UUID(), id: genuine.observationID, uptime: 999, screen: hostileScreen), .foreignRun),
            (try answer(observe, step: UUID(), id: genuine.observationID, uptime: 999, screen: hostileScreen), .wrongStep),
            (try answer(observe, sequence: observe.sequence + 1, id: genuine.observationID,
                        uptime: 999, screen: hostileScreen), .outOfSequence)
        ]
        let before = await session.record
        for (stray, rejection) in strays {
            gate.sent(stray)
            #expect(await session.receive(stray, now: 0.1) == .ignored(rejection))
            #expect(await session.record == before)
            #expect(await session.phase == .awaitingObservation)
            #expect(gate.lastObservationID == nil && gate.lastAdmittedSequence == observe.sequence)
        }
        gate.sent(genuine)
        #expect(await session.receive(genuine, now: 0.2)
                == .requestProposal(stepID: observe.stepID, observationID: genuine.observationID))
        let action = try command(await session.propose(proposal(genuine), now: 0.3))
        #expect(gate.admit(action) == nil)
        #expect(gate.admit(action) == .replayedOrOutOfOrder)
        let post = try answer(action, uptime: 11, screen: PhoneScreenState(foregroundBundleID: app, elements: []))
        _ = try command(await session.receive(post, now: 0.4))
        #expect(await session.record.steps.first?.roundTrips.map(\.sequence) == [observe.sequence, action.sequence])
    }

    @Test
    func answersForNeverAdmittedCommandsLeaveTheRealAnswerUsable() async throws {
        let session = try session()
        let observe = try command(await session.start(now: 0))
        var gate = PhoneCommandGate(runID: observe.runID)
        let genuine = try answer(observe)
        gate.sent(genuine) // No command has been admitted at all.
        #expect(gate.lastObservationID == nil && gate.lastAdmittedSequence == 0)
        #expect(gate.admit(observe) == nil)
        // An action cannot be admitted before its basis exists. Its answer must not fill the
        // outstanding observe slot, even though it names this run and this step.
        let unadmitted = PhoneCommandMessage(runID: observe.runID, stepID: observe.stepID,
                                            sequence: observe.sequence + 1, basedOnObservationID: UUID(),
                                            timeoutSeconds: 5, command: .perform(.openApp(bundleID: app)))
        #expect(gate.admit(unadmitted) == .notBasedOnLatestObservation)
        let phantom = try answer(unadmitted)
        gate.sent(phantom)
        #expect(await session.receive(phantom, now: 0.1) == .ignored(.outOfSequence))
        let foreign = try changed(observe, run: UUID(), sequence: 500)
        #expect(gate.admit(foreign) == .foreignRun)
        gate.sent(try answer(foreign))
        #expect(gate.lastObservationID == nil && gate.lastAdmittedSequence == observe.sequence)
        gate.sent(genuine)
        _ = await session.receive(genuine, now: 0.2)
        let legitimate = try command(await session.propose(proposal(genuine), now: 0.3))
        #expect(gate.admit(legitimate) == nil)
        #expect(gate.admit(legitimate) == .replayedOrOutOfOrder)
        gate.sent(phantom) // An action's answer never creates a new action basis.
        #expect(gate.lastObservationID == nil)
        #expect(gate.admit(try changed(legitimate, sequence: legitimate.sequence + 1)) == .notBasedOnLatestObservation)
    }

    @Test
    func earlierCommandAnswersAndProposalsCannotSettleAReplacementLook() async throws {
        let session = try session()
        let first = try command(await session.start(now: 0))
        var gate = PhoneCommandGate(runID: first.runID)
        #expect(gate.admit(first) == nil)
        let old = try answer(first)
        gate.sent(old)
        _ = await session.receive(old, now: 0.1)
        let replacement = try command(await session.recordManualIntervention(now: 0.2))
        #expect(replacement.stepID == first.stepID && replacement.sequence > first.sequence)
        #expect(gate.admit(replacement) == nil)
        let before = await session.record
        for stale in [old, try answer(first, uptime: 500)] {
            gate.sent(stale)
            #expect(await session.receive(stale, now: 0.3) == .ignored(.outOfSequence))
            #expect(gate.lastObservationID == nil)
            #expect(await session.record == before)
        }
        #expect(await session.propose(proposal(old), now: 0.3) == .ignored(.notExpectedInThisPhase))
        let fresh = try answer(replacement, uptime: 11)
        gate.sent(fresh)
        _ = await session.receive(fresh, now: 0.4)
        #expect(await session.propose(proposal(old), now: 0.5) == .ignored(.notDerivedFromLatestObservation))
        #expect(await session.propose(proposal(fresh, run: UUID()), now: 0.5) == .ignored(.foreignRun))
        #expect(await session.propose(proposal(fresh, step: UUID()), now: 0.5) == .ignored(.wrongStep))
        let action = try command(await session.propose(proposal(fresh), now: 0.6))
        #expect(gate.admit(action) == nil)
        let post = try answer(action, uptime: 12, screen: PhoneScreenState(foregroundBundleID: app, elements: []))
        _ = try command(await session.receive(post, now: 0.7))
        #expect(await session.record.steps.first?.extraLookCount == 1)
        #expect(await session.record.steps.first?.actionResendCount == 0)
    }

    @Test
    func duplicateAnswersAndProposalsIssueOnlyOneActionAndOneNextStep() async throws {
        let session = try session()
        let observe = try command(await session.start(now: 0))
        var gate = PhoneCommandGate(runID: observe.runID)
        #expect(gate.admit(observe) == nil)
        let seen = try answer(observe)
        gate.sent(seen)
        _ = await session.receive(seen, now: 0.1)
        for duplicate in [seen, try answer(observe, uptime: 999)] {
            gate.sent(duplicate)
            #expect(await session.receive(duplicate, now: 0.2) == .ignored(.notExpectedInThisPhase))
            #expect(gate.lastObservationID == seen.observationID)
        }
        let request = proposal(seen)
        let results = await withTaskGroup(of: PhoneLoopDirective.self) { group in
            for _ in 0..<16 { group.addTask { await session.propose(request, now: 0.3) } }
            var values: [PhoneLoopDirective] = []
            for await value in group { values.append(value) }
            return values
        }
        let actions = results.compactMap { if case .send(let value) = $0 { value } else { nil as PhoneCommandMessage? } }
        #expect(actions.count == 1)
        #expect(results.filter { $0 == .ignored(.notExpectedInThisPhase) }.count == 15)
        let action = try #require(actions.first)
        #expect(gate.admit(action) == nil)
        #expect(gate.admit(action) == .replayedOrOutOfOrder)
        let post = try answer(action, uptime: 11, screen: PhoneScreenState(foregroundBundleID: app, elements: []))
        gate.sent(post)
        let next = try command(await session.receive(post, now: 0.4))
        #expect(gate.admit(next) == nil)
        let before = await session.record
        for duplicate in [seen, post, try answer(action, uptime: 999)] {
            gate.sent(duplicate)
            #expect(await session.receive(duplicate, now: 0.5) == .ignored(.wrongStep))
            #expect(await session.record == before)
            #expect(gate.lastObservationID == nil)
        }
        let nextSeen = try answer(next, uptime: 12)
        gate.sent(nextSeen)
        #expect(await session.receive(nextSeen, now: 0.6)
                == .requestProposal(stepID: next.stepID, observationID: nextSeen.observationID))
        #expect(await session.finish(now: 0.7) == .completed)
        #expect(await session.record.steps.map(\.outcome) == [.verified, .observedOnly])
    }

    @Test
    func reusedObservationIDCannotPoisonTheNextGateSlot() async throws {
        let session = try session()
        let first = try command(await session.start(now: 0))
        var gate = PhoneCommandGate(runID: first.runID)
        #expect(gate.admit(first) == nil)
        let old = try answer(first)
        gate.sent(old)
        _ = await session.receive(old, now: 0.1)
        let next = try command(await session.recordManualIntervention(now: 0.2))
        #expect(gate.admit(next) == nil)
        // Current command tuple, but an observation ID already accepted in this run.
        // The session rejects this replay; the gate must leave room for the genuine answer too.
        let replay = try answer(next, id: old.observationID, uptime: 11)
        gate.sent(replay)
        #expect(await session.receive(replay, now: 0.3) == .ignored(.replayedObservation))
        #expect(gate.lastObservationID == nil, "A rejected replay must not spend the gate's observe slot")
        let genuine = try answer(next, uptime: 12)
        gate.sent(genuine)
        #expect(await session.receive(genuine, now: 0.4)
                == .requestProposal(stepID: next.stepID, observationID: genuine.observationID))
        #expect(gate.lastObservationID == genuine.observationID)
        let action = try command(await session.propose(proposal(genuine), now: 0.5))
        #expect(gate.admit(action) == nil, "The real command must remain executable after the replay")
    }

    @Test
    func crossStepActionCannotConsumeObservationOrSequence() async throws {
        let session = try session()
        let observe = try command(await session.start(now: 0))
        var gate = PhoneCommandGate(runID: observe.runID)
        #expect(gate.admit(observe) == nil)
        let seen = try answer(observe)
        gate.sent(seen)
        _ = await session.receive(seen, now: 0.1)
        #expect(await session.propose(proposal(seen, step: UUID()), now: 0.2) == .ignored(.wrongStep))
        let action = try command(await session.propose(proposal(seen), now: 0.3))
        let invalid: [(PhoneCommandMessage, PhoneCommandGate.Refusal)] = [
            // The right observation, named by a command of another step.
            (try changed(action, step: UUID()), .notBasedOnLatestObservation),
            (try changed(action, step: UUID(), sequence: 999), .notBasedOnLatestObservation),
            (try changed(action, basis: UUID()), .notBasedOnLatestObservation),
            (try changed(action, run: UUID()), .foreignRun),
            (try changed(action, sequence: observe.sequence), .replayedOrOutOfOrder)
        ]
        for (invalid, refusal) in invalid {
            #expect(gate.admit(invalid) == refusal)
            gate.sent(try answer(invalid))
            #expect(gate.lastObservationID == seen.observationID)
            #expect(gate.lastAdmittedSequence == observe.sequence)
        }
        #expect(gate.admit(action) == nil)
        #expect(gate.admit(action) == .replayedOrOutOfOrder)
        #expect(gate.lastObservationID == nil)
    }

    @Test
    func foreignAndDuplicateSettlementsDoNotAdvanceASecondIntent() async throws {
        let session = try session()
        let first = try command(await session.start(now: 0))
        let seen = try answer(first)
        _ = await session.receive(seen, now: 0.1)
        let a = PhoneExternalEffectReference(intentID: UUID())
        let b = PhoneExternalEffectReference(intentID: UUID())
        #expect(await session.propose(proposal(seen, effect: a), now: 0.2) == .routeToActionExecutor(a))
        let before = await session.record
        for state in [ActionAttemptState.accepted, .verified, .outcomeUnknown, .dispatching] {
            #expect(await session.externalEffectSettled(intentID: b.intentID, state: state, now: 0.3)
                    == .ignored(.notTheAwaitedEffect))
            #expect(await session.record == before)
        }
        #expect(await session.externalEffectSettled(intentID: a.intentID, state: .readyToDispatch, now: 0.3)
                == .ignored(.effectNotSettled))
        let second = try command(await session.externalEffectSettled(intentID: a.intentID, state: .accepted, now: 0.4))
        #expect(await session.externalEffectSettled(intentID: a.intentID, state: .accepted, now: 0.5)
                == .ignored(.notExpectedInThisPhase))
        let fresh = try answer(second, uptime: 11)
        _ = await session.receive(fresh, now: 0.6)
        #expect(await session.propose(proposal(fresh, effect: b), now: 0.7) == .routeToActionExecutor(b))
        let paused = await session.record
        #expect(await session.externalEffectSettled(intentID: a.intentID, state: .accepted, now: 0.8)
                == .ignored(.notTheAwaitedEffect))
        #expect(await session.receive(seen, now: 0.8) == .ignored(.notExpectedInThisPhase))
        #expect(await session.propose(proposal(seen, effect: a), now: 0.8) == .ignored(.notExpectedInThisPhase))
        #expect(await session.record == paused)
        #expect(await session.phase == .awaitingExternalEffect(b))
        let third = try command(await session.externalEffectSettled(intentID: b.intentID, state: .verified, now: 0.9))
        #expect(third.sequence == 3)
        #expect(await session.record.steps.map(\.externalIntentID) == [a.intentID, b.intentID])
    }

    @Test
    func anIntentIsRoutedOnceAndItsOldSettlementCompletesNoOtherStep() async throws {
        let session = try session()
        let first = try command(await session.start(now: 0))
        let seen = try answer(first)
        _ = await session.receive(seen, now: 0.1)
        let reference = PhoneExternalEffectReference(intentID: UUID())
        #expect(await session.propose(proposal(seen, effect: reference), now: 0.2) == .routeToActionExecutor(reference))
        let second = try command(await session.externalEffectSettled(intentID: reference.intentID, state: .accepted, now: 0.3))
        let fresh = try answer(second, uptime: 11)
        _ = await session.receive(fresh, now: 0.4)
        // A correctly correlated proposal of the next step names the intent that was already
        // settled. The run does not pause for it again: a report names only its intent, so the
        // earlier report, delivered once more, would close this step for an effect nobody performed.
        #expect(await session.propose(proposal(fresh, effect: reference), now: 0.5) == .stopped(.actionNotPermitted))
        #expect(await session.externalEffectSettled(intentID: reference.intentID, state: .accepted, now: 0.6)
                == .ignored(.notExpectedInThisPhase))
        let record = await session.record
        #expect(record.steps.map(\.outcome) == [.handedToActionExecutor, .stopped])
        #expect(record.steps.map(\.externalIntentID) == [reference.intentID, nil])
        #expect(record.stopReason == .actionNotPermitted)
    }
}
