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

    @Test("Only the section the app generated, in one language, is recognized and removed",
          arguments: EvidenceDetailText.savedLabels.indices)
    func generatedSectionIsAnchoredAndSingleLanguage(language: Int) {
        let label = EvidenceDetailText.savedLabels[language], note = EvidenceDetailText.savedTentativeNotes[language]
        let other = (language + 1) % EvidenceDetailText.savedLabels.count
        let otherLabel = EvidenceDetailText.savedLabels[other], otherNote = EvidenceDetailText.savedTentativeNotes[other]
        let first = "I review my calendar after breakfast.", second = "Then I water\nthe plants.”"
        let section = "\n\(note)\n\(label) “\(first)”\n\(label) “\(second)”"
        // Lines that begin with either language's label are ordinary description text.
        let description = "Review the calendar.\n\(otherLabel) shared calendar\n\(label) shared calendar\nConfirm the time."
        #expect(EvidenceDetailText.description(of: description + section, citing: [first, second]) == description)
        // Repeated quotations were written once, in first-citation order.
        #expect(EvidenceDetailText.description(of: description + section, citing: [first, second, first]) == description)
        #expect(EvidenceDetailText.description(of: section, citing: [first, second]) == "")
        // Not the generated section: missing or reordered lines, mixed languages, trailing text,
        // bare prose, or a look-alike line that only appears inside the description.
        let rejected = [
            description + "\n\(note)\n\(label) “\(first)”",
            description + "\n\(note)\n\(label) “\(second)”\n\(label) “\(first)”",
            description + "\n\(otherNote)\n\(label) “\(first)”\n\(label) “\(second)”",
            description + "\n\(note)\n\(otherLabel) “\(first)”\n\(label) “\(second)”",
            description + section + "\nA later line.",
            description + "\n\(first)\n\(second)",
            "\(otherLabel) “\(first)”\n\(otherLabel) “\(second)”\n" + description + "\n\(note)",
            description
        ]
        for detail in rejected {
            #expect(EvidenceDetailText.description(of: detail, citing: [first, second]) == nil)
        }
        #expect(EvidenceDetailText.description(of: description + section, citing: []) == nil)
    }
}
