import Foundation

// The pure policy of the tethered phone loop (#7): one writer that decides what is sent next,
// what counts as evidence and when a step is done. No transport, no XCTest, no model call and no
// timer live here; the caller passes the controller's monotonic time into every call.
//
// Owner's decisions of 13 October applied here: an external effect pauses the run and resumes
// it once the #12 executor has settled; the recommended age limit is 15 seconds; a runner's
// refusal reason is recorded and decides nothing; the session is an actor.

/// How a step was carried out. A session issues commands in one of the three automated modes
/// and records that mode on each step. `manualIntervention` names a step the person carried out
/// themselves; this session never writes it (it counts interventions on the step instead), and
/// it is here so one vocabulary covers a whole morning.
public enum PhoneStepExecutionMode: String, Codable, Sendable, CaseIterable {
    case nativeAction, configuredShortcut, tetheredController, manualIntervention
}

/// Who performed a run of this loop. There is deliberately no "human" case: whatever this loop
/// drove is playback, not something the person did unprompted. Code that learns habits from
/// comparable mornings must treat both values as it treats an `automated` observation origin.
public enum PhoneRunAuthorship: String, Codable, Sendable, CaseIterable {
    /// Every step was carried out by the assistant.
    case assistantExecuted
    /// The assistant drove the run and the person intervened in at least one step.
    case mixed
}

/// Why a run ended without completing. Each is a separate case so a report can say which.
public enum PhoneLoopStopReason: String, Codable, Sendable, CaseIterable {
    /// The evidence was too old to act on, or older than evidence already accepted.
    case staleEvidence
    /// The target did not identify exactly one hittable element of the observation it was derived from.
    case ambiguousTarget
    case unexpectedDialog
    /// An observation came from another runner clock than the run's first one: the phone
    /// restarted or another runner process answered. What that runner knows of the screen and
    /// of the commands already carried out is gone, so nothing it says can settle a step.
    case runnerChanged
    case modelFailure
    case transportDisconnected
    case transportTimeout
    /// The person stopped the run, or took the phone over more often than the step's budget of looks allows.
    case userStop
    /// The proposed action is outside what the application's policy allows, or the app in front
    /// is not one the policy names, or it is an external effect whose intent this run has
    /// already handed to the executor once.
    case actionNotPermitted
    /// The expected result was not observed in the same app after the action, or it already held
    /// before the action so nothing could have proved it.
    case postconditionNotVerified
    /// The executor could not establish what an external effect did (`outcomeUnknown`, or an
    /// attempt left `dispatching`). The run never continues past that: reconcile the attempt
    /// with the executor, then start a new run.
    case externalEffectUnknown
    /// The executor did not settle an external effect within the policy's wait. The effect is
    /// not recalled by this; its attempt stays in the executor's journal to be reconciled there.
    case externalEffectTimeout
}

public enum PhoneRoundTripResult: String, Codable, Sendable { case answered, timedOut, lostOnDisconnect, abandoned }

/// One command and how long its answer took, on the controller's clock.
public struct PhoneRoundTrip: Codable, Sendable, Equatable {
    public let sequence: Int
    public let kind: PhoneCommandKind
    public let seconds: TimeInterval
    public let result: PhoneRoundTripResult
    /// The reason the runner gave for not carrying this command out, if its accepted answer had
    /// one. Kept for diagnosis; no decision reads it.
    public let refusal: PhoneRunnerRefusal?

    init(sequence: Int, kind: PhoneCommandKind, seconds: TimeInterval, result: PhoneRoundTripResult,
         refusal: PhoneRunnerRefusal? = nil) {
        self.sequence = sequence; self.kind = kind; self.seconds = seconds; self.result = result; self.refusal = refusal
    }
}

public enum PhoneStepOutcome: String, Codable, Sendable {
    /// A new observation showed the expected result of the action.
    case verified
    /// The run was finished at this step after looking only.
    case observedOnly
    /// The step asked for an external effect, which this loop does not perform, and the executor
    /// settled it. What the executor established is in `externalEffectState`.
    case handedToActionExecutor
    case stopped
}

/// Which kind of evidence completed a step. They are not equally strong.
public enum PhoneVerificationKind: String, Codable, Sendable, CaseIterable {
    /// The app that was opened is the one in front.
    case appInFront
    /// The one element the policy expects after this tap was absent before and present after.
    case expectedElementAppeared
    /// The tab was not selected before and is the only selected tab after.
    case tabSelected
    /// The row labels on screen differ from before, with one list still shown. The scroll command
    /// is kept on these terms (owner's decision, 13 October): a scroll is recorded as weakly
    /// verified, never as more. Weak: on a feed
    /// that refreshes by itself this happens without any scroll, and rows of other lists on the
    /// screen are included because an observation does not say which list a row belongs to.
    /// It shows that the screen changed, not that the swipe changed it.
    case rowsChanged
}

/// What is kept about one step: identifiers, counts and timings, never screen content.
public struct PhoneStepRecord: Codable, Sendable, Equatable, Identifiable {
    public let id: UUID
    /// The adapter that sent this step's commands.
    public let mode: PhoneStepExecutionMode
    public let action: PhoneCommandKind?
    public let outcome: PhoneStepOutcome
    /// Set only when `outcome` is `verified`.
    public let verifiedBy: PhoneVerificationKind?
    /// Observations requested beyond the step's first one, reconnects aside.
    public let extraLookCount: Int
    /// Times the action was sent beyond the first.
    public let actionResendCount: Int
    /// Times the person touched the phone during this step. Above zero, the result cannot be
    /// attributed to the adapter alone, whatever `mode` says.
    public let manualInterventionCount: Int
    public let durationSeconds: TimeInterval
    /// From the observation being accepted to a proposal being accepted: the planner's time.
    public let proposalWaitSeconds: TimeInterval?
    public let roundTrips: [PhoneRoundTrip]
    public let externalIntentID: UUID?
    /// What the #12 executor reported for `externalIntentID`, in its own words. Absent when no
    /// outcome was accepted: a step stopped during the pause by the person, a timeout or the
    /// channel has an intent and no state; one stopped by an unknown outcome has both.
    public let externalEffectState: ActionAttemptState?
}

/// The run as it can be stored and read later. `authorship` is the marker for #11.
public struct PhoneRunRecord: Codable, Sendable, Equatable, Identifiable {
    public let id: UUID
    public let protocolVersion: Int
    public let startedAt: Date
    public fileprivate(set) var authorship: PhoneRunAuthorship
    public fileprivate(set) var steps: [PhoneStepRecord]
    public fileprivate(set) var reconnectCount: Int
    public fileprivate(set) var stopReason: PhoneLoopStopReason?
}

/// What must be on screen after a navigation tap for it to count: one element of this role and label.
public struct PhoneScreenExpectation: Sendable, Equatable {
    public let role: PhoneElementRole
    public let label: String
    public init(role: PhoneElementRole, label: String) { self.role = role; self.label = label }
}

/// What the application allows this run to do, and how patient it is. Written by the
/// application, fixed for the run, and not Codable: no message can carry or change one.
/// There are no default numbers; whoever starts a run chooses them. One value is offered by
/// name, `recommendedMaxEvidenceAgeSeconds`, so callers do not each invent their own.
public struct PhoneLoopPolicy: Sendable, Equatable {
    /// The recommended `maxEvidenceAgeSeconds` (owner's decision, 13 October): 15 seconds on the
    /// controller's clock, counted from when the command was issued, so it covers the answer's
    /// travel and the planner's thinking. Any other value in range may still be passed.
    ///
    /// This is not the runner's own re-check, which stays a separate obligation of the runner:
    /// immediately before acting it looks its target up again and refuses if more than 2 seconds
    /// passed since its own look or the element moved (the driver's `tapFreshNavigation`). The
    /// session cannot see that check and does not replace it. A runner that vouches for less
    /// (`validForSeconds`) also still wins: the shorter of the two windows applies.
    public static let recommendedMaxEvidenceAgeSeconds: TimeInterval = 15

    public let allowedBundleIDs: Set<String>
    /// Per app (bundle ID), the navigation labels that may be tapped there, each with the result
    /// that proves the tap worked. A label approved for one app is not valid in another.
    /// The driver takes both from the person the same way (`--navigate-label`, `--expect-label`).
    public let navigation: [String: [String: PhoneScreenExpectation]]
    public let tabLabels: Set<String>
    public let allowsListScroll: Bool
    /// The oldest an observation may be when something is decided from it.
    public let maxEvidenceAgeSeconds: TimeInterval
    public let commandTimeoutSeconds: TimeInterval
    /// How long a lost connection may last before the run stops.
    public let reconnectWindowSeconds: TimeInterval
    /// Two budgets, because the risks differ: a look only reads, a resend can act twice.
    /// Observations a step may request beyond its first (after a timeout, an inconclusive
    /// answer or a manual intervention).
    public let maxExtraLooksPerStep: Int
    /// Times a step may send its action again. Zero means an action is never sent twice.
    public let maxActionResendsPerStep: Int
    public let maxReconnects: Int
    public let maxSteps: Int
    /// How long a run may stay paused for the #12 executor to settle one external effect, on the
    /// controller's clock from the moment the effect was proposed. It includes the person's
    /// approval. When it runs out the run stops as `externalEffectTimeout`.
    public let maxExternalEffectWaitSeconds: TimeInterval

    public init(allowedBundleIDs: Set<String>, navigation: [String: [String: PhoneScreenExpectation]], tabLabels: Set<String>,
                allowsListScroll: Bool, maxEvidenceAgeSeconds: TimeInterval, commandTimeoutSeconds: TimeInterval,
                reconnectWindowSeconds: TimeInterval, maxExtraLooksPerStep: Int, maxActionResendsPerStep: Int,
                maxReconnects: Int, maxSteps: Int, maxExternalEffectWaitSeconds: TimeInterval) throws {
        func require(_ condition: Bool, _ field: String) throws {
            if !condition { throw PhoneLoopProtocolError.valueOutOfRange(field: field) }
        }
        try require(allowedBundleIDs.allSatisfy(PhoneLoopWire.isBundleID), "allowedBundleIDs")
        try require(navigation.allSatisfy { app, labels in
            allowedBundleIDs.contains(app)
                && labels.allSatisfy { PhoneLoopWire.isIdentifier($0.key) && PhoneLoopWire.isIdentifier($0.value.label) }
        }, "navigation")
        try require(tabLabels.allSatisfy(PhoneLoopWire.isIdentifier), "tabLabels")
        try require(maxEvidenceAgeSeconds.isFinite && maxEvidenceAgeSeconds > 0
                    && maxEvidenceAgeSeconds <= PhoneLoopWire.maxValiditySeconds, "maxEvidenceAgeSeconds")
        try require(commandTimeoutSeconds.isFinite && commandTimeoutSeconds > 0
                    && commandTimeoutSeconds <= PhoneLoopWire.maxTimeoutSeconds, "commandTimeoutSeconds")
        try require(reconnectWindowSeconds.isFinite && reconnectWindowSeconds > 0, "reconnectWindowSeconds")
        try require(maxExtraLooksPerStep >= 0, "maxExtraLooksPerStep")
        try require(maxActionResendsPerStep >= 0, "maxActionResendsPerStep")
        try require(maxReconnects >= 0, "maxReconnects")
        try require(maxSteps >= 1, "maxSteps")
        try require(maxExternalEffectWaitSeconds.isFinite && maxExternalEffectWaitSeconds > 0, "maxExternalEffectWaitSeconds")
        self.allowedBundleIDs = allowedBundleIDs; self.navigation = navigation; self.tabLabels = tabLabels
        self.allowsListScroll = allowsListScroll; self.maxEvidenceAgeSeconds = maxEvidenceAgeSeconds
        self.commandTimeoutSeconds = commandTimeoutSeconds; self.reconnectWindowSeconds = reconnectWindowSeconds
        self.maxExtraLooksPerStep = maxExtraLooksPerStep; self.maxActionResendsPerStep = maxActionResendsPerStep
        self.maxReconnects = maxReconnects; self.maxSteps = maxSteps
        self.maxExternalEffectWaitSeconds = maxExternalEffectWaitSeconds
    }
}

/// A pointer to an action drafted for the #12 executor (`ActionDraft.id`, the intent ID).
/// It is the only form in which this loop can mention a send, a delete or a calendar change:
/// it has no payload, is not Codable and cannot be put in a command.
public struct PhoneExternalEffectReference: Sendable, Equatable {
    public let intentID: UUID
    public init(intentID: UUID) { self.intentID = intentID }
}

public enum PhoneProposedAction: Sendable, Equatable {
    case readOnly(PhoneReadOnlyAction)
    case externalEffect(PhoneExternalEffectReference)
}

/// What a planner (a model, or a fixed script) asks for. It names the observation it looked at;
/// a proposal about any other observation is not considered.
public struct PhoneActionProposal: Sendable, Equatable {
    public let runID: UUID
    public let stepID: UUID
    public let observationID: UUID
    public let action: PhoneProposedAction
    public init(runID: UUID, stepID: UUID, observationID: UUID, action: PhoneProposedAction) {
        self.runID = runID; self.stepID = stepID; self.observationID = observationID; self.action = action
    }
}

public enum PhoneLoopPhase: Sendable, Equatable {
    case ready
    /// An `observe` is outstanding and no action's result is in doubt.
    case awaitingObservation
    case awaitingProposal
    /// An action is outstanding; its answer is the evidence the postcondition is checked against.
    case awaitingPostObservation
    /// An action was sent and what it did is not known; an `observe` is outstanding to find out.
    case reconcilingAction
    case disconnected
    /// Paused: an external effect is with the #12 executor. No command is issued, no observation
    /// is accepted and no proposal is considered until `externalEffectSettled` reports it.
    case awaitingExternalEffect(PhoneExternalEffectReference)
    case stopped(PhoneLoopStopReason)
    case completed
}

/// Why an input was set aside. The session is unchanged by an ignored input.
public enum PhoneLoopRejection: Sendable, Equatable {
    case notExpectedInThisPhase, foreignRun, wrongStep, outOfSequence, replayedObservation, notDerivedFromLatestObservation
    /// A report about another intent than the one the run is paused for.
    case notTheAwaitedEffect
    /// The executor has not invoked its adapter yet (`readyToDispatch`): that is not an outcome.
    case effectNotSettled
}

/// What the caller does next. A command exists only as the payload of `send`.
public enum PhoneLoopDirective: Sendable, Equatable {
    case send(PhoneCommandMessage)
    /// Ask the planner about this observation, then call `propose`, `modelFailed` or `finish`.
    /// If an earlier request of this run is still being worked on (a disconnect or an
    /// intervention made the session look again), cancel it: its answer names an observation
    /// that is no longer the latest and would only be ignored.
    case requestProposal(stepID: UUID, observationID: UUID)
    /// Take this to `ActionExecutor`, under its own approval. The run is paused: send nothing to
    /// the phone, and report what the executor's journal says with `externalEffectSettled`.
    case routeToActionExecutor(PhoneExternalEffectReference)
    case wait
    case ignored(PhoneLoopRejection)
    case stopped(PhoneLoopStopReason)
    case completed
}

/// The one writer of a run. Every command comes out of it and every observation, proposal,
/// timeout and stop goes into it; nothing else advances the run.
///
/// It is an actor (owner's decision, 13 October), so several tasks may feed it and there is
/// still one writer: a run is one instance, every holder of it shares one state, and two inputs
/// are never processed at the same time, so two callers cannot each be given the next sequence
/// number. No method here is `async` and none awaits: each input is judged and applied in one
/// uninterrupted turn of the actor, and another input cannot slip in halfway through. Keep it
/// that way. A caller that needs two reads to agree must take them from one directive, not from
/// two separate `await`s.
///
/// A step is: observe, accept a proposal validated against that observation, send the action,
/// and see the expected result in a new observation. Sending an action or receiving its answer
/// does not complete a step; only the evidence does. Every step starts with its own observation.
///
/// An external effect is not a command. Proposing one pauses the run (`awaitingExternalEffect`)
/// and returns `routeToActionExecutor`; the #12 executor performs it under its own approval.
/// The caller then reports the attempt's state from the executor's journal:
/// - `verified`, `accepted`, `failedKnown` or `cancelled`: the effect is settled. The step is
///   closed and the next step starts with a new observation. The effect changed the world, so
///   nothing captured before it is used again: the evidence was dropped when the run paused.
/// - `outcomeUnknown` or `dispatching`: what happened is not known. The run stops as
///   `externalEffectUnknown` and is never continued.
/// A pause lasts at most `maxExternalEffectWaitSeconds`. If the executor refuses the draft
/// before any attempt exists (no approval, a duplicate intent), there is no state to report:
/// end the run with `userStopped`, or let the pause expire.
/// A run pauses for one intent once. A proposal naming an intent this run already handed over
/// stops the run as `actionNotPermitted`, so a report is never matched to a second pause.
///
/// `now` is the controller's monotonic time in seconds, from one clock. A `now` that is not a
/// finite number, or is earlier than one already given, stops the run as stale evidence:
/// nothing can be aged against such a clock.
public actor PhoneLoopSession {
    public nonisolated let runID: UUID
    public nonisolated let policy: PhoneLoopPolicy
    /// How this session's commands are carried out.
    public nonisolated let mode: PhoneStepExecutionMode
    public private(set) var phase: PhoneLoopPhase = .ready
    public private(set) var record: PhoneRunRecord

    private enum ScreenCheck: Sendable, Equatable {
        case element(PhoneScreenExpectation)
        case tabSelected(String)
        case cellsChanged(from: [String])
    }
    /// What a new observation must show: this app in front and, except for `openApp`, the check.
    private struct Expectation: Sendable, Equatable { let app: String; let check: ScreenCheck? }
    private enum Ruling: Sendable { case allowed(Expectation), refused(PhoneLoopStopReason) }
    /// `basis` is the screen the action was validated against.
    private struct PendingAction: Sendable { let action: PhoneReadOnlyAction; let expectation: Expectation; let basis: PhoneScreenState }
    private struct Step: Sendable {
        let id: UUID
        let startedAt: TimeInterval
        let mode: PhoneStepExecutionMode
        var extraLooks = 0
        var resends = 0
        var interventions = 0
        var roundTrips: [PhoneRoundTrip] = []
        var pending: PendingAction?
        var proposalRequestedAt: TimeInterval?
        var proposalWaitSeconds: TimeInterval?
        var externalIntentID: UUID?
        /// When the run paused for the effect, on the controller's clock.
        var effectRequestedAt: TimeInterval?
        var externalEffectState: ActionAttemptState?
    }
    private struct Outstanding: Sendable { let sequence: Int; let kind: PhoneCommandKind; let issuedAt: TimeInterval }
    /// `anchor` is when the command this observation answers was issued: the capture cannot be older.
    private struct Evidence: Sendable { let observation: PhoneObservationMessage; let anchor: TimeInterval }

    private var nextSequence = 1
    private var step: Step?
    private var outstanding: Outstanding?
    private var evidence: Evidence?
    /// The runner clock of the first accepted observation, and its latest accepted capture time.
    private var runnerClock: (id: String, lastCaptureSeconds: Double)?
    private var lastNow = -TimeInterval.infinity
    private var acceptedObservationIDs: Set<UUID> = []
    /// Every intent this run has paused for. A report names only its intent, so an intent must
    /// mean one pause.
    private var routedIntentIDs: Set<UUID> = []
    private var disconnectedAt: TimeInterval?

    /// `startedAt` is the wall-clock start, kept for the record only.
    public init(runID: UUID = UUID(), policy: PhoneLoopPolicy, mode: PhoneStepExecutionMode, startedAt: Date) throws {
        // Manual intervention is something that happens to a step, not a way to send commands.
        guard mode != .manualIntervention else { throw PhoneLoopProtocolError.valueOutOfRange(field: "mode") }
        guard startedAt.timeIntervalSinceReferenceDate.isFinite else { throw PhoneLoopProtocolError.valueOutOfRange(field: "startedAt") }
        self.runID = runID; self.policy = policy; self.mode = mode
        record = PhoneRunRecord(id: runID, protocolVersion: PhoneLoopWire.version, startedAt: startedAt,
                                authorship: .assistantExecuted, steps: [], reconnectCount: 0, stopReason: nil)
    }

    // MARK: Inputs

    public func start(now: TimeInterval) -> PhoneLoopDirective {
        if let halted = haltOnUnsoundClock(now) { return halted }
        guard phase == .ready else { return .ignored(.notExpectedInThisPhase) }
        return beginStep(now: now)
    }

    /// An observation is accepted only as the answer to the one outstanding command of the
    /// current step of this run, and only once.
    public func receive(_ observation: PhoneObservationMessage, now: TimeInterval) -> PhoneLoopDirective {
        if let halted = haltOnUnsoundClock(now) { return halted }
        guard let outstanding, let current = step else { return .ignored(.notExpectedInThisPhase) }
        guard observation.runID == runID else { return .ignored(.foreignRun) }
        guard observation.stepID == current.id else { return .ignored(.wrongStep) }
        guard observation.sequence == outstanding.sequence else { return .ignored(.outOfSequence) }
        guard !acceptedObservationIDs.contains(observation.observationID) else { return .ignored(.replayedObservation) }
        // Past its deadline an answer is the timeout it is, even if nobody checked the clock in between.
        guard now - outstanding.issuedAt < policy.commandTimeoutSeconds else {
            closeRoundTrip(.timedOut, now: now)
            return recover(orStopWith: .transportTimeout, now: now)
        }
        acceptedObservationIDs.insert(observation.observationID)
        // The runner's stated reason goes into the record here and is not read again.
        closeRoundTrip(.answered, refusal: observation.refusal, now: now)

        // The run belongs to the runner that answered first. An answer from another clock is
        // another runner; one whose capture is not later than the last accepted is old evidence.
        if let runnerClock {
            guard runnerClock.id == observation.freshness.clockID else { return stop(.runnerChanged, now: now) }
            guard observation.freshness.capturedUptimeSeconds > runnerClock.lastCaptureSeconds
            else { return stop(.staleEvidence, now: now) }
        }
        runnerClock = (observation.freshness.clockID, observation.freshness.capturedUptimeSeconds)
        if observation.screen.dialogVisible { return stop(.unexpectedDialog, now: now) }
        let accepted = Evidence(observation: observation, anchor: outstanding.issuedAt)

        if outstanding.kind != .observe {
            // The answer to an action: evidence for the postcondition, never a basis for the next action.
            guard let pending = current.pending else { return stop(.postconditionNotVerified, now: now) }
            // Its age bound includes the time the action itself took. Too old to prove anything
            // is not a failure of the action: look again, if a look is left.
            guard isFresh(accepted, now: now) else { return recover(orStopWith: .staleEvidence, now: now) }
            if Self.holds(pending.expectation, in: observation.screen) { return completeStep(.verified, now: now) }
            return recover(orStopWith: .postconditionNotVerified, now: now)
        }

        guard isFresh(accepted, now: now) else { return stop(.staleEvidence, now: now) }
        evidence = accepted

        if let pending = current.pending {
            // The action's result was in doubt, and this look is the reconciliation. Either it
            // shows the expected result (the action happened), or it shows exactly the screen the
            // action was validated against (it did not happen, and may be sent again), or it is
            // inconclusive and the run stops. A screen that merely contains a matching element
            // is some third screen nobody approved an action on.
            if Self.holds(pending.expectation, in: observation.screen) { return completeStep(.verified, now: now) }
            guard current.resends < policy.maxActionResendsPerStep,
                  Self.showsSameScreen(observation.screen, as: pending.basis)
            else { return stop(.postconditionNotVerified, now: now) }
            step?.resends += 1
            phase = .awaitingPostObservation
            return issue(.perform(pending.action), basedOn: observation.observationID, now: now)
        }
        step?.proposalRequestedAt = now
        phase = .awaitingProposal
        return .requestProposal(stepID: current.id, observationID: observation.observationID)
    }

    /// A proposal is only a request. It is carried out if it is about the latest observation,
    /// that observation is still fresh, and the application's policy allows the action on the
    /// one element the target identifies there.
    public func propose(_ proposal: PhoneActionProposal, now: TimeInterval) -> PhoneLoopDirective {
        if let halted = haltOnUnsoundClock(now) { return halted }
        guard phase == .awaitingProposal, let current = step, let evidence else { return .ignored(.notExpectedInThisPhase) }
        guard proposal.runID == runID else { return .ignored(.foreignRun) }
        guard proposal.stepID == current.id else { return .ignored(.wrongStep) }
        guard proposal.observationID == evidence.observation.observationID
        else { return .ignored(.notDerivedFromLatestObservation) }
        guard isFresh(evidence, now: now) else { return stop(.staleEvidence, now: now) }
        step?.proposalWaitSeconds = current.proposalRequestedAt.map { Self.elapsed(from: $0, to: now) }

        switch proposal.action {
        case .externalEffect(let reference):
            // An intent is one effect, performed at most once: the executor refuses it a second
            // time, and a report about it can only describe the first. Pausing for it again
            // would let that old report close this step for an effect nobody performed.
            guard routedIntentIDs.insert(reference.intentID).inserted else { return stop(.actionNotPermitted, now: now) }
            // Nothing is sent. The run pauses, and what was observed before the effect is given
            // up now: whatever the executor does, that screen is no longer a basis for anything.
            step?.externalIntentID = reference.intentID
            step?.effectRequestedAt = now
            self.evidence = nil
            phase = .awaitingExternalEffect(reference)
            return .routeToActionExecutor(reference)
        case .readOnly(let action):
            switch rule(on: action, in: evidence.observation.screen) {
            case .refused(let reason): return stop(reason, now: now)
            case .allowed(let expectation):
                step?.pending = PendingAction(action: action, expectation: expectation, basis: evidence.observation.screen)
                phase = .awaitingPostObservation
                return issue(.perform(action), basedOn: evidence.observation.observationID, now: now)
            }
        }
    }

    /// What the #12 executor established about the effect the run is paused for: the `state` of
    /// its attempt, as `ActionExecutor.dispatch` or `reconcile` returned it, and the intent it
    /// belongs to. A settled state resumes the run with a new observation; an unknown one stops
    /// it. Past the pause's limit a report is the timeout it is, whatever it says, and past the
    /// reconnect window of a channel that dropped during the pause it is that disconnect.
    public func externalEffectSettled(intentID: UUID, state: ActionAttemptState, now: TimeInterval) -> PhoneLoopDirective {
        if let halted = haltOnUnsoundClock(now) { return halted }
        guard case .awaitingExternalEffect(let reference) = phase, let current = step, let pausedAt = current.effectRequestedAt
        else { return .ignored(.notExpectedInThisPhase) }
        guard intentID == reference.intentID else { return .ignored(.notTheAwaitedEffect) }
        guard now - pausedAt < policy.maxExternalEffectWaitSeconds else { return stop(.externalEffectTimeout, now: now) }
        // So is a channel that has been away for longer than the reconnect window.
        if let disconnectedAt, now - disconnectedAt >= policy.reconnectWindowSeconds { return stop(.transportDisconnected, now: now) }
        switch state {
        case .readyToDispatch:
            return .ignored(.effectNotSettled)
        case .dispatching, .outcomeUnknown:
            // `dispatching` after the adapter ran means its result could not be written down.
            step?.externalEffectState = state
            return stop(.externalEffectUnknown, now: now)
        case .accepted, .verified, .failedKnown, .cancelled:
            step?.externalEffectState = state
            closeStep(.handedToActionExecutor, now: now)
            guard record.steps.count < policy.maxSteps else { phase = .completed; return .completed }
            // The next step looks first, as every step does. With the channel down it waits for
            // the reconnect, which observes.
            step = Step(id: UUID(), startedAt: now, mode: mode)
            if disconnectedAt != nil { phase = .disconnected; return .wait }
            return observe(now: now)
        }
    }

    /// The planner produced nothing usable.
    public func modelFailed(now: TimeInterval) -> PhoneLoopDirective {
        if let halted = haltOnUnsoundClock(now) { return halted }
        guard phase == .awaitingProposal else { return .ignored(.notExpectedInThisPhase) }
        return stop(.modelFailure, now: now)
    }

    /// The plan has nothing further to do. Allowed only between an observation and an action.
    public func finish(now: TimeInterval) -> PhoneLoopDirective {
        if let halted = haltOnUnsoundClock(now) { return halted }
        guard phase == .awaitingProposal else { return .ignored(.notExpectedInThisPhase) }
        closeStep(.observedOnly, now: now)
        evidence = nil
        phase = .completed
        return .completed
    }

    /// Stops at once, whatever is outstanding. An answer that arrives afterwards is ignored.
    public func userStopped(now: TimeInterval) -> PhoneLoopDirective {
        if let halted = haltOnUnsoundClock(now) { return halted }
        guard !isTerminal else { return .ignored(.notExpectedInThisPhase) }
        return stop(.userStop, now: now)
    }

    /// Call whenever time has passed. Applies the command timeout, the limit on a pause for an
    /// external effect, the reconnect window and the age limit on evidence a planner is still
    /// thinking about.
    public func checkDeadlines(now: TimeInterval) -> PhoneLoopDirective {
        if let halted = haltOnUnsoundClock(now) { return halted }
        if let outstanding {
            guard now - outstanding.issuedAt >= policy.commandTimeoutSeconds else { return .wait }
            closeRoundTrip(.timedOut, now: now)
            // No answer says nothing about whether an action was carried out: look again first.
            return recover(orStopWith: .transportTimeout, now: now)
        }
        if isPaused, let pausedAt = step?.effectRequestedAt, now - pausedAt >= policy.maxExternalEffectWaitSeconds {
            return stop(.externalEffectTimeout, now: now)
        }
        if phase == .disconnected || isPaused, let disconnectedAt, now - disconnectedAt >= policy.reconnectWindowSeconds {
            return stop(.transportDisconnected, now: now)
        }
        if phase == .awaitingProposal, let evidence, !isFresh(evidence, now: now) { return stop(.staleEvidence, now: now) }
        return .wait
    }

    /// The channel went away. Whatever was outstanding is lost and what the phone shows is no
    /// longer known; a proposal about the earlier screen will not be accepted, so a planner
    /// request still in progress should be cancelled.
    ///
    /// While the run is paused for an external effect it stays paused: the executor does not use
    /// this channel. The same reconnect budget and window apply, and running out of either stops
    /// the run; the effect itself stays with the executor and its journal.
    public func transportDisconnected(now: TimeInterval) -> PhoneLoopDirective {
        if let halted = haltOnUnsoundClock(now) { return halted }
        guard isUnderway else { return .ignored(.notExpectedInThisPhase) }
        if isPaused {
            guard disconnectedAt == nil else { return .ignored(.notExpectedInThisPhase) }
            guard record.reconnectCount < policy.maxReconnects else { return stop(.transportDisconnected, now: now) }
            disconnectedAt = now
            return .wait
        }
        closeRoundTrip(.lostOnDisconnect, now: now)
        evidence = nil
        guard record.reconnectCount < policy.maxReconnects else { return stop(.transportDisconnected, now: now) }
        phase = .disconnected
        disconnectedAt = now
        return .wait
    }

    /// The channel is back. The run, its completed steps and the current step resume; the screen
    /// must be observed again before anything else, and an action that was outstanding is
    /// settled from that new observation, not sent again blindly. A paused run stays paused and
    /// sends nothing: it observes when the effect is settled.
    public func transportReconnected(now: TimeInterval) -> PhoneLoopDirective {
        if let halted = haltOnUnsoundClock(now) { return halted }
        guard phase == .disconnected || isPaused, let disconnectedAt else { return .ignored(.notExpectedInThisPhase) }
        guard now - disconnectedAt < policy.reconnectWindowSeconds else { return stop(.transportDisconnected, now: now) }
        self.disconnectedAt = nil
        record.reconnectCount += 1
        if isPaused { return .wait }
        return observe(now: now)
    }

    /// The person touched the phone. The step counts it and the run becomes `mixed`. Nothing
    /// captured before this moment is used: evidence in hand is dropped, an outstanding command is
    /// abandoned (its answer will be ignored) and the screen is observed again (after a reconnect,
    /// if the channel is down). Every intervention spends one of the step's extra looks; with
    /// none left the run stops as `userStop`. While the run is paused for an external effect the
    /// intervention is counted and nothing is sent or spent: there is no evidence to drop, and
    /// the run observes anew when the effect is settled.
    public func recordManualIntervention(now: TimeInterval) -> PhoneLoopDirective {
        if let halted = haltOnUnsoundClock(now) { return halted }
        guard isUnderway || phase == .disconnected else { return .ignored(.notExpectedInThisPhase) }
        step?.interventions += 1
        record.authorship = .mixed
        evidence = nil
        if isPaused { return .wait }
        closeRoundTrip(.abandoned, now: now)
        guard phase == .disconnected else { return recover(orStopWith: .userStop, now: now) }
        // Reconnecting observes again anyway; the intervention still counts.
        guard let current = step, current.extraLooks < policy.maxExtraLooksPerStep else { return stop(.userStop, now: now) }
        step?.extraLooks += 1
        return .wait
    }

    // MARK: Transitions

    private func haltOnUnsoundClock(_ now: TimeInterval) -> PhoneLoopDirective? {
        if now.isFinite, now >= lastNow { lastNow = now; return nil }
        return isTerminal ? .ignored(.notExpectedInThisPhase) : stop(.staleEvidence, now: lastNow.isFinite ? lastNow : 0)
    }

    private var isTerminal: Bool {
        switch phase {
        case .stopped, .completed: true
        default: false
        }
    }
    private var isPaused: Bool {
        if case .awaitingExternalEffect = phase { true } else { false }
    }
    private var isUnderway: Bool {
        switch phase {
        case .awaitingObservation, .awaitingProposal, .awaitingPostObservation, .reconcilingAction, .awaitingExternalEffect: true
        default: false
        }
    }

    private func isFresh(_ evidence: Evidence, now: TimeInterval) -> Bool {
        let age = now - evidence.anchor
        return age >= 0 && age <= min(policy.maxEvidenceAgeSeconds, evidence.observation.freshness.validForSeconds)
    }

    private func beginStep(now: TimeInterval) -> PhoneLoopDirective {
        step = Step(id: UUID(), startedAt: now, mode: mode)
        return observe(now: now)
    }

    private func observe(now: TimeInterval) -> PhoneLoopDirective {
        phase = step?.pending == nil ? .awaitingObservation : .reconcilingAction
        return issue(.observe, basedOn: nil, now: now)
    }

    private func issue(_ command: PhoneCommand, basedOn observationID: UUID?, now: TimeInterval) -> PhoneLoopDirective {
        guard let current = step else { return .wait }
        let message = PhoneCommandMessage(runID: runID, stepID: current.id, sequence: nextSequence,
                                          basedOnObservationID: observationID,
                                          timeoutSeconds: policy.commandTimeoutSeconds, command: command)
        outstanding = Outstanding(sequence: nextSequence, kind: command.kind, issuedAt: now)
        nextSequence += 1
        return .send(message)
    }

    /// One more observation, if the step still has a look left. A step therefore sends at most
    /// `2 + maxExtraLooksPerStep + maxActionResendsPerStep` commands, plus one per reconnect.
    private func recover(orStopWith reason: PhoneLoopStopReason, now: TimeInterval) -> PhoneLoopDirective {
        guard let current = step, current.extraLooks < policy.maxExtraLooksPerStep else { return stop(reason, now: now) }
        step?.extraLooks += 1
        evidence = nil
        return observe(now: now)
    }

    private func completeStep(_ outcome: PhoneStepOutcome, now: TimeInterval) -> PhoneLoopDirective {
        closeStep(outcome, now: now)
        evidence = nil
        guard record.steps.count < policy.maxSteps else { phase = .completed; return .completed }
        return beginStep(now: now)
    }

    private func stop(_ reason: PhoneLoopStopReason, now: TimeInterval) -> PhoneLoopDirective {
        closeRoundTrip(.abandoned, now: now)
        closeStep(.stopped, now: now)
        evidence = nil
        record.stopReason = reason
        phase = .stopped(reason)
        return .stopped(reason)
    }

    /// A recorded duration is never negative and always a finite number, so the record can be stored.
    private static func elapsed(from start: TimeInterval, to end: TimeInterval) -> TimeInterval {
        min(max(end - start, 0), .greatestFiniteMagnitude)
    }

    private func closeRoundTrip(_ result: PhoneRoundTripResult, refusal: PhoneRunnerRefusal? = nil, now: TimeInterval) {
        guard let sent = outstanding else { return }
        step?.roundTrips.append(PhoneRoundTrip(sequence: sent.sequence, kind: sent.kind, seconds: Self.elapsed(from: sent.issuedAt, to: now),
                                               result: result, refusal: refusal))
        outstanding = nil
    }

    private func closeStep(_ outcome: PhoneStepOutcome, now: TimeInterval) {
        guard let current = step else { return }
        record.steps.append(PhoneStepRecord(
            id: current.id, mode: current.mode, action: current.pending?.action.kind, outcome: outcome,
            verifiedBy: outcome == .verified ? current.pending.map { Self.verificationKind(of: $0.expectation) } : nil,
            extraLookCount: current.extraLooks, actionResendCount: current.resends,
            manualInterventionCount: current.interventions, durationSeconds: Self.elapsed(from: current.startedAt, to: now),
            proposalWaitSeconds: current.proposalWaitSeconds, roundTrips: current.roundTrips,
            externalIntentID: current.externalIntentID, externalEffectState: current.externalEffectState))
        step = nil
    }

    // MARK: Target and postcondition

    /// Decides whether the policy allows this action on this screen and, if so, what must be seen
    /// afterwards. Only identifiers, roles, flags and label equality are used; `textLines` is not read.
    private func rule(on action: PhoneReadOnlyAction, in screen: PhoneScreenState) -> Ruling {
        let expectation: Expectation
        switch action {
        case .openApp(let bundleID):
            guard policy.allowedBundleIDs.contains(bundleID) else { return .refused(.actionNotPermitted) }
            expectation = Expectation(app: bundleID, check: nil)
        case .tapNavigation(let target), .selectTab(let target), .scrollListUp(let target):
            // Labels are allowed inside the apps the policy names, not wherever they happen to appear.
            guard let app = screen.foregroundBundleID, policy.allowedBundleIDs.contains(app)
            else { return .refused(.actionNotPermitted) }
            let check: ScreenCheck
            switch action {
            case .tapNavigation:
                guard let expected = policy.navigation[app]?[target.label] else { return .refused(.actionNotPermitted) }
                check = .element(expected)
            case .selectTab:
                guard policy.tabLabels.contains(target.label) else { return .refused(.actionNotPermitted) }
                check = .tabSelected(target.label)
            default:
                guard policy.allowsListScroll else { return .refused(.actionNotPermitted) }
                // The driver scrolls only when exactly one visible list exists, whatever it is called.
                guard screen.elements.filter({ $0.role == .list && $0.isHittable }).count == 1 else { return .refused(.ambiguousTarget) }
                check = .cellsChanged(from: Self.cellLabels(in: screen))
            }
            guard Self.identifiesOne(target, among: action.targetRoles, in: screen) else { return .refused(.ambiguousTarget) }
            expectation = Expectation(app: app, check: check)
        }
        // A result that is already there cannot show that the action did anything.
        guard !Self.isAlreadyPresent(expectation, in: screen) else { return .refused(.postconditionNotVerified) }
        return .allowed(expectation)
    }

    /// The driver's rule (`exactElement`): buttons first, then cells, then static text; the first
    /// class with a match must have exactly one, and that one must be the element the target names.
    private static func identifiesOne(_ target: PhoneElementTarget, among roles: [PhoneElementRole], in screen: PhoneScreenState) -> Bool {
        for role in roles {
            let matches = screen.elements.filter { $0.role == role && $0.label == target.label }
            if matches.isEmpty { continue }
            return matches.count == 1 && matches[0].id == target.elementID && target.role == role && matches[0].isHittable
        }
        return false
    }

    private static func verificationKind(of expectation: Expectation) -> PhoneVerificationKind {
        switch expectation.check {
        case nil: .appInFront
        case .element: .expectedElementAppeared
        case .tabSelected: .tabSelected
        case .cellsChanged: .rowsChanged
        }
    }

    /// Same app in front and the same elements (identifier, role, label and flags), in any order.
    /// This relies on the runner naming an element the same way in every observation of an
    /// unchanged screen. `textLines` is not compared: it is content, and a clock on screen changes it.
    private static func showsSameScreen(_ screen: PhoneScreenState, as basis: PhoneScreenState) -> Bool {
        func byID(_ state: PhoneScreenState) -> [String: PhoneScreenElement] {
            Dictionary(state.elements.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })
        }
        return screen.foregroundBundleID == basis.foregroundBundleID && byID(screen) == byID(basis)
    }

    /// Every row on screen: an observation does not say which list a row belongs to.
    private static func cellLabels(in screen: PhoneScreenState) -> [String] {
        screen.elements.filter { $0.role == .cell }.map(\.label)
    }

    private static func holds(_ expectation: Expectation, in screen: PhoneScreenState) -> Bool {
        guard screen.foregroundBundleID == expectation.app else { return false }
        switch expectation.check {
        case nil: return true
        case .element(let expected):
            return screen.elements.filter { $0.role == expected.role && $0.label == expected.label }.count == 1
        case .tabSelected(let label):
            let tabs = screen.elements.filter { $0.role == .tab }
            let named = tabs.filter { $0.label == label }
            return named.count == 1 && named[0].isSelected && tabs.filter(\.isSelected).count == 1
        case .cellsChanged(let before):
            // The list must still be there with rows in it: an empty or loading screen is not a scroll.
            let after = cellLabels(in: screen)
            return screen.elements.filter { $0.role == .list && $0.isHittable }.count == 1 && !after.isEmpty && after != before
        }
    }

    private static func isAlreadyPresent(_ expectation: Expectation, in screen: PhoneScreenState) -> Bool {
        switch expectation.check {
        case nil: screen.foregroundBundleID == expectation.app
        case .element(let expected): screen.elements.contains { $0.role == expected.role && $0.label == expected.label }
        case .tabSelected(let label): screen.elements.contains { $0.role == .tab && $0.label == label && $0.isSelected }
        case .cellsChanged: false
        }
    }
}
