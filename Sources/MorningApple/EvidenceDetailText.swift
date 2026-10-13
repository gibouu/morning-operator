import Foundation

/// Localized fragments appended to suggested step details. Creation writes the
/// current language; validation and display read every language ever saved.
public enum EvidenceDetailText {
    public static var label: String { String(localized: "Evidence:", bundle: .module) }

    public static func line(_ quote: String) -> String { line(quote, label: label) }

    public static var tentativeNote: String {
        String(localized: "Tentative suggestion from selected evidence; duration is planned, not measured.", bundle: .module)
    }

    // A step detail is saved with the fragments of the language it was written in, and
    // is later validated and displayed under any interface language. Reading therefore
    // recognizes every fragment ever shipped, never only the current translation.
    // Append when a translation is added or reworded; never edit or remove an entry.
    // The two lists are parallel: one language writes its label and its note together.

    /// Every evidence label a saved step detail may carry.
    public static let savedLabels = ["Evidence:", "Source :"]

    /// Every tentative note a saved step detail may carry.
    public static let savedTentativeNotes = [
        "Tentative suggestion from selected evidence; duration is planned, not measured.",
        "Suggestion provisoire tirée des éléments choisis ; la durée est prévue, pas mesurée."
    ]

    /// The description of a saved detail, without the section the app generated after it:
    /// the tentative note, then one evidence line per distinct quotation in citation order,
    /// all in one language. Nil unless the detail ends with exactly that section for these
    /// quotations. A marker inside the description, in any language, is ordinary text: it
    /// neither stands in for an evidence line nor ends the description.
    public static func description(of detail: String, citing quotes: [String]) -> String? {
        guard !quotes.isEmpty else { return nil }
        var seen = Set<Data>()
        let distinct = quotes.filter { seen.insert(Data($0.utf8)).inserted }
        let bytes = Array(detail.utf8)
        for language in readableLanguages {
            let section = "\n\(language.note)\n" + distinct.map { line($0, label: language.label) }.joined(separator: "\n")
            let suffix = Array(section.utf8)
            if bytes.count >= suffix.count, bytes.suffix(suffix.count).elementsEqual(suffix) {
                return String(decoding: bytes.dropLast(suffix.count), as: UTF8.self)
            }
        }
        return nil
    }

    // The current pair is included so a reworded translation cannot reject its own new proposals.
    private static var readableLanguages: [(label: String, note: String)] {
        let saved = zip(savedLabels, savedTentativeNotes).map { (label: $0, note: $1) }
        let current = (label: label, note: tentativeNote)
        return saved.contains { $0 == current } ? saved : saved + [current]
    }

    private static func line(_ quote: String, label: String) -> String { "\(label) “\(quote)”" }

    public static var visibleContentNote: String {
        String(localized: "Visible content only; this does not prove an action or repeated habit.", bundle: .module)
    }

    public static var suggestedDurationNote: String {
        String(localized: "Suggested duration; review before approving.", bundle: .module)
    }
}
