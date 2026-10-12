import Foundation
import Testing
@testable import MorningCore

@Suite("Explicit morning voice commands")
struct MorningVoiceCommandTests {
    @Test("Exact English and French commands accept an optional MORE prefix")
    func exactGrammar() {
        let cases: [(String, MorningVoiceCommand)] = [
            ("MORE, next step.", .next), ("Suivant", .next), ("mets en pause", .pause),
            ("MORE resume", .resume), ("reprends", .resume), ("skip this step", .skip),
            ("passe cette étape", .skip), ("répète", .repeatStep), ("More repeat that", .repeatStep),
            ("Again", .repeatStep), ("MORE, read again.", .repeatStep),
            ("arrête la routine", .stop), ("stop", .stop)
        ]
        for (text, command) in cases { #expect(MorningVoiceCommandParser.parse(text) == command) }
    }

    @Test("Negated, compound, descriptive and unknown utterances do not execute")
    func rejectsExtraMeaning() {
        for text in ["", "MORE", "next and stop", "don't stop", "do not skip", "ne passe pas cette étape",
                     "the message says next", "please read the next email", "stop or pause", "more more next", "next 2", "do not read again", "again and next"] {
            #expect(MorningVoiceCommandParser.parse(text) == nil)
        }
    }

    @Test("Partials never act and the first final consumes the listening turn")
    func finalOnlyAndDuplicateDelivery() {
        var turn = MorningVoiceCommandTurn(context: context())
        #expect(turn.accept(transcript: "next", isFinal: false) == nil)
        #expect(!turn.isFinished)
        let result = turn.accept(transcript: "next", isFinal: true)
        #expect(result?.command == .next)
        #expect(result?.id == turn.id)
        #expect(turn.accept(transcript: "next", isFinal: true) == nil)
        #expect(turn.accept(transcript: "stop", isFinal: true) == nil)
    }

    @Test("Conflicting or unrecognized alternative final hypotheses abstain")
    func ambiguousFinalAbstains() {
        for alternatives in [["stop"], ["text"], ["next and stop"]] {
            var turn = MorningVoiceCommandTurn(context: context())
            #expect(turn.accept(transcript: "next", isFinal: true, alternatives: alternatives) == nil)
            #expect(turn.isFinished)
            #expect(turn.accept(transcript: "next", isFinal: true) == nil)
        }
        var equivalent = MorningVoiceCommandTurn(context: context())
        #expect(equivalent.accept(transcript: "next", isFinal: true, alternatives: ["next step"])?.command == .next)
    }

    @Test("Cancelled turns reject late finals")
    func cancellationInvalidatesResults() {
        var turn = MorningVoiceCommandTurn(context: context())
        turn.cancel()
        #expect(turn.accept(transcript: "stop", isFinal: true) == nil)
    }

    @Test("Envelope scope and consumed IDs protect every command from stale or repeated delivery")
    func contextAndDeduplication() {
        let current = context()
        var gate = MorningVoiceCommandDeduplicator()
        for command in MorningVoiceCommand.allCases {
            let result = MorningVoiceCommandEnvelope(id: UUID(), context: current, command: command, transcript: command.rawValue)
            #expect(gate.consume(result, currentContext: context()) == nil)
            #expect(gate.consume(result, currentContext: current) == command)
            #expect(gate.consume(result, currentContext: current) == nil)
        }
    }

    @Test("Next from paused resumes and advances once; replay while paused does not resume again")
    func pausedNextIsAtomicAndDeduplicated() throws {
        var session = fixtureSession()
        try session.start()
        try session.pause()
        let commandID = UUID()
        try session.applyVoiceCommand(command: .next, commandID: commandID)
        #expect(session.status == .running)
        #expect(session.currentStepIndex == 1)
        #expect(session.events.filter { $0.id == commandID }.count == 1)
        #expect(session.completedStepIDs == [session.routine.steps[0].id])
        try session.pause()
        let paused = session
        try session.applyVoiceCommand(command: .next, commandID: commandID)
        #expect(session == paused)
    }

    @Test("Skip from paused records a skipped step and terminal completion accurately")
    func pausedSkipCanComplete() throws {
        var session = fixtureSession()
        try session.start()
        try session.advance()
        try session.pause()
        let commandID = UUID()
        try session.applyVoiceCommand(command: .skip, commandID: commandID)
        #expect(session.status == .completed)
        #expect(session.skippedStepIDs == [session.routine.steps[1].id])
        #expect(session.events.contains { $0.id == commandID && $0.kind == .stepSkipped })
    }

    @Test("Pause/resume are idempotent in their own state; repeat changes no state")
    func idempotentControlsAndRepeat() throws {
        var session = fixtureSession()
        try session.start()
        let running = session
        try session.applyVoiceCommand(command: .resume, commandID: UUID())
        try session.applyVoiceCommand(command: .repeatStep, commandID: UUID())
        #expect(session == running)
        try session.applyVoiceCommand(command: .pause, commandID: UUID())
        let paused = session
        try session.applyVoiceCommand(command: .pause, commandID: UUID())
        try session.applyVoiceCommand(command: .repeatStep, commandID: UUID())
        #expect(session == paused)
        try session.applyVoiceCommand(command: .resume, commandID: UUID())
        #expect(session.status == .running)
    }

    @Test("Invalid or terminal transitions leave the session unchanged")
    func failedCommandsDoNotMutate() throws {
        for command in MorningVoiceCommand.allCases {
            var session = fixtureSession()
            let before = session
            #expect(throws: SessionError.invalidTransition) {
                try session.applyVoiceCommand(command: command, commandID: UUID())
            }
            #expect(session == before)
        }
        var stopped = fixtureSession()
        try stopped.start()
        try stopped.applyVoiceCommand(command: .stop, commandID: UUID())
        let before = stopped
        #expect(throws: SessionError.invalidTransition) {
            try stopped.applyVoiceCommand(command: .stop, commandID: UUID())
        }
        #expect(stopped == before)
    }

    private func fixtureSession() -> RoutineSession {
        RoutineSession(routine: RoutineVersion(sourceLabel: "Synthetic voice commands", steps: [
            .init(title: "First user-led step"), .init(title: "Second user-led step")
        ], isApproved: true))
    }

    private func context() -> MorningVoiceCommandContext {
        .init(sessionID: UUID(), routineVersionID: UUID(), stepID: UUID())
    }
}
