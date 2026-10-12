import Foundation

public enum MorningVoiceCommand: String, CaseIterable, Sendable, Equatable {
    case next, pause, resume, skip, repeatStep = "repeat", stop
}

public enum MorningVoiceCommandLanguage: String, CaseIterable, Sendable {
    case english, french
    public var localeIdentifier: String { self == .english ? "en-US" : "fr-FR" }
    public var exampleCommands: [String] {
        self == .english ? ["next", "pause", "resume", "skip", "repeat", "stop"]
            : ["suivant", "pause", "reprends", "passe cette étape", "répète", "arrête"]
    }
}

/// Exact command grammar, not intent inference. Negation, extra clauses and descriptive
/// instructions are not treated as permission to act merely because they contain a verb.
public enum MorningVoiceCommandParser {
    public static func parse(_ transcript: String) -> MorningVoiceCommand? {
        let normalized = transcript.folding(options: [.caseInsensitive, .diacriticInsensitive],
            locale: Locale(identifier: "en_US_POSIX"))
        let separators = CharacterSet.letters.union(.decimalDigits).inverted
        var words = normalized.components(separatedBy: separators).filter { !$0.isEmpty }
        if words.first == "more" { words.removeFirst() }
        switch words.joined(separator: " ") {
        case "next", "next step", "suivant", "etape suivante": return .next
        case "pause", "pause morning", "mets en pause": return .pause
        case "resume", "continue", "resume morning", "reprends", "reprendre", "continuer": return .resume
        case "skip", "skip step", "skip this step", "passe cette etape", "passer cette etape": return .skip
        case "again", "read again", "repeat", "repeat that", "repeat this step", "repete", "repeter", "repete cette etape": return .repeatStep
        case "stop", "stop morning", "arrete", "arreter", "arrete la routine": return .stop
        default: return nil
        }
    }
}

public struct MorningVoiceCommandContext: Sendable, Equatable {
    public let sessionID: UUID
    public let routineVersionID: UUID
    public let stepID: UUID
    public init(sessionID: UUID, routineVersionID: UUID, stepID: UUID) {
        self.sessionID = sessionID; self.routineVersionID = routineVersionID; self.stepID = stepID
    }
}

public struct MorningVoiceCommandEnvelope: Identifiable, Sendable, Equatable {
    /// One ID per explicitly started listening turn, reused for repeated delivery.
    public let id: UUID
    public let context: MorningVoiceCommandContext
    public let command: MorningVoiceCommand
    public let transcript: String
    public init(id: UUID, context: MorningVoiceCommandContext, command: MorningVoiceCommand, transcript: String) {
        self.id = id; self.context = context; self.command = command; self.transcript = transcript
    }
}

/// Exactly one whole-turn final hypothesis may be considered. This cannot identify a
/// speaker or reject acoustic replay; the caller must silence app speech before capture.
public struct MorningVoiceCommandTurn: Sendable {
    public let id: UUID
    public let context: MorningVoiceCommandContext
    public private(set) var isFinished = false

    public init(id: UUID = UUID(), context: MorningVoiceCommandContext) {
        self.id = id; self.context = context
    }

    public mutating func accept(transcript: String, isFinal: Bool,
                                alternatives: [String] = []) -> MorningVoiceCommandEnvelope? {
        guard !isFinished, isFinal else { return nil }
        isFinished = true
        guard let command = MorningVoiceCommandParser.parse(transcript),
              alternatives.allSatisfy({ MorningVoiceCommandParser.parse($0) == command }) else { return nil }
        return .init(id: id, context: context, command: command, transcript: transcript)
    }

    public mutating func cancel() { isFinished = true }
}

/// Store-owned final guard. Reset for a new run. Advanced/changed steps reject stale turns;
/// repeated delivery cannot replay pause, resume, repeat or stop either.
public struct MorningVoiceCommandDeduplicator: Sendable {
    private var consumed = Set<UUID>()
    public init() {}
    public mutating func consume(_ envelope: MorningVoiceCommandEnvelope,
                                 currentContext: MorningVoiceCommandContext) -> MorningVoiceCommand? {
        guard envelope.context == currentContext, consumed.insert(envelope.id).inserted else { return nil }
        return envelope.command
    }
    public mutating func reset() { consumed.removeAll() }
}

extension RoutineSession {
    /// Applies only session state changes, on a copy, before any caller-owned speech/effect.
    /// Next/skip can resume a paused session and advance together without dispatching the
    /// old step. The store still verifies the envelope context and deduplicates all commands.
    /// This API does not authenticate a speaker or detect acoustic replay.
    public mutating func applyVoiceCommand(command: MorningVoiceCommand, commandID: UUID,
                                          at date: Date = Date()) throws {
        // An already-applied advance must not add a resume event if redelivered while paused.
        if command == .next || command == .skip,
           events.contains(where: { $0.id == commandID && ($0.kind == .stepCompleted || $0.kind == .stepSkipped) }) {
            return
        }
        guard status == .running || status == .paused else { throw SessionError.invalidTransition }
        var updated = self
        switch command {
        case .next, .skip:
            if updated.status == .paused { try updated.resume(at: date) }
            try updated.advance(skipping: command == .skip, commandID: commandID, at: date)
        case .pause:
            if updated.status == .running { try updated.pause(at: date) }
        case .resume:
            if updated.status == .paused { try updated.resume(at: date) }
        case .stop:
            try updated.stop(at: date)
        case .repeatStep:
            guard updated.currentStep != nil else { throw SessionError.invalidTransition }
        }
        self = updated
    }
}
