import Foundation

// Wire messages of the tethered observe → plan → act → verify loop (#7).
//
// Two messages only. The controller sends a command; the runner answers each command with one
// observation that echoes the command's run, step and sequence. Nothing here opens a channel,
// drives XCTest or calls a model: `PhoneLoopSession` (the other file) is the pure policy, and
// the transport, the runner and the planner are separate work.

/// Format constants. A message of another version is refused: there is no negotiation and no
/// best-effort reading of a newer or older shape.
public enum PhoneLoopWire {
    public static let version = 1
    /// Upper bounds a decoded message must respect, so one message cannot grow without limit.
    public static let maxElements = 400
    public static let maxTextLines = 400
    public static let maxTextBytes = 1_024
    public static let maxValiditySeconds: TimeInterval = 60
    public static let maxTimeoutSeconds: TimeInterval = 120

    /// Reverse-DNS characters only, the same shape `scripts/run-device-tests.sh` accepts.
    static func isBundleID(_ value: String) -> Bool {
        let parts = value.split(separator: ".", omittingEmptySubsequences: false)
        return parts.count >= 2 && value.utf8.count <= maxTextBytes && parts.allSatisfy { part in
            !part.isEmpty && part.utf8.allSatisfy { byte in
                (48...57).contains(byte) || (65...90).contains(byte) || (97...122).contains(byte) || byte == 45
            }
        }
    }
    static func isIdentifier(_ value: String) -> Bool { !value.isEmpty && value.utf8.count <= maxTextBytes }
}

public enum PhoneLoopProtocolError: Error, Equatable, Sendable {
    case unsupportedVersion(Int)
    case valueOutOfRange(field: String)
    /// The command kind and the fields that came with it do not belong together.
    case inconsistentCommand
}

/// Every command the loop can express. The list is what the UI-test driver does today
/// (`DeviceObservationTests`, `ClockObservationTests`): capture a screen, launch a chosen app,
/// tap one uniquely labelled navigation element, select one tab, swipe one list up once.
/// There is no coordinate tap, no text entry and no send or delete; an unknown kind fails to decode.
public enum PhoneCommandKind: String, Codable, Sendable, CaseIterable {
    case observe, openApp, tapNavigation, selectTab, scrollListUp
}

/// Element classes the driver queries. Anything else on screen is not reported as an element.
public enum PhoneElementRole: String, Codable, Sendable, CaseIterable {
    case button, cell, staticText, tab, navigationBar, list
}

/// One element as the runner saw it. `id` is the runner's own name for it inside this single
/// observation; it means nothing in another observation.
public struct PhoneScreenElement: Codable, Sendable, Equatable {
    public let id: String
    public let role: PhoneElementRole
    public let label: String
    public let isHittable: Bool
    public let isSelected: Bool
    public init(id: String, role: PhoneElementRole, label: String, isHittable: Bool = true, isSelected: Bool = false) {
        self.id = id; self.role = role; self.label = label; self.isHittable = isHittable; self.isSelected = isSelected
    }
}

/// What was on screen. `textLines` is recognized or accessibility text for narration. It is
/// content: the session never reads it, and labels are only ever compared for equality with
/// labels the application's own policy names.
public struct PhoneScreenState: Codable, Sendable, Equatable {
    public let foregroundBundleID: String?
    /// Any alert or sheet, in the app or from the system. The driver refuses all of them.
    public let dialogVisible: Bool
    public let elements: [PhoneScreenElement]
    public let textLines: [String]
    public init(foregroundBundleID: String?, dialogVisible: Bool = false,
                elements: [PhoneScreenElement], textLines: [String] = []) {
        self.foregroundBundleID = foregroundBundleID; self.dialogVisible = dialogVisible
        self.elements = elements; self.textLines = textLines
    }

    func validate() throws {
        if let foregroundBundleID, !PhoneLoopWire.isBundleID(foregroundBundleID) {
            throw PhoneLoopProtocolError.valueOutOfRange(field: "foregroundBundleID")
        }
        guard elements.count <= PhoneLoopWire.maxElements,
              elements.allSatisfy({ PhoneLoopWire.isIdentifier($0.id) && $0.label.utf8.count <= PhoneLoopWire.maxTextBytes }),
              // Two elements with one identifier would make "this element" mean two things.
              Set(elements.map(\.id)).count == elements.count
        else { throw PhoneLoopProtocolError.valueOutOfRange(field: "elements") }
        guard textLines.count <= PhoneLoopWire.maxTextLines,
              textLines.allSatisfy({ $0.utf8.count <= PhoneLoopWire.maxTextBytes })
        else { throw PhoneLoopProtocolError.valueOutOfRange(field: "textLines") }
    }
}

/// When the evidence was captured, by which clock, and for how long the runner vouches for it.
///
/// The runner's monotonic clock and the controller's are different clocks on different devices,
/// so they are never subtracted from each other. The session bounds the age of an observation
/// with its own clock (an answer cannot have been captured before its command was issued) and
/// uses `capturedUptimeSeconds` only to check that captures from one `clockID` move forward.
/// The wall-clock time is recorded for people and for joining to recordings; no decision uses it.
public struct PhoneEvidenceFreshness: Codable, Sendable, Equatable {
    /// Names the runner's monotonic clock: one device, one boot.
    public let clockID: String
    public let capturedUptimeSeconds: Double
    /// Wall-clock capture time as seconds since 1970, kept as a number so it survives the wire exactly.
    public let capturedAtUnixSeconds: Double
    public let validForSeconds: TimeInterval
    public init(clockID: String, capturedUptimeSeconds: Double, capturedAtWallClock: Date, validForSeconds: TimeInterval) {
        self.clockID = clockID; self.capturedUptimeSeconds = capturedUptimeSeconds
        capturedAtUnixSeconds = capturedAtWallClock.timeIntervalSince1970; self.validForSeconds = validForSeconds
    }
    public var capturedAtWallClock: Date { Date(timeIntervalSince1970: capturedAtUnixSeconds) }

    func validate() throws {
        guard PhoneLoopWire.isIdentifier(clockID) else { throw PhoneLoopProtocolError.valueOutOfRange(field: "clockID") }
        guard capturedUptimeSeconds.isFinite, capturedUptimeSeconds >= 0
        else { throw PhoneLoopProtocolError.valueOutOfRange(field: "capturedUptimeSeconds") }
        guard capturedAtUnixSeconds.isFinite
        else { throw PhoneLoopProtocolError.valueOutOfRange(field: "capturedAtUnixSeconds") }
        guard validForSeconds.isFinite, validForSeconds > 0, validForSeconds <= PhoneLoopWire.maxValiditySeconds
        else { throw PhoneLoopProtocolError.valueOutOfRange(field: "validForSeconds") }
    }
}

/// Which element an action is aimed at: the identifier it had in the observation the action was
/// derived from, plus the role and label that identifier had there. All three must agree with
/// that observation, and the runner looks the element up again by role and label before acting.
public struct PhoneElementTarget: Codable, Sendable, Equatable {
    public let elementID: String
    public let role: PhoneElementRole
    public let label: String
    public init(elementID: String, role: PhoneElementRole, label: String) {
        self.elementID = elementID; self.role = role; self.label = label
    }
    /// A list may have no label; a tap or tab target with an empty label matches no policy entry.
    var isWellFormed: Bool { PhoneLoopWire.isIdentifier(elementID) && label.utf8.count <= PhoneLoopWire.maxTextBytes }
}

/// The actions a planner may propose. None changes data outside the phone's own navigation state.
public enum PhoneReadOnlyAction: Sendable, Equatable {
    case openApp(bundleID: String)
    case tapNavigation(PhoneElementTarget)
    case selectTab(PhoneElementTarget)
    case scrollListUp(PhoneElementTarget)

    public var kind: PhoneCommandKind {
        switch self {
        case .openApp: .openApp
        case .tapNavigation: .tapNavigation
        case .selectTab: .selectTab
        case .scrollListUp: .scrollListUp
        }
    }
}

public enum PhoneCommand: Sendable, Equatable {
    case observe
    case perform(PhoneReadOnlyAction)

    public var kind: PhoneCommandKind {
        switch self {
        case .observe: .observe
        case .perform(let action): action.kind
        }
    }
}

/// Controller → runner. Only `PhoneLoopSession` creates one (the initializer is not public);
/// the runner decodes it. `sequence` counts every command of a run from 1 and never repeats.
public struct PhoneCommandMessage: Codable, Sendable, Equatable {
    public let version: Int
    public let runID: UUID
    public let stepID: UUID
    public let sequence: Int
    /// The observation an action was validated against. Absent for `observe`, required otherwise.
    public let basedOnObservationID: UUID?
    /// How long the controller waits for the answer, so the runner can bound its own waiting.
    public let timeoutSeconds: TimeInterval
    public let command: PhoneCommand

    init(runID: UUID, stepID: UUID, sequence: Int, basedOnObservationID: UUID?,
         timeoutSeconds: TimeInterval, command: PhoneCommand) {
        version = PhoneLoopWire.version
        self.runID = runID; self.stepID = stepID; self.sequence = sequence
        self.basedOnObservationID = basedOnObservationID; self.timeoutSeconds = timeoutSeconds; self.command = command
    }

    private enum CodingKeys: String, CodingKey {
        case version, runID, stepID, sequence, basedOnObservationID, timeoutSeconds, kind, bundleID, target
    }

    public init(from decoder: Decoder) throws {
        let values = try decoder.container(keyedBy: CodingKeys.self)
        // The version is judged first: nothing else in an unknown format is interpreted.
        let version = try values.decode(Int.self, forKey: .version)
        guard version == PhoneLoopWire.version else { throw PhoneLoopProtocolError.unsupportedVersion(version) }
        let kind = try values.decode(PhoneCommandKind.self, forKey: .kind)
        let bundleID = try values.decodeIfPresent(String.self, forKey: .bundleID)
        let target = try values.decodeIfPresent(PhoneElementTarget.self, forKey: .target)
        let command: PhoneCommand
        switch (kind, bundleID, target) {
        case (.observe, nil, nil): command = .observe
        case (.openApp, let bundleID?, nil): command = .perform(.openApp(bundleID: bundleID))
        case (.tapNavigation, nil, let target?): command = .perform(.tapNavigation(target))
        case (.selectTab, nil, let target?): command = .perform(.selectTab(target))
        case (.scrollListUp, nil, let target?): command = .perform(.scrollListUp(target))
        default: throw PhoneLoopProtocolError.inconsistentCommand
        }
        self.init(runID: try values.decode(UUID.self, forKey: .runID),
                  stepID: try values.decode(UUID.self, forKey: .stepID),
                  sequence: try values.decode(Int.self, forKey: .sequence),
                  basedOnObservationID: try values.decodeIfPresent(UUID.self, forKey: .basedOnObservationID),
                  timeoutSeconds: try values.decode(Double.self, forKey: .timeoutSeconds), command: command)
        try validate()
    }

    public func encode(to encoder: Encoder) throws {
        var values = encoder.container(keyedBy: CodingKeys.self)
        try values.encode(version, forKey: .version)
        try values.encode(runID, forKey: .runID)
        try values.encode(stepID, forKey: .stepID)
        try values.encode(sequence, forKey: .sequence)
        try values.encodeIfPresent(basedOnObservationID, forKey: .basedOnObservationID)
        try values.encode(timeoutSeconds, forKey: .timeoutSeconds)
        try values.encode(command.kind, forKey: .kind)
        switch command {
        case .observe: break
        case .perform(.openApp(let bundleID)): try values.encode(bundleID, forKey: .bundleID)
        case .perform(.tapNavigation(let target)), .perform(.selectTab(let target)), .perform(.scrollListUp(let target)):
            try values.encode(target, forKey: .target)
        }
    }

    private func validate() throws {
        guard sequence >= 1 else { throw PhoneLoopProtocolError.valueOutOfRange(field: "sequence") }
        guard timeoutSeconds.isFinite, timeoutSeconds > 0, timeoutSeconds <= PhoneLoopWire.maxTimeoutSeconds
        else { throw PhoneLoopProtocolError.valueOutOfRange(field: "timeoutSeconds") }
        switch command {
        case .observe:
            guard basedOnObservationID == nil else { throw PhoneLoopProtocolError.inconsistentCommand }
        case .perform(let action):
            guard basedOnObservationID != nil else { throw PhoneLoopProtocolError.inconsistentCommand }
            switch action {
            case .openApp(let bundleID):
                guard PhoneLoopWire.isBundleID(bundleID) else { throw PhoneLoopProtocolError.valueOutOfRange(field: "bundleID") }
            case .tapNavigation(let target), .selectTab(let target), .scrollListUp(let target):
                guard target.isWellFormed else { throw PhoneLoopProtocolError.valueOutOfRange(field: "target") }
            }
        }
    }
}

/// Runner → controller: the screen captured after carrying out one command (for `observe`, just
/// the capture). It carries evidence only. It has no field saying "done": whether an action
/// worked is decided by the session from what the screen shows.
public struct PhoneObservationMessage: Codable, Sendable, Equatable {
    public let version: Int
    public let runID: UUID
    public let stepID: UUID
    /// The sequence of the command this answers.
    public let sequence: Int
    public let observationID: UUID
    public let freshness: PhoneEvidenceFreshness
    public let screen: PhoneScreenState

    public init(runID: UUID, stepID: UUID, sequence: Int, observationID: UUID = UUID(),
                freshness: PhoneEvidenceFreshness, screen: PhoneScreenState) throws {
        version = PhoneLoopWire.version
        self.runID = runID; self.stepID = stepID; self.sequence = sequence
        self.observationID = observationID; self.freshness = freshness; self.screen = screen
        try validate()
    }

    private enum CodingKeys: String, CodingKey { case version, runID, stepID, sequence, observationID, freshness, screen }

    public init(from decoder: Decoder) throws {
        let values = try decoder.container(keyedBy: CodingKeys.self)
        let version = try values.decode(Int.self, forKey: .version)
        guard version == PhoneLoopWire.version else { throw PhoneLoopProtocolError.unsupportedVersion(version) }
        try self.init(runID: try values.decode(UUID.self, forKey: .runID),
                      stepID: try values.decode(UUID.self, forKey: .stepID),
                      sequence: try values.decode(Int.self, forKey: .sequence),
                      observationID: try values.decode(UUID.self, forKey: .observationID),
                      freshness: try values.decode(PhoneEvidenceFreshness.self, forKey: .freshness),
                      screen: try values.decode(PhoneScreenState.self, forKey: .screen))
    }

    private func validate() throws {
        guard sequence >= 1 else { throw PhoneLoopProtocolError.valueOutOfRange(field: "sequence") }
        try freshness.validate()
        try screen.validate()
    }
}

/// The runner's half of ordering. A runner asks this before carrying out a command and tells it
/// about each observation it sends. A command is admitted only if it belongs to this run, its
/// sequence is higher than every sequence already admitted, and (for an action) it was derived
/// from the last observation this runner sent. So a command that is delivered twice, late, out
/// of order or after a reconnect is not carried out a second time.
public struct PhoneCommandGate: Sendable {
    public enum Refusal: Error, Equatable, Sendable { case foreignRun, replayedOrOutOfOrder, notBasedOnLatestObservation }

    public let runID: UUID
    public private(set) var lastAdmittedSequence = 0
    public private(set) var lastObservationID: UUID?
    public init(runID: UUID) { self.runID = runID }

    /// `nil` means the command may be carried out, once.
    public mutating func admit(_ command: PhoneCommandMessage) -> Refusal? {
        guard command.runID == runID else { return .foreignRun }
        guard command.sequence > lastAdmittedSequence else { return .replayedOrOutOfOrder }
        if case .perform = command.command {
            guard let lastObservationID, command.basedOnObservationID == lastObservationID
            else { return .notBasedOnLatestObservation }
            // The screen is about to change: nothing else may be derived from that observation.
            self.lastObservationID = nil
        }
        lastAdmittedSequence = command.sequence
        return nil
    }

    public mutating func sent(_ observation: PhoneObservationMessage) {
        if observation.runID == runID { lastObservationID = observation.observationID }
    }
}
