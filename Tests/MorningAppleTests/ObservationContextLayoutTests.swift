import Foundation
import MorningCore
import Testing
@testable import MorningApple

@Suite("Bounded layout hints for visible context")
struct ObservationContextLayoutTests {
    @Test("Hints reference exact Character ranges and never send omitted body geometry")
    func onlySelectedSourceLinesEnterPrompt() throws {
        let labels = ["🌅 Morning", "Cedar Mail", "Inbox", "One", "Two", "Three", "PRIVATE OMITTED BODY"]
        let source = try frame(labels)
        let input = try ObservationContextValidation.prepare(frames: [source], catalog: [])
        let excerpt = try #require(input.inputSelection.excerpts.first)
        #expect(excerpt.ocrLineIDs == Array(try #require(source.ocrLines).prefix(6).map(\.id)))
        let batch = try #require(input.batches.first)
        let object = try #require(JSONSerialization.jsonObject(with: Data(batch.prompt.utf8)) as? [String: Any])
        let frames = try #require(object["frames"] as? [[String: Any]])
        let layout = try #require(frames[0]["layout"] as? [[String: Any]])
        #expect(layout.count == 6)
        #expect(layout[0]["range"] as? [Int] == [0, labels[0].count])
        #expect(layout[1]["range"] as? [Int] == [labels[0].count + 1, labels[0].count + 1 + labels[1].count])
        #expect(Set(layout[0].keys) == ["range", "box", "confidence"])
        let box = try #require(layout[0]["box"] as? [Double])
        #expect(box.count == 4 && abs(box[0] - 0.123457) < 0.0000001)
        #expect(!batch.prompt.contains(labels.last!))
        #expect(batch.frames.first == source, "Preparing compact hints must not modify source text or exact coordinates.")
    }

    @Test("Geometry cannot exclude dense late frames or overflow any encoded prompt")
    func geometryHasAnIndependentBound() throws {
        let catalog = (0..<8).map { ObservationContextCatalogEntry(label: "Synthetic \($0)", headerText: String(repeating: "h", count: 40) + "\($0)") }
        let labels = (0..<6).map { "Line \($0) " + String(repeating: "A", count: 40) }
        let frames = try (0..<24).map { try frame(labels, at: Double($0)) }
        let input = try ObservationContextValidation.prepare(frames: frames, catalog: catalog)
        #expect(input.inputSelection.excerpts.count == 24)
        #expect(input.batches.flatMap(\.frames).map(\.id) == frames.map(\.id))
        #expect(input.batches.allSatisfy { $0.prompt.count <= ObservationContextLimits.maximumPromptCharacters })
        for excerpt in input.inputSelection.excerpts {
            let source = try #require(frames.first { $0.id == excerpt.sampleID })
            let ids = try #require(excerpt.ocrLineIDs)
            #expect(ids.count <= 6)
            #expect(ids.allSatisfy { id in source.ocrLines?.contains { $0.id == id } == true })
            #expect(excerpt.text == source.text)
        }
    }

    @Test("A larger lower heading does not grant an identity when catalog names compete")
    func positionsDoNotOverrideAmbiguity() throws {
        let source = try frame(["Cedar Mail", "Lumen Calendar", "Morning appointments"])
        let catalog = [ObservationContextCatalogEntry(label: "Cedar Mail"), .init(label: "Lumen Calendar")]
        let batch = try #require(ObservationContextValidation.prepare(frames: [source], catalog: catalog).batches.first)
        let response: [String: Any] = ["frames": [["sampleID": source.id.uuidString, "outcome": "identified",
            "contextLabel": "Lumen Calendar", "evidenceQuote": "Lumen Calendar"]]]
        let json = String(decoding: try JSONSerialization.data(withJSONObject: response), as: UTF8.self)
        let validated = ObservationContextValidation.validate(json: json, batch: batch, catalog: catalog)
        #expect(validated.decisions[0].evidence == .unknown)
        #expect(validated.diagnostics.contains { $0.kind == .unsupportedIdentity })
    }

    @Test("Visually equal normalized text cannot replace an exact source citation")
    func citationsKeepOriginalUnicodeScalars() throws {
        let original = "Caf\u{00E9}"
        let normalized = "Cafe\u{0301}"
        #expect(original == normalized)
        let source = try frame([original])
        let batch = try #require(ObservationContextValidation.prepare(frames: [source], catalog: []).batches.first)
        for quote in [original, normalized] {
            let response: [String: Any] = ["frames": [["sampleID": source.id.uuidString, "outcome": "identified",
                "contextLabel": quote, "evidenceQuote": quote]]]
            let json = String(decoding: try JSONSerialization.data(withJSONObject: response), as: UTF8.self)
            let validated = ObservationContextValidation.validate(json: json, batch: batch, catalog: [])
            if quote.utf8.elementsEqual(original.utf8) {
                #expect(validated.decisions[0].evidenceQuote?.utf8.elementsEqual(original.utf8) == true)
                #expect(validated.decisions[0].evidence != .unknown)
            } else {
                #expect(validated.decisions[0].evidence == .unknown)
                #expect(validated.diagnostics.contains { $0.kind == .invalidEvidence })
            }
        }
    }

    @Test("Old saved excerpt metadata decodes without manufacturing layout evidence")
    func legacyMetadataRemainsUnknown() throws {
        let source = try frame(["Cedar Mail"])
        let input = try ObservationContextValidation.prepare(frames: [source], catalog: [])
        let data = try JSONEncoder().encode(input.inputSelection)
        var object = try #require(JSONSerialization.jsonObject(with: data) as? [String: Any])
        var excerpts = try #require(object["excerpts"] as? [[String: Any]])
        for index in excerpts.indices { excerpts[index].removeValue(forKey: "ocrLineIDs") }
        object["excerpts"] = excerpts
        object["policyIdentifier"] = "whole-line-source-prefix-v1"
        let restored = try JSONDecoder().decode(ObservationContextInputSelection.self,
            from: JSONSerialization.data(withJSONObject: object))
        #expect(restored.excerpts.allSatisfy { $0.ocrLineIDs == nil })
        #expect(restored.excerpts.map(\.text) == input.inputSelection.excerpts.map(\.text))
    }

    private func frame(_ labels: [String], at time: Double = 0) throws -> ObservationFrameEvidence {
        var offset = 0
        let lines = try labels.enumerated().map { index, label in
            defer { offset += label.count + 1 }
            return try ObservationOCRLine(text: label, startCharacterOffset: offset, endCharacterOffset: offset + label.count,
                bounds: .init(x: 0.123456789, y: 0.9 - Double(index) * 0.1,
                              width: 0.654321987, height: index == 1 ? 0.06 : 0.02), confidence: 0.987654321)
        }
        return try .init(requestedTimeSeconds: time, actualTimeSeconds: time, outcome: .observed,
                         text: labels.joined(separator: "\n"), ocrLines: lines)
    }
}
