import Foundation
import MorningCore
import Testing
@testable import MorningApple
#if canImport(FoundationModels)
import FoundationModels
#endif

@Suite("Native visible-context options bind evidence without guessing apps")
struct ObservationContextSelectionTests {
    private func input(_ texts: [String]) throws -> ObservationContextPreparedInput {
        try ObservationContextValidation.prepare(frames: texts.enumerated().map {
            try ObservationFrameEvidence(requestedTimeSeconds: Double($0.offset), actualTimeSeconds: Double($0.offset),
                outcome: .observed, text: $0.element)
        }, catalog: [])
    }
    private func json(_ fields: [String: Any]) throws -> String {
        String(decoding: try JSONSerialization.data(withJSONObject: fields, options: .sortedKeys), as: UTF8.self)
    }

    @Test("A selected ID resolves all fields together; unknown and ambiguity remain honest alternatives")
    func selectionsRemainSameFrameAndByteExact() throws {
        let input = try input(["Capture metadata\r\nAtelier Édition\r\nCurrent reading",
            "Boreal News\r\nGarden Calendar\r\nChoose a service"])
        let batch = try #require(input.batches.first)
        let slots = try ObservationContextFrameSlots.make(batch: batch, catalog: [])
        let header = try #require(slots[0].options.first { $0.outcome == "identified" && $0.contextLabel == "Atelier Édition" })
        let ambiguity = try #require(slots[1].options.first { $0.outcome == "ambiguous" && $0.evidenceQuote.contains("\r\n") })
        let converted = try ObservationContextFrameSlots.selectionValidationJSON(from: json([
            "f0": header.id, "f1": ambiguity.id
        ]), batch: batch, catalog: [])
        let result = ObservationContextValidation.validate(json: converted, batch: batch, catalog: [])
        #expect(result.responseWasValid && result.diagnostics.isEmpty)
        #expect(result.decisions.map(\.sampleID) == batch.frames.map(\.id))
        #expect(result.decisions[0].evidenceQuote == header.evidenceQuote)
        #expect(result.decisions[1].evidence == .ambiguous(reference: batch.frames[1].evidenceReference))
        #expect(result.decisions[1].evidenceQuote?.utf8.elementsEqual(ambiguity.evidenceQuote.utf8) == true)
        let unknown = try ObservationContextFrameSlots.selectionValidationJSON(from: json([
            "f0": "unknown", "f1": "unknown"
        ]), batch: batch, catalog: [])
        let abstained = ObservationContextValidation.validate(json: unknown, batch: batch, catalog: [])
        #expect(abstained.decisions.allSatisfy { $0.evidence == .unknown })
    }

    @Test("Clear provenance markers remain visible but cannot become an identified app", arguments: [
        "SYNTHETIC • FR", "DEMO EN", "Recording metadata", "Enregistrement vidéo français", "Capture version 2"
    ])
    func provenanceIsNotAHeader(_ marker: String) throws {
        let input = try input([marker + "\nHarbor Journal — Morning edition\nA real article headline appears here"])
        let batch = try #require(input.batches.first)
        let slot = try #require(ObservationContextFrameSlots.make(batch: batch, catalog: []).first)
        #expect(batch.excerpts[0].text.hasPrefix(marker + "\n"))
        #expect(!slot.options.contains { $0.outcome == "identified" && $0.evidenceQuote == marker })
        #expect(slot.options.contains { $0.outcome == "identified" && $0.contextLabel == "Harbor Journal — Morning edition" })
        let forged = try json(["frames": [["sampleID": batch.frames[0].id.uuidString, "outcome": "identified",
            "contextLabel": marker, "evidenceQuote": marker]]])
        let rejected = ObservationContextValidation.validate(json: forged, batch: batch, catalog: [])
        #expect(rejected.decisions[0].evidence == .unknown)
        #expect(rejected.diagnostics.contains { $0.kind == .unsupportedIdentity })
        // An optional vocabulary does not turn provenance into an app either.
        let catalog = [ObservationContextCatalogEntry(label: marker)]
        #expect(ObservationContextValidation.validate(json: forged, batch: batch, catalog: catalog).decisions[0].evidence == .unknown)
    }

    @Test("Pure provenance cannot establish ambiguity, including a forged exact quote", arguments: [
        "SYNTHETIC • FR", "Recording metadata", "No real account, send, write or like",
        "SYNTHETIC • FR\r\n \r\nNo real account, send, write or like"
    ])
    func provenanceIsNotAmbiguousContext(_ quote: String) throws {
        let source = quote + "\r\nHarbor Journal\r\nRead the garden article"
        let batch = try #require(input([source]).batches.first)
        let slot = try #require(ObservationContextFrameSlots.make(batch: batch, catalog: []).first)
        #expect(batch.frames[0].text.utf8.elementsEqual(source.utf8))
        #expect(batch.excerpts[0].text.utf8.elementsEqual(source.utf8))
        #expect(!slot.options.contains { $0.outcome == "ambiguous" && $0.evidenceQuote == quote })
        #expect(slot.options.contains { $0.outcome == "unknown" && $0.evidenceQuote.isEmpty })
        #expect(slot.options.contains { $0.outcome == "identified" && $0.contextLabel == "Harbor Journal" })
        let forged = try json(["frames": [["sampleID": batch.frames[0].id.uuidString, "outcome": "ambiguous",
            "contextLabel": "", "evidenceQuote": quote]]])
        let rejected = ObservationContextValidation.validate(json: forged, batch: batch, catalog: [])
        #expect(rejected.responseWasValid)
        #expect(rejected.decisions[0].evidence == .unknown && rejected.decisions[0].evidenceQuote == nil)
        #expect(rejected.diagnostics.contains { $0.kind == .unsupportedIdentity })
    }

    @Test("A provenance-only frame offers abstention without erasing its source")
    func provenanceOnlyFrameKeepsSource() throws {
        let source = "SYNTHETIC • FR\r\nNo real account, send, write or like"
        let batch = try #require(input([source]).batches.first)
        let slot = try #require(ObservationContextFrameSlots.make(batch: batch, catalog: []).first)
        #expect(batch.excerpts[0].text.utf8.elementsEqual(source.utf8))
        #expect(slot.options.map(\.id) == ["unknown"])
        let converted = try ObservationContextFrameSlots.selectionValidationJSON(from: json(["f0": "unknown"]), batch: batch, catalog: [])
        let abstained = ObservationContextValidation.validate(json: converted, batch: batch, catalog: [])
        #expect(abstained.responseWasValid && abstained.diagnostics.isEmpty)
        #expect(abstained.decisions[0].evidence == .unknown)
    }

    @Test("A mixed provenance and content prefix remains a byte-exact ambiguous option")
    func mixedContentRemainsAmbiguous() throws {
        let source = "SYNTHETIC • FR\r\nNo real account, send, write or like\r\nHarbor Journal\r\nRead the garden article"
        let batch = try #require(input([source]).batches.first)
        let slot = try #require(ObservationContextFrameSlots.make(batch: batch, catalog: []).first)
        let option = try #require(slot.options.first { $0.outcome == "ambiguous" && $0.evidenceQuote.utf8.elementsEqual(source.utf8) })
        let converted = try ObservationContextFrameSlots.selectionValidationJSON(from: json(["f0": option.id]), batch: batch, catalog: [])
        let result = ObservationContextValidation.validate(json: converted, batch: batch, catalog: [])
        #expect(result.responseWasValid && result.diagnostics.isEmpty)
        #expect(result.decisions[0].evidence == .ambiguous(reference: batch.frames[0].evidenceReference))
        #expect(result.decisions[0].evidenceQuote?.utf8.elementsEqual(source.utf8) == true)
    }

    @Test("A marker word inside a distinct name or full qualified header is not a blacklist", arguments: [
        "Synthetic Studio", "Test Kitchen", "Demo Reader", "Cedar News • Browser SIMULATED", "Simulation Atelier"
    ])
    func ordinaryNamesRemainProposable(_ header: String) throws {
        let batch = try #require(input([header + "\nCurrent reading"]).batches.first)
        let slot = try #require(ObservationContextFrameSlots.make(batch: batch, catalog: []).first)
        let selection = try #require(slot.options.first { $0.outcome == "identified" && $0.contextLabel == header })
        let converted = try ObservationContextFrameSlots.selectionValidationJSON(from: json(["f0": selection.id]), batch: batch, catalog: [])
        let result = ObservationContextValidation.validate(json: converted, batch: batch, catalog: [])
        #expect(result.responseWasValid && result.diagnostics.isEmpty && result.decisions[0].evidenceQuote == header)
    }

    @Test("Bad shape, keys and membership produce fixed diagnostics, never a repaired response or raw content")
    func refusalDiagnosticsAndCompatibility() throws {
        let batch = try #require(input(["Harbor Journal\nArticle preview"]).batches.first)
        for (raw, category) in [("not JSON", ObservationContextDiagnostic.SelectionFailure.shape),
            (try json(["f0": ["outcome": "identified"]]), .shape),
            (try json(["f9": "unknown"]), .keys),
            (try json(["f0": "not-supplied"]), .membership)] {
            #expect(throws: category) { try ObservationContextFrameSlots.selectionValidationJSON(from: raw, batch: batch, catalog: []) }
            let diagnostic = ObservationContextDiagnostic(kind: .invalidResponse, selectionFailure: category)
            let saved = try JSONEncoder().encode(diagnostic)
            #expect(try JSONDecoder().decode(ObservationContextDiagnostic.self, from: saved) == diagnostic)
            #expect(!String(decoding: saved, as: UTF8.self).contains("Harbor Journal"))
        }
        let legacy = try JSONDecoder().decode(ObservationContextDiagnostic.self, from: Data(#"{"kind":"invalidResponse"}"#.utf8))
        #expect(legacy.selectionFailure == nil && legacy.nativeError == nil)
    }

    #if canImport(FoundationModels)
    @Test("The actual SDK GeneratedContent envelope resolves without calling a model")
    func nativeSDKEnvelope() throws {
        let batch = try #require(input(["Harbor Journal\nCurrent reading"]).batches.first)
        let slot = try #require(ObservationContextFrameSlots.make(batch: batch, catalog: []).first)
        let header = try #require(slot.options.first { $0.outcome == "identified" && $0.contextLabel == "Harbor Journal" })
        let native = GeneratedContent(properties: ["f0": header.id])
        let converted = try ObservationContextFrameSlots.selectionValidationJSON(from: native.jsonString, batch: batch, catalog: [])
        let result = ObservationContextValidation.validate(json: converted, batch: batch, catalog: [])
        #expect(result.responseWasValid && result.diagnostics.isEmpty && result.decisions[0].evidenceQuote == "Harbor Journal")
    }
    #endif
}
