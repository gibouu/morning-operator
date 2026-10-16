import Foundation
import Testing
@testable import MorningApple

@Suite("Spoken passage captions")
struct SpeechCaptionProgressTests {
    @Test("Live input replaces hypotheses and keeps the latest words, including corrections")
    @MainActor func liveInputCaptions() {
        for text in ["", "Je", "Je voudrais", "Je voudrais connaître mon prochain rendez-vous.",
                     "Je voudrais connaître mes prochains rendez-vous.", "  🌅 À demain !  "] {
            #expect(SpeechCoordinator.inputCaption(text) == text.trimmingCharacters(in: .whitespacesAndNewlines))
        }
        let text = String(repeating: "Je voudrais revoir les messages de ce matin, ", count: 8)
            + "puis prépare une réponse pour demain matin."
        let caption = SpeechCoordinator.inputCaption(text)
        #expect(caption.count <= 111)
        #expect(caption.hasPrefix("…"))
        #expect(caption.hasSuffix("puis prépare une réponse pour demain matin."))
        #expect(!caption.contains("…voudrais"), "A rolling passage starts at a word boundary.")
        let emoji = String(repeating: "👨‍👩‍👧‍👦", count: 150)
        #expect(SpeechCoordinator.inputCaption(emoji) == "…" + String(emoji.suffix(110)))
    }

    @Test("Captions follow actual UTF-16 speech ranges and remain bounded")
    func followsSpokenRange() throws {
        let text = String(repeating: "🌅 À neuf heures, votre matin continue. ", count: 15)
        let chunks = try SpeechCaptionProgress.chunks(text)
        let id = UUID()
        var progress = SpeechCaptionProgress()
        progress.begin(text, requestID: id)
        #expect(progress.currentCaption == nil, "Preparing speech must not display an unspoken passage.")

        progress.advance(to: NSRange(location: 0, length: 2), requestID: id)
        #expect(progress.currentCaption == chunks[0].trimmingCharacters(in: .whitespacesAndNewlines))
        let firstRevision = progress.revision
        progress.advance(to: NSRange(location: 3, length: 1), requestID: id)
        #expect(progress.revision == firstRevision, "Word callbacks within one passage must not repeat it.")

        progress.advance(to: NSRange(location: chunks[0].utf16.count, length: 1), requestID: id)
        #expect(progress.currentCaption == chunks[1].trimmingCharacters(in: .whitespacesAndNewlines))
        #expect(progress.revision == firstRevision + 1)
        #expect((progress.currentCaption?.count ?? 0) <= 110)
        progress.advance(to: NSRange(location: 0, length: 2), requestID: id)
        #expect(progress.revision == firstRevision + 1, "Late ranges cannot scroll the reading backwards.")
    }

    @Test("Short duplex chunks preserve every spoken character without truncation")
    func shortChunksKeepTheEntireReading() throws {
        let text = String(repeating: "🌅 À neuf heures, votre matin continue.\n", count: 15)
            + String(repeating: "é", count: 170) + " Fin de la lecture."
        let chunks = try SpeechCaptionProgress.chunks(text)
        #expect(chunks.count > 2)
        #expect(chunks.allSatisfy { $0.count <= 110 && $0.utf8.count <= 800 })
        #expect(chunks.joined().utf8.elementsEqual(text.utf8))
    }

    @Test("Ordinary captions reach the final short passage at the matching duplex boundaries")
    func reachesEveryPassage() throws {
        let text = String(repeating: "Votre prochain rendez-vous est à neuf heures. ", count: 20) + "🌅 C’est fini."
        let chunks = try SpeechCaptionProgress.chunks(text)
        let id = UUID()
        var progress = SpeechCaptionProgress()
        progress.begin(text, requestID: id)
        var offset = 0
        for chunk in chunks {
            progress.advance(to: NSRange(location: offset, length: 1), requestID: id)
            #expect(progress.currentCaption == chunk.trimmingCharacters(in: .whitespacesAndNewlines))
            #expect((progress.currentCaption?.count ?? 0) <= 110)
            offset += chunk.utf16.count
        }
        #expect(progress.currentCaption?.hasSuffix("C’est fini.") == true)
        #expect(progress.revision == UInt(chunks.count))
    }

    @Test("Stop and replacement clear private captions and reject stale callbacks")
    func replacementAndReset() {
        let old = UUID(), current = UUID()
        var progress = SpeechCaptionProgress()
        progress.begin("Old reading.", requestID: old)
        progress.showChunk("Old reading.", requestID: old)
        progress.begin("New reading.", requestID: current)
        #expect(progress.currentCaption == nil)
        let replacedRevision = progress.revision
        progress.advance(to: NSRange(location: 0, length: 3), requestID: old)
        progress.showChunk("Late old audio.", requestID: old)
        #expect(progress.currentCaption == nil)
        #expect(progress.revision == replacedRevision)

        progress.showChunk("New reading.", requestID: current)
        progress.reset()
        #expect(progress.currentCaption == nil)
        let stoppedRevision = progress.revision
        progress.showChunk("Late new audio.", requestID: current)
        #expect(progress.currentCaption == nil)
        #expect(progress.revision == stoppedRevision)
    }

    @Test("Repeated spoken chunks still create distinct scroll updates")
    func repeatedChunk() {
        let id = UUID()
        var progress = SpeechCaptionProgress()
        progress.begin("Encore. Encore.", requestID: id)
        progress.showChunk("Encore.", requestID: id)
        let firstRevision = progress.revision
        progress.showChunk("Encore.", requestID: id)
        #expect(progress.currentCaption == "Encore.")
        #expect(progress.revision == firstRevision + 1)
    }

    @Test("Invalid framework ranges cannot publish a caption or overflow")
    func invalidRanges() {
        let id = UUID()
        var progress = SpeechCaptionProgress()
        progress.begin("Good morning.", requestID: id)
        for range in [NSRange(location: NSNotFound, length: 1), NSRange(location: -1, length: 1),
                      NSRange(location: 0, length: 0), NSRange(location: 12, length: Int.max),
                      NSRange(location: Int.max, length: 1)] {
            progress.advance(to: range, requestID: id)
        }
        #expect(progress.currentCaption == nil)
        #expect(progress.revision == 0)
    }
}
