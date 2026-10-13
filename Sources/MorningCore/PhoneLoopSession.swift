import Foundation

// The pure policy of the tethered phone loop (#7): one writer that decides what is sent next,
// what counts as evidence and when a step is done. No transport, no XCTest, no model call and no
// timer live here; the caller passes the controller's monotonic time into every call.

/// How a step was carried out. A session issues commands in one of the three automated modes;
/// `manualIntervention` is recorded when the person touched the phone during a step.
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
    case modelFailure
    case transportDisconnected
    case transportTimeout
    /// The person stopped the run, or took the phone over more often than the step's retry budget allows.
    case userStop
    /// The proposed action is outside what the application's policy allows, or the app in front
    /// is not one the policy names.
    case actionNotPermitted
    /// The expected result was not observed in the same app after the action, or it already held
    /// before the action so nothing could have proved it.
    case postconditionNotVerified
}

public enum PhoneRoundTripResult: String, Codable, Sendable { case answered, timedOut, lostOnDisconnect, abandoned }

/// One command and how long its answer took, on the controller's clock.
public struct PhoneRoundTrip: Codable, Sendable, Equatable {
    public let sequence: Int
    public let kind: PhoneCommandKind
    public let seconds: TimeInterval
    public let result: PhoneRoundTripResult
}

public enum PhoneStepOutcome: String, Codable, Sendable {
    /// A new observation showed the expected result of the action.
    case verified
    /// The run was finished at this step after looking only.
    case observedOnly
    /// The step asked for an external effect, which this loop does not perform.
    case handedToActionExecutor
    case stopped
}

/// What is kept about one step: identifiers, counts and timings, never screen content.
public struct PhoneStepRecord: Codable, Sendable, Equatable, Identifiable {
    public let id: UUID
    public let mode: PhoneStepExecutionMode
    public let action: PhoneCommandKind?
    public let outcome: PhoneStepOutcome
    /// Commands sent beyond the first observation and the first action.
    public let retryCount: Int
    public let durationSeconds: TimeInterval
    /// From the observation being accepted to a proposal being accepted: the planner's time.
    public let proposalWaitSeconds: TimeInterval?
    public let roundTrips: [PhoneRoundTrip]
    public let externalIntentID: UUID?
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
/// There are no default numbers; whoever starts a run chooses them.
public struct PhoneLoopPolicy: Sendable, Equatable {
    public let allowedBundleIDs: Set<String>
    /// Navigation labels that may be tapped, each with the result that proves the tap worked.
    /// The driver takes both from the person the same way (`--navigate-label`, `--expect-label`).
    public let navigation: [String: PhoneScreenExpectation]
    public let tabLabels: Set<String>
    public let allowsListScroll: Bool
    /// The oldest an observation may be when something is decided from it.
    public let maxEvidenceAgeSeconds: TimeInterval
    public let commandTimeoutSeconds: TimeInterval
    /// How long a lost connection may last before the run stops.
    public let reconnectWindowSeconds: TimeInterval
    public let maxRetriesPerStep: Int
    public let maxReconnects: Int
    public let maxSteps: Int

    public init(allowedBundleIDs: Set<String>, navigation: [String: PhoneScreenExpectation], tabLabels: Set<String>,
                allowsListScroll: Bool, maxEvidenceAgeSeconds: TimeInterval, commandTimeoutSeconds: TimeInterval,
                reconnectWindowSeconds: TimeInterval, maxRetriesPerStep: Int, maxReconnects: Int, maxSteps: Int) throws {
        func require(_ condition: Bool, _ field: String) throws {
            if !condition { throw PhoneLoopProtocolError.valueOutOfRange(field: field) }
        }
        try require(allowedBundleIDs.allSatisfy(PhoneLoopWire.isBundleID), "allowedBundleIDs")
        try require(navigation.allSatisfy { PhoneLoopWire.isIdentifier($0.key) && PhoneLoopWire.isIdentifier($0.value.label) }, "navigation")
        try require(tabLabels.allSatisfy(PhoneLoopWire.isIdentifier), "tabLabels")
        try require(maxEvidenceAgeSeconds.isFinite && maxEvidenceAgeSeconds > 0
                    && maxEvidenceAgeSeconds <= PhoneLoopWire.maxValiditySeconds, "maxEvidenceAgeSeconds")
        try require(commandTimeoutSeconds.isFinite && commandTimeoutSeconds > 0
                    && commandTimeoutSeconds <= PhoneLoopWire.maxTimeoutSeconds, "commandTimeoutSeconds")
        try require(reconnectWindowSeconds.isFinite && reconnectWindowSeconds > 0, "reconnectWindowSeconds")
        try require(maxRetriesPerStep >= 0, "maxRetriesPerStep")
        try require(maxReconnects >= 0, "maxReconnects")
        try require(maxSteps >= 1, "maxSteps")
        self.allowedBundleIDs = allowedBundleIDs; self.navigation = navigation; self.tabLabels = tabLabels
        self.allowsListScroll = allowsListScroll; self.maxEvidenceAgeSeconds = maxEvidenceAgeSeconds
        self.commandTimeoutSeconds = commandTimeoutSeconds; self.reconnectWindowSeconds = reconnectWindowSeconds
        self.maxRetriesPerStep = maxRetriesPerStep; self.maxReconnects = maxReconnects; self.maxSteps = maxSteps
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
    case stopped(PhoneLoopStopReason)
    /// Ended by handing an external effect to the #12 executor. This loop did not perform it.
    case handedToActionExecutor(PhoneExternalEffectReference)
    case completed
}

/// Why an input was set aside. The session is unchanged by an ignored input.
public enum PhoneLoopRejection: Sendable, Equatable {
    case notExpectedInThisPhase, foreignRun, wrongStep, outOfSequence, replayedObservation, notDerivedFromLatestObservation
}

/// What the caller does next. A command exists only as the payload of `send`.
public enum PhoneLoopDirective: Sendable, Equatable {
    case send(PhoneCommandMessage)
    /// Ask the planner about this observation, then call `propose`, `modelFailed` or `finish`.
    case requestProposal(stepID: UUID, observationID: UUID)
    /// Take this to `ActionExecutor`, under its own approval. The run has ended.
    case routeToActionExecutor(PhoneExternalEffectReference)
    case wait
    case ignored(PhoneLoopRejection)
    case stopped(PhoneLoopStopReason)
    case completed
}

/// The one writer of a run. Every command comes out of it and every observation, proposal,
/// timeout and stop goes into it; nothing else advances the run. It cannot be copied, so two
/// copies of one run cannot each issue the next sequence number.
///
/// A step is: observe, accept a proposal validated against that observation, send the action,
/// and see the expected result in a new observation. Sending an action or receiving its answer
/// does not complete a step; only the evidence does. Every step starts with its own observation.
///
/// `now` is the controller's monotonic time in seconds, from one clock, never going backwards.
public struct PhoneLoopSession: ~Copyable, Sendable {
    public let runID: UUID
    public let policy: PhoneLoopPolicy
    /// How this session's commands are carried out.
    public let mode: PhoneStepExecutionMode
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
    private struct PendingAction: Sendable { let action: PhoneReadOnlyAction; var expectation: Expectation }
    private struct Step: Sendable {
        let id: UUID
        let startedAt: TimeInterval
        var mode: PhoneStepExecutionMode
        var retryCount = 0
        var roundTrips: [PhoneRoundTrip] = []
        var pending: PendingAction?
        var proposalRequestedAt: TimeInterval?
        var proposalWaitSeconds: TimeInterval?
        var externalIntentID: UUID?
    }
    private struct Outstanding: Sendable { let sequence: Int; let kind: PhoneCommandKind; let issuedAt: TimeInterval }
    /// `anchor` is when the command this observation answers was issued: the capture cannot be older.
    private struct Evidence: Sendable { let observation: PhoneObservationMessage; let anchor: TimeInterval }

    private var nextSequence = 1
    private var step: Step?
    private var outstanding: Outstanding?
    private var evidence: Evidence?
    /// The latest accepted capture time of every runner clock seen in this run.
    private var lastCaptureByClock: [String: Double] = [:]
    private var acceptedObservationIDs: Set<UUID> = []
    private var disconnectedAt: TimeInterval?

    /// `startedAt` is the wall-clock start, kept for the record only.
    public init(runID: UUID = UUID(), policy: PhoneLoopPolicy, mode: PhoneStepExecutionMode, startedAt: Date) throws {
        // Manual intervention is something that happens to a step, not a way to send commands.
        guard mode != .manualIntervention else { throw PhoneLoopProtocolError.valueOutOfRange(field: "mode") }
        self.runID = runID; self.policy = policy; self.mode = mode
        record = PhoneRunRecord(id: runID, protocolVersion: PhoneLoopWire.version, startedAt: startedAt,
                                authorship: .assistantExecuted, steps: [], reconnectCount: 0, stopReason: nil)
    }

    // MARK: Inputs

    public mutating func start(now: TimeInterval) -> PhoneLoopDirective {
        guard phase == .ready else { return .ignored(.notExpectedInThisPhase) }
        return beginStep(now: now)
    }

    /// An observation is accepted only as the answer to the one outstanding command of the
    /// current step of this run, and only once.
    public mutating func receive(_ observation: PhoneObservationMessage, now: TimeInterval) -> PhoneLoopDirective {
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
        closeRoundTrip(.answered, now: now)

        // An answer whose capture is not later than one already accepted from the same clock is old evidence.
        if let last = lastCaptureByClock[observation.freshness.clockID], observation.freshness.capturedUptimeSeconds <= last {
            return stop(.staleEvidence, now: now)
        }
        lastCaptureByClock[observation.freshness.clockID] = observation.freshness.capturedUptimeSeconds
        if observation.screen.dialogVisible { return stop(.unexpectedDialog, now: now) }
        let accepted = Evidence(observation: observation, anchor: outstanding.issuedAt)

        if outstanding.kind != .observe {
            // The answer to an action: evidence for the postcondition, never a basis for the next action.
            guard let pending = current.pending else { return stop(.postconditionNotVerified, now: now) }
            // Its age bound includes the time the action itself took. Too old to prove anything
            // is not a failure of the action: look again, if a retry is left.
            guard isFresh(accepted, now: now) else { return recover(orStopWith: .staleEvidence, now: now) }
            if Self.holds(pending.expectation, in: observation.screen) { return completeStep(.verified, now: now) }
            return recover(orStopWith: .postconditionNotVerified, now: now)
        }

        guard isFresh(accepted, now: now) else { return stop(.staleEvidence, now: now) }
        evidence = accepted

        if let pending = current.pending {
            // The action's result was in doubt. It either happened, or it may be sent again
            // against this new evidence, or the run stops; it is never assumed.
            if Self.holds(pending.expectation, in: observation.screen) { return completeStep(.verified, now: now) }
            guard current.retryCount < policy.maxRetriesPerStep,
                  case .allowed(let expectation) = rule(on: pending.action, in: observation.screen)
            else { return stop(.postconditionNotVerified, now: now) }
            step?.retryCount += 1
            step?.pending?.expectation = expectation
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
    public mutating func propose(_ proposal: PhoneActionProposal, now: TimeInterval) -> PhoneLoopDirective {
        guard phase == .awaitingProposal, let current = step, let evidence else { return .ignored(.notExpectedInThisPhase) }
        guard proposal.runID == runID else { return .ignored(.foreignRun) }
        guard proposal.stepID == current.id else { return .ignored(.wrongStep) }
        guard proposal.observationID == evidence.observation.observationID
        else { return .ignored(.notDerivedFromLatestObservation) }
        guard isFresh(evidence, now: now) else { return stop(.staleEvidence, now: now) }
        step?.proposalWaitSeconds = current.proposalRequestedAt.map { now - $0 }

        switch proposal.action {
        case .externalEffect(let reference):
            step?.externalIntentID = reference.intentID
            closeStep(.handedToActionExecutor, now: now)
            self.evidence = nil
            phase = .handedToActionExecutor(reference)
            return .routeToActionExecutor(reference)
        case .readOnly(let action):
            switch rule(on: action, in: evidence.observation.screen) {
            case .refused(let reason): return stop(reason, now: now)
            case .allowed(let expectation):
                step?.pending = PendingAction(action: action, expectation: expectation)
                phase = .awaitingPostObservation
                return issue(.perform(action), basedOn: evidence.observation.observationID, now: now)
            }
        }
    }

    /// The planner produced nothing usable.
    public mutating func modelFailed(now: TimeInterval) -> PhoneLoopDirective {
        guard phase == .awaitingProposal else { return .ignored(.notExpectedInThisPhase) }
        return stop(.modelFailure, now: now)
    }

    /// The plan has nothing further to do. Allowed only between an observation and an action.
    public mutating func finish(now: TimeInterval) -> PhoneLoopDirective {
        guard phase == .awaitingProposal else { return .ignored(.notExpectedInThisPhase) }
        closeStep(.observedOnly, now: now)
        evidence = nil
        phase = .completed
        return .completed
    }

    /// Stops at once, whatever is outstanding. An answer that arrives afterwards is ignored.
    public mutating func userStopped(now: TimeInterval) -> PhoneLoopDirective {
        guard !isTerminal else { return .ignored(.notExpectedInThisPhase) }
        return stop(.userStop, now: now)
    }

    /// Call whenever time has passed. Applies the command timeout, the reconnect window and the
    /// age limit on evidence a planner is still thinking about.
    public mutating func checkDeadlines(now: TimeInterval) -> PhoneLoopDirective {
        if let outstanding {
            guard now - outstanding.issuedAt >= policy.commandTimeoutSeconds else { return .wait }
            closeRoundTrip(.timedOut, now: now)
            // No answer says nothing about whether an action was carried out: look again first.
            return recover(orStopWith: .transportTimeout, now: now)
        }
        if phase == .disconnected, let disconnectedAt, now - disconnectedAt >= policy.reconnectWindowSeconds {
            return stop(.transportDisconnected, now: now)
        }
        if phase == .awaitingProposal, let evidence, !isFresh(evidence, now: now) { return stop(.staleEvidence, now: now) }
        return .wait
    }

    /// The channel went away. Whatever was outstanding is lost and what the phone shows is no
    /// longer known; a proposal about the earlier screen will not be accepted.
    public mutating func transportDisconnected(now: TimeInterval) -> PhoneLoopDirective {
        guard isUnderway else { return .ignored(.notExpectedInThisPhase) }
        closeRoundTrip(.lostOnDisconnect, now: now)
        evidence = nil
        guard record.reconnectCount < policy.maxReconnects else { return stop(.transportDisconnected, now: now) }
        phase = .disconnected
        disconnectedAt = now
        return .wait
    }

    /// The channel is back. The run, its completed steps and the current step resume; the screen
    /// must be observed again before anything else, and an action that was outstanding is
    /// settled from that new observation, not sent again blindly.
    public mutating func transportReconnected(now: TimeInterval) -> PhoneLoopDirective {
        guard phase == .disconnected, let disconnectedAt else { return .ignored(.notExpectedInThisPhase) }
        guard now - disconnectedAt < policy.reconnectWindowSeconds else { return stop(.transportDisconnected, now: now) }
        self.disconnectedAt = nil
        record.reconnectCount += 1
        return observe(now: now)
    }

    /// The person touched the phone. The step and the run are marked, and nothing captured before
    /// this moment is used: evidence in hand is dropped, an outstanding command is abandoned (its
    /// answer will be ignored) and the screen is observed again. That observation counts against
    /// the step's retries; with none left the run stops as `userStop`.
    public mutating func recordManualIntervention(now: TimeInterval) -> PhoneLoopDirective {
        guard isUnderway || phase == .disconnected else { return .ignored(.notExpectedInThisPhase) }
        step?.mode = .manualIntervention
        record.authorship = .mixed
        evidence = nil
        // Reconnecting observes again anyway.
        guard phase != .disconnected else { return .wait }
        closeRoundTrip(.abandoned, now: now)
        return recover(orStopWith: .userStop, now: now)
    }

    // MARK: Transitions

    private var isTerminal: Bool {
        switch phase {
        case .stopped, .handedToActionExecutor, .completed: true
        default: false
        }
    }
    private var isUnderway: Bool {
        switch phase {
        case .awaitingObservation, .awaitingProposal, .awaitingPostObservation, .reconcilingAction: true
        default: false
        }
    }

    private func isFresh(_ evidence: Evidence, now: TimeInterval) -> Bool {
        let age = now - evidence.anchor
        return age >= 0 && age <= min(policy.maxEvidenceAgeSeconds, evidence.observation.freshness.validForSeconds)
    }

    private mutating func beginStep(now: TimeInterval) -> PhoneLoopDirective {
        step = Step(id: UUID(), startedAt: now, mode: mode)
        return observe(now: now)
    }

    private mutating func observe(now: TimeInterval) -> PhoneLoopDirective {
        phase = step?.pending == nil ? .awaitingObservation : .reconcilingAction
        return issue(.observe, basedOn: nil, now: now)
    }

    private mutating func issue(_ command: PhoneCommand, basedOn observationID: UUID?, now: TimeInterval) -> PhoneLoopDirective {
        guard let current = step else { return .wait }
        let message = PhoneCommandMessage(runID: runID, stepID: current.id, sequence: nextSequence,
                                          basedOnObservationID: observationID,
                                          timeoutSeconds: policy.commandTimeoutSeconds, command: command)
        outstanding = Outstanding(sequence: nextSequence, kind: command.kind, issuedAt: now)
        nextSequence += 1
        return .send(message)
    }

    /// One more observation, if the step still has a retry left. Every command beyond a step's
    /// first observation and first action is counted, so a step sends at most `2 + maxRetriesPerStep`
    /// commands plus one per reconnect.
    private mutating func recover(orStopWith reason: PhoneLoopStopReason, now: TimeInterval) -> PhoneLoopDirective {
        guard let current = step, current.retryCount < policy.maxRetriesPerStep else { return stop(reason, now: now) }
        step?.retryCount += 1
        evidence = nil
        return observe(now: now)
    }

    private mutating func completeStep(_ outcome: PhoneStepOutcome, now: TimeInterval) -> PhoneLoopDirective {
        closeStep(outcome, now: now)
        evidence = nil
        guard record.steps.count < policy.maxSteps else { phase = .completed; return .completed }
        return beginStep(now: now)
    }

    private mutating func stop(_ reason: PhoneLoopStopReason, now: TimeInterval) -> PhoneLoopDirective {
        closeRoundTrip(.abandoned, now: now)
        closeStep(.stopped, now: now)
        evidence = nil
        record.stopReason = reason
        phase = .stopped(reason)
        return .stopped(reason)
    }

    private mutating func closeRoundTrip(_ result: PhoneRoundTripResult, now: TimeInterval) {
        guard let sent = outstanding else { return }
        step?.roundTrips.append(PhoneRoundTrip(sequence: sent.sequence, kind: sent.kind, seconds: now - sent.issuedAt, result: result))
        outstanding = nil
    }

    private mutating func closeStep(_ outcome: PhoneStepOutcome, now: TimeInterval) {
        guard let current = step else { return }
        record.steps.append(PhoneStepRecord(
            id: current.id, mode: current.mode, action: current.pending?.action.kind, outcome: outcome,
            retryCount: current.retryCount, durationSeconds: now - current.startedAt,
            proposalWaitSeconds: current.proposalWaitSeconds, roundTrips: current.roundTrips,
            externalIntentID: current.externalIntentID))
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
                guard let expected = policy.navigation[target.label] else { return .refused(.actionNotPermitted) }
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
        case .cellsChanged(let before): return cellLabels(in: screen) != before
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
