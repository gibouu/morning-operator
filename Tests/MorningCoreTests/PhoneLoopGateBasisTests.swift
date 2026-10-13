import Foundation
import Testing
@testable import MorningCore

// Fixtures only: synthetic messages, no device, no transport, no model and no external adapter.
// The gate keeps every answer it sent to the `observe` admitted last as a possible basis for the
// one action. These tests try to turn that into two actions for one observe, an action on an
// observation that was not such an answer, or a command carried out twice, in every order of
// arrival, and check that a correct controller's action is still admitted.
@Suite("Phone loop gate basis")
struct PhoneLoopGateBasisTests {
    private let app = "com.example.synthetic"
    private let otherApp = "com.example.synthetic.other"
    private let home = PhoneScreenState(foregroundBundleID: "com.apple.springboard", elements: [])
    private struct UnexpectedDirective: Error {}

    private func session(steps: Int = 1) throws -> PhoneLoopSession {
        let policy = try PhoneLoopPolicy(
            allowedBundleIDs: [app, otherApp], navigation: [:], tabLabels: [], allowsListScroll: false,
            maxEvidenceAgeSeconds: 15, commandTimeoutSeconds: 5, reconnectWindowSeconds: 30,
            maxExtraLooksPerStep: 2, maxActionResendsPerStep: 1, maxReconnects: 1,
            maxSteps: steps, maxExternalEffectWaitSeconds: 30)
        return try PhoneLoopSession(policy: policy, mode: .tetheredController,
                                    startedAt: Date(timeIntervalSince1970: 0))
    }

    private func command(_ directive: PhoneLoopDirective) throws -> PhoneCommandMessage {
        guard case .send(let value) = directive else { throw UnexpectedDirective() }
        return try JSONDecoder().decode(PhoneCommandMessage.self, from: JSONEncoder().encode(value))
    }

    private func answer(_ command: PhoneCommandMessage, id: UUID = UUID(), uptime: Double = 10,
                        run: UUID? = nil, step: UUID? = nil, sequence: Int? = nil,
                        screen: PhoneScreenState? = nil,
                        refusal: PhoneRunnerRefusal? = nil) throws -> PhoneObservationMessage {
        let value = try PhoneObservationMessage(
            runID: run ?? command.runID, stepID: step ?? command.stepID,
            sequence: sequence ?? command.sequence, observationID: id,
            freshness: PhoneEvidenceFreshness(clockID: "synthetic-gate-basis-runner",
                capturedUptimeSeconds: uptime, capturedAtWallClock: Date(timeIntervalSince1970: 0),
                validForSeconds: 15), screen: screen ?? home, refusal: refusal)
        return try JSONDecoder().decode(PhoneObservationMessage.self, from: JSONEncoder().encode(value))
    }

    private func proposal(_ observation: PhoneObservationMessage, app: String? = nil) -> PhoneActionProposal {
        PhoneActionProposal(runID: observation.runID, stepID: observation.stepID,
            observationID: observation.observationID, action: .readOnly(.openApp(bundleID: app ?? self.app)))
    }

    private func action(_ observe: PhoneCommandMessage, basis: UUID, sequence: Int,
                        run: UUID? = nil, step: UUID? = nil) -> PhoneCommandMessage {
        PhoneCommandMessage(runID: run ?? observe.runID, stepID: step ?? observe.stepID,
            sequence: sequence, basedOnObservationID: basis, timeoutSeconds: 5,
            command: .perform(.openApp(bundleID: app)))
    }

    private func permutations(_ values: [Int]) -> [[Int]] {
        if values.isEmpty { return [[]] }
        return values.flatMap { first in
            permutations(values.filter { $0 != first }).map { [first] + $0 }
        }
    }

    @Test
    func threeAnswersInEveryArrivalOrderAndALateFourthAllowExactlyOneControllerAction() async throws {
        for order in permutations([0, 1, 2]) {
            let session = try session()
            let observe = try command(await session.start(now: 0))
            var gate = PhoneCommandGate(runID: observe.runID)
            #expect(gate.admit(observe) == nil)
            var answers: [PhoneObservationMessage] = []
            for index in 0..<3 {
                if index > 0 { #expect(gate.admit(observe) == .replayedOrOutOfOrder) }
                let seen = try answer(observe, uptime: Double(10 + index),
                                      refusal: index == 0 ? nil : .replayedOrOutOfOrder)
                gate.sent(seen)
                answers.append(seen)
            }
            let chosen = answers[order[0]]
            #expect(await session.receive(chosen, now: 0.1)
                    == .requestProposal(stepID: observe.stepID, observationID: chosen.observationID))
            #expect(await session.receive(answers[order[1]], now: 0.2) == .ignored(.notExpectedInThisPhase))
            let perform = try command(await session.propose(proposal(chosen), now: 0.3))
            // Another duplicate reaches the runner while the controller's action is in flight.
            #expect(gate.admit(observe) == .replayedOrOutOfOrder)
            let fourth = try answer(observe, uptime: 13, refusal: .replayedOrOutOfOrder)
            gate.sent(fourth)
            #expect(gate.basisObservationIDs == Set(answers.map(\.observationID) + [fourth.observationID]))
            #expect(gate.admit(perform) == nil)
            #expect(gate.admit(perform) == .replayedOrOutOfOrder)
            #expect(gate.basisObservationIDs.isEmpty)
            // A fresh capture answering a still later duplicate must not rearm the spent observe.
            #expect(gate.admit(observe) == .replayedOrOutOfOrder)
            let fifth = try answer(observe, uptime: 14, refusal: .replayedOrOutOfOrder)
            for late in answers + [fourth, fifth] {
                gate.sent(late)
                #expect(await session.receive(late, now: 0.4) == .ignored(.outOfSequence))
                #expect(gate.admit(action(observe, basis: late.observationID, sequence: 99))
                        == .notBasedOnLatestObservation)
            }
            let post = try answer(perform, uptime: 15,
                                  screen: PhoneScreenState(foregroundBundleID: app, elements: []))
            gate.sent(post)
            #expect(await session.receive(post, now: 0.5) == .completed)
            #expect(await session.record.steps.map(\.outcome) == [.verified])
        }
    }

    @Test
    func all5040InterleavingsKeepOneObserveSingleUseAndCommandsAtMostOnce() throws {
        let observe = PhoneCommandMessage(runID: UUID(), stepID: UUID(), sequence: 1,
                                          basedOnObservationID: nil, timeoutSeconds: 5, command: .observe)
        let a = try answer(observe)
        let b = try answer(observe, uptime: 11, refusal: .replayedOrOutOfOrder)
        let first = action(observe, basis: a.observationID, sequence: 2)
        let alternative = action(observe, basis: b.observationID, sequence: 3)
        let post = try answer(first, uptime: 12)
        let orders = permutations(Array(0..<7))
        #expect(orders.count == 5_040)
        for order in orders {
            var gate = PhoneCommandGate(runID: observe.runID)
            #expect(gate.admit(observe) == nil)
            var executions: [Int] = []
            // Gate-level probes include actions arriving before their basis and an action
            // answer arriving without admission. Even these must not create a second action.
            for event in order {
                switch event {
                case 0: gate.sent(a)
                case 1: gate.sent(b)
                case 2, 4:
                    if gate.admit(first) == nil { executions.append(first.sequence) }
                case 3:
                    if gate.admit(alternative) == nil { executions.append(alternative.sequence) }
                case 5: #expect(gate.admit(observe) == .replayedOrOutOfOrder)
                default: gate.sent(post)
                }
                #expect(executions.count <= 1)
                if !executions.isEmpty { #expect(gate.basisObservationIDs.isEmpty) }
            }
            if executions.isEmpty {
                // Both action attempts may precede both answers in this schedule. Once
                // evidence exists, a legitimate retry must still be admissible.
                #expect(gate.admit(first) == nil)
                executions.append(first.sequence)
            }
            #expect(executions.count == 1)
        }
    }

    @Test
    func rejectedCommandsAndForeignAnswerTuplesPreserveEveryCurrentBasis() async throws {
        let session = try session()
        let observe = try command(await session.start(now: 0))
        var gate = PhoneCommandGate(runID: observe.runID)
        #expect(gate.admit(observe) == nil)
        let a = try answer(observe)
        let b = try answer(observe, uptime: 11)
        gate.sent(a)
        gate.sent(b)
        let kept: Set<UUID> = [a.observationID, b.observationID]
        let badCommands: [(PhoneCommandMessage, PhoneCommandGate.Refusal)] = [
            (action(observe, basis: a.observationID, sequence: 999, run: UUID()), .foreignRun),
            (action(observe, basis: b.observationID, sequence: 999, step: UUID()), .notBasedOnLatestObservation),
            (action(observe, basis: UUID(), sequence: 999), .notBasedOnLatestObservation),
            (action(observe, basis: a.observationID, sequence: 1), .replayedOrOutOfOrder)
        ]
        for (bad, reason) in badCommands {
            #expect(gate.admit(bad) == reason)
            #expect(gate.lastAdmittedSequence == observe.sequence && gate.basisObservationIDs == kept)
        }
        let fresh = try answer(observe, uptime: 12)
        let strays = [
            try answer(observe, id: fresh.observationID, run: UUID()),
            try answer(observe, id: fresh.observationID, step: UUID()),
            try answer(observe, id: fresh.observationID, sequence: 999)
        ]
        let before = await session.record
        for stray in strays {
            gate.sent(stray)
            _ = await session.receive(stray, now: 0.1)
            #expect(await session.record == before)
            #expect(gate.basisObservationIDs == kept)
            #expect(gate.admit(action(observe, basis: fresh.observationID, sequence: 999))
                    == .notBasedOnLatestObservation)
        }
        gate.sent(fresh)
        #expect(gate.basisObservationIDs == kept.union([fresh.observationID]))
        _ = await session.receive(fresh, now: 0.2)
        let perform = try command(await session.propose(proposal(fresh), now: 0.3))
        #expect(gate.admit(perform) == nil)
        let post = try answer(perform, uptime: 13,
                              screen: PhoneScreenState(foregroundBundleID: app, elements: []))
        gate.sent(post)
        #expect(await session.receive(post, now: 0.4) == .completed)
    }

    @Test
    func newerObserveRetiresAllAlternativesIncludingLateDuplicateCaptures() async throws {
        let session = try session()
        let old = try command(await session.start(now: 0))
        var gate = PhoneCommandGate(runID: old.runID)
        #expect(gate.admit(old) == nil)
        let a = try answer(old)
        let b = try answer(old, uptime: 11)
        gate.sent(a)
        gate.sent(b)
        _ = await session.receive(b, now: 0.1)
        let next = try command(await session.recordManualIntervention(now: 0.2))
        #expect(gate.admit(next) == nil)
        let before = await session.record
        for stale in [a, b, try answer(old, uptime: 12, refusal: .replayedOrOutOfOrder)] {
            #expect(gate.admit(old) == .replayedOrOutOfOrder)
            gate.sent(stale)
            #expect(await session.receive(stale, now: 0.3) == .ignored(.outOfSequence))
            #expect(await session.record == before)
            #expect(gate.basisObservationIDs.isEmpty)
            #expect(gate.admit(action(next, basis: stale.observationID, sequence: 999))
                    == .notBasedOnLatestObservation)
        }
        let fresh = try answer(next, uptime: 13)
        gate.sent(fresh)
        _ = await session.receive(fresh, now: 0.4)
        let perform = try command(await session.propose(proposal(fresh), now: 0.5))
        #expect(gate.admit(perform) == nil)
        let post = try answer(perform, uptime: 14,
                              screen: PhoneScreenState(foregroundBundleID: app, elements: []))
        gate.sent(post)
        #expect(await session.receive(post, now: 0.6) == .completed)
    }

    @Test
    func selectedUnselectedAndActionAnswerIDsCannotBeRecycledForTheNextObserve() async throws {
        let session = try session(steps: 2)
        let observe = try command(await session.start(now: 0))
        var gate = PhoneCommandGate(runID: observe.runID)
        #expect(gate.admit(observe) == nil)
        let selected = try answer(observe)
        let unused = try answer(observe, uptime: 11)
        gate.sent(selected)
        gate.sent(unused)
        _ = await session.receive(selected, now: 0.1)
        let perform = try command(await session.propose(proposal(selected), now: 0.2))
        #expect(gate.admit(perform) == nil)
        let screen = PhoneScreenState(foregroundBundleID: app, elements: [])
        let post = try answer(perform, uptime: 12, screen: screen)
        gate.sent(post)
        #expect(gate.admit(perform) == .replayedOrOutOfOrder)
        let duplicatePost = try answer(perform, uptime: 13, screen: screen, refusal: .replayedOrOutOfOrder)
        gate.sent(duplicatePost)
        #expect(gate.basisObservationIDs.isEmpty)
        let next = try command(await session.receive(post, now: 0.3))
        #expect(gate.admit(next) == nil)
        // Re-enveloping a capture is an invalid-runner probe, not a claim that transport
        // duplicates rewrite messages. All four IDs must stay spent, even unselected ones.
        for old in [selected, unused, post, duplicatePost] {
            gate.sent(try answer(next, id: old.observationID, uptime: 14, screen: screen))
            #expect(gate.basisObservationIDs.isEmpty)
            #expect(gate.admit(action(next, basis: old.observationID, sequence: 999))
                    == .notBasedOnLatestObservation)
        }
        let fresh = try answer(next, uptime: 15, screen: screen)
        gate.sent(fresh)
        _ = await session.receive(fresh, now: 0.4)
        let legitimate = try command(await session.propose(proposal(fresh, app: otherApp), now: 0.5))
        #expect(gate.admit(legitimate) == nil)
        let final = try answer(legitimate, uptime: 16,
                               screen: PhoneScreenState(foregroundBundleID: otherApp, elements: []))
        gate.sent(final)
        #expect(await session.receive(final, now: 0.6) == .completed)
        #expect(await session.record.steps.map(\.outcome) == [.verified, .verified])
    }

    @Test
    func duplicatedRecoveryObserveEitherSettlesOrResendsWithoutExecutingTwice() async throws {
        for alreadyExecuted in [false, true] {
            for refusalFirst in [false, true] {
                let session = try session()
                let observe = try command(await session.start(now: 0))
                var gate = PhoneCommandGate(runID: observe.runID)
                #expect(gate.admit(observe) == nil)
                let seen = try answer(observe)
                gate.sent(seen)
                _ = await session.receive(seen, now: 0.1)
                let original = try command(await session.propose(proposal(seen), now: 0.2))
                var executionCount = 0
                let opened = PhoneScreenState(foregroundBundleID: app, elements: [])
                if alreadyExecuted {
                    #expect(gate.admit(original) == nil)
                    executionCount += 1
                    // Its answer is lost. Recovery must prove the result without redoing it.
                    gate.sent(try answer(original, uptime: 11, screen: opened))
                }
                let recovery = try command(await session.checkDeadlines(now: 5.3))
                #expect(gate.admit(recovery) == nil)
                #expect(gate.admit(original) == .replayedOrOutOfOrder)
                let currentScreen = alreadyExecuted ? opened : home
                let a = try answer(recovery, uptime: 12, screen: currentScreen)
                gate.sent(a)
                #expect(gate.admit(recovery) == .replayedOrOutOfOrder)
                let b = try answer(recovery, uptime: 13, screen: currentScreen, refusal: .replayedOrOutOfOrder)
                gate.sent(b)
                let result = await session.receive(refusalFirst ? b : a, now: 5.4)
                if alreadyExecuted {
                    #expect(result == .completed)
                } else {
                    let resend = try command(result)
                    #expect(gate.admit(resend) == nil)
                    executionCount += 1
                    #expect(gate.admit(resend) == .replayedOrOutOfOrder)
                    for late in [a, b] { gate.sent(late) }
                    #expect(gate.basisObservationIDs.isEmpty)
                    let post = try answer(resend, uptime: 14, screen: opened)
                    gate.sent(post)
                    #expect(await session.receive(post, now: 5.5) == .completed)
                }
                let before = await session.record
                #expect(await session.receive(refusalFirst ? a : b, now: 5.6) == .ignored(.notExpectedInThisPhase))
                #expect(await session.record == before)
                #expect(executionCount == 1)
                #expect(before.steps.map(\.outcome) == [.verified])
                #expect(before.steps.first?.actionResendCount == (alreadyExecuted ? 0 : 1))
            }
        }
    }
}
