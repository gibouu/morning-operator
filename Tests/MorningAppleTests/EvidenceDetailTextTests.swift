import Foundation
import Testing
@testable import MorningApple

@Suite("Evidence fragments saved inside step details")
struct EvidenceDetailTextTests {
    /// Every value the String Catalog can produce for a source key, source language included.
    private func catalogValues(for key: String) throws -> [String] {
        let catalog = URL(fileURLWithPath: #filePath).deletingLastPathComponent()
            .appendingPathComponent("../../Sources/MorningApple/Resources/Localizable.xcstrings").standardizedFileURL
        let root = try #require(JSONSerialization.jsonObject(with: Data(contentsOf: catalog)) as? [String: Any])
        let strings = try #require(root["strings"] as? [String: Any])
        let entry = try #require(strings[key] as? [String: Any])
        let localizations = entry["localizations"] as? [String: Any] ?? [:]
        let translated = try localizations.values.map { value -> String in
            let unit = try #require((value as? [String: Any])?["stringUnit"] as? [String: Any])
            return try #require(unit["value"] as? String)
        }
        return [key] + translated
    }

    @Test("Every shipped translation of a saved fragment is recognized when read back")
    func catalogTranslationsAreAllReadable() throws {
        let labels = try catalogValues(for: "Evidence:")
        #expect(labels.count >= 2)
        #expect(labels.allSatisfy { EvidenceDetailText.savedLabels.contains($0) })
        let notes = try catalogValues(for: "Tentative suggestion from selected evidence; duration is planned, not measured.")
        #expect(notes.count >= 2)
        #expect(notes.allSatisfy { EvidenceDetailText.savedTentativeNotes.contains($0) })
        #expect(EvidenceDetailText.savedLabels.contains(EvidenceDetailText.label))
        #expect(EvidenceDetailText.savedTentativeNotes.contains(EvidenceDetailText.tentativeNote))
    }

    @Test("A retained quotation is found under either language and never by bare prose")
    func retainedQuotationIsLanguageIndependent() {
        let quote = "I review my calendar after breakfast."
        for label in EvidenceDetailText.savedLabels {
            #expect(EvidenceDetailText.detail("A summary.\n\(label) “\(quote)”", retains: quote))
            #expect(!EvidenceDetailText.detail("A summary.\n\(label) “\(quote)", retains: quote))
        }
        #expect(EvidenceDetailText.detail("A summary.\n\(EvidenceDetailText.line(quote))", retains: quote))
        #expect(!EvidenceDetailText.detail("A summary.\n\(quote)", retains: quote))
        #expect(!EvidenceDetailText.detail("A summary.\nEvidence: “I review my calendar.”", retains: quote))
    }

    @Test("The description shown in review excludes generated fragments of either language")
    func descriptionStripsFragmentsOfEitherLanguage() {
        for (label, note) in zip(EvidenceDetailText.savedLabels, EvidenceDetailText.savedTentativeNotes) {
            #expect(EvidenceDetailText.description(of: "A summary.\n\(note)\n\(label) “A quotation.”") == "A summary.")
            #expect(EvidenceDetailText.description(of: "A summary.\n\(label) “A quotation.”") == "A summary.")
        }
        #expect(EvidenceDetailText.description(of: "Only a summary.") == "Only a summary.")
    }
}
