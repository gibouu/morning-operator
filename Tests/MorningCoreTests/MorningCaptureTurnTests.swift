import Foundation
import Testing
@testable import MorningCore

@Suite("Explicit spoken capture turns")
struct MorningCaptureTurnTests {
    @Test("Only a final transcript is returned, once, with its words and punctuation intact")
    func finalOnlyAndDuplicateDelivery() throws {
        let id = UUID()
        var turn = MorningCaptureTurn(id: id)
        let partial = try turn.accept(transcript: "I dreamed", isFinal: false)
        #expect(partial == nil)
        #expect(!turn.isFinished)
        let final = try turn.accept(transcript: " \nI dreamed of the sea. Remember the blue door!\n ", isFinal: true)
        #expect(final == "I dreamed of the sea. Remember the blue door!")
        #expect(turn.id == id)
        #expect(turn.isFinished)
        let duplicate = try turn.accept(transcript: "A different thought", isFinal: true)
        #expect(duplicate == nil)
    }

    @Test("Routine commands remain ordinary text in capture mode")
    func commandWordsAreContent() throws {
        for text in ["next", "stop", "MORE, skip this step.", "Arrête la routine.",
                     "Don't stop; remind me to call Sam tomorrow."] {
            var turn = MorningCaptureTurn()
            let result = try turn.accept(transcript: text, isFinal: true)
            #expect(result == text)
        }
    }

    @Test("Cancellation rejects a late final without affecting a new turn")
    func cancellationIsScopedToItsTurn() throws {
        var cancelled = MorningCaptureTurn()
        let partial = try cancelled.accept(transcript: "Private unfinished thought", isFinal: false)
        #expect(partial == nil)
        cancelled.cancel()
        let lateFinal = try cancelled.accept(transcript: "Private unfinished thought", isFinal: true)
        #expect(lateFinal == nil)
        var replacement = MorningCaptureTurn()
        let newFinal = try replacement.accept(transcript: "A fresh thought", isFinal: true)
        #expect(newFinal == "A fresh thought")
        #expect(replacement.id != cancelled.id)
    }

    @Test("An empty final fails and cannot be replaced by a later callback")
    func emptyFinalConsumesTurn() throws {
        var turn = MorningCaptureTurn()
        #expect(throws: MorningCaptureTurnError.empty) {
            try turn.accept(transcript: " \n\t ", isFinal: true)
        }
        #expect(turn.isFinished)
        let later = try turn.accept(transcript: "Late recognition", isFinal: true)
        #expect(later == nil)
    }

    @Test("The character bound preserves Unicode and rejects rather than truncates a final")
    func boundedUnicodeFinal() throws {
        let text = String(repeating: "👨‍👩‍👧‍👦", count: MorningCaptureTurn.maximumCharacters)
        var accepted = MorningCaptureTurn()
        let final = try accepted.accept(transcript: " \n" + text + "\n ", isFinal: true)
        #expect(final == text)
        var rejected = MorningCaptureTurn()
        #expect(throws: MorningCaptureTurnError.tooLong) {
            try rejected.accept(transcript: text + "é", isFinal: true)
        }
        #expect(rejected.isFinished)
        let later = try rejected.accept(transcript: "Short replacement", isFinal: true)
        #expect(later == nil)
    }

    @Test("An oversized partial never consumes a later valid final")
    func partialDoesNotValidateOrConsume() throws {
        var turn = MorningCaptureTurn()
        let partial = try turn.accept(transcript: String(repeating: "x", count: 4_001), isFinal: false)
        #expect(partial == nil)
        #expect(!turn.isFinished)
        let final = try turn.accept(transcript: "Corrected final thought", isFinal: true)
        #expect(final == "Corrected final thought")
    }
}
